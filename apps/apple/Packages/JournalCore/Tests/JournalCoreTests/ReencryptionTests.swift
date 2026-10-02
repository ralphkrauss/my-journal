import GRDB
import XCTest
import os

@testable import JournalCore

/// A server in memory with the protocol's revision, cursor and image rules, for devices that meet after one of them
/// turned on encryption.
private actor EncryptedServer: SyncServer {
    var records: [UUID: RemoteChange] = [:]
    var log: [RemoteChange] = []
    var images: [UUID: Data] = [:]
    var uploads: [UUID] = []
    /// Runs once, before the next record is accepted, as another device writing at that moment would.
    var beforeNextPush: (@Sendable () async -> Void)?
    func setBeforeNextPush(_ hook: @escaping @Sendable () async -> Void) { beforeNextPush = hook }
    func status() -> ServerStatus {
        ServerStatus(protocolVersion: 1, initialized: true, features: [], serverId: "encrypted-server")
    }
    func changes(after cursor: Int64, limit: Int, applied: LoggedChange?) -> SyncPage {
        let newer = log.filter { $0.cursor > cursor }
        let page = Array(newer.prefix(limit))
        return SyncPage(
            changes: page, cursor: page.last?.cursor ?? cursor, hasMore: newer.count > page.count,
            serverId: "encrypted-server", serverIdCursor: 0)
    }
    func push(_ pending: PendingChange, serverID: String?) async -> ServerClient.PushResult {
        if let hook = beforeNextPush {
            beforeNextPush = nil
            await hook()
        }
        let current = records[pending.recordID]
        let revision = current?.revision ?? 0
        if let current, revision != pending.baseRevision {
            return pending.baseRevision > revision ? .serverBehind : .conflict(current)
        }
        guard revision == pending.baseRevision else { return .serverBehind }
        let change = RemoteChange(
            cursor: Int64(log.count + 1), recordId: pending.recordID, revision: revision + 1, kind: pending.kind,
            payload: pending.payload, deviceId: UUID(), modifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        log.append(change)
        records[pending.recordID] = change
        return .accepted(change)
    }
    func upload(_ bytes: Data, id: UUID) throws {
        // Images are immutable: the same identity with other bytes is refused.
        if let existing = images[id], existing != bytes { throw SyncRejection(reason: .invalid) }
        images[id] = bytes
        uploads.append(id)
    }
    func hasAttachment(_ id: UUID) -> Bool? { images[id] != nil }
    func downloadAttachment(_ id: UUID) throws -> Data {
        guard let image = images[id] else { throw JournalError.server("Image unavailable.") }
        return image
    }
}

/// Turning on encryption for a library created without it (docs/design/enable-encryption.md).
final class ReencryptionTests: XCTestCase {
    private var directories: [URL] = []
    private let canary = "Canary sentence only this journal contains"
    private let time = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))

    override func tearDownWithError() throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
    }
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-encrypt-\(UUID())")
        directories.append(url)
        return url
    }
    private struct Library {
        let store: JournalStore
        let entry: JournalItem
        let image: UUID
        let newer: UUID
    }
    /// An unencrypted library with a journal, an entry with an earlier version, a template, an entry with an image, a
    /// review of another device's version, and a record from a newer app version.
    private func plaintextLibrary() async throws -> Library {
        let store = try JournalStore(directory: folder(), key: VaultCrypto.generateKey(), protection: .plaintext)
        let time = time
        await store.useClock { time.withLock { $0 } }
        let journal = try await store.save(JournalItem(kind: "journal", title: "Personal"))
        var entry = try await store.save(
            JournalItem(kind: "entry", journalID: journal.id, title: "Monday", document: .plain(canary + " first")))
        time.withLock { $0 += 3600 }
        entry.document = .plain(canary + " second")
        entry = try await store.save(entry)
        try await store.save(JournalItem(kind: "template", title: "Evening", document: .plain("Grateful for")))
        let image = try await store.addAttachment(Data((canary + " image").utf8))
        try await store.save(
            JournalItem(
                kind: "entry", journalID: journal.id, title: "Photo",
                document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: image, imageDescription: "")])))
        var other = entry
        other.title = "Monday on the iPad"
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: entry.id, revision: 1, kind: "entry",
                payload: try PortableRecord.encode(other).base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
        let later = JournalItem(kind: "entry", journalID: journal.id, title: "From a later version")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JournalCoding.encoder().encode(later)) as? [String: Any])
        object["futureLayout"] = ["columns": 2]
        let future = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let newer = later.id
        try await store.apply(
            [
                RemoteChange(
                    cursor: 2, recordId: newer, revision: 1, kind: "entry", payload: future.base64EncodedString(),
                    deviceId: UUID(), modifiedAt: Date())
            ], cursor: 2)
        let history = try await store.history(for: entry.id)
        XCTAssertFalse(history.isEmpty, "The fixture needs an earlier version")
        return Library(store: store, entry: entry, image: image, newer: newer)
    }
    /// Every file in `folder`, as one byte string, to search for readable content.
    private func bytes(in folder: URL) throws -> Data {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        var all = Data()
        while let file = files?.nextObject() as? URL {
            if let data = try? Data(contentsOf: file) { all.append(data) }
        }
        return all
    }
    private func containsCanary(_ data: Data) -> Bool {
        let plain = Data(canary.utf8)
        let base64 = Data(Data(canary.utf8).base64EncodedString().prefix(24).utf8)
        return data.range(of: plain) != nil || data.range(of: base64) != nil
    }

    func testEncryptedCopyKeepsEverythingUnderTheSameIdentitiesAndNothingReadable() async throws {
        let library = try await plaintextLibrary()
        let source = library.store
        let key = try VaultCrypto.generateKey()
        let destination = folder()
        let copy = try await source.reencryptedCopy(to: destination, key: key, baseline: .restart)

        let original = try await source.items()
        let encrypted = try await copy.items()
        XCTAssertEqual(Set(encrypted.map(\.id)), Set(original.map(\.id)))
        XCTAssertEqual(encrypted.count, original.count)
        for item in original {
            let same = encrypted.first { $0.id == item.id }
            XCTAssertEqual(try PortableRecord.encode(XCTUnwrap(same)), try PortableRecord.encode(item))
        }
        let history = try await copy.history(for: library.entry.id)
        let originalHistory = try await source.history(for: library.entry.id)
        XCTAssertEqual(history.map(\.document.text), originalHistory.map(\.document.text))
        let conflicts = try await copy.conflicts()
        XCTAssertEqual(conflicts.map(\.remote.title), ["Monday on the iPad"])
        let image = try await copy.attachment(library.image)
        XCTAssertEqual(image, Data((canary + " image").utf8))
        let newer = try await copy.item(library.newer)
        XCTAssertNotNil(newer?.preservedJSON, "A newer app's record is kept exactly as it was")

        // Every record is sent to the emptied server again, except the one waiting for review.
        let pending = try await copy.pending()
        XCTAssertEqual(Set(pending.map(\.recordID)), Set(original.map(\.id)).subtracting([library.entry.id]))
        XCTAssertTrue(pending.allSatisfy { $0.baseRevision == 0 })
        // Images are checked first: another device that signed in again may have sent them already.
        let uploads = try await copy.attachmentsToVerify()
        XCTAssertEqual(uploads, [library.image])
        let identity = try await copy.syncedServerID()
        XCTAssertNil(identity)

        try await copy.close()
        XCTAssertFalse(containsCanary(try bytes(in: destination)), "Nothing readable is left in the copy")
        XCTAssertThrowsError(try JournalStore(directory: destination, key: key, protection: .plaintext))
        let wrongKey = try JournalStore(directory: destination, key: VaultCrypto.generateKey())
        do {
            _ = try await wrongKey.items()
            XCTFail("The copy opens only with its key")
        } catch {}
        try await wrongKey.close()
        let sourceFolder = await source.directory
        XCTAssertTrue(containsCanary(try bytes(in: sourceFolder)), "The library itself is unchanged")
    }

    func testCancellingLeavesTheLibraryAndRemovesTheCopy() async throws {
        let library = try await plaintextLibrary()
        let destination = folder()
        let reported = OSAllocatedUnfairLock(initialState: false)
        let task = Task {
            try await library.store.reencryptedCopy(to: destination, key: VaultCrypto.generateKey(), baseline: .restart)
            {
                _ in
                reported.withLock { $0 = true }
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled while sealing records")
        } catch is CancellationError {}
        XCTAssertTrue(reported.withLock { $0 })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let items = try await library.store.items()
        XCTAssertEqual(items.count, 5)
        let protection = await library.store.protection
        XCTAssertEqual(protection, .plaintext)
    }

    /// One device turns on encryption and uploads its copy; another, with an edit made offline, signs in again.
    /// Records the server has are matched rather than duplicated, the offline edit is kept for review, and images
    /// the first device uploaded aren't sent again.
    /// A second device with the same records and image as synchronized from the old server.
    private func secondDevice(of first: Library) async throws -> JournalStore {
        let secondFolder = folder()
        try await first.store.snapshot(to: secondFolder)
        let second = try JournalStore(directory: secondFolder, key: VaultCrypto.generateKey(), protection: .plaintext)
        let onServer = try await second.pending()
        for pending in onServer {
            try await second.acknowledge(
                pending,
                receipt: RemoteChange(
                    cursor: 1, recordId: pending.recordID, revision: 1, kind: pending.kind, payload: pending.payload,
                    deviceId: UUID(), modifiedAt: Date()))
        }
        try await second.acknowledgeAttachment(first.image)
        return second
    }

    func testAnotherDeviceRejoiningMatchesByContentAndKeepsOfflineEditsForReview() async throws {
        let first = try await plaintextLibrary()
        // The second device has the same records as synchronized from the old server, then an offline edit.
        let second = try await secondDevice(of: first)
        let secondItems = try await second.items()
        var template = try XCTUnwrap(secondItems.first { $0.kind == "template" })
        template.title = "Evening, edited offline"
        try await second.save(template)

        let key = try VaultCrypto.generateKey()
        let server = EncryptedServer()
        let encrypted = try await first.store.reencryptedCopy(to: folder(), key: key, baseline: .restart)
        try await SyncEngine(store: encrypted, server: server).synchronize()
        let uploadedFirst = await server.uploads
        XCTAssertEqual(uploadedFirst, [first.image])

        let rejoined = try await second.reencryptedCopy(to: folder(), key: key, baseline: .reconcile)
        try await SyncEngine(store: rejoined, server: server).synchronize()

        let items = try await rejoined.items()
        XCTAssertEqual(items.count, secondItems.count, "Nothing was duplicated")
        XCTAssertEqual(Set(items.map(\.id)), Set(secondItems.map(\.id)))
        let conflicts = try await rejoined.conflicts()
        XCTAssertTrue(conflicts.contains { $0.id == template.id }, "The offline edit is kept for review")
        let localTemplate = try await rejoined.item(template.id)
        XCTAssertEqual(localTemplate?.title, "Evening, edited offline")
        let uploads = await server.uploads
        XCTAssertEqual(uploads, [first.image], "The image the server has isn't sent again")
        let pendingAfter = try await rejoined.pending()
        XCTAssertTrue(pendingAfter.isEmpty)
        let image = try await rejoined.attachment(first.image)
        XCTAssertEqual(image, Data((canary + " image").utf8))
    }

    /// Another device signs in again and uploads its copy before the device that turned on encryption uploads its
    /// own. That device matches what the server has instead of showing identical journals for review, its image isn't
    /// sent again and refused, and its later edits reach the other device.
    func testTheSwitchingDeviceMatchesJournalsAnotherDeviceSentFirst() async throws {
        let first = try await plaintextLibrary()
        let second = try await secondDevice(of: first)
        let key = try VaultCrypto.generateKey()
        let server = EncryptedServer()
        let switched = try await first.store.reencryptedCopy(to: folder(), key: key, baseline: .restart)
        let rejoined = try await second.reencryptedCopy(to: folder(), key: key, baseline: .reconcile)
        let otherSync = SyncEngine(store: rejoined, server: server)
        try await otherSync.synchronize()
        let reviewed = try await switched.conflicts().map(\.id)

        let sync = SyncEngine(store: switched, server: server)
        try await expectMatched(switched, sync: sync, reviewed: reviewed)
        let uploads = await server.uploads
        XCTAssertEqual(uploads, [first.image], "The image the other device sent isn't sent again")
        try await expectEditReaches(rejoined, from: switched, sync: sync, otherSync: otherSync)
    }

    /// Another device sends the same journals while the device that turned on encryption is uploading its copy: each
    /// record the server already has from it is matched rather than shown for review.
    func testJournalsAnotherDeviceSendsDuringTheUploadAreMatched() async throws {
        let first = try await plaintextLibrary()
        let second = try await secondDevice(of: first)
        let key = try VaultCrypto.generateKey()
        let server = EncryptedServer()
        let switched = try await first.store.reencryptedCopy(to: folder(), key: key, baseline: .restart)
        let rejoined = try await second.reencryptedCopy(to: folder(), key: key, baseline: .reconcile)
        let otherSync = SyncEngine(store: rejoined, server: server)
        await server.setBeforeNextPush { _ = try? await otherSync.synchronize() }
        let reviewed = try await switched.conflicts().map(\.id)

        let sync = SyncEngine(store: switched, server: server)
        try await expectMatched(switched, sync: sync, reviewed: reviewed)
        let otherPending = try await rejoined.pending()
        XCTAssertTrue(otherPending.isEmpty, "The other device sent its copy during the upload")
        try await expectEditReaches(rejoined, from: switched, sync: sync, otherSync: otherSync)
    }

    private func expectMatched(_ store: JournalStore, sync: SyncEngine, reviewed: [UUID]) async throws {
        let report = try await sync.synchronize()
        XCTAssertNil(report.problem)
        let reviews = try await store.conflicts().map(\.id)
        XCTAssertEqual(reviews, reviewed, "Journals with the same content aren't shown for review")
        let pending = try await store.pending()
        XCTAssertTrue(pending.isEmpty)
        let unverified = try await store.attachmentsToVerify()
        XCTAssertTrue(unverified.isEmpty)
    }
    private func expectEditReaches(
        _ other: JournalStore, from store: JournalStore, sync: SyncEngine, otherSync: SyncEngine
    ) async throws {
        let items = try await store.items()
        var photo = try XCTUnwrap(items.first { $0.title == "Photo" })
        photo.title = "Photo, edited after encryption"
        try await store.save(photo)
        let report = try await sync.synchronize()
        XCTAssertNil(report.problem)
        try await otherSync.synchronize()
        let received = try await other.item(photo.id)
        XCTAssertEqual(received?.title, "Photo, edited after encryption")
    }
}
