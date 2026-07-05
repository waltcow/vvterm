import Foundation

enum DoubaoASRConfigurationError: LocalizedError, Equatable {
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(localized: "Doubao endpoint must be a wss://openspeech.bytedance.com streaming URL.")
        }
    }
}

enum DoubaoASRConfiguration {
    static let modelV2 = "volc.seedasr.sauc.duration"
    static let modelV1 = "volc.bigasr.sauc.duration"
    static let defaultStreamingEndpointV2 = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
    static let defaultStreamingEndpointV1 = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
    static let streamingSampleRate = 16_000
    static let streamingBitsPerSample = 16
    static let streamingChannelCount = 1
    static let recommendedStreamingPacketBytes =
        (streamingSampleRate * streamingBitsPerSample * streamingChannelCount / 8) / 5

    private static let allowedHost = "openspeech.bytedance.com"
    private static let allowedPaths: Set<String> = [
        "/api/v3/sauc/bigmodel_async",
        "/api/v3/sauc/bigmodel"
    ]

    static func resolvedResourceID(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? modelV2 : trimmed
    }

    static func resolvedStreamingEndpoint(_ endpoint: String, model: String) throws -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch resolvedResourceID(model) {
            case modelV1:
                return defaultStreamingEndpointV1
            default:
                return defaultStreamingEndpointV2
            }
        }

        guard let components = URLComponents(string: trimmed),
              components.scheme == "wss",
              components.host == allowedHost,
              allowedPaths.contains(components.path) else {
            throw DoubaoASRConfigurationError.invalidEndpoint
        }
        return trimmed
    }

    static func languageParameter(for appLanguageCode: String) -> String? {
        switch appLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "zh":
            return "zh-CN"
        case "en":
            return "en-US"
        case "ja":
            return "ja-JP"
        case "ko":
            return "ko-KR"
        case "es":
            return "es-MX"
        default:
            return nil
        }
    }

    static func int16PCMData(from samples: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = min(max(sample, -1.0), 1.0)
            let scaled = clamped < 0 ? clamped * 32768 : clamped * 32767
            var value = Int16(scaled).littleEndian
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    static func popRecommendedStreamingChunk(
        from buffer: inout Data,
        includeTrailingPartial: Bool
    ) -> Data? {
        guard buffer.count >= recommendedStreamingPacketBytes || (includeTrailingPartial && !buffer.isEmpty) else {
            return nil
        }

        let chunkSize = min(buffer.count, recommendedStreamingPacketBytes)
        let payload = Data(buffer.prefix(chunkSize))
        buffer.removeSubrange(0..<chunkSize)
        return payload
    }
}
