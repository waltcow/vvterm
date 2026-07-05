# Remove MLX Local ASR and Add Optional Doubao ASR

## Summary

VVTerm will remove the MLX-backed local transcription engines and add Doubao ASR as an optional remote transcription provider. The default provider remains Apple Speech. Existing users who previously selected MLX Whisper or MLX Parakeet must be migrated back to Apple Speech and persisted as `system`; they must not be moved to a cloud provider automatically.

The implementation should preserve the existing voice input entry points, overlay, keyboard shortcut, send/cancel flow, and terminal insertion behavior. Doubao is intentionally streaming and can update `partialTranscription` while recording; this is an expected provider-specific UX difference from the old MLX path, which only produced text after stop.

## Goals

- Remove MLX Whisper, MLX Parakeet, local model download UI, local model storage management UI, and `mlx-swift` package dependencies.
- Keep `System (Apple Speech)` as the default provider.
- Add `Doubao ASR` as an explicit user-selected provider in Transcription settings.
- Persist removed MLX provider selections back to `system` before any recording path can use them.
- Store the Doubao Access Token in Keychain, not in UserDefaults, and explicitly disable iCloud sync for it.
- Use the existing voice recording UI and publish Doubao partial/final transcription through the current `AudioService` state.
- Keep the first implementation focused on Doubao ASR only, not a general remote ASR platform.

## Non-Goals

- No OpenAI-compatible ASR, Aliyun ASR, GLM ASR, StepFun ASR, LLM enhancement, dictionary, hotword, or translation work.
- No automatic fallback from Doubao to Apple Speech. Apple Speech permission must only be requested for the system provider.
- No compatibility shim that keeps MLX source code compiled but hidden.
- No automatic deletion of user-downloaded MLX model files during migration.
- No arbitrary custom ASR endpoint support in the first release. Custom endpoint text is only accepted for allowlisted Doubao WebSocket URLs.
- No background streaming support. If the app cannot keep recording in foreground, the Doubao session should be cancelled and reported as interrupted.

## Protocol Sources

- Official Volcano Engine documentation: `https://www.volcengine.com/docs/6561/1354869?lang=zh`.
- Voxt reference implementation, commit `65ce20cafce214bf8ac4a4854b8b91ae748e5040`:
  - `Voxt/Core/RemoteProviders/DoubaoASRConfiguration.swift`
  - `Voxt/Transcription/RemoteASR/DoubaoStreamingSupport.swift`
  - `Voxt/Transcription/RemoteASR/RemoteASRTranscriber.swift`

The official documentation page is JavaScript-rendered in command-line fetches, so implementation review should also anchor protocol constants and packet behavior against the Voxt files above.

## Current State

`TranscriptionProvider` currently has `system`, `mlxWhisper`, and `mlxParakeet`. `TranscriptionSettingsStore.currentProvider()` maps legacy raw values `whisper` and `parakeet` back to MLX providers, and tests assert that behavior.

`AudioService` currently switches between Apple Speech and two MLX providers. For MLX, it records 16 kHz Float32 mono samples through `AudioCaptureService`, then transcribes only after recording stops. If MLX transcription fails, it currently tries an Apple Speech fallback and may request Speech Recognition permission.

`AudioCaptureService` converts microphone input to 16 kHz Float32 mono buffers with a tap buffer size of 1024 frames. Doubao requires raw 16-bit PCM mono at 16 kHz, so conversion and chunking must be explicit.

The settings screen owns MLX model managers, model pickers, download progress, deletion, storage cleanup, and legacy model ID migration. The app target links `MLX`, `MLXNN`, and `MLXFFT` products from the `mlx-swift` Swift package.

Terminal voice error handling currently appends a generic "Enable Microphone and Speech Recognition" hint for every `AudioService.RecordingError`. That is wrong for Doubao credential, endpoint, WebSocket, and network errors and must be changed.

## Migration Specification

`TranscriptionSettingsStore.currentProvider()` is the single authoritative migration trigger. It must normalize and persist removed or invalid provider raw values before returning. The voice shortcut path is safe because `AudioService.startRecording()` already reads the provider through this method.

Settings UI may call `TranscriptionSettingsStore.currentProvider()` on appear and refresh its `@AppStorage` value from UserDefaults, but it must not implement a separate settings-only migration path.

Provider raw value migration table:

| Stored raw value | Returned provider | Persisted raw value |
| --- | --- | --- |
| missing | `system` | leave missing; do not create a new key just by reading |
| `system` | `system` | `system` |
| `doubaoASR` | `doubaoASR` | `doubaoASR` |
| `whisper` | `system` | `system` |
| `parakeet` | `system` | `system` |
| `mlxWhisper` | `system` | `system` |
| `mlxParakeet` | `system` | `system` |
| any unknown or empty value | `system` | `system` |

Remove active use of these MLX model keys:

- `mlxWhisperModelId`
- `mlxParakeetModelId`
- `whisperModelId`
- `parakeetModelId`

They can be left in UserDefaults as inert historical values. They must not affect provider resolution or settings UI.

## Provider and Settings Store

`TranscriptionProvider` target cases:

- `system`
- `doubaoASR`

`TranscriptionSettingsKeys` target keys:

- `provider = "transcriptionProvider"`
- `language = "transcriptionLanguage"`
- `doubaoModelId = "doubaoASRModelId"`
- `doubaoEndpoint = "doubaoASREndpoint"`
- `doubaoAppID = "doubaoASRAppID"`

`TranscriptionSettingsDefaults` target values:

- `provider = .system`
- `language = "en"`
- `autoLanguageCode = "auto"`
- `doubaoModelId = "volc.seedasr.sauc.duration"`
- `doubaoEndpoint = ""`, meaning resolve from selected model

Remove these APIs from `TranscriptionSettingsStore`:

- `currentWhisperModelId()`
- `currentParakeetModelId()`
- `normalizedWhisperModelId(_:)`

Add these APIs or equivalent local helpers:

- `currentProvider() -> TranscriptionProvider`, including migration and persistence.
- `currentLanguageCode() -> String`.
- `currentDoubaoModelId() -> String`.
- `currentDoubaoEndpoint() -> String`.
- `currentDoubaoAppID() -> String`.
- `currentDoubaoLanguageParameter() -> String?`.

## Doubao Configuration

Recommended files:

- `Features/VoiceInput/Infrastructure/Doubao/DoubaoASRConfiguration.swift`
- `Features/VoiceInput/Infrastructure/Doubao/DoubaoStreamingProtocol.swift`
- `Features/VoiceInput/Infrastructure/Doubao/DoubaoASRProvider.swift`
- `Features/VoiceInput/Infrastructure/Doubao/DoubaoCredentialStore.swift`

Model and endpoint table:

| UI label | Model/resource ID | Default endpoint |
| --- | --- | --- |
| Doubao ASR 2.0 | `volc.seedasr.sauc.duration` | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async` |
| Doubao ASR 1.0 | `volc.bigasr.sauc.duration` | `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel` |

Required WebSocket headers:

- `X-Api-App-Key`: App ID from UserDefaults.
- `X-Api-Access-Key`: Access Token from Keychain.
- `X-Api-Resource-Id`: selected model/resource ID.
- `X-Api-Request-Id`: lowercase UUID for the session.
- `X-Api-Connect-Id`: same lowercase UUID as request ID.

Endpoint validation:

- Empty endpoint resolves from the selected model table.
- Non-empty endpoint must parse as URL.
- Scheme must be `wss`.
- Host must be exactly `openspeech.bytedance.com` for the first release.
- Path must be one of `/api/v3/sauc/bigmodel_async` or `/api/v3/sauc/bigmodel`.
- Reject `ws://`, `http://`, `https://`, other hosts, and other paths with `invalidDoubaoEndpoint`.

Request payload:

- Top-level `user.uid`: use `"vvterm"`.
- `audio.format`: `"pcm"`.
- `audio.codec`: `"raw"`.
- `audio.rate`: `16000`.
- `audio.bits`: `16`.
- `audio.channel`: `1`.
- `audio.language`: include only when `currentDoubaoLanguageParameter()` returns a value.
- `request.model_name`: `"bigmodel"`.
- `request.enable_itn`: `true`.
- `request.enable_punc`: `true`.
- `request.enable_ddc`: `true`.
- `request.show_utterances`: `true`.
- `request.enable_nonstream`: `true`.

Packet protocol:

- Version/header size: `0x1`.
- Full client request message type: `0x1`.
- Audio-only client request message type: `0x2`.
- Full server response message type: `0x9`.
- Server ack message type: `0xB`.
- Server error message type: `0xF`.
- Positive audio sequence flag: `0x1`.
- Last/negative audio packet flag: `0x3`.
- JSON serialization: `0x1`.
- No serialization for audio packets: `0x0`.
- Gzip compression is allowed for JSON and audio payloads. Keep no-compression support for empty final packets and parser robustness.

## Language Mapping

The existing language setting remains available. Apple Speech keeps its current locale handling. Doubao uses a smaller explicit mapping and falls back to server auto-detect for unsupported values instead of guessing.

| App language value | Doubao `audio.language` |
| --- | --- |
| `auto` | omit |
| `zh` | `zh-CN` |
| `en` | `en-US` |
| `ja` | `ja-JP` |
| `ko` | `ko-KR` |
| `es` | `es-MX` |
| `fr` | omit |
| `de` | omit |
| `pt` | omit |
| `ru` | omit |
| missing, empty, unknown | omit |

When Doubao is selected and the language maps to `nil`, settings should still show the selected language but the footer must state that unsupported Doubao language values use server auto-detection.

## Audio Pipeline

`AudioCaptureService` remains the shared capture component and continues outputting 16 kHz Float32 mono `AVAudioPCMBuffer` values plus recorded Float samples for metrics and fallback-free final state.

Doubao-specific conversion belongs in the Doubao adapter layer, not inside `AudioCaptureService`:

1. Extract Float32 mono samples from each `AVAudioPCMBuffer`.
2. Clamp each sample to `[-1.0, 1.0]`.
3. Convert to signed 16-bit little-endian PCM.
4. Append bytes to a pending PCM buffer.
5. Send audio packets only when pending data reaches `6400` bytes, which is 200 ms at 16 kHz, 16-bit, mono.
6. On stop, flush any trailing partial chunk before sending the final negative sequence packet.

The tap buffer is currently 1024 frames, so the provider must accumulate multiple tap buffers before sending most packets. Do not assume capture callbacks align with Doubao packet boundaries.

## Streaming State and Stop/Cancel Semantics

`AudioService` remains `@MainActor`. Doubao socket state should live in an `actor` or in a provider that serializes all WebSocket state internally. URLSession WebSocket callbacks must update `AudioService.partialTranscription`, `AudioService.transcribedText`, and recording errors through `MainActor.run` or `Task { @MainActor in ... }`.

`AudioService` creates a fresh `DoubaoASRProvider` per Doubao recording session, stores it in an `activeDoubaoProvider` property, and clears that property on stop, cancel, start failure, or runtime failure. There must be no singleton global remote ASR provider.

Start sequence for Doubao:

1. Resolve provider through `TranscriptionSettingsStore.currentProvider()`.
2. Request microphone permission only.
3. Check `NetworkMonitor.shared.isConnected`; fail fast with `networkUnavailable` if offline.
4. Validate App ID, Access Token, endpoint, and selected model before starting capture.
5. Open WebSocket, send the full request packet, then start `AudioCaptureService`.
6. Stream converted 200 ms PCM chunks as audio-only packets.
7. Update `partialTranscription` as server partials arrive.

Stop sequence for Doubao:

1. Set `isRecording = false`.
2. Stop `AudioCaptureService`.
3. Flush trailing PCM.
4. Send a final audio-only packet with negative sequence and empty payload.
5. Wait up to `2.0` seconds for a final server result.
6. Return final text if available, otherwise return the latest non-empty partial text, otherwise `""`.
7. Clear the active provider session after the wait finishes or times out.

During the 2 second final drain, the existing voice overlay should stay in processing state. The caller should not hide the overlay until `stopRecording()` returns.

Cancel sequence for Doubao:

1. Set `isRecording = false`.
2. Stop and clear `AudioCaptureService`.
3. Cancel the WebSocket without sending the final packet.
4. Clear `transcribedText` and `partialTranscription`.
5. Do not insert text into the terminal.

## Settings UI

The Transcription settings screen should become simpler:

- Terminal section remains unchanged.
- Provider picker includes:
  - `System (Apple Speech)`
  - `Doubao ASR`
- Language picker remains available for both providers.
- Remove `#if arch(arm64)` provider gating for Doubao. Cloud ASR is available on supported iOS and macOS targets.
- When Doubao is selected, show:
  - Model picker: Doubao ASR 2.0 and Doubao ASR 1.0.
  - Endpoint field with default behavior when empty.
  - App ID field.
  - Access Token secure field.
  - Privacy note that audio is sent to Doubao when this provider is selected.
  - Endpoint note that only allowlisted Doubao `wss://openspeech.bytedance.com` endpoints are accepted.

Remove MLX model sections, download progress, delete model action, storage section, and clear-all-storage UI.

## Credential Storage

Do not use `KeychainManager` for Doubao credentials. It is server UUID oriented and may use iCloud sync based on sync settings.

Add a small VoiceInput-owned credential wrapper, recommended name `DoubaoCredentialStore`, backed by:

- `KeychainStore(service: "app.vivy.vvterm")`.
- Fixed account key `voiceinput.doubaoASR.accessToken`.
- All writes must call `KeychainStore.setString(..., iCloudSync: false)`.
- Deletes must remove the same fixed account key.
- Unit tests should use an injectable in-memory storage protocol so tests do not require real SecItem access.

App ID is stored in UserDefaults under `doubaoASRAppID`. It is configuration, not the secret. Access Token is never stored in UserDefaults.

## Error Handling and Terminal UI

`AudioService.RecordingError` should remove `mlxUnavailable` and add Doubao-specific cases or equivalent typed errors:

- `networkUnavailable`
- `missingDoubaoAppID`
- `missingDoubaoAccessToken`
- `invalidDoubaoEndpoint`
- `doubaoConnectionFailed(String)`
- `doubaoServerError(String)`
- `doubaoConnectionLost`
- `doubaoFinalResultTimedOut`

Terminal voice error presentation in both `TerminalContainerView` and `TerminalView` must stop appending the Speech Recognition permission hint for every recording error.

Required UI behavior:

- Microphone permission error: show microphone recovery text.
- Apple Speech unavailable or denied: show Speech Recognition recovery text.
- Doubao credential errors: point to Transcription settings.
- Doubao endpoint errors: mention the accepted `wss://openspeech.bytedance.com` endpoint requirement.
- Doubao network/WebSocket/server errors: show the provider error without Speech Recognition instructions.

Runtime Doubao failures should stop remote capture, preserve the last partial text on screen while the error is shown, and return an empty final string if there is no usable text. They must not silently fall back to Apple Speech.

## File Deletion Inventory

Remove MLX implementation files:

- `VVTerm/Features/VoiceInput/Infrastructure/Whisper/`
- `VVTerm/Features/VoiceInput/Infrastructure/Parakeet/`
- `VVTerm/Features/VoiceInput/Infrastructure/MLXAudioSupport.swift`
- `VVTerm/Features/VoiceInput/Infrastructure/MLXModelCatalog.swift`
- `VVTerm/Features/VoiceInput/Infrastructure/MLXModelManager.swift`
- `VVTerm/Features/VoiceInput/Infrastructure/MLXModelSizeCache.swift`
- `VVTerm/Features/VoiceInput/Infrastructure/NPZLoader.swift`

Remove or replace MLX tests:

- Delete `VVTermTests/Features/VoiceInput/MLXModelCatalogTests.swift`.
- Rewrite `VVTermTests/Features/VoiceInput/TranscriptionSettingsStoreTests.swift` around system/Doubao provider resolution and MLX-to-system persistence.

Remove Xcode and package references:

- Remove `MLX`, `MLXNN`, and `MLXFFT` framework build file entries from `VVTerm.xcodeproj/project.pbxproj`.
- Remove `mlx-swift` package reference and product dependencies from the project.
- Remove `mlx-swift` from `VVTerm.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Update documentation and strings:

- Update `AGENTS.md` and `CLAUDE.md` VoiceInput descriptions so they no longer say MLX Whisper/Parakeet.
- Remove user-visible MLX settings copy from the active settings UI.
- Add localized strings for Doubao provider name, credential/endpoint/settings footers, and new recording errors. English and Simplified Chinese must be included in the implementation PR; other locales may fall back to development language if that is the current project convention.

## Privacy and Store Review

Because Doubao is remote ASR, settings must explicitly say audio is sent to Doubao when selected.

Privacy deliverables for this change:

- Inspect existing privacy manifest files and update them if the app declares audio, diagnostics, or network data practices there.
- Add an implementation checklist item for App Store privacy questionnaire review before release.
- Do not claim ASR is fully local in docs, settings, or onboarding after this change.

## Testing

Unit tests:

- Legacy values `whisper`, `parakeet`, `mlxWhisper`, and `mlxParakeet` return `system` and persist `system`.
- Unknown and empty provider raw values return `system` and persist `system`.
- `doubaoASR` persists and resolves as Doubao.
- Removed MLX model keys do not affect provider resolution.
- Doubao default model and endpoint resolution.
- Doubao endpoint validation rejects non-`wss`, non-allowlisted host, and non-allowlisted path.
- Doubao language mapping table.
- Float32 to Int16 PCM conversion, including clamp behavior.
- 1024-frame callbacks accumulate into 6400-byte packets and flush trailing partial bytes on stop.
- Doubao packet build/parse for full request, audio packet, final packet, ack, server response, and server error.
- Gzip encode/decode round trip.
- Response state handles partial, final, timeout, and socket close.
- Credential store wrapper writes the access token with `iCloudSync: false` through a fake store.

Integration-style tests:

- Introduce a small `DoubaoWebSocketClient` protocol or equivalent injectable transport so tests can exercise handshake, partial result, final result, server error, and connection-lost flows without a real network connection.
- Verify `AudioService.startRecording()` for Doubao requests microphone permission only and does not request Speech Recognition permission.
- Verify `stopRecording()` waits for final up to the configured timeout and returns latest partial on timeout.
- Verify `cancelRecording()` closes the Doubao session and clears text without terminal insertion.

Build verification:

- Xcode build after removing `mlx-swift` products.
- Existing tests after replacing MLX catalog tests with Doubao configuration/protocol tests.

Manual smoke tests:

- System provider still records and sends text to terminal.
- Doubao provider with missing credentials shows a clear settings-directed error.
- Doubao provider with invalid endpoint shows the allowlist requirement.
- Doubao provider with valid credentials streams partial text and sends final text to terminal.
- Doubao cancel closes capture and socket without inserting text.
- iOS and macOS settings show Doubao without MLX model/storage UI.

## Acceptance Criteria

- No `import MLX`, `import MLXNN`, or `import MLXFFT` remains.
- `mlx-swift` is removed from the Xcode project package references and `Package.resolved`.
- `TranscriptionProvider` has only `system` and `doubaoASR`.
- Removed MLX provider values are persisted to `system` before recording starts.
- Voice input works with Apple Speech as before.
- Doubao ASR is visible but not selected by default.
- Doubao requests microphone permission only and never requests Speech Recognition permission.
- Selecting Doubao without credentials fails with actionable UI text.
- Selecting Doubao with an invalid endpoint fails with endpoint-specific UI text.
- Selecting Doubao with valid credentials transcribes partial and final text through the existing send flow.
- Terminal error UI no longer shows Speech Recognition instructions for Doubao credential, endpoint, network, or server errors.
- AGENTS.md and CLAUDE.md no longer describe VoiceInput as MLX-backed.
- The implementation PR includes privacy manifest/App Store privacy review notes.
