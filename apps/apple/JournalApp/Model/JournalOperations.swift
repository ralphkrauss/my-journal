import Foundation
import JournalCore

extension AppModel {
    func moveEntry(_ entryID: UUID, to journalID: UUID) async throws {
        guard !locked, !replacingVault, draft?.id == entryID else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, draft?.id == entryID, let store else { throw JournalError.locked }
        try await commitEntryMove { try await store.moveEntry(entryID, to: journalID) }
    }
    func commitEntryMove(_ operation: @escaping @Sendable () async throws -> JournalItem) async throws {
        let refreshed = try await commitMutation(operation) { moved in
            self.showingTrash = false
            self.showingTemplates = false
            self.showingUnavailable = false
            self.query = ""
            self.selectedJournalID = moved.journalID
            self.selectedID = moved.id
            self.draft = moved
            if let journalID = moved.journalID { self.persistSelection(journalID: journalID, entryID: moved.id) }
        }
        if !refreshed { error = "The entry was moved, but couldn’t be displayed. Reopen My Journal to try again." }
    }
    func commitJournalResolution(_ operation: @escaping @Sendable () async throws -> JournalItem) async throws -> Bool {
        try await commitMutation(operation) { resolved in
            if self.draft?.id == resolved.id { self.draft = resolved }
            if resolved.deletedAt != nil {
                if self.draft?.journalID == resolved.id || self.draft?.id == resolved.id {
                    self.draft = nil
                    self.selectedID = nil
                }
                if self.selectedJournalID == resolved.id { self.selectedJournalID = nil }
            }
        }
    }
    func prepareJournalDeletion(_ id: UUID) async throws -> JournalDeletionPlan {
        guard !locked, !replacingVault else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        guard let store else { throw JournalError.locked }
        guard !locked, !replacingVault else { throw JournalError.locked }
        return try await store.prepareJournalDeletion(id)
    }
    func deleteJournal(_ plan: JournalDeletionPlan) async throws -> Bool {
        guard !locked, !replacingVault else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        guard !locked, !replacingVault, let store else { throw JournalError.locked }
        return try await commitJournalResolution { try await store.deleteJournal(plan) }
    }
    func restoreJournal(_ id: UUID, expectedTitle: String? = nil) async throws -> Bool {
        guard !locked, !replacingVault else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        guard !locked, !replacingVault, let store else { throw JournalError.locked }
        return try await commitMutation({
            let journal = try await store.restoreJournal(id, expectedTitle: expectedTitle)
            // Back where it was, or at the end once journals were arranged (journal-order.md).
            try? await store.placeJournalAtEnd(journal.id)
            return journal
        }) {
            journal in
            self.selectedJournalID = journal.id
            self.selectedID = nil
            self.draft = nil
            self.showingTrash = false
            self.showingTemplates = false
            self.showingUnavailable = false
            self.query = ""
            self.persistSelection(journalID: journal.id, entryID: nil)
        }
    }
    /// Creates a journal and opens it; in the Journals list's edit mode, it's only added, and editing continues.
    func createJournal(_ name: String) async {
        endEntryCreation()
        guard !locked, !replacingVault, await flush(), let store else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let journal = JournalItem(kind: "journal", title: trimmed)
            try await store.save(journal)
            await placeJournalAtEnd(journal.id)
            try await refresh()
            if !editingJournals { await switchJournal(journal.id) }
        } catch { self.error = error.shown(.saving) }
    }
    func createRecoveryJournal(_ name: String, entryID: UUID?) async throws -> Bool {
        guard !locked, !replacingVault, entryID == nil || draft?.id == entryID else { throw JournalError.locked }
        guard await finishPendingSave() else { throw JournalError.saveRequired }
        guard !locked, !replacingVault, entryID == nil || draft?.id == entryID, let store else {
            throw JournalError.locked
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JournalError.invalidData }
        let journal = JournalItem(kind: "journal", title: trimmed)
        let refreshed = try await commitMutation({
            try await store.save(journal)
            try? await store.placeJournalAtEnd(journal.id)
            return journal
        }) { _ in }
        return refreshed
    }
}
