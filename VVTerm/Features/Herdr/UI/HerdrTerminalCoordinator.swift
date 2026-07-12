import Foundation

@MainActor
final class HerdrTerminalCoordinator {
    private let server: Server
    private var onStateChange: (HerdrWorkspacePreviewState) -> Void

    private weak var terminal: GhosttyTerminalView?
    private var sshClient: SSHClient?
    private var connection: HerdrWorkspaceConnection?
    private var streamTask: Task<Void, Never>?
    private var generation = 0

    init(
        server: Server,
        onStateChange: @escaping (HerdrWorkspacePreviewState) -> Void
    ) {
        self.server = server
        self.onStateChange = onStateChange
    }

    func update(onStateChange: @escaping (HerdrWorkspacePreviewState) -> Void) {
        self.onStateChange = onStateChange
    }

    func bind(to terminal: GhosttyTerminalView) {
        guard self.terminal !== terminal else { return }
        self.terminal = terminal

        terminal.writeCallback = { [weak self] data in
            Task { @MainActor [weak self] in
                await self?.sendInput(data)
            }
        }
        terminal.setupWriteCallback()
        startIfNeeded()
    }

    func stop() {
        generation += 1
        streamTask?.cancel()
        streamTask = nil

        let connection = self.connection
        let sshClient = self.sshClient
        self.connection = nil
        self.sshClient = nil
        terminal?.writeCallback = nil

        Task.detached(priority: .high) {
            await connection?.close()
            await sshClient?.disconnect()
        }
    }

    private func startIfNeeded() {
        guard streamTask == nil, let terminal else { return }

        generation += 1
        let activeGeneration = generation
        onStateChange(.connecting)
        streamTask = Task { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            do {
                let credentials = try KeychainManager.shared.getCredentials(for: server)
                let sshClient = SSHClient()
                self.sshClient = sshClient
                _ = try await sshClient.connect(to: server, credentials: credentials)
                guard isCurrent(activeGeneration) else { return }

                onStateChange(.handshaking)
                let size = terminal.terminalSize()
                let cols = UInt16(clamping: size?.columns ?? 80)
                let rows = UInt16(clamping: size?.rows ?? 24)
                let transport = HerdrSSHTransport(
                    ssh: sshClient,
                    commandBuilder: HerdrRemoteCommandBuilder(sessionName: "vvterm")
                )
                let connection = try await transport.startWorkspaceConnection(cols: cols, rows: rows)
                guard isCurrent(activeGeneration) else {
                    await connection.close()
                    return
                }
                self.connection = connection

                while !Task.isCancelled, let event = try await connection.nextEvent() {
                    guard isCurrent(activeGeneration) else { return }
                    switch event {
                    case .welcome:
                        onStateChange(.handshaking)
                    case .ansi(_, _, _, _, let bytes):
                        terminal.feedData(bytes)
                        onStateChange(.attached)
                    case .graphics:
                        continue
                    case .shutdown(let reason):
                        onStateChange(.failed(reason ?? "The remote Herdr runtime stopped."))
                        return
                    }
                }

                if isCurrent(activeGeneration), !Task.isCancelled {
                    onStateChange(.failed("The Herdr connection closed."))
                }
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(activeGeneration) else { return }
                onStateChange(.failed(Self.failureMessage(for: error)))
            }
        }
    }

    private func sendInput(_ data: Data) async {
        guard let connection else { return }
        do {
            try await connection.sendInput(data)
        } catch {
            onStateChange(.failed(Self.failureMessage(for: error)))
        }
    }

    private func isCurrent(_ candidate: Int) -> Bool {
        candidate == generation
    }

    private static func failureMessage(for error: Error) -> String {
        if let transportError = error as? HerdrSSHTransportError,
           case .preflightFailed(let result) = transportError {
            switch result {
            case .binaryMissing:
                return "Herdr 0.7.3 is not installed on this server."
            case .runtimeUnavailable:
                return "Start the named Herdr session 'vvterm' on the server, then retry."
            case .bridgeUnavailable:
                return "This Herdr installation does not provide the remote client bridge."
            case .versionMismatch(let client, let remote):
                return "Herdr version mismatch: VVTerm expects \(client), server has \(remote)."
            case .protocolMismatch(let client, let remote):
                return "Herdr protocol mismatch: VVTerm expects \(client), server has \(remote)."
            case .invalidStatus:
                return "Herdr returned an invalid status response."
            case .compatible:
                break
            }
        }
        return error.localizedDescription
    }
}
