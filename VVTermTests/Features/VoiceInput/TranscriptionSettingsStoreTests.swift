import XCTest
@testable import VVTerm

final class TranscriptionSettingsStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearKeys()
    }

    override func tearDown() {
        clearKeys()
        super.tearDown()
    }

    func testCurrentProviderDefaultsToSystem() {
        XCTAssertEqual(TranscriptionSettingsStore.currentProvider(), .system)
    }

    func testCurrentProviderSupportsLegacyRawValues() {
        for rawValue in ["whisper", "parakeet", "mlxWhisper", "mlxParakeet"] {
            UserDefaults.standard.set(rawValue, forKey: TranscriptionSettingsKeys.provider)

            XCTAssertEqual(TranscriptionSettingsStore.currentProvider(), .system)
            XCTAssertEqual(
                UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.provider),
                TranscriptionProvider.system.rawValue
            )
        }
    }

    func testCurrentProviderSupportsDoubaoASR() {
        UserDefaults.standard.set("doubaoASR", forKey: TranscriptionSettingsKeys.provider)

        XCTAssertEqual(TranscriptionSettingsStore.currentProvider(), .doubaoASR)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.provider),
            TranscriptionProvider.doubaoASR.rawValue
        )
    }

    func testCurrentProviderNormalizesUnknownRawValuesToSystem() {
        for rawValue in ["", "local", "not-a-provider"] {
            UserDefaults.standard.set(rawValue, forKey: TranscriptionSettingsKeys.provider)

            XCTAssertEqual(TranscriptionSettingsStore.currentProvider(), .system)
            XCTAssertEqual(
                UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.provider),
                TranscriptionProvider.system.rawValue
            )
        }
    }

    func testCurrentProviderMissingKeyDoesNotPersistDefault() {
        XCTAssertNil(UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.provider))

        XCTAssertEqual(TranscriptionSettingsStore.currentProvider(), .system)
        XCTAssertNil(UserDefaults.standard.string(forKey: TranscriptionSettingsKeys.provider))
    }

    func testCurrentDoubaoSettingsUseDefaultsAndTrimStoredValues() {
        XCTAssertEqual(
            TranscriptionSettingsStore.currentDoubaoModelId(),
            TranscriptionSettingsDefaults.doubaoModelId
        )
        XCTAssertEqual(TranscriptionSettingsStore.currentDoubaoEndpoint(), "")
        XCTAssertEqual(TranscriptionSettingsStore.currentDoubaoAppID(), "")

        UserDefaults.standard.set(" custom-model ", forKey: TranscriptionSettingsKeys.doubaoModelId)
        UserDefaults.standard.set(" wss://openspeech.bytedance.com/api/v3/sauc/bigmodel ", forKey: TranscriptionSettingsKeys.doubaoEndpoint)
        UserDefaults.standard.set(" app-id ", forKey: TranscriptionSettingsKeys.doubaoAppID)

        XCTAssertEqual(TranscriptionSettingsStore.currentDoubaoModelId(), "custom-model")
        XCTAssertEqual(
            TranscriptionSettingsStore.currentDoubaoEndpoint(),
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
        )
        XCTAssertEqual(TranscriptionSettingsStore.currentDoubaoAppID(), "app-id")
    }

    private func clearKeys() {
        let defaults = UserDefaults.standard
        [
            TranscriptionSettingsKeys.provider,
            TranscriptionSettingsKeys.doubaoModelId,
            TranscriptionSettingsKeys.doubaoEndpoint,
            TranscriptionSettingsKeys.doubaoAppID,
            "whisperModelId",
            "parakeetModelId",
        ].forEach(defaults.removeObject(forKey:))
    }
}
