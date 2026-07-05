# Remove MLX Local ASR and Add Optional Doubao ASR

## Summary

VVTerm will remove the MLX-backed local transcription engines and add Doubao ASR as an optional remote transcription provider. The default provider remains Apple Speech. Existing users who previously selected MLX Whisper or MLX Parakeet will be migrated back to Apple Speech instead of being moved to a cloud provider automatically.

The implementation should preserve the existing voice input entry points, overlay, keyboard shortcut, send/cancel flow, and terminal insertion behavior.

## Goals

- Remove MLX Whisper, MLX Parakeet, local model download, model storage, and `mlx-swift` package dependencies.
- Keep `System (Apple Speech)` as the default provider.
- Add `Doubao ASR` as an explicit user-selected provider in Transcription settings.
- Store Doubao sensitive credentials outside plain UserDefaults.
- Use the existing voice recording UI and publish partial/final transcription through the current `AudioService` state.
- Keep the first implementation focused on Doubao ASR only, not a general remote ASR platform.

## Non-Goals

- No OpenAI-compatible ASR, Aliyun ASR, GLM ASR, StepFun ASR, or LLM enhancement work.
- No redesign of the voice overlay or terminal UI.
- No dictionary, hotword management, translation, or post-processing workflow.
- No compatibility shim that keeps MLX source code compiled but hidden.

## Current State

`AudioService` currently switches between Apple Speech and two MLX providers. For MLX, it records raw samples through `AudioCaptureService`, then transcribes after recording stops. The settings screen also owns MLX model managers, model pickers, download progress, deletion, and storage cleanup.

The app target links `MLX`, `MLXNN`, and `MLXFFT` products from the `mlx-swift` Swift package. Tests cover MLX model catalog behavior and legacy MLX settings migration.

## Target Architecture

`Features/VoiceInput` remains the owner of transcription provider selection, audio capture, and provider adapters.

Recommended shape:

- `Infrastructure/TranscriptionProvider.swift`
  - Providers: `system`, `doubaoASR`.
  - Defaults: provider remains `system`.
  - Legacy raw values `whisper`, `parakeet`, `mlxWhisper`, and `mlxParakeet` resolve to `system`.
  - Add Doubao settings keys for model, endpoint, app ID reference, and access token reference.

- `Infrastructure/Doubao/DoubaoASRConfiguration.swift`
  - Model IDs: `volc.seedasr.sauc.duration` as default, plus `volc.bigasr.sauc.duration`.
  - Endpoints: default streaming endpoints for current and legacy models.
  - Audio format: 16 kHz, 16-bit, mono PCM, chunked at roughly 200 ms per packet.
  - Request payload builder with punctuation, ITN, DDC, and nonstream result enabled.

- `Infrastructure/Doubao/DoubaoStreamingProtocol.swift`
  - Binary protocol constants.
  - Packet build/parse helpers.
  - Gzip encode/decode helpers.
  - Response state for partial/final text and socket closure.

- `Infrastructure/Doubao/DoubaoASRProvider.swift`
  - Owns WebSocket lifecycle.
  - Connects with `X-Api-App-Key`, `X-Api-Access-Key`, `X-Api-Resource-Id`, `X-Api-Request-Id`, and `X-Api-Connect-Id`.
  - Starts session with a full request packet.
  - Accepts 16 kHz float samples or PCM buffers from `AudioService`.
  - Publishes partial transcription updates to the caller.
  - Sends a final negative sequence packet on stop and waits briefly for final text.

- `Infrastructure/AudioService.swift`
  - Keeps Apple Speech path intact.
  - For Doubao, requests microphone permission only.
  - Captures audio and streams chunks to `DoubaoASRProvider`.
  - Updates `partialTranscription` on remote partials and `transcribedText` on final.
  - Cancels the WebSocket and capture cleanly on cancel.

## Settings

The Transcription settings screen should become simpler:

- Terminal section remains unchanged.
- Provider picker includes:
  - `System (Apple Speech)`
  - `Doubao ASR`
- Language picker stays available for system and Doubao, with `auto` supported where applicable.
- When Doubao is selected, show:
  - Model picker: Doubao ASR 2.0 and Doubao ASR 1.0.
  - Endpoint field with default behavior when empty.
  - App ID field.
  - Access Token secure field.
  - Short privacy note that audio is sent to Doubao when this provider is selected.

Remove MLX model sections, download progress, delete model action, and storage cleanup UI.

## Credential Storage

Access Token must not be stored as plain UserDefaults. Prefer `KeychainManager` or a small VoiceInput-owned keychain helper in `Core/Security` if the existing manager is server-credential-specific.

App ID is less sensitive but can be stored alongside the token for consistency. The UI may keep only non-sensitive configuration such as provider, model, endpoint, and language in UserDefaults.

## Migration

On app launch or Transcription settings appearance:

- If `transcriptionProvider` is an MLX value, set it to `system`.
- Leave old MLX model keys untouched or remove them from active use. They should not influence provider resolution.
- Do not delete user-downloaded model files automatically. Removing local model storage can be a separate cleanup action if needed later.

This avoids silently moving users from local/offline transcription to cloud transcription.

## Error Handling

Doubao startup errors should surface as recording errors:

- Missing App ID.
- Missing Access Token.
- Invalid endpoint URL.
- WebSocket handshake failure.
- Server error packet.
- Network unavailable or connection lost.

Runtime failures should stop remote capture, keep any last partial text visible, and return an empty final string if no usable text exists. Apple Speech fallback should not request Speech permission unless the user is using Apple Speech or fallback behavior is explicitly added later.

## Privacy

Because Doubao is remote ASR, the settings description must be explicit that audio is sent to Doubao when selected. The privacy manifest/App Store privacy answers should be checked before release because removing MLX changes the feature from local inference to optional remote processing.

## Testing

Unit tests:

- Legacy MLX provider values resolve to `system`.
- Doubao default model and endpoint resolution.
- Doubao packet build/parse for full request, audio packet, and final packet.
- Gzip round-trip for packet payloads.
- Response state handles partial, final, timeout, and socket close.

Build verification:

- Xcode build after removing `mlx-swift` products.
- Existing tests after replacing MLX catalog tests with Doubao configuration tests.

Manual smoke tests:

- System provider still records and sends text to terminal.
- Doubao provider with missing credentials shows a clear error.
- Doubao provider with valid credentials streams partial text and sends final text to terminal.
- Cancel closes capture and socket without inserting text.

## Acceptance Criteria

- No `import MLX`, `import MLXNN`, or `import MLXFFT` remains.
- `mlx-swift` is removed from the Xcode project package references and `Package.resolved`.
- Voice input works with Apple Speech as before.
- Doubao ASR is visible but not selected by default.
- Selecting Doubao without credentials fails with actionable UI text.
- Selecting Doubao with valid credentials transcribes and inserts terminal text through the existing send flow.
