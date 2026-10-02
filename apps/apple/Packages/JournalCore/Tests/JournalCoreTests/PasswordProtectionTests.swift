import XCTest

@testable import JournalCore

final class PasswordProtectionTests: XCTestCase {
    func testExactPasswordAndLegacyRecoveryRemainDistinct() throws {
        let key = try VaultCrypto.generateKey()
        let password = "  a generated password 🔑  "
        let current = try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2)
        XCTAssertEqual(try VaultCrypto.recover(current.0, phrase: password).0, key)
        XCTAssertThrowsError(try VaultCrypto.recover(current.0, phrase: password.trimmingCharacters(in: .whitespaces)))
        let legacy = try VaultCrypto.makeRecovery(masterKey: key, phrase: password)
        XCTAssertEqual(try VaultCrypto.recover(legacy.0, phrase: password.trimmingCharacters(in: .whitespaces)).0, key)
        var downgraded = current.0
        downgraded.formatVersion = 3
        XCTAssertThrowsError(try VaultCrypto.recover(downgraded, phrase: password))
        var unsupported = current.0
        unsupported.formatVersion = 4
        XCTAssertThrowsError(try VaultCrypto.recover(unsupported, phrase: password))
        XCTAssertThrowsError(try unsupported.contentProtection)
    }

    func testPlaintextContentSyncSnapshotAndArchiveKeepProtectionChoice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let password = "fixture access password"
        let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 3).0
        let source = try JournalStore(
            directory: root.appendingPathComponent("source"), key: key, protection: .plaintext)
        let target = try JournalStore(
            directory: root.appendingPathComponent("target"), key: key, protection: .plaintext)
        let entry = JournalItem(kind: "entry", title: "Readable journal content")
        let image = Data("readable original image bytes".utf8)
        let imageID = try await source.addAttachment(image)
        try await source.save(entry)
        let pending = try await source.pending()[0]
        XCTAssertEqual(try PortableRecord.decode(Data(base64Encoded: pending.payload) ?? Data()).title, entry.title)
        let imageBytes = try await source.encryptedAttachment(imageID)
        XCTAssertEqual(imageBytes, image)
        try await target.apply(
            [
                .init(
                    cursor: 1, recordId: entry.id, revision: 1, kind: entry.kind, payload: pending.payload,
                    deviceId: UUID(), modifiedAt: Date())
            ], cursor: 1)
        let synced = try await target.item(entry.id)
        XCTAssertEqual(synced?.title, entry.title)
        let archive = root.appendingPathComponent("backup.journalarchive")
        try await VaultArchive.export(store: source, recovery: envelope, key: key, to: archive)
        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: password)
        let protection = await restored.store.protection
        XCTAssertEqual(protection, .plaintext)
        let restoredImage = try await restored.store.attachment(imageID)
        XCTAssertEqual(restoredImage, image)
        let restoredEntry = try await restored.store.item(entry.id)
        XCTAssertEqual(restoredEntry?.title, entry.title)
        try await restored.store.close()
        XCTAssertThrowsError(try JournalStore(directory: root.appendingPathComponent("restored"), key: key))
        let reopened = try JournalStore(
            directory: root.appendingPathComponent("restored"), key: key, protection: .plaintext)
        let reopenedEntry = try await reopened.item(entry.id)
        XCTAssertEqual(reopenedEntry?.title, entry.title)
        do {
            _ = try await VaultArchive.restore(
                from: archive, to: root.appendingPathComponent("wrong"), phrase: "incorrect password")
            XCTFail("An access password is still required to restore through the app")
        } catch JournalError.invalidRecoveryKey {}
    }
}
