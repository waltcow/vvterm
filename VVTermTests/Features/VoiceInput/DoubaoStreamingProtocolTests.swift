import XCTest
@testable import VVTerm

final class DoubaoStreamingProtocolTests: XCTestCase {
    func testFullClientRequestPacketUsesExpectedHeaderAndPayload() throws {
        let packet = try DoubaoStreamingProtocol.makeFullClientRequestPacket(
            requestID: "request-1",
            userID: "vvterm",
            language: "zh-CN",
            sequence: 1
        )

        XCTAssertEqual(packet[0], 0x11)
        XCTAssertEqual(packet[1], 0x11)
        XCTAssertEqual(packet[2], 0x11)
        XCTAssertEqual(packet[3], 0x00)
        XCTAssertEqual(packet.int32BigEndian(at: 4), 1)

        let payloadSize = Int(packet.uint32BigEndian(at: 8))
        XCTAssertEqual(packet.count, 12 + payloadSize)

        let payload = try DoubaoStreamingProtocol.decodeGzipPayload(packet.subdata(in: 12..<packet.count))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let user = try XCTUnwrap(object["user"] as? [String: Any])
        let audio = try XCTUnwrap(object["audio"] as? [String: Any])
        let request = try XCTUnwrap(object["request"] as? [String: Any])

        XCTAssertEqual(user["uid"] as? String, "vvterm")
        XCTAssertEqual(audio["format"] as? String, "pcm")
        XCTAssertEqual(audio["codec"] as? String, "raw")
        XCTAssertEqual(audio["rate"] as? Int, 16_000)
        XCTAssertEqual(audio["bits"] as? Int, 16)
        XCTAssertEqual(audio["channel"] as? Int, 1)
        XCTAssertEqual(audio["language"] as? String, "zh-CN")
        XCTAssertEqual(request["reqid"] as? String, "request-1")
        XCTAssertEqual(request["model_name"] as? String, "bigmodel")
        XCTAssertEqual(request["enable_itn"] as? Bool, true)
        XCTAssertEqual(request["enable_punc"] as? Bool, true)
        XCTAssertEqual(request["enable_ddc"] as? Bool, true)
        XCTAssertEqual(request["show_utterances"] as? Bool, true)
    }

    func testAudioPacketUsesNegativeSequenceForLastPacket() throws {
        let packet = try DoubaoStreamingProtocol.makeAudioOnlyClientRequestPacket(
            payload: Data([0x01, 0x02, 0x03]),
            sequence: 5,
            isLast: true
        )

        XCTAssertEqual(packet[0], 0x11)
        XCTAssertEqual(packet[1], 0x23)
        XCTAssertEqual(packet[2] >> 4, DoubaoStreamingProtocol.serializationNone)
        XCTAssertEqual(packet.int32BigEndian(at: 4), -5)

        let payloadSize = Int(packet.uint32BigEndian(at: 8))
        let payload = try DoubaoStreamingProtocol.decodeGzipPayload(packet.subdata(in: 12..<packet.count))
        XCTAssertEqual(payloadSize, packet.count - 12)
        XCTAssertEqual(payload, Data([0x01, 0x02, 0x03]))
    }

    func testParseServerResponseExtractsPartialText() throws {
        let packet = try serverResponsePacket(
            payloadObject: [
                "result": ["text": " hello "],
                "sequence": 2
            ],
            sequence: 2,
            gzip: true
        )

        let event = try XCTUnwrap(DoubaoStreamingProtocol.parseServerPacket(packet))

        XCTAssertEqual(event.text, "hello")
        XCTAssertFalse(event.isFinal)
    }

    func testParseServerResponseTreatsJsonLastPackageAsFinal() throws {
        let packet = try serverResponsePacket(
            payloadObject: [
                "payload": [
                    "result": ["text": "done"],
                    "is_last_package": true
                ]
            ],
            sequence: 3,
            gzip: false
        )

        let event = try XCTUnwrap(DoubaoStreamingProtocol.parseServerPacket(packet))

        XCTAssertEqual(event.text, "done")
        XCTAssertTrue(event.isFinal)
    }

    func testParseServerAckTreatsNegativeSequenceAsFinal() throws {
        let packet = DoubaoStreamingProtocol.makePacket(
            messageType: DoubaoStreamingProtocol.messageTypeServerAck,
            messageFlags: DoubaoStreamingProtocol.flagLastAudioPacket,
            serialization: DoubaoStreamingProtocol.serializationNone,
            compression: DoubaoStreamingProtocol.compressionNone,
            sequence: -4,
            payload: Data()
        )

        let event = try XCTUnwrap(DoubaoStreamingProtocol.parseServerPacket(packet))

        XCTAssertNil(event.text)
        XCTAssertTrue(event.isFinal)
    }

    func testParseServerErrorThrowsMessagePayload() throws {
        let errorText = Data("invalid token".utf8)
        var packet = Data([0x11, 0xF1, 0x00, 0x00])
        packet.appendInt32BigEndian(1)
        packet.appendUInt32BigEndian(401)
        packet.appendUInt32BigEndian(UInt32(errorText.count))
        packet.append(errorText)

        XCTAssertThrowsError(try DoubaoStreamingProtocol.parseServerPacket(packet)) { error in
            XCTAssertEqual(error.localizedDescription, "invalid token")
        }
    }

    private func serverResponsePacket(
        payloadObject: [String: Any],
        sequence: Int32,
        gzip: Bool
    ) throws -> Data {
        let rawPayload = try JSONSerialization.data(withJSONObject: payloadObject)
        let payload = gzip ? try DoubaoStreamingProtocol.gzipPayload(rawPayload) : rawPayload
        return DoubaoStreamingProtocol.makePacket(
            messageType: DoubaoStreamingProtocol.messageTypeFullServerResponse,
            messageFlags: DoubaoStreamingProtocol.flagPositiveSequence,
            serialization: DoubaoStreamingProtocol.serializationJSON,
            compression: gzip ? DoubaoStreamingProtocol.compressionGzip : DoubaoStreamingProtocol.compressionNone,
            sequence: sequence,
            payload: payload
        )
    }
}

private extension Data {
    func uint32BigEndian(at offset: Int) -> UInt32 {
        precondition(count >= offset + 4)
        return self[offset..<(offset + 4)].reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }

    func int32BigEndian(at offset: Int) -> Int32 {
        Int32(bitPattern: uint32BigEndian(at: offset))
    }

    mutating func appendUInt32BigEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt32BigEndian(_ value: Int32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
