import XCTest

@testable import JournalCore

@MainActor
final class JournalLifecycleTests: XCTestCase {
    private var cursor: Int64 = 0

    func testInheritedDeletionSurvivesPartialDeliveryRepeatedCyclesAndLateEntries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let source = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let replica = try JournalStore(directory: root.appendingPathComponent("replica"), key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Late entry")
        var independent = JournalItem(kind: "entry", journalID: journal.id, title: "Deleted separately")
        independent.deletedAt = Date()
        for item in [journal, entry, independent] { try await source.save(item) }
        let initial = try await upload(source)
        let offline = try JournalStore(directory: root.appendingPathComponent("offline"), key: key)
        try await offline.apply(initial, cursor: cursor)
        let late = JournalItem(kind: "entry", journalID: journal.id, title: "Offline notes")
        try await offline.save(late)
        let entryChange = try XCTUnwrap(initial.first { $0.recordId == entry.id })
        try await replica.apply([entryChange], cursor: entryChange.cursor)
        var snapshot = try await replica.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: entry), .unavailable(.missing))
        let childBefore = try await source.item(entry.id)
        let plan = try await source.prepareJournalDeletion(journal.id)
        _ = try await source.deleteJournal(plan)
        let deletedChanges = try await upload(source)
        let deletion = try XCTUnwrap(deletedChanges.first)
        try await replica.apply([deletion], cursor: deletion.cursor)
        snapshot = try await replica.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: entry), .recentlyDeleted)
        let childAfter = try await source.item(entry.id)
        XCTAssertEqual(childBefore, childAfter, "Parent deletion must not write child tombstones.")
        _ = try await source.restoreJournal(journal.id)
        let restoredChanges = try await upload(source)
        let restoration = try XCTUnwrap(restoredChanges.first)
        try await replica.apply([restoration], cursor: restoration.cursor)
        let independentChange = try XCTUnwrap(initial.first { $0.recordId == independent.id })
        try await replica.apply([independentChange], cursor: restoration.cursor)
        snapshot = try await replica.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: entry), .journal)
        XCTAssertEqual(snapshot.location(of: independent), .recentlyDeleted)
        for _ in 0..<2 {
            let current = try await source.prepareJournalDeletion(journal.id)
            _ = try await source.deleteJournal(current)
            let removed = try await upload(source)
            try await replica.apply(removed, cursor: cursor)
            _ = try await source.restoreJournal(journal.id)
            let restored = try await upload(source)
            try await replica.apply(restored, cursor: cursor)
        }
        // A stale parent tombstone cannot undo a newer restoration, regardless of delivery order.
        try await replica.apply([deletion], cursor: cursor)
        snapshot = try await replica.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: entry), .journal)
        XCTAssertEqual(snapshot.location(of: independent), .recentlyDeleted)
        // This third store authored its entry before deletion and never received the parent lifecycle changes.
        let arrival = try await upload(offline)
        try await replica.apply(arrival, cursor: cursor)
        snapshot = try await replica.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: late), .journal)
        try await offline.close()
        try await source.close()
        try await replica.close()
    }

    func testStaleConfirmationAndSingleEntryRecoveryPreserveOtherRecordsAndRetryBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let parent = JournalItem(kind: "journal", title: "Personal")
        let target = JournalItem(kind: "journal", title: "Work")
        let imageID = try await store.addAttachment(Data("Original image".utf8))
        let entry = JournalItem(
            kind: "entry", journalID: parent.id,
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "Notes")]))
        for item in [parent, target, entry] { try await store.save(item) }
        let stale = try await store.prepareJournalDeletion(parent.id)
        let added = JournalItem(kind: "entry", journalID: parent.id, title: "Arrived after confirmation")
        try await store.save(added)
        do {
            _ = try await store.deleteJournal(stale)
            XCTFail("An expanded local set requires renewed confirmation.")
        } catch JournalLifecycleError.changed {}
        let unchanged = try await store.item(parent.id)
        XCTAssertNil(unchanged?.deletedAt)
        let renamedPlan = try await store.prepareJournalDeletion(parent.id)
        var renamed = parent
        renamed.title = "Personal archive"
        try await store.save(renamed)
        do {
            _ = try await store.deleteJournal(renamedPlan)
            XCTFail("The confirmation must identify the current journal name.")
        } catch JournalLifecycleError.changed {}
        let plan = try await store.prepareJournalDeletion(parent.id)
        let pending = try await store.pending()
        _ = try await store.deleteJournal(plan)
        do {
            _ = try await store.deleteJournal(plan)
            XCTFail("An already deleted journal must not invite repeated deletion.")
        } catch JournalLifecycleError.alreadyDeleted {}
        let after = try await store.pending()
        XCTAssertEqual(after.map(\.operationId), pending.map(\.operationId))
        XCTAssertEqual(after.map(\.payload), pending.map(\.payload))
        let moved = try await store.moveEntry(entry.id, to: target.id)
        XCTAssertEqual(moved.document, entry.document)
        var legacy = added
        legacy.deletedAt = Date()
        legacy.deletedWithJournal = true
        try await store.save(legacy)
        do {
            _ = try await store.restoreJournal(parent.id, expectedTitle: parent.title)
            XCTFail("A renamed journal requires renewed restoration confirmation.")
        } catch JournalLifecycleError.changed {}
        let stillDeleted = try await store.item(parent.id)
        XCTAssertNotNil(stillDeleted?.deletedAt)
        _ = try await store.restoreJournal(parent.id, expectedTitle: renamed.title)
        do {
            _ = try await store.restoreJournal(parent.id, expectedTitle: renamed.title)
            XCTFail("An already restored journal must report the completed state.")
        } catch JournalLifecycleError.alreadyRestored {}
        var snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: legacy), .recentlyDeleted)
        let deleteAgain = try await store.prepareJournalDeletion(parent.id)
        _ = try await store.deleteJournal(deleteAgain)
        let recovered = try await store.restoreAndMoveEntry(legacy.id, to: target.id)
        let retainedParent = try await store.item(parent.id)
        XCTAssertNotNil(retainedParent?.deletedAt)
        XCTAssertFalse(recovered.deletedWithJournal)
        XCTAssertNil(recovered.deletedAt)
        snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: recovered), .journal)
        XCTAssertEqual(snapshot.location(of: moved), .journal)
        let image = try await store.attachment(imageID)
        XCTAssertEqual(image, Data("Original image".utf8))
        try await store.close()
    }

    func testParentConflictAndUnsupportedParentBlockLifecycleMutation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root.appendingPathComponent("vault"), key: key)
        var journal = JournalItem(kind: "journal", title: "Shared")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Private until reviewed")
        let target = JournalItem(kind: "journal", title: "Destination")
        for item in [journal, entry, target] { try await store.save(item) }
        _ = try await upload(store)
        journal.title = "Local name"
        try await store.save(journal)
        var remote = journal
        remote.deletedAt = Date()
        let encrypted = try VaultCrypto.seal(
            JournalCoding.encoder().encode(remote), key: key,
            context: VaultCrypto.recordContext(id: journal.id, kind: "journal"))
        try await store.recordConflict(
            RemoteChange(
                cursor: 10, recordId: journal.id, revision: 2, kind: "journal",
                payload: encrypted.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
        let snapshot = try await store.lifecycleSnapshot()
        XCTAssertEqual(snapshot.location(of: entry), .unavailable(.conflict))
        do {
            _ = try await store.prepareJournalDeletion(journal.id)
            XCTFail("A parent conflict must be reviewed.")
        } catch JournalLifecycleError.conflict(let id) { XCTAssertEqual(id, journal.id) }
        do {
            _ = try await store.restoreAndMoveEntry(entry.id, to: target.id)
            XCTFail("Moving must not silently decide a parent conflict.")
        } catch JournalLifecycleError.conflict(let id) { XCTAssertEqual(id, journal.id) }
        let conflicts = try await store.conflicts()
        _ = try await store.resolve(XCTUnwrap(conflicts.first), choice: .local)
        _ = try await upload(store)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JournalCoding.encoder().encode(journal)) as? [String: Any])
        object["futureJournalRules"] = ["hidden": true]
        let unknown = try JSONSerialization.data(withJSONObject: object)
        let wrapped = try VaultCrypto.seal(
            unknown, key: key, context: VaultCrypto.recordContext(id: journal.id, kind: "journal"))
        try await store.apply(
            [
                RemoteChange(
                    cursor: 20, recordId: journal.id, revision: 4, kind: "journal",
                    payload: wrapped.base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
            ], cursor: 20)
        let unsupported = try await store.lifecycleSnapshot()
        XCTAssertEqual(unsupported.location(of: entry), .unavailable(.unsupported))
        do {
            _ = try await store.moveEntry(entry.id, to: journal.id)
            XCTFail("An unsupported destination must not receive a supported entry.")
        } catch JournalError.unsupportedFormat {}
        let preserved = try await store.item(journal.id)
        XCTAssertEqual(try PortableRecord.encode(XCTUnwrap(preserved)), unknown)
        try await store.close()
    }

    private func upload(_ source: JournalStore) async throws -> [RemoteChange] {
        var changes: [RemoteChange] = []
        while changes.count < 100 {
            let pending = try await source.pending()
            if pending.isEmpty { return changes }
            for change in pending {
                cursor += 1
                let receipt = RemoteChange(
                    cursor: cursor, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
                    payload: change.payload, deviceId: UUID(), modifiedAt: Date())
                try await source.acknowledge(change, receipt: receipt)
                changes.append(receipt)
            }
        }
        throw JournalError.server("The synthetic sync did not drain its outbox.")
    }
}
