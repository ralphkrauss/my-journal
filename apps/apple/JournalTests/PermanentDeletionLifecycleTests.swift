import JournalCore
import XCTest

@testable import Journal

@MainActor
final class PermanentDeletionLifecycleTests: XCTestCase {
    func testLockAfterDeletionCommitCannotFlushDeletedDraftBackToStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock { try await store.close() }
        let journal = JournalItem(kind: "journal", title: "Personal")
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: "Deleted draft")
        entry.deletedAt = Date()
        try await store.save(journal)
        try await store.save(entry)
        let model = AppModel(directory: root)
        model.store = store
        model.items = [journal, entry]
        model.draft = entry
        model.selectedID = entry.id
        model.selectedJournalID = journal.id
        model.configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: "Disposable test recovery").0)
        await model.turnOnAppLockForTesting()
        let confirmation = try await model.preparePermanentDeletion(entry.id)
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let deleting = Task {
            try await model.commitDeletionMutation {
                let marker = try await store.permanentlyDelete(confirmation)
                committed.continuation.yield(())
                committed.continuation.finish()
                for await _ in release.stream { break }
                return marker
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        _ = try await deleting.value
        await locking.value
        XCTAssertNil(model.draft)
        XCTAssertNil(model.selectedID)
        XCTAssertTrue(model.items.isEmpty)
        let persisted = try await store.item(entry.id)
        XCTAssertEqual(persisted?.isPermanentlyDeleted, true)
        XCTAssertFalse(model.saveFailure)
    }

    func testChangedDeletionScopeIsRefusedWithoutClearingSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock { try await store.close() }
        var journal = JournalItem(kind: "journal", title: "Personal", date: Date(timeIntervalSince1970: 1_700_000_000))
        journal.deletedAt = journal.date
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Retain this entry")
        try await store.save(journal)
        try await store.save(entry)
        let model = AppModel(directory: root)
        model.store = store
        model.items = [journal, entry]
        model.draft = entry
        model.selectedID = entry.id
        let confirmation = try await model.preparePermanentDeletion(journal.id)
        let arriving = JournalItem(kind: "entry", journalID: journal.id, title: "Newly arrived")
        try await store.save(arriving)
        do {
            _ = try await model.permanentlyDelete(confirmation)
            XCTFail("Changed membership requires a new review.")
        } catch PermanentDeletionError.changed {}
        XCTAssertEqual(model.draft, entry)
        XCTAssertEqual(model.selectedID, entry.id)
        XCTAssertFalse(model.replacingVault)
        let persisted = try await store.item(journal.id)
        XCTAssertEqual(persisted, journal)
        model.locked = true
        do {
            _ = try await model.preparePermanentDeletion(journal.id)
            XCTFail("A locked model must not publish a deletion preview.")
        } catch JournalError.locked {}
    }
}
