import XCTest

@testable import JournalCore

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
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        let recoveredEntry = try await restored.store.item(entry.id)
        let recoveredImage = try await restored.store.attachment(imageID)
        let recoveredPending = try await restored.store.pending()[0]
        XCTAssertEqual(recoveredEntry?.title, entry.title)
        XCTAssertEqual(recoveredEntry?.archivedAt, entry.archivedAt)
        XCTAssertEqual(recoveredImage, image)
        XCTAssertEqual(recoveredPending.operationId, pending.operationId)
        let header = try Data(contentsOf: archive.appendingPathComponent("archive.json"))
        XCTAssertNil(header.range(of: Data(entry.title.utf8)))
        XCTAssertNil(header.range(of: Data(phrase.utf8)))
        do {
            _ = try await VaultArchive.restore(
                from: archive, to: root.appendingPathComponent("wrong-key"), phrase: "wrong key")
            XCTFail("A wrong recovery key must not open the archive")
        } catch {}
        let imagePath = archive.appendingPathComponent("attachments/\(imageID.uuidString.lowercased())")
        var damaged = try Data(contentsOf: imagePath)
        damaged[0] ^= 1
        try damaged.write(to: imagePath)
        let rejectedDestination = root.appendingPathComponent("tampered")
        do {
            _ = try await VaultArchive.restore(from: archive, to: rejectedDestination, phrase: phrase)
            XCTFail("A damaged image must fail archive verification")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedDestination.path))
    }

    func testPasswordlessManifestCannotNameAFileOutsideTheRestore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key, protection: .plaintext)
        try await store.save(JournalItem(kind: "entry", title: "Passwordless entry"))
        let archive = root.appendingPathComponent("a/b/c/copy.journalarchive")
        try FileManager.default.createDirectory(
            at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await VaultArchive.export(store: store, recovery: .unprotected, key: key, to: archive)
        // The manifest of a passwordless archive is readable and unauthenticated, so anyone can list another name.
        // From the archive's attachments folder and the restore's, this name points at two places outside both.
        let name = "../../../planted"
        try Data("planted".utf8).write(to: root.appendingPathComponent("a/b/planted"))
        let headerURL = archive.appendingPathComponent("archive.json")
        var header = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: headerURL)) as? [String: Any])
        let manifestData = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(header["manifest"] as? String)))
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        var attachments = try XCTUnwrap(manifest["attachments"] as? [String: String])
        attachments[name] = String(repeating: "0", count: 64)
        manifest["attachments"] = attachments
        header["manifest"] = try JSONSerialization.data(withJSONObject: manifest).base64EncodedString()
        try JSONSerialization.data(withJSONObject: header).write(to: headerURL)

        let destination = root.appendingPathComponent("x/restored")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            _ = try await VaultArchive.restore(from: archive, to: destination, phrase: "")
            XCTFail("A listed name that isn't an image identifier must be refused")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("planted").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
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
        try await VaultArchive.export(store: store, recovery: recovery, key: archiveKey, to: archive)
        let destination = root.appendingPathComponent("inspection")
        do {
            _ = try await VaultArchive.restore(from: archive, to: destination, phrase: phrase)
            XCTFail("Records encrypted under a different key must fail validation")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.appendingPathComponent("archive.json").path))
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
    }

    func testFailedSnapshotAndArchiveExportRemoveOnlyTheirOwnDestination() async throws {
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
        // An unreferenced retained image is still part of a lossless snapshot.
        try manager.removeItem(at: imagePath)
        let failedCopy = root.appendingPathComponent("failed-copy")
        do {
            try await VaultArchive.export(store: store, recovery: recovery, key: key, to: failedCopy)
            XCTFail("A missing retained image must fail the snapshot copy")
        } catch {}
        XCTAssertFalse(manager.fileExists(atPath: failedCopy.path))
        try encrypted.write(to: imagePath)
        let failedHeader = root.appendingPathComponent("failed-header")
        do {
            try await VaultArchive.export(store: store, recovery: recovery, key: Data(), to: failedHeader)
            XCTFail("Invalid manifest encryption must not leave a partial archive")
        } catch {}
        XCTAssertFalse(manager.fileExists(atPath: failedHeader.path))
        let existing = root.appendingPathComponent("existing")
        try manager.createDirectory(at: existing, withIntermediateDirectories: false)
        let marker = existing.appendingPathComponent("keep")
        try encrypted.write(to: marker)
        do {
            try await VaultArchive.export(store: store, recovery: recovery, key: key, to: existing)
            XCTFail("An existing destination must be refused")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: marker), encrypted)
        let successful = root.appendingPathComponent("complete.journalarchive")
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: successful)
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
            try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
            XCTFail("Export must fail when a referenced image has no bytes")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.appendingPathComponent("archive.json").path))
    }
}
