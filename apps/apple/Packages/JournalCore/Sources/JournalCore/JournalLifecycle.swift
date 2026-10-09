import Foundation

public enum JournalLifecycleError: Error, LocalizedError, Sendable {
    case changed, missingJournal, unsupportedJournal, alreadyDeleted, alreadyRestored, conflict(UUID), destinationGone
    public var errorDescription: String? {
        switch self {
        case .changed: return "This journal has changed. Review the entries before deleting it."
        case .missingJournal: return "This journal is unavailable."
        case .unsupportedJournal: return "Update My Journal to make changes to this journal."
        case .alreadyDeleted: return "This journal is already in Recently Deleted."
        case .alreadyRestored: return "This journal has already been restored."
        case .conflict: return "Some changes from another device will finish combining when My Journal next syncs."
        case .destinationGone: return "The journal to restore into is no longer available. Nothing was restored."
        }
    }
}

public struct JournalDeletionPlan: Sendable {
    public let journalID: UUID
    public let title: String
    public let entryIDs: Set<UUID>
}

public enum EntryLocation: Equatable, Sendable {
    case journal, recentlyDeleted
    case unavailable(UnavailableJournal)

    public var isInLiveJournal: Bool { self == .journal }
}

/// Why an entry's journal is unavailable. A journal with a conflict that waits for a newer app is unsupported: this
/// version settles every other conflict on its own.
public enum UnavailableJournal: Equatable, Sendable {
    case missing, unsupported
}

/// One consistent view of records and conflict identities, shared by all readers.
public struct JournalLifecycleSnapshot: Sendable {
    public let items: [JournalItem]
    /// Every record with a conflict. Changing a journal or its entries waits for the conflict to end.
    public let conflictedIDs: Set<UUID>
    /// The conflicted records this version settles on its own at the next pull. They keep a journal in use and don't
    /// read as waiting for a newer app (`unusableIDs`).
    public let settlingIDs: Set<UUID>
    private let parents: [UUID: JournalItem]

    public init(items: [JournalItem], conflictedIDs: Set<UUID> = [], settlingIDs: Set<UUID> = []) {
        self.items = items.filter { !$0.isPermanentlyDeleted }
        self.conflictedIDs = conflictedIDs
        self.settlingIDs = settlingIDs
        parents = Dictionary(
            self.items.filter { $0.kind == "journal" }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
    /// The conflicted records that keep a journal out of use: those holding a version this app can't read.
    private var unusableIDs: Set<UUID> { conflictedIDs.subtracting(settlingIDs) }
    public var liveJournals: [JournalItem] {
        parents.values.filter { $0.deletedAt == nil && $0.document.isEditable && !unusableIDs.contains($0.id) }
    }
    public func location(of entry: JournalItem) -> EntryLocation {
        guard entry.kind == "entry", let journalID = entry.journalID, let parent = parents[journalID] else {
            return .unavailable(.missing)
        }
        guard parent.document.isEditable, !unusableIDs.contains(parent.id) else { return .unavailable(.unsupported) }
        if parent.deletedAt != nil || entry.deletedAt != nil || entry.deletedWithJournal { return .recentlyDeleted }
        // Archiving is no longer offered; entries archived by earlier versions stay in their journal.
        return .journal
    }
    public func deletionPlan(for journalID: UUID) throws -> JournalDeletionPlan {
        guard let journal = parents[journalID] else { throw JournalLifecycleError.missingJournal }
        guard journal.document.isEditable, !conflictedIDs.contains(journalID) else {
            throw JournalLifecycleError.unsupportedJournal
        }
        guard journal.deletedAt == nil else { throw JournalLifecycleError.alreadyDeleted }
        let children = items.filter {
            $0.kind == "entry" && $0.journalID == journalID && $0.deletedAt == nil && !$0.deletedWithJournal
        }
        if let conflict = Set(children.map(\.id)).intersection(conflictedIDs).sorted(by: {
            $0.uuidString < $1.uuidString
        })
        .first {
            throw JournalLifecycleError.conflict(conflict)
        }
        return JournalDeletionPlan(journalID: journalID, title: journal.title, entryIDs: Set(children.map(\.id)))
    }
}

public struct JournalViewSnapshot: Sendable {
    public let items: [JournalItem]
    /// The records that have a conflict. Their versions are not read, so one that can't be opened doesn't fail a read.
    public let conflictedIDs: Set<UUID>
    public let pending: Bool
    /// Pins and journal ranks.
    public let library: LibraryArrangement
}
