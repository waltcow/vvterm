import Foundation
import XCTest
@testable import VVTerm

nonisolated struct SSHIntegrationFixtureConfiguration {
    let server: Server
    let credentials: ServerCredentials

    static func load(displayName: String) throws -> SSHIntegrationFixtureConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard let host = environment["VVTERM_SSH_FIXTURE_HOST"],
              let username = environment["VVTERM_SSH_FIXTURE_USER"] else {
            return nil
        }

        let port = environment["VVTERM_SSH_FIXTURE_PORT"].flatMap(Int.init) ?? 22
        let password = environment["VVTERM_SSH_FIXTURE_PASSWORD"]
        let privateKey: Data?
        if let path = environment["VVTERM_SSH_FIXTURE_PRIVATE_KEY_PATH"] {
            privateKey = try Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            privateKey = nil
        }

        guard password != nil || privateKey != nil else {
            throw XCTSkip("Set either VVTERM_SSH_FIXTURE_PASSWORD or VVTERM_SSH_FIXTURE_PRIVATE_KEY_PATH")
        }

        let serverId = UUID()
        let passphrase = environment["VVTERM_SSH_FIXTURE_KEY_PASSPHRASE"]
        let authMethod: AuthMethod = privateKey == nil
            ? .password
            : (passphrase == nil ? .sshKey : .sshKeyWithPassphrase)
        let server = Server(
            id: serverId,
            workspaceId: UUID(),
            name: displayName,
            host: host,
            port: port,
            username: username,
            authMethod: authMethod
        )
        let credentials = ServerCredentials(
            serverId: serverId,
            password: password,
            privateKey: privateKey,
            publicKey: nil,
            passphrase: passphrase
        )
        return SSHIntegrationFixtureConfiguration(server: server, credentials: credentials)
    }
}
