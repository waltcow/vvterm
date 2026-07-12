import Foundation
import XCTest
@testable import VVTerm

private enum HerdrWorkspaceIntegrationError: Error, CustomStringConvertible {
    case failed(stage: String, underlying: String)

    var description: String {
        switch self {
        case let .failed(stage, underlying):
            return "Herdr integration failed during \(stage): \(underlying)"
        }
    }
}

final class HerdrWorkspaceIntegrationTests: XCTestCase {
    func testStoppedRuntimeFailsPreflightBeforeOpeningBridge() async throws {
        guard let configuration = try SSHIntegrationFixtureConfiguration.load(
            displayName: "Herdr Stopped Runtime Fixture"
        ) else {
            throw XCTSkip("Set VVTERM_SSH_FIXTURE_HOST and VVTERM_SSH_FIXTURE_USER to run the Herdr integration fixture")
        }

        let executable = ProcessInfo.processInfo.environment["VVTERM_HERDR_EXECUTABLE"] ?? "herdr"
        let sessionName = "vvt-stop-\(UUID().uuidString.prefix(8).lowercased())"
        let client = SSHClient()
        do {
            _ = try await client.connect(
                to: configuration.server,
                credentials: configuration.credentials
            )
            let transport = HerdrSSHTransport(
                ssh: client,
                commandBuilder: HerdrRemoteCommandBuilder(
                    executable: executable,
                    sessionName: sessionName
                )
            )
            do {
                _ = try await transport.startWorkspaceConnection(cols: 80, rows: 24)
                XCTFail("Expected stopped runtime preflight failure")
            } catch let error as HerdrSSHTransportError {
                XCTAssertEqual(error, .preflightFailed(.runtimeUnavailable))
            }
        } catch {
            await client.disconnect()
            throw error
        }
        await client.disconnect()
    }

    func testRealWorkspaceBridgeOverVVTermSSHClient() async throws {
        guard let configuration = try SSHIntegrationFixtureConfiguration.load(
            displayName: "Herdr Workspace Fixture"
        ) else {
            throw XCTSkip("Set VVTERM_SSH_FIXTURE_HOST and VVTERM_SSH_FIXTURE_USER to run the Herdr integration fixture")
        }

        let environment = ProcessInfo.processInfo.environment
        let executable = environment["VVTERM_HERDR_EXECUTABLE"] ?? "herdr"
        guard let sessionName = environment["VVTERM_HERDR_SESSION_NAME"],
              !sessionName.isEmpty else {
            throw XCTSkip("Set VVTERM_HERDR_SESSION_NAME to a pre-started disposable Herdr session; the test stops it")
        }
        let builder = HerdrRemoteCommandBuilder(
            executable: executable,
            sessionName: sessionName
        )
        let client = SSHClient()
        var connection: HerdrWorkspaceConnection?
        var stage = "SSH connect"
        var remoteEnvironment = ""

        do {
            _ = try await client.connect(
                to: configuration.server,
                credentials: configuration.credentials
            )
            stage = "remote environment probe"
            let environmentResult = try await client.executeResult(
                "env | LC_ALL=C sort",
                timeout: .seconds(20)
            )
            remoteEnvironment = String(decoding: environmentResult.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let transport = HerdrSSHTransport(ssh: client, commandBuilder: builder)
            stage = "workspace bridge start"
            let activeConnection = try await transport.startWorkspaceConnection(cols: 80, rows: 24)
            connection = activeConnection

            stage = "Welcome read"
            let welcome = try await Self.withTimeout(.seconds(20)) {
                try await activeConnection.nextEvent()
            }
            XCTAssertEqual(welcome, .welcome(protocolVersion: 16))

            stage = "initial redraw read"
            let redraw = try await Self.withTimeout(.seconds(20)) {
                try await activeConnection.nextEvent()
            }
            guard let redraw,
                  case let .ansi(sequence, width, height, full, bytes) = redraw else {
                return XCTFail("Expected initial ANSI redraw, got \(String(describing: redraw))")
            }
            XCTAssertEqual(sequence, 1)
            XCTAssertGreaterThan(width, 0)
            XCTAssertGreaterThan(height, 0)
            XCTAssertTrue(full)
            XCTAssertFalse(bytes.isEmpty)

            stage = "resize"
            try await activeConnection.resize(cols: 100, rows: 30)
            stage = "input"
            try await activeConnection.sendInput(Data([0x1B]))
            stage = "detach"
            try await activeConnection.detach()
            stage = "connection close"
            await activeConnection.close()
            connection = nil

            stage = "temporary server stop"
            let stopResult = try await client.executeResult(
                builder.stopServer(),
                timeout: .seconds(20)
            )
            XCTAssertEqual(stopResult.exitStatus, 0)
        } catch {
            let diagnostics: String
            if let connection,
               let chunk = try? await connection.nextDiagnosticChunk() {
                diagnostics = String(decoding: chunk, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                diagnostics = ""
            }
            let underlying = diagnostics.isEmpty
                ? String(describing: error)
                : "\(error); remote stderr: \(diagnostics)"
            let environmentDiagnostic = remoteEnvironment.isEmpty
                ? underlying
                : "\(underlying); remote environment: \(remoteEnvironment)"
            let failure = HerdrWorkspaceIntegrationError.failed(
                stage: stage,
                underlying: environmentDiagnostic
            )
            await connection?.close()
            _ = try? await client.executeResult(builder.stopServer(), timeout: .seconds(10))
            await client.disconnect()
            throw failure
        }

        await client.disconnect()
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
