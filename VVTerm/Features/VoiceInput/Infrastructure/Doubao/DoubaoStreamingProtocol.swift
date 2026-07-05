import Foundation
import zlib

nonisolated struct DoubaoServerEvent: Equatable, Sendable {
    let text: String?
    let isFinal: Bool
}

nonisolated enum DoubaoStreamingProtocol {
    static let version: UInt8 = 0x1
    static let headerSize: UInt8 = 0x1
    static let messageTypeFullClientRequest: UInt8 = 0x1
    static let messageTypeAudioOnlyClientRequest: UInt8 = 0x2
    static let messageTypeFullServerResponse: UInt8 = 0x9
    static let messageTypeServerAck: UInt8 = 0xB
    static let messageTypeServerErrorResponse: UInt8 = 0xF
    static let flagPositiveSequence: UInt8 = 0x1
    static let flagLastAudioPacket: UInt8 = 0x2
    static let flagNegativeAudioPacket: UInt8 = flagPositiveSequence | flagLastAudioPacket
    static let flagEvent: UInt8 = 0x4
    static let serializationNone: UInt8 = 0x0
    static let serializationJSON: UInt8 = 0x1
    static let compressionNone: UInt8 = 0x0
    static let compressionGzip: UInt8 = 0x1

    static func makeFullClientRequestPacket(
        requestID: String,
        userID: String,
        language: String?,
        sequence: Int32
    ) throws -> Data {
        let payloadObject = fullRequestPayload(
            requestID: requestID,
            userID: userID,
            language: language
        )
        let rawPayload = try JSONSerialization.data(withJSONObject: payloadObject)
        let payload = try gzipPayload(rawPayload)
        return makePacket(
            messageType: messageTypeFullClientRequest,
            messageFlags: flagPositiveSequence,
            serialization: serializationJSON,
            compression: compressionGzip,
            sequence: sequence,
            payload: payload
        )
    }

    static func makeAudioOnlyClientRequestPacket(
        payload: Data,
        sequence: Int32,
        isLast: Bool
    ) throws -> Data {
        let compression = payload.isEmpty ? compressionNone : compressionGzip
        let encodedPayload = payload.isEmpty ? payload : try gzipPayload(payload)
        return makePacket(
            messageType: messageTypeAudioOnlyClientRequest,
            messageFlags: isLast ? flagNegativeAudioPacket : flagPositiveSequence,
            serialization: serializationNone,
            compression: compression,
            sequence: isLast ? -abs(sequence) : sequence,
            payload: encodedPayload
        )
    }

    static func makePacket(
        messageType: UInt8,
        messageFlags: UInt8,
        serialization: UInt8,
        compression: UInt8,
        sequence: Int32,
        payload: Data
    ) -> Data {
        var data = Data()
        data.append((version << 4) | headerSize)
        data.append((messageType << 4) | messageFlags)
        data.append((serialization << 4) | compression)
        data.append(0x00)
        if hasSequence(messageFlags) {
            data.append(bigEndianData(sequence))
        }
        data.append(bigEndianData(UInt32(payload.count)))
        data.append(payload)
        return data
    }

    static func parseServerPacket(_ data: Data) throws -> DoubaoServerEvent? {
        guard data.count >= 8 else { return nil }

        let byte0 = data[0]
        let byte1 = data[1]
        let byte2 = data[2]
        let headerSizeWords = Int(byte0 & 0x0F)
        let headerSizeBytes = max(4, headerSizeWords * 4)
        guard data.count >= headerSizeBytes else { return nil }

        let messageType = (byte1 >> 4) & 0x0F
        let messageFlags = byte1 & 0x0F
        let compression = byte2 & 0x0F
        guard messageType == messageTypeFullServerResponse ||
              messageType == messageTypeServerAck ||
              messageType == messageTypeServerErrorResponse else {
            return nil
        }

        var cursor = headerSizeBytes
        var headerSequence: Int32?
        if hasSequence(messageFlags) {
            guard data.count >= cursor + 4 else { return nil }
            headerSequence = int32(fromBigEndian: data.subdata(in: cursor..<(cursor + 4)))
            cursor += 4
        }
        if (messageFlags & flagEvent) != 0 {
            guard data.count >= cursor + 4 else { return nil }
            cursor += 4
        }

        if messageType == messageTypeServerAck {
            return DoubaoServerEvent(
                text: nil,
                isFinal: isFinal(messageFlags: messageFlags, headerSequence: headerSequence, jsonSequence: nil, jsonLastPackage: nil)
            )
        }

        let rawPayload: Data
        switch messageType {
        case messageTypeFullServerResponse:
            guard data.count >= cursor + 4 else { return nil }
            let payloadSize = Int(uint32(fromBigEndian: data.subdata(in: cursor..<(cursor + 4))))
            cursor += 4
            guard data.count >= cursor + payloadSize else { return nil }
            rawPayload = data.subdata(in: cursor..<(cursor + payloadSize))

        case messageTypeServerErrorResponse:
            guard data.count >= cursor + 8 else { return nil }
            cursor += 4
            let payloadSize = Int(uint32(fromBigEndian: data.subdata(in: cursor..<(cursor + 4))))
            cursor += 4
            guard data.count >= cursor + payloadSize else { return nil }
            rawPayload = data.subdata(in: cursor..<(cursor + payloadSize))

        default:
            return nil
        }

        let payload = try decodedPayload(rawPayload, compression: compression)
        if messageType == messageTypeServerErrorResponse {
            let errorText = String(data: payload, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "VVTerm.DoubaoASR",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: errorText?.isEmpty == false ? errorText! : String(localized: "Unknown Doubao ASR server error.")]
            )
        }

        guard !payload.isEmpty else {
            return DoubaoServerEvent(
                text: nil,
                isFinal: isFinal(messageFlags: messageFlags, headerSequence: headerSequence, jsonSequence: nil, jsonLastPackage: nil)
            )
        }

        guard let object = try? JSONSerialization.jsonObject(with: payload) else {
            let text = String(data: payload, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return DoubaoServerEvent(
                text: sanitizedText(text),
                isFinal: isFinal(messageFlags: messageFlags, headerSequence: headerSequence, jsonSequence: nil, jsonLastPackage: nil)
            )
        }

        let jsonSequence = extractSequence(in: object)
        let jsonLastPackage = isLastPackage(in: object)
        return DoubaoServerEvent(
            text: extractDoubaoText(in: object),
            isFinal: isFinal(
                messageFlags: messageFlags,
                headerSequence: headerSequence,
                jsonSequence: jsonSequence,
                jsonLastPackage: jsonLastPackage
            )
        )
    }

    static func gzipPayload(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input)
            stream.avail_in = uInt(data.count)

            let initStatus = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                MAX_WBITS + 16,
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw NSError(
                    domain: "VVTerm.DoubaoASR",
                    code: -12,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to initialize Doubao ASR GZIP compression.")]
                )
            }
            defer { deflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            while status == Z_OK {
                var out = [UInt8](repeating: 0, count: 16_384)
                status = out.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = UnsafeMutablePointer<Bytef>(
                        outBuffer.bindMemory(to: UInt8.self).baseAddress
                    )
                    stream.avail_out = uInt(outBuffer.count)
                    return deflate(&stream, Z_FINISH)
                }
                let used = out.count - Int(stream.avail_out)
                if used > 0 {
                    output.append(contentsOf: out[0..<used])
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw NSError(
                        domain: "VVTerm.DoubaoASR",
                        code: -13,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to compress Doubao ASR payload.")]
                    )
                }
            }
            return output
        }
    }

    static func decodeGzipPayload(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input)
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit2_(
                &stream,
                16 + MAX_WBITS,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw NSError(
                    domain: "VVTerm.DoubaoASR",
                    code: -8,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to initialize Doubao ASR GZIP decompression.")]
                )
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            while status == Z_OK {
                var out = [UInt8](repeating: 0, count: 16_384)
                let outCount = out.count
                status = out.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = UnsafeMutablePointer<Bytef>(
                        outBuffer.bindMemory(to: UInt8.self).baseAddress
                    )
                    stream.avail_out = uInt(outCount)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                let used = outCount - Int(stream.avail_out)
                if used > 0 {
                    output.append(contentsOf: out[0..<used])
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw NSError(
                        domain: "VVTerm.DoubaoASR",
                        code: -9,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to decode Doubao ASR GZIP response payload.")]
                    )
                }
            }
            return output
        }
    }

    private static func fullRequestPayload(
        requestID: String,
        userID: String,
        language: String?
    ) -> [String: Any] {
        var audio: [String: Any] = [
            "format": "pcm",
            "codec": "raw",
            "rate": DoubaoASRConfiguration.streamingSampleRate,
            "bits": DoubaoASRConfiguration.streamingBitsPerSample,
            "channel": DoubaoASRConfiguration.streamingChannelCount
        ]
        if let language,
           !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            audio["language"] = language
        }

        return [
            "user": [
                "uid": userID
            ],
            "audio": audio,
            "request": [
                "reqid": requestID,
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true
            ]
        ]
    }

    private static func decodedPayload(_ rawPayload: Data, compression: UInt8) throws -> Data {
        switch compression {
        case compressionNone:
            return rawPayload
        case compressionGzip:
            return try decodeGzipPayload(rawPayload)
        default:
            if looksLikeGzip(rawPayload) {
                return try decodeGzipPayload(rawPayload)
            }
            throw NSError(
                domain: "VVTerm.DoubaoASR",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Doubao ASR response compression is unsupported.")]
            )
        }
    }

    private static func isFinal(
        messageFlags: UInt8,
        headerSequence: Int32?,
        jsonSequence: Int32?,
        jsonLastPackage: Bool?
    ) -> Bool {
        (messageFlags & flagLastAudioPacket) != 0 ||
            jsonLastPackage == true ||
            (jsonSequence ?? headerSequence ?? 1) < 0
    }

    private static func hasSequence(_ messageFlags: UInt8) -> Bool {
        (messageFlags & flagPositiveSequence) != 0 || (messageFlags & flagLastAudioPacket) != 0
    }

    private static func bigEndianData(_ value: UInt32) -> Data {
        Swift.withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func bigEndianData(_ value: Int32) -> Data {
        Swift.withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func uint32(fromBigEndian data: Data) -> UInt32 {
        precondition(data.count == 4)
        return data.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }

    private static func int32(fromBigEndian data: Data) -> Int32 {
        Int32(bitPattern: uint32(fromBigEndian: data))
    }

    private static func extractSequence(in object: Any) -> Int32? {
        if let value = object as? Int { return Int32(value) }
        if let value = object as? Int32 { return value }
        if let value = object as? Int64 { return Int32(value) }
        if let value = object as? NSNumber { return value.int32Value }

        if let dict = object as? [String: Any] {
            if let seq = dict["sequence"] {
                return extractSequence(in: seq)
            }
            for value in dict.values {
                if let seq = extractSequence(in: value) {
                    return seq
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for item in array {
                if let seq = extractSequence(in: item) {
                    return seq
                }
            }
        }
        return nil
    }

    private static func isLastPackage(in object: Any) -> Bool? {
        if let dict = object as? [String: Any] {
            if let value = dict["is_last_package"] {
                return value as? Bool ?? (value as? NSNumber)?.boolValue
            }
            for value in dict.values {
                if let result = isLastPackage(in: value) {
                    return result
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for item in array {
                if let result = isLastPackage(in: item) {
                    return result
                }
            }
        }
        return nil
    }

    private static func extractDoubaoText(in object: Any) -> String? {
        if let dict = object as? [String: Any],
           let result = dict["result"] as? [String: Any],
           let text = sanitizedText(result["text"] as? String) {
            return text
        }

        var candidates: [String] = []
        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                for key in ["text", "transcript", "utterance", "utterance_text", "result_text"] {
                    if let text = sanitizedText(dict[key] as? String) {
                        candidates.append(text)
                    }
                }
                for key in ["result", "results", "utterances", "payload_msg", "payload", "data", "nbest", "alternatives"] {
                    if let value = dict[key] {
                        walk(value)
                    }
                }
                for value in dict.values where value is [String: Any] || value is [Any] {
                    walk(value)
                }
                return
            }

            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }

        walk(object)
        return candidates.max(by: { $0.count < $1.count })
    }

    private static func sanitizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLikelyIdentifierText(trimmed) else { return nil }
        return trimmed
    }

    private static func isLikelyIdentifierText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        if trimmed.range(of: uuidPattern, options: .regularExpression) != nil {
            return true
        }

        let compactIDPattern = #"^[0-9a-fA-F_-]{16,}$"#
        if trimmed.range(of: compactIDPattern, options: .regularExpression) != nil,
           trimmed.rangeOfCharacter(from: .letters) != nil,
           trimmed.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }

        let compact = trimmed.replacingOccurrences(of: "-", with: "")
        if compact.count >= 24,
           compact.allSatisfy({ $0.isHexDigit }) {
            return true
        }

        return false
    }

    private static func looksLikeGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1F && data[1] == 0x8B
    }
}
