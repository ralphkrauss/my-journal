import Foundation
import XCTest

@testable import JournalCore

final class EntryDateTests: XCTestCase {
    func testDatePatchPreservesNewerContentAndRejectsStaleOrDeletedTargets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: directory, key: key)
        addTeardownBlock { try await store.close() }
        let journal = JournalItem(kind: "journal", title: "Work")
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: "Original")
        entry.date = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.save(journal)
        try await store.save(entry)
        let originalDate = entry.date
        entry.title = "Newer title"
        entry.document = JournalDocument(blocks: [DocumentBlock(runs: [TextRun("Newer body")])])
        try await store.save(entry)
        let changedDate = originalDate.addingTimeInterval(-86_400)
        let changed = try await store.changeEntryDate(entry.id, expectedDate: originalDate, to: changedDate)
        XCTAssertEqual(changed.title, entry.title)
        XCTAssertEqual(changed.document, entry.document)
        XCTAssertEqual(changed.date, changedDate)
        do {
            _ = try await store.changeEntryDate(entry.id, expectedDate: originalDate, to: originalDate)
            XCTFail("A stale date must not overwrite the committed date.")
        } catch EntryDateError.changed {}
        var deleted = journal
        deleted.deletedAt = Date()
        try await store.save(deleted)
        do {
            _ = try await store.changeEntryDate(entry.id, expectedDate: changedDate, to: originalDate)
            XCTFail("An entry in a deleted journal must not be edited.")
        } catch EntryDateError.unavailable {}
        let reopened = try JournalStore(directory: directory, key: key)
        addTeardownBlock { try await reopened.close() }
        let persisted = try await reopened.item(entry.id)
        XCTAssertEqual(persisted, changed)
    }
}
