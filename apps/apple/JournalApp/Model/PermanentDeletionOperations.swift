import Foundation
import JournalCore

extension AppModel {
    func preparePermanentDeletion(_ id: UUID) async throws -> PermanentDeletionConfirmation {
        let store = try await deletionStoreAfterSaving()
        let confirmation = try await store.preparePermanentDeletion(id)
        try Task.checkCancellation()
        guard !locked, !replacingVault, self.store === store else { throw JournalError.locked }
        return confirmation
    }
    func permanentlyDelete(_ confirmation: PermanentDeletionConfirmation) async throws -> Bool {
        let store = try await deletionStoreAfterSaving()
        return try await commitDeletionMutation { try await store.permanentlyDelete(confirmation) }
    }
    /// Takes the item's row out of the lists in the same update as Delete in the confirmation, so it leaves as a
    /// deleted entry's row does, rather than staying until the deletion is stored and the library read again.
    func removePermanentlyDeletedFromLists(_ confirmation: PermanentDeletionConfirmation) {
        hideInLists(confirmation.plan.recordID)
    }
    /// Permanently deletes an item that `removePermanentlyDeletedFromLists` took out of the lists. When the deletion
    /// isn't stored, the row comes back.
    func permanentlyDeleteListed(_ confirmation: PermanentDeletionConfirmation) async throws -> Bool {
        defer { showInLists(confirmation.plan.recordID) }
        return try await permanentlyDelete(confirmation)
    }
    func prepareDeletionConflict(_ id: UUID) async throws -> DeletionConflictConfirmation {
        let store = try await deletionStoreAfterSaving()
        let confirmation = try await store.prepareDeletionConflict(id)
        try Task.checkCancellation()
        guard !locked, !replacingVault, self.store === store else { throw JournalError.locked }
        return confirmation
    }
    func resolveDeletionConflict(
        _ confirmation: DeletionConflictConfirmation, choice: DeletionConflictChoice
    ) async throws -> Bool {
        let store = try await deletionStoreAfterSaving()
        return try await commitDeletionMutation {
            try await store.resolveDeletionConflict(confirmation, choice: choice)
        }
    }
    private func deletionStoreAfterSaving() async throws -> JournalStore {
        guard !locked, !replacingVault else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.server("Save your entry before reviewing these changes.")
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, let store else { throw JournalError.locked }
        return store
    }
    /// Reconcile durable results even if lock cancels the caller after the transaction commits.
    func commitDeletionMutation(_ operation: @escaping @Sendable () async throws -> JournalItem) async throws -> Bool {
        try await commitMutation(operation) { saved in
            if saved.isPermanentlyDeleted {
                if self.draft?.id == saved.id || (saved.kind == "journal" && self.draft?.journalID == saved.id) {
                    self.draft = nil
                    self.selectedID = nil
                }
                if self.selectedJournalID == saved.id { self.selectedJournalID = nil }
            } else if saved.kind == "entry" {
                self.showingTrash = false
                self.showingTemplates = false
                self.showingUnavailable = false
                self.query = ""
                self.selectedJournalID = saved.journalID
                self.selectedID = saved.id
                self.draft = saved
                if let journalID = saved.journalID {
                    self.persistSelection(journalID: journalID, entryID: saved.id)
                }
            } else if saved.kind == "template" {
                // A kept template stays open in Templates, as a restored one does.
                self.showingAllEntries = false
                self.showingTrash = false
                self.showingUnavailable = false
                self.showingTemplates = true
                self.query = ""
                self.selectedID = saved.id
                self.draft = saved
            } else {
                self.selectedJournalID = saved.id
                self.selectedID = nil
                self.draft = nil
                self.showingTrash = false
                self.showingTemplates = false
                self.showingUnavailable = false
                self.query = ""
                self.persistSelection(journalID: saved.id, entryID: nil)
            }
        }
    }
}
