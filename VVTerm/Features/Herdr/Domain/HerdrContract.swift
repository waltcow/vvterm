import Foundation

nonisolated enum HerdrPinnedContract {
    static let sourceTag = "v0.7.3"
    static let sourceRevision = "d0111c9f9022e0ec26d8f03236a91b026b567d45"
    static let binaryVersion = "0.7.3"
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

nonisolated enum HerdrConnectionFailure: Error, Equatable, Sendable {
    case binaryMissing
    case runtimeUnavailable
    case bridgeUnavailable
    case versionMismatch(client: String, remote: String)
    case protocolMismatch(client: Int, remote: Int)
    case invalidStatus
    case sshDisconnected
    case protocolError(String)
    case runtimeClosed(String?)
}

nonisolated enum HerdrConnectionState: Equatable, Sendable {
    case idle
    case preflighting
    case connecting
    case handshaking
    case attached
    case reconnecting
    case failed(HerdrConnectionFailure)
}
