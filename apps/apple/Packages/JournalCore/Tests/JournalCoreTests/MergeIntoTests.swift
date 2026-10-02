import XCTest

@testable import JournalCore

/// Merge Into… moves every entry of one journal into another (docs/design/journal-name-uniqueness.md §5).
final class MergeIntoTests: XCTestCase {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MergeInto-" + UUID().uuidString)
    var key = Data()

    override func setUpWithError() throws { key = try VaultCrypto.generateKey() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func device(_ server: MergeServer) async throws -> (JournalStore, SyncEngine) {
        let store = try JournalStore(directory: root.appendingPathComponent(UUID().uuidString), key: key)
        let engine = SyncEngine(store: store, server: server)
        try await engine.synchronize()
        return (store, engine)
    }

    func testMergingAJournalMovesEveryEntryOrNothing() async throws {
        let (store, _) = try await device(MergeServer())
        let kept = try await store.save(JournalItem(kind: "journal", title: "Default"))
        let merged = try await store.save(JournalItem(kind: "journal", title: "Default 2"))
        let live = try await store.save(JournalItem(kind: "entry", journalID: merged.id, title: "Live"))
        var archived = JournalItem(kind: "entry", journalID: merged.id, title: "Archived")
        archived.archivedAt = Date(timeIntervalSince1970: 1_000)
        archived = try await store.save(archived)
        var deleted = JournalItem(kind: "entry", journalID: merged.id, title: "Deleted")
        deleted.deletedAt = Date(timeIntervalSince1970: 2_000)
        deleted = try await store.save(deleted)
        var withJournal = JournalItem(kind: "entry", journalID: merged.id, title: "Deleted with its journal")
        withJournal.deletedAt = Date(timeIntervalSince1970: 3_000)
        withJournal.deletedWithJournal = true
        withJournal = try await store.save(withJournal)
        let elsewhere = try await store.save(JournalItem(kind: "entry", journalID: kept.id, title: "Already there"))

        // A change to review in either journal or any entry stops it, with nothing changed.
        var edited = live
        edited.title = "Edited here"
        try await store.save(edited)
        var other = live
        other.title = "Edited elsewhere"
        _ = try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: live.id, revision: 1, kind: "entry", payload: try await store.encode(other),
                deviceId: UUID(), modifiedAt: Date()))
        do {
            _ = try await store.mergeJournal(merged.id, into: kept.id)
            XCTFail("A change to review stops the merge.")
        } catch JournalMergeError.conflict(let id) { XCTAssertEqual(id, live.id) }
        let untouched = try await store.item(archived.id)
        XCTAssertEqual(untouched?.journalID, merged.id)
        let review = try await store.conflicts()
        _ = try await store.resolve(XCTUnwrap(review.first), choice: .local)

        _ = try await store.mergeJournal(merged.id, into: kept.id)
        let items = try await store.items()
        func stored(_ entry: JournalItem) -> JournalItem? { items.first { $0.id == entry.id } }
        for entry in [live, archived, deleted, withJournal, elsewhere] {
            XCTAssertEqual(stored(entry)?.journalID, kept.id, entry.title)
        }
        XCTAssertEqual(stored(archived)?.archivedAt, archived.archivedAt, "Archived entries stay archived.")
        XCTAssertEqual(stored(deleted)?.deletedAt, deleted.deletedAt, "Recently Deleted keeps the deletion time.")
        XCTAssertEqual(stored(withJournal)?.deletedAt, withJournal.deletedAt)
        XCTAssertEqual(stored(withJournal)?.deletedWithJournal, true, "It stays in Recently Deleted.")
        let source = try XCTUnwrap(items.first { $0.id == merged.id })
        XCTAssertNotNil(source.deletedAt, "The merged journal moves to Recently Deleted.")
        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: try XCTUnwrap(stored(live))), .journal)
        XCTAssertEqual(snapshot.location(of: try XCTUnwrap(stored(deleted))), .recentlyDeleted)

        // The destination gone meanwhile, or the journal itself, refuses with nothing changed.
        let third = try await store.save(JournalItem(kind: "journal", title: "Work"))
        do {
            _ = try await store.mergeJournal(third.id, into: merged.id)
            XCTFail("A journal in Recently Deleted isn't a destination.")
        } catch JournalMergeError.destinationUnavailable {}
        do {
            _ = try await store.mergeJournal(merged.id, into: third.id)
            XCTFail("A journal in Recently Deleted can't be merged.")
        } catch JournalMergeError.sourceUnavailable {}
    }

    func testAnEntrySavedByANewerVersionStopsTheMerge() async throws {
        let (store, _) = try await device(MergeServer())
        let kept = try await store.save(JournalItem(kind: "journal", title: "Default"))
        let merged = try await store.save(JournalItem(kind: "journal", title: "Default 2"))
        let plain = try await store.save(JournalItem(kind: "entry", journalID: merged.id, title: "Plain"))
        let future = JournalItem(kind: "entry", journalID: merged.id, title: "From a newer version")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JournalCoding.encoder().encode(future)) as? [String: Any])
        object["futureEntryRules"] = ["kept": true]
        let sealed = try VaultCrypto.seal(
            JSONSerialization.data(withJSONObject: object), key: key,
            context: VaultCrypto.recordContext(id: future.id, kind: "entry"))
        try await store.apply(
            [
                RemoteChange(
                    cursor: 1, recordId: future.id, revision: 1, kind: "entry",
                    payload: sealed.base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
            ], cursor: 1)
        do {
            _ = try await store.mergeJournal(merged.id, into: kept.id)
            XCTFail("An entry this version can't change stops the whole merge.")
        } catch JournalMergeError.newerVersion {}
        let untouched = try await store.item(plain.id)
        XCTAssertEqual(untouched?.journalID, merged.id)
        let journal = try await store.item(merged.id)
        XCTAssertNil(journal?.deletedAt)
    }

    func testOfflineChangesToAMergedJournalAreKept() async throws {
        let server = MergeServer()
        let (mac, macSync) = try await device(server)
        let kept = try await mac.save(JournalItem(kind: "journal", title: "Default"))
        let merged = try await mac.save(JournalItem(kind: "journal", title: "Default 2"))
        let entry = try await mac.save(JournalItem(kind: "entry", journalID: merged.id, title: "Walk"))
        try await macSync.synchronize()
        let (phone, phoneSync) = try await device(server)

        // Offline on the phone: an edit to an entry that moves, and a new entry in the journal being merged.
        let phoneEntry = try await phone.item(entry.id)
        var edited = try XCTUnwrap(phoneEntry)
        edited.title = "Walk by the river"
        try await phone.save(edited)
        let written = try await phone.save(JournalItem(kind: "entry", journalID: merged.id, title: "Written offline"))

        _ = try await mac.mergeJournal(merged.id, into: kept.id)
        try await macSync.synchronize()
        try await phoneSync.synchronize()
        try await macSync.synchronize()

        let reviews = try await phone.conflicts()
        XCTAssertEqual(reviews.map(\.id), [entry.id], "The offline edit becomes a change to review, not lost.")
        let items = try await mac.items()
        let snapshot = try await mac.lifecycleSnapshot()
        let arrived = try XCTUnwrap(items.first { $0.id == written.id })
        XCTAssertEqual(
            snapshot.location(of: arrived), .recentlyDeleted, "It arrives with its journal, in Recently Deleted.")
        let moved = try XCTUnwrap(items.first { $0.id == entry.id })
        XCTAssertEqual(moved.journalID, kept.id)
    }
}
