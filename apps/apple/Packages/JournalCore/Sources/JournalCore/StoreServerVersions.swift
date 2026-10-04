import CryptoKit
import Foundation
import GRDB

/// The version the server holds at each record's revision, as this device last sent or received it
/// (table `server_versions`). The server gives a revision to only one version, unless it lost a version it accepted,
/// such as after its data folder was replaced by an older copy: a different version at a revision this device has is
/// then kept for review instead of being ignored.
extension JournalStore {
    static let serverVersionsSchema =
        "CREATE TABLE server_versions (record TEXT PRIMARY KEY, revision INTEGER NOT NULL, digest TEXT NOT NULL)"
    /// Identifies a payload exactly, without keeping it.
    static func payloadDigest(_ payload: String) -> String {
        SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Remembers that the server holds `payload` at a record's revision. With `unlessKnown`, a version already
    /// remembered for that revision is kept.
    func rememberServerVersion(
        _ db: Database, recordID: String, revision: Int64, payload: String, unlessKnown: Bool = false
    ) throws {
        try Self.rememberServerVersion(
            db, recordID: recordID, revision: revision, payload: payload, unlessKnown: unlessKnown)
    }
    static func rememberServerVersion(
        _ db: Database, recordID: String, revision: Int64, payload: String, unlessKnown: Bool = false
    ) throws {
        guard revision > 0 else { return }
        try db.execute(
            sql: """
                INSERT INTO server_versions(record,revision,digest) VALUES (?,?,?)
                ON CONFLICT(record) DO UPDATE SET revision=excluded.revision,digest=excluded.digest
                """ + (unlessKnown ? " WHERE server_versions.revision<>excluded.revision" : ""),
            arguments: [recordID, revision, payloadDigest(payload)])
    }
    /// After the server accepted `payload` at `revision`: remembers it, rebases a change queued while it was being
    /// sent, such as when a review was resolved meanwhile, and lets a review whose other version is the one accepted
    /// compare with the revision it got.
    func settleAcknowledged(_ db: Database, recordID: String, revision: Int64, payload: String) throws {
        try rememberServerVersion(db, recordID: recordID, revision: revision, payload: payload)
        try rebaseQueuedChange(db, recordID: recordID)
        try db.execute(
            sql: "UPDATE conflicts SET revision=? WHERE record=? AND revision<? AND payload=?",
            arguments: [revision, recordID, revision, payload])
        if db.changesCount > 0 { receivedChanges += 1 }
    }
    /// Replaces a queued change based on an older revision than this device has with one based on that revision,
    /// carrying the record's current content, or removes it when nothing is left to send. A change waiting for a
    /// review is left to the review.
    func rebaseQueuedChange(_ db: Database, recordID: String) throws {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT o.operation,r.kind,r.payload,r.revision,r.dirty FROM outbox o JOIN records r ON r.id=o.record
                    WHERE o.record=? AND o.base<r.revision AND NOT EXISTS(SELECT 1 FROM conflicts WHERE record=o.record)
                    """,
                arguments: [recordID])
        else { return }
        let operation: String = row["operation"]
        try db.execute(sql: "DELETE FROM outbox WHERE operation=?", arguments: [operation])
        if let operationID = UUID(uuidString: operation) { unsentOperations[operationID] = nil }
        guard row["dirty"] as Bool else { return }
        try enqueue(db, recordID: recordID, kind: row["kind"], payload: row["payload"], revision: row["revision"])
    }
    /// Keeps a change at the revision this device has for review when it holds another version than the one known.
    func keepIfOtherVersion(_ db: Database, _ change: RemoteChange, record row: Row) throws {
        guard try isOtherVersion(db, change: change, record: row) else { return }
        try keepOtherVersion(db, change: change)
    }
    /// Whether a change at the revision this device has holds another version than the one this device knows there.
    /// That happens only when the server lost a version it had accepted, such as after its data folder was replaced
    /// by an older copy, and gave the revision to another change.
    private func isOtherVersion(_ db: Database, change: RemoteChange, record row: Row) throws -> Bool {
        let local: String = row["payload"]
        guard change.payload != local else { return false }
        let known = try Row.fetchOne(
            db, sql: "SELECT digest FROM server_versions WHERE record=? AND revision=?",
            arguments: [id(change.recordId), change.revision]
        ).map { $0["digest"] as String }
        if known == Self.payloadDigest(change.payload) { return false }
        // The same content sealed by another device is the same version.
        if sameContent(change.payload, local, id: change.recordId, kind: change.kind) { return false }
        // Without edits since, this device has the version it knows; with them, only a remembered one is known.
        return known != nil || !(row["dirty"] as Bool)
    }
    /// Keeps both versions for review: this device's stays the record, waiting to be sent, and the server's is the
    /// other side. A review already pending for a later revision keeps this version in Version History instead.
    private func keepOtherVersion(_ db: Database, change: RemoteChange) throws {
        let recordID = id(change.recordId)
        let reviewed = try Int64.fetchOne(
            db, sql: "SELECT revision FROM conflicts WHERE record=?", arguments: [recordID])
        if let reviewed, reviewed > change.revision {
            try db.execute(
                sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                arguments: [recordID, change.kind, change.payload, JournalCoding.timestamp(change.modifiedAt)])
            receivedChanges += 1
        } else {
            try recordConflict(db, change: change, replacingRevision: true)
        }
        try db.execute(sql: "UPDATE records SET dirty=1 WHERE id=?", arguments: [recordID])
        try rememberServerVersion(db, recordID: recordID, revision: change.revision, payload: change.payload)
    }

    /// The newest change this device sent that the server accepted, which may be past the position it has read.
    struct SentChange: Codable {
        var serverID: String?
        var cursor: Int64
        var change: LoggedChange
    }
    static let sentChangeSetting = "sent-change"
    /// Acknowledges a change this device sent with the server's receipt, and remembers the receipt.
    func acknowledgeSent(_ db: Database, pending: PendingChange, receipt: RemoteChange, readingOn: Bool = false)
        throws
    {
        try acknowledge(db, pending: pending, revision: receipt.revision)
        try rememberSentChange(db, receipt: receipt)
        if readingOn { try readOwnChange(db, receipt: receipt) }
    }
    /// A change the server placed right after the position this device has read can't have another change before
    /// it, so the position moves past it rather than downloading what was just sent as if it came from elsewhere.
    /// Otherwise it's read with the rest, as before. Only for a server that confirms the payload this device read
    /// last: if it later loses the change and gives its place to another device's version of the same revision, that
    /// is noticed when reading on, as reading the change again would have.
    private func readOwnChange(_ db: Database, receipt: RemoteChange) throws {
        guard receipt.cursor > 0,
            try Data.fetchOne(db, sql: "SELECT value FROM settings WHERE key='reconcile'") == nil
        else { return }
        let position =
            try Data.fetchOne(db, sql: "SELECT value FROM settings WHERE key='cursor'")
            .flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int64.init) ?? 0
        guard receipt.cursor == position + 1 else { return }
        try moveCursor(db, to: receipt.cursor, reading: LoggedChange(receipt))
    }
    private func rememberSentChange(_ db: Database, receipt: RemoteChange) throws {
        let serverID = try Data.fetchOne(db, sql: "SELECT value FROM settings WHERE key='server-id'")
            .flatMap { String(data: $0, encoding: .utf8) }
        if let stored = try Data.fetchOne(
            db, sql: "SELECT value FROM settings WHERE key=?", arguments: [Self.sentChangeSetting]),
            let sent = try? JournalCoding.decoder().decode(SentChange.self, from: stored),
            sent.serverID == serverID, sent.cursor >= receipt.cursor
        {
            return
        }
        let sent = SentChange(serverID: serverID, cursor: receipt.cursor, change: LoggedChange(receipt))
        try db.execute(
            sql: "INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            arguments: [Self.sentChangeSetting, try JournalCoding.encoder().encode(sent)])
    }
    /// The newest accepted change this device sent to the server reporting `serverID`, when it's past the position
    /// this device has read: before sending more, the server must still have it, or it lost it and gave its place to
    /// another change.
    func sentChangePastPosition(serverID: String?) throws -> (cursor: Int64, change: LoggedChange)? {
        guard let stored = try setting(Self.sentChangeSetting),
            let sent = try? JournalCoding.decoder().decode(SentChange.self, from: stored),
            sent.serverID == serverID, sent.cursor > (try cursor())
        else { return nil }
        return (sent.cursor, sent.change)
    }
}
