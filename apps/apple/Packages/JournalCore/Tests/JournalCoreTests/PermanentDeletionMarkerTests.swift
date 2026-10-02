import GRDB
import XCTest

@testable import JournalCore

final class PermanentDeletionMarkerTests: XCTestCase {
    func testCleanDeletionPurgesRecoveryAndBlocksResurrectionFromSaveHistoryAndReplay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let original = JournalItem(kind: "entry", journalID: journal.id, title: "Private words")
        try await store.apply(
            [remote(journal, revision: 1, key: key), remote(original, revision: 1, key: key)], cursor: 1)
        var edited = original
        edited.title = "Local editing"
        try await store.save(edited)
        var other = original
        other.title = "Other editing"
        try await store.recordConflict(remote(other, revision: 2, key: key))
        let conflicts = try await store.conflicts()
        _ = try await store.resolve(XCTUnwrap(conflicts.first), choice: .local)
        let pending = try await store.pending()
        let request = try XCTUnwrap(pending.first)
        try await store.acknowledge(request, receipt: receipt(request))
        let history = try await store.history(for: original.id)
        // The received version, kept before the first change here, and both reviewed versions.
        XCTAssertEqual(history.map(\.title), [other.title, edited.title, original.title])
        let marker = JournalItem.permanentDeletionMarker(for: original, at: Date(timeIntervalSince1970: 1_800_000_000))
        let deletion = try remote(marker, revision: 4, key: key)
        let dirtyPath = root.appendingPathComponent("dirty-copy")
        try await store.snapshot(to: dirtyPath)
        let dirty = try JournalStore(directory: dirtyPath, key: key)
        edited.title = "Unpublished change must retain earlier recovery history"
        try await dirty.save(edited)
        try await dirty.apply([deletion], cursor: 4)
        let dirtyHistory = try await dirty.history(for: original.id)
        XCTAssertEqual(dirtyHistory, history)
        try await dirty.close()
        try await store.apply([deletion], cursor: 4)
        let removedHistory = try await store.history(for: original.id)
        XCTAssertTrue(removedHistory.isEmpty)
        let visible = try await store.viewSnapshot()
        XCTAssertFalse(visible.items.contains { $0.id == original.id })
        do {
            try await store.save(original)
            XCTFail("Stale autosave must not revive a permanent deletion.")
        } catch PermanentDeletionError.permanentlyDeleted {}
        do {
            _ = try await store.restoreHistoryCopy(XCTUnwrap(history.first), to: journal.id)
            XCTFail("Ordinary history restoration must not bypass permanent deletion.")
        } catch PermanentDeletionError.permanentlyDeleted {}
        try await store.apply([remote(original, revision: 1, key: key)], cursor: 4)
        let afterReplay = try await store.item(original.id)
        XCTAssertEqual(afterReplay, marker)
        // A higher revision from an offline device is preserved for explicit review, even after a clean marker.
        try await store.apply([remote(other, revision: 5, key: key)], cursor: 5)
        let afterEdit = try await store.item(original.id)
        XCTAssertEqual(afterEdit, marker)
        let retained = try await store.conflicts()
        let conflict = try XCTUnwrap(retained.first)
        XCTAssertEqual(conflict.remote.title, other.title)
        for choice in [ConflictChoice.local, .remote, .keepBoth] {
            do {
                _ = try await store.resolve(conflict, choice: choice)
                XCTFail("Deletion conflicts need the dedicated consent flow.")
            } catch PermanentDeletionError.permanentlyDeleted {}
        }
        var laterEdit = other
        laterEdit.title = "Still later offline editing"
        try await store.apply([remote(laterEdit, revision: 6, key: key)], cursor: 6)
        let superseded = try await store.history(for: original.id)
        XCTAssertEqual(superseded.map(\.title), [other.title])
        // Repeating the same page must not duplicate the superseded version.
        try await store.apply([remote(laterEdit, revision: 6, key: key)], cursor: 6)
        let repeatedHistory = try await store.history(for: original.id)
        XCTAssertEqual(repeatedHistory, superseded)
        try await store.close()
        let reopened = try JournalStore(directory: root, key: key)
        let durable = try await reopened.conflicts()
        XCTAssertEqual(durable.first?.remote.title, laterEdit.title)
        try await reopened.close()
    }

    func testDirtyEditAndMarkerSurviveArchiveAndAdditiveImportWithoutChangingRetryBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Unsynced work")
        try await store.apply([remote(journal, revision: 1, key: key)], cursor: 1)
        try await store.save(entry)
        let before = try await store.pending()
        let request = try XCTUnwrap(before.first)
        let marker = JournalItem.permanentDeletionMarker(for: entry, at: Date(timeIntervalSince1970: 1_800_000_000))
        try await store.recordConflict(remote(marker, revision: 1, key: key))
        let pending = try await store.pending()
        XCTAssertTrue(pending.isEmpty)
        let conflicted = try await store.conflicts()
        XCTAssertEqual(conflicted.first?.remote, marker)
        let afterConflict = try await store.item(entry.id)
        XCTAssertEqual(afterConflict?.title, entry.title)
        var configuration = Configuration()
        configuration.readonly = true
        let database = try DatabaseQueue(
            path: root.appendingPathComponent("source/journal.sqlite").path, configuration: configuration)
        let retry = try await database.read { db -> PendingChange in
            let row = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM outbox"))
            return PendingChange(
                operationId: try XCTUnwrap(UUID(uuidString: row["operation"])),
                recordID: try XCTUnwrap(UUID(uuidString: row["record"])), baseRevision: row["base"],
                kind: row["kind"], payload: row["payload"])
        }
        XCTAssertEqual(retry.operationId, request.operationId)
        XCTAssertEqual(retry.payload, request.payload)
        XCTAssertEqual(retry.baseRevision, request.baseRevision)
        try database.close()
        let deletedParent = JournalItem.permanentDeletionMarker(for: journal, at: marker.date)
        try await store.apply([remote(deletedParent, revision: 2, key: key)], cursor: 2)
        let lifecycle = try await store.lifecycleSnapshot()
        XCTAssertTrue(lifecycle.liveJournals.isEmpty)
        XCTAssertEqual(lifecycle.location(of: entry), .unavailable(.missing))
        let phrase = "marker archive recovery fixture"
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let archive = root.appendingPathComponent("deletion.journalarchive")
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        let destination = try JournalStore(
            directory: root.appendingPathComponent("destination"), key: VaultCrypto.generateKey())
        try await destination.importAsNewJournals(from: restored.store)
        let imported = try await destination.items()
        let parent = try XCTUnwrap(imported.first { $0.kind == "journal" })
        let copy = try XCTUnwrap(imported.first { $0.kind == "entry" })
        XCTAssertTrue(parent.isCanonicalDeletionMarker)
        XCTAssertNotEqual(parent.id, journal.id)
        XCTAssertEqual(copy.journalID, parent.id)
        XCTAssertEqual(copy.title, entry.title)
        let importedConflicts = try await destination.conflicts()
        XCTAssertEqual(importedConflicts.first?.id, copy.id)
        XCTAssertEqual(importedConflicts.first?.remote.isCanonicalDeletionMarker, true)
        try await destination.close()
        try await restored.store.close()
        try await store.close()
    }

    func testMalformedMarkerCannotEraseContentAndFutureFieldsArePreserved() throws {
        let entry = JournalItem(kind: "entry", title: "Keep this text")
        var malformed = entry
        malformed.permanentlyDeletedAt = entry.date
        XCTAssertThrowsError(try PortableRecord.decode(JournalCoding.encoder().encode(malformed)))
        XCTAssertThrowsError(try PortableRecord.encode(malformed))
        let marker = JournalItem.permanentDeletionMarker(for: entry, at: Date(timeIntervalSince1970: 1_800_000_000))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: PortableRecord.encode(marker)) as? [String: Any])
        object["futureDeletionMetadata"] = ["reason": "Preserve unknown fields"]
        let bytes = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let future = try PortableRecord.decode(bytes)
        XCTAssertFalse(future.document.isEditable)
        XCTAssertFalse(future.isCanonicalDeletionMarker)
        XCTAssertEqual(try PortableRecord.encode(future), bytes)
    }

    private func remote(_ item: JournalItem, revision: Int64, key: Data) throws -> RemoteChange {
        RemoteChange(
            cursor: revision, recordId: item.id, revision: revision, kind: item.kind,
            payload: try VaultCrypto.seal(
                PortableRecord.encode(item), key: key,
                context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
            ).base64EncodedString(),
            deviceId: UUID(), modifiedAt: item.modifiedAt)
    }
    private func receipt(_ request: PendingChange) -> RemoteChange {
        RemoteChange(
            cursor: request.baseRevision + 1, recordId: request.recordID, revision: request.baseRevision + 1,
            kind: request.kind, payload: request.payload, deviceId: UUID(), modifiedAt: Date())
    }
}
