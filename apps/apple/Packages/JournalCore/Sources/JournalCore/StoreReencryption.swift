import Foundation
import GRDB

/// What an encrypted copy of a library keeps of its place on a server (docs/design/enable-encryption.md).
public enum ReencryptionBaseline: Sendable {
    /// The server is emptied and re-keyed by this device: every record and image is sent again from the copy. Another
    /// device that signed in again first may have sent the same journals, so the copy compares everything the server
    /// has by content first, and checks each image before uploading it.
    case restart
    /// Another device re-keyed the server: the copy compares everything with the server by content first, so records
    /// the server has are matched, not duplicated, and edits that differ are kept for review.
    case reconcile
}

/// Turning on encryption for a library created without it. The copy keeps every record and image under the same
/// identity, with its Version History and reviews; only how it's stored changes. It's built beside the library, checked,
/// and then switched to by the app, so the library is unchanged until then.
extension JournalStore {
    /// About how many bytes an encrypted copy of this library needs: its database and images.
    public func reencryptionSize() throws -> Int64 {
        let database =
            [directory.appendingPathComponent("journal.sqlite")]
            + ["-wal", "-shm"].map { directory.appendingPathComponent("journal.sqlite" + $0) }
        let identifiers = try db.read { try String.fetchAll($0, sql: "SELECT id FROM attachments") }
        let images = identifiers.map { directory.appendingPathComponent("attachments/\($0)") }
        return (database + images).reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// The position in the server's log this library has read, for a server that must not have changed since.
    public func syncedPosition() throws -> (cursor: Int64, change: LoggedChange?) {
        let position = try syncPosition()
        return (position.cursor, position.applied)
    }

    /// Makes an encrypted copy of this library, which must be unencrypted, in the new folder `destination`, sealed
    /// with `key`, and returns it opened. Every record, earlier version, review and image is sealed from its exact
    /// stored bytes, so content this version can only read is kept as it is. The copy is checked before it's
    /// returned: it opens only with `key`, and every row and image decrypts to the original bytes. `progress`
    /// receives the fraction done. When anything fails or the task is cancelled, the folder is removed.
    public func reencryptedCopy(
        to destination: URL, key newKey: Data, baseline: ReencryptionBaseline,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> JournalStore {
        guard protection == .plaintext, newKey.count == 32 else { throw JournalError.invalidData }
        try await snapshot(to: destination)
        do {
            let copy = try Reencryption(directory: destination, key: newKey, progress: progress)
            try copy.sealRecords(baseline: baseline)
            try copy.sealImages()
            let store = try JournalStore(directory: destination, key: newKey, protection: .encrypted)
            do {
                try await store.validateSchema()
                try await store.validateSnapshot()
                try await verify(copy: store)
            } catch {
                try? await store.close()
                throw error
            }
            progress(1)
            return store
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Checks that every record, earlier version, review and image of `copy` holds exactly the bytes stored here.
    private func verify(copy: JournalStore) async throws {
        for table in Reencryption.verifiedTables {
            let original = try await db.read { try Reencryption.payloads(table, in: $0) }
            let sealed = try await copy.plaintextPayloads(table)
            guard original == sealed else { throw JournalError.invalidData }
        }
        let identifiers = try await db.read { try String.fetchAll($0, sql: "SELECT id FROM attachments") }
        for identifier in identifiers {
            try Task.checkCancellation()
            guard let uuid = UUID(uuidString: identifier) else { throw JournalError.invalidData }
            guard try await copy.attachment(uuid) == attachment(uuid) else { throw JournalError.invalidData }
        }
    }

    /// The decrypted bytes of every payload in `table`, by the row's key.
    func plaintextPayloads(_ table: Reencryption.Table) throws -> [String: Data] {
        let rows = try db.read { try Row.fetchAll($0, sql: table.select) }
        var payloads: [String: Data] = [:]
        for row in rows {
            guard let id = UUID(uuidString: row["record"]), let sealed = Data(base64Encoded: row["payload"] as String)
            else { throw JournalError.invalidData }
            payloads[row["key"]] = try protection.decode(
                sealed, key: key, context: VaultCrypto.recordContext(id: id, kind: row["kind"]))
        }
        return payloads
    }

    /// Waits until a synchronization of this library that is running finishes, then keeps others from starting until
    /// `releaseSynchronization()`. Turning on encryption holds it from before the server switches until the encrypted
    /// copy replaced this library, so no synchronization of this library runs across the switch.
    public func holdSynchronization() async throws { try await beginSynchronization() }
    public func releaseSynchronization() { endSynchronization() }

    /// After the server refused `pending` because it has a newer revision `remote`: when that revision holds the same
    /// content, as when another device encrypted the same journals separately and sent them first, it's adopted as if
    /// this change had been accepted, instead of being shown for review. Returns whether it was.
    func adoptSameContent(_ pending: PendingChange, remote: RemoteChange) throws -> Bool {
        // The library record is merged instead, which also adopts the same content (`recordConflict`).
        guard remote.recordId == pending.recordID, remote.kind == pending.kind, pending.kind != LibraryRecord.kind,
            sameContent(remote.payload, pending.payload, id: pending.recordID, kind: pending.kind)
        else { return false }
        let recordID = id(pending.recordID)
        let adopted = try db.write { db -> Bool in
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT payload, revision FROM records WHERE id=?", arguments: [recordID]),
                (row["revision"] as Int64) < remote.revision,
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM outbox WHERE operation=?)",
                    arguments: [id(pending.operationId)]) == true,
                try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID]) == false
            else { return false }
            guard (row["payload"] as String) == pending.payload else {
                // Edited since: the edit is sent next, based on the server's revision.
                try acknowledge(db, pending: pending, revision: remote.revision)
                return true
            }
            try db.execute(sql: "DELETE FROM outbox WHERE operation=?", arguments: [id(pending.operationId)])
            try db.execute(
                sql: "UPDATE records SET payload=?, revision=?, dirty=0 WHERE id=?",
                arguments: [remote.payload, remote.revision, recordID])
            return true
        }
        if adopted { receivedChanges += 1 }
        return adopted
    }

    /// Whether two stored payloads of a record hold the same content. Encrypted payloads of the same content differ,
    /// for example between two devices that encrypted their copies separately, so they're compared decrypted.
    func sameContent(_ first: String, _ second: String?, id: UUID, kind: String) -> Bool {
        guard let second else { return false }
        if first == second { return true }
        guard protection == .encrypted, let one = Data(base64Encoded: first), let other = Data(base64Encoded: second)
        else { return false }
        let context = VaultCrypto.recordContext(id: id, kind: kind)
        guard let opened = try? protection.decode(one, key: key, context: context),
            let otherOpened = try? protection.decode(other, key: key, context: context)
        else { return false }
        return opened == otherOpened
    }
}

/// Seals a copy of an unencrypted library in place. The copy is new and private to this operation, so its database
/// keeps no rollback journal on disk, replaced content is overwritten, and free pages are removed at the end.
final class Reencryption {
    /// A table whose rows hold a record payload: each row's key, record identity and kind.
    struct Table: Sendable {
        let name: String
        let select: String
    }
    static let records = Table(
        name: "records", select: "SELECT rowid, id AS key, id AS record, kind, payload FROM records")
    static let history = Table(
        name: "history", select: "SELECT rowid, CAST(id AS TEXT) AS key, record, kind, payload FROM history")
    static let conflicts = Table(
        name: "conflicts",
        select:
            "SELECT c.rowid AS rowid, c.record AS key, c.record AS record, r.kind AS kind, c.payload AS payload FROM conflicts c JOIN records r ON r.id = c.record"
    )
    static let outbox = Table(
        name: "outbox", select: "SELECT rowid, operation AS key, record, kind, payload FROM outbox")
    /// The tables whose content the copy keeps exactly. A restart queues the outbox again.
    static let verifiedTables = [records, history, conflicts]

    private let database: DatabaseQueue
    private let directory: URL
    private let key: Data
    private let progress: @Sendable (Double) -> Void
    private let totalBytes: Int64
    private var doneBytes: Int64 = 0

    init(directory: URL, key: Data, progress: @escaping @Sendable (Double) -> Void) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.hardenAgainstHostileSchema()
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Readable content that's replaced is overwritten rather than left in free pages.
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        database = try DatabaseQueue(
            path: directory.appendingPathComponent("journal.sqlite").path, configuration: configuration)
        // No journal file holding the readable pages; a copy that fails is removed anyway.
        try database.writeWithoutTransaction { _ = try String.fetchOne($0, sql: "PRAGMA journal_mode = MEMORY") }
        self.directory = directory
        self.key = key
        self.progress = progress
        let recordBytes = try database.read { db in
            try [Self.records, Self.history, Self.conflicts, Self.outbox].reduce(Int64(0)) { total, table in
                let sum = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(LENGTH(payload)), 0) FROM \(table.name)")
                return total + (sum ?? 0)
            }
        }
        totalBytes = max(1, recordBytes + Self.imageBytes(in: directory))
    }
    private static func imageBytes(in directory: URL) -> Int64 {
        let folder = directory.appendingPathComponent("attachments")
        let files =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(Int64(0)) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
    /// The stored bytes of every payload of an unencrypted library's `table`, by the row's key.
    static func payloads(_ table: Table, in db: Database) throws -> [String: Data] {
        var payloads: [String: Data] = [:]
        for row in try Row.fetchAll(db, sql: table.select) {
            guard let bytes = Data(base64Encoded: row["payload"] as String) else { throw JournalError.invalidData }
            payloads[row["key"]] = bytes
        }
        return payloads
    }
    private func advance(by bytes: Int) {
        doneBytes += Int64(bytes)
        progress(min(0.99, Double(doneBytes) / Double(totalBytes)))
    }

    /// Seals every record payload, then prepares the copy's place on the server for `baseline`.
    func sealRecords(baseline: ReencryptionBaseline) throws {
        try database.write { db in
            for table in [Self.records, Self.history, Self.conflicts, Self.outbox] {
                try seal(table, in: db)
            }
            try db.execute(sql: "DELETE FROM reconcile_heads")
            try db.execute(
                sql: "DELETE FROM settings WHERE key IN ('cursor', 'cursor-change', 'server-id', 'reconcile')")
            switch baseline {
            case .restart: try restart(db)
            case .reconcile: try reconcile(db)
            }
            try sealLocalSettings(db)
            try db.execute(
                sql: "UPDATE settings SET value = ? WHERE key = 'content-protection'",
                arguments: [ContentProtection.encrypted.rawValue])
        }
        try database.vacuum()
    }
    private func seal(_ table: Table, in db: Database) throws {
        var last: Int64 = -1
        while true {
            try Task.checkCancellation()
            let rows = try Row.fetchAll(
                db, sql: "SELECT * FROM (\(table.select)) WHERE rowid > ? ORDER BY rowid LIMIT 200", arguments: [last])
            guard let final = rows.last else { return }
            for row in rows {
                let payload: String = row["payload"]
                guard let id = UUID(uuidString: row["record"]), let bytes = Data(base64Encoded: payload) else {
                    throw JournalError.invalidData
                }
                let sealed = try VaultCrypto.seal(
                    bytes, key: key, context: VaultCrypto.recordContext(id: id, kind: row["kind"]))
                try db.execute(
                    sql: "UPDATE \(table.name) SET payload = ? WHERE rowid = ?",
                    arguments: [sealed.base64EncodedString(), row["rowid"] as Int64])
                advance(by: payload.utf8.count)
            }
            last = final["rowid"]
        }
    }
    /// Every record is sent to the emptied server again. A record waiting for review keeps its review, which creates
    /// it again when it's resolved, as after a server lost it. What the server has is compared first, and images are
    /// checked before they're uploaded: another device that signed in again may have sent the same journals already,
    /// and the server keeps the first upload of an image.
    private func restart(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM outbox")
        try db.execute(sql: "UPDATE records SET revision = 0, dirty = 1")
        try db.execute(sql: "UPDATE conflicts SET revision = 0")
        // The library record is queued by the first synchronization with a server that takes it.
        let rows = try Row.fetchAll(
            db,
            sql:
                "SELECT id, kind, payload FROM records WHERE id NOT IN (SELECT record FROM conflicts) AND kind <> 'library'"
        )
        for row in rows {
            try db.execute(
                sql: "INSERT INTO outbox(operation, record, kind, payload, base) VALUES (?, ?, ?, ?, 0)",
                arguments: [
                    UUID().uuidString.lowercased(), row["id"] as String, row["kind"] as String,
                    row["payload"] as String,
                ])
        }
        try db.execute(sql: "UPDATE attachments SET uploaded = 2")
        try startReconciliation(db)
    }
    private func startReconciliation(_ db: Database) throws {
        let state = try JournalCoding.encoder().encode(ReconciliationState(serverID: nil, cursor: 0))
        try db.execute(sql: "INSERT INTO settings(key, value) VALUES ('reconcile', ?)", arguments: [state])
    }
    /// The server's log is compared with this copy before anything is sent (SyncReconciliation.swift). Images this
    /// device uploaded before are checked rather than sent again, since the server keeps another device's upload.
    private func reconcile(_ db: Database) throws {
        try startReconciliation(db)
        try db.execute(sql: "UPDATE attachments SET uploaded = 2 WHERE uploaded = 1")
    }

    /// Seals the settings that are stored under the library key rather than as records: the library record's unsent
    /// changes (`library-changes`) and the notes about changes settled on two devices (`kept-notes`). A value that
    /// can't be read was of no use to this library either and is left out.
    private func sealLocalSettings(_ db: Database) throws {
        try sealSetting(db, name: LibraryChanges.setting, context: LibraryChanges.context) {
            (try? JournalCoding.decoder().decode(LibraryChanges.self, from: $0)) != nil
        }
        try sealSetting(db, name: KeptNotesState.setting, context: KeptNotesState.context) {
            (try? JournalCoding.decoder().decode(KeptNotesState.self, from: $0)) != nil
        }
    }
    private func sealSetting(_ db: Database, name: String, context: String, isReadable: (Data) -> Bool) throws {
        guard let stored = try Data.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [name])
        else { return }
        guard let text = String(data: stored, encoding: .utf8), let readable = Data(base64Encoded: text),
            isReadable(readable)
        else {
            try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [name])
            return
        }
        let sealed = try VaultCrypto.seal(readable, key: key, context: context)
        try db.execute(
            sql: "UPDATE settings SET value = ? WHERE key = ?",
            arguments: [Data(sealed.base64EncodedString().utf8), name])
    }

    /// Seals every image file in place, then closes the copy's database.
    func sealImages() throws {
        let identifiers = try database.read { try String.fetchAll($0, sql: "SELECT id FROM attachments") }
        try database.close()
        for identifier in identifiers {
            try Task.checkCancellation()
            guard let id = UUID(uuidString: identifier) else { throw JournalError.invalidData }
            let file = directory.appendingPathComponent("attachments/\(identifier)")
            let bytes = try Data(contentsOf: file)
            let sealed = try VaultCrypto.seal(bytes, key: key, context: VaultCrypto.attachmentContext(id: id))
            try sealed.write(to: file, options: .atomic)
            advance(by: bytes.count)
        }
    }
}
