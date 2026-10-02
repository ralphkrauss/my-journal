import XCTest

@testable import JournalCore

final class PermanentDeletionPlanTests: XCTestCase {
    func testJournalConfirmationIncludesAllCurrentChildrenAndRejectsChangedContentOrMembership() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        var journal = JournalItem(kind: "journal", title: "Deleted journal")
        journal.deletedAt = Date()
        let other = JournalItem(kind: "journal", title: "Other journal")
        var child = JournalItem(kind: "entry", journalID: journal.id, title: "Inherited deletion")
        var independent = JournalItem(kind: "entry", journalID: journal.id, title: "Independent deletion")
        independent.deletedAt = Date()
        var moved = JournalItem(kind: "entry", journalID: other.id, title: "Moved entry")
        for item in [journal, other, child, independent, moved] { try await store.save(item) }
        let initial = try await store.lifecycleSnapshot()
        let plan = try PermanentDeletionPlan.prepare(recordID: journal.id, snapshot: initial)
        XCTAssertEqual(plan.entryCount, 2)
        moved.title = "Unrelated edit"
        try await store.save(moved)
        try plan.validate(snapshot: await store.lifecycleSnapshot())
        child.document = .plain("A newly edited thought must be reviewed")
        try await store.save(child)
        let edited = try await store.lifecycleSnapshot()
        XCTAssertThrowsError(try plan.validate(snapshot: edited)) { error in
            XCTAssertEqual(error as? PermanentDeletionError, .changed)
        }
        let updated = try PermanentDeletionPlan.prepare(recordID: journal.id, snapshot: edited)
        moved.journalID = journal.id
        try await store.save(moved)
        let expanded = try await store.lifecycleSnapshot()
        XCTAssertThrowsError(try updated.validate(snapshot: expanded)) { error in
            XCTAssertEqual(error as? PermanentDeletionError, .changed)
        }
        var remote = independent
        remote.title = "Unreviewed remote edit"
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(remote), key: key,
            context: VaultCrypto.recordContext(id: remote.id, kind: remote.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: remote.id, revision: 1, kind: remote.kind,
                payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
        let conflicted = try await store.lifecycleSnapshot()
        XCTAssertThrowsError(try PermanentDeletionPlan.prepare(recordID: journal.id, snapshot: conflicted)) { error in
            XCTAssertEqual(error as? PermanentDeletionError, .conflict(independent.id))
        }
        let pending = try await store.pending()
        XCTAssertEqual(Set(pending.map(\.recordID)), Set([journal.id, other.id, child.id, moved.id]))
        try await store.close()
    }

    func testEntryConfirmationRequiresDeletedAvailabilityAndRejectsRestoration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        var journal = JournalItem(kind: "journal", title: "Journal")
        journal.deletedAt = Date()
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Entry")
        try await store.save(journal)
        try await store.save(entry)
        let deleted = try await store.lifecycleSnapshot()
        let plan = try PermanentDeletionPlan.prepare(recordID: entry.id, snapshot: deleted)
        XCTAssertEqual(plan.entryCount, 1)
        _ = try await store.restoreJournal(journal.id)
        let restored = try await store.lifecycleSnapshot()
        XCTAssertThrowsError(try plan.validate(snapshot: restored)) { error in
            XCTAssertEqual(error as? PermanentDeletionError, .notDeleted)
        }
        var orphan = entry
        orphan.journalID = UUID()
        orphan.deletedAt = Date()
        try await store.save(orphan)
        let unavailable = try await store.lifecycleSnapshot()
        XCTAssertThrowsError(try PermanentDeletionPlan.prepare(recordID: entry.id, snapshot: unavailable)) { error in
            XCTAssertEqual(error as? PermanentDeletionError, .missing)
        }
        try await store.close()
    }
}
