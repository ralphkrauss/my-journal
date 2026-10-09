import CryptoKit
import GRDB
import XCTest

@testable import JournalCore

/// protocol/conformance/archive/v1: a small library as My Journal 1.0 wrote it, a directory archive, once with a master
/// password and once without (protocol/archive.md). Restoring them, reading the database and the manifest directly, and
/// the damage a reader must refuse are checked here; the server's tests read the same files with .NET and SQLite.
///
/// The fixtures are read-only. The app no longer writes a directory archive, so nothing can regenerate them: the
/// committed files are the 1.0 writer's own output, which is what makes them worth testing against.
final class ConformanceArchiveTests: XCTestCase {
    private static let base = "archive/v1"
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        // A restore creates its own folder, not the folders above it.
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Corpus: Decodable {
        struct Recovery: Decodable {
            let password: String
            let vaultKey: Data
        }
        let recovery: Recovery
    }

    // MARK: Reading the database directly, as another client does

    private func rows(_ queue: DatabaseQueue, _ sql: String) throws -> [Row] {
        try queue.read { try Row.fetchAll($0, sql: sql) }
    }

    private func plaintext(_ payload: String, key: Data, protection: ContentProtection, id: String, kind: String)
        throws -> String
    {
        let data = try XCTUnwrap(Data(base64Encoded: payload))
        let context = "journal:v1:record:\(kind):\(id)"
        let opened = protection == .encrypted ? try VaultCrypto.open(data, key: key, context: context) : data
        return String(decoding: opened, as: UTF8.self)
    }

    private func listing(of directory: URL, key: Data, protection: ContentProtection) throws -> [String: Any] {
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("journal.sqlite").path)
        defer { try? queue.close() }
        func open(_ row: Row, _ idColumn: String) throws -> String {
            try plaintext(row["payload"], key: key, protection: protection, id: row[idColumn], kind: row["kind"])
        }
        let records = try rows(queue, "SELECT id, kind, payload, revision, dirty FROM records ORDER BY id").map { row in
            [
                "id": row["id"] as String, "kind": row["kind"] as String, "revision": row["revision"] as Int64,
                "dirty": row["dirty"] as Int64, "plaintext": try open(row, "id"),
            ] as [String: Any]
        }
        let outbox = try rows(queue, "SELECT operation, record, kind, payload, base FROM outbox ORDER BY operation").map
        { row in
            [
                "operation": row["operation"] as String, "record": row["record"] as String,
                "kind": row["kind"] as String,
                "base": row["base"] as Int64, "plaintext": try open(row, "record"),
            ] as [String: Any]
        }
        let history = try rows(queue, "SELECT id, record, kind, payload, checkpoint FROM history ORDER BY id").map {
            row in
            [
                "record": row["record"] as String, "kind": row["kind"] as String,
                "checkpoint": row["checkpoint"] as Int64,
                "plaintext": try open(row, "record"),
            ] as [String: Any]
        }
        let settings = try rows(queue, "SELECT key, value FROM settings WHERE key = 'content-protection'").map { row in
            let value: Data = row["value"]
            return ["key": row["key"] as String, "value": String(decoding: value, as: UTF8.self)]
        }
        let migrations = try rows(queue, "SELECT identifier FROM grdb_migrations ORDER BY rowid").map {
            $0["identifier"] as String
        }
        let attachments = try rows(queue, "SELECT id, uploaded FROM attachments ORDER BY id").map {
            row -> [String: Any] in
            let id: String = row["id"]
            let stored = try Data(contentsOf: directory.appendingPathComponent("attachments/" + id))
            let context = "journal:v1:attachment:\(id)"
            let image = protection == .encrypted ? try VaultCrypto.open(stored, key: key, context: context) : stored
            return [
                "id": id, "uploaded": row["uploaded"] as Int64, "bytes": image.count,
                "sha256": SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined(),
            ]
        }
        return [
            "records": records, "outbox": outbox, "history": history, "attachments": attachments,
            "settings": settings, "migrations": migrations,
        ]
    }

    private func header(of directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("archive.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The manifest as the header holds it: sealed under the vault key with AAD journal:v1:archive, or readable.
    private func manifest(of directory: URL, key: Data?) throws -> [String: Any] {
        let sealed = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(header(of: directory)["manifest"] as? String)))
        let bytes = try key.map { try VaultCrypto.open(sealed, key: $0, context: "journal:v1:archive") } ?? sealed
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func described(_ corpus: Corpus) throws -> [String: Any] {
        var archives: [String: Any] = [:]
        for (name, protection) in [("encrypted", ContentProtection.encrypted), ("plaintext", .plaintext)] {
            let directory = Conformance.url("\(Self.base)/\(name)")
            let encrypted = protection == .encrypted
            let key = corpus.recovery.vaultKey
            var entry = try listing(of: directory, key: key, protection: protection)
            let head = try header(of: directory)
            entry["headerVersion"] = head["version"]
            entry["formatVersion"] = (head["recovery"] as? [String: Any])?["formatVersion"]
            entry["manifest"] = try manifest(of: directory, key: encrypted ? key : nil)
            if encrypted { entry["password"] = corpus.recovery.password }
            archives[name] = entry
        }
        return archives
    }

    // MARK: Checks

    private func corpus() throws -> Corpus { try Conformance.decode(Corpus.self, "crypto/encryption-v2.json") }

    private func expected() throws -> [String: Any] {
        try Conformance.object("\(Self.base)/expected.json")
    }

    func testTheArchivesHoldWhatTheFixtureSays() async throws {
        let fixture = try expected()
        let corpus = try corpus()
        let archives = try XCTUnwrap(fixture["archives"] as? [String: Any])
        XCTAssertTrue(try Conformance.same(try described(corpus), archives))
    }

    func testTheEncryptedArchiveRestoresWithItsPasswordOnly() async throws {
        let fixture = try expected()
        let encrypted = try XCTUnwrap((fixture["archives"] as? [String: Any])?["encrypted"] as? [String: Any])
        let password = try XCTUnwrap(encrypted["password"] as? String)
        let source = Conformance.url("\(Self.base)/encrypted")
        XCTAssertTrue(try VaultArchive.requiresPassword(at: source))
        let restored = try await VaultArchive.restore(
            from: source, to: root.appendingPathComponent("restored"), phrase: password)
        let items = try await restored.store.items()
        let titles = items.filter { $0.kind == "entry" }.map(\.title).sorted()
        XCTAssertEqual(titles, ["Morning pages", "Written offline"])
        let offline = UUID(uuidString: "5E1F0C2E-3B4D-4E6F-8A9B-0C1D2E3F4A5B")
        let pending = try await restored.store.pending()
        XCTAssertTrue(pending.contains { $0.recordID == offline })
        let image = try XCTUnwrap(UUID(uuidString: ConformanceRecordCases.imageID))
        let bytes = try await restored.store.attachment(image)
        XCTAssertEqual(bytes, ConformanceExportLibrary.png)
        try await restored.store.close()
        do {
            _ = try await VaultArchive.restore(
                from: source, to: root.appendingPathComponent("wrong"), phrase: "not the password")
            XCTFail("A wrong password must not restore the archive.")
        } catch JournalError.invalidRecoveryKey {}
    }

    private func apply(_ ops: [[String: Any]], to directory: URL) throws {
        for op in ops {
            let kind = try XCTUnwrap(op["op"] as? String)
            if kind == "setHeaderVersion" {
                let url = directory.appendingPathComponent("archive.json")
                var header = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                header["version"] = op["version"]
                try JSONSerialization.data(withJSONObject: header).write(to: url)
                continue
            }
            let file = directory.appendingPathComponent(try XCTUnwrap(op["file"] as? String))
            switch kind {
            case "flipByte":
                var bytes = try Data(contentsOf: file)
                bytes[try XCTUnwrap(op["offset"] as? Int)] ^= 1
                try bytes.write(to: file)
            case "delete": try FileManager.default.removeItem(at: file)
            case "add": try Data(try XCTUnwrap(op["text"] as? String).utf8).write(to: file)
            default: XCTFail("Unknown operation \(kind)")
            }
        }
    }

    /// A reader refuses damaged packages and ignores clutter, as the fixture's mutations say.
    func testDamageIsRefusedAndClutterIsIgnored() async throws {
        let fixture = try expected()
        let encrypted = try XCTUnwrap((fixture["archives"] as? [String: Any])?["encrypted"] as? [String: Any])
        let password = try XCTUnwrap(encrypted["password"] as? String)
        let mutations = try XCTUnwrap(fixture["mutations"] as? [[String: Any]])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (index, mutation) in mutations.enumerated() {
            let copy = root.appendingPathComponent("mutated-\(index)")
            try FileManager.default.copyItem(at: Conformance.url("\(Self.base)/encrypted"), to: copy)
            try apply(try XCTUnwrap(mutation["ops"] as? [[String: Any]]), to: copy)
            let name = try XCTUnwrap(mutation["name"] as? String)
            let destination = root.appendingPathComponent("restored-\(index)")
            do {
                let restored = try await VaultArchive.restore(from: copy, to: destination, phrase: password)
                try await restored.store.close()
                XCTAssertEqual(mutation["result"] as? String, "restores", name)
            } catch {
                XCTAssertEqual(mutation["result"] as? String, "refused", "\(name): \(error)")
            }
        }
    }

    func testThePlaintextArchiveRestoresWithoutAPassword() async throws {
        let source = Conformance.url("\(Self.base)/plaintext")
        XCTAssertFalse(try VaultArchive.requiresPassword(at: source))
        let restored = try await VaultArchive.restore(
            from: source, to: root.appendingPathComponent("plain"), phrase: "")
        let titles = try await restored.store.items().filter { $0.kind == "entry" }.map(\.title).sorted()
        XCTAssertEqual(titles, ["Morning pages", "Written offline"])
        try await restored.store.close()
    }
}
