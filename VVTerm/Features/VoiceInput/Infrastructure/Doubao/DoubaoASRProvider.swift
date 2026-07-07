import Foundation

nonisolated struct DoubaoASRProviderConfiguration: Equatable, Sendable {
    let endpoint: URL
    let appID: String
    let accessToken: String
    let resourceID: String
    let language: String?
}

nonisolated enum DoubaoASRWebSocketMessage: Sendable {
    case data(Data)
    case string(String)
}

nonisolated protocol DoubaoASRWebSocketClient: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> DoubaoASRWebSocketMessage
    func cancel() async
}

nonisolated protocol DoubaoASRWebSocketFactory: Sendable {
    func makeClient(
        configuration: DoubaoASRProviderConfiguration,
        connectID: String
    ) throws -> any DoubaoASRWebSocketClient
}

nonisolated struct URLSessionDoubaoASRWebSocketFactory: DoubaoASRWebSocketFactory {
    func makeClient(
        configuration: DoubaoASRProviderConfiguration,
        connectID: String
    ) throws -> any DoubaoASRWebSocketClient {
        var request = URLRequest(url: configuration.endpoint)
        request.timeoutInterval = 45
        request.setValue(configuration.appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(configuration.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(configuration.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionDoubaoASRWebSocketClient(session: session, task: task)
    }
}

nonisolated final class URLSessionDoubaoASRWebSocketClient: DoubaoASRWebSocketClient, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(session: URLSession, task: URLSessionWebSocketTask) {
        self.session = session
        self.task = task
    }

    func send(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func receive() async throws -> DoubaoASRWebSocketMessage {
        let message = try await task.receive()
        switch message {
        case .data(let data):
            return .data(data)
        case .string(let string):
            return .string(string)
        @unknown default:
            throw NSError(
                domain: "VVTerm.DoubaoASR",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Received an unsupported Doubao ASR WebSocket message.")]
            )
        }
    }

    func cancel() async {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

actor DoubaoASRProvider {
    private let webSocketFactory: any DoubaoASRWebSocketFactory
    private var client: (any DoubaoASRWebSocketClient)?
    private var receiveTask: Task<Void, Never>?
    private var responseState: DoubaoASRResponseState?
    private var pendingPCMData = Data()
    private var nextAudioSequence: Int32 = 2
    private var onServerEvent: (@Sendable (DoubaoServerEvent) async -> Void)?
    private var onRuntimeFailure: (@Sendable (Error) async -> Void)?

    init(webSocketFactory: any DoubaoASRWebSocketFactory = URLSessionDoubaoASRWebSocketFactory()) {
        self.webSocketFactory = webSocketFactory
    }

    func start(
        configuration: DoubaoASRProviderConfiguration,
        onServerEvent: @escaping @Sendable (DoubaoServerEvent) async -> Void,
        onRuntimeFailure: @escaping @Sendable (Error) async -> Void
    ) async throws {
        await cancel()

        let connectID = UUID().uuidString.lowercased()
        let requestID = UUID().uuidString.lowercased()
        let client = try webSocketFactory.makeClient(configuration: configuration, connectID: connectID)
        let responseState = DoubaoASRResponseState()

        self.client = client
        self.responseState = responseState
        self.pendingPCMData.removeAll(keepingCapacity: true)
        self.nextAudioSequence = 2
        self.onServerEvent = onServerEvent
        self.onRuntimeFailure = onRuntimeFailure
        self.receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        do {
            let packet = try DoubaoStreamingProtocol.makeFullClientRequestPacket(
                requestID: requestID,
                userID: "vvterm",
                language: configuration.language,
                sequence: 1
            )
            try await client.send(packet)
        } catch {
            await cancel()
            throw error
        }
    }

    func appendPCMData(_ data: Data) async throws {
        guard !data.isEmpty, client != nil else { return }
        pendingPCMData.append(data)
        try await flushBufferedAudio(includeTrailingPartial: false)
    }

    func finishAndWaitForFinal(timeoutSeconds: TimeInterval = 2.0) async throws -> String {
        try await flushBufferedAudio(includeTrailingPartial: true)

        if let client {
            let finalSequence = max(2, nextAudioSequence)
            let finalPacket = try DoubaoStreamingProtocol.makeAudioOnlyClientRequestPacket(
                payload: Data(),
                sequence: finalSequence,
                isLast: true
            )
            try await client.send(finalPacket)
        }

        let text = try await responseState?.waitForFinalResult(timeoutSeconds: timeoutSeconds) ?? ""
        await closeSocket()
        return text
    }

    func cancel() async {
        receiveTask?.cancel()
        receiveTask = nil
        await closeSocket()
        responseState = nil
        pendingPCMData.removeAll(keepingCapacity: false)
        nextAudioSequence = 2
        onServerEvent = nil
        onRuntimeFailure = nil
    }

    private func flushBufferedAudio(includeTrailingPartial: Bool) async throws {
        guard let client else { return }

        while let payload = DoubaoASRConfiguration.popRecommendedStreamingChunk(
            from: &pendingPCMData,
            includeTrailingPartial: includeTrailingPartial
        ) {
            let sequence = nextAudioSequence
            nextAudioSequence += 1
            let packet = try DoubaoStreamingProtocol.makeAudioOnlyClientRequestPacket(
                payload: payload,
                sequence: sequence,
                isLast: false
            )
            try await client.send(packet)
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let client else { return }
            do {
                let message = try await client.receive()
                guard let data = data(from: message),
                      let event = try DoubaoStreamingProtocol.parseServerPacket(data),
                      let responseState else {
                    continue
                }

                let snapshot = await responseState.apply(event)
                if let onServerEvent {
                    await onServerEvent(snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                await handleReceiveFailure(error)
                return
            }
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        await responseState?.markCompletedWithError(error)
        if let onRuntimeFailure {
            await onRuntimeFailure(error)
        }
    }

    private func data(from message: DoubaoASRWebSocketMessage) -> Data? {
        switch message {
        case .data(let data):
            return data
        case .string(let string):
            return string.data(using: .utf8)
        }
    }

    private func closeSocket() async {
        guard let client else { return }
        self.client = nil
        await client.cancel()
    }
}

private actor DoubaoASRResponseState {
    private var text = ""
    private var isFinal = false
    private var completionError: Error?

    func apply(_ event: DoubaoServerEvent) -> DoubaoServerEvent {
        if let eventText = event.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventText.isEmpty {
            text = eventText
        }
        if event.isFinal {
            isFinal = true
        }
        return DoubaoServerEvent(text: text, isFinal: isFinal)
    }

    func markCompletedWithError(_ error: Error) {
        if completionError == nil {
            completionError = error
        }
    }

    func waitForFinalResult(timeoutSeconds: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        while !isFinal, completionError == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        if let completionError {
            throw completionError
        }
        return text
    }
}
