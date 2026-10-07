import Foundation
import JournalCore

// Saving the open draft: each save is based on the stored version the draft came from.
extension AppModel {
    /// Shows the stored version of the open entry when it changed elsewhere and nothing here is unsaved.
    /// `base` and `writes` are from before `items` was read, so a newer save of the draft is never replaced.
    func followStoredDraft(from base: JournalItem?, writes: Int) {
        guard let draft, let base, let version = base.storedVersion, draft == base, draftWrite == nil,
            draftWrites == writes, let current = draftBase, current == base, current.storedVersion == version,
            let stored = items.first(where: { $0.id == draft.id }), stored.storedVersion != version
        else { return }
        self.draft = stored
    }

    func keepingDraftBase(_ change: () -> Void) {
        keepsDraftBase = true
        change()
        keepsDraftBase = false
    }
    /// Saves the draft, one save at a time, and makes the result the base of later edits even when the caller
    /// stops waiting, so the next save is never mistaken for a copy read before this one.
    func writeDraft(_ item: JournalItem, to store: JournalStore) async -> Error? {
        let identifier = UUID()
        draftWrites += 1
        let task = Task { () -> Error? in
            defer { if draftWrite?.id == identifier { draftWrite = nil } }
            do {
                let stored = try await store.save(item)
                if self.store === store { adoptSavedDraft(item, stored: stored) }
                return nil
            } catch {
                return error
            }
        }
        draftWrite = (identifier, task)
        return await task.value
    }
    func adoptSavedDraft(_ item: JournalItem, stored: JournalItem) {
        var saved = item
        saved.storedVersion = stored.storedVersion
        if draft?.id == item.id {
            draftBase = saved
            // Only where the draft is stored changed, which no view shows.
            lists.quietDraft = true
            keepingDraftBase { draft?.storedVersion = stored.storedVersion }
            lists.quietDraft = false
        }
        guard !locked else { return }
        replaceStoredItem(saved)
    }
}

extension AppModel {
    func saveItem(_ item: JournalItem) async {
        guard !locked, !replacingVault, let store else { return }
        var item = item
        item.modifiedAt = Date()
        do {
            let saved = try await store.save(item)
            // A later edit builds on this save even before the list is read again.
            if self.store === store, let index = items.firstIndex(where: { $0.id == saved.id }) { items[index] = saved }
            try await refresh()
        } catch { self.error = error.shown(.saving) }
    }

    /// The name of the journal that already has `name`, other than `excluding`: New Journal and Rename refuse it
    /// (docs/design/journal-name-uniqueness.md §4.1). The store checks again when saving.
    func journalNameTaken(_ name: String, excluding: UUID? = nil) -> String? {
        JournalNames.journal(named: name, in: items, excluding: excluding).map { JournalNames.displayName($0.title) }
    }
    /// A listed journal that has the name an earlier version of a journal's settings would restore (§4.3).
    func restoringNameTaken(_ comparison: JournalSettingsComparison) -> String? {
        let current = comparison.current
        guard current.deletedAt == nil,
            JournalNames.key(current.title) != JournalNames.key(comparison.historical.title)
        else { return nil }
        return journalNameTaken(comparison.historical.title, excluding: current.id)
    }
    /// The numbered name a journal in Recently Deleted comes back with when another journal has its name (§4.2).
    func restoredName(of journal: JournalItem) -> String? {
        let taken = Set(
            items.filter { JournalNames.isListed($0) && $0.id != journal.id }.map { JournalNames.key($0.title) })
        let restored = JournalNames.available(journal.title, avoiding: taken)
        return restored == journal.title ? nil : restored
    }
    func changeJournal(_ id: UUID, name: String) {
        // Surrounding spaces would make two names look alike that Move Entry tells apart.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editJournal(id) { $0.title = trimmed }
    }
    func changeJournal(_ id: UUID, template: UUID?) {
        editJournal(id) { $0.defaultTemplateID = template }
    }
    private func editJournal(_ id: UUID, update: @escaping @MainActor (inout JournalItem) -> Void) {
        guard !locked, !replacingVault, !conflicts.contains(where: { $0.id == id }) else { return }
        let prior = journalEditTask
        let session = vaultSessionID
        journalEditTask = Task {
            await prior?.value
            guard !locked, !replacingVault, vaultSessionID == session,
                !conflicts.contains(where: { $0.id == id }),
                var latest = items.first(where: { $0.id == id && $0.deletedAt == nil })
            else { return }
            update(&latest)
            await saveItem(latest)
        }
    }
}
