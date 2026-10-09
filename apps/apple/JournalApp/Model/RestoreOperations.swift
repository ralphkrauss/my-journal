import Foundation
import JournalCore

// Restore from Recently Deleted and Unavailable Journals: one verb that acts at once, with no sheet
// (docs/design/1-1-library-simplifications.md, N).

/// What Restore offers for an entry, as the control draws it.
struct RestoreOffer: Equatable {
    enum Destination: Equatable {
        /// The journal the entry is in.
        case ownJournal
        /// The Default Journal, because the entry's own journal is deleted or gone.
        case journal(id: UUID, name: String)
    }
    let destination: Destination

    /// The control's name: where the entry goes is named when it is not its own journal.
    var title: String {
        switch destination {
        case .ownJournal: return "Restore"
        case .journal(_, let name): return "Restore to “\(name)”"
        }
    }
    /// Only a restore into the entry's own journal is offered on a full swipe, so a swipe never files an entry
    /// somewhere unexpected.
    var returnsToOwnJournal: Bool { destination == .ownJournal }
}

/// Whether, and why not, an entry in Recently Deleted or Unavailable Journals can be restored now.
enum RestoreAvailability: Equatable {
    case offer(RestoreOffer)
    /// A newer version of the app saved the entry or its journal, or a conflict waits for one.
    case needsUpdate
    /// No journal is in use to restore into.
    case createJournalFirst
    /// Nothing to restore, or the entry's own changes need review first.
    case unavailable

    var offer: RestoreOffer? {
        if case .offer(let offer) = self { return offer }
        return nil
    }
}

extension AppModel {
    func restoreAvailability(for entry: JournalItem) -> RestoreAvailability {
        guard entry.kind == "entry" else { return .unavailable }
        let location = lifecycle.location(of: entry)
        if location == .journal { return .unavailable }
        guard entry.document.isEditable, entry.preservedJSON == nil, !heldConflictIDs.contains(entry.id) else {
            return .needsUpdate
        }
        guard !conflictedIDs.contains(entry.id) else { return .unavailable }
        switch location {
        case .journal:
            return .unavailable
        case .unavailable(.unsupported):
            return .needsUpdate
        case .unavailable(.missing):
            // Nothing of its own is deleted and its journal is gone: there is nothing to restore.
            guard entry.deletedAt != nil || entry.deletedWithJournal else { return .unavailable }
            return restoreIntoDefaultJournal()
        case .recentlyDeleted:
            if journals.contains(where: { $0.id == entry.journalID }) {
                return .offer(RestoreOffer(destination: .ownJournal))
            }
            return restoreIntoDefaultJournal()
        }
    }

    private func restoreIntoDefaultJournal() -> RestoreAvailability {
        guard let journal = defaultJournal else { return .createJournalFirst }
        let name = JournalNames.displayName(journal.title)
        return .offer(RestoreOffer(destination: .journal(id: journal.id, name: name)))
    }

    /// What Restore offers for an entry or template, or nil when it offers nothing.
    func restoreOffer(for item: JournalItem) -> RestoreOffer? {
        if item.kind == "template" {
            guard item.deletedAt != nil, item.document.isEditable else { return nil }
            return RestoreOffer(destination: .ownJournal)
        }
        return restoreAvailability(for: item).offer
    }

    /// Restores a template, or an entry: into its own journal when that is in use, otherwise into the Default
    /// Journal, which the store decides again in the transaction. Returns whether it was restored; a failure is
    /// shown in the alert.
    @discardableResult func restore(_ item: JournalItem) async -> Bool {
        if item.kind == "template" {
            await restoreTemplate(item.id)
            return error == nil
        }
        guard item.kind == "entry", !locked, !replacingVault else { return false }
        guard await finishPendingSave() else {
            report(JournalError.saveRequired, .saving)
            return false
        }
        guard !locked, !replacingVault, let store else { return false }
        let fallback = namedFallback(for: item)
        do {
            var restored: RestoredEntry?
            let refreshed = try await commitMutation({ try await store.restoreEntry(item.id, fallback: fallback) }) {
                result in
                restored = result
                self.showRestoredEntry(result)
            }
            guard let restored else { return false }
            if !refreshed {
                error = "The entry was restored, but couldn’t be displayed. Reopen My Journal to try again."
            }
            if !restored.returnedToOwnJournal {
                announce("Restored to \(JournalNames.displayName(restored.journal.title)).")
            }
            return true
        } catch {
            report(error, .saving)
            return false
        }
    }

    /// The journal the control named when it was drawn, nil when it named the entry's own. The store decides again at
    /// the tap, so an own journal that went away since refuses, rather than filing the entry in the Default Journal
    /// the control did not name. Without an offer nothing is named; the store says why it can't restore.
    private func namedFallback(for item: JournalItem) -> UUID? {
        guard let offer = restoreOffer(for: item) else { return defaultJournal?.id }
        switch offer.destination {
        case .ownJournal: return nil
        case .journal(let id, _): return id
        }
    }

    private func showRestoredEntry(_ result: RestoredEntry) {
        showingAllEntries = false
        showingTrash = false
        showingTemplates = false
        showingUnavailable = false
        query = ""
        selectedJournalID = result.journal.id
        selectedID = result.entry.id
        draft = result.entry
        persistSelection(journalID: result.journal.id, entryID: result.entry.id)
    }

    /// Restore Journal on a deleted journal's page. The journal is shown once it is back; one that was restored
    /// elsewhere meanwhile is shown too, with a message.
    func restoreDeletedJournal(_ id: UUID) async {
        guard !locked, !replacingVault else { return }
        if let journal = items.first(where: { $0.id == id }), journal.kind == "journal", journal.deletedAt == nil {
            await showRestoredElsewhere(id)
            return
        }
        do {
            if !(try await restoreJournal(id)) {
                error = "The journal was restored, but couldn’t be displayed. Reopen My Journal to try again."
            }
        } catch JournalLifecycleError.alreadyRestored {
            await showRestoredElsewhere(id)
        } catch {
            report(error, .saving)
        }
    }

    private func showRestoredElsewhere(_ id: UUID) async {
        error = JournalLifecycleError.alreadyRestored.shown(.saving)
        try? await refresh()
        await switchJournal(id)
    }
}
