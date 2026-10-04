import Foundation
import GRDB

/// The synchronized state an agent's copy is made from (protocol/agent-access-server.md, Publishing).
struct AgentCopySource: Sendable {
    /// The server change this device has applied up to; the version of everything published from this state.
    let cursor: Int64
    let journals: [UUID: JournalItem]
    let entries: [JournalItem]
    /// Records with a change not yet synchronized or a conflict to review: their items are left as they are.
    let unsettled: Set<UUID>
}

extension JournalStore {
    /// Reads the applied cursor and every record in one read transaction, so the version describes exactly the state
    /// the content comes from.
    func agentCopySource() throws -> AgentCopySource {
        let (cursor, records, unsettled) = try db.read { db -> (Int64, [StoredRecord], Set<UUID>) in
            let stored = try Data.fetchOne(db, sql: "SELECT value FROM settings WHERE key='cursor'")
            let cursor = stored.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Int64.init) ?? 0
            let records = try storedRecords(
                db, sql: "SELECT id,kind,payload FROM records WHERE kind IN ('journal','entry')")
            let unsettled = try String.fetchAll(
                db,
                sql:
                    "SELECT id FROM records WHERE dirty=1 UNION SELECT record FROM outbox UNION SELECT record FROM conflicts"
            )
            return (cursor, records, Set(unsettled.compactMap(UUID.init(uuidString:))))
        }
        let items = try decodeRecords(records, complete: false)
        var journals: [UUID: JournalItem] = [:]
        var entries: [JournalItem] = []
        for item in items {
            if item.kind == "journal" {
                journals[item.id] = item
            } else {
                entries.append(item)
            }
        }
        return AgentCopySource(cursor: cursor, journals: journals, entries: entries, unsettled: unsettled)
    }
    /// Changes whenever anything publishing depends on changes, without decoding records.
    func agentCopyFingerprint() throws -> String {
        try db.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT (SELECT value FROM settings WHERE key='cursor') AS cursor,
                    (SELECT COUNT(*) FROM records WHERE kind<>'library') AS records,
                    (SELECT TOTAL(revision) FROM records WHERE kind<>'library') AS revisions,
                    (SELECT TOTAL(dirty) FROM records WHERE kind<>'library') AS dirty,
                    (SELECT COUNT(*) FROM outbox WHERE kind<>'library') AS outbox,
                    (SELECT COUNT(*) FROM conflicts WHERE record<>'\(LibraryRecord.idText)') AS conflicts
                    """)
            let cursor = (row?["cursor"] as Data?).flatMap { String(data: $0, encoding: .utf8) } ?? "0"
            let parts: [String] = [
                cursor, String(row?["records"] as Int? ?? 0), String(row?["revisions"] as Double? ?? 0),
                String(row?["dirty"] as Double? ?? 0), String(row?["outbox"] as Int? ?? 0),
                String(row?["conflicts"] as Int? ?? 0),
            ]
            return parts.joined(separator: ":")
        }
    }
}
