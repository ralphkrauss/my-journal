import JournalCore
import XCTest

@testable import Journal

/// The lists follow pins and journal order (pinned-entries.md, journal-order.md): Previous Entry and Next Entry move
/// through what's on screen, Pinned first, and every list of journals uses the person's order.
@MainActor final class PinnedListTests: XCTestCase {
    func testPinnedEntriesComeFirstAndPreviousAndNextFollowTheScreen() async throws {
        let model = try await startedModel()
        let journal = try XCTUnwrap(model.journals.first)
        let store = try XCTUnwrap(model.store)
        var entries: [JournalItem] = []
        for days in [3.0, 2, 1] {
            let entry = JournalItem(
                kind: "entry", journalID: journal.id, title: "\(Int(days)) days ago", document: .plain("Text"),
                date: Date().addingTimeInterval(-86_400 * days))
            try await store.save(entry)
            entries.append(entry)
        }
        try await model.refresh()
        await model.switchJournal(journal.id)
        await model.setPinned(true, entryID: entries[0].id, undoManager: nil)

        XCTAssertEqual(model.entries.map(\.id), [entries[0].id, entries[2].id, entries[1].id])
        XCTAssertEqual(model.entryGroups.first?.0, AppModel.pinnedSection)
        XCTAssertEqual(model.entryGroups.first?.1.map(\.id), [entries[0].id])
        await model.select(entries[0].id)
        XCTAssertEqual(model.listedID(.next), entries[2].id, "Next Entry leaves Pinned for the newest month")
        await model.select(entries[2].id)
        XCTAssertEqual(model.listedID(.previous), entries[0].id)

        // In Recently Deleted a pinned entry is listed with the others, without a Pinned section.
        let stored = try await store.item(entries[0].id)
        var deleted = try XCTUnwrap(stored)
        deleted.deletedAt = Date()
        try await store.save(deleted)
        try await model.refresh()
        await model.showCollection(trash: true)
        XCTAssertFalse(model.entryGroups.contains { $0.0 == AppModel.pinnedSection })
    }

    func testAMovedJournalKeepsItsPlaceInEveryJournalList() async throws {
        let model = try await startedModel()
        await model.createJournal("Work")
        await model.createJournal("Archive")
        XCTAssertEqual(model.journals.map(\.title), ["Archive", "Default", "Work"], "By name before any move")
        let work = try XCTUnwrap(model.journals.first { $0.title == "Work" })
        let moved = await model.moveJournal(work.id, to: 0, undoManager: nil)
        XCTAssertTrue(moved)
        XCTAssertEqual(model.journals.map(\.title), ["Work", "Archive", "Default"])
        await model.createJournal("Zero")
        XCTAssertEqual(model.journals.last?.title, "Zero", "Once arranged, a new journal goes to the end")
    }

    /// A library record from a newer version can't be changed, and trying again won't help: the failure says to update.
    func testAPinOrMoveThatFailsBecauseTheLibraryIsFromANewerVersionSaysToUpdate() {
        let pinFailure = "Couldn’t pin the entry."
        XCTAssertEqual(
            AppModel.libraryFailure(LibraryError.newerVersion, fallback: pinFailure),
            "Update My Journal to use pinned entries and journal order.")
        XCTAssertEqual(AppModel.libraryFailure(LibraryError.unavailable, fallback: pinFailure), pinFailure)
        XCTAssertEqual(AppModel.libraryFailure(CocoaError(.fileWriteUnknown), fallback: pinFailure), pinFailure)
    }

    /// Edit ▸ Undo Pin Entry unpins and Redo Pin Entry pins again, as often as asked; the same for Move Journal. The
    /// reverse step must be registered while the undo manager undoes, or Redo is never offered.
    func testUndoAndRedoPinAndMoveJournal() async throws {
        let model = try await startedModel()
        let journal = try XCTUnwrap(model.journals.first)
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Goals", document: .plain("Text"))
        try await XCTUnwrap(model.store).save(entry)
        try await model.refresh()
        let undo = UndoManager()
        await model.setPinned(true, entryID: entry.id, undoManager: undo)
        XCTAssertEqual(undo.undoActionName, "Pin Entry")
        for _ in 0..<2 {
            undo.undo()
            try await waitUntil { !model.library.pinned.contains(entry.id) }
            XCTAssertTrue(undo.canRedo, "Redo Pin Entry is available")
            XCTAssertEqual(undo.redoActionName, "Pin Entry")
            undo.redo()
            try await waitUntil { model.library.pinned.contains(entry.id) }
            XCTAssertTrue(undo.canUndo)
        }

        await model.createJournal("Work")
        let work = try XCTUnwrap(model.journals.first { $0.title == "Work" })
        XCTAssertEqual(model.journals.map(\.title), ["Default", "Work"])
        let moves = UndoManager()
        await model.moveJournal(work.id, to: 0, undoManager: moves)
        XCTAssertEqual(model.journals.map(\.title), ["Work", "Default"])
        for _ in 0..<2 {
            moves.undo()
            try await waitUntil { model.journals.map(\.title) == ["Default", "Work"] }
            XCTAssertEqual(moves.redoActionName, "Move Journal")
            moves.redo()
            try await waitUntil { model.journals.map(\.title) == ["Work", "Default"] }
        }
        XCTAssertNil(model.error)
    }

    /// Undo Unpin Entry after the entry was deleted does nothing and says nothing; its steps are gone.
    func testUndoingAPinOfADeletedEntryDoesNothingQuietly() async throws {
        let model = try await startedModel()
        let journal = try XCTUnwrap(model.journals.first)
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Goals", document: .plain("Text"))
        let store = try XCTUnwrap(model.store)
        try await store.save(entry)
        try await model.refresh()
        await model.setPinned(true, entryID: entry.id, undoManager: nil)
        let undo = UndoManager()
        await model.setPinned(false, entryID: entry.id, undoManager: undo)
        var deleted = try XCTUnwrap(model.items.first { $0.id == entry.id })
        deleted.deletedAt = Date()
        try await store.save(deleted)
        try await model.refresh()
        undo.undo()
        try await waitUntil { !undo.canRedo }
        XCTAssertNil(model.error)
        XCTAssertFalse(undo.canUndo)
    }

    /// A pin withdrawn before it was stored (the next row action came first) isn't reported as a failure.
    func testACancelledPinShowsNoAlert() async throws {
        let model = try await startedModel()
        let journal = try XCTUnwrap(model.journals.first)
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Goals", document: .plain("Text"))
        try await XCTUnwrap(model.store).save(entry)
        try await model.refresh()
        let pinning = Task { await model.setPinned(true, entryID: entry.id, undoManager: nil) }
        pinning.cancel()
        _ = await pinning.value
        XCTAssertNil(model.error)
    }

    /// Locking ends the journals list's edit mode (journal-order.md), although the list is gone before it could see
    /// the lock.
    func testLockingEndsJournalEditMode() async throws {
        let model = try await startedModel()
        model.configuration?.appLock = true
        model.editingJournals = true
        XCTAssertTrue(model.lockImmediately())
        XCTAssertFalse(model.editingJournals)
    }

    /// Deleting a journal in edit mode keeps edit mode on (journal-order.md); replacing the library ends it.
    func testDeletingAJournalKeepsEditModeAndReplacingTheLibraryEndsIt() async throws {
        let model = try await startedModel()
        await model.createJournal("Work")
        let work = try XCTUnwrap(model.journals.first { $0.title == "Work" })
        model.editingJournals = true
        let plan = try await model.prepareJournalDeletion(work.id)
        _ = try await model.deleteJournal(plan)
        XCTAssertFalse(model.journals.contains { $0.id == work.id })
        XCTAssertTrue(model.editingJournals)
        model.vaultReplacement = true
        XCTAssertFalse(model.editingJournals)
        model.vaultReplacement = false
    }

    /// New Entry In ▸ a journal, locked before the entry was made: nothing is made, and no "no longer available"
    /// alert waits behind the lock screen.
    func testLockingWhileStartingAnEntryFromATemplateShowsNoAlertAfterwards() async throws {
        let model = try await startedModel()
        model.configuration?.appLock = true
        let journal = try XCTUnwrap(model.journals.first)
        let template = JournalItem(kind: "template", title: "Daily", document: .plain("What went well?"))
        try await XCTUnwrap(model.store).save(template)
        try await model.refresh()
        XCTAssertTrue(model.lockImmediately())
        await model.newEntry(fromTemplate: template.id, in: journal.id)
        XCTAssertNil(model.error)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The condition never held")
    }

    private func startedModel() async throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            try? Keychain.remove(model.keyAccount)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        return model
    }
}
