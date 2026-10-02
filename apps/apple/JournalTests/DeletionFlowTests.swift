import Combine
import JournalCore
import XCTest

@testable import Journal

@MainActor
final class DeletionFlowTests: XCTestCase {
    private func fixture() async throws -> (AppModel, JournalStore, [JournalItem], URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try JournalStore(directory: root, key: try VaultCrypto.generateKey())
        let journal = JournalItem(kind: "journal", title: "Personal")
        var entries: [JournalItem] = []
        for (index, title) in ["Newest", "Middle", "Oldest"].enumerated() {
            var entry = JournalItem(kind: "entry", journalID: journal.id, title: title)
            entry.date = Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400)
            entries.append(entry)
        }
        for item in [journal] + entries { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        model.items = [journal] + entries
        model.selectedJournalID = journal.id
        return (model, store, entries, root)
    }

    func testDeletingTheOpenEntryOpensTheNextOneAndRestoreBringsItBack() async throws {
        let (model, _, entries, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = entries[1].id
        model.draft = entries[1]
        let result = await model.deleteSelected(selectingNext: true)
        let deleted = try XCTUnwrap(result)
        XCTAssertEqual(deleted.id, entries[1].id)
        XCTAssertEqual(model.selectedID, entries[2].id, "The entry below the deleted one opens")
        let stored = try XCTUnwrap(model.items.first { $0.id == deleted.id })
        XCTAssertEqual(model.lifecycle.location(of: stored), .recentlyDeleted)
        await model.restore(deleted)
        let restored = try XCTUnwrap(model.items.first { $0.id == deleted.id })
        XCTAssertEqual(model.lifecycle.location(of: restored), .journal)
    }

    /// A swipe action animates its row away and expects it gone in the same update; a row that stayed until the
    /// deletion was stored sprang back, and a full swipe could stop the app. The entry that is open stays open.
    func testSwipedRowLeavesTheListAtOnceAndTheOpenEntryStaysOpen() async throws {
        let (model, _, entries, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = entries[0].id
        model.draft = entries[0]
        let removal = try XCTUnwrap(model.removeFromLists(entries[1].id, selectingNext: true))
        XCTAssertEqual(model.entries.map(\.id), [entries[0].id, entries[2].id])
        let deleted = await model.deleteListed(removal)
        XCTAssertEqual(deleted?.id, entries[1].id)
        XCTAssertEqual(model.selectedID, entries[0].id)
        XCTAssertEqual(model.entries.map(\.id), [entries[0].id, entries[2].id])
        let stored = try XCTUnwrap(model.items.first { $0.id == entries[1].id })
        XCTAssertEqual(model.lifecycle.location(of: stored), .recentlyDeleted)
    }

    /// Deleting the open entry opens the next one in its place, without an empty editor in between.
    func testDeletingTheOpenRowOpensTheNextEntryInOneStep() async throws {
        let (model, _, entries, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = entries[1].id
        model.draft = entries[1]
        var opened: [UUID?] = []
        let watch = model.$selectedID.dropFirst().sink { opened.append($0) }
        let removal = try XCTUnwrap(model.removeFromLists(entries[1].id, selectingNext: true))
        let deleted = await model.deleteListed(removal)
        watch.cancel()
        XCTAssertEqual(deleted?.id, entries[1].id)
        XCTAssertEqual(opened, [entries[2].id])
        XCTAssertEqual(model.draft?.id, entries[2].id)
    }

    /// When the deletion can't be stored, the row comes back rather than the entry silently disappearing.
    func testRowComesBackWhenTheDeletionFails() async throws {
        let (model, store, entries, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let removal = try XCTUnwrap(model.removeFromLists(entries[1].id, selectingNext: false))
        try await store.close()
        let deleted = await model.deleteListed(removal)
        XCTAssertNil(deleted)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.entries.map(\.id), entries.map(\.id))
    }

    /// Edit ▸ Undo Delete Entry brings the entry back and Redo Delete Entry deletes it again, as often as asked.
    func testUndoAndRedoDeleteKeepTheSameEntryAndContent() async throws {
        let (model, store, entries, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var middle = entries[1]
        middle.document = JournalDocument(markdown: "Kept **words**")
        try await store.save(middle)
        try await model.refresh()
        let original = try XCTUnwrap(model.items.first { $0.id == middle.id })
        model.selectedID = original.id
        model.draft = original
        let undo = UndoManager()
        let result = await model.deleteSelected(selectingNext: true)
        model.registerDeletionUndo(try XCTUnwrap(result), selectingNext: true, in: undo)
        XCTAssertEqual(undo.undoActionName, "Delete Entry")
        for _ in 0..<2 {
            undo.undo()
            try await waitUntil(model, shows: original.id, in: .journal)
            XCTAssertTrue(undo.canRedo, "Redo Delete Entry is available")
            XCTAssertEqual(undo.redoActionName, "Delete Entry")
            undo.redo()
            try await waitUntil(model, shows: original.id, in: .recentlyDeleted)
            XCTAssertTrue(undo.canUndo)
        }
        undo.undo()
        try await waitUntil(model, shows: original.id, in: .journal)
        let restored = try XCTUnwrap(model.items.first { $0.id == original.id })
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.document, original.document)
        XCTAssertEqual(restored.journalID, original.journalID)
        XCTAssertEqual(model.items.filter { $0.kind == "entry" }.count, entries.count, "No copy was made")
    }

    private func waitUntil(_ model: AppModel, shows id: UUID, in location: EntryLocation) async throws {
        for _ in 0..<200 {
            if let item = model.items.first(where: { $0.id == id }), model.lifecycle.location(of: item) == location {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The entry never reached \(location)")
    }

    func testDeletedTemplateCanBeRestoredAndIsTheDefaultAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: try VaultCrypto.generateKey())
        let template = JournalItem(
            kind: "template", title: "Daily Reflection", document: JournalDocument(markdown: "What went well?"))
        var journal = JournalItem(kind: "journal", title: "Personal")
        journal.defaultTemplateID = template.id
        for item in [template, journal] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        try await model.refresh()
        model.selectedJournalID = journal.id
        model.showingTemplates = true
        model.selectedID = template.id
        model.draft = model.items.first { $0.id == template.id }
        let result = await model.deleteSelected(selectingNext: true)
        let deleted = try XCTUnwrap(result)
        XCTAssertEqual(model.filteredDeletedTemplates.map(\.id), [template.id])
        XCTAssertTrue(model.templates.isEmpty)
        XCTAssertTrue(model.isRecentlyDeleted(deleted))
        // Meanwhile New Entry starts blank, but the journal keeps its setting for when the template comes back.
        XCTAssertNil(model.defaultTemplateID(of: try XCTUnwrap(model.journals.first)))
        model.showingTemplates = false
        await model.newEntry()
        XCTAssertEqual(model.draft?.document, JournalDocument())
        await model.restore(deleted)
        XCTAssertTrue(model.showingTemplates)
        XCTAssertEqual(model.selectedID, template.id)
        XCTAssertEqual(model.templates.map(\.id), [template.id])
        XCTAssertTrue(model.filteredDeletedTemplates.isEmpty)
        XCTAssertEqual(model.defaultTemplateID(of: try XCTUnwrap(model.journals.first)), template.id)
        try await store.close()
    }

    func testKeepingATemplateDeletedElsewhereLeavesItOpenInTemplates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let template = JournalItem(kind: "template", title: "Weekly Reflection")
        // Another device deletes the template permanently while it's being edited here.
        let peer = try JournalStore(directory: root.appendingPathComponent("peer"), key: key)
        try await peer.apply([try remote(template, revision: 1, key: key)], cursor: 1)
        var deleted = template
        deleted.deletedAt = Date()
        try await peer.save(deleted)
        let marker = try await peer.permanentlyDelete(try await peer.preparePermanentDeletion(template.id))
        try await peer.close()
        let store = try JournalStore(directory: root.appendingPathComponent("mine"), key: key)
        try await store.save(JournalItem(kind: "journal", title: "Personal"))
        try await store.apply([try remote(template, revision: 1, key: key)], cursor: 1)
        var edited = template
        edited.title = "Weekly Reflection, edited here"
        try await store.save(edited)
        try await store.apply([try remote(marker, revision: 2, key: key)], cursor: 2)
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        try await model.refresh()
        model.showingTemplates = true
        let opened = await model.select(template.id)
        XCTAssertTrue(opened)

        let review = try await model.prepareDeletionConflict(template.id)
        let refreshed = try await model.resolveDeletionConflict(review, choice: .keepTemplate)
        XCTAssertTrue(refreshed)
        XCTAssertTrue(model.showingTemplates)
        XCTAssertEqual(model.selectedID, template.id)
        XCTAssertEqual(model.draft?.title, edited.title)
        XCTAssertEqual(model.templates.map(\.id), [template.id])
        try await store.close()
    }

    func testAnOpenEntryRemovedElsewhereClosesButUnsavedWritingStaysOpen() async throws {
        let (model, store, entries, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        model.selectedID = entries[0].id
        model.draft = entries[0]
        var removed = entries[0]
        removed.deletedAt = Date()
        try await store.save(removed)
        try await model.refresh()
        XCTAssertNil(model.selectedID, "No empty editor is left behind")
        XCTAssertNil(model.draft)

        model.selectedID = entries[2].id
        var edited = entries[2]
        edited.title = "Writing not yet saved"
        model.draft = edited
        var removedWhileEditing = entries[2]
        removedWhileEditing.deletedAt = Date()
        try await store.save(removedWhileEditing)
        try await model.refresh()
        XCTAssertEqual(model.selectedID, entries[2].id)
        XCTAssertEqual(model.draft?.title, "Writing not yet saved")
    }

    /// Owner decision (2026-09-30): an entry stays once it's created, even if it's left empty.
    func testAnEmptyNewEntryStaysWhenLeft() async throws {
        let (model, _, entries, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await model.newEntry(blank: true)
        let empty = try XCTUnwrap(model.draft)
        await model.select(entries[0].id)
        await model.showCollection(all: true)
        let kept = try XCTUnwrap(model.items.first { $0.id == empty.id })
        XCTAssertEqual(model.lifecycle.location(of: kept), .journal)
    }

    /// New Entry stays available in Recently Deleted and outside any journal, and files the entry in Settings ▸
    /// Default Journal rather than the journal shown before (docs/design/default-journal.md). While that journal is
    /// deleted the oldest one in use takes its place; restoring it makes it the default again.
    func testNewEntryOutsideAJournalGoesToTheDefaultJournal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            try? Keychain.remove(model.keyAccount)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        let original = try XCTUnwrap(model.defaultJournal)
        await model.createJournal("Work")
        let work = try XCTUnwrap(model.journals.first { $0.title == "Work" })
        model.chooseDefaultJournal(work.id)
        await model.switchJournal(original.id)
        await model.showCollection(trash: true)
        XCTAssertTrue(model.canCreateEntry)

        await model.newEntry(blank: true)
        XCTAssertEqual(model.draft?.journalID, work.id)
        XCTAssertEqual(model.destination, .journal(work.id), "The journal the entry went to is shown")
        model.selectedJournalID = nil
        XCTAssertEqual(model.newEntryJournal?.id, work.id, "Nothing selected, as on the Mac")

        let plan = try await model.prepareJournalDeletion(work.id)
        _ = try await model.deleteJournal(plan)
        XCTAssertEqual(model.newEntryJournal?.id, original.id)
        _ = try await model.restoreJournal(work.id)
        await model.showCollection(all: true)
        XCTAssertEqual(model.newEntryJournal?.id, work.id)
    }

    private func remote(_ item: JournalItem, revision: Int64, key: Data) throws -> RemoteChange {
        RemoteChange(
            cursor: revision, recordId: item.id, revision: revision, kind: item.kind,
            payload: try VaultCrypto.seal(
                PortableRecord.encode(item), key: key, context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
            ).base64EncodedString(),
            deviceId: UUID(), modifiedAt: item.modifiedAt)
    }
}
