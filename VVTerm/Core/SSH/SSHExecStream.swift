import Foundation

nonisolated struct SSHExecResult: Equatable, Sendable {
    let stdout: Data
    let stderr: Data
    let exitStatus: Int32
}

nonisolated struct SSHExecStreamHandle: Sendable {
    let id: UUID
    let stdout: SSHExecByteStream
    let stderr: SSHExecByteStream
}

nonisolated enum SSHExecStreamFailure: Error, Equatable, Sendable {
    case bufferLimitExceeded(limit: Int)
    case remoteExit(status: Int32)
    case transport(String)
}

/// A single-consumer, bounded async byte stream.
///
/// Producers use `offer(_:)` instead of an unbounded `AsyncStream` continuation.
/// A `false` result means the producer must retain the chunk and pause reading
/// until a later offer succeeds. No bytes are discarded when the buffer is full.
nonisolated struct SSHExecByteStream: AsyncSequence, Sendable {
    typealias Element = Data

    struct AsyncIterator: AsyncIteratorProtocol {
        fileprivate let buffer: SSHExecByteStreamBuffer

        mutating func next() async throws -> Data? {
            try await buffer.next()
        }
    }

    fileprivate let buffer: SSHExecByteStreamBuffer

    init(maxBufferedBytes: Int) {
        buffer = SSHExecByteStreamBuffer(maxBufferedBytes: maxBufferedBytes)
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(buffer: buffer)
    }

    @discardableResult
    func offer(_ data: Data) async -> Bool {
        await buffer.offer(data)
    }

    func finish(throwing error: SSHExecStreamFailure? = nil) async {
        await buffer.finish(throwing: error)
    }

    var bufferedByteCount: Int {
        get async { await buffer.bufferedByteCount }
    }
}

private actor SSHExecByteStreamBuffer {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Data?, Error>
    }

    private enum TerminalState {
        case open
        case finished
        case failed(SSHExecStreamFailure)
    }

    private let maxBufferedBytes: Int
    private var chunks: [Data] = []
    private var head = 0
    private(set) var bufferedByteCount = 0
    private var waiter: Waiter?
    private var terminalState: TerminalState = .open

    init(maxBufferedBytes: Int) {
        precondition(maxBufferedBytes > 0)
        self.maxBufferedBytes = maxBufferedBytes
    }

    func offer(_ data: Data) -> Bool {
        guard case .open = terminalState else { return false }
        guard !data.isEmpty else { return true }

        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: data)
            return true
        }

        guard data.count <= maxBufferedBytes - bufferedByteCount else {
            return false
        }

        chunks.append(data)
        bufferedByteCount += data.count
        return true
    }

    func next() async throws -> Data? {
        try Task.checkCancellation()

        if head < chunks.count {
            let chunk = chunks[head]
            head += 1
            bufferedByteCount -= chunk.count
            compactStorageIfNeeded()
            return chunk
        }

        switch terminalState {
        case .open:
            let waiterId = UUID()
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    precondition(waiter == nil, "SSHExecByteStream supports one consumer")
                    waiter = Waiter(id: waiterId, continuation: continuation)
                }
            }, onCancel: { [weak self] in
                Task {
                    await self?.cancelWaiter(waiterId)
                }
            })
        case .finished:
            return nil
        case .failed(let error):
            throw error
        }
    }

    func finish(throwing error: SSHExecStreamFailure?) {
        guard case .open = terminalState else { return }
        terminalState = error.map(TerminalState.failed) ?? .finished

        guard head >= chunks.count, let waiter else { return }
        self.waiter = nil
        switch terminalState {
        case .open:
            break
        case .finished:
            waiter.continuation.resume(returning: nil)
        case .failed(let error):
            waiter.continuation.resume(throwing: error)
        }
    }

    private func cancelWaiter(_ waiterId: UUID) {
        guard let waiter, waiter.id == waiterId else { return }
        self.waiter = nil
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func compactStorageIfNeeded() {
        guard head > 32, head * 2 >= chunks.count else { return }
        chunks.removeFirst(head)
        head = 0
    }
}

nonisolated struct SSHExecPendingWriteQueue: Sendable {
    struct Entry: Sendable {
        let id: UUID
        let data: Data
        fileprivate var offset: Int

        var remainingData: Data {
            data.subdata(in: offset..<data.count)
        }
    }

    enum QueueError: Error, Equatable, Sendable {
        case limitExceeded(limit: Int)
        case invalidWriteCount(Int)
    }

    let maxPendingBytes: Int
    private var entries: [Entry] = []
    private var head = 0
    private(set) var pendingByteCount = 0

    init(maxPendingBytes: Int) {
        precondition(maxPendingBytes > 0)
        self.maxPendingBytes = maxPendingBytes
    }

    var isEmpty: Bool {
        head >= entries.count
    }

    @discardableResult
    mutating func enqueue(_ data: Data, id: UUID = UUID()) throws -> UUID {
        guard data.count <= maxPendingBytes - pendingByteCount else {
            throw QueueError.limitExceeded(limit: maxPendingBytes)
        }
        guard !data.isEmpty else { return id }

        entries.append(Entry(id: id, data: data, offset: 0))
        pendingByteCount += data.count
        return id
    }

    var current: Entry? {
        guard head < entries.count else { return nil }
        return entries[head]
    }

    func hasStarted(id: UUID) -> Bool {
        guard let entry = entries.indices.dropFirst(head)
            .map({ entries[$0] })
            .first(where: { $0.id == id }) else {
            return false
        }
        return entry.offset > 0
    }

    mutating func didWrite(_ count: Int) throws -> UUID? {
        guard var entry = current, count > 0, count <= entry.data.count - entry.offset else {
            throw QueueError.invalidWriteCount(count)
        }

        entry.offset += count
        pendingByteCount -= count
        if entry.offset == entry.data.count {
            head += 1
            compactStorageIfNeeded()
            return entry.id
        }

        entries[head] = entry
        return nil
    }

    mutating func remove(id: UUID) -> Bool {
        guard let index = entries.indices.dropFirst(head).first(where: { entries[$0].id == id }) else {
            return false
        }
        pendingByteCount -= entries[index].data.count - entries[index].offset
        entries.remove(at: index)
        compactStorageIfNeeded()
        return true
    }

    mutating func removeAll() -> [UUID] {
        let ids = entries.dropFirst(head).map(\.id)
        entries.removeAll(keepingCapacity: false)
        head = 0
        pendingByteCount = 0
        return ids
    }

    private mutating func compactStorageIfNeeded() {
        guard head > 32, head * 2 >= entries.count else { return }
        entries.removeFirst(head)
        head = 0
    }
}
