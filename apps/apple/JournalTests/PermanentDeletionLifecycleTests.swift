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

    /// Delete in the confirmation takes the row out of Recently Deleted at once, so it leaves with the list's animation
    /// as a deleted entry's row does; it used to stay until the library was read again, then vanish. A deletion
    /// that is refused brings the row back, and a stored one keeps it gone.
    func testConfirmedRowLeavesAtOnceAndComesBackWhenRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock { try await store.close() }
        var journal = JournalItem(kind: "journal", title: "Old", date: Date(timeIntervalSince1970: 1_700_000_000))
        journal.deletedAt = journal.date
        let live = JournalItem(kind: "journal", title: "Personal")
        var entry = JournalItem(kind: "entry", journalID: live.id, title: "Deleted entry")
        entry.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        for item in [journal, live, entry] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        try await model.refresh()
        model.showingTrash = true
        XCTAssertEqual(model.filteredDeletedJournals.map(\.id), [journal.id])
        XCTAssertEqual(model.entries.map(\.id), [entry.id])

        let refused = try await model.preparePermanentDeletion(journal.id)
        model.removePermanentlyDeletedFromLists(refused)
        XCTAssertTrue(model.filteredDeletedJournals.isEmpty)
        try await store.save(JournalItem(kind: "entry", journalID: journal.id, title: "Arrived meanwhile"))
        do {
            _ = try await model.permanentlyDeleteListed(refused)
            XCTFail("Changed membership requires a new review.")
        } catch PermanentDeletionError.changed {}
        XCTAssertEqual(model.filteredDeletedJournals.map(\.id), [journal.id])

        let confirmed = try await model.preparePermanentDeletion(entry.id)
        model.removePermanentlyDeletedFromLists(confirmed)
        XCTAssertTrue(model.entries.isEmpty)
        let refreshed = try await model.permanentlyDeleteListed(confirmed)
        XCTAssertTrue(refreshed)
        XCTAssertFalse(model.entries.contains { $0.id == entry.id })
        let stored = try await store.item(entry.id)
        XCTAssertEqual(stored?.isPermanentlyDeleted, true)
    }
}
