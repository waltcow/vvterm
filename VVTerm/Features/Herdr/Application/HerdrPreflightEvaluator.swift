import Foundation

nonisolated enum HerdrPreflightResult: Equatable, Sendable {
    case compatible
    case binaryMissing
    case runtimeUnavailable
    case bridgeUnavailable
    case versionMismatch(client: String, remote: String)
    case protocolMismatch(client: Int, remote: Int)
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
        guard status.client.version == expectedVersion else {
            return .versionMismatch(client: expectedVersion, remote: status.client.version)
        }
        guard status.client.protocolVersion == expectedProtocol else {
            return .protocolMismatch(client: expectedProtocol, remote: status.client.protocolVersion)
        }
        guard status.server.running else {
            return .runtimeUnavailable
        }
        guard let serverVersion = status.server.version else {
            return .invalidStatus
        }
        guard serverVersion == expectedVersion else {
            return .versionMismatch(client: expectedVersion, remote: serverVersion)
        }
        guard let serverProtocol = status.server.protocolVersion else {
            return .invalidStatus
        }
        guard serverProtocol == expectedProtocol else {
            return .protocolMismatch(client: expectedProtocol, remote: serverProtocol)
        }
        guard status.server.compatible != false else {
            return .protocolMismatch(client: expectedProtocol, remote: serverProtocol)
        }
        return .compatible
    }
}
