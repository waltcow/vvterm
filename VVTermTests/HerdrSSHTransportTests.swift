import Foundation
import Testing
@testable import VVTerm

private actor FakeHerdrSSHExecutor: HerdrSSHExecuting {
    nonisolated let handle: SSHExecStreamHandle
    var result: SSHExecResult
    private(set) var executedCommands: [String] = []
    private(set) var startedCommands: [String] = []
    private(set) var writes: [(Data, UUID)] = []
    private(set) var finishedInputs: [UUID] = []
    private(set) var closedStreams: [UUID] = []

    init(result: SSHExecResult) {
        handle = SSHExecStreamHandle(
            id: UUID(),
            stdout: SSHExecByteStream(maxBufferedBytes: 64 * 1024),
            stderr: SSHExecByteStream(maxBufferedBytes: 8 * 1024)
        )
        self.result = result
    }

    func executeResult(_ command: String, timeout: Duration?) async throws -> SSHExecResult {
        executedCommands.append(command)
        return result
    }

    func startExecStream(command: String) async throws -> SSHExecStreamHandle {
        startedCommands.append(command)
        return handle
    }

    func writeExecStream(_ data: Data, to streamId: UUID) async throws {
        writes.append((data, streamId))
    }

    func finishExecStreamInput(_ streamId: UUID) async {
        finishedInputs.append(streamId)
    }

    func closeExecStream(_ streamId: UUID) async {
        closedStreams.append(streamId)
    }

    func offerStdout(_ data: Data) async -> Bool {
        await handle.stdout.offer(data)
    }

    func offerStderr(_ data: Data) async -> Bool {
        await handle.stderr.offer(data)
    }

    func finishOutput() async {
        await handle.stdout.finish()
        await handle.stderr.finish()
    }
}

struct HerdrSSHTransportTests {
    private static let compatibleStatus = Data(#"{"client":{"version":"0.7.4","protocol":16,"binary":"herdr"},"server":{"running":true,"version":"0.7.4","protocol":16,"compatible":true}}"#.utf8)

    @Test
    func preflightUsesStructuredExecResultAndPinnedCommand() async throws {
        let fake = FakeHerdrSSHExecutor(result: SSHExecResult(
            stdout: Self.compatibleStatus,
            stderr: Data(),
            exitStatus: 0
        ))
        let transport = HerdrSSHTransport(
            ssh: fake,
            commandBuilder: HerdrRemoteCommandBuilder(sessionName: "vvterm")
        )

        #expect(try await transport.preflight() == .compatible)
        #expect(await fake.executedCommands == [
            "exec 'herdr' '--session' 'vvterm' 'status' '--json'",
        ])
    }

    @Test
    func workspaceBridgeStartsPrivateProtocolWithoutPTY() async throws {
        let fake = makeFake()
        let transport = makeTransport(fake)

        let handle = try await transport.startWorkspaceBridge()

        #expect(handle.id == fake.handle.id)
        #expect(await fake.startedCommands == [
            "exec 'herdr' '--session' 'vvterm' 'remote-client-bridge'",
        ])
    }

    @Test
    func workspaceConnectionRejectsStoppedRuntimeBeforeOpeningBridge() async {
        let fake = FakeHerdrSSHExecutor(result: SSHExecResult(
            stdout: Data(#"{"client":{"version":"0.7.4","protocol":16,"binary":"herdr"},"server":{"running":false,"version":null,"protocol":null,"compatible":null}}"#.utf8),
            stderr: Data(),
            exitStatus: 0
        ))

        await #expect(throws: HerdrSSHTransportError.preflightFailed(.runtimeUnavailable)) {
            try await makeTransport(fake).startWorkspaceConnection(cols: 80, rows: 24)
        }
        #expect(await fake.executedCommands == [
            "exec 'herdr' '--session' 'vvterm' 'status' '--json'",
        ])
        #expect(await fake.startedCommands.isEmpty)
        #expect(await fake.writes.isEmpty)
    }

    @Test
    func observeDecodesFragmentedFramesAndExposesDiagnostics() async throws {
        let fake = makeFake()
        let connection = try await makeTransport(fake).startTerminalSession(
            mode: .observe(target: "w1:p1"),
            cols: 120,
            rows: 40
        )
        let records = Data((
            #"{"type":"terminal.frame","seq":1,"encoding":"ansi","width":120,"height":40,"full":true,"bytes":"G1sySg=="}"#
                + "\n"
                + #"{"type":"terminal.closed","reason":"done"}"#
                + "\n"
        ).utf8)
        #expect(await fake.offerStdout(records.prefix(17)))
        #expect(await fake.offerStdout(records.dropFirst(17)))
        #expect(await fake.offerStderr(Data("diagnostic".utf8)))

        #expect(try await connection.nextEvent() == .frame(HerdrTerminalFrame(
            sequence: 1,
            width: 120,
            height: 40,
            full: true,
            bytes: Data([0x1B, 0x5B, 0x32, 0x4A])
        )))
        #expect(try await connection.nextEvent() == .closed(reason: "done"))
        #expect(try await connection.nextEvent() == nil)
        #expect(try await connection.nextDiagnosticChunk() == Data("diagnostic".utf8))
        await #expect(throws: HerdrSSHTransportError.readOnlySession) {
            try await connection.send(.input(Data([1])))
        }
    }

    @Test
    func controlWritesNDJSONReleasesInputAndClosesIdempotently() async throws {
        let fake = makeFake()
        let connection = try await makeTransport(fake).startTerminalSession(
            mode: .control(target: "agent one", takeover: true),
            cols: 80,
            rows: 24
        )

        try await connection.send(.input(Data([0, 0xFF])))
        try await connection.release()
        try await connection.release()
        await connection.close()
        await connection.close()

        let writes = await fake.writes
        #expect(writes.count == 2)
        #expect(try jsonType(writes[0].0) == "terminal.input")
        #expect(try jsonType(writes[1].0) == "terminal.release")
        #expect(await fake.finishedInputs == [fake.handle.id])
        #expect(await fake.closedStreams == [fake.handle.id])
        #expect(await fake.startedCommands.first?.contains("'control' 'agent one' '--takeover'") == true)
    }

    @Test
    func rejectsZeroDimensionsBeforeOpeningStream() async {
        let fake = makeFake()

        await #expect(throws: HerdrSSHTransportError.invalidDimensions) {
            try await makeTransport(fake).startTerminalSession(
                mode: .observe(target: "w1:p1"),
                cols: 0,
                rows: 24
            )
        }
        #expect(await fake.startedCommands.isEmpty)
    }

    private func makeFake() -> FakeHerdrSSHExecutor {
        FakeHerdrSSHExecutor(result: SSHExecResult(
            stdout: Self.compatibleStatus,
            stderr: Data(),
            exitStatus: 0
        ))
    }

    private func makeTransport(_ fake: FakeHerdrSSHExecutor) -> HerdrSSHTransport {
        HerdrSSHTransport(
            ssh: fake,
            commandBuilder: HerdrRemoteCommandBuilder(sessionName: "vvterm")
        )
    }

    private func jsonType(_ data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["type"] as? String
    }
}
