import Foundation
import GRDB

extension JournalStore {
    /// Records a server accepted from or sent to this library: they have a server revision.
    public func syncedRecordIDs() throws -> Set<UUID> {
        try db.read { db in
            // Every library has the library record under the same identity, so it proves nothing.
            Set(
                try String.fetchAll(db, sql: "SELECT id FROM records WHERE revision > 0 AND kind <> 'library'")
                    .compactMap(UUID.init))
        }
    }
    /// Entries, journals and templates saved here that the server hasn't accepted yet, including ones waiting for
    /// an image. Ones waiting for a review don't count, as for `hasPendingChanges`.
    public func pendingItemCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql:
                    "SELECT COUNT(*) FROM outbox o LEFT JOIN conflicts c ON c.record=o.record WHERE c.record IS NULL AND \(Self.sendable)"
            ) ?? 0
        }
    }
}
