import XCTest
@testable import VVTerm

final class DoubaoASRCredentialStoreTests: XCTestCase {
    func testAccessTokenIsStoredWithFixedKeyAndWithoutICloudSync() throws {
        let backing = SpySecretStore()
        let store = DoubaoASRCredentialStore(backing: backing)

        try store.saveAccessToken(" token-value ")

        XCTAssertEqual(backing.setCalls.count, 1)
        XCTAssertEqual(backing.setCalls[0].value, "token-value")
        XCTAssertEqual(backing.setCalls[0].key, DoubaoASRCredentialStore.accessTokenKey)
        XCTAssertFalse(backing.setCalls[0].iCloudSync)
    }

    func testBlankAccessTokenDeletesExistingSecret() throws {
        let backing = SpySecretStore()
        let store = DoubaoASRCredentialStore(backing: backing)

        try store.saveAccessToken("   ")

        XCTAssertEqual(backing.deletedKeys, [DoubaoASRCredentialStore.accessTokenKey])
        XCTAssertTrue(backing.setCalls.isEmpty)
    }

    func testAccessTokenReadsTrimmedValueAndTreatsBlankAsMissing() throws {
        let backing = SpySecretStore()
        let store = DoubaoASRCredentialStore(backing: backing)

        backing.values[DoubaoASRCredentialStore.accessTokenKey] = " stored-token "
        XCTAssertEqual(try store.accessToken(), "stored-token")

        backing.values[DoubaoASRCredentialStore.accessTokenKey] = "   "
        XCTAssertNil(try store.accessToken())
    }

    func testDeleteAccessTokenUsesFixedKey() throws {
        let backing = SpySecretStore()
        let store = DoubaoASRCredentialStore(backing: backing)

        try store.deleteAccessToken()

        XCTAssertEqual(backing.deletedKeys, [DoubaoASRCredentialStore.accessTokenKey])
    }
}

private final class SpySecretStore: DoubaoASRSecretStoring {
    struct SetCall: Equatable {
        let value: String
        let key: String
        let iCloudSync: Bool
    }

    var values: [String: String] = [:]
    var setCalls: [SetCall] = []
    var deletedKeys: [String] = []

    func setString(_ value: String, forKey key: String, iCloudSync: Bool) throws {
        setCalls.append(SetCall(value: value, key: key, iCloudSync: iCloudSync))
        values[key] = value
    }

    func getString(_ key: String) throws -> String? {
        values[key]
    }

    func delete(_ key: String) throws {
        deletedKeys.append(key)
        values.removeValue(forKey: key)
    }
}
