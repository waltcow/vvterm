import Foundation
import Testing
@testable import VVTerm

struct SSHExecStreamTests {
    @Test
    func boundedStreamRejectsWithoutDroppingAndAcceptsAfterConsumption() async throws {
        let stream = SSHExecByteStream(maxBufferedBytes: 4)

        #expect(await stream.offer(Data([1, 2, 3, 4])))
        #expect(await !stream.offer(Data([5])))

        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == Data([1, 2, 3, 4]))
        #expect(await stream.offer(Data([5])))
        #expect(try await iterator.next() == Data([5]))
    }

    @Test
    func boundedStreamDeliversBufferedBytesBeforeTerminalError() async throws {
        let stream = SSHExecByteStream(maxBufferedBytes: 8)
        #expect(await stream.offer(Data([1, 2])))
        await stream.finish(throwing: .remoteExit(status: 7))

        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == Data([1, 2]))
        await #expect(throws: SSHExecStreamFailure.remoteExit(status: 7)) {
            try await iterator.next()
        }
    }

    @Test
    func cancellingWaitingConsumerResumesItsContinuation() async {
        let stream = SSHExecByteStream(maxBufferedBytes: 8)
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await Task.yield()

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test
    func pendingWriteQueuePreservesOrderAcrossPartialWrites() throws {
        var queue = SSHExecPendingWriteQueue(maxPendingBytes: 8)
        let first = UUID()
        let second = UUID()

        try queue.enqueue(Data([1, 2, 3]), id: first)
        try queue.enqueue(Data([4, 5]), id: second)

        #expect(queue.current?.remainingData == Data([1, 2, 3]))
        #expect(try queue.didWrite(1) == nil)
        #expect(queue.current?.remainingData == Data([2, 3]))
        #expect(try queue.didWrite(2) == first)
        #expect(queue.current?.remainingData == Data([4, 5]))
        #expect(try queue.didWrite(2) == second)
        #expect(queue.isEmpty)
        #expect(queue.pendingByteCount == 0)
    }

    @Test
    func pendingWriteQueueEnforcesByteLimit() throws {
        var queue = SSHExecPendingWriteQueue(maxPendingBytes: 4)
        try queue.enqueue(Data([1, 2, 3]))

        #expect(throws: SSHExecPendingWriteQueue.QueueError.limitExceeded(limit: 4)) {
            try queue.enqueue(Data([4, 5]))
        }
        #expect(queue.pendingByteCount == 3)
    }

    @Test
    func removingPendingWriteKeepsRemainingOrderAndAccounting() throws {
        var queue = SSHExecPendingWriteQueue(maxPendingBytes: 8)
        let first = UUID()
        let second = UUID()
        try queue.enqueue(Data([1, 2, 3]), id: first)
        try queue.enqueue(Data([4, 5]), id: second)

        let removed = queue.remove(id: first)
        #expect(removed)
        #expect(queue.pendingByteCount == 2)
        #expect(queue.current?.id == second)
    }

    @Test
    func pendingWriteQueueReportsWhenCancellationWouldTruncateAFrame() throws {
        var queue = SSHExecPendingWriteQueue(maxPendingBytes: 8)
        let writeId = UUID()
        try queue.enqueue(Data([1, 2, 3]), id: writeId)

        #expect(!queue.hasStarted(id: writeId))
        _ = try queue.didWrite(1)
        #expect(queue.hasStarted(id: writeId))
    }
}
