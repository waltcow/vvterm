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
    let serverId: UUID
    let sessionName: String
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

nonisolated enum HerdrFailure: Error, Equatable, Sendable {
    case binaryMissing
    case runtimeUnavailable(sessionName: String)
    case bridgeUnavailable
    case versionMismatch(client: String, remote: String)
    case protocolMismatch(client: Int, remote: Int)
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
            return "Start the named Herdr session '\(sessionName)' on the server, then retry."
        case .bridgeUnavailable:
            return "This Herdr installation does not provide the remote client bridge."
        case .versionMismatch(let client, let remote):
            return "Herdr version mismatch: VVTerm expects \(client), server has \(remote)."
        case .protocolMismatch(let client, let remote):
            return "Herdr protocol mismatch: VVTerm expects \(client), server has \(remote)."
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
    case attached
    case suspended(HerdrSuspensionReason)
    case reconnecting(attempt: Int)
    case failed(HerdrFailure)
}
