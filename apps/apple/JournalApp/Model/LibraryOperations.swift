import Foundation
import JournalCore
import SwiftUI

/// Pinned entries and journal order (docs/design/pinned-entries.md, docs/design/journal-order.md). Both are stored in
/// the library record and arrive with each refresh (`library`).
extension AppModel {
    // MARK: Pins

    /// Lists with a Pinned section: a journal's and All Entries.
    var showsPinnedSection: Bool { !showingTrash && !showingTemplates && !showingUnavailable }
    func isPinned(_ entry: JournalItem) -> Bool { library.available && library.pinned.contains(entry.id) }
    /// An entry listed in a journal in use can be pinned and unpinned while the journals are open.
    func canPin(_ entry: JournalItem) -> Bool {
        library.available && isReady && !locked && !replacingVault && entry.kind == "entry"
            && entry.deletedAt == nil && lifecycle.location(of: entry) == .journal
    }
    /// Pins or unpins an entry: no confirmation and no message. The row moves into or out of the Pinned section with the
    /// list's usual animation, and VoiceOver says what happened, since its focus may now be on another row.
    @discardableResult func setPinned(_ pinned: Bool, entryID: UUID, undoManager: UndoManager?) async -> Bool {
        guard let store, !locked, !replacingVault else { return false }
        do {
            let arrangement = try await store.setPinned(pinned, entry: entryID)
            guard self.store === store, !locked else { return false }
            withAnimation(Self.listAnimation) { library = arrangement }
            pendingSync = true
            syncWhenWritingPauses()
            announceForAccessibility(pinned ? "Pinned" : "Unpinned")
            if let undoManager {
                registerLibraryStep(
                    LibraryUndo(name: pinned ? "Pin Entry" : "Unpin Entry"), in: undoManager
                ) { model, undoing in
                    // An entry deleted since can't be pinned or unpinned: the step does nothing, quietly.
                    guard let entry = model.items.first(where: { $0.id == entryID }), model.canPin(entry) else {
                        return false
                    }
                    return await model.setPinned(undoing ? !pinned : pinned, entryID: entryID, undoManager: nil)
                }
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            self.error = Self.libraryFailure(
                error, fallback: pinned ? "Couldn’t pin the entry." : "Couldn’t unpin the entry.")
            return false
        }
    }
    /// Registers the next Undo or Redo step of a pin or a move. The undo manager files a step registered while it
    /// undoes as the redo, so the step is registered at once and the storage work follows, one step after another
    /// (as for deletions). A step that fails leaves the rest of its steps out: they would act on another state.
    private func registerLibraryStep(
        _ step: LibraryUndo, undoing: Bool = true, in undoManager: UndoManager,
        perform: @escaping @MainActor (AppModel, Bool) async -> Bool
    ) {
        // The step keeps its target, as the undo manager doesn't.
        undoManager.registerUndo(withTarget: step) { [weak self, weak undoManager, step] _ in
            guard let self, let undoManager else { return }
            self.registerLibraryStep(step, undoing: !undoing, in: undoManager, perform: perform)
            let previous = step.operation
            step.operation = Task { @MainActor [weak self, weak undoManager] in
                await previous?.value
                guard let self else { return }
                if await !perform(self, undoing) { undoManager?.removeAllActions(withTarget: step) }
            }
        }
        undoManager.setActionName(step.name)
    }
    /// The selected entry, for File ▸ Pin Entry.
    var selectedPinnable: JournalItem? {
        guard let draft, draft.kind == "entry", canPin(draft) else { return nil }
        return draft
    }

    // MARK: Journal order

    /// Journals can be moved while the journals are open and the order isn't from a newer version.
    var canMoveJournals: Bool { library.available && isReady && !locked && !replacingVault }
    /// Moves a journal to `index` of the Journals list without it. The rank comes from the neighbours shown now.
    /// VoiceOver hears where it went; undo puts it back where it was.
    @discardableResult func moveJournal(_ id: UUID, to index: Int, undoManager: UndoManager?) async -> Bool {
        let shown = journals.map(\.id)
        guard canMoveJournals, let store, let from = shown.firstIndex(of: id) else { return false }
        var others = shown.filter { $0 != id }
        let target = min(max(index, 0), others.count)
        guard target != from else { return true }
        others.insert(id, at: target)
        // Shown at once where it was dropped; the stored order replaces it, or the previous one comes back.
        objectWillChange.send()
        lists.journalOrder = others
        defer {
            objectWillChange.send()
            lists.journalOrder = nil
        }
        do {
            let arrangement = try await store.moveJournal(id, shown: shown, to: target)
            guard self.store === store, !locked else { return false }
            library = arrangement
            pendingSync = true
            syncWhenWritingPauses()
            if let message = moveAnnouncement(id) { announceForAccessibility(message) }
            if let undoManager {
                registerLibraryStep(LibraryUndo(name: "Move Journal"), in: undoManager) { model, undoing in
                    await model.moveJournal(id, to: undoing ? from : target, undoManager: nil)
                }
            }
            return true
        } catch {
            self.error = Self.libraryFailure(error, fallback: "Couldn’t move the journal.")
            return false
        }
    }
    /// "Moved above Travel." or, for the last journal, "Moved below Travel."
    private func moveAnnouncement(_ id: UUID) -> String? {
        let order = journals
        guard let index = order.firstIndex(where: { $0.id == id }), order.count > 1 else { return nil }
        if index + 1 < order.count { return "Moved above \(JournalNames.displayName(order[index + 1].title))." }
        return "Moved below \(JournalNames.displayName(order[index - 1].title))."
    }
    /// Puts a new or restored journal at the end once journals have been arranged.
    func placeJournalAtEnd(_ id: UUID) async {
        guard let store else { return }
        try? await store.placeJournalAtEnd(id)
    }

    /// Pins and journal order were saved by a newer version, so this one can't change them.
    static let libraryNeedsUpdate = "Update My Journal to use pinned entries and journal order."

    /// What a failed pin, unpin or move tells the person: to update when the library record is from a newer version,
    /// which no retry fixes, otherwise `fallback`.
    static func libraryFailure(_ failure: Error, fallback: String) -> String {
        failure as? LibraryError == .newerVersion ? libraryNeedsUpdate : fallback
    }

    /// The Settings ▸ Sync footer about pins and journal order, when there's something to say.
    var libraryFooter: String? {
        guard connection != nil else { return nil }
        return librarySync.needsUpdate ? Self.libraryNeedsUpdate : nil
    }

    /// Moves in the lists follow Reduce Motion, as deletion does.
    static var listAnimation: Animation? {
        #if os(iOS)
            UIAccessibility.isReduceMotionEnabled ? nil : .default
        #else
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .default
        #endif
    }
}

/// The Undo and Redo steps of one pin or journal move: the step being carried out, which the next one waits for.
@MainActor final class LibraryUndo {
    let name: String
    var operation: Task<Void, Never>?
    init(name: String) { self.name = name }
}
