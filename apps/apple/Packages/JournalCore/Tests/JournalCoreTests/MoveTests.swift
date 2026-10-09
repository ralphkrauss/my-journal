import XCTest

@testable import JournalCore

final class MoveTests: XCTestCase {
    func testMovePreservesIdentityImagesHistoryAndRetryBaseline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let source = JournalItem(kind: "journal", title: "Personal")
        let destination = JournalItem(kind: "journal", title: "Work")
        let imageID = try await store.addAttachment(Data("Preserved original image".utf8))
        let entry = JournalItem(
            kind: "entry", journalID: source.id, title: "Meeting",
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "Notes")]))
        for item in [source, destination, entry] { try await store.save(item) }
        let remote = try JournalStore(directory: root.appendingPathComponent("other"), key: key)
        var other = entry
        other.title = "Other version"
        try await remote.save(other)
        let remotePending = try await remote.pending()
        let original = try XCTUnwrap(remotePending.first)
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: entry.id, revision: 1,
                kind: "entry", payload: original.payload, deviceId: UUID(), modifiedAt: Date()))
        do {
            _ = try await store.moveEntry(entry.id, to: destination.id)
            XCTFail("An unsettled conflict must be settled before moving.")
        } catch JournalLifecycleError.conflict {}
        let conflicts = try await store.conflicts()
        try await store.resolve(try XCTUnwrap(conflicts.first), choice: .local)
        let history = try await store.history(for: entry.id)
        XCTAssertEqual(history.count, 2)
        let before = try await store.pending()
        let ciphertext = try await store.encryptedAttachment(imageID)
        let savedEntry = try await store.item(entry.id)
        let moved = try await store.moveEntry(entry.id, to: destination.id)
        XCTAssertEqual(moved.id, entry.id)
        XCTAssertEqual(moved.journalID, destination.id)
        XCTAssertEqual(moved.document, entry.document)
        XCTAssertEqual(moved.date, savedEntry?.date)
        let after = try await store.pending()
        let beforeMove = try XCTUnwrap(before.first { $0.recordID == entry.id })
        let afterMove = try XCTUnwrap(after.first { $0.recordID == entry.id })
        XCTAssertEqual(afterMove.operationId, beforeMove.operationId)
        XCTAssertEqual(afterMove.baseRevision, beforeMove.baseRevision)
        XCTAssertEqual(afterMove.payload, beforeMove.payload)
        try await store.acknowledge(
            afterMove,
            receipt: RemoteChange(
                cursor: 2, recordId: entry.id,
                revision: afterMove.baseRevision + 1, kind: "entry", payload: afterMove.payload,
                deviceId: UUID(), modifiedAt: Date()))
        let queued = try await store.pending()
        let membership = try XCTUnwrap(queued.first { $0.recordID == entry.id })
        XCTAssertNotEqual(membership.operationId, afterMove.operationId)
        XCTAssertEqual(membership.baseRevision, afterMove.baseRevision + 1)
        let replica = try JournalStore(directory: root.appendingPathComponent("replica"), key: key)
        try await replica.apply(
            [
                RemoteChange(
                    cursor: 3, recordId: entry.id,
                    revision: membership.baseRevision + 1, kind: "entry", payload: membership.payload,
                    deviceId: UUID(), modifiedAt: Date())
            ], cursor: 3)
        let replicated = try await replica.item(entry.id)
        XCTAssertEqual(replicated?.journalID, destination.id)
        let reopened = try JournalStore(directory: root, key: key)
        let restored = try await reopened.item(entry.id)
        let restoredHistory = try await reopened.history(for: entry.id)
        let restoredImage = try await reopened.encryptedAttachment(imageID)
        XCTAssertEqual(restored?.journalID, destination.id)
        XCTAssertEqual(restoredHistory, history)
        XCTAssertEqual(restoredImage, ciphertext)
    }

    func testDeletedDestinationCannotChangeEntryOrItsPendingOperation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        var destination = JournalItem(kind: "journal", title: "Removed")
        destination.deletedAt = Date()
        let entry = JournalItem(kind: "entry", journalID: UUID(), title: "Keep here")
        try await store.save(destination)
        try await store.save(entry)
        let pending = try await store.pending()
        let originalEntry = try await store.item(entry.id)
        do {
            _ = try await store.moveEntry(entry.id, to: destination.id)
            XCTFail("A removed destination must not accept an entry.")
        } catch JournalError.server {}
        let stored = try await store.item(entry.id)
        let after = try await store.pending()
        XCTAssertEqual(stored, originalEntry)
        XCTAssertEqual(after.map(\.operationId), pending.map(\.operationId))
        XCTAssertEqual(after.map(\.payload), pending.map(\.payload))
    }
}
