import JournalCore
import XCTest

@testable import Journal

@MainActor
final class DraftSaveTests: XCTestCase {
    func testCancelledOrLockedRetryKeepsDraftWhileLockCleanupCanSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Saved")
        try await store.save(journal)
        try await store.save(entry)
        let baseline = try await store.items()
        let model = AppModel(directory: root)
        model.store = store
        model.items = baseline
        model.selectedID = entry.id
        var edited = entry
        edited.document = .plain("Retained draft")
        model.draft = edited
        model.saveFailure = true
        model.error = "Existing save error"
        let retry = Task { await model.flush(whileEditing: entry.id) }
        retry.cancel()
        let cancelledResult = await retry.value
        XCTAssertFalse(cancelledResult)
        XCTAssertEqual(model.draft, edited)
        XCTAssertTrue(model.saveFailure)
        XCTAssertEqual(model.error, "Existing save error")
        let afterCancellation = try await store.items()
        XCTAssertEqual(afterCancellation, baseline)
        model.locked = true
        let lockedResult = await model.flush(whileEditing: entry.id)
        XCTAssertFalse(lockedResult)
        let afterLock = try await store.items()
        XCTAssertEqual(afterLock, baseline)
        let cleanupResult = await model.flush()
        XCTAssertTrue(cleanupResult)
        XCTAssertFalse(model.saveFailure)
        let saved = try await store.items().first { $0.id == entry.id }
        XCTAssertEqual(saved?.document, edited.document)
        XCTAssertEqual(model.draft, edited)
        try await store.close()
    }
}
