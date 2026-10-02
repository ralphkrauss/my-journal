import Foundation
import JournalCore

extension AppModel {
    func restore(_ item: JournalItem) async {
        if item.kind == "template" {
            await restoreTemplate(item.id)
            return
        }
        guard let journalID = item.journalID, item.kind == "entry" else { return }
        // Restoring works on the open entry; Undo and the list's Restore may name another one.
        if draft?.id != item.id { guard await selectEntryForAction(item.id) else { return } }
        do { try await moveEntry(item.id, to: journalID, restoring: true) } catch {
            self.error = error.localizedDescription
        }
    }
    /// Return to the exact current entry for a new review, without repeating a restoration mutation.
    func reviewRestoredEntry(_ entryID: UUID) async throws {
        guard !locked, !replacingVault, let originalStore = store else { throw JournalError.locked }
        let selection = selectedID
        guard await finishPendingSave() else {
            throw JournalError.server("Save your changes before reviewing this entry.")
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, let store, store === originalStore, selectedID == selection else {
            throw JournalError.locked
        }
        let settledDraft = draft
        let snapshot = try await store.viewSnapshot()
        try Task.checkCancellation()
        guard !locked, !replacingVault, self.store === store, selectedID == selection, draft == settledDraft
        else {
            throw JournalError.locked
        }
        guard let current = snapshot.items.first(where: { $0.id == entryID && $0.kind == "entry" }) else {
            throw EntryRestorationError.unavailable
        }
        items = snapshot.items
        conflicts = snapshot.conflicts
        journalHistoryIDs = snapshot.journalHistoryIDs
        pendingSync = snapshot.pending
        selectedID = current.id
        selectedJournalID = current.journalID
        draft = current
        showingTrash = false
        showingUnavailable = false
        showingTemplates = false
        query = ""
        showDraftWhereItIs()
        rememberSelection()
    }

    func prepareEntryRestoration(_ entryID: UUID, journalID: UUID) async throws -> EntryRestorationPlan {
        guard !locked, !replacingVault, let originalStore = store else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.server("Save your changes before restoring this entry.")
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, let store, store === originalStore else { throw JournalError.locked }
        let plan = try await store.prepareEntryRestoration(entryID, journalID: journalID)
        try Task.checkCancellation()
        guard !locked, !replacingVault, self.store === store else { throw JournalError.locked }
        return plan
    }

    func restoreEntryAndJournal(_ plan: EntryRestorationPlan) async throws -> Bool {
        guard !locked, !replacingVault, let originalStore = store else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.server("Save your changes before restoring this entry.")
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, let store, store === originalStore else { throw JournalError.locked }
        return try await commitEntryRestoration { try await store.restoreEntryAndJournal(plan) }
    }

    func commitEntryRestoration(_ operation: @escaping @Sendable () async throws -> JournalItem) async throws -> Bool {
        try await commitMutation(operation) { entry in
            self.showingTrash = false
            self.showingUnavailable = false
            self.showingTemplates = false
            self.query = ""
            self.selectedJournalID = entry.journalID
            self.selectedID = entry.id
            self.draft = entry
            if let journalID = entry.journalID { self.persistSelection(journalID: journalID, entryID: entry.id) }
        }
    }
}
