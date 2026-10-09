import CryptoKit
import Foundation
import GRDB

public struct PendingChange: Codable, Sendable {
    public var operationId: UUID
    public var recordID: UUID
    public var baseRevision: Int64
    public var kind: String
    public var payload: String
}
public struct RemoteChange: Codable, Sendable {
    public var cursor: Int64
    public var recordId: UUID
    public var revision: Int64
    public var kind: String
    public var payload: String
    public var deviceId: UUID
    public var modifiedAt: Date
    public init(
        cursor: Int64, recordId: UUID, revision: Int64, kind: String, payload: String, deviceId: UUID, modifiedAt: Date
    ) {
        self.cursor = cursor
        self.recordId = recordId
        self.revision = revision
        self.kind = kind

        self.payload = payload
        self.deviceId = deviceId
        self.modifiedAt = modifiedAt
    }
}
public struct ConflictVersion: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let local: JournalItem
    public let remote: JournalItem
    public let remoteRevision: Int64
    public let deviceID: UUID
    public let modifiedAt: Date
}
/// How `resolve` settles a conflict by choice. The app never asks a person to choose: it settles every conflict itself
/// (`resolveConflicts(at:)`). This remains for the measurement and screenshot tools and for tests, which use it to
/// build a record with earlier versions in its history.
public enum ConflictChoice: Sendable { case keepBoth, local, remote }

public actor JournalStore {
    let db: DatabaseQueue
    /// The vault key; only this store and its extensions use it.
    let key: Data
    public let protection: ContentProtection
    let deletionScopeID = UUID()
    public let directory: URL
    /// Counts writes that came from elsewhere: synchronized records and images, and versions kept for review.
    var receivedChanges = 0
    var synchronizing = false
    var synchronizationWaiters: [SynchronizationWaiter] = []
    /// What the quiet mark is made of (SyncWaiting.swift).
    var quiet = QuietState()
    /// Records as last decoded from their stored payloads, reused while a payload is unchanged, so reading the journals
    /// again doesn't decrypt and parse every entry. Only in memory, and only while the journals are open: locking
    /// clears it (`forgetDecodedRecords()`). The same content is in the app's memory while unlocked anyway.
    var decodedRecords: [UUID: JournalItem] = [:]
    var remembersDecodedRecords = true
    /// The one-time pass over conflicts an earlier version left has run for this library (StoreConflictResolution.swift).
    var openingPassComplete = false
    /// Conflicted records whose last attempt to settle failed. They count as held until an attempt works, so a row that
    /// keeps failing doesn't keep a synchronization from being settled (`hasConflictAwaitingResolution`).
    var failedConflicts: Set<UUID> = []
    /// The payload each record was last saved with here, from an item that could be edited. Saving over it again
    /// needs no decoding to know that.
    var editablePayloads: [UUID: StoredVersion] = [:]
    /// Queued changes no synchronization has taken yet, with when each was queued, and when each record was last
    /// saved here. Writing is sent once it pauses, as one revision (`takeForSending`).
    var unsentOperations: [UUID: Date] = [:]
    var lastSaves: [UUID: Date] = [:]
    /// Keeping earlier versions of ordinary changes (StoreCheckpoints.swift): the time used, when each record's stored
    /// version was saved here, and when each record's current checkpoint period began. Both are only in memory.
    var clock: @Sendable () -> Date = { Date() }
    var versionsStoredAt: [UUID: Date] = [:]
    var checkpointPeriods: [UUID: Date] = [:]
    /// The largest image file, encrypted; the server accepts no larger upload.
    static let maximumAttachmentBytes = 25 * 1024 * 1024
    public init(directory: URL, key: Data, protection: ContentProtection = .encrypted) throws {
        guard key.count == 32 else { throw JournalError.invalidData }
        self.directory = directory
        self.key = key
        self.protection = protection
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        var configuration = Configuration()

        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Every committed save stays durable, also with the write-ahead log.
            try db.execute(sql: "PRAGMA synchronous = FULL")
        }
        db = try DatabaseQueue(
            path: directory.appendingPathComponent("journal.sqlite").path, configuration: configuration)
        let migrator = Self.migrator
        // A newer version may have changed what these tables mean, so this one must not write to them.
        guard try !db.read({ try migrator.hasBeenSuperseded($0) }) else { throw JournalError.newerVersion }
        try db.writeWithoutTransaction { _ = try String.fetchOne($0, sql: "PRAGMA journal_mode = WAL") }
        try migrator.migrate(db)
        db.add(transactionObserver: SyncedTableWrites(counter: quiet.writes), extent: .databaseLifetime)
        try db.write { database in
            let stored = try String.fetchOne(
                database, sql: "SELECT value FROM settings WHERE key = 'content-protection'")
            if let stored {
                guard stored == protection.rawValue else { throw JournalError.invalidData }
            } else {
                let count = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM records") ?? 0
                guard count == 0 || protection == .encrypted else { throw JournalError.invalidData }
                try database.execute(
                    sql: "INSERT INTO settings(key,value) VALUES ('content-protection',?)",
                    arguments: [protection.rawValue])
            }
        }
        // What an older version kept for the library record, before anything synchronizes (pinned-entries.md, rule 5).
        // Opening never writes otherwise, so a library damaged where records are kept still opens and reports that
        // its data can't be read: only leftovers that can be read are converted, and a failed conversion leaves them.
        let library = LibraryStore(key: key, protection: protection)
        if (try? db.read { try library.hasLeftovers($0) }) == true {
            do { try db.write { library.convertLeftovers($0) } } catch {
                LibraryStore.logger.error("Couldn’t convert what an older version kept for the library record.")
            }
        }
    }
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(
                sql: """
                    CREATE TABLE records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1);
                    CREATE TABLE outbox (operation TEXT PRIMARY KEY, record TEXT NOT NULL UNIQUE REFERENCES records(id), kind TEXT NOT NULL, payload TEXT NOT NULL, base INTEGER NOT NULL);
                    CREATE TABLE conflicts (record TEXT PRIMARY KEY REFERENCES records(id), payload TEXT NOT NULL, revision INTEGER NOT NULL, device TEXT NOT NULL, modified TEXT NOT NULL);
                    CREATE TABLE history (id INTEGER PRIMARY KEY AUTOINCREMENT, record TEXT NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, saved TEXT NOT NULL);
                    CREATE TABLE settings (key TEXT PRIMARY KEY, value BLOB NOT NULL);
                    CREATE TABLE attachments (id TEXT PRIMARY KEY, uploaded INTEGER NOT NULL DEFAULT 0);
                    """)
        }
        migrator.registerMigration("sync-reconciliation") { db in
            // Latest server version of each record while re-reading a restored or replaced server.
            try db.execute(
                sql: """
                    CREATE TABLE reconcile_heads (record TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL, revision INTEGER NOT NULL, cursor INTEGER NOT NULL, device TEXT NOT NULL, modified TEXT NOT NULL, seen_payload TEXT);
                    """)
        }
        migrator.registerMigration("history-record-index") { db in
            // Version history, incoming deletions and recovery look up one record's versions.
            try db.execute(sql: "CREATE INDEX history_record ON history(record)")
        }
        migrator.registerMigration("history-checkpoints") { db in
            // Marks versions kept from ordinary changes: only these are removed to keep a limited number.
            try db.execute(sql: "ALTER TABLE history ADD COLUMN checkpoint INTEGER NOT NULL DEFAULT 0")
        }
        migrator.registerMigration("server-versions") { db in
            // The version the server holds at each record's revision, as this device last sent or received it: a
            // different one at that revision means the server lost a version it accepted.
            try db.execute(sql: serverVersionsSchema)
        }
        return migrator
    }
    func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }
    func encode(_ item: JournalItem) throws -> String {
        try protection.encode(
            PortableRecord.encode(item), key: key,
            context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
        ).base64EncodedString()
    }
    func enqueue(_ db: Database, recordID: String, kind: String, payload: String, revision: Int64) throws {
        // The library record is queued only while the server takes it; it stays changed until then.
        if kind == LibraryRecord.kind {
            if let queued = try library.queue(db, payload: payload, revision: revision) {
                unsentOperations[queued] = Date()
            }
            return
        }
        let operation = UUID()
        try db.execute(
            sql: "INSERT OR IGNORE INTO outbox(operation,record,kind,payload,base) VALUES (?,?,?,?,?)",
            arguments: [id(operation), recordID, kind, payload, revision])
        if db.changesCount > 0 { unsentOperations[operation] = Date() }
    }
    /// Saves `item` and returns it with the version now stored. When the record changed after `item` was read
    /// (see `JournalItem.storedVersion`), that change is kept for review as a conflict instead of being overwritten,
    /// or, with `requiringUnchanged`, nothing is saved and `JournalError.conflict` is thrown.
    /// A journal can't take a name another journal in the Journals list has (`JournalNameError.taken`).
    @discardableResult public func save(_ item: JournalItem, requiringUnchanged: Bool = false) throws -> JournalItem {
        var saved = item
        saved.storedVersion = try db.write { db in
            if item.kind == "journal" { try requireAvailableName(db, for: item) }
            return try save(db, item: item, requiringUnchanged: requiringUnchanged)
        }
        return saved
    }
    @discardableResult func save(
        _ db: Database, item: JournalItem, importingMarker: Bool = false, requiringUnchanged: Bool = false
    ) throws -> StoredVersion {
        // The library record changes only by its own rules (StoreLibrary.swift).
        guard item.kind != LibraryRecord.kind else { throw JournalError.invalidData }
        if item.isPermanentlyDeleted && !importingMarker { throw PermanentDeletionError.permanentlyDeleted }
        let recordID = id(item.id)
        // The stored version this save replaces, unless it's kept for review instead.
        var replacing: String?
        if let row = try Row.fetchOne(
            db, sql: "SELECT kind,payload,revision FROM records WHERE id=?", arguments: [recordID])
        {
            guard !importingMarker else { throw PermanentDeletionError.permanentlyDeleted }
            guard row["kind"] as String == item.kind else { throw JournalError.invalidData }
            let stored: String = row["payload"]
            let version = Self.version(of: stored)
            if item.storedVersion == version, editablePayloads[item.id] == version {
                // Saved here from an editable item, and unchanged since: it's neither deleted nor read-only.
                replacing = stored
            } else if let expected = item.storedVersion, expected != version {
                let current = try decode(stored, id: item.id, kind: item.kind)
                // Already stored exactly as saved: there is nothing to write or review.
                if current == item, let version = current.storedVersion { return version }
                if requiringUnchanged { throw JournalError.conflict }
                guard item.document.isEditable else { throw JournalError.unsupportedFormat }
                try keepChangedVersion(db, current: current, payload: stored, revision: row["revision"])
            } else {
                let current = try decode(stored, id: item.id, kind: item.kind)
                if current.isPermanentlyDeleted { throw PermanentDeletionError.permanentlyDeleted }
                // A record this version can only read, such as one from a newer client, stays as it is.
                guard current.preservedJSON == nil, current.document.isEditable else {
                    throw JournalError.unsupportedFormat
                }
                replacing = stored
            }
        }
        guard item.document.isEditable else { throw JournalError.unsupportedFormat }
        try keepCheckpointIfDue(db, replacing: replacing, with: item, fromElsewhere: false)
        let payload = try encode(item)
        try db.execute(
            sql:
                "INSERT INTO records(id,kind,payload) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,dirty=1",
            arguments: [recordID, item.kind, payload])
        guard
            let revision = try Int64.fetchOne(
                db, sql: "SELECT revision FROM records WHERE id=?", arguments: [recordID])
        else { throw JournalError.invalidData }
        if try Bool.fetchOne(
            db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID]) == false
        {
            try enqueue(db, recordID: recordID, kind: item.kind, payload: payload, revision: revision)
        }
        let version = Self.version(of: payload)
        editablePayloads[item.id] = item.isPermanentlyDeleted || item.preservedJSON != nil ? nil : version
        lastSaves[item.id] = clock()
        return version
    }
    public func moveEntry(_ entryID: UUID, to journalID: UUID) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard let target = try storedItem(db, uuid: journalID), target.kind == "journal", target.deletedAt == nil
            else {
                throw JournalError.server("That journal is no longer available. Choose another journal.")
            }
            guard target.document.isEditable else { throw JournalError.unsupportedFormat }
            try requireNoConflict(db, uuid: journalID)
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT kind,payload FROM records WHERE id=?", arguments: [id(entryID)]),
                row["kind"] as String == "entry"
            else { throw JournalError.invalidData }
            var entry = try decode(row["payload"], id: entryID, kind: "entry")
            guard entry.deletedAt == nil, !entry.deletedWithJournal, entry.document.isEditable else {
                throw JournalError.unsupportedFormat
            }
            try requireNoConflict(db, uuid: entryID)
            guard let sourceID = entry.journalID, let source = try storedItem(db, uuid: sourceID),
                source.kind == "journal"
            else {
                throw JournalLifecycleError.missingJournal
            }
            guard source.document.isEditable else { throw JournalLifecycleError.unsupportedJournal }
            try requireNoConflict(db, uuid: sourceID)
            guard entry.journalID != journalID else { return entry }
            entry.journalID = journalID
            entry.modifiedAt = Date()
            return try saveCanonical(db, item: entry)
        }
    }
    public func items() throws -> [JournalItem] {
        try db.read { try items($0) }
    }
    /// Journals, entries and templates, and records of kinds this version doesn't know. The library record, which
    /// holds pins and journal order, is read with `libraryArrangement()`.
    private func items(_ db: Database) throws -> [JournalItem] {
        try decodeRecords(
            storedRecords(db, sql: "SELECT id,kind,payload FROM records WHERE kind <> 'library'"), complete: true)
    }
    public func viewSnapshot() throws -> JournalViewSnapshot {
        try db.read { db in
            JournalViewSnapshot(
                items: try items(db).filter { !$0.isPermanentlyDeleted },
                conflictedIDs: Set(try conflictedRecordIDs(db)),
                pending: try Bool.fetchOne(
                    db,
                    sql:
                        "SELECT EXISTS(SELECT 1 FROM outbox o LEFT JOIN conflicts c ON c.record=o.record WHERE c.record IS NULL AND \(Self.sendable))"
                ) == true, library: try libraryArrangement(db))
        }
    }
    public func lifecycleSnapshot() throws -> JournalLifecycleSnapshot {
        try db.read { try lifecycleSnapshot($0) }
    }
    func lifecycleSnapshot(_ db: Database) throws -> JournalLifecycleSnapshot {
        let conflicts = try String.fetchAll(db, sql: "SELECT record FROM conflicts")
        return JournalLifecycleSnapshot(
            items: try items(db), conflictedIDs: Set(conflicts.compactMap(UUID.init(uuidString:))),
            settlingIDs: try settlingConflictIDs(db))
    }
    /// Change only the journal date, preserving newer content and rejecting stale consent.
    public func changeEntryDate(_ entryID: UUID, expectedDate: Date, to date: Date) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard var entry = try storedItem(db, uuid: entryID), entry.kind == "entry",
                entry.deletedAt == nil, !entry.deletedWithJournal,
                let parentID = entry.journalID, let parent = try storedItem(db, uuid: parentID),
                parent.kind == "journal", parent.deletedAt == nil
            else { throw EntryDateError.unavailable }
            guard entry.document.isEditable, parent.document.isEditable else {
                throw JournalError.unsupportedFormat
            }
            try requireNoConflict(db, uuid: entryID)
            try requireNoConflict(db, uuid: parentID)
            guard entry.date == expectedDate else { throw EntryDateError.changed }
            entry.date = date
            entry.modifiedAt = Date()
            return try saveCanonical(db, item: entry)
        }
    }
    public func prepareJournalDeletion(_ journalID: UUID) throws -> JournalDeletionPlan {
        try db.read { try lifecycleSnapshot($0).deletionPlan(for: journalID) }
    }
    /// Patch only image descriptions into the latest record, preserving intervening body edits.
    public func updateImageDescriptions(
        _ entryID: UUID, expectedImages: [DocumentBlock], descriptions: [UUID: String]
    ) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard var item = try storedItem(db, uuid: entryID),
                item.kind == "entry" || item.kind == "template", item.deletedAt == nil,
                !item.deletedWithJournal
            else { throw ImageDescriptionError.unavailable }
            guard item.document.isEditable else { throw JournalError.unsupportedFormat }
            try requireNoConflict(db, uuid: entryID)
            if item.kind == "entry" {
                guard let parentID = item.journalID, let parent = try storedItem(db, uuid: parentID),
                    parent.kind == "journal", parent.deletedAt == nil, parent.document.isEditable
                else { throw ImageDescriptionError.unavailable }
                try requireNoConflict(db, uuid: parentID)
            }
            guard !item.document.requiresMarkdownSource else {
                throw JournalError.server("Edit image descriptions in Markdown source for this entry.")
            }
            let current = item.document.imageBlocks
            guard current == expectedImages else { throw ImageDescriptionError.changed }
            let identifiers = Set(current.map(\.id))
            guard !current.isEmpty, identifiers.count == current.count, Set(descriptions.keys) == identifiers else {
                throw JournalError.invalidData
            }
            item.document = item.document.updatingImageDescriptions(descriptions.mapValues(ImageDescription.singleLine))
            item.modifiedAt = Date()
            return try saveCanonical(db, item: item)
        }
    }
    public func deleteJournal(_ plan: JournalDeletionPlan) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            let snapshot = try lifecycleSnapshot(db)
            let current = try snapshot.deletionPlan(for: plan.journalID)
            guard current.title == plan.title, current.entryIDs == plan.entryIDs else {
                throw JournalLifecycleError.changed
            }
            guard var journal = snapshot.items.first(where: { $0.id == plan.journalID }) else {
                throw JournalLifecycleError.missingJournal
            }
            journal.deletedAt = Date()
            journal.modifiedAt = Date()
            return try saveCanonical(db, item: journal)
        }
    }
    public func restoreJournal(_ journalID: UUID, expectedTitle: String? = nil) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard var journal = try storedItem(db, uuid: journalID), journal.kind == "journal" else {
                throw JournalLifecycleError.missingJournal
            }
            guard journal.document.isEditable else { throw JournalLifecycleError.unsupportedJournal }
            try requireNoConflict(db, uuid: journalID)
            if expectedTitle != nil, journal.deletedAt == nil { throw JournalLifecycleError.alreadyRestored }
            if let expectedTitle, journal.title != expectedTitle { throw JournalLifecycleError.changed }
            guard journal.deletedAt != nil else { return journal }
            journal.deletedAt = nil
            journal.title = try availableTitle(db, for: journal)
            journal.modifiedAt = Date()
            return try saveCanonical(db, item: journal)
        }
    }
    /// Brings a template back from Recently Deleted. A template changed or permanently deleted elsewhere in the
    /// meantime is refused rather than overwritten.
    public func restoreTemplate(_ templateID: UUID) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard var template = try storedItem(db, uuid: templateID), template.kind == "template",
                !template.isPermanentlyDeleted
            else { throw JournalError.invalidData }
            guard template.document.isEditable, template.preservedJSON == nil else {
                throw JournalError.unsupportedFormat
            }
            try requireNoConflict(db, uuid: templateID)
            guard template.deletedAt != nil else { return template }
            template.deletedAt = nil
            template.modifiedAt = Date()
            return try saveCanonical(db, item: template)
        }
    }
    func requireNoConflict(_ db: Database, uuid: UUID) throws {
        if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [id(uuid)])
            == true
        {
            throw JournalLifecycleError.conflict(uuid)
        }
    }
    func storedItem(_ db: Database, uuid: UUID) throws -> JournalItem? {
        guard let row = try Row.fetchOne(db, sql: "SELECT kind,payload FROM records WHERE id=?", arguments: [id(uuid)])
        else { return nil }
        return try decodeRecord(row["payload"], id: uuid, kind: row["kind"])
    }
    func saveCanonical(_ db: Database, item: JournalItem, requiringUnchanged: Bool = false) throws -> JournalItem {
        try save(db, item: item, requiringUnchanged: requiringUnchanged)
        guard let saved = try storedItem(db, uuid: item.id) else { throw JournalError.invalidData }
        return saved
    }
    /// Keeps the stored version that a save would replace, because it changed after the saved copy was read.
    /// It becomes the other side of a conflict for review; neither version is dropped.
    private func keepChangedVersion(_ db: Database, current: JournalItem, payload: String, revision: Int64) throws {
        let recordID = id(current.id)
        if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID])
            == true
        {
            // A review is already pending with the other device's version; keep this one in Version History.
            if current.isPermanentlyDeleted { throw PermanentDeletionError.permanentlyDeleted }
            try db.execute(
                sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                arguments: [recordID, current.kind, payload, JournalCoding.timestamp(Date())])
            return
        }
        // Stored versions don't record their device; the nil identifier stands for an unknown device.
        try db.execute(
            sql: "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?)",
            arguments: [
                recordID, payload, revision, "00000000-0000-0000-0000-000000000000",
                JournalCoding.timestamp(current.modifiedAt),
            ])
        receivedChanges += 1
    }
    public func item(_ uuid: UUID) throws -> JournalItem? {
        try db.read { try storedItem($0, uuid: uuid) }
    }
    public func pending() throws -> [PendingChange] {
        try db.read { db in
            try Row.fetchAll(
                db,
                sql:
                    "SELECT o.* FROM outbox o LEFT JOIN conflicts c ON c.record=o.record WHERE c.record IS NULL AND \(Self.sendable) ORDER BY o.rowid"
            ).map { row in
                guard let op = UUID(uuidString: row["operation"]), let record = UUID(uuidString: row["record"]) else {
                    throw JournalError.invalidData
                }
                return PendingChange(
                    operationId: op, recordID: record, baseRevision: row["base"], kind: row["kind"],
                    payload: row["payload"])
            }
        }
    }
    /// `readingOn` moves the position past the change when nothing can come before it, for a server that confirms
    /// the payload of the change a device read last.
    public func acknowledge(_ pending: PendingChange, receipt: RemoteChange, readingOn: Bool = false) throws {
        guard receipt.recordId == pending.recordID, receipt.payload == pending.payload,
            receipt.revision == pending.baseRevision + 1
        else { throw JournalError.invalidData }
        try db.write { db in try acknowledgeSent(db, pending: pending, receipt: receipt, readingOn: readingOn) }
    }
    func acknowledge(_ db: Database, pending: PendingChange, revision: Int64) throws {
        let recordID = id(pending.recordID)
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT payload,kind,revision FROM records WHERE id=?", arguments: [recordID])
        else { throw JournalError.invalidData }
        guard (row["revision"] as Int64) <= revision else { return }
        try db.execute(sql: "DELETE FROM outbox WHERE operation=?", arguments: [id(pending.operationId)])
        let current: String = row["payload"]
        try db.execute(
            sql: "UPDATE records SET revision=?,dirty=? WHERE id=?",
            arguments: [revision, current == pending.payload ? 0 : 1, recordID])
        if current != pending.payload {
            try enqueue(db, recordID: recordID, kind: row["kind"], payload: current, revision: revision)
        }
        try settleAcknowledged(db, recordID: recordID, revision: revision, payload: pending.payload)
        if pending.kind == LibraryRecord.kind { try library.acknowledged(db, payload: pending.payload) }
    }
    public func cursor() throws -> Int64 {
        let value: Data? = try setting("cursor")
        return value.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int64.init) ?? 0
    }
    /// Applies a page of changes with its cursor, after authenticating every change. Content this version can't
    /// read is kept as it arrived and doesn't stop the page. Returns the images the changes refer to.
    @discardableResult public func apply(_ changes: [RemoteChange], cursor: Int64) throws -> Set<UUID> {
        var images = Set<UUID>()
        for change in changes {
            // Each change is decoded once here; applying it below reuses the result.
            let incoming = try decodeRecord(change.payload, id: change.recordId, kind: change.kind)
            images.formUnion(incoming.document.attachmentIDs)
        }
        try db.write { db in
            for change in changes { try apply(db, change: change) }
            let last = changes.last.flatMap { $0.cursor == cursor ? LoggedChange($0) : nil }
            try moveCursor(db, to: cursor, reading: last)
        }
        return images
    }
    /// Records the server's current version after a rejected push. Returns the images it refers to.
    @discardableResult public func recordConflict(_ change: RemoteChange) throws -> Set<UUID> {
        if change.recordId == LibraryRecord.id {
            // Never a review: the server's version with this device's changes on top.
            try db.write { db in record(try library.merge(db, server: change)) }
            return []
        }
        let incoming = try decode(change.payload, id: change.recordId, kind: change.kind)
        try db.write { db in
            try apply(db, change: change)
            // Refused over a revision this device already has, the queued change was based on an older one, as an
            // earlier version could leave it after a review was resolved during sending: it's sent on this one.
            try rebaseQueuedChange(db, recordID: id(change.recordId))
        }
        return Set(incoming.document.attachmentIDs)
    }
    /// Without `trustingRevision`, revisions are not compared: used when a restored server's revision
    /// numbers restarted, after reconciliation established that the change descends from local content.
    func apply(_ db: Database, change: RemoteChange, trustingRevision: Bool = true) throws {
        if change.recordId == LibraryRecord.id { return try applyLibrary(db, change: change) }
        let recordID = id(change.recordId)
        if let row = try Row.fetchOne(db, sql: "SELECT * FROM records WHERE id=?", arguments: [recordID]) {
            let revision: Int64 = row["revision"]
            if trustingRevision && change.revision < revision { return }
            if trustingRevision && change.revision == revision {
                return try keepIfOtherVersion(db, change, record: row)
            }
            if let pending = try Row.fetchOne(db, sql: "SELECT * FROM outbox WHERE record=?", arguments: [recordID]),
                (pending["payload"] as String) == change.payload, (pending["base"] as Int64) + 1 == change.revision
            {
                guard let operationID = UUID(uuidString: pending["operation"]) else { throw JournalError.invalidData }
                try acknowledge(
                    db,
                    pending: PendingChange(
                        operationId: operationID, recordID: change.recordId,
                        baseRevision: pending["base"], kind: change.kind, payload: change.payload),
                    revision: change.revision)
                return
            }
            let current = try decode(row["payload"], id: change.recordId, kind: row["kind"])
            let incoming = try decode(change.payload, id: change.recordId, kind: change.kind)
            // Even a fully acknowledged marker must not silently resurrect an offline edit.
            let hasConflict =
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID]) == true
            let explicitRevival =
                current.isCanonicalDeletionMarker
                && incoming.restoredFromDeletionID == current.permanentDeletionID
            if row["dirty"] as Bool || hasConflict
                || (current.isPermanentlyDeleted && !incoming.isPermanentlyDeleted && !explicitRevival)
            {
                try recordConflict(db, change: change)
                return
            }
        }
        let incoming = try decode(change.payload, id: change.recordId, kind: change.kind)
        if incoming.isCanonicalDeletionMarker {
            try db.execute(sql: "DELETE FROM history WHERE record=?", arguments: [recordID])
        } else if !incoming.isSupported {
            try keepLastReadableVersion(db, recordID: change.recordId)
        } else {
            let replacing = try String.fetchOne(
                db, sql: "SELECT payload FROM records WHERE id=?", arguments: [recordID])
            try keepCheckpointIfDue(db, replacing: replacing, with: incoming, fromElsewhere: true)
        }
        try db.execute(
            sql:
                "INSERT INTO records(id,kind,payload,revision,dirty) VALUES (?,?,?,?,0) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,revision=excluded.revision,dirty=0",
            arguments: [recordID, change.kind, change.payload, change.revision])
        try rememberServerVersion(db, recordID: recordID, revision: change.revision, payload: change.payload)
        receivedChanges += 1
    }
    /// A version this device can't fully read never removes the last one it can: that one stays in Version History.
    private func keepLastReadableVersion(_ db: Database, recordID: UUID) throws {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT kind,payload FROM records WHERE id=?", arguments: [id(recordID)])
        else { return }
        let payload: String = row["payload"]
        let current = try decode(payload, id: recordID, kind: row["kind"])
        guard current.isSupported, !current.isPermanentlyDeleted else { return }
        try db.execute(
            sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
            arguments: [id(recordID), current.kind, payload, JournalCoding.timestamp(Date())])
    }
    func recordConflict(_ db: Database, change: RemoteChange, replacingRevision: Bool = false) throws {
        try preserveSupersededConflict(db, change: change, replacingRevision: replacingRevision)
        let update =
            "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?) ON CONFLICT(record) DO UPDATE SET payload=excluded.payload,revision=excluded.revision,device=excluded.device,modified=excluded.modified"
        try db.execute(
            sql: replacingRevision ? update : update + " WHERE excluded.revision > conflicts.revision",
            arguments: [
                id(change.recordId), change.payload, change.revision, id(change.deviceId),
                JournalCoding.timestamp(change.modifiedAt),
            ])
        receivedChanges += 1
    }
    private func preserveSupersededConflict(_ db: Database, change: RemoteChange, replacingRevision: Bool) throws {
        let recordID = id(change.recordId)
        guard let previous = try Row.fetchOne(db, sql: "SELECT * FROM conflicts WHERE record=?", arguments: [recordID]),
            replacingRevision || (previous["revision"] as Int64) < change.revision,
            (previous["payload"] as String) != change.payload
        else { return }
        // Review must not lose an earlier conflicting edit when the remote head advances.
        try db.execute(
            sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
            arguments: [recordID, change.kind, previous["payload"] as String, previous["modified"] as String])
    }
    public func conflicts() throws -> [ConflictVersion] {
        try db.read { try conflicts($0) }
    }
    private func conflicts(_ db: Database) throws -> [ConflictVersion] {
        try Row.fetchAll(
            db, sql: "SELECT c.*,r.kind,r.payload AS local FROM conflicts c JOIN records r ON r.id=c.record"
        ).map { row in
            guard let uuid = UUID(uuidString: row["record"]), let deviceID = UUID(uuidString: row["device"]),
                let modifiedAt = try? JournalCoding.date(from: row["modified"] as String)
            else { throw JournalError.invalidData }
            return ConflictVersion(
                id: uuid, local: try decode(row["local"], id: uuid, kind: row["kind"]),
                remote: try decode(row["payload"], id: uuid, kind: row["kind"]), remoteRevision: row["revision"],
                deviceID: deviceID,
                modifiedAt: modifiedAt)
        }
    }
    @discardableResult public func resolve(_ conflict: ConflictVersion, choice: ConflictChoice) throws -> JournalItem {
        try Task.checkCancellation()
        let recordID = id(conflict.id)
        return try db.write { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql:
                        "SELECT c.*,r.payload AS local,r.kind FROM conflicts c JOIN records r ON r.id=c.record WHERE c.record=?",
                    arguments: [recordID]), (row["revision"] as Int64) == conflict.remoteRevision
            else { throw JournalError.conflict }
            let current = try decode(row["local"], id: conflict.id, kind: row["kind"])
            let remote = try decode(row["payload"], id: conflict.id, kind: row["kind"])
            guard current == conflict.local, remote == conflict.remote else { throw JournalError.conflict }
            guard !current.isPermanentlyDeleted, !remote.isPermanentlyDeleted else {
                throw PermanentDeletionError.permanentlyDeleted
            }
            guard current.document.isEditable, remote.document.isEditable else {
                throw JournalError.unsupportedFormat
            }
            guard current.kind != "journal" || choice != .keepBoth else {
                throw JournalError.server(
                    "Choose one version of this journal. Its entries will stay in the same journal.")
            }
            let originals: [String] = [row["local"], row["payload"]]
            for payload in originals {
                try db.execute(
                    sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                    arguments: [recordID, current.kind, payload, JournalCoding.timestamp(Date())])
            }
            var chosen = choice == .remote ? remote : current
            chosen.modifiedAt = Date()
            let payload = try encode(chosen)
            try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [recordID])
            try db.execute(sql: "DELETE FROM conflicts WHERE record=?", arguments: [recordID])
            try db.execute(
                sql: "UPDATE records SET payload=?,revision=?,dirty=1 WHERE id=?",
                arguments: [payload, conflict.remoteRevision, recordID])
            // The other version is the server's at that revision, unless it was kept from a save on this device.
            try rememberServerVersion(
                db, recordID: recordID, revision: conflict.remoteRevision, payload: row["payload"], unlessKnown: true)
            try enqueue(db, recordID: recordID, kind: chosen.kind, payload: payload, revision: conflict.remoteRevision)
            if choice == .keepBoth {
                var copy = remote
                copy.id = UUID()
                copy.restoredFromDeletionID = nil
                copy.modifiedAt = Date()
                let copyPayload = try encode(copy), copyID = id(copy.id)
                try db.execute(
                    sql: "INSERT INTO records(id,kind,payload) VALUES (?,?,?)",
                    arguments: [copyID, copy.kind, copyPayload])
                try enqueue(db, recordID: copyID, kind: copy.kind, payload: copyPayload, revision: 0)
            }
            return try decode(payload, id: chosen.id, kind: chosen.kind)
        }
    }
    public func setting(_ name: String) throws -> Data? {
        try db.read { try Data.fetchOne($0, sql: "SELECT value FROM settings WHERE key=?", arguments: [name]) }
    }
    public func setSetting(_ name: String, value: Data?) throws {
        try db.write { db in
            if let value {
                try db.execute(
                    sql:
                        "INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    arguments: [name, value])
            } else {
                try db.execute(sql: "DELETE FROM settings WHERE key=?", arguments: [name])
            }
        }
    }
    private func allHistory() throws -> [JournalItem] {
        let records = try db.read { db in
            try storedRecords(db, sql: "SELECT record AS id,kind,payload FROM history ORDER BY id DESC")
        }
        try Task.checkCancellation()
        let key = key
        let protection = protection
        return try Parallel.map(records) { record in
            try Self.decode(
                record.payload, id: record.id, kind: record.kind, version: Self.version(of: record.payload), key: key,
                protection: protection)
        }
    }
    func contentForImport(for purpose: ContentImport.Purpose = .archive) throws -> ContentImport {
        let allItems = try items()
        return try ContentImport(items: allItems, history: allHistory(), conflicts: conflicts(), for: purpose)
    }
    /// Adds separately identified journals to a staged destination; the caller commits that vault atomically.
    /// Source credentials, settings and synchronization baselines are deliberately not imported.
    public func importAsNewJournals(from source: JournalStore) async throws {
        let transfer = try await source.contentForImport()
        let arrangement = try await source.arrangementForImport()
        let importedItems = try transfer.items.map(transfer.remap)
        let importedHistory = try transfer.history.map(transfer.remap)
        for (original, replacement) in transfer.imageIDs {
            try Task.checkCancellation()
            let bytes = try await source.attachment(original)
            _ = try addAttachment(bytes, id: replacement)
        }
        try Task.checkCancellation()
        try saveImportedItems(importedItems)
        try importHistory(importedHistory, transfer: transfer)
        try importArrangement(arrangement, identities: transfer.recordIDs)
        // Changes an archive carried for review are settled the way any others are.
        try resolveConflicts(at: .local)
    }
    private func importHistory(_ importedHistory: [JournalItem], transfer: ContentImport) throws {
        try db.write { db in
            for item in importedHistory.reversed() {
                try db.execute(
                    sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                    arguments: [
                        id(item.id), item.kind, try encode(item), JournalCoding.timestamp(item.modifiedAt),
                    ])
            }
            for conflict in transfer.conflicts {
                let remote = try transfer.remap(conflict.remote)
                try db.execute(
                    sql: "INSERT INTO conflicts(record,payload,revision,device,modified) VALUES (?,?,?,?,?)",
                    arguments: [
                        id(remote.id), try encode(remote), 0, id(conflict.deviceID),
                        JournalCoding.timestamp(conflict.modifiedAt),
                    ])
            }
        }
    }
    /// Rejects a restored database with objects the app doesn't create, such as triggers or views that would act
    /// on later writes. Call after opening it, when every known migration has been applied. The structure is compared,
    /// not the text that created it, because another client's database library writes the same tables differently
    /// (`DatabaseStructure`).
    public func validateSchema() throws {
        let expected = try DatabaseStructure.expected(afterMigrations: Self.migrator.migrations.count)
        guard try db.read(DatabaseStructure.read).matches(expected) else { throw JournalError.invalidData }
    }
    /// Images used by current records, their earlier versions and versions awaiting review.
    public func referencedAttachmentIDs() throws -> Set<UUID> {
        // The library record has no images, but it's authenticated with everything else.
        if let stored = try db.read({ try library.stored($0) }) {
            _ = try openedPayload(stored.payload, id: LibraryRecord.id, kind: LibraryRecord.kind)
        }
        var images = Set(try items().flatMap { $0.document.attachmentIDs })
        images.formUnion(try allHistory().flatMap { $0.document.attachmentIDs })
        for conflict in try conflicts() { images.formUnion(conflict.remote.document.attachmentIDs) }
        return images
    }
    /// The images among `identifiers` that have no file on this device.
    public func missingAttachments(_ identifiers: Set<UUID>) -> Set<UUID> {
        identifiers.filter { !FileManager.default.fileExists(atPath: attachmentURL($0).path) }
    }
    /// Copies a consistent encrypted vault, including revisions, pending operations and history.
    /// The destination must be new. No server credentials are stored in this database.
    public func snapshot(to destination: URL, requireComplete: Bool = false) async throws {
        try Task.checkCancellation()
        if requireComplete { try await validateSnapshot() }
        try copySnapshot(to: destination)
    }
    private func copySnapshot(to destination: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else {
            throw JournalError.server("Choose a new location for the journal copy.")
        }
        try manager.createDirectory(
            at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var target: DatabaseQueue?
        do {
            let snapshot = try DatabaseQueue(path: destination.appendingPathComponent("journal.sqlite").path)
            target = snapshot
            try db.backup(to: snapshot)
            // A single self-contained file: the copy doesn't keep this store's write-ahead log mode.
            try snapshot.writeWithoutTransaction { _ = try String.fetchOne($0, sql: "PRAGMA journal_mode = DELETE") }
            let images = destination.appendingPathComponent("attachments", isDirectory: true)
            try manager.createDirectory(at: images, withIntermediateDirectories: true)
            let identifiers = try db.read { try String.fetchAll($0, sql: "SELECT id FROM attachments") }
            for identifier in identifiers {
                try Task.checkCancellation()
                guard let uuid = UUID(uuidString: identifier) else { throw JournalError.invalidData }
                try manager.copyItem(
                    at: directory.appendingPathComponent("attachments/\(id(uuid))"),
                    to: images.appendingPathComponent(id(uuid)))
            }
            try Task.checkCancellation()
            try snapshot.close()
            for suffix in ["-wal", "-shm"] {
                let leftover = destination.appendingPathComponent("journal.sqlite" + suffix)
                if manager.fileExists(atPath: leftover.path) { try manager.removeItem(at: leftover) }
            }
        } catch {
            try? target?.close()
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    public func addAttachment(_ bytes: Data, id uuid: UUID = UUID()) throws -> UUID {
        guard bytes.count <= 25 * 1024 * 1024 - 28 else {
            throw JournalError.server("Choose an image smaller than 25 MB.")
        }
        let encrypted = try protection.encode(bytes, key: key, context: VaultCrypto.attachmentContext(id: uuid))
        try cacheAttachment(encrypted, id: uuid, uploaded: false)
        return uuid
    }
    public func cacheAttachment(_ encrypted: Data, id uuid: UUID, uploaded: Bool = true) throws {
        guard encrypted.count <= Self.maximumAttachmentBytes else { throw JournalError.invalidData }
        _ = try protection.decode(encrypted, key: key, context: VaultCrypto.attachmentContext(id: uuid))
        try encrypted.write(to: attachmentURL(uuid), options: .atomic)
        try db.write {
            try $0.execute(
                sql:
                    "INSERT INTO attachments(id,uploaded) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET uploaded=excluded.uploaded",
                arguments: [id(uuid), uploaded])
        }
        if uploaded { receivedChanges += 1 }
    }
    public func attachment(_ uuid: UUID) throws -> Data {
        try protection.decode(encryptedAttachment(uuid), key: key, context: VaultCrypto.attachmentContext(id: uuid))
    }
    public func encryptedAttachment(_ uuid: UUID) throws -> Data {
        try Self.encryptedAttachment(at: attachmentURL(uuid))
    }
    func attachmentURL(_ uuid: UUID) -> URL { directory.appendingPathComponent("attachments/\(id(uuid))") }
    public func close() throws { try db.close() }
    public func pendingAttachments() throws -> [UUID] {
        try db.read {
            try String.fetchAll($0, sql: "SELECT id FROM attachments WHERE uploaded=0").compactMap(
                UUID.init(uuidString:))
        }
    }
    public func acknowledgeAttachment(_ uuid: UUID) throws {
        try db.write { try $0.execute(sql: "UPDATE attachments SET uploaded=1 WHERE id=?", arguments: [id(uuid)]) }
    }
}

extension JournalItem {
    /// Whether this version reads every field of the record, rather than preserving one it can't fully read.
    var isSupported: Bool { preservedJSON == nil && document.isEditable }
}
