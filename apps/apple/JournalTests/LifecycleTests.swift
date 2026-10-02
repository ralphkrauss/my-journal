import JournalCore
import XCTest

@testable import Journal

@MainActor
final class LifecycleTests: XCTestCase {
    func testLockedModelRejectsEntryAndJournalMutations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let journal = JournalItem(kind: "journal", title: "Private")
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: "Preserve me")
        entry.deletedAt = Date()
        try await store.save(journal)
        try await store.save(entry)
        let original = try await store.item(entry.id)
        let model = AppModel()
        model.store = store
        model.items = [journal, entry]
        model.selectedJournalID = journal.id
        model.draft = entry

        model.locked = true
        await model.createJournal("Not allowed")
        await model.newEntry()
        await model.restore(entry)
        await model.deleteSelected()
        await model.saveTemplate(name: "Not allowed")
        var edited = entry
        edited.title = "Not allowed"
        model.updateDraft(edited)
        await model.saveItem(edited)
        let stored = try await store.items()
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.id == entry.id }, original)
        XCTAssertEqual(model.draft, entry)
    }
    func testFinalEditSurvivesImmediateFlushAndReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let model = AppModel()
        model.store = store
        let journal = JournalItem(kind: "journal", title: "Work")
        var item = JournalItem(kind: "entry", journalID: journal.id, title: "First")
        try await store.save(journal)
        try await store.save(item)
        model.items = [journal, item]
        model.draft = item
        model.selectedJournalID = journal.id
        for index in 0..<30 {
            item.document = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Final text \(index)")])])
            model.updateDraft(item)
        }
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
        let reopened = try JournalStore(directory: root, key: key)
        let restored = try await reopened.items()
        XCTAssertEqual(restored.first { $0.id == item.id }?.document.text, "Final text 29")
    }
}
