import Foundation
import JournalCore

extension AppModel {
    /// Moves the open entry or template to Recently Deleted and returns it so the deletion can be undone.
    /// With `selectingNext`, the entry below it (or above, at the end of the list) opens, as in Notes.
    @discardableResult func deleteSelected(selectingNext: Bool = false) async -> JournalItem? {
        let next = selectingNext ? draft.flatMap { entryAfter($0.id) } : nil
        return await deleteOpenItem(opening: next)
    }
    /// Takes an entry or template out of the lists in the same update as the swipe, menu command or key that
    /// deletes it; `deleteListed` then stores the deletion. A swipe animates its row away and expects it gone at
    /// once: a row that stayed until the deletion was stored sprang back, and a full swipe could stop the app.
    /// With `selectingNext`, deleting the open entry opens the one below it (or above, at the end of the list).
    func removeFromLists(_ id: UUID, selectingNext: Bool) -> ListedDeletion? {
        guard !locked, !replacingVault, !lists.deleting.contains(id),
            let item = items.first(where: { $0.id == id }), ["entry", "template"].contains(item.kind),
            item.deletedAt == nil
        else { return nil }
        let next = selectingNext && draft?.id == id ? entryAfter(id) : nil
        hideInLists(id)
        return ListedDeletion(id: id, next: next)
    }
    /// Moves an entry or template that `removeFromLists` took out of the lists to Recently Deleted and returns it
    /// so the deletion can be undone. Another entry that is open stays open. When the deletion fails, the row
    /// comes back.
    /// With `settle`, the library is read again only once the row's removal animation has finished.
    func deleteListed(_ deletion: ListedDeletion, settle: Duration = .zero) async -> JournalItem? {
        defer { showInLists(deletion.id) }
        if draft?.id == deletion.id { return await deleteOpenItem(opening: deletion.next, settle: settle) }
        guard !locked, !replacingVault, let store, var item = items.first(where: { $0.id == deletion.id }) else {
            return nil
        }
        item.deletedAt = Date()
        do {
            try await store.save(item)
            await waitForListRemovals(settle)
            try await refresh()
            return item
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
    /// Waits until `settle` has passed since a row last left a list. Reading the library again updates every list, and
    /// in the middle of a row's removal that interrupts its movement; after several quick deletions, this waits for
    /// the last one.
    func waitForListRemovals(_ settle: Duration) async {
        guard settle > .zero else { return }
        while let last = lists.lastRemoval, !Task.isCancelled {
            let remaining = last.advanced(by: settle) - .now
            guard remaining > .zero else { return }
            try? await Task.sleep(for: remaining)
        }
    }
    /// Stops listing a journal, entry or template while it is being deleted.
    func hideInLists(_ id: UUID) {
        objectWillChange.send()
        lists.hide(id)
    }
    func showInLists(_ id: UUID) {
        guard lists.deleting.contains(id) else { return }
        objectWillChange.send()
        lists.show(id)
    }
    func showInLists(_ ids: [UUID]) {
        guard !lists.deleting.isDisjoint(with: ids) else { return }
        objectWillChange.send()
        lists.show(ids)
    }
    private func deleteOpenItem(opening next: UUID?, settle: Duration = .zero) async -> JournalItem? {
        guard !locked, !replacingVault, await flush(), let store, var item = draft else { return nil }
        guard item.kind != "journal" else { return nil }
        item.deletedAt = Date()
        do {
            try await store.save(item)
            // The next entry replaces this one in a single update, without an empty editor between them.
            let replacement = next.flatMap { id in items.first { $0.id == id } }
            selectedID = replacement?.id
            draft = replacement
            await waitForListRemovals(settle)
            try await refresh()
            if let replacement, selectedID == replacement.id { rememberSelection() }
            return item
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
    /// The entry that opens when `id` is deleted: the one below it in the list, or above it at the end.
    private func entryAfter(_ id: UUID) -> UUID? {
        let list = entries
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1 < list.count ? list[index + 1].id : index > 0 ? list[index - 1].id : nil
    }
    /// Lets Edit ▸ Undo bring back an entry or template that `deleteSelected` moved to Recently Deleted, and Redo
    /// delete it again.
    func registerDeletionUndo(_ deleted: JournalItem, selectingNext: Bool, in undoManager: UndoManager?) {
        guard let undoManager, ["entry", "template"].contains(deleted.kind) else { return }
        registerDeletionStep(
            DeletionUndo(item: deleted, selectingNext: selectingNext), restoring: true, in: undoManager)
    }
    /// Registers the next step of an Undo and Redo cycle. The undo manager files a step registered while it undoes
    /// as the redo, so the step is registered at once and the storage work follows, one step after another.
    private func registerDeletionStep(_ deletion: DeletionUndo, restoring: Bool, in undoManager: UndoManager) {
        // The step keeps its target, as the undo manager doesn't.
        undoManager.registerUndo(withTarget: deletion) { [weak self, weak undoManager, deletion] _ in
            guard let self, let undoManager else { return }
            self.registerDeletionStep(deletion, restoring: !restoring, in: undoManager)
            let previous = deletion.operation
            deletion.operation = Task { @MainActor [weak self, weak undoManager] in
                await previous?.value
                guard let self else { return }
                let succeeded =
                    restoring ? await self.restoreDeletion(deletion.item) : await self.repeatDeletion(deletion)
                // The entry isn't where the remaining steps expect it; they would act on something else.
                if !succeeded { undoManager?.removeAllActions(withTarget: deletion) }
            }
        }
        undoManager.setActionName(deletion.item.kind == "template" ? "Delete Template" : "Delete Entry")
    }
    private func restoreDeletion(_ item: JournalItem) async -> Bool {
        await restore(item)
        return items.first { $0.id == item.id }.map { !isRecentlyDeleted($0) } ?? false
    }
    private func repeatDeletion(_ deletion: DeletionUndo) async -> Bool {
        guard await selectEntryForAction(deletion.item.id),
            let deleted = await deleteSelected(selectingNext: deletion.selectingNext)
        else { return false }
        deletion.item = deleted
        return true
    }
    /// Brings a template back from Recently Deleted and shows it in Templates, as a restored entry opens in its
    /// journal.
    func restoreTemplate(_ id: UUID) async {
        guard !locked, !replacingVault else { return }
        guard await finishPendingSave() else {
            error = "Save your changes before restoring this template."
            return
        }
        guard !locked, !replacingVault, let store else { return }
        do {
            let refreshed = try await commitMutation({ try await store.restoreTemplate(id) }) { restored in
                self.showingAllEntries = false
                self.showingTrash = false
                self.showingUnavailable = false
                self.showingTemplates = true
                self.query = ""
                self.selectedID = restored.id
                self.draft = restored
            }
            if !refreshed {
                error = "The template was restored, but couldn’t be displayed. Reopen My Journal to try again."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Duration {
    /// How long a list takes to close the gap a removed row leaves (measured on iOS 26: about 0.4 s).
    static let listRemoval = Duration.milliseconds(450)
}

/// An entry or template whose row has left the lists while it moves to Recently Deleted.
struct ListedDeletion {
    let id: UUID
    /// The entry that opens in its place, when it was open.
    let next: UUID?
}

/// What the Undo and Redo steps of one deleted entry or template share.
@MainActor final class DeletionUndo {
    var item: JournalItem
    let selectingNext: Bool
    /// The step being carried out; the next one waits for it.
    var operation: Task<Void, Never>?
    init(item: JournalItem, selectingNext: Bool) {
        self.item = item
        self.selectingNext = selectingNext
    }
}
