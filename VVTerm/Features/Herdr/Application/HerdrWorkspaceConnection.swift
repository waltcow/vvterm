import Foundation

nonisolated enum HerdrWorkspaceConnectionError: Error, Equatable, Sendable {
    case detached
    case closed
    case concurrentRead
}
actor HerdrWorkspaceConnection {
    private let ssh: any HerdrSSHExecuting
    private let handle: SSHExecStreamHandle
    private let adapter: HerdrClientKitAdapter
    private var pendingEvents: ArraySlice<HerdrClientKitEvent> = []
    private var detached = false
    private var closed = false
    private var eventReadInProgress = false
    private var diagnosticReadInProgress = false

    init(
        ssh: any HerdrSSHExecuting,
        handle: SSHExecStreamHandle,
        adapter: HerdrClientKitAdapter
    ) {
        self.ssh = ssh
        self.handle = handle
        self.adapter = adapter
    }

    var id: UUID { handle.id }

    func bootstrap() async throws {
        try await flushOutbound()
    }

    func nextEvent() async throws -> HerdrClientKitEvent? {
        guard !eventReadInProgress else {
            throw HerdrWorkspaceConnectionError.concurrentRead
        }
        eventReadInProgress = true
        defer { eventReadInProgress = false }

        if let event = dequeueEvent() {
            return event
        }
        guard !closed else { return nil }

        while true {
            var iterator = handle.stdout.makeAsyncIterator()
            guard let chunk = try await iterator.next() else {
                return nil
            }
            try await adapter.feed(chunk)
            try await flushOutbound()
            while let event = try await adapter.nextEvent() {
                pendingEvents.append(event)
            }
            if let event = dequeueEvent() {
                return event
            }
        }
    }

    func nextDiagnosticChunk() async throws -> Data? {
        guard !diagnosticReadInProgress else {
            throw HerdrWorkspaceConnectionError.concurrentRead
        }
        diagnosticReadInProgress = true
        defer { diagnosticReadInProgress = false }

        guard !closed else { return nil }
        var iterator = handle.stderr.makeAsyncIterator()
        return try await iterator.next()
    }

    func sendInput(_ data: Data) async throws {
        try requireWritable()
        try await adapter.sendInput(data)
        try await flushOutbound()
    }

    func resize(cols: UInt16, rows: UInt16) async throws {
        try requireWritable()
        try await adapter.resize(cols: cols, rows: rows)
        try await flushOutbound()
    }

    func scroll(direction: HerdrScrollDirection, lines: UInt16) async throws {
        try requireWritable()
        try await adapter.scroll(direction: direction, lines: lines)
        try await flushOutbound()
    }

    func detach() async throws {
        guard !closed else {
            throw HerdrWorkspaceConnectionError.closed
        }
        guard !detached else { return }
        try await adapter.detach()
        detached = true
        try await flushOutbound()
        await ssh.finishExecStreamInput(handle.id)
    }

    func close() async {
        guard !closed else { return }
        closed = true
        await ssh.closeExecStream(handle.id)
    }

    private func flushOutbound() async throws {
        for frame in try await adapter.drainOutbound() {
            try await ssh.writeExecStream(frame, to: handle.id)
        }
    }

    private func requireWritable() throws {
        if closed {
            throw HerdrWorkspaceConnectionError.closed
        }
        if detached {
            throw HerdrWorkspaceConnectionError.detached
        }
    }

    private func dequeueEvent() -> HerdrClientKitEvent? {
        guard let event = pendingEvents.first else { return nil }
        pendingEvents = pendingEvents.dropFirst()
        return event
    }
}
