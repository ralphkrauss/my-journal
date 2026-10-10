import CryptoKit
import XCTest

@testable import JournalCore

/// protocol/conformance/archive/v2: real encrypted file archives, as the Apple app writes them (the library of
/// archive/v1/encrypted repackaged, and an empty one sealed under a format 1 recovery key). The files are made once;
/// `JOURNAL_CONFORMANCE_REGENERATE=1 swift test --filter ConformanceArchiveV2` makes new ones (new random nonces) and
/// rewrites `expected.json`. Restoring them, the layout of the container and the mutations a reader must refuse or
/// accept are checked here; the server's tests read the same files with .NET.
final class ConformanceArchiveV2Tests: XCTestCase {
    private static let base = "archive/v2"
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Credentials of the shared corpora

    private struct PasswordCorpus: Decodable {
        struct Recovery: Decodable {
            struct Wrapped: Decodable {
                let envelope: EnvelopeText
            }
            let password: String
            let vaultKey: Data
            let envelopes: [Wrapped]
        }
        let recovery: Recovery
    }
    private struct EnvelopeText: Decodable {
        let salt: String
        let wrappedKey: String
        let iterations: Int
        let formatVersion: Int
        var envelope: RecoveryEnvelope {
            RecoveryEnvelope(salt: salt, wrappedKey: wrappedKey, iterations: iterations, formatVersion: formatVersion)
        }
    }
    private struct KeyCorpus: Decodable {
        struct Recovery: Decodable {
            let phrase: String
            let salt: String
            let iterations: Int
        }
        struct Item: Decodable {
            let name: String
            let plaintext: String
            let combined: String
        }
        let recovery: Recovery
        let envelopes: [Item]
    }

    /// The format 1 envelope, phrase and vault key of crypto/encryption-v1.json.
    private func recoveryKeyCredentials() throws -> (envelope: RecoveryEnvelope, phrase: String, vaultKey: Data) {
        let corpus = try Conformance.decode(KeyCorpus.self, "crypto/encryption-v1.json")
        let wrapping = try XCTUnwrap(corpus.envelopes.first { $0.name == "recovery" })
        let envelope = RecoveryEnvelope(
            salt: corpus.recovery.salt, wrappedKey: wrapping.combined, iterations: corpus.recovery.iterations,
            formatVersion: 1)
        return (envelope, corpus.recovery.phrase, try XCTUnwrap(Data(base64Encoded: wrapping.plaintext)))
    }

    private func passwordCredentials() throws -> (envelope: RecoveryEnvelope, password: String, vaultKey: Data) {
        let corpus = try Conformance.decode(PasswordCorpus.self, "crypto/encryption-v2.json")
        let first = try XCTUnwrap(corpus.recovery.envelopes.first)
        return (first.envelope.envelope, corpus.recovery.password, corpus.recovery.vaultKey)
    }

    // MARK: Generation

    private func generate() async throws {
        let credentials = try passwordCredentials()
        let v1 = Conformance.url("archive/v1/encrypted")
        let database = root.appendingPathComponent("v1-journal.sqlite")
        try FileManager.default.copyItem(at: v1.appendingPathComponent("journal.sqlite"), to: database)
        let images = try FileManager.default.contentsOfDirectory(atPath: v1.appendingPathComponent("attachments").path)
            .filter { !$0.hasPrefix(".") }
            .map { FileArchive.Image(identifier: $0, file: v1.appendingPathComponent("attachments/\($0)")) }
        try? FileManager.default.removeItem(at: Conformance.url("\(Self.base)/encrypted.zip"))
        try FileArchive.write(
            databaseFile: database, images: images, recovery: credentials.envelope, key: credentials.vaultKey,
            to: Conformance.url("\(Self.base)/encrypted.zip"), options: .standard)

        let legacy = try recoveryKeyCredentials()
        let empty = try JournalStore(directory: root.appendingPathComponent("empty"), key: legacy.vaultKey)
        let snapshot = root.appendingPathComponent("empty.sqlite")
        let identifiers = try await empty.exportDatabase(to: snapshot)
        XCTAssertTrue(identifiers.isEmpty)
        try await empty.close()
        try? FileManager.default.removeItem(at: Conformance.url("\(Self.base)/encrypted-recovery-key.zip"))
        try FileArchive.write(
            databaseFile: snapshot, images: [], recovery: legacy.envelope, key: legacy.vaultKey,
            to: Conformance.url("\(Self.base)/encrypted-recovery-key.zip"), options: .standard)
    }

    // MARK: Reading the container without the reader under test

    struct Layout {
        let name: String
        let localHeaderOffset: Int
        let centralHeaderOffset: Int
        let dataOffset: Int
        let bytes: Int
        let method: Int
        let crc32: UInt32
    }

    static func le16(_ data: Data, _ offset: Int) -> Int {
        Int(data[data.startIndex + offset]) | Int(data[data.startIndex + offset + 1]) << 8
    }
    static func le32(_ data: Data, _ offset: Int) -> Int { le16(data, offset) | le16(data, offset + 2) << 16 }

    /// The entries of a small archive the way a short script would find them: the end record, then each central entry.
    static func layout(of archive: Data) -> [Layout] {
        let recordStart = archive.count - 22
        let count = le16(archive, recordStart + 10)
        var position = le32(archive, recordStart + 16)
        var entries: [Layout] = []
        for _ in 0..<count {
            let nameLength = le16(archive, position + 28)
            let extraLength = le16(archive, position + 30)
            let commentLength = le16(archive, position + 32)
            let local = le32(archive, position + 42)
            let nameStart = archive.startIndex + position + 46
            let name = String(decoding: archive[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let dataOffset = local + 30 + le16(archive, local + 26) + le16(archive, local + 28)
            entries.append(
                Layout(
                    name: name, localHeaderOffset: local, centralHeaderOffset: position, dataOffset: dataOffset,
                    bytes: le32(archive, position + 24), method: le16(archive, position + 10),
                    crc32: UInt32(le32(archive, position + 16))))
            position += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// CRC-32 (IEEE), written out so that the mutations do not depend on the code under test.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    static func little(_ value: UInt32) -> String { hex((0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) }) }
    static func sha256(_ data: Data) -> String { hex(Array(SHA256.hash(data: data))) }

    // MARK: The golden description

    private func describe(_ file: String, password: String, formatVersion: Int) throws -> [String: Any] {
        let archive = try Conformance.data("\(Self.base)/\(file)")
        let entries = Self.layout(of: archive)
        let listed = entries.map { entry -> [String: Any] in
            let data = archive[
                (archive.startIndex + entry.dataOffset)..<(archive.startIndex + entry.dataOffset + entry.bytes)]
            return [
                "name": entry.name, "localHeaderOffset": entry.localHeaderOffset, "dataOffset": entry.dataOffset,
                "bytes": entry.bytes, "method": entry.method, "crc32": Self.little(entry.crc32),
                "sha256": Self.sha256(data),
            ]
        }
        return ["file": file, "password": password, "recoveryFormat": formatVersion, "entries": listed]
    }

    private func generated() throws -> [String: Any] {
        let credentials = try passwordCredentials()
        let legacy = try recoveryKeyCredentials()
        var encrypted = try describe("encrypted.zip", password: credentials.password, formatVersion: 2)
        encrypted["titles"] = ["Morning pages", "Written offline"]
        var legacyArchive = try describe("encrypted-recovery-key.zip", password: legacy.phrase, formatVersion: 1)
        legacyArchive["titles"] = [String]()
        return ["encrypted": encrypted, "encryptedRecoveryKey": legacyArchive]
    }

    // MARK: Mutations

    private struct Mutation {
        let name: String
        let note: String
        let expect: String
        var operations: [[String: Any]] = []
        var password: String?
    }

    private func set(_ offset: Int, _ bytes: [UInt8]) -> [String: Any] {
        ["op": "set", "offset": offset, "bytes": Self.hex(bytes)]
    }

    /// Changes `replacement` bytes of an entry's data at `index`, and (when `patchCRC`) the CRC-32 in the local header
    /// and the central directory so that the check under test, not the CRC, is what fires.
    private func change(
        _ entry: Layout, in archive: Data, at index: Int, to replacement: [UInt8], patchCRC: Bool
    ) -> [[String: Any]] {
        var data = Data(
            archive[(archive.startIndex + entry.dataOffset)..<(archive.startIndex + entry.dataOffset + entry.bytes)])
        for (position, byte) in replacement.enumerated() { data[data.startIndex + index + position] = byte }
        var operations = [set(entry.dataOffset + index, replacement)]
        if patchCRC {
            let crc = Self.crc32(data)
            let bytes = (0..<4).map { UInt8((crc >> (8 * UInt32($0))) & 0xFF) }
            operations.append(set(entry.localHeaderOffset + 14, bytes))
            operations.append(set(entry.centralHeaderOffset + 16, bytes))
        }
        return operations
    }

    private func mutations() throws -> [[String: Any]] {
        let credentials = try passwordCredentials()
        let archive = try Conformance.data("\(Self.base)/encrypted.zip")
        let entries = Self.layout(of: archive)
        func entry(_ name: String) throws -> Layout { try XCTUnwrap(entries.first { $0.name == name }) }
        let database = try entry("journal.sqlite")
        let image = try entry("attachments/01234567-89ab-4cde-8fab-0123456789ab")
        let header = try entry("archive.json")
        let headerBytes = archive[
            (archive.startIndex + header.dataOffset)..<(archive.startIndex + header.dataOffset + header.bytes)]
        let headerText = String(decoding: headerBytes, as: UTF8.self)

        func flip(_ target: Layout, _ index: Int, patchCRC: Bool) -> [[String: Any]] {
            let original = archive[archive.startIndex + target.dataOffset + index]
            return change(target, in: archive, at: index, to: [original ^ 1], patchCRC: patchCRC)
        }
        func edit(_ marker: String, offset: Int, to replacement: String, patchCRC: Bool) throws -> [[String: Any]] {
            let found = try XCTUnwrap(headerText.range(of: marker))
            let index = headerText.utf8.distance(from: headerText.startIndex, to: found.lowerBound) + offset
            // A change that changes nothing would test nothing.
            let current = headerBytes[headerBytes.startIndex + index]
            let different = current == Array(replacement.utf8)[0] ? UInt8(ascii: "B") : Array(replacement.utf8)[0]
            return change(header, in: archive, at: index, to: [different], patchCRC: patchCRC)
        }
        let list = [
            Mutation(
                name: "database-byte-changed",
                note: "One byte of journal.sqlite; the CRC-32 is patched, so the manifest's hash catches it.",
                expect: "damaged", operations: flip(database, 40000, patchCRC: true)),
            Mutation(
                name: "database-byte-changed-stale-crc",
                note: "The same change with the CRC-32 left alone: the CRC-32 is checked.",
                expect: "damaged", operations: flip(database, 40000, patchCRC: false)),
            Mutation(
                name: "image-byte-changed", note: "One byte of the image with the CRC-32 patched.", expect: "damaged",
                operations: flip(image, 20, patchCRC: true)),
            Mutation(
                name: "image-byte-changed-stale-crc", note: "The same with the CRC-32 left alone.", expect: "damaged",
                operations: flip(image, 20, patchCRC: false)),
            Mutation(
                name: "manifest-byte-changed",
                note:
                    "A character of the sealed manifest in archive.json; the CRC-32 is patched, so authentication fails.",
                expect: "damaged", operations: try edit("\"manifest\":\"", offset: 30, to: "A", patchCRC: true)),
            Mutation(
                name: "archive-version-newer", note: "archiveVersion 3 with the CRC-32 patched: a newer archive.",
                expect: "newer", operations: try edit("\"archiveVersion\":2", offset: 17, to: "3", patchCRC: true)),
            Mutation(
                name: "archive-version-newer-stale-crc",
                note:
                    "archiveVersion 3 with the CRC-32 left alone: the CRC-32 is checked before archive.json is decoded, so this is damaged, not newer.",
                expect: "damaged", operations: try edit("\"archiveVersion\":2", offset: 17, to: "3", patchCRC: false)),
            Mutation(
                name: "recovery-format-4",
                note:
                    "The envelope's formatVersion 4 (no password) in a file archive: refused before anything else is read.",
                expect: "damaged", operations: try edit("\"formatVersion\":2", offset: 16, to: "4", patchCRC: true)),
            Mutation(
                name: "wrong-password", note: "The right file with a password that does not open the envelope.",
                expect: "wrongPassword",
                password: "not the password"),
            Mutation(
                name: "manifest-sealed-for-a-directory-archive",
                note:
                    "The manifest sealed under the directory archive's context journal:v1:archive instead of journal:v2:archive; same length, CRC-32 patched.",
                expect: "damaged",
                operations: try resealed(
                    headerText: headerText, header: header, archive: archive, credentials: credentials.vaultKey)),
        ]
        return list.map { mutation in
            var record: [String: Any] = [
                "name": mutation.name, "note": mutation.note, "archive": "encrypted", "expect": mutation.expect,
                "operations": mutation.operations,
            ]
            if let password = mutation.password { record["password"] = password }
            return record
        }
    }

    /// Replaces the base64 manifest with the same plaintext sealed under the other context, which has the same length.
    private func resealed(headerText: String, header: Layout, archive: Data, credentials key: Data) throws -> [[String:
        Any]]
    {
        let marker = "\"manifest\":\""
        let start = try XCTUnwrap(headerText.range(of: marker)).upperBound
        let end = try XCTUnwrap(headerText[start...].firstIndex(of: "\""))
        let sealed = try XCTUnwrap(Data(base64Encoded: String(headerText[start..<end])))
        let plain = try VaultCrypto.open(sealed, key: key, context: FileArchiveHeader.manifestContext)
        let other = try VaultCrypto.seal(plain, key: key, context: "journal:v1:archive").base64EncodedString()
        let index = headerText.utf8.distance(from: headerText.startIndex, to: start)
        XCTAssertEqual(other.utf8.count, headerText.utf8.distance(from: start, to: end))
        return change(header, in: archive, at: index, to: Array(other.utf8), patchCRC: true)
    }

    private func inputs() throws -> [String: Any] {
        [
            "corpusVersion": 1,
            "purpose":
                "The file archive (protocol/archive.md): the library of archive/v1/encrypted repackaged with a master password envelope (recovery format 2), and an empty library under a recovery key envelope (format 1), with the entries of the container and the mutations a reader must refuse. See README.md in this folder.",
            "passwordSource":
                "crypto/encryption-v2.json, recovery.password (encrypted.zip); crypto/encryption-v1.json, recovery.phrase (encrypted-recovery-key.zip)",
            "databaseSource":
                "archive/v1/expected.json, archives.encrypted: journal.sqlite and the image of encrypted.zip are the files of archive/v1/encrypted byte for byte",
            "archiveVersion": 2,
            "mutations": try mutations(),
        ]
    }

    private func expected() async throws -> [String: Any] {
        if Conformance.regenerating {
            try await generate()
            var fixture = try inputs()
            fixture["archives"] = try generated()
            try Conformance.write(fixture, to: "\(Self.base)/expected.json")
        }
        return try Conformance.object("\(Self.base)/expected.json")
    }

    // MARK: Checks

    func testTheArchivesHoldWhatTheFixtureSays() async throws {
        let fixture = try await expected()
        let archives = try XCTUnwrap(fixture["archives"] as? [String: Any])
        XCTAssertTrue(try Conformance.same(try generated(), archives))
    }

    /// The database and the image are those of archive/v1/encrypted, byte for byte, so the v1 and v2 listings of the
    /// database agree; the manifest authenticates and lists exactly them.
    func testTheEncryptedArchiveRepackagesTheVersion1Files() async throws {
        _ = try await expected()
        let archive = try Conformance.data("\(Self.base)/encrypted.zip")
        let v1 = Conformance.url("archive/v1/encrypted")
        for entry in Self.layout(of: archive) where entry.name != "archive.json" {
            let data = archive[
                (archive.startIndex + entry.dataOffset)..<(archive.startIndex + entry.dataOffset + entry.bytes)]
            XCTAssertEqual(data, try Data(contentsOf: v1.appendingPathComponent(entry.name)), entry.name)
        }
    }

    func testTheEncryptedArchiveRestoresWithItsPasswordOnly() async throws {
        _ = try await expected()
        let credentials = try passwordCredentials()
        let source = Conformance.url("\(Self.base)/encrypted.zip")
        XCTAssertNoThrow(try VaultArchive.checkHeader(at: source))
        let restored = try await VaultArchive.restore(
            from: source, to: root.appendingPathComponent("restored"), phrase: credentials.password)
        XCTAssertEqual(restored.key, credentials.vaultKey)
        let titles = try await restored.store.items().filter { $0.kind == "entry" }.map(\.title).sorted()
        XCTAssertEqual(titles, ["Morning pages", "Written offline"])
        let image = try XCTUnwrap(UUID(uuidString: ConformanceRecordCases.imageID))
        let bytes = try await restored.store.attachment(image)
        XCTAssertEqual(bytes, ConformanceExportLibrary.png)
        try await restored.store.close()
        do {
            _ = try await VaultArchive.restore(
                from: source, to: root.appendingPathComponent("trimmed"),
                phrase: credentials.password.trimmingCharacters(in: .whitespaces))
            XCTFail("Format 2 does not trim: the trimmed password opens nothing")
        } catch JournalError.invalidRecoveryKey {}
    }

    /// A format 1 envelope (the generated recovery key, trimmed and compared exactly) opens a file archive too.
    func testTheRecoveryKeyArchiveRestoresWithTheLegacyKey() async throws {
        _ = try await expected()
        let legacy = try recoveryKeyCredentials()
        let source = Conformance.url("\(Self.base)/encrypted-recovery-key.zip")
        let restored = try await VaultArchive.restore(
            from: source, to: root.appendingPathComponent("restored"), phrase: legacy.phrase)
        XCTAssertEqual(restored.key, legacy.vaultKey)
        XCTAssertEqual(restored.recovery.formatVersion, 1)
        let items = try await restored.store.items()
        XCTAssertTrue(items.isEmpty)
        try await restored.store.close()
        do {
            _ = try await VaultArchive.restore(
                from: source, to: root.appendingPathComponent("wrong"), phrase: legacy.phrase.uppercased())
            XCTFail("Format 1 does not fold case")
        } catch JournalError.invalidRecoveryKey {}
    }

    private func apply(_ operations: [[String: Any]], to archive: Data) throws -> Data {
        var bytes = archive
        for operation in operations {
            XCTAssertEqual(operation["op"] as? String, "set")
            let offset = try XCTUnwrap(operation["offset"] as? Int)
            let text = try XCTUnwrap(operation["bytes"] as? String)
            var index = text.startIndex
            var position = offset
            while index < text.endIndex {
                let next = text.index(index, offsetBy: 2)
                bytes[bytes.startIndex + position] = try XCTUnwrap(UInt8(text[index..<next], radix: 16))
                index = next
                position += 1
            }
        }
        return bytes
    }

    func testEveryMutationGivesTheStatedOutcome() async throws {
        let fixture = try await expected()
        let credentials = try passwordCredentials()
        let original = try Conformance.data("\(Self.base)/encrypted.zip")
        let mutations = try XCTUnwrap(fixture["mutations"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(mutations.count, 10)
        for (index, mutation) in mutations.enumerated() {
            let name = try XCTUnwrap(mutation["name"] as? String)
            let archive = root.appendingPathComponent("mutated-\(index).zip")
            try apply(try XCTUnwrap(mutation["operations"] as? [[String: Any]]), to: original).write(to: archive)
            let password = mutation["password"] as? String ?? credentials.password
            let destination = root.appendingPathComponent("restored-\(index)")
            do {
                let restored = try await VaultArchive.restore(from: archive, to: destination, phrase: password)
                try await restored.store.close()
                XCTAssertEqual(mutation["expect"] as? String, "accept", name)
            } catch {
                XCTAssertEqual(
                    ConformanceContainerTests.outcome(of: error), mutation["expect"] as? String, "\(name): \(error)")
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), name)
            }
        }
    }
}
