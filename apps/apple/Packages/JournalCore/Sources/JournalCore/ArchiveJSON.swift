import Foundation

/// A member name as the bytes of its UTF-8 text. Swift compares strings by canonical equivalence, so the Kelvin sign
/// (U+212A) equals `K` and a composed and a decomposed `é` are one name; other readers compare bytes, and two readers
/// must see the same members (protocol/archive.md, Rules for both kinds).
struct ArchiveJSONKey: Hashable, ExpressibleByStringLiteral {
    let bytes: [UInt8]

    init(bytes: [UInt8]) { self.bytes = bytes }

    init(stringLiteral value: String) { bytes = Array(value.utf8) }

    var text: String { String(decoding: bytes, as: UTF8.self) }
}

/// A JSON value read by `StrictJSON`.
enum ArchiveJSONValue: Equatable {
    case object([ArchiveJSONKey: ArchiveJSONValue])
    case array([ArchiveJSONValue])
    case string(String)
    /// The number exactly as written, so a reader can refuse floats, exponents and leading zeros itself.
    case number(String)
    case bool(Bool)
    case null

    var object: [ArchiveJSONKey: ArchiveJSONValue]? {
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
/// member name is an error here. Names are compared as bytes. It also refuses a byte order mark, comments, trailing
/// commas, anything nested deeper than `ArchiveLimits.jsonDepth` and more values than its caller allows.
///
/// Memory is bounded by the input and by the value limit: members of the top-level object that the caller doesn't
/// name are checked but never built, so 16 MiB of `0,` costs no more than 16 MiB of `{}` or of nothing.
struct StrictJSON {
    private let bytes: [UInt8]
    private let keeping: Set<ArchiveJSONKey>?
    private let maximumValues: Int
    private var position = 0
    private var values = 0

    /// `keeping` names the members of the top-level object to read; the others are validated and dropped. Nil keeps
    /// everything. `maximumValues` counts every value, of every kind, at every depth.
    static func parse(_ data: Data, keeping: Set<ArchiveJSONKey>? = nil, maximumValues: Int) throws -> ArchiveJSONValue
    {
        var parser = StrictJSON(bytes: Array(data), keeping: keeping, maximumValues: maximumValues)
        parser.skipWhitespace()
        let value = try parser.value(depth: 0, retain: true)
        parser.skipWhitespace()
        guard parser.position == parser.bytes.count else { throw JournalError.invalidData }
        return value
    }

    private init(bytes: [UInt8], keeping: Set<ArchiveJSONKey>?, maximumValues: Int) {
        self.bytes = bytes
        self.keeping = keeping
        self.maximumValues = maximumValues
    }

    private var current: UInt8? { position < bytes.count ? bytes[position] : nil }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { position += 1 }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard current == byte else { throw JournalError.invalidData }
        position += 1
    }

    /// With `retain` false the value is read and checked but not kept: containers are not built and the result is
    /// `.null`.
    private mutating func value(depth: Int, retain: Bool) throws -> ArchiveJSONValue {
        values += 1
        guard values <= maximumValues, let byte = current else { throw JournalError.invalidData }
        switch byte {
        case 0x7B: return try object(depth: depth, retain: retain)
        case 0x5B: return try array(depth: depth, retain: retain)
        case 0x22:
            // One String, which also checks the bytes are UTF-8; a string that isn't kept is dropped at once.
            guard let text = Self.validText(try rawString()) else { throw JournalError.invalidData }
            return retain ? .string(text) : .null
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

    /// A container nested `jsonDepth` deep is the deepest allowed: the top-level one is depth 0 and the first.
    private func requireRoom(forContainerAt depth: Int) throws {
        guard depth < ArchiveLimits.jsonDepth else { throw JournalError.invalidData }
    }

    private mutating func object(depth: Int, retain: Bool) throws -> ArchiveJSONValue {
        try requireRoom(forContainerAt: depth)
        try expect(0x7B)
        var members: [ArchiveJSONKey: ArchiveJSONValue] = [:]
        var dropped: Set<ArchiveJSONKey> = []
        skipWhitespace()
        if current == 0x7D {
            position += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard current == 0x22 else { throw JournalError.invalidData }
            let nameBytes = try rawString()
            guard Self.validText(nameBytes) != nil else { throw JournalError.invalidData }
            let name = ArchiveJSONKey(bytes: nameBytes)
            guard members[name] == nil, !dropped.contains(name) else { throw JournalError.invalidData }
            skipWhitespace()
            try expect(0x3A)
            skipWhitespace()
            let keepMember = retain && (depth > 0 || keeping?.contains(name) ?? true)
            let member = try value(depth: depth + 1, retain: keepMember)
            if keepMember { members[name] = member } else { dropped.insert(name) }
            skipWhitespace()
            if current == 0x2C {
                position += 1
                continue
            }
            try expect(0x7D)
            return .object(members)
        }
    }

    private mutating func array(depth: Int, retain: Bool) throws -> ArchiveJSONValue {
        try requireRoom(forContainerAt: depth)
        try expect(0x5B)
        var items: [ArchiveJSONValue] = []
        skipWhitespace()
        if current == 0x5D {
            position += 1
            return .array(items)
        }
        while true {
            skipWhitespace()
            let item = try value(depth: depth + 1, retain: retain)
            if retain { items.append(item) }
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

    /// The text of `bytes` if they are valid UTF-8: decoding replaces what is invalid, so only valid bytes come back
    /// unchanged. (Foundation's `String(bytes:encoding:)` would do the same with an extra copy of a large string.)
    private static func validText(_ bytes: [UInt8]) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
        return text.utf8.elementsEqual(bytes) ? text : nil
    }

    /// The bytes of a string with its escapes resolved. The caller checks that they are UTF-8.
    private mutating func rawString() throws -> [UInt8] {
        try expect(0x22)
        var decoded: [UInt8] = []
        // The text can't be longer than the bytes up to the closing quote; reserving them avoids the doubling of a
        // growing array, which would hold twice a 16 MiB string for a moment.
        var end = position
        while end < bytes.count, bytes[end] != 0x22 { end += bytes[end] == 0x5C ? 2 : 1 }
        decoded.reserveCapacity(min(end, bytes.count) - position)
        while true {
            guard let byte = current else { throw JournalError.invalidData }
            position += 1
            switch byte {
            case 0x22: return decoded
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
