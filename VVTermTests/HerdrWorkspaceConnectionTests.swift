import Foundation
import Testing
@testable import VVTerm

private actor FakeHerdrWorkspaceSSH: HerdrSSHExecuting {
    nonisolated let handle = SSHExecStreamHandle(
        id: UUID(),
        stdout: SSHExecByteStream(maxBufferedBytes: 64 * 1024),
        stderr: SSHExecByteStream(maxBufferedBytes: 8 * 1024)
    )
    private(set) var writes: [Data] = []
    private(set) var commands: [String] = []
    private(set) var finishedInput = false
    private(set) var closeCount = 0

    func executeResult(_ command: String, timeout: Duration?) async throws -> SSHExecResult {
        commands.append(command)
        return SSHExecResult(
            stdout: Data(#"{"client":{"version":"0.7.3","protocol":16,"binary":"herdr"},"server":{"running":true,"version":"0.7.3","protocol":16,"compatible":true}}"#.utf8),
            stderr: Data(),
            exitStatus: 0
        )
    }

    func startExecStream(command: String) async throws -> SSHExecStreamHandle {
        commands.append(command)
        return handle
    }

    func writeExecStream(_ data: Data, to streamId: UUID) async throws {
        #expect(streamId == handle.id)
        writes.append(data)
    }

    func finishExecStreamInput(_ streamId: UUID) async {
        #expect(streamId == handle.id)
        finishedInput = true
    }

    func closeExecStream(_ streamId: UUID) async {
        #expect(streamId == handle.id)
        closeCount += 1
    }

    func offerStdout(_ data: Data) async -> Bool {
        await handle.stdout.offer(data)
    }
}

struct HerdrWorkspaceConnectionTests {
    @Test
    func pumpsHelloWelcomeAnsiInputResizeAndDetach() async throws {
        let fake = FakeHerdrWorkspaceSSH()
        let transport = HerdrSSHTransport(
            ssh: fake,
            commandBuilder: HerdrRemoteCommandBuilder(sessionName: "vvterm")
        )
        let connection = try await transport.startWorkspaceConnection(cols: 80, rows: 24)

        #expect(await fake.commands == [
            "exec 'herdr' '--session' 'vvterm' 'status' '--json'",
            "exec 'herdr' '--session' 'vvterm' 'remote-client-bridge'",
        ])
        #expect(await fake.writes == [
            Data([9, 0, 0, 0, 0, 16, 80, 24, 0, 0, 1, 0, 0]),
        ])

        let inbound = Data([
            4, 0, 0, 0, 0, 16, 1, 0,
            10, 0, 0, 0, 2, 1, 120, 40, 1, 4, 0x1B, 0x5B, 0x32, 0x4A,
        ])
        #expect(await fake.offerStdout(inbound.prefix(5)))
        #expect(await fake.offerStdout(inbound.dropFirst(5)))

        #expect(try await connection.nextEvent() == .welcome(protocolVersion: 16))
        #expect(try await connection.nextEvent() == .ansi(
            sequence: 1,
            width: 120,
            height: 40,
            full: true,
            bytes: Data([0x1B, 0x5B, 0x32, 0x4A])
        ))

        try await connection.sendInput(Data([0, 0xFF]))
        try await connection.resize(cols: 120, rows: 40)
        try await connection.detach()
        try await connection.detach()

        #expect(await fake.writes.suffix(3) == [
            Data([4, 0, 0, 0, 1, 2, 0, 0xFF]),
            Data([5, 0, 0, 0, 3, 120, 40, 0, 0]),
            Data([1, 0, 0, 0, 4]),
        ])
        #expect(await fake.finishedInput)
        await #expect(throws: HerdrWorkspaceConnectionError.detached) {
            try await connection.sendInput(Data([1]))
        }

        await connection.close()
        await connection.close()
        #expect(await fake.closeCount == 1)
    }
}
