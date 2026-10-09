import JournalCore
import XCTest

@testable import Journal

/// Changes on two devices that this version settles itself, and what it tells the person afterwards
/// (docs/design/1-1-conflicts-and-reconnect.md). The other device's versions arrive as sync delivers them.
@MainActor
final class ConflictNotesTests: XCTestCase {
    // MARK: The open entry meets a permanent deletion

    /// The edit is saved as one entry in Recently Deleted and the open draft moves there with its text, so the next
    /// save writes that entry and does not meet the deletion again.
    func testTheOpenEntryFollowsItsEditToTheSavedEntryOnce() async throws {
        let library = try await startedLibrary()
        let (model, store) = (library.model, library.store)
        let entry = try await library.entryDeletedPermanentlyElsewhere(title: "Plans", text: "Edited here")
        try await model.refresh()
        model.selectedID = entry.id
        model.draft = model.items.first { $0.id == entry.id }
        // Writing that hasn't been saved yet when the settlement arrives.
        model.keepingDraftBase { model.draft?.title = "Plans, typed since" }

        let settled = try await store.resolveConflicts(at: .local)
        guard case .deletedAndChanged(let parkedID?) = settled.resolved.first?.result else {
            return XCTFail("The edit is saved separately")
        }
        await model.followResolved(settled.resolved)

        XCTAssertEqual(model.draft?.id, parkedID)
        XCTAssertEqual(model.selectedID, parkedID)
        XCTAssertEqual(model.draft?.title, "Plans, typed since", "Nothing typed is lost")
        XCTAssertEqual(model.draft?.document.text, "Edited here")
        XCTAssertNotNil(model.draft?.deletedAt, "It is in Recently Deleted, where deleted entries are read-only")
        XCTAssertFalse(model.canEdit)
        XCTAssertTrue(model.showingTrash, "It is shown where it is now")

        let saved = await model.flush()
        XCTAssertTrue(saved)
        let again = try await store.resolveConflicts(at: .local)
        XCTAssertTrue(again.resolved.isEmpty, "The save did not meet the deletion again")
        let rows = try await store.conflicts()
        XCTAssertTrue(rows.isEmpty)
        let entries = try await store.items().filter { $0.kind == "entry" && !$0.isPermanentlyDeleted }
        XCTAssertEqual(entries.map(\.id), [parkedID], "One saved entry, no second one")
        XCTAssertEqual(entries.first?.title, "Plans, typed since")
    }

    /// The draft is written onto the saved entry, so the entry must still be what the settlement saved. Edited in
    /// another window, or deleted for good, it is left alone and the draft stays where it is, with a message.
    func testTheOpenEntryDoesNotFollowASavedEntryThatChangedOrWasDeletedMeanwhile() async throws {
        for change in ["edited", "deleted for good"] {
            let library = try await startedLibrary()
            let (model, store) = (library.model, library.store)
            let entry = try await library.entryDeletedPermanentlyElsewhere(title: "Plans", text: "Edited here")
            try await model.refresh()
            model.selectedID = entry.id
            model.draft = model.items.first { $0.id == entry.id }
            // Writing that isn't saved yet keeps the entry open until it is.
            model.keepingDraftBase { model.draft?.title = "Plans, typed since" }
            let settled = try await store.resolveConflicts(at: .local)
            guard case .deletedAndChanged(let parkedID?) = settled.resolved.first?.result else {
                return XCTFail("The edit is saved separately")
            }
            if change == "edited" {
                let current = try await store.item(parkedID)
                var edited = try XCTUnwrap(current)
                edited.document = .plain("Changed in another window")
                try await store.save(edited)
            } else {
                _ = try await store.permanentlyDelete(try await store.preparePermanentDeletion(parkedID))
            }

            await model.followResolved(settled.resolved)

            XCTAssertEqual(model.draft?.id, entry.id, "\(change): the draft stays")
            XCTAssertEqual(model.draft?.title, "Plans, typed since", change)
            XCTAssertEqual(model.selectedID, entry.id, change)
            XCTAssertEqual(model.error, JournalError.conflict.errorDescription, change)
            let stored = try await store.item(parkedID)
            if change == "edited" {
                XCTAssertEqual(stored?.document.text, "Changed in another window", "Nothing is written onto it")
            } else {
                XCTAssertEqual(stored?.isPermanentlyDeleted, true, change)
            }
        }
    }

    // MARK: Changed on Two Devices

    func testKeptNotesShowTheFourKindsAndOpeningMarksTheNoteSeen() async throws {
        let library = try await startedLibrary()
        let (model, store) = (library.model, library.store)
        let entry = try await library.entryDeletedPermanentlyElsewhere(title: "Plans", text: "Edited here")
        try await library.journalRenamedOnTwoDevices(from: "Travel", here: "Trips", there: "Journeys")
        try await library.journalChangedAgainstPermanentDeletion(title: "Old", editedTo: "Old, renamed")
        try await library.entryEditedOnTwoDevices(title: "Notes")
        let settled = try await store.resolveConflicts(at: .local)
        XCTAssertEqual(settled.resolved.count, 4)
        try await model.refresh()
        XCTAssertTrue(model.conflictedIDs.isEmpty, "Nothing waits for the person")

        let rows = model.keptNoteRows
        XCTAssertEqual(rows.count, 4)
        let both = try XCTUnwrap(rows.first { $0.title == "Notes (other version)" })
        XCTAssertEqual(both.sentence, "Changed on two devices. Both versions are kept.")
        XCTAssertNotNil(both.opens, "The row opens the other version")
        XCTAssertTrue(both.spokenLabel.hasPrefix("Notes (other version). Changed on two devices."), both.spokenLabel)
        let renamed = try XCTUnwrap(rows.first { $0.title == "Trips" })
        XCTAssertEqual(
            renamed.sentence, "Renamed on two devices. The name is now “Trips”; the other was “Journeys”.")
        XCTAssertNil(renamed.opens, "A journal rename is only text")
        let deleted = try XCTUnwrap(rows.first { $0.title == "Old, renamed" })
        XCTAssertEqual(
            deleted.sentence, "Deleted permanently on one device and changed on another. It stays deleted.")
        XCTAssertNil(deleted.opens)
        let saved = try XCTUnwrap(rows.first { $0.opens != nil && $0.title == "Plans" })
        XCTAssertEqual(saved.title, "Plans")
        XCTAssertEqual(
            saved.sentence,
            "Deleted permanently on one device and changed on another. The changed version is saved separately.")
        XCTAssertTrue(saved.spokenLabel.hasPrefix("Plans. Deleted permanently on one device"), saved.spokenLabel)
        XCTAssertTrue(saved.spokenLabel.contains(saved.date.formatted(date: .abbreviated, time: .shortened)))
        XCTAssertFalse(model.keptNotes.first { $0.id == saved.id }?.seen ?? true)

        let opened = await model.openKeptNote(saved.id)
        XCTAssertTrue(opened)
        let parkedID = try XCTUnwrap(saved.opens)
        XCTAssertEqual(model.draft?.id, parkedID)
        XCTAssertTrue(model.showingTrash, "Its journal is in use, so it is in Recently Deleted")
        XCTAssertNotEqual(parkedID, entry.id)
        XCTAssertTrue(model.keptNotes.first { $0.id == saved.id }?.seen ?? false, "Opening marks it seen")
    }

    func testARowWhoseSavedEntryIsGoneIsNotShownAndNothingShowsWhileLocked() async throws {
        let library = try await startedLibrary()
        let (model, store) = (library.model, library.store)
        _ = try await library.entryDeletedPermanentlyElsewhere(title: "Plans", text: "Edited here")
        let settled = try await store.resolveConflicts(at: .local)
        guard case .deletedAndChanged(let parkedID?) = settled.resolved.first?.result else {
            return XCTFail("The edit is saved separately")
        }
        try await model.refresh()
        XCTAssertEqual(model.keptNoteRows.count, 1)

        let confirmation = try await store.preparePermanentDeletion(parkedID)
        try await store.permanentlyDelete(confirmation)
        try await model.refresh()
        XCTAssertTrue(model.keptNoteRows.isEmpty, "The saved entry was deleted permanently")

        let second = try await library.entryDeletedPermanentlyElsewhere(title: "More", text: "Edited again")
        _ = try await store.resolveConflicts(at: .local)
        try await model.refresh()
        XCTAssertEqual(model.keptNoteRows.count, 1)
        XCTAssertNotEqual(second.id, parkedID)
        model.locked = true
        XCTAssertTrue(model.keptNoteRows.isEmpty, "Nothing is read while locked")
        model.locked = false

        await model.clearKeptNotes()
        XCTAssertTrue(model.keptNoteRows.isEmpty)
    }

    /// The person has nothing to do about a note, so it never counts as a problem for the rating request; a change that
    /// only a newer version can read does.
    func testKeptNotesAreNotAProblemForTheRatingRequestButAHeldChangeIs() async throws {
        let library = try await startedLibrary()
        let (model, store) = (library.model, library.store)
        model.applicationActive = true
        _ = try await library.entryDeletedPermanentlyElsewhere(title: "Plans", text: "Edited here")
        try await library.journalRenamedOnTwoDevices(from: "Travel", here: "Trips", there: "Journeys")
        try await library.entryEditedOnTwoDevices(title: "Notes")
        _ = try await store.resolveConflicts(at: .local)
        try await model.refresh()
        XCTAssertEqual(model.keptNoteRows.count, 3)
        XCTAssertTrue(model.reviewStateIsClear)

        try await library.entryHeldForANewerVersion(title: "Held")
        try await model.refresh()
        XCTAssertTrue(model.heldChangesNeedUpdate)
        XCTAssertFalse(model.reviewStateIsClear)
    }

    // MARK: The notice above the open entry

    func testTheOpenEntryShowsTheNoticeOnceUntilItIsDismissedOrTheOtherVersionIsOpened() async throws {
        let library = try await startedLibrary()
        let (model, store) = (library.model, library.store)
        let entry = try await library.entryEditedOnTwoDevices(title: "Notes")
        try await model.refresh()
        model.selectedID = entry.id
        model.draft = model.items.first { $0.id == entry.id }
        let beforeSettling = model.entryNotice(for: try XCTUnwrap(model.draft))
        XCTAssertNil(beforeSettling, "Nothing to say while the versions wait to be settled")

        _ = try await store.resolveConflicts(at: .local)
        try await model.refresh()
        let open = try XCTUnwrap(model.draft)
        guard case .keptBoth(let note)? = model.entryNotice(for: open) else {
            return XCTFail("The entry says the other version was saved")
        }
        XCTAssertEqual(note.recordID, entry.id)
        XCTAssertEqual(open.document.text, "Edited here", "This device's version stays the entry")

        await model.dismissKeptNote(note.id)
        XCTAssertNil(model.entryNotice(for: open), "Dismissed")
        XCTAssertEqual(model.keptNoteRows.count, 1, "…and still listed in Settings until it expires")

        let again = try await library.entryEditedOnTwoDevices(title: "Notes", revisions: (3, 4))
        _ = try await store.resolveConflicts(at: .local)
        try await model.refresh()
        let second = try XCTUnwrap(model.items.first { $0.id == again.id })
        guard case .keptBoth(let next)? = model.entryNotice(for: second) else {
            return XCTFail("A later copy of the same entry is noted again")
        }
        let opened = await model.openKeptNote(next.id)
        XCTAssertTrue(opened)
        XCTAssertNotEqual(model.draft?.id, entry.id, "The other version is open")
        XCTAssertNil(model.entryNotice(for: second), "Opening it marks the note seen")
    }

    func testTheNoticeSaysWhenTheOtherVersionIsNewerAndNothingShowsWhileLockedOrForAJournal() async throws {
        let library = try await startedLibrary()
        let (model, store) = (library.model, library.store)
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_100_000)
        let entry = try await library.entryEditedOnTwoDevices(title: "Notes", here: older, there: newer)
        _ = try await store.resolveConflicts(at: .local)
        try await model.refresh()
        guard case .keptBoth(let note)? = model.entryNotice(for: entry) else { return XCTFail("No notice") }
        XCTAssertEqual(note.otherIsNewer, true)
        let row = try XCTUnwrap(model.keptNoteRows.first)
        XCTAssertEqual(row.sentence, "Changed on two devices. The other version is newer. Both versions are kept.")

        model.locked = true
        XCTAssertNil(model.entryNotice(for: entry), "Nothing is read while locked")
        XCTAssertTrue(model.keptNoteRows.isEmpty)
        model.locked = false
        let journal = try XCTUnwrap(model.journals.first)
        XCTAssertNil(model.entryNotice(for: journal))
    }

    /// The text under a resting cursor never moves: a notice that arrives while the person is in the entry waits for the
    /// next time it is shown or for the editor to let go; one that has appeared stays.
    func testANoticeWaitsForTheEditorToLetGoAndStaysOnceItHasAppeared() {
        let notice = UUID()
        var release = NoticeRelease()
        XCTAssertTrue(release.isVisible(notice, whileWriting: false), "Shown in place when nobody is writing")
        XCTAssertFalse(release.isVisible(notice, whileWriting: true), "…but not under a resting cursor")
        release.reveal(notice, whileWriting: true)
        XCTAssertFalse(release.isVisible(notice, whileWriting: true), "Revealing while writing does nothing")
        release.reveal(notice, whileWriting: false)
        XCTAssertTrue(release.isVisible(notice, whileWriting: true), "Once shown, it stays when writing starts again")
        XCTAssertFalse(release.isVisible(UUID(), whileWriting: true), "Another notice waits for its own moment")
    }

    func testAnEntryHoldingAVersionFromANewerAppSaysSoWithoutAnyButtons() async throws {
        let library = try await startedLibrary()
        let model = library.model
        let held = try await library.entryHeldForANewerVersion(title: "Held")
        try await model.refresh()
        XCTAssertEqual(model.entryNotice(for: held), .updateNeeded)
        XCTAssertTrue(model.heldChangesNeedUpdate)
        XCTAssertTrue(model.keptNoteRows.isEmpty, "A held change is one line in Settings ▸ Sync, not a row")
    }

    // MARK: Support

    @MainActor private final class Library {
        let model: AppModel
        let store: JournalStore
        let key: Data
        let peerRoot: URL
        let journal: JournalItem
        private var cursor: Int64 = 0
        private var entries: [String: UUID] = [:]

        init(model: AppModel, store: JournalStore, key: Data, peerRoot: URL, journal: JournalItem) {
            self.model = model
            self.store = store
            self.key = key
            self.peerRoot = peerRoot
            self.journal = journal
        }

        /// What sync does with a record another device wrote: stores it, and sets it aside when it meets writing here.
        private func deliver(_ item: JournalItem, revision: Int64) async throws {
            cursor += 1
            try await store.apply([try remote(item, revision: revision, cursor: cursor)], cursor: cursor)
        }

        /// An entry this device edited while another deleted it permanently, as the pull delivers it.
        func entryDeletedPermanentlyElsewhere(title: String, text: String) async throws -> JournalItem {
            let entry = JournalItem(kind: "entry", journalID: journal.id, title: title, document: .plain("Original"))
            let peer = try JournalStore(directory: peerRoot.appendingPathComponent(UUID().uuidString), key: key)
            // The other device has the journal too, so the entry's deletion can be made permanent there.
            try await peer.apply([try remote(journal, revision: 1, cursor: 1)], cursor: 1)
            try await peer.apply([try remote(entry, revision: 1, cursor: 2)], cursor: 2)
            var deleted = entry
            deleted.deletedAt = Date()
            try await peer.save(deleted)
            let marker = try await peer.permanentlyDelete(try await peer.preparePermanentDeletion(entry.id))
            try await peer.close()
            try await deliver(entry, revision: 1)
            var edited = entry
            edited.document = .plain(text)
            try await store.save(edited)
            try await deliver(marker, revision: 2)
            return edited
        }

        func journalRenamedOnTwoDevices(from original: String, here: String, there: String) async throws {
            let shared = JournalItem(kind: "journal", title: original)
            try await deliver(shared, revision: 1)
            var mine = shared
            mine.title = here
            try await store.save(mine)
            var theirs = shared
            theirs.title = there
            try await deliver(theirs, revision: 2)
        }

        func journalChangedAgainstPermanentDeletion(title: String, editedTo edited: String) async throws {
            let shared = JournalItem(kind: "journal", title: title)
            let peer = try JournalStore(directory: peerRoot.appendingPathComponent(UUID().uuidString), key: key)
            try await peer.apply([try remote(shared, revision: 1)], cursor: 1)
            var deleted = shared
            deleted.deletedAt = Date()
            try await peer.save(deleted)
            let marker = try await peer.permanentlyDelete(try await peer.preparePermanentDeletion(shared.id))
            try await peer.close()
            try await deliver(shared, revision: 1)
            var mine = shared
            mine.title = edited
            try await store.save(mine)
            try await deliver(marker, revision: 2)
        }

        /// An entry edited here while another device edited it too. `revisions` are the revisions the entry is at and
        /// the other device's version arrives at; a second call for the same entry continues from them.
        @discardableResult func entryEditedOnTwoDevices(
            title: String, here: Date? = nil, there: Date? = nil, revisions: (Int64, Int64) = (1, 2)
        ) async throws -> JournalItem {
            let id = entries[title] ?? UUID()
            entries[title] = id
            var entry = JournalItem(
                id: id, kind: "entry", journalID: journal.id, title: title, document: .plain("Original"))
            if revisions.0 == 1 {
                try await deliver(entry, revision: 1)
            } else {
                let stored = try await store.item(id)
                entry = try XCTUnwrap(stored)
                // Sent and accepted, so the record is clean at the earlier revision.
                for change in try await store.pending() where change.recordID == id {
                    let receipt = RemoteChange(
                        cursor: 100, recordId: id, revision: revisions.0, kind: "entry", payload: change.payload,
                        deviceId: UUID(), modifiedAt: Date())
                    try await store.acknowledge(change, receipt: receipt)
                }
            }
            var mine = entry
            mine.document = .plain(revisions.0 == 1 ? "Edited here" : "Edited here again")
            if let here { mine.modifiedAt = here }
            try await store.save(mine)
            var theirs = entry
            theirs.document = .plain("Edited there \(revisions.1)")
            if let there { theirs.modifiedAt = there }
            try await deliver(theirs, revision: revisions.1)
            return mine
        }

        /// A record with a member this version doesn't know, as a newer app writes it, against writing here.
        @discardableResult func entryHeldForANewerVersion(title: String) async throws -> JournalItem {
            let entry = JournalItem(kind: "entry", journalID: journal.id, title: title, document: .plain("Original"))
            try await deliver(entry, revision: 1)
            var mine = entry
            mine.document = .plain("Edited here")
            try await store.save(mine)
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: PortableRecord.encode(entry)) as? [String: Any])
            object["futureLayout"] = ["columns": 2]
            let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
            cursor += 1
            let change = RemoteChange(
                cursor: cursor, recordId: entry.id, revision: 2, kind: "entry",
                payload: try VaultCrypto.seal(
                    future, key: key, context: VaultCrypto.recordContext(id: entry.id, kind: "entry")
                ).base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
            try await store.apply([change], cursor: cursor)
            return mine
        }

        func remote(_ item: JournalItem, revision: Int64, cursor: Int64? = nil) throws -> RemoteChange {
            RemoteChange(
                cursor: cursor ?? revision, recordId: item.id, revision: revision, kind: item.kind,
                payload: try VaultCrypto.seal(
                    PortableRecord.encode(item), key: key,
                    context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
                ).base64EncodedString(),
                deviceId: UUID(), modifiedAt: item.modifiedAt)
        }
    }

    private func startedLibrary() async throws -> Library {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            try? Keychain.remove(model.keyAccount)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        let store = try XCTUnwrap(model.store)
        let key = try XCTUnwrap(model.masterKey)
        let journal = try XCTUnwrap(model.journals.first)
        return Library(
            model: model, store: store, key: key, peerRoot: root.appendingPathComponent("peers"), journal: journal)
    }
}
