import XCTest

@testable import JournalCore

/// Plain Restore (docs/design/1-1-library-simplifications.md, N): `restoreEntry(_:fallback:)` decides the destination
/// inside one transaction, so what the control named when it was drawn can't move an entry somewhere unexpected.
final class RestoreEntryTests: ConflictTestCase {
    private func deleted(_ item: JournalItem, in store: JournalStore) async throws -> JournalItem {
        var copy = item
        copy.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save(copy)
        return copy
    }
    private func deleteJournal(_ id: UUID, in store: JournalStore) async throws {
        _ = try await store.deleteJournal(try await store.prepareJournalDeletion(id))
    }

    func testAnEntryWhoseJournalIsInUseGoesHomeWithItsPinAndNothingElseChanges() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let sibling = entry("Sibling", text: "stays", journal: home.id)
        let draft = entry("Draft", text: "text", journal: home.id)
        let fallback = journal("Default")
        for item in [home, sibling, draft, fallback] { try await settle(item, in: store) }
        try await store.setPinned(true, entry: draft.id)
        _ = try await deleted(draft, in: store)
        let siblingBefore = try await store.item(sibling.id)

        let result = try await store.restoreEntry(draft.id, fallback: fallback.id)
        XCTAssertTrue(result.returnedToOwnJournal)
        XCTAssertEqual(result.journal.id, home.id)
        XCTAssertNil(result.entry.deletedAt)
        XCTAssertEqual(result.entry.document.text, "text")
        let siblingAfter = try await store.item(sibling.id)
        XCTAssertEqual(siblingAfter, siblingBefore)
        let arrangement = try await store.libraryArrangement()
        XCTAssertTrue(arrangement.pinned.contains(draft.id), "A restored entry keeps its pin")
    }

    func testAnEntryUnderADeletedJournalGoesToTheFallbackAndTheJournalStaysDeleted() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let notes = entry("Notes", text: "inside", journal: work.id)
        let other = entry("Other", text: "also inside", journal: work.id)
        let fallback = journal("Default")
        for item in [work, notes, other, fallback] { try await settle(item, in: store) }
        try await deleteJournal(work.id, in: store)
        let otherBefore = try await store.item(other.id)
        let journalBefore = try await store.item(work.id)

        let result = try await store.restoreEntry(notes.id, fallback: fallback.id)
        XCTAssertFalse(result.returnedToOwnJournal)
        XCTAssertEqual(result.journal.id, fallback.id)
        XCTAssertEqual(result.entry.journalID, fallback.id)
        let journalAfter = try await store.item(work.id)
        XCTAssertEqual(journalAfter, journalBefore, "The deleted journal stays deleted and keeps its other entries")
        let otherAfter = try await store.item(other.id)
        XCTAssertEqual(otherAfter, otherBefore)
        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: result.entry), .journal)
    }

    func testALegacyEntryWhoseJournalIsMissingAndAParkedEntryWhoseJournalWasDeletedForGoodGoToTheFallback() async throws
    {
        let store = try await openStore()
        let fallback = journal("Default")
        try await settle(fallback, in: store)
        let gone = journal("Gone")
        var legacy = entry("Legacy", text: "an earlier version deleted this", journal: gone.id)
        legacy.deletedWithJournal = true
        legacy.deletedAt = Date(timeIntervalSince1970: 1_700_000_500)
        try await deliver(legacy, revision: 1, to: store)
        var parked = entry("Parked", text: "saved next to a deletion", journal: gone.id)
        parked.deletedAt = Date(timeIntervalSince1970: 1_700_000_600)
        try await deliver(parked, revision: 1, to: store)
        try await deliver(marker(for: gone), revision: 1, to: store)

        for item in [legacy, parked] {
            let snapshot = try await store.lifecycleSnapshot()
            let stored = try await self.stored(store, item.id)
            XCTAssertEqual(snapshot.location(of: stored), .unavailable(.missing))
            let result = try await store.restoreEntry(item.id, fallback: fallback.id)
            XCTAssertFalse(result.returnedToOwnJournal)
            XCTAssertEqual(result.entry.journalID, fallback.id)
            XCTAssertFalse(result.entry.deletedWithJournal)
            XCTAssertNil(result.entry.deletedAt)
        }
        let list = try await store.lifecycleSnapshot().items.filter { $0.kind == "entry" }
        XCTAssertEqual(Set(list.compactMap(\.journalID)), [fallback.id])
    }

    /// The control said "Restore to Default" because the journal was deleted; it came back before the tap.
    func testAJournalRestoredBetweenDrawingTheControlAndTappingSendsTheEntryHome() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let notes = entry("Notes", text: "inside", journal: work.id)
        let fallback = journal("Default")
        for item in [work, notes, fallback] { try await settle(item, in: store) }
        try await deleteJournal(work.id, in: store)
        _ = try await store.restoreJournal(work.id)
        let result = try await store.restoreEntry(notes.id, fallback: fallback.id)
        XCTAssertTrue(result.returnedToOwnJournal)
        XCTAssertEqual(result.entry.journalID, work.id)
    }

    func testRestoreIsRefusedWithoutWritingWhenNothingCanTakeTheEntry() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let notes = entry("Notes", text: "inside", journal: work.id)
        let fallback = journal("Default")
        for item in [work, notes, fallback] { try await settle(item, in: store) }
        try await deleteJournal(work.id, in: store)
        try await deleteJournal(fallback.id, in: store)
        let before = try await store.items()
        let pendingBefore = try await store.pending().map(\.operationId)
        for destination in [nil, fallback.id, UUID()] {
            do {
                _ = try await store.restoreEntry(notes.id, fallback: destination)
                XCTFail("Nothing is available to restore into")
            } catch JournalLifecycleError.destinationGone {}
        }
        let after = try await store.items()
        XCTAssertEqual(
            after.sorted { $0.id.uuidString < $1.id.uuidString }, before.sorted { $0.id.uuidString < $1.id.uuidString })
        let pendingAfter = try await store.pending().map(\.operationId)
        XCTAssertEqual(pendingAfter, pendingBefore, "Nothing was written")
    }

    func testRestoreIsRefusedForANewerVersionOrAConflictAndForAnEntryThatIsNotDeletedWithNoJournal() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let notes = entry("Notes", text: "inside", journal: work.id)
        let fallback = journal("Default")
        for item in [work, notes, fallback] { try await settle(item, in: store) }
        try await deleteJournal(work.id, in: store)
        // The entry's journal was saved by a newer version of the app.
        let current = try await stored(store, work.id)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: PortableRecord.encode(current)) as? [String: Any])
        object["futureRules"] = ["hidden": true]
        let future = RemoteChange(
            cursor: 20, recordId: work.id, revision: 3, kind: "journal",
            payload: try VaultCrypto.seal(
                try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), key: key,
                context: VaultCrypto.recordContext(id: work.id, kind: "journal")
            ).base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
        try await store.apply([future], cursor: 20)
        do {
            _ = try await store.restoreEntry(notes.id, fallback: fallback.id)
            XCTFail("Moving an entry out of a journal this version can't read is not offered")
        } catch JournalLifecycleError.unsupportedJournal {}

        // An entry under review is refused.
        var edited = notes
        edited.document = .plain("edited here")
        try await store.save(edited)
        var elsewhere = notes
        elsewhere.document = .plain("edited there")
        try await deliver(elsewhere, revision: 2, to: store)
        do {
            _ = try await store.restoreEntry(notes.id, fallback: fallback.id)
            XCTFail("An entry with changes to review is not restored")
        } catch JournalLifecycleError.conflict {}

        // A live entry whose journal is missing has nothing of its own to restore.
        let orphan = entry("Orphan", text: "no journal", journal: UUID())
        try await deliver(orphan, revision: 1, to: store)
        do {
            _ = try await store.restoreEntry(orphan.id, fallback: fallback.id)
            XCTFail("Nothing of its own is deleted")
        } catch JournalLifecycleError.missingJournal {}
    }

    // MARK: Agent scope

    /// A restored entry follows the grants of the journal it lands in, exactly as a moved entry does.
    func testARestoredEntryIsReadableByTheGrantOfItsNewJournalAndNoLongerByTheOldOne() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let notes = entry("Notes", text: "readable text", journal: work.id)
        let fallback = journal("Default")
        let stays = entry("Stays", text: "stays put", journal: work.id)
        for item in [work, notes, fallback, stays] { try await settle(item, in: store) }
        try await store.apply([], cursor: 5)

        func readable(by journals: Set<UUID>) async throws -> Set<UUID> {
            let source = try await store.agentCopySource()
            let keys = try AgentCopyKeys(VaultCrypto.random(32))
            let settings = AgentCopySettings(
                name: "Claude", clientName: "Claude Code", journalIDs: journals, expiresAt: nil, key: Data())
            let grant = UUID()
            let uploads = try AgentCopyPlan(settings: settings, keys: keys, grantID: grant, source: source)
                .changes(comparedWith: [:])
            let items = try uploads.compactMap { upload in
                try upload.payload.map { try AgentCopyCrypto.open($0, itemID: upload.id, grantID: grant, keys: keys) }
            }
            return Set(items.map(\.id))
        }
        // Acknowledge everything so the publisher sees settled records.
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 6, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        let beforeWork = try await readable(by: [work.id])
        XCTAssertTrue(beforeWork.contains(notes.id))
        try await deleteJournal(work.id, in: store)
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 7, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        let deletedWork = try await readable(by: [work.id])
        XCTAssertFalse(deletedWork.contains(notes.id), "An entry in Recently Deleted is never readable by an agent")

        _ = try await store.restoreEntry(notes.id, fallback: fallback.id)
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 8, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        let atDestination = try await readable(by: [fallback.id])
        let atOldJournal = try await readable(by: [work.id])
        XCTAssertTrue(atDestination.contains(notes.id), "A grant on the destination sees the entry")
        XCTAssertFalse(atOldJournal.contains(notes.id), "A grant on the old journal no longer does")
    }

    func testAnEntryRestoredInPlaceIsPublishedAsBefore() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let draft = entry("Draft", text: "readable", journal: home.id)
        for item in [home, draft] { try await settle(item, in: store) }
        _ = try await deleted(draft, in: store)
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 3, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        _ = try await store.restoreEntry(draft.id, fallback: nil)
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 4, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        let source = try await store.agentCopySource()
        let keys = try AgentCopyKeys(VaultCrypto.random(32))
        let settings = AgentCopySettings(
            name: "Claude", clientName: "Claude Code", journalIDs: [home.id], expiresAt: nil, key: Data())
        let uploads = try AgentCopyPlan(settings: settings, keys: keys, grantID: UUID(), source: source)
            .changes(comparedWith: [:])
        XCTAssertTrue(uploads.contains { $0.id == keys.itemID(recordID: draft.id) && $0.payload != nil })
    }
}
