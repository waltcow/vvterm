import Foundation
import Combine
import os.log
import AVFoundation

@MainActor
class AudioService: NSObject, ObservableObject {
    typealias StartupOperation = @MainActor (
        UUID,
        @escaping @MainActor () -> AudioCaptureLifecycleState
    ) async throws -> Void

    private enum RecordingState {
        case idle
        case starting(operationID: UUID, provider: TranscriptionProvider)
        case recording(operationID: UUID, provider: TranscriptionProvider)
        case processing(operationID: UUID, provider: TranscriptionProvider)

        var operationID: UUID? {
            switch self {
            case .idle:
                return nil
            case .starting(let operationID, _),
                 .recording(let operationID, _),
                 .processing(let operationID, _):
                return operationID
            }
        }

        var provider: TranscriptionProvider? {
            switch self {
            case .idle:
                return nil
            case .starting(_, let provider),
                 .recording(_, let provider),
                 .processing(_, let provider):
                return provider
            }
        }

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }
    }

    private let logger = Logger.audio
    @Published private var recordingState: RecordingState = .idle
    @Published var transcribedText = ""
    @Published var partialTranscription = ""
    @Published var audioLevel: Float = 0.0
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionStatus: AudioPermissionManager.PermissionStatus = .notDetermined
    @Published private(set) var runtimeRecordingError: RecordingError?

    // Services
    private let permissionManager = AudioPermissionManager()
    private let speechRecognitionService = SpeechRecognitionService()
    private let audioCaptureService: AudioCaptureService
    private let doubaoProvider = DoubaoASRProvider()
    private let doubaoCredentialStore = DoubaoASRCredentialStore()
    private let startupOperation: StartupOperation?

    var isRecording: Bool { recordingState.isRecording }

    override init() {
        audioCaptureService = AudioCaptureService()
        startupOperation = nil
        super.init()
        setupBindings()
    }

    init(
        audioCaptureService: AudioCaptureService,
        startupOperation: @escaping StartupOperation
    ) {
        self.audioCaptureService = audioCaptureService
        self.startupOperation = startupOperation
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

    func checkPermissions(includeSpeech: Bool) -> Bool {
        permissionManager.checkPermissions(includeSpeech: includeSpeech)
    }

    // MARK: - Recording Control

    func startRecording(
        operationID: UUID,
        lifecycleState: @escaping @MainActor () -> AudioCaptureLifecycleState
    ) async throws {
        try Task.checkCancellation()
        let requestedProvider = TranscriptionSettingsStore.currentProvider()
        let effectiveProvider = resolveProvider(for: requestedProvider)
        runtimeRecordingError = nil
        recordingState = .starting(operationID: operationID, provider: effectiveProvider)

        let needsSpeech = effectiveProvider == .system
        do {
            if let startupOperation {
                try await startupOperation(operationID, lifecycleState)
            } else {
                try await Self.runStartupSequence(
                    lifecycleState: lifecycleState,
                    operationIsCurrent: { [weak self] in
                        self?.recordingState.operationID == operationID
                    },
                    checkPermissions: { [weak self] in
                        self?.checkPermissions(includeSpeech: needsSpeech) ?? false
                    },
                    requestPermissions: { [weak self] in
                        await self?.requestPermissions(includeSpeech: needsSpeech) ?? false
                    },
                    startServices: { [weak self] in
                        guard let self else { throw CancellationError() }

                        self.speechRecognitionService.resetTranscriptions()
                        self.audioCaptureService.cancel()

                        switch effectiveProvider {
                        case .system:
                            try self.startAppleSpeech(lifecycleState: lifecycleState)
                        case .doubaoASR:
                            try await self.startDoubaoASR(lifecycleState: lifecycleState)
                        }
                    }
                )
            }

            guard recordingState.operationID == operationID else {
                throw CancellationError()
            }
            recordingState = .recording(operationID: operationID, provider: effectiveProvider)
        } catch {
            guard recordingState.operationID == operationID else {
                throw CancellationError()
            }
            recordingState = .idle
            audioCaptureService.cancel()
            speechRecognitionService.cancelRecognition()
            await doubaoProvider.cancel()
            if error is CancellationError {
                throw error
            }
            throw recordingError(for: error)
        }
    }

    func stopRecording(operationID: UUID) async -> String {
        let provider = recordingState.provider ?? .system
        recordingState = .processing(operationID: operationID, provider: provider)

        audioCaptureService.bufferHandler = nil
        _ = audioCaptureService.stop()

        switch provider {
        case .system:
            let finalText = await speechRecognitionService.stopRecognition()
            guard finishProcessing(operationID) else { return "" }
            speechRecognitionService.resetTranscriptions()
            return finalText
        case .doubaoASR:
            let text = await Self.runProcessingSequence(
                operationIsCurrent: { [weak self] in
                    self?.processingIsCurrent(operationID) == true
                },
                transcribe: { [doubaoProvider] in
                    try await doubaoProvider.finishAndWaitForFinal(timeoutSeconds: 2.0)
                },
                fallback: { [weak self, doubaoProvider] error in
                    guard let self else { return nil }
                    self.logger.error("Doubao ASR finalization failed: \(error.localizedDescription)")
                    await doubaoProvider.cancel()
                    return self.transcribedText.isEmpty
                        ? self.partialTranscription
                        : self.transcribedText
                }
            )
            guard let text, finishProcessing(operationID) else {
                cancelProcessingIfCurrent(operationID)
                return ""
            }
            transcribedText = text
            partialTranscription = ""
            return text
        }
    }

    func cancelRecording() {
        recordingState = .idle
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

    static func runStartupSequence(
        lifecycleState: @escaping @MainActor () -> AudioCaptureLifecycleState,
        operationIsCurrent: @escaping @MainActor () -> Bool,
        checkPermissions: @escaping @MainActor () -> Bool,
        requestPermissions: @escaping @MainActor () async -> Bool,
        startServices: @escaping @MainActor () async throws -> Void
    ) async throws {
        try validateStartup(
            lifecycleState: lifecycleState,
            operationIsCurrent: operationIsCurrent
        )

        let hasPermissions = checkPermissions()
        try validateStartup(
            lifecycleState: lifecycleState,
            operationIsCurrent: operationIsCurrent
        )
        if !hasPermissions {
            let granted = await requestPermissions()
            try validateStartup(
                lifecycleState: lifecycleState,
                operationIsCurrent: operationIsCurrent
            )
            guard granted else { throw RecordingError.permissionDenied }
        }

        try validateStartup(
            lifecycleState: lifecycleState,
            operationIsCurrent: operationIsCurrent
        )
        try await startServices()
        try validateStartup(
            lifecycleState: lifecycleState,
            operationIsCurrent: operationIsCurrent
        )
    }

    static func runProcessingSequence(
        operationIsCurrent: @escaping @MainActor () -> Bool,
        transcribe: @escaping @MainActor () async throws -> String,
        fallback: @escaping @MainActor (Error) async -> String?
    ) async -> String? {
        do {
            let text = try await transcribe()
            guard operationIsCurrent(), !Task.isCancelled else { return nil }
            return text
        } catch {
            guard operationIsCurrent(), !Task.isCancelled else { return nil }
            let fallbackText = await fallback(error)
            guard operationIsCurrent(), !Task.isCancelled else { return nil }
            return fallbackText
        }
    }

    private static func validateStartup(
        lifecycleState: @MainActor () -> AudioCaptureLifecycleState,
        operationIsCurrent: @MainActor () -> Bool
    ) throws {
        try Task.checkCancellation()
        guard operationIsCurrent() else { throw CancellationError() }
        guard lifecycleState().allowsCapture else {
            throw RecordingError.inactiveLifecycle
        }
    }

    // MARK: - Errors

    enum RecordingError: LocalizedError, Equatable {
        case permissionDenied
        case speechRecognitionUnavailable
        case recordingFailed
        case inactiveLifecycle
        case inputUnavailable
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
            case .inactiveLifecycle:
                return String(localized: "Voice recording is only available while VVTerm is active.")
            case .inputUnavailable:
                return String(localized: "Audio input is temporarily unavailable. Please check the current microphone or audio route and try again.")
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
            case .inactiveLifecycle,
                 .inputUnavailable,
                 .doubaoNetworkUnavailable,
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

    private func startAppleSpeech(lifecycleState: () -> AudioCaptureLifecycleState) throws {
        guard speechRecognitionService.isAvailable else {
            throw RecordingError.speechRecognitionUnavailable
        }

        audioCaptureService.bufferHandler = { [weak speechRecognitionService] buffer in
            speechRecognitionService?.appendAudioBuffer(buffer)
        }

        try speechRecognitionService.startRecognition()
        guard lifecycleState().allowsCapture else {
            throw RecordingError.inactiveLifecycle
        }
        try audioCaptureService.start(lifecycleState: lifecycleState)
    }

    // MARK: - Doubao ASR

    private func startDoubaoASR(lifecycleState: () -> AudioCaptureLifecycleState) async throws {
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
            guard lifecycleState().allowsCapture else {
                throw RecordingError.inactiveLifecycle
            }
            try audioCaptureService.start(lifecycleState: lifecycleState)
        } catch let error as RecordingError {
            audioCaptureService.bufferHandler = nil
            await doubaoProvider.cancel()
            throw error
        } catch {
            audioCaptureService.bufferHandler = nil
            await doubaoProvider.cancel()
            if error is AudioCaptureService.RecordingError {
                throw recordingError(for: error)
            }
            throw RecordingError.doubaoConnectionFailed(error.localizedDescription)
        }
    }

    private func recordingError(for error: Error) -> RecordingError {
        if let recordingError = error as? RecordingError {
            return recordingError
        }
        guard let captureError = error as? AudioCaptureService.RecordingError else {
            return .recordingFailed
        }
        switch captureError {
        case .inactiveLifecycle:
            return .inactiveLifecycle
        case .inputUnavailable:
            return .inputUnavailable
        case .converterUnavailable:
            return .recordingFailed
        }
    }

    private func processingIsCurrent(_ operationID: UUID) -> Bool {
        guard case .processing(let currentID, _) = recordingState else { return false }
        return currentID == operationID
    }

    private func finishProcessing(_ operationID: UUID) -> Bool {
        guard processingIsCurrent(operationID), !Task.isCancelled else {
            cancelProcessingIfCurrent(operationID)
            return false
        }
        recordingState = .idle
        return true
    }

    private func cancelProcessingIfCurrent(_ operationID: UUID) {
        if processingIsCurrent(operationID) {
            recordingState = .idle
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
        guard isRecording, recordingState.provider == .doubaoASR else { return }

        logger.error("Doubao ASR runtime failure: \(error.localizedDescription, privacy: .public)")
        recordingState = .idle
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
