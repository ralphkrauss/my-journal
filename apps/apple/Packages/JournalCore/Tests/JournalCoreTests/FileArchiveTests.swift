import XCTest
import os

@testable import JournalCore

/// The file archive written by `exportFile` and read back: what is kept, what is refused, and what is left behind.
final class FileArchiveTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Library {
        let store: JournalStore
        let key: Data
        let phrase: String
        let recovery: RecoveryEnvelope
        let images: [UUID: Data]
        let entry: JournalItem
    }

    /// A library with two images, an entry that uses one of them, an unsent edit and an earlier version.
    private func makeLibrary(named name: String = "source") async throws -> Library {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase, formatVersion: 2).0
        let store = try JournalStore(directory: root.appendingPathComponent(name), key: key)
        let first = Data((0..<5000).map { UInt8($0 % 251) })
        let second = Data("a second image".utf8)
        let firstID = try await store.addAttachment(first)
        let secondID = try await store.addAttachment(second)
        var entry = JournalItem(
            kind: "entry", title: "Kept in a file archive",
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: firstID, imageDescription: "A picture")]
            ))
        entry = try await store.save(entry)
        try await store.keepInHistory(entry)
        entry.title = "Edited after the earlier version"
        entry = try await store.save(entry)
        return Library(
            store: store, key: key, phrase: phrase, recovery: recovery, images: [firstID: first, secondID: second],
            entry: entry)
    }

    func testARestoredFileArchiveHoldsTheImagesTheUnsentEditAndTheEarlierVersion() async throws {
        let library = try await makeLibrary()
        let archive = root.appendingPathComponent("library.journalarchive")
        try await VaultArchive.exportFile(
            store: library.store, recovery: library.recovery, key: library.key, to: archive)
        XCTAssertNoThrow(try VaultArchive.checkHeader(at: archive))

        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: library.phrase)
        let entry = try await restored.store.item(library.entry.id)
        XCTAssertEqual(entry?.title, library.entry.title)
        let pending = try await restored.store.pending()
        let sourcePending = try await library.store.pending()
        XCTAssertEqual(pending.map(\.operationId), sourcePending.map(\.operationId))
        let history = try await restored.store.history(for: library.entry.id)
        XCTAssertEqual(history.map(\.title), ["Kept in a file archive"])
        for (identifier, bytes) in library.images {
            let restoredImage = try await restored.store.attachment(identifier)
            XCTAssertEqual(restoredImage, bytes)
        }
        try await restored.store.close()
        try await library.store.close()
    }

    /// The other version of an entry changed on two devices waits in `conflicts`; the archive keeps it with the entry.
    func testAConflictWaitingForSettlementIsKept() async throws {
        let library = try await makeLibrary()
        var theirs = library.entry
        theirs.title = "Written on another device"
        let payload = try VaultCrypto.seal(
            PortableRecord.encode(theirs), key: library.key,
            context: VaultCrypto.recordContext(id: theirs.id, kind: theirs.kind))
        let change = RemoteChange(
            cursor: 1, recordId: theirs.id, revision: 7, kind: theirs.kind, payload: payload.base64EncodedString(),
            deviceId: UUID(), modifiedAt: theirs.modifiedAt)
        try await library.store.apply([change], cursor: 1)
        let before = try await library.store.conflicts()
        XCTAssertEqual(before.count, 1)

        let archive = root.appendingPathComponent("conflict.journalarchive")
        try await VaultArchive.exportFile(
            store: library.store, recovery: library.recovery, key: library.key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: library.phrase)
        let conflicts = try await restored.store.conflicts()
        XCTAssertEqual(conflicts.map(\.remote.title), ["Written on another device"])
        XCTAssertEqual(conflicts.map(\.remoteRevision), [7])
        try await restored.store.close()
        try await library.store.close()
    }

    /// The writer's container choices that other tools rely on: stored entries, fixed time, order, and no leftovers.
    func testTheArchiveIsOneFileOfStoredEntriesInTheDocumentedOrder() async throws {
        let library = try await makeLibrary()
        let archive = root.appendingPathComponent("library.journalarchive")
        try await VaultArchive.exportFile(
            store: library.store, recovery: library.recovery, key: library.key, to: archive)
        let input = try ArchiveInput(path: archive.path)
        let directory = try ZipDirectory.read(from: input)
        XCTAssertEqual(directory.attachments.count, 2)
        let entries = directory.all.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        XCTAssertEqual(entries.first?.role, .database)
        XCTAssertEqual(entries.last?.role, .header)
        XCTAssertTrue(entries.allSatisfy { $0.method == ZipEntry.stored && $0.flags == 0 })
        let names = entries.dropFirst().dropLast().map(\.role.name)
        XCTAssertEqual(names, names.sorted())
        let temporary = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
        XCTAssertFalse(temporary.contains { $0.hasPrefix("export-") && $0.hasSuffix(".sqlite") })
        try await library.store.close()
    }

    func testOneByteChunksAndForcedZip64RoundTrip() async throws {
        let library = try await makeLibrary()
        var options = ArchiveOptions.standard
        options.chunkBytes = 7
        options.forceZip64 = true
        let archive = root.appendingPathComponent("zip64.journalarchive")
        try await FileArchive.export(
            store: library.store, recovery: library.recovery, key: library.key, to: archive, options: options)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: library.phrase, options: options)
        let pending = try await restored.store.pending()
        XCTAssertEqual(pending.count, 1)
        try await restored.store.close()
        try await library.store.close()
    }

    func testAFailedExportRemovesItsOwnFilesAndNeverAnExistingDestination() async throws {
        let library = try await makeLibrary()
        let manager = FileManager.default
        let firstImage = try XCTUnwrap(library.images.keys.first).uuidString.lowercased()
        let image = root.appendingPathComponent("source/attachments/\(firstImage)")
        let kept = try Data(contentsOf: image)
        try manager.removeItem(at: image)
        let failed = root.appendingPathComponent("failed.journalarchive")
        do {
            try await VaultArchive.exportFile(
                store: library.store, recovery: library.recovery, key: library.key, to: failed)
            XCTFail("A missing image must fail the export")
        } catch {}
        XCTAssertFalse(manager.fileExists(atPath: failed.path))
        try kept.write(to: image)

        let existing = root.appendingPathComponent("existing.journalarchive")
        try Data("not ours".utf8).write(to: existing)
        do {
            try await VaultArchive.exportFile(
                store: library.store, recovery: library.recovery, key: library.key, to: existing)
            XCTFail("An existing destination must be refused")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: existing), Data("not ours".utf8))
        let temporary = try manager.contentsOfDirectory(atPath: manager.temporaryDirectory.path)
        XCTAssertFalse(temporary.contains { $0.hasPrefix("export-") && $0.hasSuffix(".sqlite") })
        try await library.store.close()
    }

    func testACancelledExportLeavesNothing() async throws {
        let library = try await makeLibrary()
        let archive = root.appendingPathComponent("cancelled.journalarchive")
        let task = Task {
            try await VaultArchive.exportFile(
                store: library.store, recovery: library.recovery, key: library.key, to: archive)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("A cancelled export must not complete")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        try await library.store.close()
    }

    /// Export needs the database, the images and 256 MiB beyond them; restore needs twice the declared bytes plus the
    /// same reserve. Both are refused before anything is written.
    func testTooLittleFreeSpaceRefusesExportAndRestoreBeforeWriting() async throws {
        let library = try await makeLibrary()
        let archive = root.appendingPathComponent("space.journalarchive")
        let estimate = try await library.store.archiveBytesEstimate()
        let short = ArchiveOptions(availableSpace: { _ in estimate + ArchiveLimits.spaceReserve - 1 })
        do {
            try await FileArchive.export(
                store: library.store, recovery: library.recovery, key: library.key, to: archive, options: short)
            XCTFail("An export without room must be refused")
        } catch ArchiveError.notEnoughSpace {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        let enough = ArchiveOptions(availableSpace: { _ in estimate + ArchiveLimits.spaceReserve })
        try await FileArchive.export(
            store: library.store, recovery: library.recovery, key: library.key, to: archive, options: enough)

        let destination = root.appendingPathComponent("restored")
        let declared = try await restoreDeclaredBytes(of: archive, phrase: library.phrase)
        let tight = ArchiveOptions(availableSpace: { _ in declared * 2 + ArchiveLimits.spaceReserve - 1 })
        do {
            _ = try await VaultArchive.restore(from: archive, to: destination, phrase: library.phrase, options: tight)
            XCTFail("A restore without room must be refused")
        } catch ArchiveError.notEnoughSpace {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        try await library.store.close()
    }

    /// The directory archive of 1.0 needs the same room: twice the listed files plus the reserve.
    func testADirectoryArchiveNeedsRoomToo() async throws {
        let source = Conformance.url("archive/v1/encrypted")
        let password = try XCTUnwrap(
            (try Conformance.object("crypto/encryption-v2.json")["recovery"] as? [String: Any])?["password"] as? String)
        var listed = UInt64(
            try FileManager.default.attributesOfItem(
                atPath: source.appendingPathComponent("journal.sqlite").path)[.size] as? UInt64 ?? 0)
        let images = try FileManager.default.contentsOfDirectory(
            atPath: source.appendingPathComponent("attachments").path)
        for name in images {
            let size =
                try FileManager.default.attributesOfItem(
                    atPath: source.appendingPathComponent("attachments/\(name)").path)[.size] as? UInt64
            listed += size ?? 0
        }
        let needed = listed * 2 + ArchiveLimits.spaceReserve
        let destination = root.appendingPathComponent("directory-restore")
        do {
            _ = try await VaultArchive.restore(
                from: source, to: destination, phrase: password,
                options: ArchiveOptions(availableSpace: { _ in needed - 1 }))
            XCTFail("A restore without room must be refused")
        } catch ArchiveError.notEnoughSpace {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let restored = try await VaultArchive.restore(
            from: source, to: destination, phrase: password,
            options: ArchiveOptions(availableSpace: { _ in needed }))
        try await restored.store.close()
    }

    private func restoreDeclaredBytes(of archive: URL, phrase: String) async throws -> UInt64 {
        let container = try ArchiveContainer(at: archive)
        let header = try FileArchiveHeader.parse(try container.headerData())
        let key = try VaultCrypto.recover(header.recovery, phrase: phrase).0
        let bytes = try VaultCrypto.open(header.sealedManifest, key: key, context: FileArchiveHeader.manifestContext)
        return try ArchiveManifest.parse(bytes).declaredBytes
    }

    func testAnArchiveForAnEnvelopeOfALibraryWithoutEncryptionIsNotWritten() async throws {
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root.appendingPathComponent("library"), key: key)
        let archive = root.appendingPathComponent("plain.journalarchive")
        var envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: "a password", formatVersion: 2).0
        envelope.formatVersion = 4
        do {
            try await VaultArchive.exportFile(store: store, recovery: envelope, key: key, to: archive)
            XCTFail("1.1 writes only encrypted archives")
        } catch JournalError.notEncrypted {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        try await store.close()
    }
    // MARK: Reading through restore

    /// A library with enough records that its database compresses less than the expansion limit allows.
    private func makeDenseLibrary() async throws -> Library {
        let library = try await makeLibrary()
        var generator = SystemRandomNumberGenerator()
        for number in 0..<120 {
            let text = (0..<80).map { _ in String(UInt64.random(in: 0...UInt64.max, using: &generator), radix: 36) }
            let entry = JournalItem(
                kind: "entry", title: "Entry \(number)",
                document: .init(blocks: [DocumentBlock(runs: [TextRun(text.joined())])]))
            _ = try await library.store.save(entry)
        }
        return library
    }

    /// Deflated entries restore through the whole reader (container, hashes, database inspection, store), in tiny
    /// chunks that split the compressed stream and its output at every kind of boundary.
    func testDeflatedEntriesRestoreInSmallChunks() async throws {
        let library = try await makeDenseLibrary()
        let stored = root.appendingPathComponent("stored.journalarchive")
        try await VaultArchive.exportFile(
            store: library.store, recovery: library.recovery, key: library.key, to: stored)
        let deflated = root.appendingPathComponent("deflated.journalarchive")
        let count = try ArchiveRepack.deflate(stored, to: deflated)
        XCTAssertGreaterThanOrEqual(count, 2, "the database and the header at least are deflated")
        XCTAssertLessThan(
            try deflated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
            try stored.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        for chunk in [1, 13, 4096] {
            var options = ArchiveOptions.standard
            options.chunkBytes = chunk
            let destination = root.appendingPathComponent("restored-\(chunk)")
            let restored = try await VaultArchive.restore(
                from: deflated, to: destination, phrase: library.phrase, options: options)
            let entry = try await restored.store.item(library.entry.id)
            XCTAssertEqual(entry?.title, library.entry.title, "chunk \(chunk)")
            let count = try await restored.store.items().count
            XCTAssertEqual(count, 121, "chunk \(chunk)")
            for (identifier, bytes) in library.images {
                let image = try await restored.store.attachment(identifier)
                XCTAssertEqual(image, bytes, "chunk \(chunk)")
            }
            try await restored.store.close()
        }
        try await library.store.close()
    }

    /// Cancelling a restore while it extracts stops at the next chunk and removes the staging folder it made, and
    /// reports the cancellation rather than damage.
    func testCancellingARestoreMidExtractionRemovesTheStagingFolder() async throws {
        let library = try await makeLibrary()
        let archive = root.appendingPathComponent("library.journalarchive")
        try await VaultArchive.exportFile(
            store: library.store, recovery: library.recovery, key: library.key, to: archive)
        let before = try Data(contentsOf: archive)
        let destination = root.appendingPathComponent("restored")
        var options = ArchiveOptions.standard
        options.chunkBytes = 512
        let chunkLimit: UInt64 = 20_000
        let reached = OSAllocatedUnfairLock(initialState: UInt64(0))
        options.didExtract = { total in
            reached.withLock { $0 = total }
            if total >= chunkLimit { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let phrase = library.phrase
        let task = Task {
            try await VaultArchive.restore(from: archive, to: destination, phrase: phrase, options: options)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled restore must not complete")
        } catch is CancellationError {}
        let extracted = reached.withLock { $0 }
        XCTAssertGreaterThanOrEqual(extracted, chunkLimit)
        XCTAssertLessThan(extracted, chunkLimit + 512, "no chunk is read after the cancellation")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: archive), before)
        try await library.store.close()
    }
}
