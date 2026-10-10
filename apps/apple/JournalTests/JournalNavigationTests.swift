import CryptoKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class JournalNavigationTests: XCTestCase {
    func testAllEntriesIncludesLiveJournalsWithoutLeakingDeletedOrUnavailableEntries() async {
        let model = AppModel(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = JournalItem(kind: "journal", title: "Default")
        let second = JournalItem(kind: "journal", title: "Work")
        let personal = JournalItem(kind: "entry", journalID: first.id, title: "Today")
        let work = JournalItem(kind: "entry", journalID: second.id, title: "Meeting")
        var archived = JournalItem(kind: "entry", journalID: first.id, title: "Archived")
        archived.archivedAt = Date()
        var deleted = JournalItem(kind: "entry", journalID: second.id, title: "Deleted")
        deleted.deletedAt = Date()
        let unavailable = JournalItem(kind: "entry", journalID: UUID(), title: "Unavailable")
        model.items = [first, second, personal, work, archived, deleted, unavailable]
        model.selectedJournalID = first.id
        // Archiving is no longer offered; an entry archived by an earlier version shows in its journal.
        XCTAssertEqual(Set(model.entries.map(\.id)), [personal.id, archived.id])
        model.showingAllEntries = true
        XCTAssertEqual(Set(model.entries.map(\.id)), [personal.id, work.id, archived.id])
        model.query = "Meeting"
        await model.lists.searched()
        XCTAssertEqual(model.entries.map(\.id), [work.id])
    }

    func testSelectedJournalPreviewCannotOverwriteLaterMetadataAndRestoreSurvivesReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        defer {
            let account =
                "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        await model.newEntry()
        let parent = try XCTUnwrap(model.selectedJournalID)
        let store = try XCTUnwrap(model.store)
        var entry = try XCTUnwrap(model.draft)
        entry.title = "Survives journal recovery"
        model.updateDraft(entry)
        let plan = try await model.prepareJournalDeletion(parent)
        _ = try await model.deleteJournal(plan)
        await model.showCollection(trash: true)
        await model.select(parent)
        var changed = try XCTUnwrap(model.draft)
        changed.title = "Renamed on another device"
        try await store.save(changed)
        // A lifecycle flush before refresh must not write the selected old metadata.
        let flushed = await model.flush()
        XCTAssertTrue(flushed)
        let stored = try await store.item(parent)
        XCTAssertEqual(stored?.title, changed.title)
        try await model.refresh()
        XCTAssertEqual(model.draft?.title, changed.title)
        do {
            _ = try await model.restoreJournal(parent, expectedTitle: plan.title)
            XCTFail("A stale restore confirmation must not mutate the journal.")
        } catch JournalLifecycleError.changed {}
        _ = try await model.restoreJournal(parent, expectedTitle: changed.title)
        XCTAssertFalse(model.showingTrash)
        XCTAssertNil(model.draft)
        XCTAssertEqual(model.selectedJournalID, parent)
        try await store.close()
        let reopened = AppModel(directory: root)
        await reopened.load()
        XCTAssertEqual(reopened.selectedJournalID, parent)
        XCTAssertEqual(reopened.entries.first?.title, entry.title)
        XCTAssertEqual(reopened.journals.first?.title, changed.title)
        try await reopened.store?.close()
    }
    func testDeletedAndUnavailableEntriesStayDiscoverableAndSingleRecoveryPreservesSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        defer {
            let account =
                "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        await model.newEntry()
        let parent = try XCTUnwrap(model.selectedJournalID)
        let store = try XCTUnwrap(model.store)
        var entry = try XCTUnwrap(model.draft)
        entry.title = "Retained notes"
        model.updateDraft(entry)
        var independent = JournalItem(kind: "entry", journalID: parent, title: "Deleted separately")
        independent.deletedAt = Date()
        try await store.save(independent)
        let plan = try await model.prepareJournalDeletion(parent)
        let deleted = try await model.deleteJournal(plan)
        XCTAssertTrue(deleted)
        XCTAssertTrue(model.journals.isEmpty)
        XCTAssertNil(model.draft)
        await model.showCollection(trash: true)
        XCTAssertEqual(Set(model.entries.map(\.id)), Set([entry.id, independent.id]))
        XCTAssertEqual(model.filteredDeletedJournals.map(\.id), [parent])
        await model.select(parent)
        XCTAssertFalse(model.canEdit)
        let deletedJournal = try XCTUnwrap(model.draft)
        if let preview = await NativeTestPreview.capture(
            DeletedJournalView(journal: deletedJournal).environmentObject(model), name: "Deleted journal detail")
        {
            add(preview)
        }
        model.query = "No matching journal"
        await model.lists.searched()
        XCTAssertTrue(model.filteredDeletedJournals.isEmpty)
        XCTAssertTrue(model.entries.isEmpty)
        model.query = ""
        await model.select(entry.id)
        XCTAssertFalse(model.canEdit)
        var rejected = entry
        rejected.title = "Not editable in trash"
        model.updateDraft(rejected)
        XCTAssertEqual(model.draft?.title, entry.title)
        if let preview = await NativeTestPreview.capture(
            MoveEntryView(entryID: entry.id).environmentObject(model), name: "Recover entry without a live destination")
        {
            add(preview)
        }
        let created = try await model.createRecoveryJournal("Recovered", entryID: entry.id)
        XCTAssertTrue(created)
        XCTAssertEqual(model.draft?.id, entry.id)
        XCTAssertTrue(model.showingTrash)
        let destination = try XCTUnwrap(model.journals.first { $0.title == "Recovered" })
        try await model.moveEntry(entry.id, to: destination.id)
        XCTAssertEqual(model.draft?.id, entry.id)
        XCTAssertEqual(model.draft?.journalID, destination.id)
        XCTAssertTrue(model.canEdit)
        let restored = try await model.restoreJournal(parent)
        XCTAssertTrue(restored)
        await model.showCollection(trash: true)
        XCTAssertEqual(model.entries.map(\.id), [independent.id])
        let orphan = JournalItem(kind: "entry", journalID: UUID(), title: "Unavailable but preserved")
        try await store.save(orphan)
        try await model.refresh()
        await model.showCollection(unavailable: true)
        XCTAssertEqual(model.entries.map(\.id), [orphan.id])
        await model.select(orphan.id)
        XCTAssertFalse(model.canEdit)
        if let preview = await NativeTestPreview.capture(
            EntryRecoveryNotice(entry: orphan).environmentObject(model), name: "Unavailable journal entry recovery")
        {
            add(preview)
        }
        let savedOrphan = try await store.item(orphan.id)
        XCTAssertEqual(savedOrphan?.journalID, orphan.journalID)
        let missingParent = try XCTUnwrap(orphan.journalID)
        try await store.save(JournalItem(id: missingParent, kind: "journal", title: "Arrived from sync"))
        try await model.refresh()
        XCTAssertFalse(model.showingUnavailable)
        XCTAssertEqual(model.selectedJournalID, missingParent)
        XCTAssertEqual(model.draft?.id, orphan.id)
        XCTAssertTrue(model.canEdit)
        try await restoreLegacyOrphan(into: destination, model: model, store: store)
        try await store.close()
    }

    /// An entry an earlier version deleted with a journal that is gone is restored into the Default Journal, and says so.
    private func restoreLegacyOrphan(into destination: JournalItem, model: AppModel, store: JournalStore) async throws {
        var legacy = JournalItem(kind: "entry", journalID: UUID(), title: "Legacy orphan")
        legacy.deletedWithJournal = true
        legacy.deletedAt = Date()
        try await store.save(legacy)
        try await model.refresh()
        await model.showCollection(unavailable: true)
        await model.select(legacy.id)
        model.chooseDefaultJournal(destination.id)
        var announced: [String] = []
        model.announce = { announced.append($0) }
        let legacyOffer = try XCTUnwrap(model.restoreOffer(for: legacy))
        XCTAssertEqual(legacyOffer.title, "Restore to “Recovered”")
        let restoredLegacy = await model.restore(legacy)
        XCTAssertTrue(restoredLegacy)
        XCTAssertEqual(announced, ["Restored to Recovered."])
        XCTAssertEqual(model.draft?.id, legacy.id)
        XCTAssertFalse(model.draft?.deletedWithJournal ?? true)
        XCTAssertEqual(model.draft?.journalID, destination.id)
        XCTAssertTrue(model.canEdit)
    }

    /// An entry opened in All Entries reopens after relaunch, even when it belongs to another journal.
    func testAllEntriesSelectionReopensTheEntryInItsJournal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        let relaunched = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            try? await relaunched.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        let parent = try XCTUnwrap(model.selectedJournalID)
        await model.newEntry()
        var entry = try XCTUnwrap(model.draft)
        entry.title = "Keep this entry open"
        model.updateDraft(entry)
        _ = await model.finishPendingSave()
        await model.createJournal("Work")
        _ = await model.show(.all)
        _ = await model.select(entry.id)
        XCTAssertEqual(model.draft?.id, entry.id)
        try await model.store?.close()

        await relaunched.load()
        XCTAssertEqual(relaunched.selectedJournalID, parent)
        XCTAssertEqual(relaunched.draft?.id, entry.id)
    }

    /// View ▸ Previous Entry and Next Entry follow the list as shown, search included, while the list may be hidden.
    /// The open entry is saved first, as choosing another row saves it, and they stop at either end.
    func testPreviousAndNextEntryFollowTheVisibleListAndSaveFirst() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        let store = try XCTUnwrap(model.store)
        let journal = try XCTUnwrap(model.selectedJournalID)
        var entries: [JournalItem] = []
        for (index, title) in ["River walk", "Team meeting", "River trip plans"].enumerated() {
            var entry = JournalItem(kind: "entry", journalID: journal, title: title)
            entry.date = Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400)
            try await store.save(entry)
            entries.append(entry)
        }
        try await model.refresh()
        XCTAssertEqual(model.listedIDs, entries.map(\.id), "Newest first, as the list shows them")
        XCTAssertEqual(model.listedID(.next), entries[0].id, "With nothing open, Next Entry opens the first entry")

        await model.select(entries[0].id)
        XCTAssertNil(model.listedID(.previous), "Previous Entry is unavailable at the top of the list")
        var edited = try XCTUnwrap(model.draft)
        edited.title = "River walk at dawn"
        model.updateDraft(edited)
        await model.selectListed(.next)
        XCTAssertEqual(model.selectedID, entries[1].id)
        let saved = try await store.item(entries[0].id)
        XCTAssertEqual(saved?.title, edited.title, "The entry left behind is saved")

        await model.selectListed(.next)
        XCTAssertEqual(model.selectedID, entries[2].id)
        XCTAssertNil(model.listedID(.next), "Next Entry is unavailable at the end of the list")

        model.query = "River"
        await model.lists.searched()
        XCTAssertEqual(model.listedID(.previous), entries[0].id, "An entry the search hides is skipped")

        model.query = ""
        _ = await model.showCollection(trash: true)
        XCTAssertNil(model.listedID(.next), "Nothing to move to in an empty list")
        XCTAssertNil(model.listedID(.previous))
        _ = await model.show(.journal(journal))
        await model.select(entries[1].id)
        model.locked = true
        XCTAssertNil(model.listedID(.next), "Locked, the journal's entries can't be opened")
        XCTAssertNil(model.listedID(.previous))
    }

    /// A journal synced from another device or restored from an archive can have an empty name. The search field's
    /// placeholder, also its tooltip and VoiceOver label, names it as the sidebar and window title do.
    func testSearchPromptNamesAJournalWithoutATitle() {
        let model = AppModel(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let untitled = JournalItem(kind: "journal", title: "")
        let work = JournalItem(kind: "journal", title: "Work")
        model.items = [untitled, work]
        model.selectedJournalID = untitled.id
        XCTAssertEqual(RootView.searchPrompt(for: model), "Search Untitled Journal")
        model.selectedJournalID = work.id
        XCTAssertEqual(RootView.searchPrompt(for: model), "Search Work")
    }

    /// New Entry with a deleted entry open in Recently Deleted opens one new entry in the default journal. Leaving
    /// Recently Deleted closed the deleted entry after the new one was saved, so it was never opened (iPad, Mac).
    func testNewEntryFromAnOpenDeletedEntryOpensTheNewEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        let parent = try XCTUnwrap(model.selectedJournalID)
        let store = try XCTUnwrap(model.store)
        var gone = JournalItem(kind: "entry", journalID: parent, title: "Gone entry")
        gone.deletedAt = Date()
        try await store.save(gone)
        try await model.refresh()
        _ = await model.show(.deleted)
        await model.select(gone.id)
        XCTAssertEqual(model.draft?.id, gone.id)

        await model.newEntry()
        let created = try XCTUnwrap(model.draft)
        XCTAssertNotEqual(created.id, gone.id)
        XCTAssertEqual(model.selectedID, created.id)
        XCTAssertEqual(model.destination, .journal(parent))
        XCTAssertEqual(model.titleFocus?.itemID, created.id)
        let live = try await store.items().filter { $0.kind == "entry" && $0.deletedAt == nil }
        XCTAssertEqual(live.map(\.id), [created.id])
    }
}
