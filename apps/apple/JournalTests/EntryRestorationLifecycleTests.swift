import JournalCore
import XCTest

@testable import Journal

@MainActor
final class EntryRestorationLifecycleTests: XCTestCase {
    func testLockAfterAtomicRecoveryCannotFlushOldDeletionOrArchiveState() async throws {
        let (model, store, journal, entry) = try await fixture()
        await model.turnOnAppLockForTesting()
        let plan = try await model.prepareEntryRestoration(entry.id, journalID: journal.id)
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let restoring = Task {
            try await model.commitEntryRestoration {
                let saved = try await store.restoreEntryAndJournal(plan)
                committed.continuation.yield(())
                committed.continuation.finish()
                for await _ in release.stream { break }
                return saved
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        _ = try await restoring.value
        await locking.value
        XCTAssertTrue(model.locked)
        XCTAssertFalse(model.canEdit)
        XCTAssertEqual(model.draft?.id, entry.id)
        XCTAssertNil(model.draft?.deletedAt)
        XCTAssertNil(model.draft?.archivedAt)
        XCTAssertTrue(model.items.isEmpty)
        let savedEntry = try await store.item(entry.id)
        let savedJournal = try await store.item(journal.id)
        XCTAssertNil(savedEntry?.archivedAt)
        XCTAssertNil(savedEntry?.deletedAt)
        XCTAssertNil(savedJournal?.deletedAt)
        XCTAssertEqual(savedEntry?.document, entry.document)
        XCTAssertFalse(model.saveFailure)
    }

    func testStaleRecoveryRetainsSelectionAndFreshRecoveryOpensCapturedEntry() async throws {
        let (model, store, journal, entry) = try await fixture()
        let plan = try await model.prepareEntryRestoration(entry.id, journalID: journal.id)
        let arrived = JournalItem(kind: "entry", journalID: journal.id, title: "Arrived after review")
        try await store.save(arrived)
        do {
            _ = try await model.restoreEntryAndJournal(plan)
            XCTFail("Expanded recovery scope requires fresh review.")
        } catch EntryRestorationError.changed {}
        XCTAssertEqual(model.selectedID, entry.id)
        XCTAssertEqual(model.draft?.archivedAt, entry.archivedAt)
        XCTAssertTrue(model.showingTrash)
        let fresh = try await model.prepareEntryRestoration(entry.id, journalID: journal.id)
        let refreshed = try await model.restoreEntryAndJournal(fresh)
        XCTAssertTrue(refreshed)
        XCTAssertFalse(model.showingTrash)
        XCTAssertEqual(model.selectedJournalID, journal.id)
        XCTAssertEqual(model.selectedID, entry.id)
        XCTAssertNil(model.draft?.archivedAt)
        XCTAssertNil(model.draft?.deletedAt)
        XCTAssertTrue(model.canEdit)
    }

    func testReviewAfterParentRestorationReadsLatestEntryWithoutChangingItsRecoveryState() async throws {
        let (model, store, journal, entry) = try await fixture()
        let plan = try await model.prepareEntryRestoration(entry.id, journalID: journal.id)
        _ = try await store.restoreJournal(journal.id)
        var latest = entry
        latest.document = .plain("New writing received after the confirmation opened")
        try await store.save(latest)
        do {
            _ = try await model.restoreEntryAndJournal(plan)
            XCTFail("An already restored parent requires review of the remaining entry state.")
        } catch EntryRestorationError.alreadyRestored {}
        let before = try await store.items()
        let pending = try await store.pending()
        try await model.reviewRestoredEntry(entry.id)
        XCTAssertEqual(model.selectedID, entry.id)
        XCTAssertEqual(model.draft?.document, latest.document)
        XCTAssertEqual(model.draft?.deletedAt, entry.deletedAt)
        XCTAssertEqual(model.draft?.archivedAt, entry.archivedAt)
        XCTAssertTrue(model.showingTrash)
        let after = try await store.items()
        let afterPending = try await store.pending()
        XCTAssertEqual(after, before)
        XCTAssertEqual(afterPending.map(\.operationId), pending.map(\.operationId))
        XCTAssertEqual(afterPending.map(\.payload), pending.map(\.payload))
    }

    private func fixture() async throws -> (AppModel, JournalStore, JournalItem, JournalItem) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var journal = JournalItem(kind: "journal", title: "Work", date: date)
        journal.deletedAt = date
        var entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Recovered work", document: .plain("Keep this writing"),
            date: date)
        entry.archivedAt = date
        entry.deletedAt = date
        try await store.save(journal)
        try await store.save(entry)
        let model = AppModel(directory: root)
        model.store = store
        model.items = [journal, entry]
        model.draft = entry
        model.selectedID = entry.id
        model.selectedJournalID = journal.id
        model.showingTrash = true
        model.configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: "Disposable recovery fixture").0)
        return (model, store, journal, entry)
    }
}
