import Foundation
import GRDB

extension JournalStore {
    public func preparePermanentDeletion(_ recordID: UUID) throws -> PermanentDeletionConfirmation {
        try Task.checkCancellation()
        return try db.read { db in
            let plan = try PermanentDeletionPlan.prepare(recordID: recordID, snapshot: lifecycleSnapshot(db))
            return try deletionConfirmation(db, plan: plan)
        }
    }
    private func deletionConfirmation(_ db: Database, plan: PermanentDeletionPlan) throws
        -> PermanentDeletionConfirmation
    {
        let history = try deletionHistory(db, records: plan.records.map(\.id))
        var historicalOnlyIDs = Set<UUID>()
        if plan.kind == "journal" {
            let rows = try Row.fetchCursor(
                db,
                sql: """
                    SELECT h.record,h.kind,h.payload FROM history h
                    WHERE h.kind='entry' AND NOT EXISTS(SELECT 1 FROM records r WHERE r.id=h.record)
                    """)
            while let row = try rows.next() {
                try Task.checkCancellation()
                guard let identifier = UUID(uuidString: row["record"]) else { throw JournalError.invalidData }
                let version = try decode(row["payload"], id: identifier, kind: row["kind"])
                if version.journalID == plan.recordID { historicalOnlyIDs.insert(identifier) }
            }
        }
        return PermanentDeletionConfirmation(
            plan: plan, storeID: deletionScopeID, history: history, historicalOnlyIDs: historicalOnlyIDs)
    }
    /// Revalidate and commit all markers/history removals atomically. Existing retries remain immutable.
    @discardableResult public func permanentlyDelete(_ confirmation: PermanentDeletionConfirmation) throws
        -> JournalItem
    {
        try Task.checkCancellation()
        guard confirmation.storeID == deletionScopeID else { throw PermanentDeletionError.changed }
        return try db.write { db in
            try confirmation.plan.validate(snapshot: lifecycleSnapshot(db))
            let current = try deletionConfirmation(db, plan: confirmation.plan)
            guard current.history == confirmation.history,
                current.historicalOnlyIDs == confirmation.historicalOnlyIDs
            else { throw PermanentDeletionError.changed }
            let now = Date()
            for record in confirmation.plan.records {
                try Task.checkCancellation()
                let marker = JournalItem.permanentDeletionMarker(for: record, at: now)
                let payload = try encode(marker)
                let recordID = id(record.id)
                guard
                    let revision = try Int64.fetchOne(
                        db, sql: "SELECT revision FROM records WHERE id=?", arguments: [recordID])
                else { throw PermanentDeletionError.missing }
                try db.execute(sql: "UPDATE records SET payload=?,dirty=1 WHERE id=?", arguments: [payload, recordID])
                try db.execute(sql: "DELETE FROM history WHERE record=?", arguments: [recordID])
                try enqueue(db, recordID: recordID, kind: record.kind, payload: payload, revision: revision)
            }
            try Task.checkCancellation()
            guard let marker = try storedItem(db, uuid: confirmation.plan.recordID) else {
                throw JournalError.invalidData
            }
            return marker
        }
    }

    public func prepareDeletionConflict(_ recordID: UUID) throws -> DeletionConflictConfirmation {
        try Task.checkCancellation()
        return try db.read { db in
            DeletionConflictConfirmation(
                conflict: try deletionConflict(db, recordID: recordID), storeID: deletionScopeID, copyID: UUID(),
                history: try deletionHistory(db, records: [recordID]))
        }
    }
    private func deletionConflict(_ db: Database, recordID: UUID) throws -> ConflictVersion {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT c.*,r.payload AS local,r.kind,r.revision AS localRevision
                    FROM conflicts c JOIN records r ON r.id=c.record WHERE c.record=?
                    """, arguments: [id(recordID)]),
            let deviceID = UUID(uuidString: row["device"]),
            let modifiedAt = try? JournalCoding.date(from: row["modified"] as String),
            (row["localRevision"] as Int64) <= (row["revision"] as Int64)
        else { throw PermanentDeletionError.changed }
        let local = try decode(row["local"], id: recordID, kind: row["kind"])
        let remote = try decode(row["payload"], id: recordID, kind: row["kind"])
        guard ["entry", "journal", "template"].contains(local.kind), local.document.isEditable,
            remote.document.isEditable,
            local.preservedJSON == nil, remote.preservedJSON == nil
        else { throw PermanentDeletionError.unsupported }
        guard local.isCanonicalDeletionMarker || remote.isCanonicalDeletionMarker else {
            throw PermanentDeletionError.changed
        }
        return ConflictVersion(
            id: recordID, local: local, remote: remote, remoteRevision: row["revision"],
            deviceID: deviceID, modifiedAt: modifiedAt)
    }
    /// Only explicit deletion review may revive a marked identity or discard the competing edited version.
    @discardableResult public func resolveDeletionConflict(
        _ confirmation: DeletionConflictConfirmation, choice: DeletionConflictChoice
    ) throws -> JournalItem {
        try Task.checkCancellation()
        guard confirmation.storeID == deletionScopeID else { throw PermanentDeletionError.changed }
        return try db.write { db in
            let reviewed = confirmation.conflict
            guard try deletionConflict(db, recordID: reviewed.id) == reviewed,
                try deletionHistory(db, records: [reviewed.id]) == confirmation.history
            else { throw PermanentDeletionError.changed }
            let selected = try deletionResolution(db, confirmation: confirmation, choice: choice)
            let original = selected.id == reviewed.id ? selected : confirmation.deletion
            let payload = try encode(original)
            let recordID = id(reviewed.id)
            // Retire the superseded request; never reuse its identity with different bytes.
            try db.execute(sql: "DELETE FROM outbox WHERE record=?", arguments: [recordID])
            if let other = try String.fetchOne(
                db, sql: "SELECT payload FROM conflicts WHERE record=?", arguments: [recordID])
            {
                try rememberServerVersion(
                    db, recordID: recordID, revision: reviewed.remoteRevision, payload: other, unlessKnown: true)
            }
            try db.execute(sql: "DELETE FROM conflicts WHERE record=?", arguments: [recordID])
            if case .keepDeletion = choice {
                try db.execute(sql: "DELETE FROM history WHERE record=?", arguments: [recordID])
            }
            try db.execute(
                sql: "UPDATE records SET payload=?,revision=?,dirty=1 WHERE id=?",
                arguments: [payload, reviewed.remoteRevision, recordID])
            try enqueue(
                db, recordID: recordID, kind: original.kind, payload: payload, revision: reviewed.remoteRevision)
            if selected.id != reviewed.id {
                let copyPayload = try encode(selected)
                try db.execute(
                    sql: "INSERT INTO records(id,kind,payload) VALUES (?,?,?)",
                    arguments: [id(selected.id), selected.kind, copyPayload])
                try enqueue(db, recordID: id(selected.id), kind: selected.kind, payload: copyPayload, revision: 0)
            }
            try Task.checkCancellation()
            guard let result = try storedItem(db, uuid: selected.id) else { throw JournalError.invalidData }
            return result
        }
    }
    private func deletionResolution(
        _ db: Database, confirmation: DeletionConflictConfirmation, choice: DeletionConflictChoice
    ) throws -> JournalItem {
        if case .keepDeletion = choice { return confirmation.deletion }
        guard var edited = confirmation.edited else { throw PermanentDeletionError.changed }
        switch choice {
        case .keepDeletion: return confirmation.deletion
        case .keepEntry(let journalID), .keepEntryAsCopy(let journalID):
            guard edited.kind == "entry", let parent = try storedItem(db, uuid: journalID),
                parent.kind == "journal", parent.deletedAt == nil, !parent.isPermanentlyDeleted,
                parent.document.isEditable, parent.preservedJSON == nil
            else { throw HistoryRecoveryError.destinationUnavailable }
            try requireNoConflict(db, uuid: journalID)
            edited.journalID = journalID
            if case .keepEntryAsCopy = choice { edited.id = confirmation.copyID }
        case .keepJournal:
            guard edited.kind == "journal" else { throw PermanentDeletionError.unsupported }
            edited.title = try availableTitle(db, for: edited)
        case .keepTemplate:
            guard edited.kind == "template" else { throw PermanentDeletionError.unsupported }
        }
        edited.restoredFromDeletionID =
            edited.id == confirmation.conflict.id ? confirmation.deletion.permanentDeletionID : nil
        edited.permanentDeletionID = nil
        edited.permanentlyDeletedAt = nil
        edited.deletedAt = nil
        edited.deletedWithJournal = false
        edited.archivedAt = nil
        edited.modifiedAt = Date()
        return edited
    }
    private func deletionHistory(_ db: Database, records: [UUID]) throws -> [DeletionHistoryState] {
        var history: [DeletionHistoryState] = []
        for record in records {
            try Task.checkCancellation()
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id,record,kind,payload FROM history WHERE record=? ORDER BY id", arguments: [id(record)])
            for row in rows {
                history.append(
                    DeletionHistoryState(
                        rowID: row["id"], recordID: row["record"], kind: row["kind"], payload: row["payload"]))
            }
        }
        return history
    }
}
