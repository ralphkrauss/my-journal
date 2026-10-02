import CryptoKit
import GRDB
import XCTest

@testable import JournalCore

/// A save made from a copy read before the stored record changed, for example before sync applied an edit from
/// another device, must never overwrite that change.
final class StaleSaveTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func openStore() throws -> JournalStore {
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock { try? await store.close() }
        return store
    }
    private func remote(_ item: JournalItem, revision: Int64, cursor: Int64) throws -> RemoteChange {
        try remote(PortableRecord.encode(item), id: item.id, kind: item.kind, revision: revision, cursor: cursor)
    }
    private func remote(_ plaintext: Data, id: UUID, kind: String, revision: Int64, cursor: Int64) throws
        -> RemoteChange
    {
        let sealed = try VaultCrypto.seal(plaintext, key: key, context: VaultCrypto.recordContext(id: id, kind: kind))
        return RemoteChange(
            cursor: cursor, recordId: id, revision: revision, kind: kind, payload: sealed.base64EncodedString(),
            deviceId: UUID(), modifiedAt: Date())
    }
    /// Saves and acknowledges an entry, so it is synchronized and clean like one another device can change.
    private func synchronizedEntry(_ text: String, in store: JournalStore) async throws -> JournalItem {
        let entry = JournalItem(kind: "entry", journalID: UUID(), document: .plain(text))
        try await store.save(entry)
        let pending = try await store.pending().first { $0.recordID == entry.id }
        let queued = try XCTUnwrap(pending)
        try await store.acknowledge(
            queued,
            receipt: RemoteChange(
                cursor: 1, recordId: entry.id, revision: 1, kind: "entry", payload: queued.payload,
                deviceId: UUID(), modifiedAt: Date()))
        let stored = try await store.item(entry.id)
        return try XCTUnwrap(stored)
    }

    func testASaveBasedOnAnOlderVersionKeepsBothVersionsForReview() async throws {
        let store = try openStore()
        let opened = try await synchronizedEntry("Written first", in: store)
        var fromPhone = opened
        fromPhone.document = .plain("Written on the iPhone")
        try await store.apply([remote(fromPhone, revision: 2, cursor: 2)], cursor: 2)

        var typed = opened
        typed.document = .plain("Written first, then typed on the Mac")
        try await store.save(typed)

        let conflicts = try await store.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(conflict.remote.document.text, "Written on the iPhone")
        XCTAssertEqual(conflict.local.document.text, typed.document.text)
        let pending = try await store.pending()
        XCTAssertTrue(pending.isEmpty, "Nothing is sent until the versions are reviewed")
        try await store.resolve(conflict, choice: .keepBoth)
        let texts = Set(try await store.items().map(\.document.text))
        XCTAssertTrue(texts.isSuperset(of: ["Written on the iPhone", typed.document.text]))

        // Removing an untouched entry must not happen when anything arrived after it was read.
        let untouched = try await synchronizedEntry("", in: store)
        var written = untouched
        written.document = .plain("Written elsewhere")
        try await store.apply([remote(written, revision: 2, cursor: 3)], cursor: 3)
        var removed = untouched
        removed.deletedAt = Date()
        do {
            try await store.save(removed, requiringUnchanged: true)
            XCTFail("A changed entry must not be removed")
        } catch JournalError.conflict {}
        let kept = try await store.item(untouched.id)
        XCTAssertEqual(kept?.document.text, "Written elsewhere")
        XCTAssertNil(kept?.deletedAt)
    }

    func testTypingIntoAnEntryDeletedElsewhereAsksForReviewInsteadOfFailing() async throws {
        let store = try openStore()
        let opened = try await synchronizedEntry("Kept writing", in: store)
        let marker = JournalItem.permanentDeletionMarker(for: opened, at: Date())
        try await store.apply([remote(marker, revision: 2, cursor: 2)], cursor: 2)
        var typed = opened
        typed.document = .plain("Kept writing after it was deleted elsewhere")
        try await store.save(typed)
        let review = try await store.prepareDeletionConflict(opened.id)
        XCTAssertEqual(review.edited?.document.text, typed.document.text)
        XCTAssertTrue(review.deletion.isPermanentlyDeleted)
    }

    func testASaveNeverReplacesARecordFromANewerVersion() async throws {
        let store = try openStore()
        let opened = try await synchronizedEntry("Older format", in: store)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(opened)) as? [String: Any])
        object["futureLayout"] = ["columns": 2]
        let newer = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        try await store.apply([remote(newer, id: opened.id, kind: "entry", revision: 2, cursor: 2)], cursor: 2)

        var unrelatedCopy = JournalItem(kind: "entry", journalID: opened.journalID, document: .plain("Replacement"))
        unrelatedCopy.id = opened.id
        do {
            try await store.save(unrelatedCopy)
            XCTFail("A record this version can only read must stay as it is")
        } catch JournalError.unsupportedFormat {}
        var stale = opened
        stale.document = .plain("Edited from the older copy")
        try await store.save(stale)
        let conflicts = try await store.conflicts()
        XCTAssertEqual(try PortableRecord.encode(XCTUnwrap(conflicts.first).remote), newer)
    }

    func testAnAuthenticatedRecordThisVersionCantReadIsKeptWithoutStoppingSync() async throws {
        let store = try openStore()
        var readable = try await synchronizedEntry("Readable before", in: store)
        readable.title = "Weekly notes"
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(readable)) as? [String: Any])
        object["document"] = "a layout this version doesn't know"
        let unreadable = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let unreadableChange = try remote(unreadable, id: readable.id, kind: "entry", revision: 2, cursor: 2)
        let arriving = JournalItem(kind: "entry", journalID: readable.journalID, document: .plain("After it"))
        var tampered = try remote(arriving, revision: 1, cursor: 4)
        tampered.payload = try remote(readable, revision: 3, cursor: 4).payload

        do {
            try await store.apply([tampered], cursor: 4)
            XCTFail("Content that doesn't authenticate must not be applied")
        } catch {}
        try await store.apply([unreadableChange, remote(arriving, revision: 1, cursor: 3)], cursor: 3)

        let cursor = try await store.cursor()
        XCTAssertEqual(cursor, 3)
        let applied = try await store.item(arriving.id)
        XCTAssertEqual(applied?.document.text, "After it")
        let current = try await store.item(readable.id)
        let kept = try XCTUnwrap(current)
        XCTAssertFalse(kept.document.isEditable)
        XCTAssertEqual(kept.title, "Weekly notes")
        XCTAssertEqual(kept.preservedJSON, unreadable)
        let database = try DatabaseQueue(path: root.appendingPathComponent("journal.sqlite").path)
        let recordID = readable.id.uuidString.lowercased()
        let stored = try await database.read {
            try String.fetchOne($0, sql: "SELECT payload FROM records WHERE id=?", arguments: [recordID])
        }
        try database.close()
        XCTAssertEqual(stored, unreadableChange.payload, "The original encrypted record is kept unchanged")
        let history = try await store.history(for: readable.id)
        XCTAssertEqual(history.first?.document.text, "Readable before")
    }

    func testADatabaseFromANewerVersionIsRefusedWithoutChanges() async throws {
        let store = try openStore()
        try await store.save(JournalItem(kind: "journal", title: "Personal"))
        try await store.close()
        let file = root.appendingPathComponent("journal.sqlite")
        let database = try DatabaseQueue(path: file.path)
        try await database.write {
            try $0.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('from-a-newer-version')")
        }
        try database.close()
        let before = SHA256.hash(data: try Data(contentsOf: file))
        do {
            _ = try openStore()
            XCTFail("A newer database must not be opened")
        } catch JournalError.newerVersion {}
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: file)), before)
    }
}
