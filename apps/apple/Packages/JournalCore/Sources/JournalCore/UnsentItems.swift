import GRDB

extension JournalStore {
    /// Entries, journals and templates whose latest version is only on this device: everything waiting to be sent,
    /// including entries waiting for an image, changes waiting for a conflict to be reviewed and changes the server
    /// refused. Erasing this device's journals loses them (docs/design/erase-device-2026-10-04.md); unlike
    /// `pendingItemCount`, nothing the server hasn't accepted is left out.
    public func unsentItemCount() throws -> Int {
        try db.read { db in
            try Int.fetchOne(
                db,
                sql:
                    "SELECT COUNT(*) FROM (SELECT o.record FROM outbox o WHERE \(Self.sendable) UNION SELECT record FROM conflicts)"
            ) ?? 0
        }
    }
}
