import Foundation

nonisolated enum HerdrPinnedContract {
    static let sourceTag = "v0.7.4"
    static let sourceRevision = "50aaa2ec046ee26ff407c20f49de496f522512a8"
    static let binaryVersion = "0.7.4"
    static let protocolVersion = 16

    static let maxProtocolFrameBytes = 2 * 1024 * 1024
    static let maxGraphicsProtocolFrameBytes = 32 * 1024 * 1024
    static let maxTerminalSessionLineBytes = 48 * 1024 * 1024
}

nonisolated struct HerdrRuntimeReference: Hashable, Sendable {
    static let defaultSessionName = "default"

    let serverId: UUID
    let sessionName: String

    init(
        serverId: UUID,
        sessionName: String = Self.defaultSessionName
    ) {
        self.serverId = serverId
        self.sessionName = sessionName
    }
}

nonisolated enum HerdrAttachmentMode: Hashable, Sendable {
    case workspace
    case observe(target: String)
    case control(target: String, takeover: Bool)
}

nonisolated struct HerdrAttachment: Identifiable, Hashable, Sendable {
    let id: UUID
    let runtime: HerdrRuntimeReference
    let mode: HerdrAttachmentMode
}

nonisolated enum HerdrSuspensionReason: Equatable, Sendable {
    case background
    case offline
}

nonisolated struct HerdrBinaryVersionWarning: Equatable, Sendable {
    let testedVersion: String
    let clientVersion: String
    let serverVersion: String
    let protocolVersion: Int

    var message: String {
        if clientVersion == serverVersion {
            return "Herdr \(clientVersion) uses compatible protocol \(protocolVersion). VVTerm was tested with Herdr \(testedVersion)."
        }
        return "Herdr client \(clientVersion) and server \(serverVersion) use compatible protocol \(protocolVersion). VVTerm was tested with Herdr \(testedVersion)."
    }
}

nonisolated enum HerdrFailure: Error, Equatable, Sendable {
    case binaryMissing
    case runtimeUnavailable(sessionName: String)
    case bridgeUnavailable
    case protocolMismatch(client: Int, remote: Int)
    case runtimeIncompatible(clientVersion: String, serverVersion: String)
    case invalidStatus
    case authenticationFailed
    case hostKeyVerificationFailed
    case sshInterrupted(String)
    case runtimeStopped(String?)
    case protocolError(String)
    case unknown(String)

    var message: String {
        switch self {
        case .binaryMissing:
            return "Herdr 0.7.4 is not installed on this server."
        case .runtimeUnavailable(let sessionName):
            if sessionName == HerdrRuntimeReference.defaultSessionName {
                return "Start the default Herdr session on the server, then retry."
            }
            return "Start the named Herdr session '\(sessionName)' on the server, then retry."
        case .bridgeUnavailable:
            return "This Herdr installation does not provide the remote client bridge."
        case .protocolMismatch(let client, let remote):
            return "Herdr protocol mismatch: VVTerm expects \(client), server has \(remote)."
        case .runtimeIncompatible(let clientVersion, let serverVersion):
            return "Herdr reports client \(clientVersion) and server \(serverVersion) are incompatible."
        case .invalidStatus:
            return "Herdr returned an invalid status response."
        case .authenticationFailed:
            return "SSH authentication failed."
        case .hostKeyVerificationFailed:
            return "SSH host verification failed. Check the saved host fingerprint."
        case .sshInterrupted(let message):
            return message.isEmpty ? "The SSH connection was interrupted." : message
        case .runtimeStopped(let reason):
            return reason ?? "The remote Herdr runtime stopped."
        case .protocolError(let message), .unknown(let message):
            return message
        }
    }

    var allowsAutomaticReconnect: Bool {
        if case .sshInterrupted = self {
            return true
        }
        return false
    }
}

nonisolated enum HerdrConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case handshaking
    case attached(versionWarning: HerdrBinaryVersionWarning?)
    case suspended(HerdrSuspensionReason)
    case reconnecting(attempt: Int)
    case failed(HerdrFailure)

    var isAttached: Bool {
        if case .attached = self {
            return true
        }
        return false
    }
}
