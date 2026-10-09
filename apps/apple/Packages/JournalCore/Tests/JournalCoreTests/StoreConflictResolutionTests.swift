import GRDB
import XCTest
import os

@testable import JournalCore

/// Journal and permanent-deletion conflicts settled on this device (protocol/conflicts.md, Orchestration), with real
/// isolated stores. Entries and templates that differ still wait for the person.
final class StoreConflictResolutionTests: ConflictTestCase {
    // MARK: Several revisions, journals

    func testSeveralRevisionsWhileTheLocalVersionIsUnsentLeaveOneRowAndOneOutcome() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        mine.defaultTemplateID = UUID()
        try await store.save(mine)
        var changes: [RemoteChange] = []
        for (index, name) in ["Second", "Third", "Fourth"].enumerated() {
            var version = work
            version.title = name
            changes.append(try remote(version, revision: Int64(index + 2), cursor: Int64(index + 1)))
        }
        try await store.apply(changes, cursor: 3)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.remoteRevision, 4)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved, [ResolvedConflict(recordID: work.id, kind: "journal", result: .journalKept)])
        let record = try await stored(store, work.id)
        XCTAssertEqual(record.title, "Mine")
        XCTAssertEqual(record.defaultTemplateID, mine.defaultTemplateID, "A setting this version no longer shows")
        let pending = try await store.pending()
        XCTAssertEqual(pending.map(\.baseRevision), [4])
        let history = try await store.history(for: work.id)
        XCTAssertEqual(Set(history.map(\.title)), ["Second", "Third", "Fourth"], "Every other version is kept")
        let notes = try await store.keptNotes()
        XCTAssertEqual(notes.map(\.kind), [.journalRenamed])
        XCTAssertEqual(notes.first?.name, "Mine")
        XCTAssertEqual(notes.first?.otherName, "Fourth")
        let again = try await settleAfterPause(store)
        XCTAssertTrue(again.resolved.isEmpty, "One resolution per record")
    }

    func testARenamedJournalThatWasDeletedElsewhereIsDeletedWithItsNameAndItsEntriesFollow() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let notes = entry("Notes", text: "inside", journal: work.id)
        try await settle(work, in: store)
        try await settle(notes, in: store)
        var renamed = work
        renamed.title = "Work, renamed"
        try await store.save(renamed)
        var deleted = work
        deleted.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await deliver(deleted, revision: 2, to: store)
        // The entry was edited here too, so it has a conflict of its own, which still waits for the person.
        var edited = notes
        edited.document = .plain("edited here")
        try await store.save(edited)
        var elsewhere = notes
        elsewhere.document = .plain("edited elsewhere")
        try await deliver(elsewhere, revision: 2, to: store)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.map(\.recordID), [work.id])
        XCTAssertEqual(report.review, 1)
        let journalAfter = try await stored(store, work.id)
        XCTAssertEqual(journalAfter.title, "Work, renamed")
        XCTAssertEqual(journalAfter.deletedAt, deleted.deletedAt)
        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: notes), .recentlyDeleted)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.map(\.id), [notes.id], "The entry keeps its review, and the journal's is gone")
        let sent = try await store.pending()
        XCTAssertEqual(sent.map(\.recordID), [work.id], "Nothing is sent for the entry under review")
    }

    func testTheNameRuleNumbersAJournalThatEndsUpWithATakenNameWithoutAConflict() async throws {
        let store = try await openStore()
        let work = journal("Work", seconds: 2_000)
        try await settle(work, in: store)
        var mine = work
        mine.title = "Alpha"
        try await store.save(mine)
        var theirs = work
        theirs.title = "Beta"
        try await deliver(theirs, revision: 2, to: store)
        // Another device made a journal with the name this device's rename keeps.
        let elsewhere = journal("Alpha", seconds: 1_000)
        try await deliver(elsewhere, revision: 1, to: store)
        _ = try await settleAfterPause(store)
        let waiting = try await store.automaticRenames()
        XCTAssertTrue(waiting.isEmpty, "A journal with a change waiting to be sent isn't renamed")
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 9, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        let renames = try await store.automaticRenames()
        XCTAssertEqual(renames.count, 1, "The newer journal gets a number, as an ordinary change")
        let rows = try await store.conflicts()
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: Permanent deletion

    func testAnEditOpenHereMeetsAPermanentDeletionAndTheDeletionStaysFinal() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        var edited = draft
        edited.document = .plain("words kept after the deletion")
        try await store.save(edited)
        let deletion = marker(for: draft)
        try await deliver(deletion, revision: 2, to: store)

        let report = try await settleAfterPause(store)
        guard case .deletedAndChanged(let parkedID?) = try XCTUnwrap(report.resolved.first).result else {
            return XCTFail("The edit was not parked")
        }
        let record = try await stored(store, draft.id)
        XCTAssertEqual(record, deletion, "The marker is the record")
        let history = try await store.history(for: draft.id)
        XCTAssertTrue(history.isEmpty, "A permanent deletion removes earlier versions")
        let parked = try await stored(store, parkedID)
        XCTAssertEqual(parked.title, "Draft")
        XCTAssertEqual(parked.document.text, "words kept after the deletion")
        XCTAssertEqual(parked.journalID, home.id)
        XCTAssertEqual(parked.deletedAt, deletion.permanentlyDeletedAt)
        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: parked), .recentlyDeleted)
        let pending = try await store.pending()
        XCTAssertEqual(pending.map(\.recordID), [parkedID], "Only the parked entry is sent, as a new record")
        XCTAssertEqual(pending.first?.baseRevision, 0)
        let rows = try await store.conflicts()
        XCTAssertTrue(rows.isEmpty)
        let notes = try await store.keptNotes()
        XCTAssertEqual(notes.map(\.kind), [.deletedAndChanged])
        XCTAssertEqual(notes.first?.otherID, parkedID)
        // The edit comes back with one Restore, to its own journal.
        let restored = try await store.restoreEntry(parkedID, fallback: nil)
        XCTAssertTrue(restored.returnedToOwnJournal)
        XCTAssertEqual(restored.entry.document.text, "words kept after the deletion")
    }

    func testAPermanentDeletionMadeHereMeetsAnEditFromElsewhere() async throws {
        let store = try await openStore()
        let home = journal("Home")
        var draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        draft.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save(draft)
        let confirmation = try await store.preparePermanentDeletion(draft.id)
        let deletion = try await store.permanentlyDelete(confirmation)
        var elsewhere = entry("Draft", text: "an edit from another device", journal: home.id)
        elsewhere.id = draft.id
        try await store.recordConflict(try remote(elsewhere, revision: 2))
        let sentBefore = try await store.pending()
        XCTAssertTrue(sentBefore.isEmpty, "A record under review is not sent")

        let report = try await settleAfterPause(store)
        guard case .deletedAndChanged(let parkedID?) = try XCTUnwrap(report.resolved.first).result else {
            return XCTFail("The edit was not parked")
        }
        let record = try await stored(store, draft.id)
        XCTAssertEqual(record, deletion)
        let parked = try await stored(store, parkedID)
        XCTAssertEqual(parked.document.text, "an edit from another device")
        let pending = try await store.pending()
        let marker = try XCTUnwrap(pending.first { $0.recordID == draft.id })
        XCTAssertEqual(marker.baseRevision, 2, "The deletion is sent on top of the edit it replaces")
        XCTAssertEqual(pending.first { $0.recordID == parkedID }?.baseRevision, 0)
    }

    func testTwoPermanentDeletionsKeepTheServersAndRemoveTheHistory() async throws {
        let store = try await openStore()
        let home = journal("Home")
        var draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        draft.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save(draft)
        _ = try await store.permanentlyDelete(try await store.preparePermanentDeletion(draft.id))
        let theirs = marker(for: draft, at: 1_810_000_000)
        try await store.recordConflict(try remote(theirs, revision: 2))
        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.first?.result, .twoDeletions)
        let record = try await stored(store, draft.id)
        XCTAssertEqual(record, theirs)
        let pending = try await store.pending()
        XCTAssertTrue(pending.isEmpty, "Nothing is left to send")
        let others = try await parkedItems(in: store, excluding: draft.id)
        XCTAssertTrue(others.isEmpty)
    }

    func testAJournalAgainstAPermanentDeletionCreatesNoJournalAndItsEditedEntriesAreUnavailable() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let notes = entry("Notes", text: "inside", journal: work.id)
        try await settle(work, in: store)
        try await settle(notes, in: store)
        var renamed = work
        renamed.title = "Work, renamed here"
        try await store.save(renamed)
        var edited = notes
        edited.document = .plain("edited here")
        try await store.save(edited)
        // The journal was deleted permanently with its entry on another device.
        try await store.apply(
            [
                try remote(marker(for: work), revision: 2, cursor: 1),
                try remote(marker(for: notes), revision: 2, cursor: 2),
            ],
            cursor: 2)
        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.count, 2)
        let items = try await store.items()
        XCTAssertEqual(items.filter { $0.kind == "journal" && !$0.isPermanentlyDeleted }.count, 0)
        let parked = try XCTUnwrap(items.first { $0.kind == "entry" && !$0.isPermanentlyDeleted })
        XCTAssertEqual(parked.journalID, work.id)
        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: parked), .unavailable(.missing))
        let notesAfter = try await store.keptNotes()
        XCTAssertEqual(Set(notesAfter.map(\.kind)), [.journalDeleted, .deletedAndChanged])
        XCTAssertEqual(notesAfter.first { $0.kind == .journalDeleted }?.name, "Work, renamed here")
        // Restore brings it back to the Default Journal, since its own journal is gone.
        let fallback = journal("Default")
        try await settle(fallback, in: store)
        let restored = try await store.restoreEntry(parked.id, fallback: fallback.id)
        XCTAssertFalse(restored.returnedToOwnJournal)
        XCTAssertEqual(restored.entry.journalID, fallback.id)
    }

    func testAParkedEntryKeepsTheImagesOfTheEditedVersion() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let imageID = try await store.addAttachment(Data("a picture".utf8))
        var draft = entry("With picture", text: "x", journal: home.id)
        draft.document = JournalDocument(blocks: [DocumentBlock(kind: "image", attachmentID: imageID)])
        try await settle(home, in: store)
        try await settle(draft, in: store)
        var edited = draft
        edited.title = "With picture, edited"
        try await store.save(edited)
        try await deliver(marker(for: draft), revision: 2, to: store)
        let report = try await settleAfterPause(store)
        guard case .deletedAndChanged(let parkedID?) = try XCTUnwrap(report.resolved.first).result else {
            return XCTFail("The edit was not parked")
        }
        let parked = try await stored(store, parkedID)
        XCTAssertEqual(parked.document.attachmentIDs, [imageID])
        let referenced = try await store.referencedAttachmentIDs()
        XCTAssertTrue(referenced.contains(imageID))
        let bytes = try await store.attachment(imageID)
        XCTAssertEqual(bytes, Data("a picture".utf8))
    }

    // MARK: A derived identity that exists

    private enum ExistingState: CaseIterable {
        case clean, editedElsewhere, deleted, permanentlyDeleted, madeEarlierHere
    }

    /// The derived identity of the parked entry already exists in some state: nothing is written to it, revived or noted,
    /// and the record still settles.
    func testAParkedIdentityThatAlreadyExistsInAnyStateIsLeftAlone() async throws {
        for state in ExistingState.allCases {
            let store = try await openStore("existing-\(state)")
            let home = journal("Home")
            let draft = entry("Draft", text: "first", journal: home.id)
            try await settle(home, in: store)
            try await settle(draft, in: store)
            var edited = draft
            edited.document = .plain("the same words everywhere")
            let derived = await store.copyIdentity.copyID(
                .park, record: draft.id, plaintext: try PortableRecord.encode(edited))
            var existing = edited
            existing.id = derived
            switch state {
            case .clean: try await deliver(existing, revision: 1, to: store)
            case .editedElsewhere:
                try await deliver(existing, revision: 1, to: store)
                existing.title = "Edited since"
                try await store.save(existing)
            case .deleted:
                existing.deletedAt = Date(timeIntervalSince1970: 1_600_000_000)
                try await deliver(existing, revision: 1, to: store)
            case .permanentlyDeleted:
                try await deliver(marker(for: existing, at: 1_650_000_000), revision: 1, to: store)
            case .madeEarlierHere: try await store.save(existing)
            }
            let before = try await store.item(derived)
            let pendingBefore = try await store.pending().filter { $0.recordID == derived }.map(\.payload)
            try await store.save(edited)
            try await deliver(marker(for: draft), revision: 2, to: store)

            let report = try await settleAfterPause(store)
            XCTAssertEqual(report.resolved.count, 1, "\(state)")
            let after = try await store.item(derived)
            XCTAssertEqual(after, before, "\(state): nothing is written to it")
            let pendingAfter = try await store.pending().filter { $0.recordID == derived }.map(\.payload)
            XCTAssertEqual(pendingAfter, pendingBefore, "\(state)")
            let notes = try await store.keptNotes()
            XCTAssertTrue(notes.isEmpty, "\(state): no note")
            let record = try await stored(store, draft.id)
            XCTAssertTrue(record.isCanonicalDeletionMarker, "\(state): the record still settles")
            let rows = try await store.conflicts()
            XCTAssertTrue(rows.isEmpty, "\(state)")
        }
    }

    /// A parked entry this device made and has not sent is dropped when it meets a permanent deletion: the person who
    /// deleted it for good is not overruled, and its content is still in the other record.
    func testAParkedEntryDeletedForGoodElsewhereIsNotRevivedByALateDevice() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        var edited = draft
        edited.document = .plain("words")
        try await store.save(edited)
        try await deliver(marker(for: draft), revision: 2, to: store)
        let report = try await settleAfterPause(store)
        guard case .deletedAndChanged(let parkedID?) = try XCTUnwrap(report.resolved.first).result else {
            return XCTFail("The edit was not parked")
        }
        // Another device made the same parked entry earlier and deleted it for good.
        let parked = try await stored(store, parkedID)
        try await store.recordConflict(try remote(marker(for: parked, at: 1_820_000_000), revision: 1, cursor: 5))
        let late = try await settleAfterPause(store)
        XCTAssertEqual(late.resolved.first?.result, .deletedAndChanged(parkedID: nil))
        let record = try await stored(store, parkedID)
        XCTAssertTrue(record.isCanonicalDeletionMarker)
        let others = try await parkedItems(in: store, excluding: draft.id)
        XCTAssertTrue(others.isEmpty, "Nothing was parked again")
        let state = try await store.keptNotesState()
        XCTAssertFalse(state.isAutomaticCopy(parkedID))
    }

    /// Two clients write the same parked entry with different bytes: the one that arrives first wins and a device that
    /// had not sent its own, and had not edited it since, drops it without a further copy.
    func testAParkedEntryThatAnotherClientAlsoWroteIsReplacedByTheArrivingVersion() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        var edited = draft
        edited.document = .plain("words")
        try await store.save(edited)
        try await deliver(marker(for: draft), revision: 2, to: store)
        let report = try await settleAfterPause(store)
        guard case .deletedAndChanged(let parkedID?) = try XCTUnwrap(report.resolved.first).result else {
            return XCTFail("The edit was not parked")
        }
        var theirs = try await stored(store, parkedID)
        // The same words, written with another title wording and time: other bytes, nothing of ours lost.
        theirs.title = "Draft (saved separately)"
        theirs.modifiedAt = Date(timeIntervalSince1970: 1_800_000_500)
        try await store.recordConflict(try remote(theirs, revision: 1, cursor: 9))
        let later = try await settleAfterPause(store)
        XCTAssertEqual(later.resolved.count, 1)
        let record = try await stored(store, parkedID)
        XCTAssertEqual(record.title, "Draft (saved separately)")
        XCTAssertEqual(record.document.text, "words")
        let pending = try await store.pending()
        XCTAssertTrue(pending.isEmpty, "Nothing of the dropped version is sent")
        let state = try await store.keptNotesState()
        XCTAssertFalse(state.isAutomaticCopy(parkedID))
        let others = try await parkedItems(in: store, excluding: draft.id)
        XCTAssertEqual(others.count, 1, "No further copy")
    }

    // MARK: Held

    func testAVersionThisAppCannotReadStaysHeldAndNothingIsSentUntilItCanBeRead() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let other = journal("Other")
        try await settle(work, in: store)
        try await settle(other, in: store)
        var renamed = work
        renamed.title = "Mine"
        try await store.save(renamed)
        var otherRenamed = other
        otherRenamed.title = "Mine too"
        try await store.save(otherRenamed)
        // One page: a version from a newer app of one journal and an ordinary change to the other.
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(work)) as? [String: Any])
        object["futureRules"] = ["hidden": true]
        let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let futureChange = RemoteChange(
            cursor: 1, recordId: work.id, revision: 2, kind: "journal",
            payload: try VaultCrypto.seal(
                future, key: key, context: VaultCrypto.recordContext(id: work.id, kind: "journal")
            ).base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
        var otherElsewhere = other
        otherElsewhere.title = "Theirs"
        try await store.apply([futureChange, try remote(otherElsewhere, revision: 2, cursor: 2)], cursor: 2)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.map(\.recordID), [other.id])
        XCTAssertEqual(report.held, 1)
        let held = try await store.heldConflictIDs()
        XCTAssertEqual(held, [work.id])
        let pending = try await store.pending()
        XCTAssertEqual(pending.map(\.recordID), [other.id], "Nothing is sent for the held record")
        let waiting = try await store.settledFactsAwaitConflict()
        XCTAssertFalse(waiting, "A held row is not waiting for a later point")

        // The next version of that record can be read: it replaces the held one and the row is settled.
        var readable = work
        readable.title = "Later elsewhere"
        try await store.apply([try remote(readable, revision: 3, cursor: 3)], cursor: 3)
        let later = try await settleAfterPause(store)
        XCTAssertEqual(later.resolved.map(\.recordID), [work.id])
        let record = try await stored(store, work.id)
        XCTAssertEqual(record.title, "Mine")
        let heldAfter = try await store.heldConflictIDs()
        XCTAssertTrue(heldAfter.isEmpty)
    }

    // MARK: When it runs

    func testNothingIsSettledDuringAReconciliationOrForARecordBeingWritten() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        try await store.save(mine)
        var theirs = work
        theirs.title = "Theirs"
        try await deliver(theirs, revision: 2, to: store)

        let written = try await store.resolveConflicts(at: .completedPull)
        XCTAssertEqual(written.deferred, 1, "The record was saved a moment ago")
        XCTAssertTrue(written.resolved.isEmpty)
        let waiting = try await store.settledFactsAwaitConflict()
        XCTAssertTrue(waiting, "A round that follows settles it")
        time.withLock { $0 = $0.addingTimeInterval(3) }

        try await store.beginReconciliation(serverID: "restored")
        let reconciling = try await store.resolveConflicts(at: .completedPull)
        XCTAssertTrue(reconciling.resolved.isEmpty)
        try await store.setSetting("reconcile", value: nil)
        let paused = try await store.resolveConflicts(at: .completedPull)
        XCTAssertEqual(paused.resolved.count, 1)
    }

    /// The open entry while a save of it has failed is held by the caller: its conflict waits for a round after the
    /// save works again.
    func testARecordTheCallerHoldsIsLeftForALaterRound() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        try await store.save(mine)
        var theirs = work
        theirs.title = "Theirs"
        try await deliver(theirs, revision: 2, to: store)
        time.withLock { $0 = $0.addingTimeInterval(3) }
        let held = try await store.resolveConflicts(at: .completedPull, holding: [work.id])
        XCTAssertEqual(held.deferred, 1)
        XCTAssertTrue(held.resolved.isEmpty)
        let later = try await store.resolveConflicts(at: .completedPull)
        XCTAssertEqual(later.resolved.count, 1)
    }

    func testOpeningSettlesRowsFromAnEarlierVersionButWaitsForAPullOtherwiseUnlessThereIsNoServer() async throws {
        let store = try await openStore(runPass: false)
        let work = journal("Work")
        try await settle(work, in: store)
        var mine = work
        mine.title = "Mine"
        try await store.save(mine)
        var theirs = work
        theirs.title = "Theirs"
        try await deliver(theirs, revision: 2, to: store)
        // The library was opened by the first version that settles conflicts on its own: the row is an earlier one.
        let opening = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(opening.resolved.count, 1)

        // A row made after that, such as one left by a crash in the middle of a paged catch-up, waits for a pull.
        var again = mine
        again.title = "Mine again"
        try await store.save(again)
        var third = work
        third.title = "Third"
        try await deliver(third, revision: 3, to: store)
        let reopened = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(reopened.resolved.isEmpty)
        let noServer = try await store.resolveConflicts(at: .opening(serverConfigured: false))
        XCTAssertEqual(noServer.resolved.count, 1, "With no server there is no pull to wait for")
    }

    // MARK: The pass over rows an earlier version left

    func testTheOneTimePassSettlesEveryJournalAndDeletionRowOnceAndLeavesTheRest() async throws {
        let store = try await openStore("pass", runPass: false)
        let home = journal("Home")
        let renamedElsewhere = journal("Renamed")
        let edited = entry("Edited", text: "first", journal: home.id)
        let deletedHere = entry("Deleted here", text: "first", journal: home.id)
        let both = entry("Both", text: "first", journal: home.id)
        let differing = entry("Differing", text: "first", journal: home.id)
        for item in [home, renamedElsewhere, edited, deletedHere, both, differing] { try await settle(item, in: store) }
        // 1. A journal renamed on two devices.
        var local = renamedElsewhere
        local.title = "Renamed here"
        try await store.save(local)
        var theirs = renamedElsewhere
        theirs.title = "Renamed there"
        try await deliver(theirs, revision: 2, to: store)
        // 2. An edit against a permanent deletion.
        var change = edited
        change.document = .plain("edited")
        try await store.save(change)
        try await deliver(marker(for: edited), revision: 2, to: store)
        // 3. A deletion the person had meant to confirm with Keep Deletion, against an edit.
        var removal = deletedHere
        removal.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save(removal)
        _ = try await store.permanentlyDelete(try await store.preparePermanentDeletion(deletedHere.id))
        var elsewhere = deletedHere
        elsewhere.document = .plain("an edit from elsewhere")
        try await store.recordConflict(try remote(elsewhere, revision: 2))
        // 4. Two permanent deletions.
        var bothDeleted = both
        bothDeleted.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.save(bothDeleted)
        _ = try await store.permanentlyDelete(try await store.preparePermanentDeletion(both.id))
        try await store.recordConflict(try remote(marker(for: both, at: 1_820_000_000), revision: 2))
        // 5. An entry whose content differs: the review is left for the person.
        var mine = differing
        mine.document = .plain("mine")
        try await store.save(mine)
        var other = differing
        other.document = .plain("other")
        try await deliver(other, revision: 2, to: store)
        // 6. A row whose other version this device's record has already passed: a review out of date.
        let stale = journal("Stale")
        try await settle(stale, in: store)
        var staleLocal = stale
        staleLocal.title = "Stale here"
        try await store.save(staleLocal)
        var staleRemote = stale
        staleRemote.title = "Stale there"
        try await deliver(staleRemote, revision: 2, to: store)
        try await store.db.write {
            try $0.execute(
                sql: "UPDATE records SET revision=9 WHERE id=?", arguments: [stale.id.uuidString.lowercased()])
        }

        let before = try await store.conflicts().count
        XCTAssertEqual(before, 6)
        let report = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(report.resolved.count, 5)
        let kinds = report.resolved.map(\.result)
        XCTAssertEqual(kinds.filter { $0 == .journalKept }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .twoDeletions }.count, 1)
        XCTAssertEqual(kinds.filter { $0 == .superseded }.count, 1)
        XCTAssertEqual(report.parked.count, 2)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.map(\.id), [differing.id], "Entries that differ keep their review until they settle too")
        let kept = try await stored(store, renamedElsewhere.id)
        XCTAssertEqual(kept.title, "Renamed here")
        let stalePast = try await store.history(for: stale.id)
        XCTAssertEqual(stalePast.map(\.title), ["Stale there"], "Its other version is kept in Version History")
        // The deletion the person meant to confirm is final, and the edit is parked.
        let deletionRecord = try await stored(store, deletedHere.id)
        XCTAssertTrue(deletionRecord.isCanonicalDeletionMarker)
        let entries = try await store.items().filter { $0.kind == "entry" && !$0.isPermanentlyDeleted }
        XCTAssertEqual(Set(entries.map(\.document.text)), ["edited", "an edit from elsewhere", "mine"])

        // The pass runs once: a second opening settles nothing and parks nothing again.
        try await store.close()
        let reopened = try JournalStore(directory: root.appendingPathComponent("pass"), key: key)
        let second = try await reopened.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(second.resolved.isEmpty)
        let parkedAgain = try await reopened.items().filter { $0.kind == "entry" && !$0.isPermanentlyDeleted }
        XCTAssertEqual(parkedAgain.count, 3)
        try await reopened.close()
    }

    /// Interrupted between rows, the next opening finishes the rest without a second copy of what was made.
    func testAnInterruptedPassFinishesTheRestWithoutADuplicate() async throws {
        let store = try await openStore("interrupted", runPass: false)
        let home = journal("Home")
        let first = entry("First", text: "a", journal: home.id)
        let second = entry("Second", text: "b", journal: home.id)
        for item in [home, first, second] { try await settle(item, in: store) }
        var edits: [UUID: JournalItem] = [:]
        for item in [first, second] {
            var edited = item
            edited.document = .plain("edited \(item.title)")
            edits[item.id] = edited
            try await store.save(edited)
            try await deliver(marker(for: item), revision: 2, to: store)
        }
        // The second parked entry can't be stored.
        let victim = await store.copyIdentity.copyID(
            .park, record: second.id, plaintext: try PortableRecord.encode(try XCTUnwrap(edits[second.id])))
        try await store.db.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_park BEFORE INSERT ON records WHEN NEW.id='\(victim.uuidString.lowercased())'
                    BEGIN SELECT RAISE(ABORT, 'Injected failure'); END
                    """)
        }
        let interrupted = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(interrupted.resolved.count, 1, "The other row is settled; this one stays")
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.map(\.id), [second.id])
        try await store.db.write { try $0.execute(sql: "DROP TRIGGER fail_park") }
        try await store.close()

        let reopened = try JournalStore(directory: root.appendingPathComponent("interrupted"), key: key)
        let rest = try await reopened.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertEqual(rest.resolved.count, 1)
        let parked = try await reopened.items().filter { $0.kind == "entry" && !$0.isPermanentlyDeleted }
        XCTAssertEqual(Set(parked.map(\.document.text)), ["edited First", "edited Second"])
        XCTAssertEqual(parked.count, 2)
        try await reopened.close()
    }

    func testAFailedSettlementChangesNothingAndRepeatsWithTheSameOutcome() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let draft = entry("Draft", text: "first", journal: home.id)
        try await settle(home, in: store)
        try await settle(draft, in: store)
        var edited = draft
        edited.document = .plain("words")
        try await store.save(edited)
        try await deliver(marker(for: draft), revision: 2, to: store)
        try await store.db.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_park BEFORE INSERT ON records WHEN NEW.kind='entry'
                    BEGIN SELECT RAISE(ABORT, 'Injected failure'); END
                    """)
        }
        let cursor = try await store.cursor()
        let recordBefore = try await stored(store, draft.id)
        let pendingBefore = try await store.pending()
        let failed = try await settleAfterPause(store)
        XCTAssertTrue(failed.resolved.isEmpty, "The failure stays with that record and doesn't stop the round")
        XCTAssertEqual(failed.held, 1)
        let recordAfter = try await stored(store, draft.id)
        XCTAssertEqual(recordAfter, recordBefore)
        let cursorAfter = try await store.cursor()
        XCTAssertEqual(cursorAfter, cursor)
        let pendingAfter = try await store.pending()
        XCTAssertEqual(pendingAfter.map(\.operationId), pendingBefore.map(\.operationId))
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.count, 1)
        try await store.db.write { try $0.execute(sql: "DROP TRIGGER fail_park") }
        let retry = try await settleAfterPause(store)
        XCTAssertEqual(retry.resolved.count, 1)
        let stored = try await store.item(draft.id)
        XCTAssertEqual(stored?.isCanonicalDeletionMarker, true)
    }

    // MARK: Notes

    func testKeptNotesAreSealedExpireClearAndAreIgnoredWhenDamaged() async throws {
        let store = try await openStore()
        let work = journal("Work")
        let other = journal("Other")
        let draft = entry("Draft", text: "x", journal: work.id)
        for item in [work, other, draft] { try await settle(item, in: store) }
        // A rename and a deletion.
        var renamed = work
        renamed.title = "Work here"
        try await store.save(renamed)
        var theirs = work
        theirs.title = "Work there"
        try await deliver(theirs, revision: 2, to: store)
        var changedOther = other
        changedOther.title = "Other here"
        try await store.save(changedOther)
        try await deliver(marker(for: other), revision: 2, to: store)
        time.withLock { $0 = $0.addingTimeInterval(3) }
        _ = try await settleAfterPause(store)
        let all = try await store.keptNotes()
        XCTAssertEqual(Set(all.map(\.kind)), [.journalRenamed, .journalDeleted])

        // What the notes say is sealed: no journal name is readable in the settings value.
        let raw = try await store.setting("kept-notes")
        let text = String(decoding: try XCTUnwrap(raw), as: UTF8.self)
        let decoded = try XCTUnwrap(Data(base64Encoded: text))
        XCTAssertNil(try? JSONSerialization.jsonObject(with: decoded))
        XCTAssertFalse(String(decoding: decoded, as: UTF8.self).contains("Work here"))

        try await store.markKeptNoteSeen(try XCTUnwrap(all.first).id)
        let seen = try await store.keptNotes().filter(\.seen)
        XCTAssertEqual(seen.count, 1)

        // After 30 days only the journal rename note is left: it is the only trail of the name that lost.
        time.withLock { $0 = $0.addingTimeInterval(31 * 24 * 60 * 60) }
        let months = try await store.keptNotes()
        XCTAssertEqual(months.map(\.kind), [.journalRenamed])
        try await store.clearKeptNotes()
        let cleared = try await store.keptNotes()
        XCTAssertTrue(cleared.isEmpty)

        // A value that can't be opened is ignored and blocks nothing.
        try await store.setSetting("kept-notes", value: Data("not sealed".utf8))
        let damaged = try await store.keptNotes()
        XCTAssertTrue(damaged.isEmpty)
        let more = journal("More")
        try await settle(more, in: store)
        var moreHere = more
        moreHere.title = "More here"
        try await store.save(moreHere)
        var moreThere = more
        moreThere.title = "More there"
        try await deliver(moreThere, revision: 2, to: store)
        time.withLock { $0 = $0.addingTimeInterval(3) }
        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.count, 1)
        let rewritten = try await store.keptNotes()
        XCTAssertEqual(rewritten.map(\.kind), [.journalRenamed])
    }

    func testTheNoteListKeepsRenameNotesFirstWhenFull() throws {
        var state = KeptNotesState()
        let rename = KeptNote(kind: .journalRenamed, recordID: UUID(), name: "A", otherName: "B", created: Date())
        state.add(rename)
        for index in 0..<30 {
            state.add(KeptNote(kind: .journalDeleted, recordID: UUID(), name: "J\(index)", created: Date()))
        }
        XCTAssertEqual(state.notes.count, KeptNotesState.noteLimit)
        XCTAssertTrue(state.notes.contains { $0.id == rename.id })
    }

    func testTheNotesSurviveEncryptingTheLibraryAndAnArchive() async throws {
        let plain = try JournalStore(directory: root.appendingPathComponent("plain"), key: key, protection: .plaintext)
        addTeardownBlock { try? await plain.close() }
        let work = journal("Work")
        try await settle(work, in: plain)
        var mine = work
        mine.title = "Mine"
        try await plain.save(mine)
        var theirs = work
        theirs.title = "Theirs"
        let payload = try PortableRecord.encode(theirs).base64EncodedString()
        try await plain.recordConflict(
            RemoteChange(
                cursor: 2, recordId: work.id, revision: 2, kind: "journal", payload: payload, deviceId: UUID(),
                modifiedAt: Date()))
        let report = try await plain.resolveConflicts(at: .completedPull)
        XCTAssertEqual(report.resolved.count, 1)
        let newKey = Data((0..<32).map { UInt8($0 &+ 128) })
        let encrypted = try await plain.reencryptedCopy(
            to: root.appendingPathComponent("encrypted"), key: newKey, baseline: .restart)
        addTeardownBlock { try? await encrypted.close() }
        let notes = try await encrypted.keptNotes()
        XCTAssertEqual(notes.map(\.kind), [.journalRenamed], "Sealed under the new key like library-changes")
        let raw = try await encrypted.setting("kept-notes")
        let sealed = try XCTUnwrap(Data(base64Encoded: String(decoding: try XCTUnwrap(raw), as: UTF8.self)))
        XCTAssertNil(try? JSONSerialization.jsonObject(with: sealed))
        // An archive carries the key, and a reader that doesn't know it accepts the database.
        try await encrypted.validateSchema()
        let phrase = "kept notes archive fixture"
        let recovery = try VaultCrypto.makeRecovery(masterKey: newKey, phrase: phrase).0
        let archive = root.appendingPathComponent("notes.journalarchive")
        try await VaultArchive.export(store: encrypted, recovery: recovery, key: newKey, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        addTeardownBlock { try? await restored.store.close() }
        let restoredNotes = try await restored.store.keptNotes()
        XCTAssertEqual(restoredNotes.map(\.kind), [.journalRenamed])
    }
}

extension JournalStore {
    /// Whether a conflict is waiting for a later point, as a synchronization reports it.
    func settledFactsAwaitConflict() throws -> Bool { try hasConflictAwaitingResolution() }
}

extension ConflictResolutionReport {
    /// The identities of the entries parked, in the order they were settled.
    var parked: [UUID] {
        resolved.compactMap { resolved in
            if case .deletedAndChanged(let id?) = resolved.result { return id }
            return nil
        }
    }
}
