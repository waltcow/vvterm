import XCTest
@testable import VVTerm

final class DoubaoASRConfigurationTests: XCTestCase {
    func testResolvedStreamingEndpointUsesModelDefaults() throws {
        XCTAssertEqual(
            try DoubaoASRConfiguration.resolvedStreamingEndpoint("", model: DoubaoASRConfiguration.modelV2),
            DoubaoASRConfiguration.defaultStreamingEndpointV2
        )
        XCTAssertEqual(
            try DoubaoASRConfiguration.resolvedStreamingEndpoint("   ", model: DoubaoASRConfiguration.modelV1),
            DoubaoASRConfiguration.defaultStreamingEndpointV1
        )
        XCTAssertEqual(
            try DoubaoASRConfiguration.resolvedStreamingEndpoint("", model: "unknown-model"),
            DoubaoASRConfiguration.defaultStreamingEndpointV2
        )
    }

    func testResolvedStreamingEndpointAcceptsAllowlistedDoubaoURLs() throws {
        let endpoint = " wss://openspeech.bytedance.com/api/v3/sauc/bigmodel "

        XCTAssertEqual(
            try DoubaoASRConfiguration.resolvedStreamingEndpoint(endpoint, model: DoubaoASRConfiguration.modelV2),
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
        )
    }

    func testResolvedStreamingEndpointRejectsUnsafeURLs() {
        let invalidEndpoints = [
            "ws://openspeech.bytedance.com/api/v3/sauc/bigmodel",
            "https://openspeech.bytedance.com/api/v3/sauc/bigmodel",
            "wss://example.com/api/v3/sauc/bigmodel",
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream",
            "not a url"
        ]

        for endpoint in invalidEndpoints {
            XCTAssertThrowsError(
                try DoubaoASRConfiguration.resolvedStreamingEndpoint(endpoint, model: DoubaoASRConfiguration.modelV2),
                "Expected endpoint to be rejected: \(endpoint)"
            )
        }
    }

    func testLanguageMappingOnlySendsKnownDoubaoCodes() {
        let expectations: [(String, String?)] = [
            ("auto", nil),
            ("zh", "zh-CN"),
            ("en", "en-US"),
            ("ja", "ja-JP"),
            ("ko", "ko-KR"),
            ("es", "es-MX"),
            ("fr", nil),
            ("de", nil),
            ("pt", nil),
            ("ru", nil),
            ("", nil),
            ("unknown", nil)
        ]

        for (appCode, doubaoCode) in expectations {
            XCTAssertEqual(DoubaoASRConfiguration.languageParameter(for: appCode), doubaoCode)
        }
    }

    func testFloatSamplesConvertToLittleEndianInt16PCM() {
        let data = DoubaoASRConfiguration.int16PCMData(from: [-2.0, -1.0, -0.5, 0, 0.5, 1.0, 2.0])

        XCTAssertEqual(data.count, 14)
        XCTAssertEqual(data.int16ValuesLittleEndian(), [-32768, -32768, -16384, 0, 16383, 32767, 32767])
    }

    func testRecommendedChunkingUses6400BytesAndFlushesTrailingPartial() {
        var buffer = Data(repeating: 7, count: 7000)

        let firstChunk = DoubaoASRConfiguration.popRecommendedStreamingChunk(
            from: &buffer,
            includeTrailingPartial: false
        )
        XCTAssertEqual(firstChunk?.count, 6400)
        XCTAssertEqual(buffer.count, 600)

        XCTAssertNil(
            DoubaoASRConfiguration.popRecommendedStreamingChunk(
                from: &buffer,
                includeTrailingPartial: false
            )
        )
        XCTAssertEqual(buffer.count, 600)

        let trailingChunk = DoubaoASRConfiguration.popRecommendedStreamingChunk(
            from: &buffer,
            includeTrailingPartial: true
        )
        XCTAssertEqual(trailingChunk?.count, 600)
        XCTAssertTrue(buffer.isEmpty)
    }
}

private extension Data {
    func int16ValuesLittleEndian() -> [Int16] {
        stride(from: 0, to: count, by: 2).map { offset in
            let low = UInt16(self[offset])
            let high = UInt16(self[offset + 1]) << 8
            return Int16(bitPattern: high | low)
        }
    }
}
