import GRDB
import XCTest

@testable import JournalCore

final class DeletionConflictTests: XCTestCase {
    func testKeepEntryConvergesOnlyForTheExplicitlyReviewedDeletion() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let review = try await fixture.store.prepareDeletionConflict(fixture.entry.id)
        let revived = try await fixture.store.resolveDeletionConflict(
            review, choice: .keepEntry(journalID: fixture.journal.id))
        XCTAssertEqual(revived.id, fixture.entry.id)
        XCTAssertEqual(revived.document, fixture.entry.document)
        XCTAssertEqual(revived.date, fixture.entry.date)
        XCTAssertEqual(revived.restoredFromDeletionID, fixture.marker.permanentDeletionID)
        let retained = try await fixture.store.history(for: revived.id)
        XCTAssertEqual(retained.count, 1)
        let peer = try JournalStore(directory: fixture.root.appendingPathComponent("peer"), key: fixture.key)
        try await peer.apply([fixture.remote(fixture.marker, revision: 1)], cursor: 1)
        try await peer.apply([fixture.remote(revived, revision: 4)], cursor: 4)
        let peerItem = try await peer.item(revived.id)
        XCTAssertEqual(peerItem, revived)
        let conflicts = try await peer.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        // Two deletions in the same second still have separate identities.
        let secondDeletion = JournalItem.permanentDeletionMarker(for: revived, at: fixture.marker.date)
        try await peer.apply([fixture.remote(secondDeletion, revision: 5)], cursor: 5)
        try await peer.apply([fixture.remote(revived, revision: 6)], cursor: 6)
        let guarded = try await peer.item(revived.id)
        XCTAssertEqual(guarded, secondDeletion)
        let staleRevival = try await peer.conflicts()
        XCTAssertEqual(staleRevival.count, 1)
        try await peer.close()
        try await fixture.store.close()
    }

    func testKeepCopyRetainsSourceHistoryAndImagesWithoutDuplicatingOnRetry() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let review = try await fixture.store.prepareDeletionConflict(fixture.entry.id)
        let copy = try await fixture.store.resolveDeletionConflict(
            review, choice: .keepEntryAsCopy(journalID: fixture.journal.id))
        XCTAssertNotEqual(copy.id, fixture.entry.id)
        XCTAssertEqual(copy.document, fixture.entry.document)
        XCTAssertEqual(copy.date, fixture.entry.date)
        XCTAssertEqual(copy.journalID, fixture.journal.id)
        XCTAssertNil(copy.restoredFromDeletionID)
        let original = try await fixture.store.item(fixture.entry.id)
        XCTAssertEqual(original, fixture.marker)
        let sourceHistory = try await fixture.store.history(for: fixture.entry.id)
        let copyHistory = try await fixture.store.history(for: copy.id)
        XCTAssertEqual(sourceHistory.count, 1)
        XCTAssertTrue(copyHistory.isEmpty)
        let image = try await fixture.store.attachment(fixture.imageID)
        XCTAssertEqual(image, fixture.image)
        do {
            _ = try await fixture.store.resolveDeletionConflict(
                review, choice: .keepEntryAsCopy(journalID: fixture.journal.id))
            XCTFail("Repeated confirmation cannot create a second copy.")
        } catch PermanentDeletionError.changed {}
        let items = try await fixture.store.items()
        XCTAssertEqual(items.filter { $0.kind == "entry" && !$0.isPermanentlyDeleted }.map(\.id), [copy.id])
        let pending = try await fixture.store.pending()
        XCTAssertEqual(Set(pending.map(\.recordID)), [copy.id, fixture.entry.id])
        try await fixture.store.close()
    }

    func testKeepDeletionRequiresFreshReviewAndPurgesOnlyAfterConfirmation() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let stale = try await fixture.store.prepareDeletionConflict(fixture.entry.id)
        var newer = fixture.entry
        newer.title = "Changed while reviewing"
        try await fixture.store.apply([fixture.remote(newer, revision: 4)], cursor: 4)
        do {
            _ = try await fixture.store.resolveDeletionConflict(stale, choice: .keepDeletion)
            XCTFail("A newer competing edit needs fresh destructive consent.")
        } catch PermanentDeletionError.changed {}
        let historyBefore = try await fixture.store.history(for: fixture.entry.id)
        XCTAssertEqual(historyBefore.count, 2)
        let review = try await fixture.store.prepareDeletionConflict(fixture.entry.id)
        let deleted = try await fixture.store.resolveDeletionConflict(review, choice: .keepDeletion)
        XCTAssertEqual(deleted, fixture.marker)
        let historyAfter = try await fixture.store.history(for: fixture.entry.id)
        let conflicts = try await fixture.store.conflicts()
        XCTAssertTrue(historyAfter.isEmpty)
        XCTAssertTrue(conflicts.isEmpty)
        let pending = try await fixture.store.pending()
        XCTAssertEqual(pending.first?.baseRevision, 4)
        try await fixture.store.close()
    }

    func testFailedCopyRollsBackResolutionAndKeepingJournalNeverRevivesChildren() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let review = try await fixture.store.prepareDeletionConflict(fixture.entry.id)
        let database = try DatabaseQueue(path: fixture.root.appendingPathComponent("source/journal.sqlite").path)
        try await database.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_copy BEFORE INSERT ON records WHEN NEW.kind='entry'
                    BEGIN SELECT RAISE(ABORT, 'Injected copy failure'); END
                    """)
        }
        do {
            _ = try await fixture.store.resolveDeletionConflict(
                review, choice: .keepEntryAsCopy(journalID: fixture.journal.id))
            XCTFail("A failed copy must retain the original conflict and marker.")
        } catch is DatabaseError {}
        let unchanged = try await fixture.store.prepareDeletionConflict(fixture.entry.id)
        XCTAssertEqual(unchanged.conflict, review.conflict)
        let pendingCount = try await database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox") }
        XCTAssertEqual(pendingCount, 0)
        try await database.write { try $0.execute(sql: "DROP TRIGGER fail_copy") }
        try database.close()
        let parentMarker = JournalItem.permanentDeletionMarker(for: fixture.journal, at: fixture.marker.date)
        try await fixture.store.apply([fixture.remote(parentMarker, revision: 2)], cursor: 4)
        var settings = fixture.journal
        settings.title = "Reviewed journal name"
        try await fixture.store.apply([fixture.remote(settings, revision: 3)], cursor: 5)
        let journalReview = try await fixture.store.prepareDeletionConflict(settings.id)
        let kept = try await fixture.store.resolveDeletionConflict(journalReview, choice: .keepJournal)
        XCTAssertEqual(kept.title, settings.title)
        XCTAssertEqual(kept.restoredFromDeletionID, parentMarker.permanentDeletionID)
        let child = try await fixture.store.item(fixture.entry.id)
        XCTAssertEqual(child, fixture.marker)
        let childConflicts = try await fixture.store.conflicts()
        XCTAssertEqual(childConflicts.map(\.id), [fixture.entry.id])
        try await fixture.store.close()
    }

    func testTwoDeletionMarkersRequireExplicitHistoryPurgeAndCannotRestoreMissingContent() async throws {
        let fixture = try await Fixture.make()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        addTeardownBlock { try await fixture.store.close() }
        let anotherMarker = JournalItem.permanentDeletionMarker(for: fixture.entry, at: fixture.marker.date)
        try await fixture.store.apply([fixture.remote(anotherMarker, revision: 4)], cursor: 4)
        let reviewed = try await fixture.store.prepareDeletionConflict(fixture.entry.id)
        XCTAssertNil(reviewed.edited)
        let history = try await fixture.store.history(for: fixture.entry.id)
        XCTAssertEqual(history.count, 2)
        do {
            _ = try await fixture.store.resolveDeletionConflict(
                reviewed, choice: .keepEntry(journalID: fixture.journal.id))
            XCTFail("Two markers cannot manufacture a recovered entry.")
        } catch PermanentDeletionError.changed {}
        let unchangedHistory = try await fixture.store.history(for: fixture.entry.id)
        XCTAssertEqual(unchangedHistory, history)
        let kept = try await fixture.store.resolveDeletionConflict(reviewed, choice: .keepDeletion)
        XCTAssertEqual(kept, fixture.marker)
        let purgedHistory = try await fixture.store.history(for: fixture.entry.id)
        XCTAssertTrue(purgedHistory.isEmpty)
        let conflicts = try await fixture.store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        let pending = try await fixture.store.pending()
        XCTAssertEqual(pending.first?.baseRevision, 4)
    }

    private struct Fixture {
        let root: URL
        let key: Data
        let store: JournalStore
        let journal: JournalItem
        let entry: JournalItem
        let marker: JournalItem
        let imageID: UUID
        let image: Data
        static func make() async throws -> Self {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let key = try VaultCrypto.generateKey()
            let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
            let journal = JournalItem(kind: "journal", title: "Destination")
            let image = Data("Image retained by reviewed entry".utf8)
            let imageID = try await store.addAttachment(image)
            let entry = JournalItem(
                kind: "entry", journalID: UUID(), title: "Reviewed edit",
                document: .init(blocks: [
                    DocumentBlock(runs: [TextRun("Keep every word", bold: true)]),
                    DocumentBlock(kind: "image", attachmentID: imageID),
                ]), date: Date(timeIntervalSince1970: 1_700_000_000))
            let marker = JournalItem.permanentDeletionMarker(for: entry, at: Date(timeIntervalSince1970: 1_800_000_000))
            let fixture = Self(
                root: root, key: key, store: store, journal: journal, entry: entry, marker: marker,
                imageID: imageID, image: image)
            try await store.apply(
                [fixture.remote(journal, revision: 1), fixture.remote(marker, revision: 1)], cursor: 1)
            var earlier = entry
            earlier.title = "Earlier conflicting edit"
            try await store.apply([fixture.remote(earlier, revision: 2)], cursor: 2)
            try await store.apply([fixture.remote(entry, revision: 3)], cursor: 3)
            return fixture
        }
        func remote(_ item: JournalItem, revision: Int64) throws -> RemoteChange {
            RemoteChange(
                cursor: revision, recordId: item.id, revision: revision, kind: item.kind,
                payload: try VaultCrypto.seal(
                    PortableRecord.encode(item), key: key,
                    context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
                ).base64EncodedString(),
                deviceId: UUID(), modifiedAt: item.modifiedAt)
        }
    }
}
