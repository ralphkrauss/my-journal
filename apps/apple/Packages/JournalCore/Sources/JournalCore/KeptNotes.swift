import CryptoKit
import Foundation
import GRDB

/// What this device tells the person about changes it settled on its own ("Changed on Two Devices").
public struct KeptNote: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// An entry or template changed on two devices; the other version is saved as a separate entry or template.
        case keptBoth
        /// An entry or template edited on one device and deleted permanently on another; the edit is saved separately.
        case deletedAndChanged
        /// A journal edited on one device and deleted permanently on another; it stays deleted.
        case journalDeleted
        /// A journal renamed on two devices; the later name stays.
        case journalRenamed
        /// A kind written by a newer version of this app.
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    public var id: UUID
    public var kind: Kind
    /// The record that was settled.
    public var recordID: UUID
    /// The record the row opens: the copy, or the parked entry or template.
    public var otherID: UUID?
    /// The journal's name now, or the name of what the person edited.
    public var name: String
    /// A journal name that lost.
    public var otherName: String?
    /// The other version of an entry or template was modified later than this device's, by the clocks of the two
    /// devices. Only the wording of the notice and the row uses it; nothing is decided by it.
    public var otherIsNewer: Bool?
    /// The person has seen it, or opened what it names.
    public var seen: Bool
    public var created: Date

    public init(
        kind: Kind, recordID: UUID, otherID: UUID? = nil, name: String, otherName: String? = nil,
        otherIsNewer: Bool? = nil, created: Date
    ) {
        self.id = UUID()
        self.kind = kind
        self.recordID = recordID
        self.otherID = otherID
        self.name = name
        self.otherName = otherName
        self.otherIsNewer = otherIsNewer
        self.seen = false
        self.created = created
    }
}

/// A copy or parked entry this device made on its own, so a later conflict knows it.
struct KeptCopy: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The other version of an entry or template that differed (row 3).
        case copy
        /// An edit saved next to a permanent deletion (row 4).
        case parked
        /// Written before this value was recorded: never replaced or dropped on its own.
        case unspecified

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unspecified
        }
    }

    var copyID: UUID
    var recordID: UUID
    var kind: Kind = .unspecified
    /// The device the other version came from; nil when unknown, which never matches in a replacement.
    var originDevice: UUID?
    var originRevision: Int64
    /// Lower-case hex SHA-256 of the plaintext this device holds for the copy: what it wrote, or, after a replacement,
    /// what it wrote last.
    var digest: String
    /// A later version of the other device replaced the content this device first wrote. Such a copy holds content that
    /// exists nowhere else, so it is never dropped for a version of its own identity that arrives; it goes through the
    /// ordinary rules, which keep both.
    var replaced = false
}

extension KeptCopy {
    /// Reads a value written before `kind` and `replaced` existed, which is `unspecified` and treated as replaced.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        copyID = try values.decode(UUID.self, forKey: .copyID)
        recordID = try values.decode(UUID.self, forKey: .recordID)
        kind = try values.decodeIfPresent(Kind.self, forKey: .kind) ?? .unspecified
        originDevice = try values.decodeIfPresent(UUID.self, forKey: .originDevice)
        originRevision = try values.decode(Int64.self, forKey: .originRevision)
        digest = try values.decode(String.self, forKey: .digest)
        replaced = try values.decodeIfPresent(Bool.self, forKey: .replaced) ?? (kind == .unspecified)
    }
}

/// The sealed settings key `kept-notes` (docs/design/1-1-conflicts-and-reconnect.md, 5.2). It is local: not a record,
/// never synchronized. A value that can't be opened is ignored and blocks nothing.
struct KeptNotesState: Codable, Equatable, Sendable {
    static let setting = "kept-notes"
    static let context = "journal:v1:local:kept-notes"
    static let copyLimit = 200
    static let noteLimit = 20
    static let noteLifetime: TimeInterval = 30 * 24 * 60 * 60

    var version = 1
    var copies: [KeptCopy] = []
    var notes: [KeptNote] = []
    /// The steps of the one-time pass over rows an earlier version left that have run: 1 is journals and markers, 2
    /// is the rest, entries and templates.
    var passStep = 0
    /// The rows the pass took when it first ran that are still to be settled; nil once none is, or before it ran.
    var passRecords: [UUID]?

    mutating func add(_ note: KeptNote) {
        notes.append(note)
        while notes.count > Self.noteLimit {
            // Rename notes are the only trail of a name that lost, so they go last.
            let index = notes.firstIndex { $0.kind != .journalRenamed } ?? 0
            notes.remove(at: index)
        }
    }
    /// Notes that the copy `otherID` of an entry or template was made or replaced. A replacement updates the note the
    /// copy already has, keeping whether the person saw it, so co-editing doesn't fill the list.
    mutating func noteKeptBoth(_ note: KeptNote) {
        guard let index = notes.firstIndex(where: { $0.kind == .keptBoth && $0.otherID == note.otherID }) else {
            return add(note)
        }
        notes[index].name = note.name
        notes[index].otherIsNewer = note.otherIsNewer
        notes[index].created = note.created
    }
    mutating func remember(_ copy: KeptCopy) {
        copies.removeAll { $0.copyID == copy.copyID }
        copies.append(copy)
        if copies.count > Self.copyLimit { copies.removeFirst(copies.count - Self.copyLimit) }
    }
    func isAutomaticCopy(_ id: UUID) -> Bool { copies.contains { $0.copyID == id } }
    /// Whether `id` is a copy this device made, no later version has replaced, and `plaintext`, what it holds now, is
    /// exactly what it first wrote: nobody has edited it since and its content is in the other record, so dropping it
    /// for a version of its own identity loses nothing. A replaced copy holds the replacing version's content, which
    /// exists nowhere else.
    func isFirstWrittenCopy(_ id: UUID, plaintext: Data) -> Bool {
        guard let copy = copies.first(where: { $0.copyID == id }), !copy.replaced else { return false }
        return copy.digest == Self.digest(of: plaintext)
    }
    static func digest(of plaintext: Data) -> String {
        SHA256.hash(data: plaintext).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads and writes `kept-notes`, sealed like `library-changes`.
struct KeptNotesStore {
    let key: Data
    let protection: ContentProtection

    func state(_ db: Database) throws -> KeptNotesState {
        guard
            let stored = try Data.fetchOne(
                db, sql: "SELECT value FROM settings WHERE key=?", arguments: [KeptNotesState.setting]),
            let text = String(data: stored, encoding: .utf8), let bytes = Data(base64Encoded: text)
        else { return KeptNotesState() }
        let decoder = JournalCoding.decoder()
        let opened = try? protection.decode(bytes, key: key, context: KeptNotesState.context)
        // Left readable by a version that turned on encryption without knowing this value.
        let readable = opened ?? (protection == .encrypted ? bytes : nil)
        guard let readable, let state = try? decoder.decode(KeptNotesState.self, from: readable), state.version == 1
        else { return KeptNotesState() }
        return state
    }
    func save(_ db: Database, _ state: KeptNotesState) throws {
        let sealed = try protection.encode(
            JournalCoding.encoder().encode(state), key: key, context: KeptNotesState.context)
        try db.execute(
            sql: "INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            arguments: [KeptNotesState.setting, Data(sealed.base64EncodedString().utf8)])
    }
}

extension JournalStore {
    var keptNotesStore: KeptNotesStore { KeptNotesStore(key: key, protection: protection) }
    func keptNotesState() throws -> KeptNotesState { try db.read { try keptNotesStore.state($0) } }

    /// The notes to show: the 20 most recent, newest first, without those older than 30 days (rename notes don't
    /// expire) and without those whose saved entry or template is gone.
    public func keptNotes() throws -> [KeptNote] {
        let now = clock()
        return try db.read { db in
            let notes = try keptNotesStore.state(db).notes
            let existing = try Set(
                String.fetchAll(db, sql: "SELECT id FROM records WHERE kind IN ('entry','template')"))
            return notes.filter { note in
                switch note.kind {
                case .journalRenamed: return true
                case .journalDeleted, .unknown:
                    return now.timeIntervalSince(note.created) < KeptNotesState.noteLifetime
                case .deletedAndChanged, .keptBoth:
                    guard now.timeIntervalSince(note.created) < KeptNotesState.noteLifetime else { return false }
                    return note.otherID.map { existing.contains(id($0)) } ?? false
                }
            }
            .sorted { $0.created > $1.created }
        }
    }
    /// Marks a note seen, such as when the person opens what it names.
    public func markKeptNoteSeen(_ noteID: UUID) throws {
        try db.write { db in
            var state = try keptNotesStore.state(db)
            guard let index = state.notes.firstIndex(where: { $0.id == noteID }), !state.notes[index].seen else {
                return
            }
            state.notes[index].seen = true
            try keptNotesStore.save(db, state)
            receivedChanges += 1
        }
    }
    /// Forgets every note. Nothing else changes.
    public func clearKeptNotes() throws {
        try db.write { db in
            var state = try keptNotesStore.state(db)
            guard !state.notes.isEmpty else { return }
            state.notes = []
            try keptNotesStore.save(db, state)
            receivedChanges += 1
        }
    }
}
