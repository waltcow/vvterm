import Foundation

nonisolated protocol HerdrSSHExecuting: Sendable {
    func executeResult(_ command: String, timeout: Duration?) async throws -> SSHExecResult
    func startExecStream(command: String) async throws -> SSHExecStreamHandle
    func writeExecStream(_ data: Data, to streamId: UUID) async throws
    func finishExecStreamInput(_ streamId: UUID) async
    func closeExecStream(_ streamId: UUID) async
}

extension SSHClient: HerdrSSHExecuting {}

nonisolated enum HerdrSSHTransportError: Error, Equatable, Sendable {
    case invalidDimensions
    case readOnlySession
    case inputReleased
    case connectionClosed
    case concurrentRead
    case workspaceRequiresClientKit
    case preflightFailed(HerdrPreflightResult)
}

nonisolated struct HerdrSSHTransport: Sendable {
    private let ssh: any HerdrSSHExecuting
    let commandBuilder: HerdrRemoteCommandBuilder

    init(ssh: any HerdrSSHExecuting, commandBuilder: HerdrRemoteCommandBuilder) {
        self.ssh = ssh
        self.commandBuilder = commandBuilder
    }

    func preflight() async throws -> HerdrPreflightResult {
        let service = HerdrPreflightService(commandBuilder: commandBuilder)
        return try await service.run { command in
            try await ssh.executeResult(command, timeout: .seconds(20))
        }
    }

    func startWorkspaceBridge() async throws -> SSHExecStreamHandle {
        try await ssh.startExecStream(command: commandBuilder.workspaceBridge())
    }

    func startWorkspaceConnection(
        cols: UInt16,
        rows: UInt16
    ) async throws -> HerdrWorkspaceConnection {
        guard cols > 0, rows > 0 else {
            throw HerdrSSHTransportError.invalidDimensions
        }
        let preflightResult = try await preflight()
        guard case .compatible(let versionWarning) = preflightResult else {
            throw HerdrSSHTransportError.preflightFailed(preflightResult)
        }
        let adapter = try HerdrClientKitAdapter(cols: cols, rows: rows)
        let handle = try await startWorkspaceBridge()
        let connection = HerdrWorkspaceConnection(
            ssh: ssh,
            handle: handle,
            adapter: adapter,
            versionWarning: versionWarning
        )
        do {
            try await connection.bootstrap()
            return connection
        } catch {
            await ssh.closeExecStream(handle.id)
            throw error
        }
    }

    func startTerminalSession(
        mode: HerdrAttachmentMode,
        cols: UInt16,
        rows: UInt16
    ) async throws -> HerdrTerminalSessionConnection {
        guard cols > 0, rows > 0 else {
            throw HerdrSSHTransportError.invalidDimensions
        }

        let command: String
        let writable: Bool
        switch mode {
        case .workspace:
            throw HerdrSSHTransportError.workspaceRequiresClientKit
        case .observe(let target):
            command = commandBuilder.terminalObserve(target: target, cols: cols, rows: rows)
            writable = false
        case let .control(target, takeover):
            command = commandBuilder.terminalControl(
                target: target,
                takeover: takeover,
                cols: cols,
                rows: rows
            )
            writable = true
        }

        let handle = try await ssh.startExecStream(command: command)
        return HerdrTerminalSessionConnection(ssh: ssh, handle: handle, writable: writable)
    }
}

actor HerdrTerminalSessionConnection {
    private let ssh: any HerdrSSHExecuting
    private let handle: SSHExecStreamHandle
    private let writable: Bool
    private var decoder = HerdrTerminalSessionDecoder()
    private var pendingEvents: ArraySlice<HerdrTerminalSessionEvent> = []
    private var receivedClosedEvent = false
    private var inputReleased = false
    private var connectionClosed = false
    private var eventReadInProgress = false
    private var diagnosticReadInProgress = false

    init(ssh: any HerdrSSHExecuting, handle: SSHExecStreamHandle, writable: Bool) {
        self.ssh = ssh
        self.handle = handle
        self.writable = writable
    }

    var id: UUID { handle.id }

    func nextEvent() async throws -> HerdrTerminalSessionEvent? {
        guard !eventReadInProgress else {
            throw HerdrSSHTransportError.concurrentRead
        }
        eventReadInProgress = true
        defer { eventReadInProgress = false }

        if let event = dequeueEvent() {
            return event
        }
        if receivedClosedEvent || connectionClosed {
            return nil
        }

        while true {
            var iterator = handle.stdout.makeAsyncIterator()
            guard let chunk = try await iterator.next() else {
                return nil
            }
            let decoded = try decoder.append(chunk)
            guard !decoded.isEmpty else { continue }

            if let closedIndex = decoded.firstIndex(where: { event in
                if case .closed = event { return true }
                return false
            }) {
                pendingEvents.append(contentsOf: decoded[...closedIndex])
                receivedClosedEvent = true
            } else {
                pendingEvents.append(contentsOf: decoded)
            }
            return dequeueEvent()
        }
    }

    func nextDiagnosticChunk() async throws -> Data? {
        guard !diagnosticReadInProgress else {
            throw HerdrSSHTransportError.concurrentRead
        }
        diagnosticReadInProgress = true
        defer { diagnosticReadInProgress = false }

        guard !connectionClosed else { return nil }
        var iterator = handle.stderr.makeAsyncIterator()
        return try await iterator.next()
    }

    func send(_ command: HerdrTerminalControlCommand) async throws {
        guard !connectionClosed else {
            throw HerdrSSHTransportError.connectionClosed
        }
        guard writable else {
            throw HerdrSSHTransportError.readOnlySession
        }
        guard !inputReleased else {
            throw HerdrSSHTransportError.inputReleased
        }
        try await ssh.writeExecStream(
            HerdrTerminalSessionEncoder.encode(command),
            to: handle.id
        )
    }

    func release() async throws {
        guard !connectionClosed else {
            throw HerdrSSHTransportError.connectionClosed
        }
        guard writable else {
            throw HerdrSSHTransportError.readOnlySession
        }
        guard !inputReleased else { return }

        try await ssh.writeExecStream(
            HerdrTerminalSessionEncoder.encode(.release),
            to: handle.id
        )
        inputReleased = true
        await ssh.finishExecStreamInput(handle.id)
    }

    func close() async {
        guard !connectionClosed else { return }
        connectionClosed = true
        await ssh.closeExecStream(handle.id)
    }

    private func dequeueEvent() -> HerdrTerminalSessionEvent? {
        guard let event = pendingEvents.first else { return nil }
        pendingEvents = pendingEvents.dropFirst()
        return event
    }
}
