import XCTest

@testable import JournalCore

/// What 1.1 keeps of a library 1.0 wrote, and of devices that still run 1.0
/// (docs/design/1-1-library-simplifications.md, K to N, and docs/design/1-1-conflicts-and-reconnect.md).
final class JournalSettingsPreservedTests: ConflictTestCase {
    /// A journal's default template is neither shown nor used any more, but a 1.0 device still uses it, so every
    /// way 1.1 writes a journal keeps it.
    func testADefaultTemplateSurvivesEveryWayAJournalIsWritten() async throws {
        let store = try await openStore()
        let template = JournalItem(kind: "template", title: "Weekly", document: .plain("What went well?"))
        var work = journal("Work")
        work.defaultTemplateID = template.id
        try await settle(template, in: store)
        try await settle(work, in: store)

        // Rename.
        var renamed = work
        renamed.title = "Work, renamed"
        try await store.save(renamed)
        let afterRename = try await stored(store, work.id)
        XCTAssertEqual(afterRename.defaultTemplateID, template.id)
        // Delete Journal and Restore Journal.
        _ = try await store.deleteJournal(try await store.prepareJournalDeletion(work.id))
        let afterDelete = try await stored(store, work.id)
        XCTAssertEqual(afterDelete.defaultTemplateID, template.id)
        let afterRestore = try await store.restoreJournal(work.id)
        XCTAssertEqual(afterRestore.defaultTemplateID, template.id)
        // Settling a conflict: a 1.0 device changed the template while this device renamed the journal.
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 5, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        var again = try await stored(store, work.id)
        again.title = "Work, renamed again"
        try await store.save(again)
        var fromTenOh = try await stored(store, work.id)
        fromTenOh.title = "Work"
        fromTenOh.defaultTemplateID = UUID()
        try await deliver(fromTenOh, revision: 4, to: store)
        _ = try await settleAfterPause(store)
        let settled = try await stored(store, work.id)
        XCTAssertEqual(settled.title, "Work, renamed again")
        XCTAssertEqual(settled.defaultTemplateID, template.id, "This device's record keeps its template")

        // Another device receives it.
        let peer = try await openStore("peer")
        let pending = try await store.pending()
        let journalChange = try XCTUnwrap(pending.first { $0.recordID == work.id })
        try await peer.apply(
            [
                RemoteChange(
                    cursor: 1, recordId: work.id, revision: journalChange.baseRevision + 1, kind: "journal",
                    payload: journalChange.payload, deviceId: UUID(), modifiedAt: Date())
            ], cursor: 1)
        let received = try await stored(peer, work.id)
        XCTAssertEqual(received.defaultTemplateID, template.id)
    }

    func testAnImportedAndAMergedJournalKeepTheirTemplateUnderTheNewIdentity() async throws {
        let source = try await openStore("source")
        let template = JournalItem(kind: "template", title: "Weekly", document: .plain("What went well?"))
        var work = journal("Work")
        work.defaultTemplateID = template.id
        try await settle(template, in: source)
        try await settle(work, in: source)
        let library = try await openStore("library")
        try await library.importAsNewJournals(from: source)
        let items = try await library.items()
        let importedTemplate = try XCTUnwrap(items.first { $0.kind == "template" })
        let importedJournal = try XCTUnwrap(items.first { $0.kind == "journal" })
        XCTAssertNotEqual(importedTemplate.id, template.id)
        XCTAssertEqual(importedJournal.defaultTemplateID, importedTemplate.id, "Remapped, not dropped")
    }

    /// A record with a member this version doesn't know is never rewritten or made editable by a way of writing a
    /// journal: its original bytes stay.
    func testAJournalWithAnUnknownMemberIsNeverRewritten() async throws {
        let store = try await openStore()
        let work = journal("Work")
        try await settle(work, in: store)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(work)) as? [String: Any])
        object["futureRules"] = ["hidden": true]
        let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        try await store.apply(
            [
                RemoteChange(
                    cursor: 3, recordId: work.id, revision: 2, kind: "journal",
                    payload: try VaultCrypto.seal(
                        future, key: key, context: VaultCrypto.recordContext(id: work.id, kind: "journal")
                    ).base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
            ], cursor: 3)
        var renamed = try await stored(store, work.id)
        renamed.title = "Renamed"
        do {
            try await store.save(renamed)
            XCTFail("A journal this version can't fully read is not rewritten")
        } catch JournalError.unsupportedFormat {}
        do {
            _ = try await store.deleteJournal(try await store.prepareJournalDeletion(work.id))
            XCTFail("Nor deleted")
        } catch JournalLifecycleError.unsupportedJournal {}
        let kept = try await stored(store, work.id)
        XCTAssertEqual(try PortableRecord.encode(kept), future)
        XCTAssertTrue(kept.document.version == Int.max || kept.preservedJSON != nil)
    }

    /// The records a 1.0 Merge Into… leaves, arriving on a 1.1 device: the merged journal is in Recently Deleted
    /// with no entries and restores as an empty journal, and an entry that stayed deleted restores into the
    /// destination.
    func testAJournalMergedByTenOhArrivesIntact() async throws {
        let source = try await openStore("tenoh")
        let from = journal("From", seconds: 1_000)
        let into = journal("Into", seconds: 2_000)
        let live = entry("Live", text: "moved", journal: from.id)
        var gone = entry("Gone", text: "stayed deleted", journal: from.id)
        gone.deletedAt = Date(timeIntervalSince1970: 1_700_000_900)
        for item in [from, into, live, gone] { try await settle(item, in: source) }
        // What 1.0 writes for Merge Into…: entries move, the source journal is deleted.
        var movedLive = live
        movedLive.journalID = into.id
        var movedGone = gone
        movedGone.journalID = into.id
        var tombstoned = from
        tombstoned.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        for item in [movedLive, movedGone, tombstoned] { try await source.save(item) }

        let replica = try await openStore("replica")
        var cursor: Int64 = 0
        for item in [from, into, live, gone] {
            cursor += 1
            try await replica.apply([remote(item, revision: 1, cursor: cursor)], cursor: cursor)
        }
        for item in [movedLive, movedGone, tombstoned] {
            cursor += 1
            try await replica.apply([remote(item, revision: 2, cursor: cursor)], cursor: cursor)
        }
        let snapshot = try await replica.lifecycleSnapshot()
        let intoJournal = try await stored(replica, into.id)
        let entries = snapshot.items.filter { $0.kind == "entry" }
        XCTAssertTrue(entries.allSatisfy { $0.journalID == intoJournal.id })
        let sourceAfter = try await stored(replica, from.id)
        XCTAssertNotNil(sourceAfter.deletedAt, "In Recently Deleted")
        XCTAssertTrue(entries.filter { $0.journalID == from.id }.isEmpty, "With no entries")
        let restored = try await replica.restoreJournal(from.id)
        XCTAssertNil(restored.deletedAt)
        let stayedDeleted = try await replica.restoreEntry(gone.id, fallback: nil)
        XCTAssertTrue(stayedDeleted.returnedToOwnJournal)
        XCTAssertEqual(stayedDeleted.journal.id, into.id)
    }

    // MARK: The pass runs before a pull can replace a row's other version

    func testTheOneTimePassSettlesARowFromTheVersionThePersonSawBeforeAnyPullReplacesIt() async throws {
        let server = MemoryServer()
        let other = try await openStore("other")
        let otherSync = SyncEngine(store: other, server: server)
        let work = journal("Work")
        try await other.save(work)
        try await otherSync.synchronize()

        let mine = try await openStore("mine", runPass: false)
        let mineSync = SyncEngine(store: mine, server: server)
        try await mineSync.synchronize()
        var renamedHere = try await stored(mine, work.id)
        renamedHere.title = "Mine"
        try await mine.save(renamedHere)
        // The other device renames; this one receives that version and keeps it for review, as 1.0 did.
        var second = try await stored(other, work.id)
        second.title = "Second"
        try await other.save(second)
        try await otherSync.synchronize()
        let latest = await server.record(work.id)
        let secondChange = try XCTUnwrap(latest)
        try await mine.apply([secondChange], cursor: secondChange.cursor)
        let rows = try await mine.conflicts()
        XCTAssertEqual(rows.count, 1)
        // What 1.0 left: no sealed key says the pass has run, and the person quit before reviewing.
        try await mine.setSetting("kept-notes", value: nil)
        try await mine.close()

        // A third version reaches the server before this device opens the library again.
        var third = try await stored(other, work.id)
        third.title = "Third"
        try await other.save(third)
        try await otherSync.synchronize()

        let reopened = try JournalStore(directory: root.appendingPathComponent("mine"), key: key)
        addTeardownBlock { try? await reopened.close() }
        let engine = SyncEngine(store: reopened, server: server)
        try await engine.synchronize()
        let report = try await engine.synchronize()
        XCTAssertTrue(report.settled)
        let finalRecord = try await stored(reopened, work.id)
        XCTAssertEqual(finalRecord.title, "Mine")
        let history = try await reopened.history(for: work.id)
        XCTAssertEqual(Set(history.map(\.title)), ["Second", "Third"], "Every version the person did not keep")
        let atServer = await server.record(work.id)
        let serverRecord = try XCTUnwrap(atServer)
        XCTAssertEqual(serverRecord.revision, 4, "Sent on top of the third version")
        let remainingRows = try await reopened.conflicts()
        XCTAssertTrue(remainingRows.isEmpty)
        let pending = try await reopened.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    /// Settling happens in the round that read the other version: what it queues is sent without another interval.
    func testASyncRoundSendsWhatSettlingQueued() async throws {
        let server = MemoryServer()
        let first = try await openStore("first")
        let second = try await openStore("second")
        let firstSync = SyncEngine(store: first, server: server)
        let secondSync = SyncEngine(store: second, server: server)
        let work = journal("Work")
        try await first.save(work)
        try await firstSync.synchronize()
        try await secondSync.synchronize()
        var alpha = try await stored(first, work.id)
        alpha.title = "Alpha"
        try await first.save(alpha)
        var beta = try await stored(second, work.id)
        beta.title = "Beta"
        try await second.save(beta)
        try await firstSync.synchronize()
        time.withLock { $0 = $0.addingTimeInterval(10) }
        let report = try await secondSync.synchronize()
        XCTAssertEqual(report.resolvedConflicts.map(\.result), [.journalKept])
        let atServer = await server.record(work.id)
        let serverRecord = try XCTUnwrap(atServer)
        XCTAssertEqual(serverRecord.revision, 3, "The settled name was sent in the same round")
        let pending = try await second.pending()
        XCTAssertTrue(pending.isEmpty)
    }
}
