import Foundation
import GRDB

/// Progress while re-reading a server whose database changed, for example after a backup restore.
public struct ReconciliationState: Codable, Sendable, Equatable {
    public var serverID: String?
    public var cursor: Int64
}

/// When a server's database identity changes, its change cursors and revision numbers restarted from an
/// older state. The client then re-reads the whole log and compares it with local records by content:
/// - equal content adopts the server's revision;
/// - a server version that descends from local content is applied;
/// - a server version from before the restore that is not newer than ours is replaced by re-uploading
///   ours, since the server lost later revisions this device had;
/// - anything else, including versions written after the restore, becomes a normal conflict for review;
/// - records the server lost entirely are uploaded again.
/// Nothing is discarded silently and no conflicting edit is overwritten.
extension JournalStore {
    public func syncedServerID() throws -> String? {
        try setting("server-id").flatMap { String(data: $0, encoding: .utf8) }
    }
    public func reconciliation() throws -> ReconciliationState? {
        try setting("reconcile").map { try JournalCoding.decoder().decode(ReconciliationState.self, from: $0) }
    }
    /// Whether this store must reconcile before synchronizing with a server reporting `serverID`.
    public func needsReconciliation(serverID: String?) throws -> Bool {
        if try reconciliation() != nil { return true }
        let stored = try syncedServerID()
        if stored == serverID { return false }
        guard stored == nil, let serverID else { return true }
        // A store that never synchronized adopts the identity; one with history may predate a restore.
        let synchronized = try db.read { db in
            try Bool.fetchOne(
                db,
                sql:
                    "SELECT EXISTS(SELECT 1 FROM records WHERE revision > 0) OR EXISTS(SELECT 1 FROM outbox WHERE base > 0) OR EXISTS(SELECT 1 FROM settings WHERE key='cursor' AND CAST(value AS TEXT) <> '0')"
            ) == true
        }
        if synchronized { return true }
        try setSetting("server-id", value: Data(serverID.utf8))
        return false
    }
    public func beginReconciliation(serverID: String?) throws {
        let state = try JournalCoding.encoder().encode(ReconciliationState(serverID: serverID, cursor: 0))
        try db.write { db in
            try db.execute(sql: "DELETE FROM reconcile_heads")
            try db.execute(
                sql:
                    "INSERT INTO settings(key,value) VALUES ('reconcile',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [state])
        }
    }
    /// Records the latest server version of each record in a page, after authenticating every change.
    public func stageReconciliation(_ changes: [RemoteChange], cursor: Int64) throws {
        guard var state = try reconciliation() else { throw JournalError.invalidData }
        for change in changes { _ = try decode(change.payload, id: change.recordId, kind: change.kind) }
        state.cursor = cursor
        let encoded = try JournalCoding.encoder().encode(state)
        try db.write { db in
            for change in changes {
                let recordID = id(change.recordId)
                let local = try String.fetchOne(
                    db, sql: "SELECT payload FROM records WHERE id=?", arguments: [recordID])
                try db.execute(
                    sql: """
                        INSERT INTO reconcile_heads(record,kind,payload,revision,cursor,device,modified,seen_payload) VALUES (?,?,?,?,?,?,?,?)
                        ON CONFLICT(record) DO UPDATE SET kind=excluded.kind,payload=excluded.payload,revision=excluded.revision,cursor=excluded.cursor,device=excluded.device,modified=excluded.modified,seen_payload=COALESCE(excluded.seen_payload,reconcile_heads.seen_payload)
                        """,
                    arguments: [
                        recordID, change.kind, change.payload, change.revision, change.cursor, id(change.deviceId),
                        JournalCoding.timestamp(change.modifiedAt),
                        sameContent(change.payload, local, id: change.recordId, kind: change.kind)
                            ? change.payload : nil,
                    ])
            }
            try db.execute(sql: "UPDATE settings SET value=? WHERE key='reconcile'", arguments: [encoded])
        }
    }
    /// Compares the staged server log with local records. `serverIDCursor` is the newest change that
    /// existed when the server's identity was assigned; later changes were written after a restore.
    public func finishReconciliation(serverIDCursor: Int64) throws {
        guard let state = try reconciliation() else { throw JournalError.invalidData }
        try db.write { db in
            // Revision numbers may have been reused, so versions remembered for them no longer apply.
            try db.execute(sql: "DELETE FROM server_versions")
            let heads = try Row.fetchAll(db, sql: "SELECT * FROM reconcile_heads")
            var seen = Set<String>()
            for head in heads {
                seen.insert(head["record"])
                try reconcile(db, head: head, serverIDCursor: serverIDCursor)
            }
            let local = try Row.fetchAll(db, sql: "SELECT id,kind,payload,revision FROM records")
            for row in local where !seen.contains(row["id"]) {
                try reconcileMissing(db, row: row)
            }
            // The server may also have lost images; each is checked before the next upload of records.
            try db.execute(sql: "UPDATE attachments SET uploaded=2 WHERE uploaded=1")
            let last = try stagedChange(db, at: state.cursor)
            try db.execute(sql: "DELETE FROM reconcile_heads")
            try db.execute(
                sql: "DELETE FROM settings WHERE key IN ('reconcile',?)", arguments: [Self.sentChangeSetting])
            try moveCursor(db, to: state.cursor, reading: last)
            if let serverID = state.serverID {
                try db.execute(
                    sql:
                        "INSERT INTO settings(key,value) VALUES ('server-id',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                    arguments: [Data(serverID.utf8)])
            } else {
                try db.execute(sql: "DELETE FROM settings WHERE key='server-id'")
            }
        }
    }
    /// The change a reconciliation read at `cursor`: the newest change of its record, so it's always staged.
    func stagedChange(at cursor: Int64) throws -> LoggedChange? {
        try db.read { try stagedChange($0, at: cursor) }
    }
    private func stagedChange(_ db: Database, at cursor: Int64) throws -> LoggedChange? {
        guard cursor > 0,
            let row = try Row.fetchOne(
                db, sql: "SELECT record,revision,payload FROM reconcile_heads WHERE cursor=?", arguments: [cursor]),
            let record = UUID(uuidString: row["record"])
        else { return nil }
        return LoggedChange(recordId: record, revision: row["revision"], digest: Self.payloadDigest(row["payload"]))
    }
    public func attachmentsToVerify() throws -> [UUID] {
        try db.read {
            try String.fetchAll($0, sql: "SELECT id FROM attachments WHERE uploaded=2").compactMap(
                UUID.init(uuidString:))
        }
    }

    private func reconcile(_ db: Database, head: Row, serverIDCursor: Int64) throws {
        let recordID: String = head["record"]
        guard let uuid = UUID(uuidString: recordID), let deviceID = UUID(uuidString: head["device"]),
            let modified = try? JournalCoding.date(from: head["modified"] as String)
        else { throw JournalError.invalidData }
        let change = RemoteChange(
            cursor: head["cursor"], recordId: uuid, revision: head["revision"], kind: head["kind"],
            payload: head["payload"], deviceId: deviceID, modifiedAt: modified)
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM records WHERE id=?", arguments: [recordID]) else {
            try apply(db, change: change)
            return
        }
        if uuid == LibraryRecord.id {
            // Never a review: what this device knows only fills in what the server lacks (pinned-entries.md, rule 4).
            return record(try library.reconcile(db, server: change, seen: head["seen_payload"]))
        }
        if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID])
            == true
        {
            // Keep the pending review; compare against what the server has now. A replaced remote version
            // is kept in history.
            try recordConflict(db, change: change, replacingRevision: true)
            try alignConflictRevision(db, recordID: recordID, revision: change.revision)
            return
        }
        let local: String = row["payload"]
        let seenPayload: String? = head["seen_payload"]
        let fromBeforeIdentity = change.cursor <= serverIDCursor
        // Content is compared decrypted: another device's copy of the same content is sealed differently.
        if sameContent(change.payload, local, id: uuid, kind: change.kind) {
            try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [recordID])
            try db.execute(
                sql: "UPDATE records SET revision=?,dirty=0 WHERE id=?", arguments: [change.revision, recordID])
            try rememberServerVersion(db, recordID: recordID, revision: change.revision, payload: change.payload)
        } else if let seenPayload, sameContent(seenPayload, local, id: uuid, kind: change.kind) {
            // The server has our content and newer versions based on it.
            try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [recordID])
            try db.execute(sql: "UPDATE records SET dirty=0 WHERE id=?", arguments: [recordID])
            try apply(db, change: change, trustingRevision: false)
        } else if seenPayload == change.payload
            || (fromBeforeIdentity && change.revision <= row["revision"] as Int64)
        {
            // The server lost newer versions this device has (or edited since reading them).
            try reupload(db, recordID: recordID, kind: row["kind"], payload: local, base: change.revision)
            try rememberServerVersion(db, recordID: recordID, revision: change.revision, payload: change.payload)
        } else if fromBeforeIdentity {
            try apply(db, change: change)
        } else {
            try recordConflict(db, change: change)
        }
        try alignConflictRevision(db, recordID: recordID, revision: change.revision)
    }
    /// Later remote changes are compared with the local revision, which must use the server's numbering.
    private func alignConflictRevision(_ db: Database, recordID: String, revision: Int64) throws {
        try db.execute(
            sql: "UPDATE records SET revision=? WHERE id=? AND EXISTS(SELECT 1 FROM conflicts WHERE record=?)",
            arguments: [revision, recordID, recordID])
    }
    private func reconcileMissing(_ db: Database, row: Row) throws {
        let recordID: String = row["id"]
        if recordID == LibraryRecord.idText { return record(try library.reconcile(db, server: nil, seen: nil)) }
        if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [recordID])
            == true
        {
            // Resolving the review creates the record again.
            try db.execute(sql: "UPDATE conflicts SET revision=0 WHERE record=?", arguments: [recordID])
            try alignConflictRevision(db, recordID: recordID, revision: 0)
            return
        }
        let pendingBase = try Int64.fetchOne(db, sql: "SELECT base FROM outbox WHERE record=?", arguments: [recordID])
        if row["revision"] as Int64 == 0 && (pendingBase ?? 0) == 0 { return }
        try reupload(db, recordID: recordID, kind: row["kind"], payload: row["payload"], base: 0)
    }
    private func reupload(_ db: Database, recordID: String, kind: String, payload: String, base: Int64) throws {
        try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [recordID])
        try db.execute(sql: "UPDATE records SET revision=?,dirty=1 WHERE id=?", arguments: [base, recordID])
        try enqueue(db, recordID: recordID, kind: kind, payload: payload, revision: base)
    }
}

/// A synchronization waiting for another one of the same store to finish.
struct SynchronizationWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
}

// Synchronization support: the position in the server's log, exclusive passes, change tracking and queued changes
// the server can't take yet.
extension JournalStore {
    /// Where this device is in the server's log: its cursor and, when known, the change it read there.
    func syncPosition() throws -> (cursor: Int64, applied: LoggedChange?) {
        let applied = try setting("cursor-change").flatMap {
            try? JournalCoding.decoder().decode(LoggedChange.self, from: $0)
        }
        return (try cursor(), applied)
    }
    /// Moves the cursor together with the change read there, which the server
    /// confirms before reading on. When that change isn't known, none is kept for a new position.
    func moveCursor(_ db: Database, to cursor: Int64, reading change: LoggedChange?) throws {
        let position = Data(String(cursor).utf8)
        let previous = try Data.fetchOne(db, sql: "SELECT value FROM settings WHERE key='cursor'")
        try db.execute(
            sql:
                "INSERT INTO settings(key,value) VALUES ('cursor',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            arguments: [position])
        if let change {
            try db.execute(
                sql:
                    "INSERT INTO settings(key,value) VALUES ('cursor-change',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: [JournalCoding.encoder().encode(change)])
        } else if previous != position {
            try db.execute(sql: "DELETE FROM settings WHERE key='cursor-change'")
        }
    }
    /// Waits until no other synchronization of this store runs, whichever engine started it. A caller cancelled
    /// while waiting stops waiting and throws `CancellationError`, so quitting never waits on another
    /// synchronization; the gate then passes to the next waiter.
    func beginSynchronization() async throws {
        guard synchronizing else {
            synchronizing = true
            quiet.generation += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Runs on this actor before the cancellation handler's removal can, so a waiter is either never
                // queued or queued and then removed.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                synchronizationWaiters.append(SynchronizationWaiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.stopWaitingForSynchronization(id) }
        }
        // The gate may have been handed over just as the caller was cancelled: pass it on rather than start.
        if Task.isCancelled {
            endSynchronization()
            throw CancellationError()
        }
    }
    /// Releases the gate and returns the quiet mark: this release and the write count the synchronization's settled
    /// facts were read at. A synchronization handed the gate here advances the generation again, so it breaks the mark.
    @discardableResult func endSynchronization() -> QuietMark {
        quiet.generation += 1
        let mark = QuietMark(store: quiet.epoch, generation: quiet.generation, writes: quiet.factsWrites ?? -1)
        quiet.factsWrites = nil
        if synchronizationWaiters.isEmpty {
            synchronizing = false
        } else {
            quiet.generation += 1
            synchronizationWaiters.removeFirst().continuation.resume()
        }
        return mark
    }
    /// Removes a cancelled waiter. One already handed the gate isn't queued any more and passes it on itself.
    private func stopWaitingForSynchronization(_ id: UUID) {
        guard let index = synchronizationWaiters.firstIndex(where: { $0.id == id }) else { return }
        synchronizationWaiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
    /// Increases whenever a synchronized record, image or conflicting version is stored, so a view knows
    /// when it must be read again.
    public func receivedChangeCount() -> Int { receivedChanges }
    /// Whether local changes are waiting to be sent; changes waiting for a review don't count.
    public func hasPendingChanges() throws -> Bool {
        try db.read { db in
            try Bool.fetchOne(
                db,
                sql:
                    "SELECT EXISTS(SELECT 1 FROM outbox o LEFT JOIN conflicts c ON c.record=o.record WHERE c.record IS NULL AND \(Self.sendable))"
            ) == true
        }
    }
    /// The title a queued change shows, for explaining why it can't sync.
    public func title(of pending: PendingChange) throws -> String {
        try decode(pending.payload, id: pending.recordID, kind: pending.kind).displayTitle
    }
    /// Whether a queued change refers to any of these images.
    public func pendingChange(_ pending: PendingChange, refersTo images: Set<UUID>) throws -> Bool {
        let item = try decode(pending.payload, id: pending.recordID, kind: pending.kind)
        return !images.isDisjoint(with: item.document.attachmentIDs)
    }
    /// Whether a queued change is still being written: its record was saved here within `pause`, and it was queued
    /// less than `longest` ago. Changes queued before the journals were opened aren't. A save or queueing that seems
    /// to be in the future, because the clock was set back since, counts as long ago.
    func isBeingWritten(_ pending: PendingChange, at now: Date, pause: TimeInterval, longest: TimeInterval) -> Bool {
        guard let queued = unsentOperations[pending.operationId], let saved = lastSaves[pending.recordID] else {
            return false
        }
        let sinceSave = now.timeIntervalSince(saved)
        let sinceQueued = now.timeIntervalSince(queued)
        return (0..<pause).contains(sinceSave) && (0..<longest).contains(sinceQueued)
    }
    /// Takes a queued change for sending. One no synchronization took before carries the record's current content,
    /// so writing that continued after it was queued is sent as one revision, once the server has every image that
    /// content uses; until then its earlier content is sent if the server has its images, or nothing. Once taken, a
    /// change keeps its content, so sending it again is the same request. Nil when nothing is to be sent now.
    func takeForSending(_ pending: PendingChange) throws -> PendingChange? {
        let untried = unsentOperations[pending.operationId] != nil
        let taken = try db.write { db -> PendingChange? in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql:
                        "SELECT o.payload AS queued,o.base,r.payload AS current,r.revision FROM outbox o JOIN records r ON r.id=o.record WHERE o.operation=?",
                    arguments: [id(pending.operationId)])
            else { return nil }
            var taken = pending
            taken.payload = row["queued"]
            taken.baseRevision = row["base"]
            let current: String = row["current"]
            guard untried, current != taken.payload, row["revision"] as Int64 == taken.baseRevision else {
                if pending.kind == LibraryRecord.kind { try library.sending(db, payload: taken.payload) }
                return taken
            }
            if try imagesAreOnServer(db, payload: current, id: pending.recordID, kind: pending.kind) {
                try db.execute(
                    sql: "UPDATE outbox SET payload=? WHERE operation=?", arguments: [current, id(pending.operationId)])
                taken.payload = current
                if pending.kind == LibraryRecord.kind { try library.sending(db, payload: taken.payload) }
                return taken
            }
            let earlierIsComplete = try imagesAreOnServer(
                db, payload: taken.payload, id: pending.recordID, kind: pending.kind)
            return earlierIsComplete ? taken : nil
        }
        if taken != nil { unsentOperations[pending.operationId] = nil }
        return taken
    }
    /// Whether the server has every image stored on this device that a payload uses.
    private func imagesAreOnServer(_ db: Database, payload: String, id recordID: UUID, kind: String) throws -> Bool {
        let images = try decode(payload, id: recordID, kind: kind).document.attachmentIDs
        guard !images.isEmpty else { return true }
        let marks = Array(repeating: "?", count: images.count).joined(separator: ",")
        let waiting = try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM attachments WHERE uploaded<>1 AND id IN (\(marks))",
            arguments: StatementArguments(images.map { self.id($0) }))
        return waiting == 0
    }
    /// Replaces a queued change the server never applied with the record's current content, as a new operation.
    /// Returns false, keeping the queued change, when the content hasn't changed since.
    public func requeue(_ pending: PendingChange) throws -> Bool {
        try db.write { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql:
                        "SELECT o.payload AS queued,r.payload AS current,r.kind FROM outbox o JOIN records r ON r.id=o.record WHERE o.operation=?",
                    arguments: [id(pending.operationId)]),
                (row["queued"] as String) != (row["current"] as String)
            else { return false }
            try db.execute(sql: "DELETE FROM outbox WHERE operation=?", arguments: [id(pending.operationId)])
            try enqueue(
                db, recordID: id(pending.recordID), kind: row["kind"], payload: row["current"],
                revision: pending.baseRevision)
            return true
        }
    }
}
