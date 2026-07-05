import XCTest
@testable import VVTerm

final class DoubaoASRProviderTests: XCTestCase {
    func testStartSendsFullRequestAndPublishesServerText() async throws {
        let client = FakeDoubaoWebSocketClient()
        let provider = DoubaoASRProvider(webSocketFactory: FakeDoubaoWebSocketFactory(client: client))
        let updates = DoubaoUpdateRecorder()

        try await provider.start(
            configuration: configuration,
            onServerEvent: { event in
                await updates.append(event)
            },
            onRuntimeFailure: { _ in }
        )

        let sent = await client.sentPackets()
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0][1] >> 4, DoubaoStreamingProtocol.messageTypeFullClientRequest)

        let serverPacket = try serverResponsePacket(text: " hello ", sequence: 2, isFinal: false)
        await client.push(.data(serverPacket))
        try await Task.sleep(nanoseconds: 50_000_000)

        let latestEvent = await updates.latest()
        XCTAssertEqual(latestEvent?.text, "hello")
        XCTAssertEqual(latestEvent?.isFinal, false)

        await provider.cancel()
    }

    func testAppendPCMDataBuffersUntilRecommendedChunkSize() async throws {
        let client = FakeDoubaoWebSocketClient()
        let provider = DoubaoASRProvider(webSocketFactory: FakeDoubaoWebSocketFactory(client: client))

        try await provider.start(
            configuration: configuration,
            onServerEvent: { _ in },
            onRuntimeFailure: { _ in }
        )
        try await provider.appendPCMData(Data(repeating: 1, count: 6_399))
        let initialSentCount = await client.sentPackets().count
        XCTAssertEqual(initialSentCount, 1)

        try await provider.appendPCMData(Data([2]))
        let sent = await client.sentPackets()

        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[1][1] >> 4, DoubaoStreamingProtocol.messageTypeAudioOnlyClientRequest)
        XCTAssertEqual(sent[1].int32BigEndian(at: 4), 2)

        await provider.cancel()
    }

    func testFinishFlushesTrailingAudioSendsFinalPacketAndReturnsFinalText() async throws {
        let client = FakeDoubaoWebSocketClient()
        let provider = DoubaoASRProvider(webSocketFactory: FakeDoubaoWebSocketFactory(client: client))

        try await provider.start(
            configuration: configuration,
            onServerEvent: { _ in },
            onRuntimeFailure: { _ in }
        )
        try await provider.appendPCMData(Data(repeating: 1, count: 128))

        let finishTask = Task {
            try await provider.finishAndWaitForFinal(timeoutSeconds: 0.5)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let sent = await client.sentPackets()
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(sent[1][1] >> 4, DoubaoStreamingProtocol.messageTypeAudioOnlyClientRequest)
        XCTAssertEqual(sent[1].int32BigEndian(at: 4), 2)
        XCTAssertEqual(sent[2][1], 0x23)
        XCTAssertLessThan(sent[2].int32BigEndian(at: 4), 0)

        await client.push(.data(try serverResponsePacket(text: "final text", sequence: -3, isFinal: true)))
        let result = try await finishTask.value

        XCTAssertEqual(result, "final text")
    }

    private var configuration: DoubaoASRProviderConfiguration {
        DoubaoASRProviderConfiguration(
            endpoint: URL(string: DoubaoASRConfiguration.defaultStreamingEndpointV2)!,
            appID: "app-id",
            accessToken: "access-token",
            resourceID: DoubaoASRConfiguration.modelV2,
            language: "zh-CN"
        )
    }

    private func serverResponsePacket(text: String, sequence: Int32, isFinal: Bool) throws -> Data {
        let payload: [String: Any] = [
            "result": ["text": text],
            "sequence": sequence,
            "is_last_package": isFinal
        ]
        let rawPayload = try JSONSerialization.data(withJSONObject: payload)
        return DoubaoStreamingProtocol.makePacket(
            messageType: DoubaoStreamingProtocol.messageTypeFullServerResponse,
            messageFlags: DoubaoStreamingProtocol.flagPositiveSequence,
            serialization: DoubaoStreamingProtocol.serializationJSON,
            compression: DoubaoStreamingProtocol.compressionNone,
            sequence: sequence,
            payload: rawPayload
        )
    }
}

private actor DoubaoUpdateRecorder {
    private var events: [DoubaoServerEvent] = []

    func append(_ event: DoubaoServerEvent) {
        events.append(event)
    }

    func latest() -> DoubaoServerEvent? {
        events.last
    }
}

private struct FakeDoubaoWebSocketFactory: DoubaoASRWebSocketFactory {
    let client: FakeDoubaoWebSocketClient

    func makeClient(
        configuration: DoubaoASRProviderConfiguration,
        connectID: String
    ) throws -> DoubaoASRWebSocketClient {
        client
    }
}

private actor FakeDoubaoWebSocketClient: DoubaoASRWebSocketClient {
    private var sent: [Data] = []
    private var receiveContinuations: [CheckedContinuation<DoubaoASRWebSocketMessage, Error>] = []
    private var queuedMessages: [DoubaoASRWebSocketMessage] = []

    func send(_ data: Data) async throws {
        sent.append(data)
    }

    func receive() async throws -> DoubaoASRWebSocketMessage {
        try await withCheckedThrowingContinuation { continuation in
            if !queuedMessages.isEmpty {
                let message = queuedMessages.removeFirst()
                continuation.resume(returning: message)
            } else {
                receiveContinuations.append(continuation)
            }
        }
    }

    func cancel() async {
        let continuations = receiveContinuations
        receiveContinuations.removeAll()

        for continuation in continuations {
            continuation.resume(throwing: CancellationError())
        }
    }

    func sentPackets() async -> [Data] {
        sent
    }

    func push(_ message: DoubaoASRWebSocketMessage) async {
        if let continuation = receiveContinuations.first {
            receiveContinuations.removeFirst()
            continuation.resume(returning: message)
        } else {
            queuedMessages.append(message)
        }
    }
}

private extension Data {
    func int32BigEndian(at offset: Int) -> Int32 {
        precondition(count >= offset + 4)
        let value = self[offset..<(offset + 4)].reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        return Int32(bitPattern: value)
    }
}
