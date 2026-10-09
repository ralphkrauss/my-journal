import Foundation
import GRDB

/// Restoring from Version History: copies of earlier versions.
extension JournalStore {
    /// Copies an authenticated historical record without changing its source or resolving its conflicts.
    public func restoreHistoryCopy(_ version: JournalItem, to journalID: UUID? = nil) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard version.kind == "entry" || version.kind == "template" else { throw JournalError.invalidData }
            guard !version.isPermanentlyDeleted,
                try storedItem(db, uuid: version.id)?.isPermanentlyDeleted != true
            else { throw PermanentDeletionError.permanentlyDeleted }
            guard version.document.isEditable else { throw JournalError.unsupportedFormat }
            try requireHistoricalVersion(db, version: version)
            if version.kind == "entry" {
                guard let journalID, let parent = try storedItem(db, uuid: journalID),
                    parent.kind == "journal", parent.deletedAt == nil, parent.document.isEditable
                else { throw HistoryRecoveryError.destinationUnavailable }
                try requireNoConflict(db, uuid: journalID)
            } else if journalID != nil {
                throw JournalError.invalidData
            }
            var copy = version
            copy.id = UUID()
            copy.restoredFromDeletionID = nil
            copy.journalID = journalID
            copy.deletedAt = nil
            copy.deletedWithJournal = false
            copy.archivedAt = nil
            copy.modifiedAt = Date()
            return try saveCanonical(db, item: copy)
        }
    }
    func requireHistoricalVersion(_ db: Database, version: JournalItem) throws {
        let rows = try Row.fetchCursor(
            db, sql: "SELECT kind,payload FROM history WHERE record=? ORDER BY id DESC", arguments: [id(version.id)])
        while let row = try rows.next() {
            if try decode(row["payload"], id: version.id, kind: row["kind"]) == version { return }
        }
        throw HistoryRecoveryError.unavailableVersion
    }
    public func history(for uuid: UUID) throws -> [JournalItem] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT kind,payload FROM history WHERE record=? ORDER BY id DESC", arguments: [id(uuid)]
            ).map { try decode($0["payload"], id: uuid, kind: $0["kind"]) }
        }
    }
}
