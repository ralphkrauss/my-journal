import Foundation
import JournalCore
import os

// Changes on two devices that this version settles itself, and what the person is told afterwards
// (docs/design/1-1-conflicts-and-reconnect.md, step 1: journals and permanent deletions).

/// One row of Settings ▸ Sync ▸ Changed on Two Devices.
struct KeptNoteRow: Identifiable, Equatable {
    /// The note's own identity.
    let id: UUID
    let title: String
    let sentence: String
    let date: Date
    /// The entry or template the row opens; nil for a row that is only text.
    let opens: UUID?

    /// What VoiceOver reads for a row: the title, the sentence, then the date and time.
    var spokenLabel: String {
        [title, sentence, date.formatted(date: .abbreviated, time: .shortened)].joined(separator: ". ")
    }
}

extension AppModel {
    /// A conflict the person can still review. Journals and permanent deletions settle themselves; what a newer
    /// version must read stays out of the review too, and Settings ▸ Sync says so (`heldChangesNeedUpdate`).
    static func isReviewable(_ conflict: ConflictVersion) -> Bool {
        conflict.local.kind != "journal" && !conflict.local.isPermanentlyDeleted
            && !conflict.remote.isPermanentlyDeleted
    }

    /// Takes the conflicts a read of the library found: all of them for the lifecycle, the reviewable ones for the
    /// review, and whether any journal or deletion conflict waits for a newer version.
    func adoptConflicts(_ rows: [ConflictVersion], held: Set<UUID>) {
        conflictedIDs = Set(rows.map(\.id))
        heldConflictIDs = held
        // A journal or deletion conflict that settles at the next pull doesn't make its journal unavailable.
        settlingConflictIDs = Set(rows.filter { !Self.isReviewable($0) && !held.contains($0.id) }.map(\.id))
        let needsUpdate = rows.contains { !Self.isReviewable($0) && held.contains($0.id) }
        if heldChangesNeedUpdate != needsUpdate { heldChangesNeedUpdate = needsUpdate }
        conflicts = rows.filter(Self.isReviewable)
    }

    // MARK: The list

    /// The rows of Changed on Two Devices, newest first, written from the items as they are now. A saved entry or
    /// template that has gone leaves no row, and neither does a note from a newer version.
    var keptNoteRows: [KeptNoteRow] {
        guard !locked else { return [] }
        return keptNotes.compactMap(keptNoteRow)
    }

    private func keptNoteRow(_ note: KeptNote) -> KeptNoteRow? {
        switch note.kind {
        case .journalRenamed:
            let current = items.first { $0.id == note.recordID && $0.kind == "journal" }
            let name = JournalNames.displayName(current?.title ?? note.name)
            let other = JournalNames.displayName(note.otherName ?? "")
            return KeptNoteRow(
                id: note.id, title: name,
                sentence: "Renamed on two devices. The name is now “\(name)”; the other was “\(other)”.",
                date: note.created, opens: nil)
        case .journalDeleted:
            return KeptNoteRow(
                id: note.id, title: JournalNames.displayName(note.name),
                sentence: "Deleted permanently on one device and changed on another. It stays deleted.",
                date: note.created, opens: nil)
        case .deletedAndChanged:
            guard let parkedID = note.otherID, let parked = items.first(where: { $0.id == parkedID }) else {
                return nil
            }
            return KeptNoteRow(
                id: note.id, title: keptTitle(of: parked, fallback: note.name),
                sentence:
                    "Deleted permanently on one device and changed on another. The changed version is saved separately.",
                date: note.created, opens: parkedID)
        case .unknown:
            return nil
        }
    }

    private func keptTitle(of item: JournalItem, fallback: String) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let named = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return named.isEmpty ? item.displayTitle : named
    }

    /// Forgets every note. Nothing else changes.
    func clearKeptNotes() async {
        guard !locked, let store else { return }
        do {
            try await store.clearKeptNotes()
            try await refresh()
        } catch { report(error, .saving) }
    }

    /// Opens what a row names wherever it is, and marks the note seen. Returns whether it was opened.
    @discardableResult func openKeptNote(_ id: UUID, revealing: Bool = false) async -> Bool {
        guard !locked, !replacingVault, let store, let note = keptNotes.first(where: { $0.id == id }),
            let itemID = note.otherID
        else { return false }
        guard await showItem(itemID, revealing: revealing) else { return false }
        do {
            try await store.markKeptNoteSeen(id)
            try await refresh()
        } catch {
            Logger(subsystem: "org.privatejournal", category: "conflicts").error(
                "A kept note could not be marked seen.")
        }
        return true
    }

    // MARK: Settling

    /// Settles the conflicts left from an earlier version when a library opens. Rows made since wait for the next
    /// completed pull, unless no server is configured.
    func settleConflictsOnOpening(_ store: JournalStore, serverConfigured: Bool) async {
        // Opening writes nothing when there is nothing to settle, and never touches a library that can't be read.
        guard let waiting = try? await store.conflicts(), !waiting.isEmpty else { return }
        do {
            _ = try await store.resolveConflicts(at: .opening(serverConfigured: serverConfigured))
        } catch is CancellationError {
            return
        } catch {
            Logger(subsystem: "org.privatejournal", category: "conflicts").error("Conflicts could not be settled.")
        }
    }

    /// The open entry while its save has failed: a conflict of that record is not settled under the person.
    var conflictsToHold: Set<UUID> {
        guard saveFailure, let draft, draft.kind != "journal" else { return [] }
        return [draft.id]
    }

    /// Without a server there is no pull to settle a conflict a stale save made, so it is settled once writing
    /// pauses, the way the next synchronization sends it.
    func resolveConflictsWhenWritingPauses() {
        localResolution?.cancel()
        localResolution = nil
        guard connection == nil, let store else { return }
        localResolution = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((SyncEngine.writingPause + 0.25) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.store === store, !self.locked, !self.replacingVault else { return }
            let holding = self.conflictsToHold
            guard let report = try? await store.resolveConflicts(at: .local, holding: holding), report.changedRecords
            else { return }
            await self.followResolved(report.resolved)
        }
    }

    /// The library is read again after conflicts were settled, and the entry that is open follows the entry its
    /// edit was parked as, if its record was deleted permanently on another device.
    func followResolved(_ resolved: [ResolvedConflict]) async {
        guard !resolved.isEmpty, !locked, !replacingVault else { return }
        await followParkedEntry(resolved)
        try? await refresh()
    }

    /// The open entry meets a permanent deletion made elsewhere (docs/design/1-1-conflicts-and-reconnect.md, 3.4).
    /// Its edit was saved as a new entry in Recently Deleted. The draft moves there in memory, with the title and
    /// text it has now, so the next save writes that entry and not the record that is now a deletion, which would
    /// make a second one. A deleted entry is read-only here: it shows with the notice that says where it is. It
    /// follows only an entry that is still as the settlement saved it.
    func followParkedEntry(_ resolved: [ResolvedConflict]) async {
        guard let open = draft, open.kind != "journal" else { return }
        let parked = resolved.compactMap { settled -> UUID? in
            guard settled.recordID == open.id, case .deletedAndChanged(let id) = settled.result else { return nil }
            return id
        }.first
        guard let parkedID = parked, let store else { return }
        // A save of the draft that is still running ends first, so it is not mistaken for a newer edit.
        while let write = draftWrite { _ = await write.task.value }
        guard !locked, !replacingVault, self.store === store, let current = draft, current.id == open.id else {
            return
        }
        // The draft is written onto that entry, so it must still be exactly what the settlement saved: not edited,
        // deleted for good or changed on another device since. Otherwise the draft stays where it is.
        guard let stored = try? await store.unchangedParkedEntry(parkedID, for: open.id) else {
            report(JournalError.conflict, .saving)
            return
        }
        var target = stored
        target.title = current.title
        target.document = current.document
        showingTemplates = false
        selectedID = stored.id
        draft = stored
        // The stored entry is the base; text typed since stays unsaved until the next save writes it there.
        keepingDraftBase { draft = target }
        query = ""
        revealCollection(of: stored, keepingAllEntries: false)
        rememberSelection()
    }
}
