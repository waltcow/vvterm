import Foundation
import Testing
import XCTest
@testable import VVTerm

nonisolated enum SSHExecStreamBinaryEchoFixture {
    enum FixtureError: Error, Equatable {
        case invalidFrameHeader
        case truncatedFrame(expected: Int, actual: Int)
        case payloadTooLarge(Int)
    }

    static let readyDiagnostic = "VVTERM_EXEC_STREAM_FIXTURE_READY"
    static let eofDiagnostic = "VVTERM_EXEC_STREAM_FIXTURE_EOF"
    static let maximumPayloadBytes = 2 * 1024 * 1024

    static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maximumPayloadBytes else {
            throw FixtureError.payloadTooLarge(payload.count)
        }

        let length = UInt32(payload.count)
        var frame = Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ])
        frame.append(payload)
        return frame
    }

    static func decode(_ data: Data) throws -> [Data] {
        var frames: [Data] = []
        var offset = 0

        while offset < data.count {
            guard data.count - offset >= 4 else {
                throw FixtureError.invalidFrameHeader
            }

            let length = Int(data[offset]) << 24
                | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
            offset += 4

            guard length <= maximumPayloadBytes else {
                throw FixtureError.payloadTooLarge(length)
            }
            guard data.count - offset >= length else {
                throw FixtureError.truncatedFrame(
                    expected: length,
                    actual: data.count - offset
                )
            }

            frames.append(data.subdata(in: offset..<(offset + length)))
            offset += length
        }

        return frames
    }

    static func remoteCommand(pythonExecutable: String = "python3") -> String {
        let source = #"""
import struct
import sys

stdin = sys.stdin.buffer
stdout = sys.stdout.buffer
stderr = sys.stderr

def read_exact(count):
    chunks = []
    remaining = count
    while remaining:
        chunk = stdin.read(remaining)
        if not chunk:
            if chunks:
                raise EOFError("truncated frame")
            return None
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)

stderr.write("VVTERM_EXEC_STREAM_FIXTURE_READY\n")
stderr.flush()

while True:
    header = read_exact(4)
    if header is None:
        break
    length = struct.unpack(">I", header)[0]
    if length > 2097152:
        raise ValueError("payload too large")
    payload = read_exact(length)
    if payload is None:
        raise EOFError("truncated payload")
    stdout.write(header)
    stdout.write(payload)
    stdout.flush()

stderr.write("VVTERM_EXEC_STREAM_FIXTURE_EOF\n")
stderr.flush()
"""#
        return "\(posixQuote(pythonExecutable)) -u -c \(posixQuote(source))"
    }

    private static func posixQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

struct SSHExecStreamBinaryEchoFixtureTests {
    @Test
    func frameCodecPreservesBinaryPayloadsAndZeroLengthFrames() throws {
        let payloads = [
            Data(),
            Data([0]),
            Data([0, 10, 13, 27, 255]),
            Data((0..<32_768).map { UInt8($0 % 251) })
        ]
        let encoded = try payloads.reduce(into: Data()) { result, payload in
            result.append(try SSHExecStreamBinaryEchoFixture.encode(payload))
        }

        #expect(try SSHExecStreamBinaryEchoFixture.decode(encoded) == payloads)
    }

    @Test
    func frameCodecRejectsTruncatedAndOversizedPayloads() throws {
        #expect(throws: SSHExecStreamBinaryEchoFixture.FixtureError.invalidFrameHeader) {
            try SSHExecStreamBinaryEchoFixture.decode(Data([0, 0, 0]))
        }
        #expect(throws: SSHExecStreamBinaryEchoFixture.FixtureError.truncatedFrame(expected: 2, actual: 1)) {
            try SSHExecStreamBinaryEchoFixture.decode(Data([0, 0, 0, 2, 1]))
        }
        #expect(throws: SSHExecStreamBinaryEchoFixture.FixtureError.payloadTooLarge(2_097_153)) {
            try SSHExecStreamBinaryEchoFixture.decode(Data([0, 32, 0, 1]))
        }
    }

    @Test
    func remoteCommandKeepsProtocolOnStdoutAndDiagnosticsOnStderr() {
        let command = SSHExecStreamBinaryEchoFixture.remoteCommand()

        #expect(command.hasPrefix("'python3' -u -c '"))
        #expect(command.contains("sys.stdout.buffer"))
        #expect(command.contains("sys.stderr"))
        #expect(command.contains(SSHExecStreamBinaryEchoFixture.readyDiagnostic))
        #expect(command.contains(SSHExecStreamBinaryEchoFixture.eofDiagnostic))
    }
}

final class SSHExecStreamIntegrationTests: XCTestCase {
    func testBinaryEchoOverLongLivedExecStream() async throws {
        guard let configuration = try SSHIntegrationFixtureConfiguration.load(
            displayName: "SSH Exec Stream Fixture"
        ) else {
            throw XCTSkip("Set VVTERM_SSH_FIXTURE_HOST and VVTERM_SSH_FIXTURE_USER to run the SSH integration fixture")
        }
        let pythonExecutable = ProcessInfo.processInfo.environment["VVTERM_SSH_FIXTURE_PYTHON"] ?? "python3"

        let payloads = makePayloads()
        let client = SSHClient()
        do {
            _ = try await client.connect(
                to: configuration.server,
                credentials: configuration.credentials
            )
            let handle = try await client.startExecStream(
                command: SSHExecStreamBinaryEchoFixture.remoteCommand(
                    pythonExecutable: pythonExecutable
                )
            )
            let stdoutTask = Task { try await Self.collect(handle.stdout) }
            let stderrTask = Task { try await Self.collect(handle.stderr) }
            let concurrentExecTask = Task {
                try await client.executeResult(
                    "printf VVTERM_EXEC_STREAM_CONCURRENT; printf VVTERM_EXEC_STREAM_STDERR >&2; exit 23"
                )
            }

            for payload in payloads {
                try await client.writeExecStream(
                    try SSHExecStreamBinaryEchoFixture.encode(payload),
                    to: handle.id
                )
            }
            await client.finishExecStreamInput(handle.id)

            let stdout = try await Self.withTimeout(.seconds(60)) {
                try await stdoutTask.value
            }
            let stderr = try await Self.withTimeout(.seconds(60)) {
                try await stderrTask.value
            }
            let concurrentExecResult = try await Self.withTimeout(.seconds(60)) {
                try await concurrentExecTask.value
            }
            let echoedPayloads = try SSHExecStreamBinaryEchoFixture.decode(stdout)
            let diagnostics = String(decoding: stderr, as: UTF8.self)

            XCTAssertEqual(echoedPayloads, payloads)
            XCTAssertTrue(diagnostics.contains(SSHExecStreamBinaryEchoFixture.readyDiagnostic))
            XCTAssertTrue(diagnostics.contains(SSHExecStreamBinaryEchoFixture.eofDiagnostic))
            XCTAssertFalse(stdout.contains(Data(SSHExecStreamBinaryEchoFixture.readyDiagnostic.utf8)))
            XCTAssertEqual(String(decoding: concurrentExecResult.stdout, as: UTF8.self), "VVTERM_EXEC_STREAM_CONCURRENT")
            XCTAssertEqual(String(decoding: concurrentExecResult.stderr, as: UTF8.self), "VVTERM_EXEC_STREAM_STDERR")
            XCTAssertEqual(concurrentExecResult.exitStatus, 23)
        } catch {
            await client.disconnect()
            throw error
        }
        await client.disconnect()
    }

    private func makePayloads() -> [Data] {
        var payloads = [
            Data(),
            Data([0]),
            Data([0, 10, 13, 27, 255]),
            Data((0..<32_768).map { UInt8($0 % 251) }),
            Data((0..<1_048_576).map { UInt8($0 % 253) })
        ]
        payloads.append(contentsOf: (0..<256).map { index in
            Data([UInt8(index), 0, 10, 13, UInt8(255 - index)])
        })
        return payloads
    }

    private static func collect(_ stream: SSHExecByteStream) async throws -> Data {
        var result = Data()
        for try await chunk in stream {
            result.append(chunk)
        }
        return result
    }

    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw SSHError.timeout
            }
            guard let result = try await group.next() else {
                throw SSHError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
