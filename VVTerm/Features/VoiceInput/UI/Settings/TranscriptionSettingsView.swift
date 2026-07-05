//
//  TranscriptionSettingsView.swift
//  VVTerm
//

import SwiftUI

// MARK: - Transcription Settings View

struct TranscriptionSettingsView: View {
    @AppStorage(TranscriptionSettingsKeys.provider) private var provider = TranscriptionSettingsDefaults.provider.rawValue
    @AppStorage(TranscriptionSettingsKeys.language) private var language = TranscriptionSettingsDefaults.language
    @AppStorage(TranscriptionSettingsKeys.doubaoModelId) private var doubaoModelId = TranscriptionSettingsDefaults.doubaoModelId
    @AppStorage(TranscriptionSettingsKeys.doubaoEndpoint) private var doubaoEndpoint = TranscriptionSettingsDefaults.doubaoEndpoint
    @AppStorage(TranscriptionSettingsKeys.doubaoAppID) private var doubaoAppID = ""
    @AppStorage("terminalVoiceButtonEnabled") private var terminalVoiceButtonEnabled = true

    @State private var doubaoAccessToken = ""
    @State private var doubaoCredentialStatus: String?

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
                }
            } header: {
                Text("Provider")
            } footer: {
                Text(providerDescription)
            }

            if provider == TranscriptionProvider.system.rawValue ||
                provider == TranscriptionProvider.doubaoASR.rawValue {
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
        }
        .formStyle(.grouped)
        .onAppear {
            migrateLegacySettings()
            loadDoubaoAccessToken()
        }
    }

    private var providerDescription: String {
        switch provider {
        case TranscriptionProvider.system.rawValue:
            return String(localized: "Uses Apple's built-in speech recognition. Requires network for best results.")
        case TranscriptionProvider.doubaoASR.rawValue:
            return String(localized: "Streams microphone audio to Doubao ASR. Requires a Volcengine App ID and Access Token.")
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

    private func migrateLegacySettings() {
        provider = TranscriptionSettingsStore.currentProvider().rawValue
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
