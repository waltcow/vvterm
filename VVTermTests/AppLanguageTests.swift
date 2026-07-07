import Foundation
import Testing
@testable import VVTerm

struct AppLanguageTests {
    @Test
    func appLanguageChoicesAreLimitedToSystemEnglishAndSimplifiedChinese() {
        #expect(AppLanguage.allCases.map(\.rawValue) == ["system", "en", "zh-Hans"])
    }

    @Test
    func unsupportedLegacyLanguageSelectionFallsBackToSystemLanguages() {
        defer {
            UserDefaults.standard.removeObject(forKey: AppLanguage.storageKey)
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }

        UserDefaults.standard.set("ja", forKey: AppLanguage.storageKey)
        UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
        AppLanguage.applySelection("ja")

        #expect(UserDefaults.standard.string(forKey: AppLanguage.storageKey) == nil)
        #expect(UserDefaults.standard.stringArray(forKey: "AppleLanguages") != ["ja"])
    }
}
