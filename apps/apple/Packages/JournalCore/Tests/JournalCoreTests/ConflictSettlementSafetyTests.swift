import GRDB
import XCTest

@testable import JournalCore

/// What settling a conflict does when a row can't be read, when a copy was edited meanwhile, and when a transaction
/// fails (protocol/conflicts.md, Orchestration and The rules), with real isolated stores.
final class ConflictSettlementSafetyTests: ConflictTestCase {
    // MARK: A row that can't be read

    /// Two journals are renamed on both devices; one conflict row is damaged, once as text and once as sealed bytes.
    private func journalsWithTwoDamagedRows(in store: JournalStore) async throws -> (good: JournalItem, bad: [UUID]) {
        let names = ["Good", "Damaged text", "Damaged seal"]
        var journals: [JournalItem] = []
        for name in names {
            let item = journal(name)
            try await settle(item, in: store)
            var mine = item
            mine.title = name + " here"
            try await store.save(mine)
            var theirs = item
            theirs.title = name + " there"
            try await deliver(theirs, revision: 2, to: store)
            journals.append(item)
        }
        let garbage = Data(repeating: 7, count: 64).base64EncodedString()
        for (item, payload) in zip(journals.dropFirst(), ["%% not base64 %%", garbage]) {
            try await store.db.write {
                try $0.execute(
                    sql: "UPDATE conflicts SET payload=? WHERE record=?",
                    arguments: [payload, item.id.uuidString.lowercased()])
            }
        }
        return (journals[0], journals.dropFirst().map(\.id))
    }

    func testOneUnreadableRowIsHeldAndTheGoodOnesStillSettle() async throws {
        let store = try await openStore()
        let (good, bad) = try await journalsWithTwoDamagedRows(in: store)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.map(\.recordID), [good.id], "The readable row settles")
        XCTAssertEqual(report.held, 2, "The damaged rows are held for a later round")
        let held = try await store.heldConflictIDs()
        XCTAssertEqual(held, Set(bad))
        let waiting = try await store.settledFactsAwaitConflict()
        XCTAssertFalse(waiting, "A damaged row is not waiting for a round")
    }

    func testASynchronizationFinishesAndSendsTheGoodRowBesideAnUnreadableOne() async throws {
        let server = MemoryServer()
        let first = try await openStore("first")
        let second = try await openStore("second")
        let firstSync = SyncEngine(store: first, server: server)
        let secondSync = SyncEngine(store: second, server: server)
        let good = journal("Good")
        let damaged = journal("Damaged")
        for item in [good, damaged] { try await first.save(item) }
        try await synchronize(firstSync)
        try await synchronize(secondSync)
        for (item, name) in [(good, "Good there"), (damaged, "Damaged there")] {
            var theirs = item
            theirs.title = name
            try await first.save(theirs)
        }
        try await synchronize(firstSync)
        for (item, name) in [(good, "Good here"), (damaged, "Damaged here")] {
            var mine = item
            mine.title = name
            try await second.save(mine)
        }
        // The conflicts are made but not settled in this round.
        time.withLock { $0 = $0.addingTimeInterval(3) }
        try await secondSync.synchronize(SyncEngine.Request(holdingConflicts: [good.id, damaged.id]))
        let rows = try await second.conflicts()
        XCTAssertEqual(Set(rows.map(\.id)), [good.id, damaged.id])
        try await second.db.write {
            try $0.execute(
                sql: "UPDATE conflicts SET payload='%% not base64 %%' WHERE record=?",
                arguments: [damaged.id.uuidString.lowercased()])
        }

        time.withLock { $0 = $0.addingTimeInterval(3) }
        let report = try await secondSync.synchronize()
        XCTAssertEqual(report.resolvedConflicts.map(\.recordID), [good.id])
        let settled = try await stored(second, good.id)
        XCTAssertEqual(settled.title, "Good here")
        let sent = await server.record(good.id)
        XCTAssertEqual(sent?.revision, 3, "The settled row went out in the same round")
        let remaining = try await second.heldConflictIDs()
        XCTAssertEqual(remaining, [damaged.id])
    }

    private func synchronize(_ engine: SyncEngine) async throws {
        time.withLock { $0 = $0.addingTimeInterval(3) }
        try await engine.synchronize()
    }

    // MARK: A copy this device made and has not sent

    /// An entry edited here while another device deleted it for good is parked, then edited again before it is sent.
    private func parkedThenEdited(in store: JournalStore) async throws -> (parkedID: UUID, edited: JournalItem) {
        let home = journal("Home")
        let draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        var typed = draft
        typed.document = .plain("words")
        try await store.save(typed)
        try await deliver(marker(for: draft), revision: 2, to: store)
        let report = try await settleAfterPause(store)
        guard case .deletedAndChanged(let parkedID?) = try XCTUnwrap(report.resolved.first).result else {
            XCTFail("The edit was not parked")
            return (UUID(), draft)
        }
        var edited = try await stored(store, parkedID)
        edited.document = .plain("words, and more typed after it was parked")
        try await store.save(edited)
        return (parkedID, edited)
    }

    func testAnEditedUnsentParkedEntryIsKeptWhenAnotherVersionOfItArrives() async throws {
        let store = try await openStore()
        let (parkedID, edited) = try await parkedThenEdited(in: store)
        var theirs = edited
        theirs.document = .plain("words")
        theirs.modifiedAt = Date(timeIntervalSince1970: 1_800_000_500)
        try await store.recordConflict(try remote(theirs, revision: 1, cursor: 9))

        let report = try await settleAfterPause(store)
        XCTAssertTrue(report.resolved.isEmpty, "Edits are not decided by a rule that drops them")
        let record = try await stored(store, parkedID)
        XCTAssertEqual(record.document.text, "words, and more typed after it was parked")
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.map(\.id), [parkedID], "The two versions wait for the person")
    }

    func testAnEditedUnsentParkedEntryMeetingADeletionIsParkedAgainNotDropped() async throws {
        let store = try await openStore()
        let (parkedID, edited) = try await parkedThenEdited(in: store)
        try await store.recordConflict(try remote(marker(for: edited, at: 1_820_000_000), revision: 1, cursor: 9))

        let report = try await settleAfterPause(store)
        guard case .deletedAndChanged(let again?) = try XCTUnwrap(report.resolved.first).result else {
            return XCTFail("The typed words were dropped")
        }
        XCTAssertNotEqual(again, parkedID)
        let saved = try await stored(store, again)
        XCTAssertEqual(saved.document.text, "words, and more typed after it was parked")
        let record = try await stored(store, parkedID)
        XCTAssertTrue(record.isCanonicalDeletionMarker, "The deletion is still final")
    }

    // MARK: A permanent deletion made here against several edits

    func testSeveralRevisionsPulledAgainstALocalPermanentDeletionLeaveNoHistory() async throws {
        let store = try await openStore()
        let home = journal("Home")
        var draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        draft.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save(draft)
        let deletion = try await store.permanentlyDelete(try await store.preparePermanentDeletion(draft.id))
        for (revision, text) in [(Int64(2), "second"), (3, "third")] {
            var elsewhere = entry("Draft", text: text, journal: home.id)
            elsewhere.id = draft.id
            try await deliver(elsewhere, revision: revision, to: store)
        }
        let before = try await store.history(for: draft.id)
        XCTAssertEqual(before.count, 1, "The earlier revision was set aside by the pull")

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.parked.count, 1)
        let record = try await stored(store, draft.id)
        XCTAssertEqual(record, deletion)
        let after = try await store.history(for: draft.id)
        XCTAssertTrue(after.isEmpty, "A permanent deletion removes every earlier version")
    }

    // MARK: The one-time pass

    private func renamedOnTwoDevices(_ name: String, in store: JournalStore, revision: Int64 = 2) async throws
        -> JournalItem
    {
        let item = journal(name)
        try await settle(item, in: store)
        var mine = item
        mine.title = name + " here"
        try await store.save(mine)
        var theirs = item
        theirs.title = name + " there"
        try await deliver(theirs, revision: revision, to: store)
        return item
    }
    private func failWrites(of record: UUID, in store: JournalStore) async throws {
        try await store.db.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_write BEFORE UPDATE ON records
                    WHEN NEW.id='\(record.uuidString.lowercased())' AND NEW.dirty=1
                    BEGIN SELECT RAISE(ABORT, 'Injected failure'); END
                    """)
        }
    }

    func testAFailedPassRetriesOnlyTheRowsItFirstTookAndNotOnesMadeLater() async throws {
        let store = try await openStore(runPass: false)
        let old = try await renamedOnTwoDevices("Old", in: store)
        try await failWrites(of: old.id, in: store)
        let first = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(first.resolved.isEmpty, "The row fails and stays")
        // A row made after that, as a paged catch-up that stopped in the middle leaves one, waits for a pull.
        let later = try await renamedOnTwoDevices("Later", in: store)
        try await store.db.write { try $0.execute(sql: "DROP TRIGGER fail_write") }

        let second = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(second.resolved.map(\.recordID), [old.id], "Only the row the pass first took")
        let rows = try await store.conflicts().map(\.id)
        XCTAssertEqual(rows, [later.id])
        let third = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(third.resolved.isEmpty, "The pass is complete")
        let pulled = try await settleAfterPause(store)
        XCTAssertEqual(pulled.resolved.map(\.recordID), [later.id], "…and the later row settles with a pull")
    }

    func testThePassWaitsForAReconciliationAndLeavesHeldRowsForALaterCall() async throws {
        let store = try await openStore(runPass: false)
        let held = try await renamedOnTwoDevices("Held", in: store)
        let other = try await renamedOnTwoDevices("Other", in: store)

        try await store.beginReconciliation(serverID: "restored")
        let reconciling = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(reconciling.resolved.isEmpty, "Row revisions aren't final during a reconciliation")
        var state = try await store.keptNotesState()
        XCTAssertEqual(state.passStep, 0)
        XCTAssertNil(state.passRecords, "…and the pass did not start")
        try await store.setSetting("reconcile", value: nil)

        let holding = try await store.resolveConflicts(at: .opening(serverConfigured: true), holding: [held.id])
        XCTAssertEqual(holding.resolved.map(\.recordID), [other.id])
        state = try await store.keptNotesState()
        XCTAssertEqual(state.passRecords, [held.id], "The held row is still the pass's to settle")
        let rest = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(rest.resolved.map(\.recordID), [held.id])
        state = try await store.keptNotesState()
        XCTAssertEqual(state.passStep, 1)
        XCTAssertNil(state.passRecords)
    }

    // MARK: A row whose other version the record has passed

    private func stale(_ item: JournalItem, in store: JournalStore) async throws {
        try await store.db.write {
            try $0.execute(
                sql: "UPDATE records SET revision=9 WHERE id=?", arguments: [item.id.uuidString.lowercased()])
        }
    }

    func testAnOutOfDateRowWhoseOtherVersionIsADeletionLeavesNoMarkerInHistory() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        try await store.save(mine)
        try await deliver(marker(for: work), revision: 2, to: store)
        try await stale(work, in: store)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.map(\.result), [.superseded])
        let history = try await store.history(for: work.id)
        XCTAssertTrue(history.isEmpty, "A permanent deletion is not an earlier version")
        let rows = try await store.conflicts()
        XCTAssertTrue(rows.isEmpty)
    }

    func testAnOutOfDateRowWhoseOtherVersionCannotBeReadKeepsItsRow() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        try await store.save(mine)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(work)) as? [String: Any])
        object["futureRules"] = ["hidden": true]
        let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let change = RemoteChange(
            cursor: 1, recordId: work.id, revision: 2, kind: "journal",
            payload: try VaultCrypto.seal(
                future, key: key, context: VaultCrypto.recordContext(id: work.id, kind: "journal")
            ).base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
        try await store.apply([change], cursor: 1)
        try await stale(work, in: store)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.held, 1)
        XCTAssertTrue(report.resolved.isEmpty)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.map(\.id), [work.id], "Nothing is dropped that this version can't read")
        let history = try await store.history(for: work.id)
        XCTAssertTrue(history.isEmpty)
    }

    // MARK: A settlement that rolls back

    func testASettlementThatRollsBackLeavesTheQueueInMemoryAsItWas() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        try await store.save(mine)
        var theirs = work
        theirs.title = "Theirs"
        try await deliver(theirs, revision: 2, to: store)
        // The note of the rename can't be stored, which fails the transaction after the queue was rewritten.
        try await store.db.write { db in
            for event in ["INSERT", "UPDATE"] {
                try db.execute(
                    sql: """
                        CREATE TRIGGER fail_note_\(event) BEFORE \(event) ON settings WHEN NEW.key='kept-notes'
                        BEGIN SELECT RAISE(ABORT, 'Injected failure'); END
                        """)
            }
        }
        let queuedBefore = await store.unsentOperations
        let pendingBefore = try await store.pending().map(\.operationId)
        XCTAssertFalse(queuedBefore.isEmpty)

        time.withLock { $0 = $0.addingTimeInterval(3) }
        let failed = try await store.resolveConflicts(at: .completedPull)
        XCTAssertTrue(failed.resolved.isEmpty)
        let queuedAfter = await store.unsentOperations
        XCTAssertEqual(queuedAfter, queuedBefore)
        let pendingAfter = try await store.pending().map(\.operationId)
        XCTAssertEqual(pendingAfter, pendingBefore)
    }

    // MARK: What a waiting conflict does to the library

    func testAJournalWhoseConflictSettlesAtTheNextPullStaysInUseButOneHeldForANewerVersionDoesNot() async throws {
        let store = try await openStore()
        let settling = journal("Settling")
        let held = journal("Held")
        let inSettling = entry("In settling", text: "x", journal: settling.id)
        let inHeld = entry("In held", text: "y", journal: held.id)
        for item in [settling, held, inSettling, inHeld] { try await settle(item, in: store) }
        var renamed = settling
        renamed.title = "Settling, here"
        try await store.save(renamed)
        var theirs = settling
        theirs.title = "Settling, there"
        try await deliver(theirs, revision: 2, to: store)
        var mine = held
        mine.title = "Held, here"
        try await store.save(mine)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(held)) as? [String: Any])
        object["futureRules"] = ["hidden": true]
        let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let change = RemoteChange(
            cursor: 9, recordId: held.id, revision: 2, kind: "journal",
            payload: try VaultCrypto.seal(
                future, key: key, context: VaultCrypto.recordContext(id: held.id, kind: "journal")
            ).base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
        try await store.recordConflict(change)
        let rows = try await store.conflicts()
        XCTAssertEqual(Set(rows.map(\.id)), [settling.id, held.id])

        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertTrue(snapshot.liveJournals.contains { $0.id == settling.id })
        XCTAssertEqual(snapshot.location(of: inSettling), .journal, "It settles at the next pull; nothing to update")
        XCTAssertFalse(snapshot.liveJournals.contains { $0.id == held.id })
        XCTAssertEqual(snapshot.location(of: inHeld), .unavailable(.unsupported))
    }

    // MARK: A server that lost the record

    func testARowForARecordTheRestoredServerLostIsSettledAsANewRecord() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        try await store.save(mine)
        var theirs = work
        theirs.title = "Theirs"
        try await deliver(theirs, revision: 2, to: store)

        try await store.beginReconciliation(serverID: "restored")
        try await store.stageReconciliation([], cursor: 0)
        try await store.finishReconciliation(serverIDCursor: 0)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.map(\.remoteRevision), [0], "The record has to be created again")

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.map(\.result), [.journalKept])
        let record = try await stored(store, work.id)
        XCTAssertEqual(record.title, "Mine")
        let pending = try await store.pending()
        XCTAssertEqual(pending.map(\.baseRevision), [0], "It is sent as a new record")
        let history = try await store.history(for: work.id)
        XCTAssertEqual(history.map(\.title), ["Theirs"])
        let remaining = try await store.conflicts()
        XCTAssertTrue(remaining.isEmpty)
    }
}
