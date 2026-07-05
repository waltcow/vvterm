import Foundation
import Combine
import os.log
import AVFoundation

@MainActor
class AudioService: NSObject, ObservableObject {
    private let logger = Logger.audio
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var partialTranscription = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionStatus: AudioPermissionManager.PermissionStatus = .notDetermined
    @Published private(set) var runtimeRecordingError: RecordingError?

    // Services
    private let permissionManager = AudioPermissionManager()
    private let speechRecognitionService = SpeechRecognitionService()
    private let audioCaptureService = AudioCaptureService()
    private let doubaoProvider = DoubaoASRProvider()
    private let doubaoCredentialStore = DoubaoASRCredentialStore()

    private var activeProvider: TranscriptionProvider = .system

    override init() {
        super.init()
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Permission status
        permissionManager.$permissionStatus
            .assign(to: &$permissionStatus)

        // Speech recognition
        speechRecognitionService.$transcribedText
            .assign(to: &$transcribedText)

        speechRecognitionService.$partialTranscription
            .assign(to: &$partialTranscription)

        // Audio capture
        audioCaptureService.$audioLevel
            .assign(to: &$audioLevel)

        audioCaptureService.$recordingDuration
            .assign(to: &$recordingDuration)
    }

    // MARK: - Permission Handling

    func requestPermissions(includeSpeech: Bool) async -> Bool {
        return await permissionManager.requestPermissions(includeSpeech: includeSpeech)
    }

    func checkPermissions(includeSpeech: Bool) async -> Bool {
        return await permissionManager.checkPermissions(includeSpeech: includeSpeech)
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        let requestedProvider = TranscriptionSettingsStore.currentProvider()
        let effectiveProvider = resolveProvider(for: requestedProvider)
        activeProvider = effectiveProvider

        let needsSpeech = effectiveProvider == .system
        let hasPermissions = await checkPermissions(includeSpeech: needsSpeech)
        if !hasPermissions {
            let granted = await requestPermissions(includeSpeech: needsSpeech)
            guard granted else {
                throw RecordingError.permissionDenied
            }
        }

        // Reset state
        runtimeRecordingError = nil
        speechRecognitionService.resetTranscriptions()
        audioCaptureService.cancel()

        // Start services
        switch effectiveProvider {
        case .system:
            try await startAppleSpeech()
        case .doubaoASR:
            try await startDoubaoASR()
        }

        isRecording = true
    }

    func stopRecording() async -> String {
        isRecording = false
        audioCaptureService.bufferHandler = nil

        _ = audioCaptureService.stop()

        switch activeProvider {
        case .system:
            let finalText = await speechRecognitionService.stopRecognition()
            speechRecognitionService.resetTranscriptions()
            return finalText
        case .doubaoASR:
            do {
                let finalText = try await doubaoProvider.finishAndWaitForFinal(timeoutSeconds: 2.0)
                transcribedText = finalText
                partialTranscription = ""
                return finalText
            } catch {
                logger.error("Doubao ASR finalization failed: \(error.localizedDescription)")
                await doubaoProvider.cancel()
                let bestEffortText = transcribedText.isEmpty ? partialTranscription : transcribedText
                partialTranscription = ""
                return bestEffortText
            }
        }
    }

    func cancelRecording() {
        isRecording = false
        runtimeRecordingError = nil
        audioCaptureService.bufferHandler = nil

        audioCaptureService.cancel()
        speechRecognitionService.cancelRecognition()
        Task { [doubaoProvider] in
            await doubaoProvider.cancel()
        }
        speechRecognitionService.resetTranscriptions()
        transcribedText = ""
        partialTranscription = ""
    }

    // MARK: - Errors

    enum RecordingError: LocalizedError, Equatable {
        case permissionDenied
        case speechRecognitionUnavailable
        case recordingFailed
        case missingDoubaoCredentials
        case invalidDoubaoEndpoint
        case doubaoNetworkUnavailable
        case doubaoConnectionFailed(String)
        case doubaoConnectionLost
        case doubaoServerError(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return String(localized: "Microphone permission is required. The microphone will be automatically requested when recording starts.")
            case .speechRecognitionUnavailable:
                return String(localized: "Speech recognition is not available. Please enable Siri in System Settings > Siri & Spotlight.")
            case .recordingFailed:
                return String(localized: "Failed to start recording. Please check microphone permissions in System Settings > Privacy & Security > Microphone.")
            case .missingDoubaoCredentials:
                return String(localized: "Doubao ASR App ID and Access Token are required.")
            case .invalidDoubaoEndpoint:
                return String(localized: "Doubao ASR endpoint must be a wss://openspeech.bytedance.com streaming URL.")
            case .doubaoNetworkUnavailable:
                return String(localized: "Doubao ASR requires a network connection.")
            case .doubaoConnectionFailed(let message):
                return String(localized: "Doubao ASR connection failed: \(message)")
            case .doubaoConnectionLost:
                return String(localized: "Doubao ASR connection was lost during recording.")
            case .doubaoServerError(let message):
                return String(localized: "Doubao ASR server error: \(message)")
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .permissionDenied, .speechRecognitionUnavailable, .recordingFailed:
                return String(localized: "Enable Microphone and Speech Recognition in System Settings.")
            case .missingDoubaoCredentials:
                return String(localized: "Open Transcription settings and enter your Doubao ASR App ID and Access Token.")
            case .invalidDoubaoEndpoint:
                return String(localized: "Use a wss://openspeech.bytedance.com endpoint or leave the endpoint field empty.")
            case .doubaoNetworkUnavailable,
                 .doubaoConnectionFailed,
                 .doubaoConnectionLost,
                 .doubaoServerError:
                return nil
            }
        }
    }

    // MARK: - Provider Resolution

    private func resolveProvider(for requested: TranscriptionProvider) -> TranscriptionProvider {
        switch requested {
        case .system:
            return .system
        case .doubaoASR:
            return .doubaoASR
        }
    }

    // MARK: - Apple Speech

    private func startAppleSpeech() async throws {
        guard speechRecognitionService.isAvailable else {
            throw RecordingError.speechRecognitionUnavailable
        }

        audioCaptureService.bufferHandler = { [weak speechRecognitionService] buffer in
            speechRecognitionService?.appendAudioBuffer(buffer)
        }

        try await speechRecognitionService.startRecognition()
        do {
            try audioCaptureService.start()
        } catch {
            throw RecordingError.recordingFailed
        }
    }

    // MARK: - Doubao ASR

    private func startDoubaoASR() async throws {
        guard NetworkMonitor.shared.isConnected else {
            throw RecordingError.doubaoNetworkUnavailable
        }

        let configuration = try doubaoConfiguration()
        audioCaptureService.bufferHandler = { [weak self] buffer in
            guard let self,
                  let pcmData = Self.int16PCMData(from: buffer),
                  !pcmData.isEmpty else {
                return
            }

            Task { [weak self, doubaoProvider] in
                do {
                    try await doubaoProvider.appendPCMData(pcmData)
                } catch {
                    await MainActor.run {
                        self?.logger.error("Doubao ASR audio send failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        do {
            try await doubaoProvider.start(
                configuration: configuration,
                onServerEvent: { [weak self] event in
                    await self?.handleDoubaoServerEvent(event)
                },
                onRuntimeFailure: { [weak self] error in
                    await self?.handleDoubaoRuntimeFailure(error)
                }
            )
            try audioCaptureService.start()
        } catch let error as RecordingError {
            audioCaptureService.bufferHandler = nil
            await doubaoProvider.cancel()
            throw error
        } catch {
            audioCaptureService.bufferHandler = nil
            await doubaoProvider.cancel()
            throw RecordingError.doubaoConnectionFailed(error.localizedDescription)
        }
    }

    private func doubaoConfiguration() throws -> DoubaoASRProviderConfiguration {
        let appID = TranscriptionSettingsStore.currentDoubaoAppID()
        guard !appID.isEmpty else {
            throw RecordingError.missingDoubaoCredentials
        }

        let accessToken: String
        do {
            guard let token = try doubaoCredentialStore.accessToken() else {
                throw RecordingError.missingDoubaoCredentials
            }
            accessToken = token
        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.doubaoConnectionFailed(error.localizedDescription)
        }

        let resourceID = DoubaoASRConfiguration.resolvedResourceID(
            TranscriptionSettingsStore.currentDoubaoModelId()
        )
        let endpointString: String
        do {
            endpointString = try DoubaoASRConfiguration.resolvedStreamingEndpoint(
                TranscriptionSettingsStore.currentDoubaoEndpoint(),
                model: resourceID
            )
        } catch {
            throw RecordingError.invalidDoubaoEndpoint
        }
        guard let endpoint = URL(string: endpointString) else {
            throw RecordingError.invalidDoubaoEndpoint
        }

        return DoubaoASRProviderConfiguration(
            endpoint: endpoint,
            appID: appID,
            accessToken: accessToken,
            resourceID: resourceID,
            language: DoubaoASRConfiguration.languageParameter(
                for: TranscriptionSettingsStore.currentLanguageCode()
            )
        )
    }

    private func handleDoubaoServerEvent(_ event: DoubaoServerEvent) {
        guard let text = event.text else { return }
        if event.isFinal {
            transcribedText = text
            partialTranscription = ""
        } else {
            partialTranscription = text
        }
    }

    private func handleDoubaoRuntimeFailure(_ error: Error) async {
        guard isRecording, activeProvider == .doubaoASR else { return }

        isRecording = false
        audioCaptureService.bufferHandler = nil
        audioCaptureService.cancel()
        await doubaoProvider.cancel()
        runtimeRecordingError = mapDoubaoRuntimeFailure(error)
    }

    private func mapDoubaoRuntimeFailure(_ error: Error) -> RecordingError {
        if let recordingError = error as? RecordingError {
            return recordingError
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return .doubaoConnectionLost
        }
        return .doubaoServerError(message)
    }

    static func formattedRecordingErrorMessage(_ error: RecordingError) -> String {
        [error.localizedDescription, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    private static func int16PCMData(from buffer: AVAudioPCMBuffer) -> Data? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0,
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        return DoubaoASRConfiguration.int16PCMData(from: samples)
    }

}
