import Foundation

protocol DoubaoASRSecretStoring: AnyObject {
    func setString(_ value: String, forKey key: String, iCloudSync: Bool) throws
    func getString(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

extension KeychainStore: DoubaoASRSecretStoring {}

struct DoubaoASRCredentialStore {
    static let accessTokenKey = "doubaoASR.accessToken"

    private let backing: DoubaoASRSecretStoring

    init(backing: DoubaoASRSecretStoring = KeychainStore(service: "app.vivy.vvterm")) {
        self.backing = backing
    }

    func saveAccessToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteAccessToken()
            return
        }

        try backing.setString(trimmed, forKey: Self.accessTokenKey, iCloudSync: false)
    }

    func accessToken() throws -> String? {
        let token = try backing.getString(Self.accessTokenKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, !token.isEmpty else {
            return nil
        }
        return token
    }

    func deleteAccessToken() throws {
        try backing.delete(Self.accessTokenKey)
    }
}
