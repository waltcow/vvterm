import Foundation
import HerdrClientKit

nonisolated enum HerdrClientKitAdapterError: Error, Equatable, Sendable {
    case creationFailed
    case operationFailed(status: Int32, message: String)
    case invalidBuffer
    case unknownEvent(UInt32)
}
nonisolated enum HerdrClientKitEvent: Equatable, Sendable {
    case welcome(protocolVersion: UInt32)
    case ansi(sequence: UInt64, width: UInt16, height: UInt16, full: Bool, bytes: Data)
    case graphics(Data)
    case shutdown(reason: String?)
}

actor HerdrClientKitAdapter {
    private let client: OpaquePointer

    static var protocolVersion: UInt32 {
        herdr_client_protocol_version()
    }

    init(cols: UInt16, rows: UInt16) throws {
        guard let client = herdr_client_new(cols, rows) else {
            throw HerdrClientKitAdapterError.creationFailed
        }
        self.client = client
    }

    deinit {
        herdr_client_free(client)
    }

    func feed(_ data: Data) throws {
        let status = data.withUnsafeBytes { bytes in
            herdr_client_feed(
                client,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count
            )
        }
        try check(status)
    }

    func sendInput(_ data: Data) throws {
        let status = data.withUnsafeBytes { bytes in
            herdr_client_send_input(
                client,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count
            )
        }
        try check(status)
    }

    func resize(cols: UInt16, rows: UInt16) throws {
        try check(herdr_client_resize(client, cols, rows))
    }

    func scroll(direction: HerdrScrollDirection, lines: UInt16) throws {
        let rawDirection = switch direction {
        case .up:
            UInt32(HERDR_SCROLL_UP)
        case .down:
            UInt32(HERDR_SCROLL_DOWN)
        }
        try check(herdr_client_scroll(client, rawDirection, lines))
    }

    func detach() throws {
        try check(herdr_client_detach(client))
    }

    func drainOutbound() throws -> [Data] {
        var frames: [Data] = []
        while true {
            var buffer = herdr_buffer_t(ptr: nil, len: 0, capacity: 0)
            let status = herdr_client_take_outbound(client, &buffer)
            if status == HERDR_STATUS_EMPTY {
                return frames
            }
            try check(status)
            frames.append(try copyAndFree(&buffer))
        }
    }

    func nextEvent() throws -> HerdrClientKitEvent? {
        var event = herdr_event_t(
            kind: 0,
            sequence: 0,
            width: 0,
            height: 0,
            full: 0,
            data: herdr_buffer_t(ptr: nil, len: 0, capacity: 0)
        )
        let status = herdr_client_next_event(client, &event)
        if status == HERDR_STATUS_EMPTY {
            return nil
        }
        try check(status)
        defer { herdr_event_free(&event) }

        let data = try copy(event.data)
        switch event.kind {
        case UInt32(HERDR_EVENT_WELCOME):
            return .welcome(protocolVersion: UInt32(event.sequence))
        case UInt32(HERDR_EVENT_ANSI):
            return .ansi(
                sequence: event.sequence,
                width: event.width,
                height: event.height,
                full: event.full != 0,
                bytes: data
            )
        case UInt32(HERDR_EVENT_GRAPHICS):
            return .graphics(data)
        case UInt32(HERDR_EVENT_SHUTDOWN):
            return .shutdown(reason: data.isEmpty ? nil : String(data: data, encoding: .utf8))
        default:
            throw HerdrClientKitAdapterError.unknownEvent(event.kind)
        }
    }

    private func check(_ status: Int32) throws {
        guard status == HERDR_STATUS_OK else {
            throw HerdrClientKitAdapterError.operationFailed(
                status: status,
                message: takeError() ?? "HerdrClientKit operation failed"
            )
        }
    }

    private func takeError() -> String? {
        var buffer = herdr_buffer_t(ptr: nil, len: 0, capacity: 0)
        guard herdr_client_take_error(client, &buffer) == HERDR_STATUS_OK else {
            return nil
        }
        defer { herdr_buffer_free(&buffer) }
        guard let data = try? copy(buffer) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func copyAndFree(_ buffer: inout herdr_buffer_t) throws -> Data {
        defer { herdr_buffer_free(&buffer) }
        return try copy(buffer)
    }

    private func copy(_ buffer: herdr_buffer_t) throws -> Data {
        guard buffer.len > 0 else { return Data() }
        guard let pointer = buffer.ptr else {
            throw HerdrClientKitAdapterError.invalidBuffer
        }
        return Data(bytes: pointer, count: buffer.len)
    }
}
