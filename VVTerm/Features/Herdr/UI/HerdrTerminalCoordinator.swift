import Foundation

@MainActor
final class HerdrTerminalCoordinator {
    private let server: Server
    private let sessionName = "vvterm"
    private var onStateChange: (HerdrConnectionState) -> Void

    private weak var terminal: GhosttyTerminalView?
    private var sshClient: SSHClient?
    private var connection: HerdrWorkspaceConnection?
    private var streamTask: Task<Void, Never>?
    private var resizeFlushTask: Task<Void, Never>?
    private var resizeCoalescer = HerdrResizeCoalescer()
    private var zoomState = HerdrZoomState()
    private var stateMachine = HerdrConnectionStateMachine()
    private var streamTaskConnectionID: UUID?

    private static let resizeThrottleInterval: Duration = .milliseconds(120)

    init(
        server: Server,
        onStateChange: @escaping (HerdrConnectionState) -> Void
    ) {
        self.server = server
        self.onStateChange = onStateChange
    }

    func update(onStateChange: @escaping (HerdrConnectionState) -> Void) {
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
        terminal.onResize = { [weak self] cols, rows in
            Task { @MainActor [weak self] in
                self?.queueResize(cols: cols, rows: rows)
            }
        }
        terminal.setupWriteCallback()
        terminal.applyPresentationOverrides(zoomState.presentationOverrides)
        startIfNeeded()
    }

    func handleZoom(_ action: TerminalZoomAction) -> TerminalZoomResult {
        let result = zoomState.apply(action)
        terminal?.applyPresentationOverrides(result.presentationOverrides)
        return result
    }

    func stop() {
        let resources = invalidateConnection(as: .idle)
        terminal?.writeCallback = nil
        terminal?.onResize = nil

        Task.detached(priority: .high) {
            await resources.connection?.close()
            await resources.sshClient?.disconnect()
        }
    }

    private func startIfNeeded() {
        guard streamTask == nil,
              let terminal,
              let connectionID = stateMachine.begin() else { return }

        streamTaskConnectionID = connectionID
        onStateChange(stateMachine.state)
        streamTask = Task { [weak self, weak terminal] in
            guard let self, let terminal else { return }
            defer { completeStreamTask(for: connectionID) }
            do {
                let credentials = try KeychainManager.shared.getCredentials(for: server)
                let sshClient = SSHClient()
                self.sshClient = sshClient
                _ = try await sshClient.connect(to: server, credentials: credentials)
                guard stateMachine.accepts(connectionID) else {
                    await sshClient.disconnect()
                    return
                }

                publish(.handshaking, for: connectionID)
                let size = terminal.terminalSize()
                let cols = UInt16(clamping: size?.columns ?? 80)
                let rows = UInt16(clamping: size?.rows ?? 24)
                let transport = HerdrSSHTransport(
                    ssh: sshClient,
                    commandBuilder: HerdrRemoteCommandBuilder(sessionName: sessionName)
                )
                let connection = try await transport.startWorkspaceConnection(cols: cols, rows: rows)
                guard stateMachine.accepts(connectionID) else {
                    await connection.close()
                    await sshClient.disconnect()
                    return
                }
                self.connection = connection

                while !Task.isCancelled, let event = try await connection.nextEvent() {
                    guard stateMachine.accepts(connectionID) else { return }
                    switch event {
                    case .welcome:
                        publish(.handshaking, for: connectionID)
                    case .ansi(_, _, _, _, let bytes):
                        terminal.feedData(bytes)
                        publish(.attached, for: connectionID)
                    case .graphics:
                        continue
                    case .shutdown(let reason):
                        await finishConnection(
                            connectionID,
                            as: .failed(.runtimeStopped(reason))
                        )
                        return
                    }
                }

                if stateMachine.accepts(connectionID), !Task.isCancelled {
                    await finishConnection(
                        connectionID,
                        as: .failed(.sshInterrupted("The Herdr connection closed."))
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await finishConnection(
                    connectionID,
                    as: .failed(Self.failure(for: error, sessionName: sessionName))
                )
            }
        }
    }

    private func sendInput(_ data: Data) async {
        guard let connectionID = stateMachine.activeConnectionID,
              let connection else { return }
        do {
            try await connection.sendInput(data)
        } catch {
            await finishConnection(
                connectionID,
                as: .failed(Self.failure(for: error, sessionName: sessionName))
            )
        }
    }

    private func queueResize(cols: Int, rows: Int) {
        if let immediate = resizeCoalescer.offer(cols: cols, rows: rows),
           let connectionID = stateMachine.activeConnectionID {
            Task { @MainActor [weak self] in
                await self?.transmitResize(immediate, connectionID: connectionID)
            }
        }
        scheduleResizeFlushIfNeeded()
    }

    private func scheduleResizeFlushIfNeeded() {
        guard resizeCoalescer.isThrottleWindowOpen, resizeFlushTask == nil else { return }

        resizeFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.resizeThrottleInterval)
                } catch {
                    return
                }

                let flush = resizeCoalescer.flush()
                if let size = flush.size,
                   let connectionID = stateMachine.activeConnectionID {
                    await transmitResize(size, connectionID: connectionID)
                }
                if !flush.shouldContinue {
                    resizeFlushTask = nil
                    return
                }
            }
        }
    }

    private func transmitResize(
        _ size: HerdrTerminalSize,
        connectionID: UUID
    ) async {
        guard stateMachine.accepts(connectionID), let connection else { return }
        do {
            try await connection.resize(cols: size.cols, rows: size.rows)
        } catch {
            await finishConnection(
                connectionID,
                as: .failed(Self.failure(for: error, sessionName: sessionName))
            )
        }
    }

    private func publish(_ state: HerdrConnectionState, for connectionID: UUID) {
        guard stateMachine.transition(to: state, for: connectionID) else { return }
        onStateChange(state)
    }

    private func finishConnection(
        _ connectionID: UUID,
        as finalState: HerdrConnectionState
    ) async {
        guard stateMachine.finish(connectionID, as: finalState) else { return }

        streamTask?.cancel()
        streamTask = nil
        streamTaskConnectionID = nil
        resizeFlushTask?.cancel()
        resizeFlushTask = nil
        resizeCoalescer.reset()

        let connection = self.connection
        let sshClient = self.sshClient
        self.connection = nil
        self.sshClient = nil
        onStateChange(finalState)

        await connection?.close()
        await sshClient?.disconnect()
    }

    private func completeStreamTask(for connectionID: UUID) {
        guard streamTaskConnectionID == connectionID else { return }
        streamTask = nil
        streamTaskConnectionID = nil
    }

    private func invalidateConnection(
        as state: HerdrConnectionState
    ) -> (connection: HerdrWorkspaceConnection?, sshClient: SSHClient?) {
        stateMachine.invalidate(as: state)
        streamTask?.cancel()
        streamTask = nil
        streamTaskConnectionID = nil
        resizeFlushTask?.cancel()
        resizeFlushTask = nil
        resizeCoalescer.reset()

        let resources = (connection: connection, sshClient: sshClient)
        self.connection = nil
        self.sshClient = nil
        onStateChange(state)
        return resources
    }

    private static func failure(for error: Error, sessionName: String) -> HerdrFailure {
        if let transportError = error as? HerdrSSHTransportError,
           case .preflightFailed(let result) = transportError {
            switch result {
            case .binaryMissing:
                return .binaryMissing
            case .runtimeUnavailable:
                return .runtimeUnavailable(sessionName: sessionName)
            case .bridgeUnavailable:
                return .bridgeUnavailable
            case .versionMismatch(let client, let remote):
                return .versionMismatch(client: client, remote: remote)
            case .protocolMismatch(let client, let remote):
                return .protocolMismatch(client: client, remote: remote)
            case .invalidStatus:
                return .invalidStatus
            case .compatible:
                break
            }
        }
        return .unknown(error.localizedDescription)
    }
}
