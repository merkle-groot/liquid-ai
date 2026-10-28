import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ChatViewModel {
    enum EngineState: Equatable { case idle, loading, ready, failed(String) }

    var messages: [ChatMessage] = []
    var input = ""
    var thinkingEnabled = true
    var systemPrompt = "You are a helpful assistant running fully on-device on an iPhone."
    private(set) var engineState: EngineState = .idle
    private(set) var isGenerating = false

    private let engine = LlamaEngine()
    private var generation: Task<Void, Never>?

    var canSend: Bool {
        engineState == .ready && !isGenerating && !input.trimmed.isEmpty
    }

    func loadModel(at url: URL) async {
        guard engineState != .ready, engineState != .loading else { return }
        engineState = .loading
        do {
            try await engine.load(path: url.path)
            engineState = .ready
        } catch {
            engineState = .failed(error.localizedDescription)
        }
    }

    func unloadModel() async {
        stop()
        await engine.unload()
        engineState = .idle
    }

    func send() {
        let text = input.trimmed
        guard canSend else { return }
        input = ""
        messages.append(ChatMessage(role: .user, content: text))
        respond()
    }

    func stop() {
        generation?.cancel()
    }

    func newChat() {
        stop()
        messages.removeAll()
    }

    private func respond() {
        let thinking = thinkingEnabled
        let history = messages
        let reply = ChatMessage(role: .assistant, content: "", isStreaming: true)
        let id = reply.id
        messages.append(reply)
        isGenerating = true
        UIApplication.shared.isIdleTimerDisabled = true

        // Looked up by id each time: "New chat" may clear `messages` mid-stream.
        func edit(_ change: (inout ChatMessage) -> Void) {
            if let i = messages.firstIndex(where: { $0.id == id }) { change(&messages[i]) }
        }

        generation = Task {
            defer {
                isGenerating = false
                edit { $0.isStreaming = false }
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                let prompt = try await fittingPrompt(history: history, thinking: thinking)
                var raw = ""
                let started = Date()
                var thoughtFor: TimeInterval?
                for try await piece in engine.generate(prompt: prompt, maxTokens: thinking ? 4096 : 2048) {
                    raw += piece
                    let parts = ChatPrompt.split(raw, thinking: thinking)
                    if thinking, !parts.inThinking, thoughtFor == nil { thoughtFor = Date().timeIntervalSince(started) }
                    edit {
                        $0.reasoning = parts.reasoning
                        $0.content = parts.answer
                    }
                }
                let stats = await engine.lastStats
                var line = String(format: "%.1f tok/s · %d tokens", stats.tokensPerSecond, stats.generatedTokens)
                if let thoughtFor { line = String(format: "Thought %.0fs · ", thoughtFor) + line }
                if Task.isCancelled { line += " · stopped" }
                edit { $0.stats = line }
            } catch {
                edit { $0.content = "⚠️ \(error.localizedDescription)" }
            }
        }
    }

    /// Drops the oldest turns until the prompt leaves room for a response.
    private func fittingPrompt(history: [ChatMessage], thinking: Bool) async throws -> String {
        let reserve = thinking ? 3072 : 1536
        var turns = history.filter { !$0.content.isEmpty }
        while true {
            let prompt = ChatPrompt.render(system: systemPrompt, messages: turns, thinking: thinking)
            let count = try await engine.tokenCount(prompt)
            if count + reserve <= Int(LlamaEngine.contextSize) || turns.count <= 1 { return prompt }
            turns.removeFirst(min(2, turns.count - 1))
        }
    }
}
