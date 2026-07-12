import Foundation
import Testing
@testable import VVTerm

struct HerdrTerminalSessionCodecTests {
    @Test
    func decodesFragmentedFrameAndClosedRecords() throws {
        let frame = #"{"type":"terminal.frame","seq":7,"encoding":"ansi","width":120,"height":40,"full":true,"bytes":"G1sySg=="}"#
        let closed = #"{"type":"terminal.closed","reason":"server stopped"}"#
        let input = Data((frame + "\n" + closed + "\n").utf8)
        var decoder = HerdrTerminalSessionDecoder(maxLineBytes: 1024)

        #expect(try decoder.append(input.prefix(13)).isEmpty)
        let events = try decoder.append(input.dropFirst(13))

        #expect(events == [
            .frame(HerdrTerminalFrame(
                sequence: 7,
                width: 120,
                height: 40,
                full: true,
                bytes: Data([0x1B, 0x5B, 0x32, 0x4A])
            )),
            .closed(reason: "server stopped"),
        ])
    }

    @Test
    func rejectsUnsupportedEncoding() throws {
        let line = Data((#"{"type":"terminal.frame","seq":1,"encoding":"cells","width":80,"height":24,"full":true,"bytes":""}"# + "\n").utf8)
        var decoder = HerdrTerminalSessionDecoder(maxLineBytes: 1024)

        #expect(throws: HerdrTerminalSessionCodecError.unsupportedEncoding("cells")) {
            try decoder.append(line)
        }
    }

    @Test
    func rejectsBooleanWhereProtocolRequiresInteger() {
        let line = Data((#"{"type":"terminal.frame","seq":true,"encoding":"ansi","width":80,"height":24,"full":true,"bytes":""}"# + "\n").utf8)
        var decoder = HerdrTerminalSessionDecoder(maxLineBytes: 1024)

        #expect(throws: HerdrTerminalSessionCodecError.invalidRecord) {
            try decoder.append(line)
        }
    }

    @Test
    func enforcesBoundOnUnterminatedLine() {
        var decoder = HerdrTerminalSessionDecoder(maxLineBytes: 8)

        #expect(throws: HerdrTerminalSessionCodecError.lineTooLarge(limit: 8)) {
            try decoder.append(Data(repeating: 0x41, count: 9))
        }
    }

    @Test
    func encodesBinaryInputAsBase64NDJSON() throws {
        let data = try HerdrTerminalSessionEncoder.encode(.input(Data([0, 0x0A, 0xFF])))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["type"] as? String == "terminal.input")
        #expect(object["bytes"] as? String == "AAr/")
        #expect(data.last == 0x0A)
    }

    @Test
    func encodesResizeScrollAndReleaseCommands() throws {
        let resize = try decodeObject(.resize(cols: 100, rows: 30, cellWidthPixels: 8, cellHeightPixels: 16))
        #expect(resize["type"] as? String == "terminal.resize")
        #expect(resize["cols"] as? Int == 100)
        #expect(resize["cell_width_px"] as? Int == 8)

        let scroll = try decodeObject(.scroll(direction: .up, lines: 3, source: .pageKey))
        #expect(scroll["type"] as? String == "terminal.scroll")
        #expect(scroll["direction"] as? String == "up")
        #expect(scroll["source"] as? String == "page_key")

        let release = try decodeObject(.release)
        #expect(release["type"] as? String == "terminal.release")
    }

    private func decodeObject(_ command: HerdrTerminalControlCommand) throws -> [String: Any] {
        let data = try HerdrTerminalSessionEncoder.encode(command)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
