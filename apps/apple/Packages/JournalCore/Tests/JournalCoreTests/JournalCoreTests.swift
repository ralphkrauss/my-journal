import XCTest

@testable import JournalCore

final class JournalCoreTests: XCTestCase {
    private var directories: [URL] = []
    override func tearDownWithError() throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
    }
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-test-\(UUID())")
        directories.append(url)
        return url
    }
    private func change(_ pending: PendingChange, revision: Int64, cursor: Int64 = 1) -> RemoteChange {
        RemoteChange(
            cursor: cursor, recordId: pending.recordID, revision: revision, kind: pending.kind,
            payload: pending.payload, deviceId: UUID(), modifiedAt: Date())
    }

    func testRecoveryAndTamperProtectionBindCiphertextToItsRecord() throws {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let (envelope, secret) = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase)
        let recovered = try VaultCrypto.recover(envelope, phrase: phrase)
        XCTAssertEqual(recovered.0, key)
        XCTAssertEqual(recovered.1, secret)
        XCTAssertThrowsError(try VaultCrypto.recover(envelope, phrase: "incorrect"))
        let context = VaultCrypto.recordContext(id: UUID(), kind: "entry")
        let ciphertext = try VaultCrypto.seal(Data("Private thoughts".utf8), key: key, context: context)
        XCTAssertThrowsError(try VaultCrypto.open(ciphertext, key: key, context: "another-record"))
        var damaged = ciphertext
        damaged[damaged.count - 1] ^= 1
        XCTAssertThrowsError(try VaultCrypto.open(damaged, key: key, context: context))
    }

    func testOfflineSaveSurvivesReopenWithoutPlaintextInDatabase() async throws {
        let folder = directory(), key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: folder, key: key)
        let entry = JournalItem(kind: "entry", title: "private-sentinel-769", document: .plain("My private writing"))
        try await store.save(entry)
        let reopened = try JournalStore(directory: folder, key: key)
        let restored = try await reopened.item(entry.id), pending = try await reopened.pending()
        XCTAssertEqual(restored?.title, entry.title)
        XCTAssertEqual(pending.count, 1)
        // Recent writes can still be in the write-ahead log beside the database file.
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path)
        where name.hasPrefix("journal.sqlite") {
            let database = try Data(contentsOf: folder.appendingPathComponent(name))
            XCTAssertNil(database.range(of: Data(entry.title.utf8)), name)
        }
    }

    func testEditsDuringUploadAreQueuedAgainstAcknowledgedRevision() async throws {
        let store = try JournalStore(directory: directory(), key: VaultCrypto.generateKey())
        var entry = JournalItem(kind: "entry", document: .plain("First draft"))
        try await store.save(entry)
        let original = try await store.pending()[0]
        entry.document = .plain("Continued while uploading")
        try await store.save(entry)
        try await store.acknowledge(original, receipt: change(original, revision: 1))
        let next = try await store.pending(), restored = try await store.item(entry.id)
        XCTAssertEqual(restored?.document.text, entry.document.text)
        XCTAssertEqual(next.count, 1)
        XCTAssertEqual(next[0].baseRevision, 1)
        XCTAssertNotEqual(next[0].operationId, original.operationId)
        XCTAssertNotEqual(next[0].payload, original.payload)
    }

    func testDownloadedOwnReceiptAfterLostResponseDoesNotCreateFalseConflict() async throws {
        let store = try JournalStore(directory: directory(), key: VaultCrypto.generateKey())
        let entry = JournalItem(kind: "entry", document: .plain("Saved before network failed"))
        try await store.save(entry)
        let pending = try await store.pending()[0]
        try await store.apply([change(pending, revision: 1)], cursor: 1)
        let outbox = try await store.pending(), conflicts = try await store.conflicts()
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertTrue(conflicts.isEmpty)
        let cursor = try await store.cursor()
        XCTAssertEqual(cursor, 1)
    }

    func testConflictKeepsBothVersionsAndHistoryAfterResolution() async throws {
        let key = try VaultCrypto.generateKey()
        let local = try JournalStore(directory: directory(), key: key),
            remote = try JournalStore(directory: directory(), key: key)
        var entry = JournalItem(kind: "entry", document: .plain("Original"))
        try await local.save(entry)
        let first = try await local.pending()[0], receipt = change(first, revision: 1)
        try await local.acknowledge(first, receipt: receipt)
        try await remote.apply([receipt], cursor: 1)
        entry.document = .plain("Local offline edit")
        try await local.save(entry)
        entry.document = .plain("Remote offline edit")
        try await remote.save(entry)
        let remotePending = try await remote.pending()[0]
        try await local.recordConflict(change(remotePending, revision: 2))
        let conflicts = try await local.conflicts()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].local.document.text, "Local offline edit")
        XCTAssertEqual(conflicts[0].remote.document.text, "Remote offline edit")
        try await local.resolve(conflicts[0], choice: .keepBoth)
        let items = try await local.items(), history = try await local.history(for: entry.id)
        XCTAssertEqual(Set(items.map(\.document.text)), Set(["Local offline edit", "Remote offline edit"]))
        XCTAssertEqual(history.count, 2)
        let remaining = try await local.conflicts()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCorruptRemotePageDoesNotAdvanceCursorOrPartiallyApply() async throws {
        let key = try VaultCrypto.generateKey()
        let source = try JournalStore(directory: directory(), key: key),
            destination = try JournalStore(directory: directory(), key: key)
        try await source.save(JournalItem(kind: "entry", document: .plain("Valid")))
        let pending = try await source.pending()[0]
        let valid = change(pending, revision: 1)
        var invalid = valid
        invalid.recordId = UUID()
        invalid.cursor = 2
        do {
            try await destination.apply([valid, invalid], cursor: 2)
            XCTFail("Tampering should fail")
        } catch {}
        let items = try await destination.items(), cursor = try await destination.cursor()
        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(cursor, 0)
    }

    func testVaultSnapshotPreservesCiphertextPendingReceiptsAndCursor() async throws {
        let key = try VaultCrypto.generateKey()
        let source = try JournalStore(directory: directory(), key: key)
        let imageID = try await source.addAttachment(Data("original image bytes".utf8))
        var item = JournalItem(kind: "entry", document: .plain("Before disconnect"))
        try await source.save(item)
        let first = try await source.pending()[0]
        try await source.apply([change(first, revision: 1, cursor: 17)], cursor: 17)
        item.document = .plain("Edited while disconnected")
        try await source.save(item)
        let pending = try await source.pending()[0]
        let copiedDirectory = directory()
        try await source.snapshot(to: copiedDirectory)
        let copy = try JournalStore(directory: copiedDirectory, key: key)
        let copiedPending = try await copy.pending()[0]
        let copiedImage = try await copy.encryptedAttachment(imageID)
        let originalImage = try await source.encryptedAttachment(imageID)
        XCTAssertEqual(copiedImage, originalImage)
        XCTAssertEqual(copiedPending.operationId, pending.operationId)
        XCTAssertEqual(copiedPending.baseRevision, pending.baseRevision)
        XCTAssertEqual(copiedPending.payload, pending.payload)
        let cursor = try await copy.cursor()
        XCTAssertEqual(cursor, 17)
        item.document = .plain("Later source edit")
        try await source.save(item)
        let copiedEntry = try await copy.item(item.id)
        XCTAssertEqual(copiedEntry?.document.text, "Edited while disconnected")
    }

    func testHTTPSRequiredExceptLoopbackAndCredentialsRejectedInURL() throws {
        XCTAssertThrowsError(try ServerClient(address: "http://example.com"))
        XCTAssertThrowsError(try ServerClient(address: "https://user:secret@example.com"))
        XCTAssertNoThrow(try ServerClient(address: "http://127.0.0.1:8080"))
        XCTAssertNoThrow(try ServerClient(address: "https://journal.example.ts.net"))
    }
}
