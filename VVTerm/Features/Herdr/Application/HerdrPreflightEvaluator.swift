import Foundation

nonisolated enum HerdrPreflightResult: Equatable, Sendable {
    case compatible(versionWarning: HerdrBinaryVersionWarning?)
    case binaryMissing
    case runtimeUnavailable
    case bridgeUnavailable
    case protocolMismatch(client: Int, remote: Int)
    case runtimeIncompatible(clientVersion: String, serverVersion: String)
    case invalidStatus
}

nonisolated struct HerdrPreflightStatus: Decodable, Equatable, Sendable {
    struct Client: Decodable, Equatable, Sendable {
        let version: String
        let protocolVersion: Int
        let binary: String

        private enum CodingKeys: String, CodingKey {
            case version
            case protocolVersion = "protocol"
            case binary
        }
    }

    struct Server: Decodable, Equatable, Sendable {
        let running: Bool
        let version: String?
        let protocolVersion: Int?
        let compatible: Bool?

        private enum CodingKeys: String, CodingKey {
            case running
            case version
            case protocolVersion = "protocol"
            case compatible
        }
    }

    let client: Client
    let server: Server
}

nonisolated struct HerdrPreflightEvaluator: Sendable {
    let expectedVersion: String
    let expectedProtocol: Int

    init(
        expectedVersion: String = HerdrPinnedContract.binaryVersion,
        expectedProtocol: Int = HerdrPinnedContract.protocolVersion
    ) {
        self.expectedVersion = expectedVersion
        self.expectedProtocol = expectedProtocol
    }

    func evaluate(stdout: Data) -> HerdrPreflightResult {
        guard let status = try? JSONDecoder().decode(HerdrPreflightStatus.self, from: stdout) else {
            return .invalidStatus
        }
        return evaluate(status: status)
    }

    func evaluate(status: HerdrPreflightStatus) -> HerdrPreflightResult {
        guard status.client.protocolVersion == expectedProtocol else {
            return .protocolMismatch(client: expectedProtocol, remote: status.client.protocolVersion)
        }
        guard status.server.running else {
            return .runtimeUnavailable
        }
        guard let serverVersion = status.server.version else {
            return .invalidStatus
        }
        guard let serverProtocol = status.server.protocolVersion else {
            return .invalidStatus
        }
        guard serverProtocol == expectedProtocol else {
            return .protocolMismatch(client: expectedProtocol, remote: serverProtocol)
        }
        guard status.server.compatible != false else {
            return .runtimeIncompatible(
                clientVersion: status.client.version,
                serverVersion: serverVersion
            )
        }

        let versionWarning: HerdrBinaryVersionWarning?
        if status.client.version != expectedVersion || serverVersion != expectedVersion {
            versionWarning = HerdrBinaryVersionWarning(
                testedVersion: expectedVersion,
                clientVersion: status.client.version,
                serverVersion: serverVersion,
                protocolVersion: expectedProtocol
            )
        } else {
            versionWarning = nil
        }
        return .compatible(versionWarning: versionWarning)
    }
}
