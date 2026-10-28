import SwiftUI

@main
struct LFM3ChatApp: App {
    @State private var store = ModelStore()
    @State private var chat = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(chat)
        }
    }
}

struct RootView: View {
    @Environment(ModelStore.self) private var store
    @Environment(ChatViewModel.self) private var chat

    var body: some View {
        switch store.state {
        case .ready(let url):
            ChatView()
                .task(id: url) { await chat.loadModel(at: url) }
        default:
            DownloadView()
        }
    }
}
