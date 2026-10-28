import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var chat
    @Environment(ModelStore.self) private var store
    @FocusState private var inputFocused: Bool
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if chat.messages.isEmpty { emptyState }
                        ForEach(chat.messages) { MessageRow(message: $0).id($0.id) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.last?.content) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.messages.last?.reasoning) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: chat.messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("LFM3 Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { chat.newChat() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(chat.messages.isEmpty)
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            switch chat.engineState {
            case .loading, .idle:
                ProgressView()
                Text("Loading model…").foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            case .ready:
                Image(systemName: "drop.fill").font(.largeTitle).foregroundStyle(.tint)
                Text("LFM3-1.7B is ready").font(.headline)
                Text("Running on-device with llama.cpp + Metal").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var inputBar: some View {
        @Bindable var chat = chat
        return HStack(alignment: .bottom, spacing: 8) {
            Button {
                chat.thinkingEnabled.toggle()
            } label: {
                Image(systemName: chat.thinkingEnabled ? "brain.fill" : "brain")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(chat.thinkingEnabled ? "Thinking on" : "Thinking off")

            TextField("Message", text: $chat.input, axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                .onSubmit { chat.send() }

            if chat.isGenerating {
                Button { chat.stop() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 32))
                }
            } else {
                Button { chat.send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .disabled(!chat.canSend)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct MessageRow: View {
    let message: ChatMessage
    @State private var showReasoning = false

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: .rect(cornerRadius: 18))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !message.reasoning.isEmpty {
                    DisclosureGroup(isExpanded: $showReasoning) {
                        Text(message.reasoning)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    } label: {
                        Label(message.isStreaming && message.content.isEmpty ? "Thinking…" : "Reasoning",
                              systemImage: "brain")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if !message.content.isEmpty {
                    Text(markdown(message.content))
                        .textSelection(.enabled)
                } else if message.isStreaming && message.reasoning.isEmpty {
                    ProgressView().controlSize(.small)
                }
                if let stats = message.stats {
                    Text(stats).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
    }
}

struct SettingsView: View {
    @Environment(ChatViewModel.self) private var chat
    @Environment(ModelStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var chat = chat
        NavigationStack {
            Form {
                Section("System prompt") {
                    TextField("System prompt", text: $chat.systemPrompt, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("Thinking (reasoning)", isOn: $chat.thinkingEnabled)
                } footer: {
                    Text("LFM3 reasons before answering by default. Turn off for faster, shorter replies.")
                }
                Section("Model") {
                    LabeledContent("Model", value: "LFM3-1.7B")
                    LabeledContent("Quantization", value: "Q4_0 (QAD)")
                    LabeledContent("Context", value: "\(LlamaEngine.contextSize) tokens")
                    LabeledContent("Runtime", value: "llama.cpp · Metal")
                    Button("Delete Downloaded Model", role: .destructive) {
                        Task {
                            await chat.unloadModel()
                            chat.newChat()
                            store.deleteModel()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
