import Foundation
import GRDB

/// Why a journal couldn't be merged into another (docs/design/journal-name-uniqueness.md §5).
public enum JournalMergeError: LocalizedError, Equatable, Sendable {
    /// The journal being merged is gone or in Recently Deleted.
    case sourceUnavailable
    /// The journal it would be merged into is gone or in Recently Deleted.
    case destinationUnavailable
    /// A journal or entry has a change to review.
    case conflict(UUID)
    /// A journal or entry was saved by a newer version, which this one can't change without losing content.
    case newerVersion

    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable: "This journal is no longer available."
        case .destinationUnavailable: "That journal is no longer available. Choose another journal."
        case .conflict: "These changes need review before you can continue."
        case .newerVersion: "Update My Journal to merge this journal. Some entries were saved by a newer version."
        }
    }
}

extension JournalStore {
    /// Moves every entry of `sourceID` into `destinationID`, then moves `sourceID` to Recently Deleted, in one
    /// transaction. Archived entries stay archived, and entries in Recently Deleted stay there with their deletion
    /// time and state unchanged: only the journal they belong to changes. Nothing changes when any entry or either
    /// journal has a change to review or was saved by a newer version. Returns the destination.
    public func mergeJournal(_ sourceID: UUID, into destinationID: UUID) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            guard sourceID != destinationID, var source = try storedItem(db, uuid: sourceID),
                JournalNames.isListed(source)
            else { throw JournalMergeError.sourceUnavailable }
            guard let destination = try storedItem(db, uuid: destinationID), JournalNames.isListed(destination) else {
                throw JournalMergeError.destinationUnavailable
            }
            for journal in [source, destination] {
                guard journal.document.isEditable, journal.preservedJSON == nil else {
                    throw JournalMergeError.newerVersion
                }
                try requireNoMergeConflict(db, journal.id)
            }
            let entries = try decodeRecords(
                storedRecords(db, sql: "SELECT id,kind,payload FROM records WHERE kind='entry'"), complete: true
            ).filter { $0.journalID == sourceID }
            for entry in entries {
                guard entry.document.isEditable, entry.preservedJSON == nil else {
                    throw JournalMergeError.newerVersion
                }
                try requireNoMergeConflict(db, entry.id)
            }
            let now = Date()
            for original in entries {
                try Task.checkCancellation()
                guard var entry = try storedItem(db, uuid: original.id) else { throw JournalError.invalidData }
                entry.journalID = destinationID
                entry.modifiedAt = now
                _ = try saveCanonical(db, item: entry)
            }
            source.deletedAt = now
            source.modifiedAt = now
            _ = try saveCanonical(db, item: source)
            guard let merged = try storedItem(db, uuid: destinationID) else { throw JournalError.invalidData }
            return merged
        }
    }
    private func requireNoMergeConflict(_ db: Database, _ uuid: UUID) throws {
        if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM conflicts WHERE record=?)", arguments: [id(uuid)])
            == true
        {
            throw JournalMergeError.conflict(uuid)
        }
    }
}
