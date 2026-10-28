# LFM3 Chat (iOS)

On-device chat with Liquid AI's **LFM3-1.7B** (released 2026-10-27), running locally via
llama.cpp + Metal. No server: the app downloads the 1.05 GB `LFM3-1.7B-QAD-Q4_0.gguf` from
Hugging Face on first launch, then works offline.

- Streaming responses, with LFM3's reasoning shown in a collapsible "Reasoning" section
- Thinking on/off toggle (brain button), editable system prompt, stop and new chat
- 8K context window; the oldest turns are dropped when the window fills
- Sampling follows the model card: temp 0.1, top_k 50, repetition penalty 1.1
- Requires iOS 17+, built for iPhone and iPad (arm64 devices only, no simulator slice)

## Build

```sh
brew install xcodegen
scripts/fetch-llama.sh        # llama.cpp xcframework b11946 (LFM3 support landed in b11935)
xcodegen generate
open LFM3Chat.xcodeproj
```

## Ship to TestFlight

1. Enroll in the paid Apple Developer Program (https://developer.apple.com/programs/enroll/).
   A free Personal Team can't create distribution certificates.
2. In Xcode → Settings → Accounts, make sure the enrolled team is signed in, and set
   `DEVELOPMENT_TEAM` in `project.yml` if the team ID changes.
3. In App Store Connect → Apps → "+" → New App, choose platform iOS and bundle ID
   `com.vishnuprakash.lfm3chat` (the ID is already registered), and enter any SKU.
4. Run `scripts/testflight.sh`.
5. In App Store Connect → TestFlight, add yourself as an internal tester and install the
   build with the TestFlight app on your iPhone.

`ITSAppUsesNonExemptEncryption` is set to `NO`, so TestFlight skips the export-compliance
prompt. External testers need a Beta App Review; internal testers don't.

## Layout

| File | Purpose |
|---|---|
| `LFM3Chat/LlamaEngine.swift` | actor wrapping the llama.cpp C API (load, prefill, sample, stream) |
| `LFM3Chat/ChatPrompt.swift` | LFM3 chat-template rendering and `<think>` splitting |
| `LFM3Chat/ModelStore.swift` | resumable GGUF download into Application Support (excluded from backup) |
| `LFM3Chat/ChatViewModel.swift` | conversation state, context trimming, generation task |
| `LFM3Chat/*View.swift` | SwiftUI UI |
