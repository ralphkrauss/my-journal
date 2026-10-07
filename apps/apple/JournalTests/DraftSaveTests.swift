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

    /// Typing retries a failed write on every edit; the alert is for the first failure and for a requested retry.
    func testSaveFailureIsAnnouncedOnceUntilTheWriterAsksToTryAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Notes")
        try await store.save(journal)
        try await store.save(entry)
        let model = AppModel(directory: root)
        model.store = store
        model.items = try await store.items()
        model.selectedID = entry.id
        model.draft = entry
        var edited = entry
        edited.document = .plain("First edit")
        try await store.close()

        // Typing saves after each edit; the first failure is announced.
        model.updateDraft(edited)
        _ = await model.finishPendingSave()
        XCTAssertTrue(model.saveFailure)
        XCTAssertNotNil(model.error)

        model.error = nil
        for text in ["Second edit", "Third edit"] {
            edited.document = .plain(text)
            model.updateDraft(edited)
            _ = await model.finishPendingSave()
        }
        XCTAssertTrue(model.saveFailure)
        XCTAssertNil(model.error, "Later failures while typing leave the Not Saved notice to say it.")

        _ = await model.flush(announcing: .never)
        XCTAssertNil(model.error)

        _ = await model.flush(announcing: .always)
        XCTAssertNotNil(model.error, "A retry the person asked for reports its failure.")

        let reopened = try JournalStore(directory: root, key: key)
        model.store = reopened
        model.error = nil
        let saved = await model.flush(announcing: .always)
        XCTAssertTrue(saved)
        XCTAssertFalse(model.saveFailure)
        XCTAssertNil(model.error)
        try await reopened.close()
    }
}
