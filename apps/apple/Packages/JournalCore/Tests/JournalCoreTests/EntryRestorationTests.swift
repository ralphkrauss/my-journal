import GRDB
import XCTest

@testable import JournalCore

final class EntryRestorationTests: XCTestCase {
    func testRestoresCapturedEntryAndParentPreservingNewerContentSiblingsAndRetryBytes() async throws {
        let fixture = try await makeFixture()
        let store = fixture.store
        let plan = try await store.prepareEntryRestoration(fixture.entry.id, journalID: fixture.journal.id)
        XCTAssertEqual(plan.entryCount, 2)
        let before = try await store.pending()
        var edited = fixture.entry
        edited.document = .plain("A newer body must survive recovery")
        try await store.save(edited)
        let recovered = try await store.restoreEntryAndJournal(plan)
        XCTAssertEqual(recovered.document, edited.document)
        XCTAssertNil(recovered.deletedAt)
        XCTAssertFalse(recovered.deletedWithJournal)
        XCTAssertNil(recovered.archivedAt)
        let parent = try await store.item(fixture.journal.id)
        XCTAssertNil(parent?.deletedAt)
        let archivedSibling = try await store.item(fixture.archivedSibling.id)
        let deletedSibling = try await store.item(fixture.deletedSibling.id)
        XCTAssertEqual(archivedSibling, fixture.archivedSibling)
        XCTAssertEqual(deletedSibling, fixture.deletedSibling)
        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: recovered), .journal)
        // Archiving is no longer offered; an entry archived earlier shows in its journal again.
        XCTAssertEqual(snapshot.location(of: fixture.archivedSibling), .journal)
        XCTAssertEqual(snapshot.location(of: fixture.deletedSibling), .recentlyDeleted)
        let after = try await store.pending()
        XCTAssertEqual(after.map(\.operationId), before.map(\.operationId))
        XCTAssertEqual(after.map(\.payload), before.map(\.payload))
        do {
            _ = try await store.restoreEntryAndJournal(plan)
            XCTFail("Completed parent recovery must require a fresh entry review, not repeat the mutation.")
        } catch EntryRestorationError.alreadyRestored {}
    }

    func testChangedMembershipArchiveStateAndCrossStoreConsentCannotRestoreParent() async throws {
        let fixture = try await makeFixture()
        let store = fixture.store
        let plan = try await store.prepareEntryRestoration(fixture.entry.id, journalID: fixture.journal.id)
        let added = JournalItem(kind: "entry", journalID: fixture.journal.id, title: "Arrived after review")
        try await store.save(added)
        do {
            _ = try await store.restoreEntryAndJournal(plan)
            XCTFail("Changed parent membership requires review.")
        } catch EntryRestorationError.changed {}
        let refreshed = try await store.prepareEntryRestoration(fixture.entry.id, journalID: fixture.journal.id)
        var changed = fixture.entry
        changed.archivedAt = nil
        try await store.save(changed)
        do {
            _ = try await store.restoreEntryAndJournal(refreshed)
            XCTFail("Changed archive state must not silently change the reviewed recovery.")
        } catch EntryRestorationError.changed {}
        let latest = try await store.prepareEntryRestoration(fixture.entry.id, journalID: fixture.journal.id)
        let second = try JournalStore(directory: fixture.root, key: fixture.key)
        addTeardownBlock { try await second.close() }
        do {
            _ = try await second.restoreEntryAndJournal(latest)
            XCTFail("Consent belongs to the store instance that prepared it.")
        } catch EntryRestorationError.changed {}
        let retained = try await store.item(fixture.journal.id)
        XCTAssertNotNil(retained?.deletedAt)
    }

    func testSecondWriteFailureRollsBackParentEntryAndOutbox() async throws {
        let fixture = try await makeFixture()
        let store = fixture.store
        let plan = try await store.prepareEntryRestoration(fixture.entry.id, journalID: fixture.journal.id)
        let before = try await store.items()
        let pending = try await store.pending()
        let database = try DatabaseQueue(path: fixture.root.appendingPathComponent("journal.sqlite").path)
        addTeardownBlock { try database.close() }
        let entryID = fixture.entry.id.uuidString.lowercased()
        try await database.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_entry_restoration BEFORE UPDATE ON records
                    WHEN NEW.id='\(entryID)'
                    BEGIN SELECT RAISE(ABORT, 'Injected restoration failure'); END
                    """)
        }
        do {
            _ = try await store.restoreEntryAndJournal(plan)
            XCTFail("A failed entry save must also roll back the already written parent.")
        } catch is DatabaseError {}
        let after = try await store.items()
        let afterPending = try await store.pending()
        XCTAssertEqual(after, before)
        XCTAssertEqual(afterPending.map(\.operationId), pending.map(\.operationId))
        XCTAssertEqual(afterPending.map(\.payload), pending.map(\.payload))
    }

    private struct Fixture {
        let root: URL
        let key: Data
        let store: JournalStore
        let journal: JournalItem
        let entry: JournalItem
        let archivedSibling: JournalItem
        let deletedSibling: JournalItem
    }

    private func makeFixture() async throws -> Fixture {
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
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: "Selected", date: date)
        entry.deletedAt = date
        entry.archivedAt = date
        var archived = JournalItem(kind: "entry", journalID: journal.id, title: "Archived sibling", date: date)
        archived.archivedAt = date
        var deleted = JournalItem(kind: "entry", journalID: journal.id, title: "Deleted sibling", date: date)
        deleted.deletedAt = date
        for item in [journal, entry, archived, deleted] { try await store.save(item) }
        return Fixture(
            root: root, key: key, store: store, journal: journal, entry: entry,
            archivedSibling: archived, deletedSibling: deleted)
    }
}
