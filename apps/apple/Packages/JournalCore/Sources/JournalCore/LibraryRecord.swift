import CoreFoundation
import Foundation

/// A JSON value kept as read, so values and members this version doesn't know are written back unchanged.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// A value read with `JSONSerialization`, which tells booleans from numbers only through their type.
    init?(foundation value: Any) {
        switch value {
        case is NSNull: self = .null
        case let string as String: self = .string(string)
        case let decimal as NSDecimalNumber: self = .number(decimal.doubleValue)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .number(number.doubleValue)
            } else {
                self = .integer(number.int64Value)
            }
        case let array as [Any]:
            var values: [JSONValue] = []
            for element in array {
                guard let converted = JSONValue(foundation: element) else { return nil }
                values.append(converted)
            }
            self = .array(values)
        case let object as [String: Any]:
            var members: [String: JSONValue] = [:]
            for (key, element) in object {
                guard let converted = JSONValue(foundation: element) else { return nil }
                members[key] = converted
            }
            self = .object(members)
        default: return nil
        }
    }
    /// The value as `JSONSerialization` writes it.
    public var foundationValue: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .integer(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.foundationValue)
        case .object(let members): members.mapValues(\.foundationValue)
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let members): try container.encode(members)
        }
    }
}

/// The record that holds pins and journal order for the whole library (docs/design/pinned-entries.md, "Proposal: one
/// library record"; protocol/records.md, "The library record"). Every library has it under the same identity.
public struct LibraryRecord: Equatable, Sendable {
    /// The same in every library: devices that create it separately create the same record.
    public static let id = UUID(
        uuid: (0x9F, 0x29, 0x7F, 0x28, 0x7D, 0x13, 0x41, 0xB7, 0xA7, 0xEA, 0x83, 0xD0, 0x6C, 0xAC, 0x69, 0x24))
    public static let kind = "library"
    static let idText = id.uuidString.lowercased()
    /// The version this client reads and writes. A higher one is kept byte for byte and never written.
    static let version = 1
    /// What an older version that has to name the record shows.
    static let title = "Pinned Entries and Journal Order"

    /// `values`: keys `‹namespace›/‹lower-case UUID or name›`, including ones this version doesn't know.
    var values: [String: JSONValue]
    /// Every other top-level member as read, so members a later version adds are written back.
    var members: [String: JSONValue]

    init(values: [String: JSONValue] = [:], members: [String: JSONValue] = [:]) {
        self.values = values
        self.members = members
    }

    /// Reads a record's plaintext. Anything other than a version-1 library record with a `values` object, such as
    /// one from a newer version, is held: kept as it is, read-only.
    static func read(_ plaintext: Data) -> LibraryContent {
        guard let object = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
            let converted = JSONValue(foundation: object), case .object(var members) = converted,
            members["kind"] == .string(kind), case .string(let identity) = members["id"],
            UUID(uuidString: identity) == id, members["version"] == .integer(Int64(version)),
            case .object(let values) = members["values"]
        else { return .held }
        members["values"] = nil
        return .readable(LibraryRecord(values: values, members: members))
    }
    /// The record's JSON, with the fixed members written as this version writes them.
    func encoded(modifiedAt: Date) throws -> Data {
        var object = members
        object["id"] = .string(Self.id.uuidString)
        object["kind"] = .string(Self.kind)
        object["modifiedAt"] = .string(JournalCoding.timestamp(modifiedAt))
        object["title"] = .string(Self.title)
        object["values"] = .object(values)
        object["version"] = .integer(Int64(Self.version))
        return try JournalCoding.encoder().encode(object)
    }
}

/// What a stored library record holds for this version.
enum LibraryContent: Equatable {
    case readable(LibraryRecord)
    /// Written by a newer version, or not a library record this version can read: never written over.
    case held

    var record: LibraryRecord? {
        guard case .readable(let record) = self else { return nil }
        return record
    }
}

/// Pins and journal ranks as the lists show them.
public struct LibraryArrangement: Equatable, Sendable {
    /// Entries pinned, including ones not on this device (yet); permanently deleted ones are left out.
    public var pinned: Set<UUID>
    /// Valid ranks by journal; invalid ones are ignored.
    public var ranks: [UUID: String]
    /// False while the library record is from a newer version: pins and order can't be shown or changed.
    public var available: Bool

    public static let empty = LibraryArrangement(pinned: [], ranks: [:], available: true)

    public init(pinned: Set<UUID>, ranks: [UUID: String], available: Bool) {
        self.pinned = pinned
        self.ranks = ranks
        self.available = available
    }
    init(values: [String: JSONValue], deleted: Set<UUID> = []) {
        var pinned = Set<UUID>()
        var ranks: [UUID: String] = [:]
        for (key, value) in values {
            if let entry = LibraryKey.identity(key, in: LibraryKey.pinned), !deleted.contains(entry),
                LibraryKey.isPinned(value)
            {
                pinned.insert(entry)
            } else if let journal = LibraryKey.identity(key, in: LibraryKey.rank), case .string(let rank) = value,
                JournalRanks.isValid(rank)
            {
                ranks[journal] = rank
            }
        }
        self.init(pinned: pinned, ranks: ranks, available: true)
    }
}

/// The keys of the library record's values.
enum LibraryKey {
    static let pinned = "pinned"
    static let rank = "journal-rank"

    static func pin(_ entry: UUID) -> String { "\(pinned)/\(entry.uuidString.lowercased())" }
    static func rank(_ journal: UUID) -> String { "\(rank)/\(journal.uuidString.lowercased())" }
    /// The record a key of `namespace` names.
    static func identity(_ key: String, in namespace: String) -> UUID? {
        let prefix = namespace + "/"
        guard key.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(key.dropFirst(prefix.count)))
    }
    /// Writers write `true`; anything other than `false` or `null` counts, so a later version can store more.
    static func isPinned(_ value: JSONValue) -> Bool { value != .bool(false) && value != .null }
}

/// A change this device made to one key that the server hasn't confirmed yet (docs/design/pinned-entries.md,
/// "Conflicts", rule 1).
struct LibraryIntent: Codable, Equatable, Sendable {
    /// The new value; ignored for a removal.
    var value: JSONValue
    /// The key is removed.
    var removes: Bool
    /// Applied only where the server's version has no value for the key: automatic ranks, and keys whose lineage is
    /// unknown after a restore.
    var ifAbsent: Bool
    /// Sent in an operation, which the server may or may not have applied.
    var sent: Bool
    /// When this device made it, as `LibraryChanges.generation` counts. A payload written before it doesn't carry it,
    /// even when it holds the same value (pinned, unpinned, pinned again while an earlier answer was lost).
    var generation: Int?

    static func set(_ value: JSONValue?) -> Self {
        LibraryIntent(value: value ?? .null, removes: value == nil, ifAbsent: false, sent: false)
    }
    static func ifAbsent(_ value: JSONValue) -> Self {
        LibraryIntent(value: value, removes: false, ifAbsent: true, sent: false)
    }
    /// Whether `values` already holds what this intent asks for.
    func isSatisfied(by values: [String: JSONValue], key: String) -> Bool {
        if ifAbsent { return values[key] != nil }
        return removes ? values[key] == nil : values[key] == value
    }
}

/// The intents of this device, stored sealed in `settings` (`library-changes`).
struct LibraryChanges: Codable, Equatable, Sendable {
    static let setting = "library-changes"
    static let context = "journal:v1:local:library-changes"
    var version = 1
    var changes: [String: LibraryIntent] = [:]
    /// Counts this device's changes, so each intent knows which payloads were written after it.
    var generation = 0
    /// The generation each payload this device wrote and may still send was written at, by payload digest.
    var payloads: [String: Int] = [:]
    /// The stored value couldn't be opened, so what this device changed is unknown: until the next merge, its keys
    /// that differ from the server's are treated as of unknown lineage (rule 4). Kept when stored again.
    var damaged = false

    init(changes: [String: LibraryIntent] = [:], damaged: Bool = false) {
        self.changes = changes
        self.damaged = damaged
    }
    private enum CodingKeys: String, CodingKey { case version, changes, unknownLineage, generation, payloads }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        changes = try container.decode([String: LibraryIntent].self, forKey: .changes)
        damaged = try container.decodeIfPresent(Bool.self, forKey: .unknownLineage) ?? false
        generation = try container.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        payloads = try container.decodeIfPresent([String: Int].self, forKey: .payloads) ?? [:]
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(changes, forKey: .changes)
        if damaged { try container.encode(true, forKey: .unknownLineage) }
        if generation > 0 { try container.encode(generation, forKey: .generation) }
        if !payloads.isEmpty { try container.encode(payloads, forKey: .payloads) }
    }
    /// Starts the next change of this device: the intents it sets carry its generation.
    mutating func nextGeneration() -> Int {
        generation += 1
        return generation
    }
    /// Remembers that `payload` carries every intent made so far.
    mutating func wrote(_ payload: String) {
        payloads[JournalStore.payloadDigest(payload)] = generation
    }
    /// Whether an intent was made before `payload` was written, so that payload carries it. Payloads this device
    /// didn't write, or wrote before generations were counted, carry every intent with their value.
    private func isCarried(_ intent: LibraryIntent, by payload: String?) -> Bool {
        guard let payload, let written = payloads[JournalStore.payloadDigest(payload)] else { return true }
        return (intent.generation ?? 0) <= written
    }

    /// Rule 2: the server's values with the intents applied on top.
    func merged(onto server: [String: JSONValue]) -> [String: JSONValue] {
        var values = server
        for (key, intent) in changes {
            if intent.ifAbsent {
                if values[key] == nil, !intent.removes { values[key] = intent.value }
            } else {
                values[key] = intent.removes ? nil : intent.value
            }
        }
        return values
    }
    /// Rule 3: forgets what a version the server holds already has. With this device's own `payload`, only what that
    /// payload carried: a change made again after it was written is newer, though equal.
    mutating func clear(by values: [String: JSONValue], payload: String? = nil) {
        changes = changes.filter { key, intent in
            !intent.isSatisfied(by: values, key: key) || !isCarried(intent, by: payload)
        }
    }
    /// Rule 4: the server's version may be newer or older than what this device knows. Only changes that never left
    /// this device keep their strength; everything else this device has only fills in what the server lacks.
    mutating func reconcile(local: [String: JSONValue], server: [String: JSONValue], provenLineage: Bool) {
        var reconciled: [String: LibraryIntent] = [:]
        for (key, intent) in changes {
            guard intent.sent else {
                reconciled[key] = intent
                continue
            }
            if !intent.removes { reconciled[key] = .ifAbsent(intent.value) }
        }
        if !provenLineage || damaged {
            for (key, value) in local where server[key] == nil && reconciled[key] == nil {
                reconciled[key] = .ifAbsent(value)
            }
        }
        // What reconciliation leaves is newer than any payload written before it.
        let now = nextGeneration()
        changes = reconciled.mapValues { intent in
            var intent = intent
            intent.generation = now
            return intent
        }
        damaged = false
    }
    /// Marks the intents a payload being sent carries: those it holds that were made before it was written.
    mutating func markSent(in values: [String: JSONValue], payload: String) {
        for (key, intent) in changes where intent.isSatisfied(by: values, key: key) && isCarried(intent, by: payload) {
            changes[key]?.sent = true
        }
    }
}
