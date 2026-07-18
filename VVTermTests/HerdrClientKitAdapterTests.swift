import Foundation
import Testing
@testable import VVTerm

struct HerdrClientKitAdapterTests {
    @Test
    func createsProtocol16HelloAndCompletesFragmentedHandshake() async throws {
        #expect(HerdrClientKitAdapter.protocolVersion == 16)
        let adapter = try HerdrClientKitAdapter(cols: 80, rows: 24)

        #expect(try await adapter.drainOutbound() == [
            Data([9, 0, 0, 0, 0, 16, 80, 24, 0, 0, 1, 0, 0]),
        ])

        let welcome = Data([4, 0, 0, 0, 0, 16, 1, 0])
        try await adapter.feed(welcome.prefix(3))
        #expect(try await adapter.nextEvent() == nil)
        try await adapter.feed(welcome.dropFirst(3))
        #expect(try await adapter.nextEvent() == .welcome(protocolVersion: 16))
    }

    @Test
    func emitsAnsiAndEncodesInputResizeScrollAndDetach() async throws {
        let adapter = try HerdrClientKitAdapter(cols: 80, rows: 24)
        _ = try await adapter.drainOutbound()
        try await adapter.feed(Data([4, 0, 0, 0, 0, 16, 1, 0]))
        _ = try await adapter.nextEvent()

        try await adapter.feed(Data([
            10, 0, 0, 0, 2, 1, 120, 40, 1, 4, 0x1B, 0x5B, 0x32, 0x4A,
        ]))
        #expect(try await adapter.nextEvent() == .ansi(
            sequence: 1,
            width: 120,
            height: 40,
            full: true,
            bytes: Data([0x1B, 0x5B, 0x32, 0x4A])
        ))

        try await adapter.sendInput(Data([0, 10, 13, 27, 255]))
        try await adapter.resize(cols: 120, rows: 40)
        try await adapter.scroll(direction: .up, lines: 3)
        try await adapter.detach()
        #expect(try await adapter.drainOutbound() == [
            Data([7, 0, 0, 0, 1, 5, 0, 10, 13, 27, 255]),
            Data([5, 0, 0, 0, 3, 120, 40, 0, 0]),
            Data([7, 0, 0, 0, 6, 0, 0, 3, 0, 0, 0]),
            Data([1, 0, 0, 0, 4]),
        ])
    }

    @Test
    func surfacesProtocolMismatchAsDeterministicError() async throws {
        let adapter = try HerdrClientKitAdapter(cols: 80, rows: 24)
        _ = try await adapter.drainOutbound()

        await #expect(throws: HerdrClientKitAdapterError.self) {
            try await adapter.feed(Data([4, 0, 0, 0, 0, 17, 1, 0]))
        }
    }
}
