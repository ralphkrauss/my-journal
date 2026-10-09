import Foundation
import JournalCore

extension AppModel {
    /// Whether a row can be deleted: its context menu and its swipe ask the same. A template has no journal; an
    /// entry needs one in use, since deleting one in an unavailable journal would change something nobody sees.
    func offersDelete(_ entry: JournalItem) -> Bool {
        entry.document.isEditable && entry.deletedAt == nil
            && (entry.kind == "template" || lifecycle.location(of: entry).isInLiveJournal)
    }
    /// Context actions capture a row, never whatever selection happens to exist later.
    func selectEntryForAction(_ id: UUID) async -> Bool {
        guard !locked, !replacingVault else { return false }
        let previousID = selectedID
        guard await finishPendingSave(), !Task.isCancelled, !locked, !replacingVault,
            selectedID == previousID, let item = items.first(where: { $0.id == id })
        else { return false }
        selectedID = id
        draft = item
        rememberSelection()
        return true
    }
    func changeEntryDate(_ entryID: UUID, expectedDate: Date, to date: Date) async throws {
        guard !locked, !replacingVault, draft?.id == entryID, canEdit else { throw EntryDateError.unavailable }
        guard await entryAutosaveSettled() else { throw JournalError.saveRequired }
        try Task.checkCancellation()
        guard !locked, !replacingVault, draft?.id == entryID, let store else { throw EntryDateError.unavailable }
        let refreshed = try await commitMutation({
            try await store.changeEntryDate(entryID, expectedDate: expectedDate, to: date)
        }) { saved in
            self.draft = saved
            self.selectedID = saved.id
        }
        if !refreshed { error = "The date was saved. Reopen My Journal to refresh your entries." }
    }
}
