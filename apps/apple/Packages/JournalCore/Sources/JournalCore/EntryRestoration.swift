import Foundation
import GRDB

public enum EntryRestorationError: Error, LocalizedError, Sendable {
    case changed, unavailable, alreadyRestored

    public var errorDescription: String? {
        switch self {
        case .changed: return "This entry or journal has changed. Review it again before restoring."
        case .unavailable: return "This entry or journal is no longer available for restoration."
        case .alreadyRestored: return "This journal has already been restored. Review the entry before continuing."
        }
    }
}

/// Immutable, store-bound review of an entry and the parent restoration it requires.
public struct EntryRestorationPlan: Sendable {
    public let entry: JournalItem
    public let journal: JournalItem
    public let entryCount: Int
    public var legacyEntryCount: Int {
        children.filter { $0.id != entry.id && $0.deletedWithJournal }.count
    }
    let storeID: UUID
    let children: [EntryRestorationState]

    func matches(_ other: Self) -> Bool {
        storeID == other.storeID && children == other.children
            && entry.id == other.entry.id && entry.journalID == other.entry.journalID
            && entry.title == other.entry.title && entry.date == other.entry.date
            && entry.displayTitle == other.entry.displayTitle
            && journal.id == other.journal.id && journal.title == other.journal.title
            && journal.deletedAt == other.journal.deletedAt
    }
}

struct EntryRestorationState: Equatable, Sendable {
    let id: UUID
    let deletedAt: Date?
    let deletedWithJournal: Bool
    let archivedAt: Date?

    init(_ item: JournalItem) {
        id = item.id
        deletedAt = item.deletedAt
        deletedWithJournal = item.deletedWithJournal
        archivedAt = item.archivedAt
    }
}

extension JournalStore {
    public func prepareEntryRestoration(_ entryID: UUID, journalID: UUID) throws -> EntryRestorationPlan {
        try Task.checkCancellation()
        return try db.read { try entryRestorationPlan($0, entryID: entryID, journalID: journalID) }
    }

    /// Restore the parent and selected entry together; siblings and unrelated current content are retained.
    public func restoreEntryAndJournal(_ plan: EntryRestorationPlan) throws -> JournalItem {
        try Task.checkCancellation()
        return try db.write { db in
            let current = try entryRestorationPlan(db, entryID: plan.entry.id, journalID: plan.journal.id)
            guard plan.matches(current) else { throw EntryRestorationError.changed }
            var journal = current.journal
            journal.deletedAt = nil
            journal.title = try availableTitle(db, for: journal)
            journal.modifiedAt = Date()
            _ = try saveCanonical(db, item: journal)
            try Task.checkCancellation()
            var entry = current.entry
            entry.deletedAt = nil
            entry.deletedWithJournal = false
            entry.archivedAt = nil
            entry.modifiedAt = Date()
            return try saveCanonical(db, item: entry)
        }
    }

    private func entryRestorationPlan(_ db: Database, entryID: UUID, journalID: UUID) throws -> EntryRestorationPlan {
        let snapshot = try lifecycleSnapshot(db)
        guard let entry = snapshot.items.first(where: { $0.id == entryID && $0.kind == "entry" }),
            let journal = snapshot.items.first(where: { $0.id == journalID && $0.kind == "journal" })
        else { throw EntryRestorationError.unavailable }
        guard entry.journalID == journalID else { throw EntryRestorationError.changed }
        guard entry.document.isEditable, journal.document.isEditable else { throw JournalError.unsupportedFormat }
        try requireNoConflict(db, uuid: entryID)
        try requireNoConflict(db, uuid: journalID)
        guard journal.deletedAt != nil else { throw EntryRestorationError.alreadyRestored }
        let children = snapshot.items.filter { $0.kind == "entry" && $0.journalID == journalID }
        let count = children.filter { $0.id == entryID || ($0.deletedAt == nil && !$0.deletedWithJournal) }.count
        return EntryRestorationPlan(
            entry: entry, journal: journal, entryCount: count, storeID: entryRestorationScopeID,
            children: children.sorted { $0.id.uuidString < $1.id.uuidString }.map(EntryRestorationState.init))
    }
}
