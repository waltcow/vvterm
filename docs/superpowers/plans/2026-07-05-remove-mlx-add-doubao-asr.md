# Remove MLX and Add Doubao ASR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove MLX local ASR from VVTerm and add Doubao ASR as an optional remote transcription provider while keeping Apple Speech as the default.

**Architecture:** VoiceInput keeps ownership of provider selection, audio capture, settings, and ASR adapters. Doubao is implemented as a per-recording provider with focused configuration, protocol, credential, and transport types under `Features/VoiceInput/Infrastructure/Doubao/`. Existing terminal voice entry points continue to call `AudioService`.

**Tech Stack:** Swift, SwiftUI, Combine, AVFoundation, URLSessionWebSocketTask, Security Keychain, XCTest, Xcode project.

---

## File Map

- Modify `VVTerm/Features/VoiceInput/Infrastructure/TranscriptionProvider.swift`: provider enum, settings keys/defaults, migration and Doubao settings helpers.
- Create `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoASRConfiguration.swift`: model IDs, endpoint validation, language mapping, PCM conversion, chunk sizing.
- Create `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoStreamingProtocol.swift`: packet constants, build/parse, gzip helpers, response state.
- Create `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoCredentialStore.swift`: fixed Keychain-backed access token storage with injectable test storage.
- Create `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoASRProvider.swift`: per-session WebSocket lifecycle, stream/stop/cancel API.
- Modify `VVTerm/Features/VoiceInput/Infrastructure/AudioService.swift`: remove MLX branches, add Doubao start/stop/cancel.
- Modify `VVTerm/Features/VoiceInput/UI/Settings/TranscriptionSettingsView.swift`: remove MLX model UI, add Doubao settings.
- Modify `VVTerm/Features/TerminalSessions/UI/Terminal/TerminalContainerView.swift` and `VVTerm/Features/TerminalSessions/UI/Splits/TerminalView.swift`: provider-specific voice error presentation.
- Delete MLX infrastructure files and `VVTermTests/Features/VoiceInput/MLXModelCatalogTests.swift`.
- Modify `VVTermTests/Features/VoiceInput/TranscriptionSettingsStoreTests.swift`: migration and settings helper tests.
- Add Doubao tests under `VVTermTests/Features/VoiceInput/`.
- Modify `VVTerm.xcodeproj/project.pbxproj` and `Package.resolved`: remove `mlx-swift`, `MLX`, `MLXNN`, `MLXFFT`.
- Modify `AGENTS.md`, `CLAUDE.md`, `VVTerm/Resources/en.lproj/Localizable.strings`, `VVTerm/Resources/zh-Hans.lproj/Localizable.strings`, and privacy notes if needed.

## Commands

- VoiceInput tests:
  `xcodebuild test -project VVTerm.xcodeproj -scheme VVTerm -destination 'platform=macOS' -only-testing:VVTermTests/TranscriptionSettingsStoreTests -only-testing:VVTermTests/DoubaoASRConfigurationTests -only-testing:VVTermTests/DoubaoStreamingProtocolTests -only-testing:VVTermTests/DoubaoCredentialStoreTests`
- Build:
  `xcodebuild build -project VVTerm.xcodeproj -scheme VVTerm -destination 'platform=macOS'`
- MLX cleanup check:
  `rg -n 'import MLX|import MLXNN|import MLXFFT|mlx-swift|MLX Whisper|MLX Parakeet|mlxWhisper|mlxParakeet' VVTerm VVTermTests VVTerm.xcodeproj AGENTS.md CLAUDE.md`

## Task 1: Settings Migration Tests

**Files:**
- Modify: `VVTermTests/Features/VoiceInput/TranscriptionSettingsStoreTests.swift`
- Modify: `VVTerm/Features/VoiceInput/Infrastructure/TranscriptionProvider.swift`

- [ ] Replace legacy MLX expectations with tests proving `whisper`, `parakeet`, `mlxWhisper`, and `mlxParakeet` return `.system` and persist `"system"`.
- [ ] Add tests that `doubaoASR` resolves as `.doubaoASR`.
- [ ] Add tests that unknown and empty raw values return `.system` and persist `"system"`.
- [ ] Run the targeted test and verify it fails because `.doubaoASR` and migration behavior are not implemented.
- [ ] Implement provider enum, keys, defaults, migration, and Doubao settings helpers.
- [ ] Run the targeted test and verify it passes.

## Task 2: Doubao Configuration Tests

**Files:**
- Create: `VVTermTests/Features/VoiceInput/DoubaoASRConfigurationTests.swift`
- Create: `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoASRConfiguration.swift`

- [ ] Add tests for default model endpoint resolution.
- [ ] Add tests rejecting non-`wss`, non-allowlisted hosts, and invalid paths.
- [ ] Add tests for language mapping values from the spec.
- [ ] Add tests for Float32 to little-endian Int16 PCM conversion and 6400-byte chunk popping.
- [ ] Run the tests and verify failure because the type is missing.
- [ ] Implement configuration, endpoint validation, language mapping, PCM conversion, and chunk helpers.
- [ ] Run the tests and verify they pass.

## Task 3: Doubao Protocol Tests

**Files:**
- Create: `VVTermTests/Features/VoiceInput/DoubaoStreamingProtocolTests.swift`
- Create: `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoStreamingProtocol.swift`

- [ ] Add tests for full request, audio packet, and final negative packet headers.
- [ ] Add tests for gzip round trip.
- [ ] Add tests for parsing server text and server error packets.
- [ ] Add tests for response state final timeout behavior.
- [ ] Run tests and verify failure because protocol helpers are missing.
- [ ] Implement packet build/parse, gzip helpers, text extraction, and response state.
- [ ] Run tests and verify they pass.

## Task 4: Credential Store Tests

**Files:**
- Create: `VVTermTests/Features/VoiceInput/DoubaoCredentialStoreTests.swift`
- Create: `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoCredentialStore.swift`

- [ ] Add a fake keychain store test that token writes use key `voiceinput.doubaoASR.accessToken` and `iCloudSync == false`.
- [ ] Add get/delete tests.
- [ ] Run tests and verify failure because the store is missing.
- [ ] Implement the protocol-backed credential store and real `KeychainStore` adapter.
- [ ] Run tests and verify they pass.

## Task 5: Doubao Provider and AudioService

**Files:**
- Create: `VVTerm/Features/VoiceInput/Infrastructure/Doubao/DoubaoASRProvider.swift`
- Modify: `VVTerm/Features/VoiceInput/Infrastructure/AudioService.swift`
- Test: extend Doubao tests with fake transport where practical.

- [ ] Add injectable WebSocket client types so provider behavior can be tested without network.
- [ ] Test that stop sends trailing audio, final packet, waits up to 2 seconds, and returns latest partial on timeout.
- [ ] Test that cancel closes the session without final packet.
- [ ] Implement `DoubaoASRProvider` with per-recording lifecycle.
- [ ] Remove MLX providers, MLX fallback, and `mlxUnavailable`.
- [ ] Add Doubao-specific `RecordingError` cases and microphone-only permission path.
- [ ] Wire `NetworkMonitor.shared.isConnected` fail-fast for Doubao.
- [ ] Run VoiceInput tests.

## Task 6: Settings UI and Terminal Errors

**Files:**
- Modify: `VVTerm/Features/VoiceInput/UI/Settings/TranscriptionSettingsView.swift`
- Modify: `VVTerm/Features/TerminalSessions/UI/Terminal/TerminalContainerView.swift`
- Modify: `VVTerm/Features/TerminalSessions/UI/Splits/TerminalView.swift`
- Modify: `VVTerm/Resources/en.lproj/Localizable.strings`
- Modify: `VVTerm/Resources/zh-Hans.lproj/Localizable.strings`

- [ ] Replace MLX model/download/storage UI with system/Doubao provider, language, model, endpoint, app ID, token, and privacy fields.
- [ ] Make token field read/write through `DoubaoCredentialStore`.
- [ ] Add provider-specific terminal error message helper so Doubao errors do not append Speech Recognition instructions.
- [ ] Add English and Simplified Chinese strings for new UI/error text.
- [ ] Build to catch SwiftUI binding and localization issues.

## Task 7: Delete MLX and Project References

**Files:**
- Delete MLX source files listed in the spec.
- Delete `VVTermTests/Features/VoiceInput/MLXModelCatalogTests.swift`.
- Modify `VVTerm.xcodeproj/project.pbxproj`.
- Modify `VVTerm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Modify `AGENTS.md` and `CLAUDE.md`.

- [ ] Delete MLX implementation and test files.
- [ ] Remove MLX build products, package reference, and resolved package pin.
- [ ] Update architecture docs so VoiceInput no longer claims MLX model management.
- [ ] Run the MLX cleanup `rg` command and verify only historical spec/plan references remain.
- [ ] Run build.

## Task 8: Final Verification

- [ ] Run VoiceInput targeted tests.
- [ ] Run full macOS build.
- [ ] Inspect `VVTerm/PrivacyInfo.xcprivacy`; update only if current manifest must declare new collected data for this app-owned remote ASR flow.
- [ ] Run `git diff --check`.
- [ ] Summarize tests, build result, privacy note, and any remaining manual smoke tests requiring real Doubao credentials.
