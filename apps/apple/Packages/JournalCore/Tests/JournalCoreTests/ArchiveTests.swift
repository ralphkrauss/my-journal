import XCTest

@testable import JournalCore

/// Export and restore of a file archive through the public API. The reader's handling of hostile and damaged input is
/// in the conformance and hardening tests; these protect what a person relies on.
final class ArchiveTests: XCTestCase {
    func testEncryptedArchiveRestoresImagesAndPendingEditsAndRejectsTampering() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let image = Data("original archive image".utf8)
        let imageID = try await store.addAttachment(image)
        var entry = JournalItem(
            kind: "entry", title: "private-archive-sentinel",
            document: .init(blocks: [
                DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "A useful image")
            ]))
        entry.archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.save(entry)
        let pending = try await store.pending()[0]
        let archive = root.appendingPathComponent("copy.journalarchive")
        try await VaultArchive.exportFile(store: store, recovery: recovery, key: key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        let recoveredEntry = try await restored.store.item(entry.id)
        let recoveredImage = try await restored.store.attachment(imageID)
        let recoveredPending = try await restored.store.pending()[0]
        XCTAssertEqual(recoveredEntry?.title, entry.title)
        XCTAssertEqual(recoveredEntry?.archivedAt, entry.archivedAt)
        XCTAssertEqual(recoveredImage, image)
        XCTAssertEqual(recoveredPending.operationId, pending.operationId)
        try await restored.store.close()

        // Everything a reader can see without the password is ciphertext, and the password is nowhere in the file.
        var bytes = try Data(contentsOf: archive)
        XCTAssertNil(bytes.range(of: Data(entry.title.utf8)))
        XCTAssertNil(bytes.range(of: Data(phrase.utf8)))
        do {
            _ = try await VaultArchive.restore(
                from: archive, to: root.appendingPathComponent("wrong-key"), phrase: "wrong key")
            XCTFail("A wrong recovery key must not open the archive")
        } catch JournalError.invalidRecoveryKey {}

        // One changed byte of an image, found in the file where the library keeps the same bytes.
        let stored = try Data(
            contentsOf: root.appendingPathComponent("source/attachments/\(imageID.uuidString.lowercased())"))
        let position = try XCTUnwrap(bytes.range(of: stored)).lowerBound
        bytes[position] ^= 1
        try bytes.write(to: archive)
        let rejectedDestination = root.appendingPathComponent("tampered")
        do {
            _ = try await VaultArchive.restore(from: archive, to: rejectedDestination, phrase: phrase)
            XCTFail("A damaged image must fail archive verification")
        } catch JournalError.invalidData {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedDestination.path))
        try await store.close()
    }

    func testFailedPayloadValidationRemovesStagingAndPreservesExistingDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: VaultCrypto.generateKey())
        try await store.save(JournalItem(kind: "entry", title: "Original entry"))
        let archiveKey = try VaultCrypto.generateKey()
        let phrase = "archive validation fixture"
        let recovery = try VaultCrypto.makeRecovery(masterKey: archiveKey, phrase: phrase).0
        let archive = root.appendingPathComponent("invalid-payload.journalarchive")
        // An authenticated inventory is insufficient: record ciphertext must also validate.
        try await VaultArchive.exportFile(store: store, recovery: recovery, key: archiveKey, to: archive)
        let before = try Data(contentsOf: archive)
        let destination = root.appendingPathComponent("inspection")
        do {
            _ = try await VaultArchive.restore(from: archive, to: destination, phrase: phrase)
            XCTFail("Records encrypted under a different key must fail validation")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: archive), before, "The archive is only read")
        let sourceItems = try await store.items()
        XCTAssertEqual(sourceItems.first?.title, "Original entry")

        let existing = root.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let marker = existing.appendingPathComponent("keep")
        let original = Data("existing destination".utf8)
        try original.write(to: marker)
        do {
            _ = try await VaultArchive.restore(from: archive, to: existing, phrase: phrase)
            XCTFail("Restore must refuse an existing destination")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: marker), original)
        try await store.close()
    }

    func testFailedExportsRemoveOnlyTheirOwnFile() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let source = root.appendingPathComponent("source")
        let store = try JournalStore(directory: source, key: key)
        let imageID = try await store.addAttachment(Data("Retained image".utf8))
        let imagePath = source.appendingPathComponent("attachments/\(imageID.uuidString.lowercased())")
        let encrypted = try Data(contentsOf: imagePath)
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: "export failure fixture").0
        // An unreferenced retained image is still part of a lossless archive.
        try manager.removeItem(at: imagePath)
        let failedCopy = root.appendingPathComponent("failed-copy.journalarchive")
        do {
            try await VaultArchive.exportFile(store: store, recovery: recovery, key: key, to: failedCopy)
            XCTFail("A missing retained image must fail the export")
        } catch {}
        XCTAssertFalse(manager.fileExists(atPath: failedCopy.path))
        try encrypted.write(to: imagePath)
        let failedHeader = root.appendingPathComponent("failed-header.journalarchive")
        do {
            try await VaultArchive.exportFile(store: store, recovery: recovery, key: Data(), to: failedHeader)
            XCTFail("Invalid manifest encryption must not leave a partial archive")
        } catch {}
        XCTAssertFalse(manager.fileExists(atPath: failedHeader.path))
        let successful = root.appendingPathComponent("complete.journalarchive")
        try await VaultArchive.exportFile(store: store, recovery: recovery, key: key, to: successful)
        let restored = try await VaultArchive.restore(
            from: successful, to: root.appendingPathComponent("restored"), phrase: "export failure fixture")
        let restoredImage = try await restored.store.attachment(imageID)
        XCTAssertEqual(restoredImage, Data("Retained image".utf8))
        try await restored.store.close()
        try await store.close()
    }

    func testArchiveDoesNotClaimCompletenessWhenAnImageIsMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: "fixture recovery key").0
        try await store.save(
            JournalItem(kind: "entry", document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: UUID())])))
        let archive = root.appendingPathComponent("missing-image.journalarchive")
        do {
            try await VaultArchive.exportFile(store: store, recovery: recovery, key: key, to: archive)
            XCTFail("Export must fail when a referenced image has no bytes")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        try await store.close()
    }

    /// A folder made by 1.0 is read by the same call, whatever its name, and keeps the library whole.
    func testADirectoryArchiveFromVersionOneRestoresThroughTheSameCall() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let imageID = try await store.addAttachment(Data("a 1.0 image".utf8))
        let entry = JournalItem(
            kind: "entry", title: "Written by 1.0",
            document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: imageID, imageDescription: "")]))
        try await store.save(entry)
        let folder = root.appendingPathComponent("Journal Archive.journalarchive")
        try await DirectoryArchiveFixture.write(store: store, recovery: recovery, key: key, to: folder)
        XCTAssertNoThrow(try VaultArchive.checkHeader(at: folder))
        let restored = try await VaultArchive.restore(
            from: folder, to: root.appendingPathComponent("restored"), phrase: phrase)
        let restoredEntry = try await restored.store.item(entry.id)
        let restoredImage = try await restored.store.attachment(imageID)
        XCTAssertEqual(restoredEntry?.title, entry.title)
        XCTAssertEqual(restoredImage, Data("a 1.0 image".utf8))
        try await restored.store.close()
        try await store.close()
    }
}
