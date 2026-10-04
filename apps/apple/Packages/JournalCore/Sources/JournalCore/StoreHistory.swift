import Foundation
import GRDB

/// Restoring from Version History: copies of earlier versions, and a journal's earlier settings.
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
    /// Restores only the selected journal settings; membership and lifecycle are retained.
    public func restoreJournalSettings(_ version: JournalItem, expectedJournal: JournalItem) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard version.kind == "journal", expectedJournal.kind == "journal", version.id == expectedJournal.id else {
                throw JournalError.invalidData
            }
            guard !version.isPermanentlyDeleted,
                try storedItem(db, uuid: version.id)?.isPermanentlyDeleted != true
            else { throw PermanentDeletionError.permanentlyDeleted }
            guard version.document.isEditable else { throw JournalError.unsupportedFormat }
            try requireHistoricalVersion(db, version: version)
            guard var current = try storedItem(db, uuid: version.id), current.kind == "journal" else {
                throw JournalLifecycleError.missingJournal
            }
            guard current.document.isEditable else { throw JournalLifecycleError.unsupportedJournal }
            try requireNoConflict(db, uuid: current.id)
            guard current == expectedJournal else { throw HistoryRecoveryError.changedJournal }
            if JournalNames.key(current.title) != JournalNames.key(version.title), current.deletedAt == nil,
                let other = try journalNamed(db, version.title, excluding: current.id)
            {
                throw JournalNameError.taken(JournalNames.displayName(other.title))
            }
            guard current.title != version.title || current.defaultTemplateID != version.defaultTemplateID else {
                throw HistoryRecoveryError.settingsAlreadyApplied
            }
            try db.execute(
                sql: "INSERT INTO history(record,kind,payload,saved) SELECT id,kind,payload,? FROM records WHERE id=?",
                arguments: [JournalCoding.timestamp(Date()), id(current.id)])
            current.title = version.title
            current.defaultTemplateID = version.defaultTemplateID
            current.modifiedAt = Date()
            return try saveCanonical(db, item: current)
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
    public func journalHistoryIDs() throws -> Set<UUID> {
        try db.read { db in
            Set(
                try String.fetchAll(db, sql: "SELECT DISTINCT record FROM history WHERE kind='journal'").compactMap(
                    UUID.init(uuidString:)))
        }
    }
    public func history(for uuid: UUID) throws -> [JournalItem] {
        try db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT kind,payload FROM history WHERE record=? ORDER BY id DESC", arguments: [id(uuid)]
            ).map { try decode($0["payload"], id: uuid, kind: $0["kind"]) }
        }
    }
}
