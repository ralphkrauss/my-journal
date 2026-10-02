import GRDB
import XCTest

@testable import JournalCore

final class PermanentDeletionTransactionTests: XCTestCase {
    func testJournalDeletionRetainsExcludedHistorySharedImagesAndImmutableRetry() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = fixture.store
        let orphan = JournalItem(kind: "entry", journalID: fixture.journal.id, title: "Historical only")
        try await fixture.addHistory(orphan)
        try await fixture.addHistory(fixture.entry)
        var movedHistory = fixture.moved
        movedHistory.journalID = fixture.journal.id
        try await fixture.addHistory(movedHistory)
        let confirmation = try await store.preparePermanentDeletion(fixture.journal.id)
        XCTAssertEqual(confirmation.plan.entryCount, 2)
        XCTAssertEqual(confirmation.historicalOnlyEntryCount, 1)
        let pending = try await store.pending()
        let retry = try XCTUnwrap(pending.first { $0.recordID == fixture.entry.id })
        let marker = try await store.permanentlyDelete(confirmation)
        XCTAssertTrue(marker.isCanonicalDeletionMarker)
        let after = try await store.items()
        XCTAssertEqual(after.filter(\.isPermanentlyDeleted).count, 3)
        XCTAssertEqual(after.first { $0.id == fixture.moved.id }?.title, fixture.moved.title)
        let history = try await store.history(for: fixture.entry.id)
        XCTAssertTrue(history.isEmpty)
        let excluded = try await store.history(for: orphan.id)
        XCTAssertEqual(excluded.first?.title, orphan.title)
        let retainedMovedHistory = try await store.history(for: fixture.moved.id)
        XCTAssertEqual(retainedMovedHistory.first?.journalID, fixture.journal.id)
        let image = try await store.attachment(fixture.imageID)
        XCTAssertEqual(image, fixture.image)
        let pendingAfter = try await store.pending()
        let unchanged = try XCTUnwrap(pendingAfter.first { $0.recordID == retry.recordID })
        XCTAssertEqual(unchanged.operationId, retry.operationId)
        XCTAssertEqual(unchanged.payload, retry.payload)
        XCTAssertEqual(unchanged.baseRevision, retry.baseRevision)
        let receipt = RemoteChange(
            cursor: 1, recordId: retry.recordID, revision: 1, kind: retry.kind,
            payload: retry.payload, deviceId: UUID(), modifiedAt: Date())
        try await store.acknowledge(retry, receipt: receipt)
        let nextPending = try await store.pending()
        let next = try XCTUnwrap(nextPending.first { $0.recordID == retry.recordID })
        XCTAssertNotEqual(next.operationId, retry.operationId)
        XCTAssertNotEqual(next.payload, retry.payload)
        XCTAssertEqual(next.baseRevision, 1)
        try await store.apply([receipt], cursor: 1)
        let retained = try await store.item(fixture.entry.id)
        XCTAssertEqual(retained?.isPermanentlyDeleted, true)
        try await store.close()
    }

    func testChangedRecoveryScopeAndDifferentStoreRefuseDestructiveConsent() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let beforeHistory = try await fixture.store.preparePermanentDeletion(fixture.journal.id)
        try await fixture.addHistory(fixture.entry)
        do {
            try await fixture.store.permanentlyDelete(beforeHistory)
            XCTFail("New recovery versions require refreshed consent.")
        } catch PermanentDeletionError.changed {}
        let beforeOrphan = try await fixture.store.preparePermanentDeletion(fixture.journal.id)
        try await fixture.addHistory(JournalItem(kind: "entry", journalID: fixture.journal.id, title: "Earlier notes"))
        do {
            try await fixture.store.permanentlyDelete(beforeOrphan)
            XCTFail("A new excluded historical identity changes the warning scope.")
        } catch PermanentDeletionError.changed {}
        let current = try await fixture.store.preparePermanentDeletion(fixture.journal.id)
        let clonePath = fixture.root.appendingPathComponent("clone")
        try await fixture.store.snapshot(to: clonePath)
        let clone = try JournalStore(directory: clonePath, key: fixture.key)
        do {
            try await clone.permanentlyDelete(current)
            XCTFail("Consent must be bound to the store that was reviewed.")
        } catch PermanentDeletionError.changed {}
        let items = try await fixture.store.items()
        XCTAssertFalse(items.contains(where: \.isPermanentlyDeleted))
        try await clone.close()
        try await fixture.store.close()
    }

    func testMidTransactionFailureRollsBackMarkersHistoryAndOutbox() async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await fixture.addHistory(fixture.journal)
        let confirmation = try await fixture.store.preparePermanentDeletion(fixture.journal.id)
        let records = try await fixture.store.items()
        let pending = try await fixture.store.pending()
        let history = try await fixture.store.history(for: fixture.journal.id)
        let database = try DatabaseQueue(path: fixture.root.appendingPathComponent("source/journal.sqlite").path)
        // The journal sorts first; fail the next record after its marker/history writes have executed.
        try await database.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_deletion BEFORE UPDATE ON records
                    WHEN NEW.id='00000000-0000-0000-0000-000000000002'
                    BEGIN SELECT RAISE(ABORT, 'Injected write failure'); END
                    """)
        }
        do {
            try await fixture.store.permanentlyDelete(confirmation)
            XCTFail("The injected failure must abort the entire destructive transaction.")
        } catch is DatabaseError {}
        let after = try await fixture.store.items()
        let afterPending = try await fixture.store.pending()
        let afterHistory = try await fixture.store.history(for: fixture.journal.id)
        XCTAssertEqual(after, records)
        XCTAssertEqual(afterPending.map(\.operationId), pending.map(\.operationId))
        XCTAssertEqual(afterPending.map(\.payload), pending.map(\.payload))
        XCTAssertEqual(afterHistory, history)
        try database.close()
        try await fixture.store.close()
    }

    private struct Fixture {
        let root: URL
        let key: Data
        let store: JournalStore
        let journal: JournalItem
        let entry: JournalItem
        let moved: JournalItem
        let imageID: UUID
        let image: Data
        static func make() async throws -> Self {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let key = try VaultCrypto.generateKey()
            let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
            var journal = JournalItem(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
                kind: "journal", title: "Deleted journal")
            journal.deletedAt = Date()
            let live = JournalItem(kind: "journal", title: "Other journal")
            let image = Data("Shared image bytes".utf8)
            let imageID = try await store.addAttachment(image)
            let document = JournalDocument(blocks: [DocumentBlock(kind: "image", attachmentID: imageID)])
            let entry = JournalItem(
                id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
                kind: "entry", journalID: journal.id, title: "Included", document: document)
            var independent = JournalItem(kind: "entry", journalID: journal.id, title: "Independently deleted")
            independent.deletedAt = Date()
            let moved = JournalItem(kind: "entry", journalID: live.id, title: "Moved elsewhere", document: document)
            for record in [journal, live, entry, independent, moved] { try await store.save(record) }
            return Self(
                root: root, key: key, store: store, journal: journal, entry: entry, moved: moved,
                imageID: imageID, image: image)
        }
        func addHistory(_ item: JournalItem) async throws {
            let payload = try VaultCrypto.seal(
                PortableRecord.encode(item), key: key,
                context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
            ).base64EncodedString()
            let database = try DatabaseQueue(path: root.appendingPathComponent("source/journal.sqlite").path)
            try await database.write { db in
                try db.execute(
                    sql: "INSERT INTO history(record,kind,payload,saved) VALUES (?,?,?,?)",
                    arguments: [item.id.uuidString.lowercased(), item.kind, payload, "2026-09-20T12:00:00Z"])
            }
            try database.close()
        }
    }
}
