import CryptoKit
import GRDB
import XCTest

@testable import JournalCore

/// protocol/conformance/archive/v1: a small library as Export Archive writes it, once with a master password and once
/// without (protocol/archive.md). Restoring them, reading the database and the manifest directly, and the damage a
/// reader must refuse are checked here; the server's tests read the same files with .NET and SQLite.
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
            struct Wrapped: Decodable {
                let envelope: RecoveryEnvelopeText
            }
            let password: String
            let vaultKey: Data
            let envelopes: [Wrapped]
        }
        let recovery: Recovery
    }
    private struct RecoveryEnvelopeText: Decodable {
        let salt: String
        let wrappedKey: String
        let iterations: Int
        let formatVersion: Int
        var envelope: RecoveryEnvelope {
            RecoveryEnvelope(salt: salt, wrappedKey: wrappedKey, iterations: iterations, formatVersion: formatVersion)
        }
    }

    // MARK: Generation

    /// The library both archives hold: records as the Apple app writes them, one with an image, one made on this
    /// device and not yet sent, an earlier version, and the library record that holds pins.
    private func populate(_ store: JournalStore) async throws {
        let cases = ConformanceRecordCases.all
        for name in ["journal-with-default-template", "template", "entry-markdown"] {
            let record = try XCTUnwrap(cases.first { $0.name == name })
            let id = try XCTUnwrap(UUID(uuidString: record.id))
            try await store.insertSynchronized(Data(record.plaintext.utf8), id: id, kind: record.kind)
        }
        let image = try XCTUnwrap(UUID(uuidString: ConformanceRecordCases.imageID))
        _ = try await store.addAttachment(ConformanceExportLibrary.png, id: image)
        let entryID = try XCTUnwrap(UUID(uuidString: ConformanceRecordCases.entryID))
        let stored = try await store.item(entryID)
        let earlier = try XCTUnwrap(stored)
        try await store.keepInHistory(earlier)
        let journal = try XCTUnwrap(UUID(uuidString: ConformanceRecordCases.journalID))
        let offline = JournalItem(
            id: UUID(uuidString: "5E1F0C2E-3B4D-4E6F-8A9B-0C1D2E3F4A5B") ?? UUID(), kind: "entry", journalID: journal,
            title: "Written offline", document: JournalDocument(markdown: "Not sent to a server yet.\n"),
            date: (try? JournalCoding.date(from: "2026-10-01T08:00:00Z")) ?? Date())
        try await store.save(offline)
        try await store.setLibraryValues([
            "pinned/" + ConformanceRecordCases.entryID.lowercased(): .bool(true),
            "journal-rank/" + ConformanceRecordCases.journalID.lowercased(): .string("V"),
        ])
    }

    private func generate(_ corpus: Corpus) async throws {
        let manager = FileManager.default
        for (name, protection) in [("encrypted", ContentProtection.encrypted), ("plaintext", .plaintext)] {
            let destination = Conformance.url("\(Self.base)/\(name)")
            try? manager.removeItem(at: destination)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let key = protection == .encrypted ? corpus.recovery.vaultKey : try VaultCrypto.generateKey()
            let store = try JournalStore(
                directory: root.appendingPathComponent("source-" + name), key: key, protection: protection)
            try await populate(store)
            let recovery =
                protection == .encrypted
                ? try XCTUnwrap(corpus.recovery.envelopes.first).envelope.envelope : .unprotected
            try await VaultArchive.export(store: store, recovery: recovery, key: key, to: destination)
            try await store.close()
        }
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

    private func generated(_ corpus: Corpus) throws -> [String: Any] {
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

    private func inputs(_ corpus: Corpus) -> [String: Any] {
        [
            "corpusVersion": 1,
            "purpose":
                "A small library as Export Archive writes it, with a master password (encrypted/) and without (plaintext/): what is in the package and the database once decrypted (protocol/archive.md). The encrypted archive uses the format 2 envelope, password and vault key of crypto/encryption-v2.json. See README.md in this folder.",
            "passwordSource": "crypto/encryption-v2.json, recovery.password",
            "mutations": Self.mutations,
        ]
    }

    /// Damage and clutter applied to a copy of encrypted/, and whether a reader must then refuse it. Offsets are
    /// bytes from the start of the file; a flipped byte has its lowest bit inverted.
    private static let image = "attachments/01234567-89ab-4cde-8fab-0123456789ab"
    private static var mutations: [[String: Any]] {
        [
            [
                "name": "database-changed", "note": "A byte of the database differs from the manifest's hash.",
                "ops": [["op": "flipByte", "file": "journal.sqlite", "offset": 40000]], "result": "refused",
            ],
            [
                "name": "image-changed", "note": "A byte of an image differs from the manifest's hash.",
                "ops": [["op": "flipByte", "file": image, "offset": 20]], "result": "refused",
            ],
            [
                "name": "image-missing", "note": "A file the manifest lists is gone.",
                "ops": [["op": "delete", "file": image]], "result": "refused",
            ],
            [
                "name": "header-version-mismatch", "note": "Header version 2 on an envelope that needs a password.",
                "ops": [["op": "setHeaderVersion", "version": 2]], "result": "refused",
            ],
            [
                "name": "system-file-in-attachments",
                "note": "Copying between volumes adds dot files, which are ignored.",
                "ops": [
                    ["op": "add", "file": "attachments/.DS_Store", "text": ""],
                    [
                        "op": "add", "file": "attachments/._01234567-89ab-4cde-8fab-0123456789ab",
                        "text": "resource fork",
                    ],
                ],
                "result": "restores",
            ],
            [
                "name": "other-top-level-file", "note": "Other top-level files are ignored.",
                "ops": [["op": "add", "file": "Thumbs.db", "text": "thumbnails"]], "result": "restores",
            ],
        ]
    }

    // MARK: Checks

    private func corpus() throws -> Corpus { try Conformance.decode(Corpus.self, "crypto/encryption-v2.json") }

    private func expected() async throws -> [String: Any] {
        let corpus = try corpus()
        if Conformance.regenerating {
            try await generate(corpus)
            var fixture = inputs(corpus)
            fixture["archives"] = try generated(corpus)
            try Conformance.write(fixture, to: "\(Self.base)/expected.json")
        }
        return try Conformance.object("\(Self.base)/expected.json")
    }

    func testTheArchivesHoldWhatTheFixtureSays() async throws {
        let fixture = try await expected()
        let corpus = try corpus()
        let archives = try XCTUnwrap(fixture["archives"] as? [String: Any])
        XCTAssertTrue(try Conformance.same(try generated(corpus), archives))
    }

    func testTheEncryptedArchiveRestoresWithItsPasswordOnly() async throws {
        let fixture = try await expected()
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
        let fixture = try await expected()
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
        _ = try await expected()
        let source = Conformance.url("\(Self.base)/plaintext")
        XCTAssertFalse(try VaultArchive.requiresPassword(at: source))
        let restored = try await VaultArchive.restore(
            from: source, to: root.appendingPathComponent("plain"), phrase: "")
        let titles = try await restored.store.items().filter { $0.kind == "entry" }.map(\.title).sorted()
        XCTAssertEqual(titles, ["Morning pages", "Written offline"])
        try await restored.store.close()
    }
}
