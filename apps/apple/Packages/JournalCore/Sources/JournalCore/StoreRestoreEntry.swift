import Foundation
import GRDB

/// Where Restore put an entry.
public struct RestoredEntry: Sendable {
    /// The entry as saved.
    public let entry: JournalItem
    /// The journal it is in now.
    public let journal: JournalItem
    /// It went back to the journal it was in, rather than to the fallback.
    public let returnedToOwnJournal: Bool
}

extension JournalStore {
    /// Brings an entry back from Recently Deleted, or from Unavailable Journals when it has a deletion of its own, and
    /// decides where it goes inside one transaction (docs/design/1-1-library-simplifications.md, N):
    ///
    /// - its own journal when that journal is in use: live, readable and without a conflict;
    /// - otherwise `fallback`, when the entry's journal is deleted, was deleted permanently or is missing. That
    ///   journal must be in use too.
    ///
    /// An entry whose own journal is saved by a newer version, or has a conflict waiting for one, is not restored.
    /// Only the entry's own tombstone and legacy marker are cleared; its journal and its siblings are not touched.
    /// Pins and journal order belong to the library record by entry identity and are untouched. When neither journal
    /// can take the entry, nothing is written.
    public func restoreEntry(_ entryID: UUID, fallback fallbackID: UUID?) throws -> RestoredEntry {
        try Task.checkCancellation()
        return try db.write { db in
            guard var entry = try storedItem(db, uuid: entryID), entry.kind == "entry", !entry.isPermanentlyDeleted
            else { throw JournalError.invalidData }
            guard entry.document.isEditable, entry.preservedJSON == nil else { throw JournalError.unsupportedFormat }
            try requireNoConflict(db, uuid: entryID)
            let isDeleted = entry.deletedAt != nil || entry.deletedWithJournal
            let own = try entry.journalID.flatMap { try storedItem(db, uuid: $0) }
            switch try restoreDestination(db, own: own, entryIsDeleted: isDeleted, fallbackID: fallbackID) {
            case .own(let journal):
                guard isDeleted || entry.archivedAt != nil else {
                    return RestoredEntry(entry: entry, journal: journal, returnedToOwnJournal: true)
                }
                clearDeletion(of: &entry)
                return RestoredEntry(
                    entry: try saveCanonical(db, item: entry), journal: journal, returnedToOwnJournal: true)
            case .fallback(let journal):
                entry.journalID = journal.id
                clearDeletion(of: &entry)
                return RestoredEntry(
                    entry: try saveCanonical(db, item: entry), journal: journal, returnedToOwnJournal: false)
            }
        }
    }

    private enum RestoreDestination {
        case own(JournalItem)
        case fallback(JournalItem)
    }

    private func restoreDestination(
        _ db: Database, own: JournalItem?, entryIsDeleted: Bool, fallbackID: UUID?
    ) throws -> RestoreDestination {
        if let own, !own.isPermanentlyDeleted {
            guard own.kind == "journal" else { throw JournalLifecycleError.missingJournal }
            guard own.document.isEditable, own.preservedJSON == nil, try !hasConflictRow(db, own.id) else {
                throw JournalLifecycleError.unsupportedJournal
            }
            if own.deletedAt == nil { return .own(own) }
        } else if !entryIsDeleted {
            // Nothing of its own is deleted and its journal is gone: there is nothing to restore.
            throw JournalLifecycleError.missingJournal
        }
        guard let fallbackID, let fallback = try storedItem(db, uuid: fallbackID), fallback.kind == "journal",
            fallback.deletedAt == nil, !fallback.isPermanentlyDeleted, fallback.document.isEditable,
            fallback.preservedJSON == nil, try !hasConflictRow(db, fallback.id)
        else { throw JournalLifecycleError.destinationGone }
        return .fallback(fallback)
    }

    private func clearDeletion(of entry: inout JournalItem) {
        entry.deletedAt = nil
        entry.deletedWithJournal = false
        entry.archivedAt = nil
        entry.modifiedAt = Date()
    }

    private func hasConflictRow(_ db: Database, _ uuid: UUID) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [id(uuid)])
            == true
    }
}
