import Foundation
import llama

enum LlamaError: LocalizedError {
    case modelLoadFailed
    case contextInitFailed
    case tokenizeFailed
    case decodeFailed(Int32)
    case promptTooLong(Int)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: "Could not load the model file. Try deleting and re-downloading it."
        case .contextInitFailed: "Could not create an inference context (out of memory?)."
        case .tokenizeFailed: "Could not tokenize the prompt."
        case .decodeFailed(let code): "Inference failed (llama_decode returned \(code))."
        case .promptTooLong(let n): "The conversation is too long (\(n) tokens). Start a new chat."
        }
    }
}

struct GenerationStats: Sendable {
    var promptTokens = 0
    var generatedTokens = 0
    var tokensPerSecond = 0.0
}

/// Owns the llama.cpp model/context. All llama calls are serialized on this actor.
actor LlamaEngine {
    static let contextSize: Int32 = 8192
    static let batchSize: Int32 = 512

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?

    var isLoaded: Bool { context != nil }

    func load(path: String) throws {
        guard context == nil else { return }
        llama_backend_init()

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 99  // offload everything to Metal
        guard let m = llama_model_load_from_file(path, mparams) else { throw LlamaError.modelLoadFailed }

        let threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(Self.contextSize)
        cparams.n_batch = UInt32(Self.batchSize)
        cparams.n_ubatch = UInt32(Self.batchSize)
        cparams.n_threads = threads
        cparams.n_threads_batch = threads
        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            throw LlamaError.contextInitFailed
        }

        let v = llama_model_get_vocab(m)
        // Recommended LFM3 sampling: repetition_penalty 1.1, top_k 50, temperature 0.1
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        // top_k first: the penalty sampler is slow over the full 128k vocabulary
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(50))
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(v), 64, 1.1, 0, 0))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.1))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        model = m
        context = c
        vocab = v
        sampler = chain
    }

    func unload() {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        sampler = nil; context = nil; vocab = nil; model = nil
    }

    func tokenCount(_ text: String) throws -> Int {
        try tokenize(text).count
    }

    /// Streams decoded text pieces for `prompt`. Cancelling the consuming task stops generation.
    nonisolated func generate(prompt: String, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stats = try await self.run(prompt: prompt, maxTokens: maxTokens) { piece in
                        continuation.yield(piece)
                    }
                    await self.setLastStats(stats)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private(set) var lastStats = GenerationStats()
    private func setLastStats(_ s: GenerationStats) { lastStats = s }

    // MARK: - Internals

    private func run(prompt: String, maxTokens: Int, emit: @Sendable (String) -> Void) throws -> GenerationStats {
        guard let context, let vocab, let sampler else { throw LlamaError.contextInitFailed }

        // Stateless turns: the whole conversation is re-encoded each time (prefill is fast for 1.7B).
        llama_memory_clear(llama_get_memory(context), true)
        llama_sampler_reset(sampler)

        var tokens = try tokenize(prompt)
        let budget = Int(Self.contextSize) - tokens.count
        guard budget > 16 else { throw LlamaError.promptTooLong(tokens.count) }
        let limit = min(maxTokens, budget)

        // Prefill in batch-sized chunks
        var offset = 0
        while offset < tokens.count {
            let n = min(Int(Self.batchSize), tokens.count - offset)
            let rc = tokens.withUnsafeMutableBufferPointer { buf in
                llama_decode(context, llama_batch_get_one(buf.baseAddress! + offset, Int32(n)))
            }
            guard rc == 0 else { throw LlamaError.decodeFailed(rc) }
            offset += n
        }

        let start = Date()
        var generated = 0
        var pending: [UInt8] = []
        var pieceBuf = [CChar](repeating: 0, count: 256)

        while generated < limit, !Task.isCancelled {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            generated += 1

            let n = llama_token_to_piece(vocab, token, &pieceBuf, Int32(pieceBuf.count), 0, true)
            if n > 0 {
                pending += pieceBuf[0..<Int(n)].map { UInt8(bitPattern: $0) }
                // Tokens can split multi-byte UTF-8 characters; only emit complete text.
                if let s = String(bytes: pending, encoding: .utf8) {
                    emit(s)
                    pending.removeAll()
                } else if pending.count > 16 {
                    emit(String(decoding: pending, as: UTF8.self))
                    pending.removeAll()
                }
            }

            let rc = llama_decode(context, llama_batch_get_one(&token, 1))
            guard rc == 0 else { throw LlamaError.decodeFailed(rc) }
        }
        if !pending.isEmpty { emit(String(decoding: pending, as: UTF8.self)) }

        let elapsed = Date().timeIntervalSince(start)
        return GenerationStats(
            promptTokens: tokens.count,
            generatedTokens: generated,
            tokensPerSecond: elapsed > 0 ? Double(generated) / elapsed : 0
        )
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocab else { throw LlamaError.contextInitFailed }
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 8)
        // BOS is written explicitly by the prompt formatter, so add_special = false.
        var n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        }
        guard n >= 0 else { throw LlamaError.tokenizeFailed }
        return Array(tokens.prefix(Int(n)))
    }
}
