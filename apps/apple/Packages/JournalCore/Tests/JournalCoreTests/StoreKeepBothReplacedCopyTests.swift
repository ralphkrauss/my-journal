import GRDB
import XCTest

@testable import JournalCore

/// A copy that a later version of the other device replaced holds content that exists nowhere else, so it is never
/// dropped for a version of its own identity or a permanent deletion; what the device remembers about copies is
/// bounded; and one conflict that can't be opened or settled neither fails a read nor keeps a synchronization from
/// settling (protocol/conflicts.md, Copies and Parking).
extension StoreKeepBothTests {
    /// A copy this device made and has not sent, then replaced by a later version from the same device. Returns the
    /// copy as made first, which has the identity it keeps.
    private func unsentCopyThatWasReplaced(of page: JournalItem, in store: JournalStore) async throws -> JournalItem {
        let first = try await madeCopy(of: page, text: "theirs 1", revision: 2, device: mac, in: store)
        let current = try await stored(store, page.id)
        try await typing("mine 2", into: current, in: store)
        try await deliver(version(of: page, "theirs 2"), revision: 3, to: store, device: mac)
        _ = try await settleAfterPause(store)
        let replaced = try await stored(store, first.id)
        XCTAssertEqual(replaced.document.text, "theirs 2", "The later version took the copy")
        let queued = try await store.pending().filter { $0.recordID == first.id }
        XCTAssertEqual(queued.map(\.baseRevision), [0], "…and the copy was never sent")
        return first
    }
    private func entries(withText text: String, in store: JournalStore) async throws -> [JournalItem] {
        try await store.items().filter { $0.kind == "entry" && !$0.isPermanentlyDeleted && $0.document.text == text }
    }

    func testAReplacedUnsentCopyIsKeptWhenAVersionOfItsOwnIdentityArrives() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let copy = try await unsentCopyThatWasReplaced(of: page, in: store)

        // Another client wrote that copy too, with other words, and sent it first.
        let arriving = version(of: copy, "written elsewhere")
        try await store.recordConflict(try remote(arriving, revision: 1, cursor: 20, device: phone))
        let report = try await settleAfterPause(store)

        XCTAssertEqual(report.resolved.count, 1)
        let kept = try await entries(withText: "theirs 2", in: store)
        XCTAssertEqual(kept.map(\.id), [copy.id], "The words only the replaced copy held are still its own")
        let other = try await entries(withText: "written elsewhere", in: store)
        XCTAssertEqual(other.count, 1, "The arriving version is kept as a copy of its own")
        let sent = try await store.pending().filter { $0.recordID == copy.id }
        XCTAssertEqual(sent.map(\.baseRevision), [1], "The replaced copy is sent on top of the version that arrived")
    }

    func testAReplacedUnsentCopyMeetingAPermanentDeletionIsParkedNotDropped() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let copy = try await unsentCopyThatWasReplaced(of: page, in: store)

        try await store.recordConflict(try remote(marker(for: copy, at: 1_820_000_000), revision: 1, cursor: 20))
        _ = try await settleAfterPause(store)

        let record = try await stored(store, copy.id)
        XCTAssertTrue(record.isCanonicalDeletionMarker, "The deletion stays final")
        let parked = try await store.items().filter {
            $0.kind == "entry" && $0.deletedAt != nil && !$0.isPermanentlyDeleted && $0.document.text == "theirs 2"
        }
        XCTAssertEqual(parked.count, 1, "The replaced content is kept in Recently Deleted")
    }

    func testACopyHoldingWhatWasFirstWrittenIsStillDroppedForAMarker() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let copy = try await madeCopy(of: page, text: "theirs", revision: 2, device: mac, in: store)
        try await store.recordConflict(try remote(marker(for: copy, at: 1_820_000_000), revision: 1, cursor: 20))
        _ = try await settleAfterPause(store)
        let record = try await stored(store, copy.id)
        XCTAssertTrue(record.isCanonicalDeletionMarker)
        let parked = try await store.items().filter { $0.deletedAt != nil && !$0.isPermanentlyDeleted }
        XCTAssertTrue(parked.isEmpty, "Its content is in the other record, so nothing is parked")
    }

    func testAnAutomaticCopyWithoutTheMarksOfAnEarlierBuildIsNeverDropped() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let copy = try await madeCopy(of: page, text: "theirs", revision: 2, device: mac, in: store)
        // A value written before the kind and the replaced mark were recorded.
        let notes = await store.keptNotesStore
        try await store.db.write { db in
            var state = try notes.state(db)
            let json = try JSONEncoder().encode(state.copies)
            var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [[String: Any]])
            for index in objects.indices {
                objects[index].removeValue(forKey: "kind")
                objects[index].removeValue(forKey: "replaced")
            }
            state.copies = try JSONDecoder().decode(
                [KeptCopy].self, from: JSONSerialization.data(withJSONObject: objects))
            try notes.save(db, state)
        }
        let read = try await store.keptNotesState()
        XCTAssertEqual(read.copies.first?.kind, .unspecified)
        XCTAssertEqual(read.copies.first?.replaced, true, "Unknown history is treated as replaced")
        let arriving = version(of: copy, "written elsewhere")
        try await store.recordConflict(try remote(arriving, revision: 1, cursor: 20, device: phone))
        _ = try await settleAfterPause(store)
        let kept = try await entries(withText: "theirs", in: store)
        XCTAssertEqual(kept.map(\.id), [copy.id])
    }

    // MARK: Bounds on what the device remembers

    func testACopyForgottenBecauseTheListIsFullIsKeptWhenAVersionOfItsOwnIdentityArrives() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let copy = try await madeCopy(of: page, text: "theirs", revision: 2, device: mac, in: store)
        // 200 later copies push the oldest out of the list while this one is unsent.
        let notes = await store.keptNotesStore
        try await store.db.write { db in
            var state = try notes.state(db)
            for _ in 0..<KeptNotesState.copyLimit {
                state.remember(
                    KeptCopy(
                        copyID: UUID(), recordID: UUID(), kind: .copy, originDevice: nil, originRevision: 0,
                        digest: "0"))
            }
            try notes.save(db, state)
        }
        let known = try await store.keptNotesState()
        XCTAssertFalse(known.isAutomaticCopy(copy.id), "It was forgotten")
        XCTAssertEqual(known.copies.count, KeptNotesState.copyLimit)

        let arriving = version(of: copy, "written elsewhere")
        try await store.recordConflict(try remote(arriving, revision: 1, cursor: 20, device: phone))
        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.count, 1)
        let mine = try await entries(withText: "theirs", in: store)
        XCTAssertEqual(mine.map(\.id), [copy.id], "Nothing is replaced or dropped that the device no longer knows")
        let other = try await entries(withText: "written elsewhere", in: store)
        XCTAssertEqual(other.count, 1, "…and the version that arrived is kept")
    }

    func testAParkedEntryIsNeverReplacedByALaterVersionOfTheRecordItCameFrom() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let first = try await madeCopy(of: page, text: "theirs 1", revision: 2, device: mac, in: store)
        try await send(from: store)
        // The note says this entry is a parked one, as the settlement of an edit against a deletion records it.
        let notes = await store.keptNotesStore
        try await store.db.write { db in
            var state = try notes.state(db)
            state.copies = state.copies.map { entry in
                var changed = entry
                changed.kind = .parked
                return changed
            }
            try notes.save(db, state)
        }
        let current = try await stored(store, page.id)
        try await typing("mine 2", into: current, in: store)
        try await deliver(version(of: page, "theirs 2"), revision: 4, to: store, device: mac)
        _ = try await settleAfterPause(store)

        let parkedEntry = try await stored(store, first.id)
        XCTAssertEqual(parkedEntry.document.text, "theirs 1", "It is not a version of the record")
        let later = try await entries(withText: "theirs 2", in: store)
        XCTAssertEqual(later.count, 1, "The later version is a copy of its own")
    }

    // MARK: One conflict that can't be opened

    func testOneConflictThatCannotBeOpenedFailsNeitherTheSnapshotNorTheOthers() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let second = entry("Second", text: "first", journal: page.journalID)
        try await settle(second, in: store)
        try await typing("mine", into: page, in: store)
        try await typing("mine", into: try await stored(store, second.id), in: store)
        try await deliver(version(of: page, "theirs"), revision: 2, to: store, device: mac)
        try await deliver(version(of: second, "theirs"), revision: 2, to: store, device: mac)
        try await store.db.write { db in
            try db.execute(
                sql: "UPDATE conflicts SET payload='not a record' WHERE record=?",
                arguments: [page.id.uuidString.lowercased()])
        }

        let snapshot = try await store.viewSnapshot()
        XCTAssertEqual(snapshot.conflictedIDs, [page.id, second.id])
        XCTAssertTrue(snapshot.items.contains { $0.id == page.id }, "The library is read")
        let held = try await store.heldConflictIDs()
        XCTAssertEqual(held, [page.id], "A row that can't be opened is held; the other settles")
        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.map(\.recordID), [second.id])
        XCTAssertEqual(report.held, 1)
        let ids = try await store.conflictedIDs()
        XCTAssertEqual(ids, [page.id])
    }
}
