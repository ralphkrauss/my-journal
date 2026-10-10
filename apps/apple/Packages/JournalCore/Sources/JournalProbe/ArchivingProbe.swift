import Foundation
import JournalCore

extension Probe {
    static func verifyArchiveRecovery(
        sender: JournalStore, observer: JournalStore, client: ServerClient, observerClient: ServerClient,
        entryID: UUID, journalID: UUID
    ) async throws {
        let senderSync = SyncEngine(store: sender, client: client)
        let observerSync = SyncEngine(store: observer, client: observerClient)
        let archived = try await sender.setEntryArchived(entryID, expectedArchivedAt: nil, archived: true)
        let queued = try await sender.pending()
        _ = try await sender.setEntryArchived(entryID, expectedArchivedAt: archived.archivedAt, archived: false)
        let retry = try await sender.pending()
        guard queued.map(\.operationId) == retry.map(\.operationId),
            queued.map(\.payload) == retry.map(\.payload)
        else {
            throw ProbeFailure(
                "archiving and unarchiving before a sync replaced the queued request instead of keeping it")
        }
        try await senderSync.synchronize()
        try await senderSync.synchronize()
        try await observerSync.synchronize()
        guard let unarchived = try await observer.item(entryID), unarchived.archivedAt == nil,
            unarchived.document == archived.document
        else { throw ProbeFailure("the other device did not receive the unarchived entry unchanged") }
        let finalArchive = try await sender.setEntryArchived(entryID, expectedArchivedAt: nil, archived: true)
        try await senderSync.synchronize()
        try await observerSync.synchronize()
        guard try await observer.item(entryID) == finalArchive else {
            throw ProbeFailure("the other device did not receive the final archived entry")
        }
        print("PASS: archive changes converge without replacing immutable pending requests or writing")

        let siblings = try await sender.items().filter { $0.kind == "entry" && $0.id != entryID }
        let deletion = try await sender.prepareJournalDeletion(journalID)
        _ = try await sender.deleteJournal(deletion)
        try await senderSync.synchronize()
        try await observerSync.synchronize()
        guard try await observer.item(journalID)?.deletedAt != nil else {
            throw ProbeFailure("the other device did not receive the journal deletion")
        }
        _ = try await sender.restoreJournal(journalID)
        let restored = try await sender.restoreEntry(entryID, fallback: nil).entry
        try await senderSync.synchronize()
        try await senderSync.synchronize()
        try await observerSync.synchronize()
        let observed = try await observer.items()
        let pending = try await sender.pending()
        let conflicts = try await observer.conflicts()
        // Restore puts back what is deleted: an entry that was only archived stays archived (StoreRestoreEntry.swift).
        guard try await observer.item(entryID) == restored, restored.archivedAt == finalArchive.archivedAt,
            restored.deletedAt == nil, restored.document == finalArchive.document,
            try await observer.item(journalID)?.deletedAt == nil,
            siblings.allSatisfy({ sibling in observed.contains(sibling) }), pending.isEmpty, conflicts.isEmpty
        else {
            throw ProbeFailure(
                "restoring the journal and the entry did not converge on the other device, or siblings, queued changes or conflicts differ"
            )
        }
        print("PASS: journal and entry recovery converges on another device while preserving siblings")
    }
}
