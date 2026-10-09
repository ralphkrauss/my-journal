import Foundation

/// A JSON value read by `StrictJSON`.
enum ArchiveJSONValue: Equatable {
    case object([String: ArchiveJSONValue])
    case array([ArchiveJSONValue])
    case string(String)
    /// The number exactly as written, so a reader can refuse floats, exponents and leading zeros itself.
    case number(String)
    case bool(Bool)
    case null

    var object: [String: ArchiveJSONValue]? {
        if case .object(let members) = self { return members }
        return nil
    }
    var string: String? {
        if case .string(let text) = self { return text }
        return nil
    }
    var number: String? {
        if case .number(let text) = self { return text }
        return nil
    }

    /// A JSON integer without sign, fraction, exponent or leading zero, at most 2^53 - 1 (what .NET `long`,
    /// JavaScript and Swift all read the same). Anything else is not a size.
    static func exactSize(_ text: String) -> UInt64? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.count <= 16, bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        guard bytes.count == 1 || bytes[0] != 0x30 else { return nil }
        guard let value = UInt64(text), value <= (1 << 53) - 1 else { return nil }
        return value
    }
}

/// A small JSON reader for the archive header and manifest. Foundation's reader keeps the last of two members with the
/// same name, other readers keep the first, and a header read two ways would be two different archives, so a repeated
/// member name is an error here. It also refuses a byte order mark, comments, trailing commas and anything nested
/// deeper than `ArchiveLimits.jsonDepth`.
struct StrictJSON {
    private let bytes: [UInt8]
    private var position = 0

    static func parse(_ data: Data) throws -> ArchiveJSONValue {
        var parser = StrictJSON(bytes: Array(data))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.position == parser.bytes.count else { throw JournalError.invalidData }
        return value
    }

    private init(bytes: [UInt8]) { self.bytes = bytes }

    private var current: UInt8? { position < bytes.count ? bytes[position] : nil }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { position += 1 }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard current == byte else { throw JournalError.invalidData }
        position += 1
    }

    private mutating func value(depth: Int) throws -> ArchiveJSONValue {
        guard depth <= ArchiveLimits.jsonDepth, let byte = current else { throw JournalError.invalidData }
        switch byte {
        case 0x7B: return try object(depth: depth)
        case 0x5B: return try array(depth: depth)
        case 0x22: return .string(try string())
        case 0x74: return try literal("true", .bool(true))
        case 0x66: return try literal("false", .bool(false))
        case 0x6E: return try literal("null", .null)
        default: return try number()
        }
    }

    private mutating func literal(_ text: String, _ value: ArchiveJSONValue) throws -> ArchiveJSONValue {
        for expected in text.utf8 { try expect(expected) }
        return value
    }

    private mutating func object(depth: Int) throws -> ArchiveJSONValue {
        try expect(0x7B)
        var members: [String: ArchiveJSONValue] = [:]
        skipWhitespace()
        if current == 0x7D {
            position += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard current == 0x22 else { throw JournalError.invalidData }
            let name = try string()
            guard members[name] == nil else { throw JournalError.invalidData }
            skipWhitespace()
            try expect(0x3A)
            skipWhitespace()
            members[name] = try value(depth: depth + 1)
            skipWhitespace()
            if current == 0x2C {
                position += 1
                continue
            }
            try expect(0x7D)
            return .object(members)
        }
    }

    private mutating func array(depth: Int) throws -> ArchiveJSONValue {
        try expect(0x5B)
        var items: [ArchiveJSONValue] = []
        skipWhitespace()
        if current == 0x5D {
            position += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            items.append(try value(depth: depth + 1))
            skipWhitespace()
            if current == 0x2C {
                position += 1
                continue
            }
            try expect(0x5D)
            return .array(items)
        }
    }

    private mutating func number() throws -> ArchiveJSONValue {
        let start = position
        if current == 0x2D { position += 1 }
        guard let first = current, (0x30...0x39).contains(first) else { throw JournalError.invalidData }
        if first == 0x30 {
            position += 1
        } else {
            skipDigits()
        }
        if current == 0x2E {
            position += 1
            guard let digit = current, (0x30...0x39).contains(digit) else { throw JournalError.invalidData }
            skipDigits()
        }
        if current == 0x65 || current == 0x45 {
            position += 1
            if current == 0x2B || current == 0x2D { position += 1 }
            guard let digit = current, (0x30...0x39).contains(digit) else { throw JournalError.invalidData }
            skipDigits()
        }
        guard let text = String(bytes: bytes[start..<position], encoding: .utf8) else { throw JournalError.invalidData }
        return .number(text)
    }

    private mutating func skipDigits() {
        while let byte = current, (0x30...0x39).contains(byte) { position += 1 }
    }

    private mutating func string() throws -> String {
        try expect(0x22)
        var decoded: [UInt8] = []
        while true {
            guard let byte = current else { throw JournalError.invalidData }
            position += 1
            switch byte {
            case 0x22:
                guard let text = String(bytes: decoded, encoding: .utf8) else { throw JournalError.invalidData }
                return text
            case 0x5C: try appendEscape(to: &decoded)
            case 0x00..<0x20: throw JournalError.invalidData
            default: decoded.append(byte)
            }
        }
    }

    private mutating func appendEscape(to decoded: inout [UInt8]) throws {
        guard let escape = current else { throw JournalError.invalidData }
        position += 1
        switch escape {
        case 0x22, 0x5C, 0x2F: decoded.append(escape)
        case 0x62: decoded.append(0x08)
        case 0x66: decoded.append(0x0C)
        case 0x6E: decoded.append(0x0A)
        case 0x72: decoded.append(0x0D)
        case 0x74: decoded.append(0x09)
        case 0x75: decoded.append(contentsOf: Array(try unicodeEscape().utf8))
        default: throw JournalError.invalidData
        }
    }

    private mutating func unicodeEscape() throws -> String {
        let first = try hexQuad()
        var scalarValue = first
        if (0xD800...0xDBFF).contains(first) {
            try expect(0x5C)
            try expect(0x75)
            let second = try hexQuad()
            guard (0xDC00...0xDFFF).contains(second) else { throw JournalError.invalidData }
            scalarValue = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
        }
        guard let scalar = Unicode.Scalar(scalarValue) else { throw JournalError.invalidData }
        return String(Character(scalar))
    }

    private mutating func hexQuad() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current else { throw JournalError.invalidData }
            position += 1
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
            case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
            default: throw JournalError.invalidData
            }
            value = value << 4 | digit
        }
        return value
    }
}
