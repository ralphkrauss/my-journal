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
