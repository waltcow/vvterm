import Foundation
import CloudKit
import Testing
@testable import VVTerm

struct ServerConnectionModeTests {
    private func makeServer(
        connectionMode: SSHConnectionMode = .standard,
        authMethod: AuthMethod = .password
    ) -> Server {
        Server(
            id: UUID(),
            workspaceId: UUID(),
            environment: .production,
            name: "Test Server",
            host: "example.com",
            port: 22,
            username: "root",
            connectionMode: connectionMode,
            authMethod: authMethod,
            tags: ["test"],
            notes: "note",
            lastConnected: nil,
            isFavorite: false,
            tmuxEnabledOverride: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func mutateJSON(_ server: Server, mutate: (inout [String: Any]) -> Void) throws -> Data {
        let encoded = try JSONEncoder().encode(server)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test
    func decodeWithoutConnectionModeDefaultsToStandard() throws {
        let server = makeServer(connectionMode: .mosh, authMethod: .password)
        let data = try mutateJSON(server) { object in
            object.removeValue(forKey: "connectionMode")
        }

        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.connectionMode == .standard)
    }

    @Test
    func decodeWithoutBiometricFlagDefaultsToFalse() throws {
        let server = makeServer(connectionMode: .standard, authMethod: .password)
        let data = try mutateJSON(server) { object in
            object.removeValue(forKey: "requiresBiometricUnlock")
        }

        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.requiresBiometricUnlock == false)
    }

    @Test
    func encodeDecodePreservesBiometricFlag() throws {
        var server = makeServer(connectionMode: .standard, authMethod: .password)
        server.requiresBiometricUnlock = true

        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.requiresBiometricUnlock == true)
    }

    @Test
    func decodeWithUnknownConnectionModeDefaultsToStandard() throws {
        let server = makeServer(connectionMode: .standard, authMethod: .password)
        let data = try mutateJSON(server) { object in
            object["connectionMode"] = "future-mode"
        }

        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.connectionMode == .standard)
    }

    @Test
    func decodeMoshConnectionMode() throws {
        let server = makeServer(connectionMode: .mosh, authMethod: .sshKey)
        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.connectionMode == .mosh)
    }

    @Test
    func decodeLegacyTailscaleConnectionModeDefaultsToStandard() throws {
        let server = makeServer(connectionMode: .standard, authMethod: .password)
        let data = try mutateJSON(server) { object in
            object["connectionMode"] = "tailscale"
        }

        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.connectionMode == .standard)
    }

    @Test
    func decodeLegacyCloudflareConnectionModeDefaultsToStandard() throws {
        let server = makeServer(connectionMode: .standard, authMethod: .password)
        let data = try mutateJSON(server) { object in
            object["connectionMode"] = "cloudflare"
        }

        let decoded = try JSONDecoder().decode(Server.self, from: data)
        #expect(decoded.connectionMode == .standard)
    }

    @Test
    func legacyCloudflareFieldsAreIgnoredByLocalPersistence() throws {
        let server = makeServer(connectionMode: .standard, authMethod: .password)
        let data = try mutateJSON(server) { object in
            object["connectionMode"] = "cloudflare"
            object["cloudflareAccessMode"] = "serviceToken"
            object["cloudflareTeamDomainOverride"] = "team.cloudflareaccess.com"
            object["cloudflareAppDomainOverride"] = "ssh.example.com"
        }

        let decoded = try JSONDecoder().decode(Server.self, from: data)
        let encoded = try JSONEncoder().encode(decoded)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(decoded.connectionMode == .standard)
        #expect(object["cloudflareAccessMode"] == nil)
        #expect(object["cloudflareTeamDomainOverride"] == nil)
        #expect(object["cloudflareAppDomainOverride"] == nil)
    }

    @Test
    func cloudKitDecodesLegacyTailscaleAndCloudflareModesAsStandard() throws {
        let tailscale = try #require(Self.cloudKitServer(connectionMode: "tailscale"))
        let cloudflare = try #require(Self.cloudKitServer(connectionMode: "cloudflare"))

        #expect(tailscale.connectionMode == .standard)
        #expect(cloudflare.connectionMode == .standard)
    }

    @Test
    func cloudKitDoesNotWriteLegacyCloudflareFields() throws {
        let server = try #require(Self.cloudKitServer(connectionMode: "cloudflare", includeCloudflareFields: true))
        let record = server.toRecord()

        #expect(server.connectionMode == .standard)
        #expect(record["cloudflareAccessMode"] == nil)
        #expect(record["cloudflareTeamDomainOverride"] == nil)
        #expect(record["cloudflareAppDomainOverride"] == nil)
    }

    @Test
    func moshPasswordSelectionPreservesPasswordCredentials() {
        let passwordCredentials = ServerFormCredentialBuilder.build(
            serverId: UUID(),
            transportSelection: .mosh,
            authMethod: .password,
            password: "secret",
            sshKey: "",
            sshPassphrase: "",
            sshPublicKey: ""
        )
        #expect(passwordCredentials.password == "secret")
        #expect(passwordCredentials.privateKey == nil)
    }

    @Test
    func moshKeySelectionPreservesKeyCredentials() {
        let keyCredentials = ServerFormCredentialBuilder.build(
            serverId: UUID(),
            transportSelection: .mosh,
            authMethod: .sshKeyWithPassphrase,
            password: "",
            sshKey: "PRIVATE_KEY",
            sshPassphrase: "phrase",
            sshPublicKey: "PUBLIC_KEY"
        )
        #expect(String(data: keyCredentials.privateKey ?? Data(), encoding: .utf8) == "PRIVATE_KEY")
        #expect(keyCredentials.passphrase == "phrase")
        #expect(String(data: keyCredentials.publicKey ?? Data(), encoding: .utf8) == "PUBLIC_KEY")
    }

    @Test
    func standardSelectionPreservesPasswordCredentials() {
        let credentials = ServerFormCredentialBuilder.build(
            serverId: UUID(),
            transportSelection: .standard,
            authMethod: .password,
            password: "ssh-password",
            sshKey: "",
            sshPassphrase: "",
            sshPublicKey: ""
        )

        #expect(credentials.password == "ssh-password")
        #expect(credentials.privateKey == nil)
    }

    private static func cloudKitServer(
        connectionMode: String,
        includeCloudflareFields: Bool = false
    ) -> Server? {
        let record = CKRecord(recordType: "Server", recordID: CKRecord.ID(recordName: UUID().uuidString))
        record["workspaceId"] = UUID().uuidString
        record["name"] = "Legacy Server"
        record["host"] = "ssh.example.com"
        record["port"] = 22
        record["username"] = "root"
        record["authMethod"] = AuthMethod.password.rawValue
        record["connectionMode"] = connectionMode
        if includeCloudflareFields {
            record["cloudflareAccessMode"] = "serviceToken"
            record["cloudflareTeamDomainOverride"] = "team.cloudflareaccess.com"
            record["cloudflareAppDomainOverride"] = "ssh.example.com"
        }
        return Server(from: record)
    }
}
