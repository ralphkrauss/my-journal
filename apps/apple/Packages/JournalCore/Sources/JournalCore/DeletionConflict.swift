import Foundation

public enum DeletionConflictChoice: Sendable {
    case keepDeletion
    case keepEntry(journalID: UUID)
    case keepEntryAsCopy(journalID: UUID)
    case keepJournal
    case keepTemplate
}

public struct DeletionConflictConfirmation: Sendable {
    public let conflict: ConflictVersion
    public var edited: JournalItem? {
        if !conflict.local.isPermanentlyDeleted { return conflict.local }
        return conflict.remote.isPermanentlyDeleted ? nil : conflict.remote
    }
    public var deletion: JournalItem {
        conflict.local.isPermanentlyDeleted ? conflict.local : conflict.remote
    }
    let storeID: UUID
    let copyID: UUID
    let history: [DeletionHistoryState]
}
