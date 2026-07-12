import Foundation
import Testing
@testable import VVTerm

struct HerdrPreflightTests {
    @Test
    func acceptsPinnedClientAndRunningServer() {
        let json = Data(#"{"client":{"version":"0.7.3","channel":"stable","protocol":16,"binary":"/opt/homebrew/bin/herdr","session":"vvterm"},"server":{"status":"running","running":true,"version":"0.7.3","protocol":16,"capabilities":{"live_handoff":true,"detached_server_daemon":true},"compatible":true,"socket":"/tmp/herdr.sock","session":"vvterm","restart_needed":false},"update":{"restart_needed":false}}"#.utf8)

        #expect(HerdrPreflightEvaluator().evaluate(stdout: json) == .compatible)
    }

    @Test
    func rejectsClientProtocolBeforeInspectingRuntime() {
        let status = HerdrPreflightStatus(
            client: .init(version: "0.7.3", protocolVersion: 17, binary: "herdr"),
            server: .init(running: false, version: nil, protocolVersion: nil, compatible: nil)
        )

        #expect(HerdrPreflightEvaluator().evaluate(status: status) == .protocolMismatch(client: 16, remote: 17))
    }

    @Test
    func reportsUnavailableRuntimeFromStructuredStatus() {
        let status = HerdrPreflightStatus(
            client: .init(version: "0.7.3", protocolVersion: 16, binary: "herdr"),
            server: .init(running: false, version: nil, protocolVersion: nil, compatible: nil)
        )

        #expect(HerdrPreflightEvaluator().evaluate(status: status) == .runtimeUnavailable)
    }

    @Test
    func decodesExactStoppedRuntimeJSONFromHerdr073() {
        let json = Data(#"{"client":{"version":"0.7.3","channel":"stable","protocol":16,"binary":"/usr/local/bin/herdr","session":"vvterm"},"server":{"status":"not_running","running":false,"version":null,"protocol":null,"capabilities":null,"compatible":null,"socket":"/tmp/herdr.sock","session":"vvterm","restart_needed":false},"update":{"restart_needed":false}}"#.utf8)

        #expect(HerdrPreflightEvaluator().evaluate(stdout: json) == .runtimeUnavailable)
    }

    @Test
    func rejectsInvalidStatusWithoutParsingHumanOutput() {
        #expect(HerdrPreflightEvaluator().evaluate(stdout: Data("herdr is running".utf8)) == .invalidStatus)
    }

    @Test
    func commandBuilderQuotesEveryRemoteArgument() {
        let builder = HerdrRemoteCommandBuilder(
            executable: "/opt/herdr's/bin/herdr",
            sessionName: "work; touch /tmp/nope"
        )

        #expect(builder.status() == "exec '/opt/herdr'\\''s/bin/herdr' '--session' 'work; touch /tmp/nope' 'status' '--json'")
        #expect(builder.workspaceBridge().hasSuffix("'remote-client-bridge'"))
        #expect(builder.stopServer().hasSuffix("'server' 'stop'"))
        #expect(builder.terminalControl(target: "agent one", takeover: true, cols: 120, rows: 40).contains("'agent one' '--takeover' '--cols' '120' '--rows' '40'"))
    }

    @Test
    func serviceMapsShellCommandNotFoundWithoutParsingStderr() async throws {
        let service = HerdrPreflightService(
            commandBuilder: HerdrRemoteCommandBuilder(sessionName: "vvterm")
        )

        let result = try await service.run { _ in
            SSHExecResult(
                stdout: Data(),
                stderr: Data("sh: herdr: command not found".utf8),
                exitStatus: 127
            )
        }

        #expect(result == .binaryMissing)
    }

    @Test
    func servicePassesOnlySuccessfulStructuredOutputToEvaluator() async throws {
        let service = HerdrPreflightService(
            commandBuilder: HerdrRemoteCommandBuilder(sessionName: "vvterm")
        )

        let result = try await service.run { command in
            #expect(command == "exec 'herdr' '--session' 'vvterm' 'status' '--json'")
            return SSHExecResult(
                stdout: Data(#"{"client":{"version":"0.7.3","protocol":16,"binary":"herdr"},"server":{"running":true,"version":"0.7.3","protocol":16,"compatible":true}}"#.utf8),
                stderr: Data(),
                exitStatus: 0
            )
        }

        #expect(result == .compatible)
    }
}
