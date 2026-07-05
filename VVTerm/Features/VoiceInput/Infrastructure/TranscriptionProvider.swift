import Foundation

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case system
    case doubaoASR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "System (Apple Speech)")
        case .doubaoASR:
            return String(localized: "Doubao ASR")
        }
    }
}

struct TranscriptionSettingsKeys {
    static let provider = "transcriptionProvider"
    static let language = "transcriptionLanguage"
    static let doubaoModelId = "doubaoASRModelId"
    static let doubaoEndpoint = "doubaoASREndpoint"
    static let doubaoAppID = "doubaoASRAppID"
}

struct TranscriptionSettingsDefaults {
    static let provider: TranscriptionProvider = .system
    static let language = "en"
    static let autoLanguageCode = "auto"
    static let doubaoModelId = "volc.seedasr.sauc.duration"
    static let doubaoEndpoint = ""
}

struct TranscriptionSettingsStore {
    static func currentProvider() -> TranscriptionProvider {
        guard let stored = UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.provider) else {
            return TranscriptionSettingsDefaults.provider
        }

        let raw = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        switch raw {
        case TranscriptionProvider.system.rawValue:
            return .system
        case TranscriptionProvider.doubaoASR.rawValue:
            return .doubaoASR
        case "whisper", "parakeet", "mlxWhisper", "mlxParakeet":
            UserDefaults.standard.set(
                TranscriptionProvider.system.rawValue,
                forKey: TranscriptionSettingsKeys.provider
            )
            return .system
        default:
            UserDefaults.standard.set(
                TranscriptionProvider.system.rawValue,
                forKey: TranscriptionSettingsKeys.provider
            )
            return TranscriptionSettingsDefaults.provider
        }
    }

    static func currentLanguageCode() -> String {
        let raw = UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.language)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let raw, !raw.isEmpty else { return TranscriptionSettingsDefaults.language }
        return raw
    }

    static func currentDoubaoModelId() -> String {
        let raw = UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.doubaoModelId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else {
            return TranscriptionSettingsDefaults.doubaoModelId
        }
        return raw
    }

    static func currentDoubaoEndpoint() -> String {
        UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.doubaoEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? TranscriptionSettingsDefaults.doubaoEndpoint
    }

    static func currentDoubaoAppID() -> String {
        UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.doubaoAppID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
