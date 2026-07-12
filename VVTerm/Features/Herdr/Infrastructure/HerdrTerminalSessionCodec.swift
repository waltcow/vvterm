import Foundation
import CoreFoundation

nonisolated struct HerdrTerminalFrame: Equatable, Sendable {
    let sequence: UInt64
    let width: UInt16
    let height: UInt16
    let full: Bool
    let bytes: Data
}

nonisolated enum HerdrTerminalSessionEvent: Equatable, Sendable {
    case frame(HerdrTerminalFrame)
    case closed(reason: String?)
}

nonisolated enum HerdrTerminalSessionCodecError: Error, Equatable {
    case lineTooLarge(limit: Int)
    case invalidRecord
    case unsupportedEncoding(String)
    case invalidDimensions
}

nonisolated struct HerdrTerminalSessionDecoder: Sendable {
    private var buffered = Data()
    private let maxLineBytes: Int

    init(maxLineBytes: Int = HerdrPinnedContract.maxTerminalSessionLineBytes) {
        self.maxLineBytes = maxLineBytes
    }

    mutating func append(_ data: Data) throws -> [HerdrTerminalSessionEvent] {
        if buffered.count + data.count > maxLineBytes, !data.contains(0x0A) {
            throw HerdrTerminalSessionCodecError.lineTooLarge(limit: maxLineBytes)
        }
        buffered.append(data)

        var events: [HerdrTerminalSessionEvent] = []
        while let newline = buffered.firstIndex(of: 0x0A) {
            let line = buffered[..<newline]
            buffered.removeSubrange(...newline)
            if line.isEmpty {
                continue
            }
            guard line.count <= maxLineBytes else {
                throw HerdrTerminalSessionCodecError.lineTooLarge(limit: maxLineBytes)
            }
            events.append(try Self.decodeRecord(Data(line)))
        }
        guard buffered.count <= maxLineBytes else {
            throw HerdrTerminalSessionCodecError.lineTooLarge(limit: maxLineBytes)
        }
        return events
    }

    private static func decodeRecord(_ data: Data) throws -> HerdrTerminalSessionEvent {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            throw HerdrTerminalSessionCodecError.invalidRecord
        }

        switch type {
        case "terminal.frame":
            guard
                let sequence = uint64(object["seq"]),
                let width = uint16(object["width"]),
                let height = uint16(object["height"]),
                width > 0,
                height > 0,
                let full = object["full"] as? Bool,
                let encoding = object["encoding"] as? String,
                let encodedBytes = object["bytes"] as? String,
                let bytes = Data(base64Encoded: encodedBytes)
            else {
                throw HerdrTerminalSessionCodecError.invalidRecord
            }
            guard encoding == "ansi" else {
                throw HerdrTerminalSessionCodecError.unsupportedEncoding(encoding)
            }
            return .frame(HerdrTerminalFrame(
                sequence: sequence,
                width: width,
                height: height,
                full: full,
                bytes: bytes
            ))

        case "terminal.closed":
            return .closed(reason: object["reason"] as? String)

        default:
            throw HerdrTerminalSessionCodecError.invalidRecord
        }
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.uint64Value
        return NSNumber(value: result) == number ? result : nil
    }

    private static func uint16(_ value: Any?) -> UInt16? {
        guard let number = value as? NSNumber else { return nil }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let result = number.uint64Value
        guard result <= UInt16.max, NSNumber(value: result) == number else { return nil }
        return UInt16(result)
    }
}

nonisolated enum HerdrTerminalScrollDirection: String, Encodable, Sendable {
    case up
    case down
}

nonisolated enum HerdrTerminalScrollSource: String, Encodable, Sendable {
    case wheel
    case pageKey = "page_key"
}

nonisolated enum HerdrTerminalControlCommand: Encodable, Equatable, Sendable {
    case input(Data)
    case resize(cols: UInt16, rows: UInt16, cellWidthPixels: UInt32 = 0, cellHeightPixels: UInt32 = 0)
    case scroll(direction: HerdrTerminalScrollDirection, lines: UInt16, source: HerdrTerminalScrollSource = .wheel)
    case release

    private enum CodingKeys: String, CodingKey {
        case type
        case bytes
        case cols
        case rows
        case cellWidthPixels = "cell_width_px"
        case cellHeightPixels = "cell_height_px"
        case direction
        case lines
        case source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .input(bytes):
            try container.encode("terminal.input", forKey: .type)
            try container.encode(bytes, forKey: .bytes)
        case let .resize(cols, rows, cellWidthPixels, cellHeightPixels):
            try container.encode("terminal.resize", forKey: .type)
            try container.encode(cols, forKey: .cols)
            try container.encode(rows, forKey: .rows)
            try container.encode(cellWidthPixels, forKey: .cellWidthPixels)
            try container.encode(cellHeightPixels, forKey: .cellHeightPixels)
        case let .scroll(direction, lines, source):
            try container.encode("terminal.scroll", forKey: .type)
            try container.encode(direction, forKey: .direction)
            try container.encode(lines, forKey: .lines)
            try container.encode(source, forKey: .source)
        case .release:
            try container.encode("terminal.release", forKey: .type)
        }
    }
}

nonisolated enum HerdrTerminalSessionEncoder {
    static func encode(_ command: HerdrTerminalControlCommand) throws -> Data {
        var data = try JSONEncoder().encode(command)
        data.append(0x0A)
        return data
    }
}
