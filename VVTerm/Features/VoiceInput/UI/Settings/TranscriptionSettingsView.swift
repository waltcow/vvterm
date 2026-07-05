//
//  TranscriptionSettingsView.swift
//  VVTerm
//

import SwiftUI

// MARK: - Transcription Settings View

struct TranscriptionSettingsView: View {
    @AppStorage(TranscriptionSettingsKeys.provider) private var provider = TranscriptionSettingsDefaults.provider.rawValue
    @AppStorage(TranscriptionSettingsKeys.mlxWhisperModelId) private var whisperModelId = TranscriptionSettingsDefaults.mlxWhisperModelId
    @AppStorage(TranscriptionSettingsKeys.mlxParakeetModelId) private var parakeetModelId = TranscriptionSettingsDefaults.mlxParakeetModelId
    @AppStorage(TranscriptionSettingsKeys.language) private var language = TranscriptionSettingsDefaults.language
    @AppStorage(TranscriptionSettingsKeys.doubaoModelId) private var doubaoModelId = TranscriptionSettingsDefaults.doubaoModelId
    @AppStorage(TranscriptionSettingsKeys.doubaoEndpoint) private var doubaoEndpoint = TranscriptionSettingsDefaults.doubaoEndpoint
    @AppStorage(TranscriptionSettingsKeys.doubaoAppID) private var doubaoAppID = ""
    @AppStorage("terminalVoiceButtonEnabled") private var terminalVoiceButtonEnabled = true

    @StateObject private var whisperManager: MLXModelManager
    @StateObject private var parakeetManager: MLXModelManager
    @State private var doubaoAccessToken = ""
    @State private var doubaoCredentialStatus: String?

    private let mlxAvailable = MLXAudioSupport.isSupported
    private let doubaoCredentialStore = DoubaoASRCredentialStore()

    private let languages = [
        ("en", String(localized: "English")),
        ("es", String(localized: "Spanish")),
        ("fr", String(localized: "French")),
        ("de", String(localized: "German")),
        ("ja", String(localized: "Japanese")),
        ("zh", String(localized: "Chinese")),
        ("ko", String(localized: "Korean")),
        ("pt", String(localized: "Portuguese")),
        ("ru", String(localized: "Russian")),
        ("auto", String(localized: "Auto-detect"))
    ]

    init() {
        let whisper = MLXModelManager(kind: .whisper, modelId: Self.resolveWhisperModelId())
        let parakeet = MLXModelManager(kind: .parakeetTDT, modelId: Self.resolveParakeetModelId())
        _whisperManager = StateObject(wrappedValue: whisper)
        _parakeetManager = StateObject(wrappedValue: parakeet)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show voice input button", isOn: $terminalVoiceButtonEnabled)
            } header: {
                Text("Terminal")
            } footer: {
                Text("Cmd + Shift + M always works, even when the button is hidden.")
            }

            Section {
                Picker("Engine", selection: $provider) {
                    Text("System (Apple)").tag(TranscriptionProvider.system.rawValue)
                    Text("Doubao ASR").tag(TranscriptionProvider.doubaoASR.rawValue)
                    #if arch(arm64)
                    if mlxAvailable {
                        Text("Whisper (MLX)").tag(TranscriptionProvider.mlxWhisper.rawValue)
                        Text("Parakeet (MLX)").tag(TranscriptionProvider.mlxParakeet.rawValue)
                    }
                    #endif
                }
            } header: {
                Text("Provider")
            } footer: {
                Text(providerDescription)
            }

            if provider == TranscriptionProvider.system.rawValue ||
                provider == TranscriptionProvider.doubaoASR.rawValue ||
                provider == TranscriptionProvider.mlxWhisper.rawValue {
                Section {
                    Picker("Language", selection: $language) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    if language == TranscriptionSettingsDefaults.autoLanguageCode {
                        if provider == TranscriptionProvider.system.rawValue {
                            Text("Auto-detect uses your device language.")
                        } else if provider == TranscriptionProvider.doubaoASR.rawValue {
                            Text("Auto-detect lets Doubao ASR infer the spoken language.")
                        } else {
                            Text("Auto-detect identifies the spoken language before transcribing.")
                        }
                    } else if provider == TranscriptionProvider.doubaoASR.rawValue,
                              DoubaoASRConfiguration.languageParameter(for: language) == nil {
                        Text("This language is not sent to Doubao ASR; the request will use automatic language detection.")
                    }
                }
            }

            if provider == TranscriptionProvider.doubaoASR.rawValue {
                doubaoSection
            }

            #if arch(arm64)
            if mlxAvailable && provider == TranscriptionProvider.mlxWhisper.rawValue {
                modelSection(
                    manager: whisperManager,
                    modelBinding: $whisperModelId,
                    models: [
                        ("mlx-community/whisper-tiny-mlx", String(localized: "Tiny"), "~39 MB"),
                        ("mlx-community/whisper-base-mlx", String(localized: "Base"), "~74 MB"),
                        ("mlx-community/whisper-small-mlx", String(localized: "Small"), "~244 MB"),
                        ("mlx-community/whisper-medium-mlx-8bit", String(localized: "Medium (8-bit)"), "~400 MB"),
                        ("mlx-community/whisper-medium-mlx-q4", String(localized: "Medium (Q4)"), "~250 MB"),
                        ("mlx-community/whisper-medium-mlx-fp32", String(localized: "Medium (FP32)"), "~1.5 GB")
                    ]
                )
            }

            if mlxAvailable && provider == TranscriptionProvider.mlxParakeet.rawValue {
                modelSection(
                    manager: parakeetManager,
                    modelBinding: $parakeetModelId,
                    models: [
                        ("mlx-community/parakeet-tdt-0.6b-v2", String(localized: "Parakeet TDT 0.6B"), "~600 MB")
                    ],
                    footnote: String(localized: "Parakeet supports English only.")
                )
            }
            #endif

            storageSection
        }
        .formStyle(.grouped)
        .onAppear {
            migrateLegacySettings()
            loadDoubaoAccessToken()
            whisperManager.refreshStatus()
            parakeetManager.refreshStatus()
        }
    }

    private var providerDescription: String {
        switch provider {
        case TranscriptionProvider.system.rawValue:
            return String(localized: "Uses Apple's built-in speech recognition. Requires network for best results.")
        case TranscriptionProvider.doubaoASR.rawValue:
            return String(localized: "Streams microphone audio to Doubao ASR. Requires a Volcengine App ID and Access Token.")
        case TranscriptionProvider.mlxWhisper.rawValue:
            return String(localized: "OpenAI Whisper runs locally using MLX. Works offline after download.")
        case TranscriptionProvider.mlxParakeet.rawValue:
            return String(localized: "NVIDIA Parakeet runs locally using MLX. Optimized for real-time transcription.")
        default:
            return ""
        }
    }

    @ViewBuilder
    private var doubaoSection: some View {
        Section {
            Picker("Model", selection: $doubaoModelId) {
                Text("SeedASR streaming").tag(DoubaoASRConfiguration.modelV2)
                Text("BigASR streaming").tag(DoubaoASRConfiguration.modelV1)
            }

            TextField("Endpoint Override", text: $doubaoEndpoint)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            TextField("App ID", text: $doubaoAppID)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            SecureField("Access Token", text: $doubaoAccessToken)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif

            HStack {
                Button("Save Access Token") {
                    saveDoubaoAccessToken()
                }
                Button("Remove Access Token", role: .destructive) {
                    removeDoubaoAccessToken()
                }
            }

            if let doubaoCredentialStatus {
                Text(doubaoCredentialStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Doubao ASR")
        } footer: {
            Text("Leave endpoint empty to use the model default. Custom endpoints must use Volcengine's allowlisted wss://openspeech.bytedance.com streaming URLs. Audio is sent to Doubao ASR only when this provider is selected.")
        }
    }

    @ViewBuilder
    private func modelSection(
        manager: MLXModelManager,
        modelBinding: Binding<String>,
        models: [(String, String, String)],
        footnote: String? = nil
    ) -> some View {
        Section {
            Picker("Model", selection: modelBinding) {
                ForEach(models, id: \.0) { id, name, size in
                    HStack {
                        Text(name)
                        Spacer()
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(id)
                }
            }
            .onChangeCompat(of: modelBinding.wrappedValue) { newValue in
                manager.modelId = newValue
                manager.refreshStatus()
            }

            modelStatusRow(manager: manager)

            if case .downloading(let progress) = manager.state {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                    HStack {
                        if progress.totalBytes > 0 {
                            Text(String(format: String(localized: "%@ / %@"),
                                        ByteCountFormatter.string(fromByteCount: progress.bytesDownloaded, countStyle: .file),
                                        ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)))
                        } else {
                            Text("Downloading...")
                        }
                        Spacer()
                        if let eta = progress.estimatedSecondsRemaining, eta > 0 {
                            Text(formatETA(eta))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if manager.isModelAvailable {
                Button("Delete Model", role: .destructive) {
                    manager.removeModel()
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Model")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let footnote {
                    Text(footnote)
                }
                if let repoSize = manager.repoSizeBytes {
                    Text(String(format: String(localized: "Download size: %@"),
                                ByteCountFormatter.string(fromByteCount: repoSize, countStyle: .file)))
                }
            }
        }
    }

    @ViewBuilder
    private func modelStatusRow(manager: MLXModelManager) -> some View {
        HStack {
            Text("Status")
            Spacer()
            switch manager.state {
            case .idle:
                Button("Download") {
                    Task { await manager.downloadModel() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .downloading:
                Text("Downloading...")
                    .foregroundStyle(.orange)
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let error):
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Failed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatETA(_ seconds: Int) -> String {
        if seconds < 60 {
            return String(format: String(localized: "%llds remaining"), seconds)
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return String(format: String(localized: "%lldm remaining"), minutes)
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return String(format: String(localized: "%lldh %lldm remaining"), hours, minutes)
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        #if arch(arm64)
        if mlxAvailable {
            let activeManager = provider == TranscriptionProvider.mlxWhisper.rawValue ? whisperManager : parakeetManager
            if activeManager.totalStorageBytes > 0 {
                Section("Storage") {
                    HStack {
                        Text("Model Storage")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: activeManager.localStorageBytes, countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total MLX Models")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: activeManager.totalStorageBytes, countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    Button("Clear All Storage", role: .destructive) {
                        MLXModelManager.clearAllStorage()
                        whisperManager.refreshStatus()
                        parakeetManager.refreshStatus()
                    }
                }
            }
        }
        #endif
    }

    private static func resolveWhisperModelId() -> String {
        let defaults = UserDefaults.standard
        if let current = defaults.string(forKey: TranscriptionSettingsKeys.mlxWhisperModelId) {
            return current
        }
        if let legacy = defaults.string(forKey: "whisperModelId") {
            defaults.set(legacy, forKey: TranscriptionSettingsKeys.mlxWhisperModelId)
            return legacy
        }
        return TranscriptionSettingsDefaults.mlxWhisperModelId
    }

    private static func resolveParakeetModelId() -> String {
        let defaults = UserDefaults.standard
        if let current = defaults.string(forKey: TranscriptionSettingsKeys.mlxParakeetModelId) {
            return current
        }
        if let legacy = defaults.string(forKey: "parakeetModelId") {
            defaults.set(legacy, forKey: TranscriptionSettingsKeys.mlxParakeetModelId)
            return legacy
        }
        return TranscriptionSettingsDefaults.mlxParakeetModelId
    }

    private func migrateLegacySettings() {
        let defaults = UserDefaults.standard
        provider = TranscriptionSettingsStore.currentProvider().rawValue

        if defaults.string(forKey: TranscriptionSettingsKeys.mlxWhisperModelId) == nil,
           let legacy = defaults.string(forKey: "whisperModelId") {
            defaults.set(legacy, forKey: TranscriptionSettingsKeys.mlxWhisperModelId)
            whisperModelId = legacy
        }

        if defaults.string(forKey: TranscriptionSettingsKeys.mlxParakeetModelId) == nil,
           let legacy = defaults.string(forKey: "parakeetModelId") {
            defaults.set(legacy, forKey: TranscriptionSettingsKeys.mlxParakeetModelId)
            parakeetModelId = legacy
        }

        if !mlxAvailable,
           provider != TranscriptionProvider.system.rawValue {
            provider = TranscriptionProvider.system.rawValue
            defaults.set(provider, forKey: TranscriptionSettingsKeys.provider)
        }
    }

    private func loadDoubaoAccessToken() {
        do {
            doubaoAccessToken = try doubaoCredentialStore.accessToken() ?? ""
        } catch {
            doubaoAccessToken = ""
            doubaoCredentialStatus = String(localized: "Failed to read Doubao ASR Access Token.")
        }
    }

    private func saveDoubaoAccessToken() {
        do {
            try doubaoCredentialStore.saveAccessToken(doubaoAccessToken)
            doubaoCredentialStatus = doubaoAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "Doubao ASR Access Token removed.")
                : String(localized: "Doubao ASR Access Token saved.")
            loadDoubaoAccessToken()
        } catch {
            doubaoCredentialStatus = String(localized: "Failed to save Doubao ASR Access Token.")
        }
    }

    private func removeDoubaoAccessToken() {
        do {
            try doubaoCredentialStore.deleteAccessToken()
            doubaoAccessToken = ""
            doubaoCredentialStatus = String(localized: "Doubao ASR Access Token removed.")
        } catch {
            doubaoCredentialStatus = String(localized: "Failed to remove Doubao ASR Access Token.")
        }
    }
}
