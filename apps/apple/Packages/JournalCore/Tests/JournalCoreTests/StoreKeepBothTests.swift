import GRDB
import XCTest

@testable import JournalCore

/// Entries and templates that differ (row 3 of protocol/conflicts.md): this device's version stays the record, the other
/// becomes a separate entry with a derived identity, and an untouched copy is replaced by a later version from the same
/// device and by nothing else. Real isolated stores; the multi-device conversations are in ConflictScenarioTests.
final class StoreKeepBothTests: ConflictTestCase {
    private let phone = UUID()
    private let mac = UUID()

    /// An entry that is synchronized and clean, like one another device can change, and the journal it is in.
    private func synchronizedEntry(_ text: String, in store: JournalStore) async throws -> JournalItem {
        let home = journal("Home")
        try await settle(home, in: store)
        let page = entry("Page", text: text, journal: home.id)
        try await settle(page, in: store)
        return try await stored(store, page.id)
    }
    @discardableResult private func typing(_ text: String, into item: JournalItem, in store: JournalStore)
        async throws -> JournalItem
    {
        var changed = item
        changed.document = .plain(text)
        return try await store.save(changed)
    }
    private func version(of item: JournalItem, _ text: String) -> JournalItem {
        var other = item
        other.document = .plain(text)
        other.storedVersion = nil
        return other
    }
    /// What the server would do with everything queued: accept it, so the records are clean.
    private func send(from store: JournalStore) async throws {
        for change in try await store.pending() {
            let receipt = RemoteChange(
                cursor: 100, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
    }
    private func copies(of item: JournalItem, in store: JournalStore) async throws -> [JournalItem] {
        try await store.items().filter {
            $0.kind == item.kind && $0.id != item.id && $0.title.hasSuffix("(other version)")
        }
    }
    private func payload(of id: UUID, in store: JournalStore) async throws -> String? {
        try await store.db.read {
            try String.fetchOne(
                $0, sql: "SELECT payload FROM records WHERE id=?", arguments: [id.uuidString.lowercased()])
        }
    }

    // MARK: What is kept

    func testAnEntryThatDiffersKeepsThisVersionAndMakesTheOtherAnEntryOfItsOwn() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        try await typing("mine", into: page, in: store)
        let theirs = version(of: page, "theirs")
        try await deliver(theirs, revision: 2, to: store, device: mac)

        let report = try await settleAfterPause(store)
        guard case .keptBoth(let copyID?) = try XCTUnwrap(report.resolved.first).result else {
            return XCTFail("Both versions were not kept")
        }
        let record = try await stored(store, page.id)
        XCTAssertEqual(record.document.text, "mine")
        let copy = try await stored(store, copyID)
        XCTAssertEqual(copy.document.text, "theirs")
        XCTAssertEqual(copy.title, "Page (other version)")
        XCTAssertEqual(copy.journalID, page.journalID)
        let derived = await store.copyIdentity.copyID(
            .copy, record: page.id, plaintext: try PortableRecord.encode(theirs))
        XCTAssertEqual(copyID, derived, "The identity is derived from the other version, not random")
        let sent = try await store.pending()
        XCTAssertEqual(sent.first { $0.recordID == page.id }?.baseRevision, 2, "On top of the other version")
        XCTAssertEqual(sent.first { $0.recordID == copyID }?.baseRevision, 0, "A new record")
        let notes = try await store.keptNotes()
        XCTAssertEqual(notes.map(\.kind), [.keptBoth])
        XCTAssertEqual(notes.first?.recordID, page.id)
        XCTAssertEqual(notes.first?.otherID, copyID)
        let again = try await settleAfterPause(store)
        XCTAssertTrue(again.resolved.isEmpty, "One resolution per record")
    }

    func testTheOtherVersionInRecentlyDeletedStaysThereAndTemplatesGetTemplates() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        try await typing("mine", into: page, in: store)
        var deleted = version(of: page, "theirs")
        deleted.deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await deliver(deleted, revision: 2, to: store, device: mac)
        _ = try await settleAfterPause(store)
        let deletedCopies = try await copies(of: page, in: store)
        let copy = try XCTUnwrap(deletedCopies.first)
        XCTAssertEqual(copy.deletedAt, deleted.deletedAt, "Each version stays where it is")
        let live = try await stored(store, page.id)
        XCTAssertNil(live.deletedAt)

        var weekly = JournalItem(kind: "template", title: "Weekly", document: .plain("one"))
        weekly.modifiedAt = weekly.date
        try await settle(weekly, in: store)
        let current = try await stored(store, weekly.id)
        try await typing("mine", into: current, in: store)
        try await deliver(version(of: weekly, "theirs"), revision: 2, to: store, device: mac)
        _ = try await settleAfterPause(store)
        let templateCopies = try await copies(of: weekly, in: store)
        let templateCopy = try XCTUnwrap(templateCopies.first)
        XCTAssertEqual(templateCopy.kind, "template")
        XCTAssertEqual(templateCopy.document.text, "theirs")
    }

    // MARK: Several revisions, and the open editor

    func testSeveralRevisionsPulledWhileThisVersionIsUnsentMakeOneCopyOfTheLatest() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        try await typing("mine", into: page, in: store)
        // The catch-up is split over two pages, and the record is dirty throughout.
        try await deliver(version(of: page, "second"), revision: 2, to: store, device: mac)
        try await deliver(version(of: page, "third"), revision: 3, to: store, device: mac)
        try await deliver(version(of: page, "fourth"), revision: 4, to: store, device: mac)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.remoteRevision, 4)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.count, 1)
        let made = try await copies(of: page, in: store)
        XCTAssertEqual(made.map(\.document.text), ["fourth"], "Exactly one copy, of the latest version")
        let history = try await store.history(for: page.id)
        XCTAssertEqual(Set(history.map(\.document.text)), ["second", "third"], "Earlier ones go to history")
        let pending = try await store.pending()
        XCTAssertEqual(pending.first { $0.recordID == page.id }?.baseRevision, 4)
    }

    func testTheRecordKeepsItsBytesSoTheOpenEditorSeesNothing() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let open = try await typing("mine", into: page, in: store)
        let before = try await payload(of: page.id, in: store)
        try await deliver(version(of: page, "theirs"), revision: 2, to: store, device: mac)
        _ = try await settleAfterPause(store)

        let after = try await payload(of: page.id, in: store)
        XCTAssertEqual(after, before, "Row 3 does not change the bytes of the version the person has open")
        let stored = try await stored(store, page.id)
        XCTAssertEqual(stored.storedVersion, open.storedVersion)
        // The draft the editor holds is still current: saving it again neither fails nor makes a row.
        try await store.save(open, requiringUnchanged: true)
        let rows = try await store.conflicts()
        XCTAssertTrue(rows.isEmpty)
    }

    func testARecordBeingWrittenIsNotSettledUntilItPauses() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        try await typing("mine", into: page, in: store)
        try await deliver(version(of: page, "theirs"), revision: 2, to: store, device: mac)
        let typingNow = try await store.resolveConflicts(at: .completedPull)
        XCTAssertEqual(typingNow.deferred, 1)
        XCTAssertTrue(typingNow.resolved.isEmpty)
        let paused = try await settleAfterPause(store)
        XCTAssertEqual(paused.resolved.count, 1)
    }

    func testASaveOverAVersionThatArrivedUnseenKeepsTheDraftAndTheArrivedTextSeparately() async throws {
        let store = try await openStore()
        let opened = try await synchronizedEntry("Written first", in: store)
        try await deliver(version(of: opened, "Written on the iPhone"), revision: 2, to: store, device: phone)
        // The draft was read before that arrived.
        try await typing("Written first, then typed on the Mac", into: opened, in: store)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.count, 1)
        let pending = try await store.pending()
        XCTAssertTrue(pending.filter { $0.recordID == opened.id }.isEmpty, "Nothing is sent before it is settled")

        // With no server there is no pull to wait for: it is settled once writing pauses.
        let report = try await settleAfterPause(store, .local)
        XCTAssertEqual(report.resolved.count, 1)
        let record = try await stored(store, opened.id)
        XCTAssertEqual(record.document.text, "Written first, then typed on the Mac")
        let made = try await copies(of: opened, in: store)
        XCTAssertEqual(made.map(\.document.text), ["Written on the iPhone"])
    }

    // MARK: Replacing an earlier copy

    private func madeCopy(
        of page: JournalItem, text: String, revision: Int64, device: UUID, in store: JournalStore
    ) async throws -> JournalItem {
        let current = try await stored(store, page.id)
        try await typing("mine \(text)", into: current, in: store)
        try await deliver(version(of: page, text), revision: revision, to: store, device: device)
        _ = try await settleAfterPause(store)
        let made = try await copies(of: page, in: store)
        return try XCTUnwrap(made.first { $0.document.text == text })
    }

    func testALaterVersionFromTheSameDeviceReplacesAnUntouchedCopyUnderItsOwnIdentity() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let first = try await madeCopy(of: page, text: "theirs 1", revision: 2, device: mac, in: store)
        try await send(from: store)
        let sent = try await stored(store, first.id)
        XCTAssertNotNil(sent)

        let current = try await stored(store, page.id)
        try await typing("mine 2", into: current, in: store)
        try await deliver(version(of: page, "theirs 2"), revision: 4, to: store, device: mac)
        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.first?.result, .keptBoth(copyID: first.id))
        let made = try await copies(of: page, in: store)
        XCTAssertEqual(made.map(\.id), [first.id], "Still one copy, with the identity it was first made with")
        XCTAssertEqual(made.first?.document.text, "theirs 2")
        let history = try await store.history(for: first.id)
        XCTAssertEqual(history.map(\.document.text), ["theirs 1"], "What it replaced goes to its Version History")
        let pending = try await store.pending().filter { $0.recordID == first.id }
        XCTAssertEqual(pending.map(\.baseRevision), [1], "Sent on top of the revision the copy has")
        let notes = try await store.keptNotes()
        XCTAssertEqual(notes.count, 1, "The note of the copy is updated, not repeated")
    }

    func testAnUnsentCopyIsReplacedWithoutALeftoverQueuedChange() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let first = try await madeCopy(of: page, text: "theirs 1", revision: 2, device: mac, in: store)
        // The copy was never sent; the record was.
        for change in try await store.pending() where change.recordID == page.id {
            let receipt = RemoteChange(
                cursor: 100, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                payload: change.payload, deviceId: UUID(), modifiedAt: Date())
            try await store.acknowledge(change, receipt: receipt)
        }
        let current = try await stored(store, page.id)
        try await typing("mine 2", into: current, in: store)
        try await deliver(version(of: page, "theirs 2"), revision: 4, to: store, device: mac)
        _ = try await settleAfterPause(store)
        let queued = try await store.pending().filter { $0.recordID == first.id }
        XCTAssertEqual(queued.count, 1, "One change for the copy, the later content")
        XCTAssertEqual(queued.first?.baseRevision, 0)
        let body = try await stored(store, first.id)
        XCTAssertEqual(body.document.text, "theirs 2")
    }

    func testACopyThePersonOrAnotherDeviceChangedIsNeverReplaced() async throws {
        // Edited here.
        let store = try await openStore("edited-here")
        let page = try await synchronizedEntry("first", in: store)
        let first = try await madeCopy(of: page, text: "theirs 1", revision: 2, device: mac, in: store)
        try await send(from: store)
        var renamed = try await stored(store, first.id)
        renamed.title = "A title the person chose"
        try await store.save(renamed)
        let current = try await stored(store, page.id)
        try await typing("mine 2", into: current, in: store)
        try await deliver(version(of: page, "theirs 2"), revision: 4, to: store, device: mac)
        _ = try await settleAfterPause(store)
        let after = try await stored(store, first.id)
        XCTAssertEqual(after.title, "A title the person chose")
        XCTAssertEqual(after.document.text, "theirs 1")
        let made = try await copies(of: page, in: store)
        XCTAssertEqual(made.filter { $0.document.text == "theirs 2" }.count, 1, "The later version is a new copy")

        // Edited on another device, and pulled here.
        let other = try await openStore("edited-elsewhere")
        let item = try await synchronizedEntry("first", in: other)
        let firstCopy = try await madeCopy(of: item, text: "theirs 1", revision: 2, device: mac, in: other)
        try await send(from: other)
        var elsewhere = firstCopy
        elsewhere.document = .plain("edited on the iPad")
        elsewhere.storedVersion = nil
        try await deliver(elsewhere, revision: 2, to: other, device: phone)
        let there = try await stored(other, item.id)
        try await typing("mine 2", into: there, in: other)
        try await deliver(version(of: item, "theirs 2"), revision: 4, to: other, device: mac)
        _ = try await settleAfterPause(other)
        let kept = try await stored(other, firstCopy.id)
        XCTAssertEqual(kept.document.text, "edited on the iPad", "Another device's edit is never overwritten")
        let madeThere = try await copies(of: item, in: other)
        XCTAssertTrue(madeThere.contains { $0.document.text == "theirs 2" })
    }

    func testACopyOfAnotherDevicesVersionIsNotReplacedByThisDevicesVersion() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let first = try await madeCopy(of: page, text: "from the Mac", revision: 2, device: mac, in: store)
        try await send(from: store)
        let current = try await stored(store, page.id)
        try await typing("mine 2", into: current, in: store)
        try await deliver(version(of: page, "from the iPhone"), revision: 4, to: store, device: phone)
        _ = try await settleAfterPause(store)
        let unchanged = try await stored(store, first.id)
        XCTAssertEqual(unchanged.document.text, "from the Mac")
        let made = try await copies(of: page, in: store)
        XCTAssertEqual(Set(made.map(\.document.text)), ["from the Mac", "from the iPhone"])
    }

    func testAnUnknownOriginNeverMatchesSoTwoSavesOverUnseenVersionsMakeTwoCopies() async throws {
        let store = try await openStore()
        let first = try await synchronizedEntry("first", in: store)
        var base = first
        for (index, text) in ["unseen one", "unseen two"].enumerated() {
            // The record is at revision 2 after the first round, and 3 once that was sent.
            try await deliver(version(of: first, text), revision: index == 0 ? 2 : 4, to: store, device: UUID())
            try await typing("typed \(index)", into: base, in: store)
            _ = try await settleAfterPause(store, .local)
            try await send(from: store)
            base = try await stored(store, first.id)
        }
        let made = try await copies(of: first, in: store)
        XCTAssertEqual(
            Set(made.map(\.document.text)), ["unseen one", "unseen two"],
            "A version kept by a save doesn't record its device: it is never replaced into another")
        let state = try await store.keptNotesState()
        XCTAssertEqual(state.copies.filter { $0.originDevice == nil }.count, 2)
    }

    // MARK: A derived identity that already exists

    private enum Existing: CaseIterable {
        case clean, editedElsewhere, deleted, permanentlyDeleted, madeEarlierHere
    }

    func testADerivedIdentityThatExistsInAnyStateMeansNothingIsDoneAndTheRecordStillSettles() async throws {
        for state in Existing.allCases {
            let store = try await openStore("existing-\(state)")
            let page = try await synchronizedEntry("first", in: store)
            let theirs = version(of: page, "the same words everywhere")
            let derived = await store.copyIdentity.copyID(
                .copy, record: page.id, plaintext: try PortableRecord.encode(theirs))
            var existing = theirs
            existing.id = derived
            existing.title = "Page (other version)"
            switch state {
            case .clean: try await deliver(existing, revision: 1, to: store, device: mac)
            case .editedElsewhere:
                try await deliver(existing, revision: 1, to: store, device: mac)
                existing.title = "Edited since"
                try await deliver(existing, revision: 2, to: store, device: phone)
            case .deleted:
                existing.deletedAt = Date(timeIntervalSince1970: 1_600_000_000)
                try await deliver(existing, revision: 1, to: store, device: mac)
            case .permanentlyDeleted:
                try await deliver(marker(for: existing, at: 1_650_000_000), revision: 1, to: store, device: mac)
            case .madeEarlierHere: try await store.save(existing)
            }
            let before = try await payload(of: derived, in: store)
            let queuedBefore = try await store.pending().filter { $0.recordID == derived }.map(\.payload)
            try await typing("mine", into: page, in: store)
            try await deliver(theirs, revision: 2, to: store, device: mac)

            let report = try await settleAfterPause(store)
            XCTAssertEqual(report.resolved.first?.result, .keptBoth(copyID: nil), "\(state)")
            let after = try await payload(of: derived, in: store)
            XCTAssertEqual(after, before, "\(state): no write")
            let queuedAfter = try await store.pending().filter { $0.recordID == derived }.map(\.payload)
            XCTAssertEqual(queuedAfter, queuedBefore, "\(state)")
            let notes = try await store.keptNotes()
            XCTAssertTrue(notes.isEmpty, "\(state): no note")
            let record = try await stored(store, page.id)
            XCTAssertEqual(record.document.text, "mine", "\(state): the record still settles")
            let queued = try await store.pending().first { $0.recordID == page.id }
            XCTAssertEqual(queued?.baseRevision, 2, "\(state)")
            let rows = try await store.conflicts()
            XCTAssertTrue(rows.isEmpty, "\(state)")
        }
    }

    // MARK: A copy that meets a marker

    func testAnUnsentCopyNeverRevivesACopyDeletedForGoodElsewhere() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let copy = try await madeCopy(of: page, text: "theirs", revision: 2, device: mac, in: store)
        // Another device made the same copy earlier and deleted it for good; this device had not sent its own.
        try await store.recordConflict(try remote(marker(for: copy, at: 1_820_000_000), revision: 1, cursor: 9))
        _ = try await settleAfterPause(store)
        let record = try await stored(store, copy.id)
        XCTAssertTrue(record.isCanonicalDeletionMarker, "The deletion stays final")
        let others = try await copies(of: page, in: store)
        XCTAssertTrue(others.isEmpty, "Nothing was made again")
    }

    func testACopyThisDeviceMadeIsReplacedByTheSameCopyArrivingFromAnotherClient() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        let copy = try await madeCopy(of: page, text: "theirs", revision: 2, device: mac, in: store)
        // Another client wrote the same copy with other wording and sent it first.
        var arriving = copy
        arriving.title = "Page (other version, written elsewhere)"
        arriving.storedVersion = nil
        try await store.recordConflict(try remote(arriving, revision: 1, cursor: 9, device: phone))
        _ = try await settleAfterPause(store)
        let record = try await stored(store, copy.id)
        XCTAssertEqual(record.title, arriving.title, "The arriving version wins")
        let rows = try await store.conflicts()
        XCTAssertTrue(rows.isEmpty)
        let queued = try await store.pending().filter { $0.recordID == copy.id }
        XCTAssertTrue(queued.isEmpty, "…and the local one is dropped")
    }

    // MARK: Failures, images, held records

    func testAFailedSettlementKeepsEverythingAsItWasAndTheRetryMakesTheSameCopy() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        try await typing("mine", into: page, in: store)
        let theirs = version(of: page, "theirs")
        try await deliver(theirs, revision: 2, to: store, device: mac)
        try await store.db.write { db in
            try db.execute(
                sql: """
                    CREATE TRIGGER fail_copy BEFORE INSERT ON records WHEN NEW.kind='entry'
                    BEGIN SELECT RAISE(ABORT, 'Injected failure'); END
                    """)
        }
        let cursor = try await store.cursor()
        let recordBefore = try await payload(of: page.id, in: store)
        let failed = try await settleAfterPause(store)
        XCTAssertTrue(failed.resolved.isEmpty)
        XCTAssertEqual(failed.held, 1)
        let recordAfter = try await payload(of: page.id, in: store)
        XCTAssertEqual(recordAfter, recordBefore)
        let cursorAfter = try await store.cursor()
        XCTAssertEqual(cursorAfter, cursor)
        let rows = try await store.conflicts()
        XCTAssertEqual(rows.count, 1, "The row stays for the next round")
        try await store.db.write { try $0.execute(sql: "DROP TRIGGER fail_copy") }
        let retry = try await settleAfterPause(store)
        let derived = await store.copyIdentity.copyID(
            .copy, record: page.id, plaintext: try PortableRecord.encode(theirs))
        XCTAssertEqual(retry.resolved.first?.result, .keptBoth(copyID: derived))
    }

    func testTheCopyKeepsTheOtherVersionsImagesAndOneFileServesBothEntries() async throws {
        let store = try await openStore()
        let home = journal("Home")
        let imageID = try await store.addAttachment(Data("a picture".utf8))
        var page = entry("Page", text: "first", journal: home.id)
        page.document = JournalDocument(blocks: [DocumentBlock(kind: "image", attachmentID: imageID)])
        try await settle(home, in: store)
        try await settle(page, in: store)
        // This device removed the picture while the other kept it and wrote beside it.
        let current = try await stored(store, page.id)
        try await typing("no picture any more", into: current, in: store)
        var theirs = page
        theirs.document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("with words")]), DocumentBlock(kind: "image", attachmentID: imageID),
        ])
        try await deliver(theirs, revision: 2, to: store, device: mac)
        _ = try await settleAfterPause(store)

        let imageCopies = try await copies(of: page, in: store)
        let copy = try XCTUnwrap(imageCopies.first)
        XCTAssertEqual(copy.document.attachmentIDs, [imageID], "The same attachment identity, no bytes copied")
        let referenced = try await store.referencedAttachmentIDs()
        XCTAssertTrue(referenced.contains(imageID))
        let bytes = try await store.attachment(imageID)
        XCTAssertEqual(bytes, Data("a picture".utf8))
    }

    func testAVersionThisAppCannotReadStaysHeldWhileAnotherRecordSettles() async throws {
        let store = try await openStore()
        let held = try await synchronizedEntry("held", in: store)
        let normal = entry("Normal", text: "first", journal: held.journalID)
        try await settle(normal, in: store)
        try await typing("mine", into: held, in: store)
        try await typing("mine", into: try await stored(store, normal.id), in: store)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(version(of: held, "theirs"))) as? [String: Any])
        object["futureLayout"] = ["columns": 2]
        let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let change = RemoteChange(
            cursor: 8, recordId: held.id, revision: 2, kind: "entry",
            payload: try VaultCrypto.seal(
                future, key: key, context: VaultCrypto.recordContext(id: held.id, kind: "entry")
            ).base64EncodedString(), deviceId: mac, modifiedAt: Date())
        try await store.apply([change], cursor: 8)
        try await deliver(version(of: normal, "theirs"), revision: 2, to: store, device: mac)

        let report = try await settleAfterPause(store)
        XCTAssertEqual(report.resolved.map(\.recordID), [normal.id])
        XCTAssertEqual(report.held, 1)
        let pending = try await store.pending()
        XCTAssertFalse(pending.contains { $0.recordID == held.id }, "Nothing is sent for the held record")
        let heldIDs = try await store.heldConflictIDs()
        XCTAssertEqual(heldIDs, [held.id])
    }

    // MARK: When it runs

    func testARowMadeAfterThePassWaitsForAPullAndNothingSettlesDuringAReconciliation() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        try await typing("mine", into: page, in: store)
        try await deliver(version(of: page, "theirs"), revision: 2, to: store, device: mac)
        time.withLock { $0 = $0.addingTimeInterval(3) }

        // A library that is opened again does not settle a row this version made: its other version may be an
        // intermediate one, left by a crash in the middle of a paged catch-up.
        let reopened = try await store.resolveConflicts(at: .opening(serverConfigured: true))
        XCTAssertTrue(reopened.resolved.isEmpty)
        // …nor does a reconciliation, whose revisions are not final until the whole log is compared.
        try await store.beginReconciliation(serverID: "restored")
        let reconciling = try await store.resolveConflicts(at: .completedPull)
        XCTAssertTrue(reconciling.resolved.isEmpty)
        try await store.setSetting("reconcile", value: nil)
        // With no server there is no pull to wait for.
        let withoutServer = try await store.resolveConflicts(at: .opening(serverConfigured: false))
        XCTAssertEqual(withoutServer.resolved.count, 1)
    }

    func testDeletingForGoodWaitsForAConflictThatSettlesAndRefusesOneThatIsHeld() async throws {
        let store = try await openStore()
        let page = try await synchronizedEntry("first", in: store)
        var removed = try await stored(store, page.id)
        removed.deletedAt = Date()
        try await store.save(removed)
        try await deliver(version(of: page, "theirs"), revision: 2, to: store, device: mac)
        do {
            _ = try await store.preparePermanentDeletion(page.id)
            XCTFail("An entry with changes about to be combined is not deleted for good")
        } catch PermanentDeletionError.conflict {}

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(version(of: page, "newer"))) as? [String: Any])
        object["futureLayout"] = ["columns": 2]
        let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let change = RemoteChange(
            cursor: 9, recordId: page.id, revision: 3, kind: "entry",
            payload: try VaultCrypto.seal(
                future, key: key, context: VaultCrypto.recordContext(id: page.id, kind: "entry")
            ).base64EncodedString(), deviceId: mac, modifiedAt: Date())
        try await store.recordConflict(change)
        do {
            _ = try await store.preparePermanentDeletion(page.id)
            XCTFail("An entry holding a version from a newer app is not deleted")
        } catch PermanentDeletionError.unsupported {}
    }
}
