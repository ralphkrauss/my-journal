import Foundation
import GRDB

/// Whether a server holds this library's journals, decided after access is granted and before anything is sent
/// (docs/design/sync-health-and-recovery.md §3.3). The same library rejoins by record identity, so nothing is
/// duplicated; only a different library merges, which combines same-name journals and skips unedited built-ins.
public enum SyncLineage {
    /// Pages read at a time: small enough that records at their size limit fit one response.
    static let pageSize = 10

    /// True when the server has the identity this library last synchronized with, or any record this library
    /// synchronized before, or, for a library that synchronized before, no records at all: an empty server combines
    /// nothing, and turning on encryption on another device empties the server until that device sends its copy, which
    /// keeps the library's identities. Reads the server's changes only until it can tell.
    public static func serverHoldsLibrary(_ store: JournalStore, client: ServerClient) async throws -> Bool {
        let status = try await client.status()
        if let id = status.serverId, try await store.syncedServerID() == id { return true }
        let known = try await store.syncedRecordIDs()
        guard !known.isEmpty else { return false }
        var cursor: Int64 = 0
        while true {
            try Task.checkCancellation()
            let page = try await client.changes(after: cursor, limit: pageSize)
            if cursor == 0 && page.changes.isEmpty && !page.hasMore { return true }
            if page.changes.contains(where: { known.contains($0.recordId) }) { return true }
            guard page.hasMore, page.cursor > cursor else { return false }
            cursor = page.cursor
        }
    }
}

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
