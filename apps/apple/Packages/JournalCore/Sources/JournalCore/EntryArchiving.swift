import Foundation

public enum EntryArchivingError: Error, LocalizedError, Sendable {
    case changed, unavailable

    public var errorDescription: String? {
        switch self {
        case .changed: return "This entry’s archive status changed. Review it before trying again."
        case .unavailable: return "This entry is no longer available for editing."
        }
    }
}

extension JournalStore {
    /// Patch the latest entry without replacing newer content or outstanding sync retry bytes.
    public func setEntryArchived(_ entryID: UUID, expectedArchivedAt: Date?, archived: Bool) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard var entry = try storedItem(db, uuid: entryID), entry.kind == "entry",
                !entry.isPermanentlyDeleted, entry.deletedAt == nil, !entry.deletedWithJournal,
                let parentID = entry.journalID, let parent = try storedItem(db, uuid: parentID),
                parent.kind == "journal", !parent.isPermanentlyDeleted, parent.deletedAt == nil
            else { throw EntryArchivingError.unavailable }
            guard entry.document.isEditable, parent.document.isEditable else {
                throw JournalError.unsupportedFormat
            }
            try requireNoConflict(db, uuid: entryID)
            try requireNoConflict(db, uuid: parentID)
            guard entry.archivedAt == expectedArchivedAt else { throw EntryArchivingError.changed }
            guard (entry.archivedAt != nil) != archived else { return entry }
            entry.archivedAt = archived ? Date() : nil
            entry.modifiedAt = Date()
            return try saveCanonical(db, item: entry)
        }
    }
}
