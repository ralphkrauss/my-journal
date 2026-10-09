import Foundation
import XCTest

@testable import JournalCore

final class EntryArchivingTests: XCTestCase {
    func testArchivePatchPreservesContentAndRetryThenConvergesAfterAcknowledgment() async throws {
        let (store, key) = try makeStore()
        let journal = JournalItem(kind: "journal", title: "Work")
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: "Before")
        try await store.save(journal)
        try await store.save(entry)
        let pending = try await store.pending()
        let initial = try XCTUnwrap(pending.first { $0.recordID == entry.id })
        entry.title = "Latest title"
        entry.document = .plain("Latest writing")
        try await store.save(entry)
        let archived = try await store.setEntryArchived(entry.id, expectedArchivedAt: nil, archived: true)
        XCTAssertEqual(archived.title, entry.title)
        XCTAssertEqual(archived.document, entry.document)
        XCTAssertEqual(archived.journalID, journal.id)
        XCTAssertEqual(archived.date.timeIntervalSince1970, entry.date.timeIntervalSince1970, accuracy: 1)
        XCTAssertNotNil(archived.archivedAt)
        let after = try await store.pending()
        let retry = try XCTUnwrap(after.first { $0.recordID == entry.id })
        XCTAssertEqual(retry.operationId, initial.operationId)
        XCTAssertEqual(retry.payload, initial.payload)
        try await store.acknowledge(initial, receipt: receipt(initial, cursor: 1))
        let next = try await store.pending()
        let queued = try XCTUnwrap(next.first { $0.recordID == entry.id })
        XCTAssertNotEqual(queued.operationId, initial.operationId)
        let payload = try XCTUnwrap(Data(base64Encoded: queued.payload))
        let decoded = try PortableRecord.decode(
            VaultCrypto.open(payload, key: key, context: VaultCrypto.recordContext(id: entry.id, kind: "entry")))
        XCTAssertEqual(decoded, archived)
        try await store.acknowledge(queued, receipt: receipt(queued, cursor: 2))
        do {
            _ = try await store.setEntryArchived(entry.id, expectedArchivedAt: nil, archived: false)
            XCTFail("Stale archive consent must not undo a newer action.")
        } catch EntryArchivingError.changed {}
        let unarchived = try await store.setEntryArchived(
            entry.id, expectedArchivedAt: archived.archivedAt, archived: false)
        XCTAssertNil(unarchived.archivedAt)
        XCTAssertEqual(unarchived.document, archived.document)
    }

    func testDeletedParentRefusesArchiveAndRecoveryPreservesSiblingArchiveState() async throws {
        let (store, _) = try makeStore()
        let journal = JournalItem(kind: "journal", title: "Work")
        let destination = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "One")
        let sibling = JournalItem(kind: "entry", journalID: journal.id, title: "Two")
        for item in [journal, destination, entry, sibling] { try await store.save(item) }
        let archived = try await store.setEntryArchived(entry.id, expectedArchivedAt: nil, archived: true)
        let archivedSibling = try await store.setEntryArchived(sibling.id, expectedArchivedAt: nil, archived: true)
        let moved = try await store.moveEntry(entry.id, to: destination.id)
        XCTAssertEqual(moved.archivedAt, archived.archivedAt)
        _ = try await store.moveEntry(entry.id, to: journal.id)
        let plan = try await store.prepareJournalDeletion(journal.id)
        XCTAssertEqual(plan.entryIDs, [entry.id, sibling.id])
        _ = try await store.deleteJournal(plan)
        do {
            _ = try await store.setEntryArchived(entry.id, expectedArchivedAt: archived.archivedAt, archived: false)
            XCTFail("Archiving must not bypass parent recovery.")
        } catch EntryArchivingError.unavailable {}
        _ = try await store.restoreJournal(journal.id)
        let restored = try await store.item(entry.id)
        XCTAssertEqual(restored?.archivedAt, archived.archivedAt)
        let recovered = try await store.restoreEntry(entry.id, fallback: nil).entry
        XCTAssertEqual(
            recovered.archivedAt, archived.archivedAt, "Restore doesn't unarchive an entry that isn't deleted")
        let retained = try await store.item(sibling.id)
        XCTAssertEqual(retained, archivedSibling)
        var marker = JournalItem.permanentDeletionMarker(for: archived, at: archived.date)
        XCTAssertNil(try PortableRecord.decode(PortableRecord.encode(marker)).archivedAt)
        marker.archivedAt = archived.archivedAt
        XCTAssertThrowsError(try PortableRecord.encode(marker))
        var invalid = journal
        invalid.archivedAt = archived.archivedAt
        XCTAssertThrowsError(try PortableRecord.encode(invalid))
    }

    func testArchiveCannotResolveConcurrentEditsOrParentConflicts() async throws {
        let (store, key) = try makeStore()
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Local writing")
        try await store.save(journal)
        try await store.save(entry)
        for item in [entry, journal] {
            var remote = item
            remote.title = "Concurrent writing"
            let payload = try VaultCrypto.seal(
                PortableRecord.encode(remote), key: key,
                context: VaultCrypto.recordContext(id: item.id, kind: item.kind))
            try await store.recordConflict(
                RemoteChange(
                    cursor: 1, recordId: item.id, revision: 1, kind: item.kind,
                    payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
            do {
                _ = try await store.setEntryArchived(entry.id, expectedArchivedAt: nil, archived: true)
                XCTFail("Archive must not silently resolve concurrent changes.")
            } catch JournalLifecycleError.conflict(let identifier) {
                XCTAssertEqual(identifier, item.id)
            }
            let conflicts = try await store.conflicts()
            let captured = try XCTUnwrap(conflicts.first { $0.id == item.id })
            XCTAssertEqual(captured.remote.title, remote.title)
            let unchanged = try await store.item(entry.id)
            XCTAssertNil(unchanged?.archivedAt)
            XCTAssertEqual(unchanged?.title, entry.title)
            _ = try await store.resolve(captured, choice: .local)
        }
    }

    private func makeStore() throws -> (JournalStore, Data) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: directory, key: key)
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: directory)
        }
        return (store, key)
    }

    private func receipt(_ change: PendingChange, cursor: Int64) -> RemoteChange {
        RemoteChange(
            cursor: cursor, recordId: change.recordID, revision: change.baseRevision + 1, kind: change.kind,
            payload: change.payload, deviceId: UUID(), modifiedAt: Date())
    }
}
