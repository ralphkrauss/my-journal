import GRDB
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
    }

    func testFormatsOfLibrariesWithoutEncryptionAreRefusedNotOpened() throws {
        let key = try VaultCrypto.generateKey()
        let password = "a password"
        let current = try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2).0
        for version in [3, 4] {
            var unencrypted = current
            unencrypted.formatVersion = version
            XCTAssertThrowsError(try unencrypted.requireEncrypted(), "format \(version)") {
                XCTAssertEqual($0 as? JournalError, .notEncrypted)
            }
            XCTAssertThrowsError(try VaultCrypto.recover(unencrypted, phrase: password)) {
                XCTAssertEqual($0 as? JournalError, .notEncrypted)
            }
            XCTAssertThrowsError(try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: version))
            { XCTAssertEqual($0 as? JournalError, .notEncrypted) }
        }
        var newer = current
        newer.formatVersion = 5
        XCTAssertThrowsError(try newer.requireEncrypted()) {
            XCTAssertEqual($0 as? JournalError, .unsupportedFormat)
        }
    }

    func testDirectoryArchiveOfALibraryWithoutEncryptionIsRefusedBeforeAnyPassword() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for version in [3, 4] {
            let archive = root.appendingPathComponent("archive-\(version)")
            try DirectoryArchiveFixture.writeUnencryptedHeader(formatVersion: version, to: archive)
            XCTAssertThrowsError(try VaultArchive.checkHeader(at: archive)) {
                XCTAssertEqual($0 as? JournalError, .notEncrypted, "format \(version)")
            }
            do {
                _ = try await VaultArchive.restore(
                    from: archive, to: root.appendingPathComponent("restored-\(version)"), phrase: "any")
                XCTFail("An archive of journals that aren't encrypted was restored.")
            } catch JournalError.notEncrypted {}
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.appendingPathComponent("restored-\(version)").path))
        }
    }

    func testALibraryMarkedAsNotEncryptedIsNeverOpened() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let folder = root.appendingPathComponent("library")
        let store = try JournalStore(directory: folder, key: key)
        try await store.save(JournalItem(kind: "entry", title: "Written by 1.0 without encryption"))
        try await store.close()
        let queue = try DatabaseQueue(path: folder.appendingPathComponent("journal.sqlite").path)
        try await queue.write {
            try $0.execute(sql: "UPDATE settings SET value = 'plaintext' WHERE key = 'content-protection'")
        }
        try queue.close()
        XCTAssertThrowsError(try JournalStore(directory: folder, key: key)) {
            XCTAssertEqual($0 as? JournalError, .notEncrypted)
        }
    }
}
