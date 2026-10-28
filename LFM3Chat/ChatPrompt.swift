import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case system, user, assistant }

    let id = UUID()
    var role: Role
    var content: String
    var reasoning: String = ""
    var isStreaming = false
    var stats: String?
}

/// Renders a conversation the same way LFM3's Jinja chat template does for plain-text turns:
///
///     <|startoftext|><|im_start|>system\n…<|im_end|>\n
///     <|im_start|>user\n…<|im_end|>\n
///     <|im_start|>assistant\n<think></think>…<|im_end|>\n     (earlier turns: reasoning dropped)
///     <|im_start|>assistant\n<think>                           (thinking on)
///
enum ChatPrompt {
    static func render(system: String?, messages: [ChatMessage], thinking: Bool) -> String {
        var out = "<|startoftext|>"
        if let system, !system.isEmpty {
            out += "<|im_start|>system\n\(system)<|im_end|>\n"
        }
        for m in messages where m.role != .system {
            out += "<|im_start|>\(m.role.rawValue)\n"
            if m.role == .assistant { out += "<think></think>" }
            out += m.content + "<|im_end|>\n"
        }
        out += "<|im_start|>assistant\n"
        out += thinking ? "<think>" : "<think></think>"
        return out
    }

    /// Splits raw model output into (reasoning, answer). With thinking on, the prompt already
    /// opened `<think>`, so everything before `</think>` is reasoning.
    static func split(_ raw: String, thinking: Bool) -> (reasoning: String, answer: String, inThinking: Bool) {
        var text = raw
        if text.hasPrefix("<think>") { text.removeFirst("<think>".count) }
        if let close = text.range(of: "</think>") {
            return (String(text[..<close.lowerBound]).trimmed, String(text[close.upperBound...]).trimmed, false)
        }
        return thinking ? (text.trimmed, "", true) : ("", text.trimmed, false)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
