import SwiftUI

struct DownloadView: View {
    @Environment(ModelStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "drop.fill")
                .font(.system(size: 64))
                .foregroundStyle(.linearGradient(colors: [.cyan, .indigo], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 8) {
                Text("LFM3 Chat").font(.largeTitle.bold())
                Text("Chat with Liquid AI's LFM3-1.7B entirely on your device. No servers, works offline once downloaded.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            content
            Text("Model: \(ModelStore.fileName) · LFM Open License v1.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .downloading(let progress, let received, let total):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                Text("\(bytes(received)) of \(bytes(total))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel) { store.cancelDownload() }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                downloadButton(title: "Retry Download")
            }
        default:
            downloadButton(title: "Download Model (\(bytes(ModelStore.approxBytes)))")
        }
    }

    private func downloadButton(title: String) -> some View {
        Button { store.startDownload() } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
