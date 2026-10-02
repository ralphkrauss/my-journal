import CryptoKit
import GRDB
import XCTest

@testable import JournalCore

/// An archive package is a single self-contained database plus images. Copies between volumes can add system files;
/// a crafted database must not bring objects that act on later writes.
final class ArchivePackageTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
    private func export(_ title: String) async throws -> (archive: URL, phrase: String, key: Data) {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let image = try await store.addAttachment(Data("archived image".utf8))
        try await store.save(
            JournalItem(
                kind: "entry", title: title,
                document: .init(blocks: [DocumentBlock(kind: "image", attachmentID: image, imageDescription: "")])))
        let archive = root.appendingPathComponent("copy.journalarchive")
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
        try await store.close()
        return (archive, phrase, key)
    }

    func testCopiedPackageWithSystemFilesRestoresFromOneSelfContainedDatabase() async throws {
        let (archive, phrase, _) = try await export("Written before the copy")
        let names = try FileManager.default.contentsOfDirectory(atPath: archive.path)
        XCTAssertFalse(names.contains { $0.hasPrefix("journal.sqlite-") }, "No write-ahead log beside the database")
        // SQLite's file format versions: 1 is the rollback journal, 2 needs a write-ahead log.
        let header = try Data(contentsOf: archive.appendingPathComponent("journal.sqlite")).prefix(20)
        XCTAssertEqual(Array(header.suffix(2)), [1, 1])
        let images = archive.appendingPathComponent("attachments")
        for name in try FileManager.default.contentsOfDirectory(atPath: images.path) {
            try Data("resource fork".utf8).write(to: images.appendingPathComponent("._" + name))
        }
        try Data().write(to: images.appendingPathComponent(".DS_Store"))

        let restored = try await VaultArchive.restore(
            from: archive, to: root.appendingPathComponent("restored"), phrase: phrase)
        let items = try await restored.store.items()
        XCTAssertEqual(items.map(\.title), ["Written before the copy"])
        try await restored.store.close()
    }

    func testRestoreRejectsADatabaseWithObjectsTheAppDoesNotCreate() async throws {
        let (archive, phrase, key) = try await export("Protected entry")
        let database = archive.appendingPathComponent("journal.sqlite")
        let queue = try DatabaseQueue(path: database.path)
        try await queue.write {
            try $0.execute(
                sql: "CREATE TRIGGER copy_outbox AFTER INSERT ON outbox BEGIN DELETE FROM history; END")
        }
        try queue.close()
        // Someone with the key can list the altered database; the schema itself must still be refused.
        let headerURL = archive.appendingPathComponent("archive.json")
        var header = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: headerURL)) as? [String: Any])
        let sealed = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(header["manifest"] as? String)))
        let opened = try VaultCrypto.open(sealed, key: key, context: "journal:v1:archive")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: opened) as? [String: Any])
        manifest["database"] = SHA256.hash(data: try Data(contentsOf: database)).map { String(format: "%02x", $0) }
            .joined()
        let resealed = try VaultCrypto.seal(
            JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys), key: key,
            context: "journal:v1:archive")
        header["manifest"] = resealed.base64EncodedString()
        try JSONSerialization.data(withJSONObject: header).write(to: headerURL)

        let destination = root.appendingPathComponent("restored")
        do {
            _ = try await VaultArchive.restore(from: archive, to: destination, phrase: phrase)
            XCTFail("A database with a trigger must not become the journal")
        } catch JournalError.invalidData {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
