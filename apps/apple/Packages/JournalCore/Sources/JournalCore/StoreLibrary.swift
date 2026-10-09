import Foundation
import GRDB
import os

/// Why pins or journal order couldn't be changed.
public enum LibraryError: LocalizedError, Equatable, Sendable {
    /// The library record was written by a newer version, which this one can't change without losing content.
    case newerVersion
    /// The entry or journal isn't listed in a journal in use.
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .newerVersion: "Update My Journal to use pinned entries and journal order."
        case .unavailable: "This item is no longer available."
        }
    }
}

/// What Settings ▸ Sync explains about pins and journal order.
public struct LibrarySyncState: Equatable, Sendable {
    /// The library record is from a newer version.
    public var needsUpdate: Bool

    public init(needsUpdate: Bool = false) {
        self.needsUpdate = needsUpdate
    }
}

/// What a library rule changed besides the database: operations queued, and whether the change came from elsewhere.
struct LibraryEffects {
    var queued: [UUID] = []
    var received = false
}

/// The library record's rules over the database (docs/design/pinned-entries.md, "Conflicts"). A value rather than store
/// methods, so opening a store can convert what older versions left before anything else runs.
struct LibraryStore: Sendable {
    let key: Data
    let protection: ContentProtection
    /// "1" once this library has synchronized with a server, which takes the library record. 1.0 also wrote "0" for
    /// a server that could not; that value is read as "not yet" and replaced at the next synchronization.
    static let syncedSetting = "server-record-kinds"
    static let logger = Logger(subsystem: "io.github.ralphkrauss.myjournal", category: "library")

    struct Stored {
        let payload: String
        let revision: Int64
        let dirty: Bool
    }

    // MARK: Reading and writing

    var context: String { VaultCrypto.recordContext(id: LibraryRecord.id, kind: LibraryRecord.kind) }
    func content(_ payload: String) -> LibraryContent {
        guard let data = Data(base64Encoded: payload),
            let plaintext = try? protection.decode(data, key: key, context: context)
        else { return .held }
        return LibraryRecord.read(plaintext)
    }
    func seal(_ record: LibraryRecord) throws -> String {
        try protection.encode(record.encoded(modifiedAt: Date()), key: key, context: context).base64EncodedString()
    }
    func stored(_ db: Database) throws -> Stored? {
        try Row.fetchOne(
            db, sql: "SELECT payload,revision,dirty FROM records WHERE id=?", arguments: [LibraryRecord.idText]
        ).map { Stored(payload: $0["payload"], revision: $0["revision"], dirty: $0["dirty"]) }
    }
    /// The stored record's values; empty without one. Throws for a record this version can't change.
    func values(_ db: Database) throws -> [String: JSONValue] {
        guard let stored = try stored(db) else { return [:] }
        guard let record = content(stored.payload).record else { throw LibraryError.newerVersion }
        return record.values
    }
    func changes(_ db: Database) throws -> LibraryChanges {
        guard
            let stored = try Data.fetchOne(
                db, sql: "SELECT value FROM settings WHERE key=?", arguments: [LibraryChanges.setting])
        else { return LibraryChanges() }
        guard let text = String(data: stored, encoding: .utf8), let bytes = Data(base64Encoded: text) else {
            return LibraryChanges(damaged: true)
        }
        let decoder = JournalCoding.decoder()
        if let opened = try? protection.decode(bytes, key: key, context: LibraryChanges.context),
            let changes = try? decoder.decode(LibraryChanges.self, from: opened)
        {
            return Self.readable(changes)
        }
        // Left readable by a version that turned on encryption without knowing this value: accepted, and sealed
        // the next time it's stored.
        if protection == .encrypted, let changes = try? decoder.decode(LibraryChanges.self, from: bytes) {
            return Self.readable(changes)
        }
        return LibraryChanges(damaged: true)
    }
    /// Intents written by a newer version (a higher `version`) can't be read safely: what this device changed is
    /// then unknown, as for a value that can't be opened.
    private static func readable(_ changes: LibraryChanges) -> LibraryChanges {
        changes.version == 1 ? changes : LibraryChanges(damaged: true)
    }
    func save(_ db: Database, _ changes: LibraryChanges) throws {
        var changes = changes
        // Only payloads that may still be sent or acknowledged: the stored record and what is queued.
        let live = Set(
            try String.fetchAll(
                db, sql: "SELECT payload FROM records WHERE id=? UNION SELECT payload FROM outbox WHERE record=?",
                arguments: [LibraryRecord.idText, LibraryRecord.idText]
            ).map(JournalStore.payloadDigest))
        changes.payloads = changes.payloads.filter { live.contains($0.key) }
        guard !changes.changes.isEmpty || changes.damaged else {
            try db.execute(sql: "DELETE FROM settings WHERE key=?", arguments: [LibraryChanges.setting])
            return
        }
        let sealed = try protection.encode(
            JournalCoding.encoder().encode(changes), key: key, context: LibraryChanges.context)
        try db.execute(
            sql: "INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            arguments: [LibraryChanges.setting, Data(sealed.base64EncodedString().utf8)])
    }
    /// Whether this library has synchronized with a server.
    static func syncOpen(_ db: Database) throws -> Bool {
        try String.fetchOne(
            db, sql: "SELECT CAST(value AS TEXT) FROM settings WHERE key=?", arguments: [syncedSetting]) == "1"
    }
    /// Queues the library record once the library has synchronized with a server: the one place it's queued. A
    /// queued change stays.
    func queue(_ db: Database, payload: String, revision: Int64) throws -> UUID? {
        guard try Self.syncOpen(db) else { return nil }
        let operation = UUID()
        try db.execute(
            sql: "INSERT OR IGNORE INTO outbox(operation,record,kind,payload,base) VALUES (?,?,?,?,?)",
            arguments: [
                operation.uuidString.lowercased(), LibraryRecord.idText, LibraryRecord.kind, payload, revision,
            ])
        return db.changesCount > 0 ? operation : nil
    }
    /// Stores the record: `payload` at `revision`.
    private func write(_ db: Database, payload: String, revision: Int64, dirty: Bool) throws {
        try db.execute(
            sql: """
                INSERT INTO records(id,kind,payload,revision,dirty) VALUES (?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,revision=excluded.revision,dirty=excluded.dirty
                """,
            arguments: [LibraryRecord.idText, LibraryRecord.kind, payload, revision, dirty])
    }
    private func retireQueued(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [LibraryRecord.idText])
    }

    // MARK: Local changes (rule 1)

    /// Applies this device's own change: `sets` as the person's changes (nil removes a key), `ifAbsent` as automatic
    /// values. Keys of records deleted permanently here are removed too. Record and intents change together.
    func change(_ db: Database, sets: [String: JSONValue?], ifAbsent: [String: JSONValue] = [:]) throws
        -> LibraryEffects
    {
        let stored = try stored(db)
        var record = LibraryRecord()
        if let stored {
            guard let readable = content(stored.payload).record else { throw LibraryError.newerVersion }
            record = readable
        }
        var changes = try changes(db)
        let generation = changes.nextGeneration()
        var requested = sets
        for key in record.values.keys where requested[key] == nil {
            if try isPermanentlyDeleted(db, key: key) { requested[key] = .some(nil) }
        }
        let before = record.values
        for (key, value) in requested where record.values[key] != value {
            record.values[key] = value
            changes.changes[key] = .set(value)
            changes.changes[key]?.generation = generation
        }
        for (key, value) in ifAbsent where record.values[key] == nil {
            record.values[key] = value
            if changes.changes[key] == nil {
                changes.changes[key] = .ifAbsent(value)
                changes.changes[key]?.generation = generation
            }
        }
        guard record.values != before else {
            try save(db, changes)
            return LibraryEffects()
        }
        let payload = try seal(record)
        try write(db, payload: payload, revision: stored?.revision ?? 0, dirty: true)
        changes.wrote(payload)
        var effects = LibraryEffects()
        if let queued = try queue(db, payload: payload, revision: stored?.revision ?? 0) { effects.queued = [queued] }
        try save(db, changes)
        return effects
    }
    /// Whether a key names a record that exists here as a permanent-deletion marker. Keys of records this device
    /// doesn't have are never removed: the record may not have arrived yet.
    private func isPermanentlyDeleted(_ db: Database, key: String) throws -> Bool {
        guard
            let identity = LibraryKey.identity(key, in: LibraryKey.pinned)
                ?? LibraryKey.identity(key, in: LibraryKey.rank)
        else { return false }
        return try permanentlyDeleted(db, [identity]).contains(identity)
    }
    /// The records among `identities` that are permanent-deletion markers here.
    func permanentlyDeleted(_ db: Database, _ identities: [UUID]) throws -> Set<UUID> {
        var deleted = Set<UUID>()
        for identity in identities {
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT kind,payload FROM records WHERE id=?",
                    arguments: [identity.uuidString.lowercased()])
            else { continue }
            let item = try JournalStore.decode(
                row["payload"], id: identity, kind: row["kind"], version: JournalStore.version(of: row["payload"]),
                key: key, protection: protection)
            if item.isPermanentlyDeleted { deleted.insert(identity) }
        }
        return deleted
    }

    // MARK: Synchronization (rules 2–4)

    /// The server holds `payload`: forget the intents it already has (rule 3).
    /// A damaged value still learns this, and keeps its unknown lineage for the next merge.
    func acknowledged(_ db: Database, payload: String) throws {
        guard let values = content(payload).record?.values else { return }
        var changes = try changes(db)
        changes.clear(by: values, payload: payload)
        try save(db, changes)
    }
    /// A payload is being sent: the intents it carries may now reach the server.
    func sending(_ db: Database, payload: String) throws {
        guard let values = content(payload).record?.values else { return }
        var changes = try changes(db)
        changes.markSent(in: values, payload: payload)
        try save(db, changes)
    }
    /// Takes the server's version as it is, such as one from a newer version, which is never written over.
    func adopt(_ db: Database, server change: RemoteChange) throws -> LibraryEffects {
        try write(db, payload: change.payload, revision: change.revision, dirty: false)
        try retireQueued(db)
        try JournalStore.rememberServerVersion(
            db, recordID: LibraryRecord.idText, revision: change.revision, payload: change.payload)
        if let values = content(change.payload).record?.values {
            var changes = try changes(db)
            changes.clear(by: values)
            try save(db, changes)
        }
        return LibraryEffects(received: true)
    }
    /// Rule 2: the server's version with this device's intents on top, replacing what would be a review for other
    /// records. Equal to the server's version, it's adopted and nothing is sent.
    func merge(_ db: Database, server change: RemoteChange) throws -> LibraryEffects {
        guard let server = content(change.payload).record else { return try adopt(db, server: change) }
        try JournalStore.rememberServerVersion(
            db, recordID: LibraryRecord.idText, revision: change.revision, payload: change.payload)
        var changes = try changes(db)
        if changes.damaged {
            let local = try stored(db).flatMap { content($0.payload).record?.values } ?? [:]
            changes.reconcile(local: local, server: server.values, provenLineage: false)
        }
        changes.clear(by: server.values)
        let merged = changes.merged(onto: server.values)
        try save(db, changes)
        guard merged != server.values else {
            try write(db, payload: change.payload, revision: change.revision, dirty: false)
            try retireQueued(db)
            return LibraryEffects(received: true)
        }
        var effects = LibraryEffects(received: true)
        var record = server
        record.values = merged
        if let queued = try Row.fetchOne(
            db, sql: "SELECT payload,base FROM outbox WHERE record=?", arguments: [LibraryRecord.idText]),
            queued["base"] as Int64 == change.revision,
            content(queued["payload"]).record.map({ Self.sameContent($0, record) }) == true
        {
            try write(db, payload: queued["payload"], revision: change.revision, dirty: true)
            return effects
        }
        let payload = try seal(record)
        try retireQueued(db)
        try write(db, payload: payload, revision: change.revision, dirty: true)
        changes.wrote(payload)
        try save(db, changes)
        if let queued = try queue(db, payload: payload, revision: change.revision) { effects.queued = [queued] }
        return effects
    }
    /// Rule 4: after a restore, a rollback, a fork or a fresh server, this device can't tell whether the server's
    /// version (nil when the server lacks the record) is newer or older than what it knows. `seen` is a server payload
    /// with this device's content, which proves the server's version descends from it.
    func reconcile(_ db: Database, server change: RemoteChange?, seen: String?) throws -> LibraryEffects {
        try db.execute(sql: "DELETE FROM conflicts WHERE record=?", arguments: [LibraryRecord.idText])
        let serverValues: [String: JSONValue]
        if let change {
            guard let server = content(change.payload).record else { return try adopt(db, server: change) }
            serverValues = server.values
        } else {
            serverValues = [:]
        }
        let stored = try stored(db)
        if let stored, content(stored.payload).record == nil {
            return try reupload(db, held: stored.payload, server: change)
        }
        let local = stored.flatMap { content($0.payload).record }
        var changes = try changes(db)
        let seenValues = seen.flatMap { content($0).record?.values }
        if let seenValues, !changes.damaged { changes.clear(by: seenValues) }
        changes.reconcile(local: local?.values ?? [:], server: serverValues, provenLineage: seenValues != nil)
        try save(db, changes)
        if let change { return try merge(db, server: change) }
        // The server lacks the record: it's sent again from revision 0.
        var record = local ?? LibraryRecord()
        record.values = changes.merged(onto: [:])
        let payload = try seal(record)
        try retireQueued(db)
        try write(db, payload: payload, revision: 0, dirty: true)
        changes.wrote(payload)
        try save(db, changes)
        var effects = LibraryEffects()
        if let queued = try queue(db, payload: payload, revision: 0) { effects.queued = [queued] }
        return effects
    }

    /// A record from a newer version that the server lost or replaced with an older one goes back as it is: this
    /// version never writes over it (pinned-entries.md, "Reading rules").
    private func reupload(_ db: Database, held payload: String, server change: RemoteChange?) throws -> LibraryEffects {
        let revision = change?.revision ?? 0
        if let change {
            try JournalStore.rememberServerVersion(
                db, recordID: LibraryRecord.idText, revision: change.revision, payload: change.payload)
        }
        try retireQueued(db)
        try write(db, payload: payload, revision: revision, dirty: true)
        var effects = LibraryEffects(received: change != nil)
        if let queued = try queue(db, payload: payload, revision: revision) { effects.queued = [queued] }
        return effects
    }

    /// Whether two records hold the same values and members, apart from when they were written.
    private static func sameContent(_ first: LibraryRecord, _ second: LibraryRecord) -> Bool {
        var firstMembers = first.members
        var secondMembers = second.members
        firstMembers["modifiedAt"] = nil
        secondMembers["modifiedAt"] = nil
        return first.values == second.values && firstMembers == secondMembers
    }

    // MARK: What older versions left (rule 5)

    /// Whether this store's key opens its records. Without encryption there's nothing to check; with no records,
    /// there's nothing to convert either.
    private func keyOpensRecords(_ db: Database) throws -> Bool {
        guard protection == .encrypted else { return true }
        let rows = try Row.fetchAll(db, sql: "SELECT id,kind,payload FROM records ORDER BY id LIMIT 3")
        return rows.contains { row in
            guard let id = UUID(uuidString: row["id"]), let data = Data(base64Encoded: row["payload"] as String) else {
                return false
            }
            return
                (try? protection.decode(data, key: key, context: VaultCrypto.recordContext(id: id, kind: row["kind"])))
                != nil
        }
    }

    /// Whether an older version kept a review or Version History for the library record.
    func hasLeftovers(_ db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql:
                "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?) OR EXISTS(SELECT 1 FROM history WHERE kind=?)",
            arguments: [LibraryRecord.idText, LibraryRecord.kind]) == true
    }
    /// Converts a review and Version History an older version kept for the library record, before anything else runs.
    /// A failure is logged and leaves them; it never stops the library from opening.
    func convertLeftovers(_ db: Database) {
        do {
            // A library opened with a key that may be wrong (checking a password) converts nothing: the review it
            // can't open would replace this device's version.
            guard try keyOpensRecords(db) else { return }
            try db.execute(sql: "DELETE FROM history WHERE kind=?", arguments: [LibraryRecord.kind])
            guard
                let review = try Row.fetchOne(
                    db, sql: "SELECT payload,revision,device,modified FROM conflicts WHERE record=?",
                    arguments: [LibraryRecord.idText])
            else { return }
            let payload: String = review["payload"]
            let revision: Int64 = review["revision"]
            if revision > 0 {
                let change = RemoteChange(
                    cursor: 0, recordId: LibraryRecord.id, revision: revision, kind: LibraryRecord.kind,
                    payload: payload, deviceId: UUID(), modifiedAt: Date())
                _ = try reconcile(db, server: change, seen: nil)
                return
            }
            // At revision 0 the other version isn't on the server: both versions' keys only fill in what's absent.
            try db.execute(sql: "DELETE FROM conflicts WHERE record=?", arguments: [LibraryRecord.idText])
            guard let other = content(payload).record else {
                // From a newer version: kept as it is and sent, never written over.
                _ = try reupload(db, held: payload, server: nil)
                return
            }
            let local = try stored(db).flatMap { content($0.payload).record }
            var changes = try changes(db)
            for (key, value) in (local?.values ?? [:]).merging(other.values, uniquingKeysWith: { mine, _ in mine })
            where changes.changes[key] == nil {
                changes.changes[key] = .ifAbsent(value)
            }
            changes.damaged = false
            try save(db, changes)
            var record = local ?? other
            record.values = changes.merged(onto: [:])
            let sealed = try seal(record)
            try retireQueued(db)
            try write(db, payload: sealed, revision: 0, dirty: true)
            changes.wrote(sealed)
            try save(db, changes)
            _ = try queue(db, payload: sealed, revision: 0)
        } catch {
            Self.logger.error("Couldn't convert what an older version kept for the library record.")
        }
    }
}

extension JournalStore {
    var library: LibraryStore { LibraryStore(key: key, protection: protection) }

    func record(_ effects: LibraryEffects) {
        for operation in effects.queued { unsentOperations[operation] = Date() }
        if effects.received { receivedChanges += 1 }
    }

    // MARK: Pins and order

    /// Pins and ranks as the lists show them.
    public func libraryArrangement() throws -> LibraryArrangement {
        try db.read { try libraryArrangement($0) }
    }
    func libraryArrangement(_ db: Database) throws -> LibraryArrangement {
        guard let stored = try library.stored(db) else { return .empty }
        guard let record = library.content(stored.payload).record else {
            return LibraryArrangement(pinned: [], ranks: [:], available: false)
        }
        // Entries are usually decoded already, so this reads no payload again.
        var deleted = Set<UUID>()
        for entry in record.values.keys.compactMap({ LibraryKey.identity($0, in: LibraryKey.pinned) })
        where try storedItem(db, uuid: entry)?.isPermanentlyDeleted == true {
            deleted.insert(entry)
        }
        return LibraryArrangement(values: record.values, deleted: deleted)
    }
    public func librarySyncState() throws -> LibrarySyncState {
        try db.read { db in
            guard let stored = try library.stored(db) else { return LibrarySyncState() }
            return LibrarySyncState(needsUpdate: library.content(stored.payload).record == nil)
        }
    }
    /// Pins or unpins an entry. Only an entry listed in a journal in use can be pinned; any can be unpinned.
    @discardableResult public func setPinned(_ pinned: Bool, entry entryID: UUID) throws -> LibraryArrangement {
        try Task.checkCancellation()
        return try db.write { db in
            if pinned { try requireListed(db, entryID) }
            record(try library.change(db, sets: [LibraryKey.pin(entryID): pinned ? .bool(true) : nil]))
            return try libraryArrangement(db)
        }
    }
    private func requireListed(_ db: Database, _ entryID: UUID) throws {
        guard let entry = try storedItem(db, uuid: entryID), entry.kind == "entry",
            let journalID = entry.journalID, let journal = try storedItem(db, uuid: journalID)
        else { throw LibraryError.unavailable }
        let conflicted = try String.fetchAll(
            db, sql: "SELECT record FROM conflicts WHERE record IN (?,?)", arguments: [id(journalID), id(entryID)])
        let snapshot = JournalLifecycleSnapshot(
            items: [entry, journal], conflictedIDs: Set(conflicted.compactMap(UUID.init(uuidString:))),
            settlingIDs: try settlingConflictIDs(db))
        guard snapshot.location(of: entry) == .journal else { throw LibraryError.unavailable }
    }
    /// Journals in use, in the order shown.
    public func arrangedJournals() throws -> [JournalItem] {
        try db.read { try arrangedJournals($0) }
    }
    func arrangedJournals(_ db: Database) throws -> [JournalItem] {
        JournalRanks.arranged(try lifecycleSnapshot(db).liveJournals, ranks: try libraryArrangement(db).ranks)
    }
    /// Moves a journal to `index` of `shown` without it, `shown` being the journals in use in the order shown at the
    /// drop. Its rank is computed from the neighbours shown then, so an order arriving meanwhile can't put it
    /// elsewhere. Journals shown without a rank first get automatic ones.
    @discardableResult public func moveJournal(_ journalID: UUID, shown: [UUID], to index: Int) throws
        -> LibraryArrangement
    {
        try Task.checkCancellation()
        return try db.write { db in
            let live = Set(try lifecycleSnapshot(db).liveJournals.map(\.id))
            let before = shown.filter(live.contains)
            guard before.contains(journalID) else { throw LibraryError.unavailable }
            let values = try library.values(db)
            var ranks = LibraryArrangement(values: values).ranks
            let automatic = Self.automaticRanks(for: before, skipping: journalID, ranks: ranks, values: values)
            ranks.merge(automatic) { current, _ in current }
            var after = before.filter { $0 != journalID }
            let target = min(max(index, 0), after.count)
            let lower = after[..<target].last { ranks[$0] != nil }.flatMap { ranks[$0] }
            let upper = after[target...].first { ranks[$0] != nil }.flatMap { ranks[$0] }
            var sets: [String: JSONValue?] = [:]
            var ifAbsent = automatic.reduce(into: [String: JSONValue]()) {
                $0[LibraryKey.rank($1.key)] = .string($1.value)
            }
            if let rank = JournalRanks.between(lower, upper) {
                sets[LibraryKey.rank(journalID)] = .string(rank)
            } else {
                // No room left between them: every journal is spaced evenly again.
                after.insert(journalID, at: target)
                for (position, journal) in after.enumerated() {
                    sets[LibraryKey.rank(journal)] = .string(JournalRanks.spaced(position, count: after.count))
                }
                ifAbsent = [:]
            }
            record(try library.change(db, sets: sets, ifAbsent: ifAbsent))
            return try libraryArrangement(db)
        }
    }
    /// Puts a new or restored journal without a rank at the end, once journals have been arranged; without an
    /// arrangement, journals stay in name order.
    public func placeJournalAtEnd(_ journalID: UUID) throws {
        try db.write { db in
            guard let values = try? library.values(db) else { return }
            let ranks = LibraryArrangement(values: values).ranks
            guard ranks[journalID] == nil else { return }
            let shown = try arrangedJournals(db).map(\.id).filter { $0 != journalID }
            guard shown.contains(where: { ranks[$0] != nil }) else { return }
            let automatic = Self.automaticRanks(for: shown, skipping: nil, ranks: ranks, values: values)
            let last = (shown.compactMap { ranks[$0] ?? automatic[$0] }).max(by: JournalRanks.precedes)
            guard let rank = JournalRanks.between(last, nil) else { return }
            let ifAbsent = automatic.reduce(into: [String: JSONValue]()) {
                $0[LibraryKey.rank($1.key)] = .string($1.value)
            }
            record(try library.change(db, sets: [LibraryKey.rank(journalID): .string(rank)], ifAbsent: ifAbsent))
        }
    }
    /// Ranks for the journals shown without one, in the order shown: spaced evenly when none is ranked, otherwise after
    /// the last valid rank. A journal whose key holds a value this version can't use keeps it, unranked.
    static func automaticRanks(
        for shown: [UUID], skipping moved: UUID?, ranks: [UUID: String], values: [String: JSONValue]
    )
        -> [UUID: String]
    {
        var automatic: [UUID: String] = [:]
        if !shown.contains(where: { ranks[$0] != nil }) {
            for (position, journal) in shown.enumerated()
            where journal != moved && values[LibraryKey.rank(journal)] == nil {
                automatic[journal] = JournalRanks.spaced(position, count: shown.count)
            }
            return automatic
        }
        var last = shown.compactMap { ranks[$0] }.max(by: JournalRanks.precedes)
        for journal in shown where journal != moved && ranks[journal] == nil && values[LibraryKey.rank(journal)] == nil
        {
            guard let rank = JournalRanks.between(last, nil) else { break }
            automatic[journal] = rank
            last = rank
        }
        return automatic
    }

    // MARK: Synchronization

    /// Records that this library synchronizes with a server, at the start of each synchronization. A library record
    /// changed before the first one is queued then, at the revision it has; until then nothing of it is sent or
    /// counted.
    func updateLibrarySync() throws {
        try db.write { db in
            let current = try String.fetchOne(
                db, sql: "SELECT CAST(value AS TEXT) FROM settings WHERE key=?",
                arguments: [LibraryStore.syncedSetting])
            if current != "1" {
                try db.execute(
                    sql:
                        "INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    arguments: [LibraryStore.syncedSetting, Data("1".utf8)])
            }
            guard let stored = try library.stored(db), stored.dirty,
                library.content(stored.payload).record != nil,
                try Bool.fetchOne(
                    db,
                    sql:
                        "SELECT EXISTS(SELECT 1 FROM outbox WHERE record=?) OR EXISTS(SELECT 1 FROM conflicts WHERE record=?)",
                    arguments: [LibraryRecord.idText, LibraryRecord.idText]) == false
            else { return }
            if let queued = try library.queue(db, payload: stored.payload, revision: stored.revision) {
                unsentOperations[queued] = Date()
            }
        }
    }
    /// SQL for queued changes that may be sent: none of the library record before the library has synchronized.
    static let sendable =
        "(o.kind <> 'library' OR EXISTS(SELECT 1 FROM settings WHERE key='\(LibraryStore.syncedSetting)' AND CAST(value AS TEXT)='1'))"

    /// A change of the library record from the server (`apply`).
    func applyLibrary(_ db: Database, change: RemoteChange) throws {
        if let stored = try library.stored(db) {
            if change.revision < stored.revision { return }
            if change.revision == stored.revision {
                guard try isOtherLibraryVersion(db, change: change, local: stored.payload) else { return }
                // The server lost a version it accepted and gave its revision to another.
                return record(try library.reconcile(db, server: change, seen: nil))
            }
            if let queued = try Row.fetchOne(
                db, sql: "SELECT operation,payload,base FROM outbox WHERE record=?", arguments: [LibraryRecord.idText]),
                (queued["payload"] as String) == change.payload, (queued["base"] as Int64) + 1 == change.revision,
                let operation = UUID(uuidString: queued["operation"])
            {
                return try acknowledge(
                    db,
                    pending: PendingChange(
                        operationId: operation, recordID: change.recordId, baseRevision: queued["base"],
                        kind: change.kind, payload: change.payload),
                    revision: change.revision)
            }
            let changes = try library.changes(db)
            if stored.dirty || !changes.changes.isEmpty || changes.damaged {
                return record(try library.merge(db, server: change))
            }
        }
        record(try library.adopt(db, server: change))
    }
    private func isOtherLibraryVersion(_ db: Database, change: RemoteChange, local: String) throws -> Bool {
        guard change.payload != local else { return false }
        let known = try String.fetchOne(
            db, sql: "SELECT digest FROM server_versions WHERE record=? AND revision=?",
            arguments: [LibraryRecord.idText, change.revision])
        if known == Self.payloadDigest(change.payload) { return false }
        return !sameContent(change.payload, local, id: LibraryRecord.id, kind: LibraryRecord.kind)
    }

    // MARK: Importing

    /// Adds `arrangement`, read from a library being imported with `arrangementForImport()`.
    func importArrangement(
        _ arrangement: (pinned: Set<UUID>, journals: [UUID], ranked: Bool), identities: [UUID: UUID]
    ) throws {
        try db.write { db in
            try importArrangement(
                db, pinned: arrangement.pinned, journals: arrangement.journals, ranked: arrangement.ranked,
                identities: identities)
        }
    }

    /// Adds the pins and journal order of a library being imported: pins of imported entries, and imported journals
    /// after the journals here. Journals here are first given automatic ranks in the order shown when they have none,
    /// so imported ones don't move above them. `identities` maps the source's records to their identities here.
    func importArrangement(
        _ db: Database, pinned: Set<UUID>, journals: [UUID], ranked: Bool, identities: [UUID: UUID]
    ) throws {
        // A library record from a newer version can't take them; the journals and entries still import.
        if let stored = try library.stored(db), library.content(stored.payload).record == nil { return }
        var sets: [String: JSONValue?] = [:]
        for entry in pinned {
            guard let imported = identities[entry] else { continue }
            sets[LibraryKey.pin(imported)] = .bool(true)
        }
        let imported = journals.compactMap { identities[$0] }
        let values = (try? library.values(db)) ?? [:]
        let ranks = LibraryArrangement(values: values).ranks
        let existing = try arrangedJournals(db).map(\.id).filter { !imported.contains($0) }
        var ifAbsent: [String: JSONValue] = [:]
        if !imported.isEmpty, ranked || existing.contains(where: { ranks[$0] != nil }) {
            let automatic = Self.automaticRanks(for: existing, skipping: nil, ranks: ranks, values: values)
            for (journal, rank) in automatic { ifAbsent[LibraryKey.rank(journal)] = .string(rank) }
            var last = existing.compactMap { ranks[$0] ?? automatic[$0] }.max(by: JournalRanks.precedes)
            for journal in imported {
                guard let rank = JournalRanks.between(last, nil) else { break }
                sets[LibraryKey.rank(journal)] = .string(rank)
                last = rank
            }
        }
        guard !sets.isEmpty || !ifAbsent.isEmpty else { return }
        record(try library.change(db, sets: sets, ifAbsent: ifAbsent))
    }
    /// What `importArrangement` needs from a source library: its pinned entries, its journals in use in their order,
    /// and whether they were arranged. Nothing when its library record is from a newer version.
    func arrangementForImport() throws -> (pinned: Set<UUID>, journals: [UUID], ranked: Bool) {
        try db.read { db in
            let arrangement = try libraryArrangement(db)
            guard arrangement.available else { return ([], [], false) }
            let journals = try arrangedJournals(db).map(\.id)
            return (arrangement.pinned, journals, journals.contains { arrangement.ranks[$0] != nil })
        }
    }

    // MARK: Inspection, for tests and other clients' fixtures

    /// The library record's current values here.
    func libraryValues() throws -> [String: JSONValue] { try db.read { try library.values($0) } }
    /// The values a library payload holds; nil for one this version can't read.
    func libraryValues(inPayload payload: String) -> [String: JSONValue]? { library.content(payload).record?.values }
    func libraryChanges() throws -> [String: LibraryIntent] { try db.read { try library.changes($0).changes } }
    /// Sets library values as the person's own changes.
    func setLibraryValues(_ values: [String: JSONValue?]) throws {
        try db.write { db in record(try library.change(db, sets: values)) }
    }
    func sealedPayload(_ plaintext: Data, id: UUID, kind: String) throws -> String {
        try protection.encode(plaintext, key: key, context: VaultCrypto.recordContext(id: id, kind: kind))
            .base64EncodedString()
    }
    func openedPayload(_ payload: String, id: UUID, kind: String) throws -> Data {
        guard let data = Data(base64Encoded: payload) else { throw JournalError.invalidData }
        return try protection.decode(data, key: key, context: VaultCrypto.recordContext(id: id, kind: kind))
    }
}
