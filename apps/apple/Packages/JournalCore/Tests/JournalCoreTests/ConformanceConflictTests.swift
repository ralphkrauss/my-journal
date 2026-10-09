import CryptoKit
import XCTest

@testable import JournalCore

/// protocol/conformance/records/conflict-resolution-v1.json, conflict-copy-ids-v1.json and journal-rewrite-v1.json: the
/// rules that settle a record changed on two devices, the identity of a parked entry or copy, and what a journal write
/// keeps (protocol/conflicts.md, protocol/records.md).
final class ConformanceConflictTests: XCTestCase {
    private static let resolutionPath = "records/conflict-resolution-v1.json"
    private static let identitiesPath = "records/conflict-copy-ids-v1.json"
    private static let rewritePath = "records/journal-rewrite-v1.json"

    /// The synthetic vault key of crypto/encryption-v2.json, which the identity vectors use.
    private static func vaultKey() throws -> Data {
        let crypto = try Conformance.object("crypto/encryption-v2.json")
        let recovery = try XCTUnwrap(crypto["recovery"] as? [String: Any])
        return try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(recovery["vaultKey"] as? String)))
    }
    private static func hex(_ data: some Sequence<UInt8>) -> String { data.map { String(format: "%02x", $0) }.joined() }

    // MARK: Settling

    private static func resolutionFixture() throws -> [String: Any] {
        let ids = ConflictCopyIdentity(vaultKey: try vaultKey())
        return try Conformance.fixture(resolutionPath) {
            let cases = try ConformanceConflictCases.all.map { testCase -> [String: Any] in
                [
                    "name": testCase.name, "note": testCase.note, "kind": testCase.kind,
                    "recordID": testCase.recordID.uuidString.lowercased(), "local": testCase.local,
                    "other": testCase.other, "expected": try ConformanceConflictCases.expected(for: testCase, ids: ids),
                ]
            }
            return [
                "corpusVersion": 1,
                "purpose":
                    "Two versions of one record as exact plaintext (local is this device's, other is the other device's) and what settling them produces (protocol/conflicts.md, The rules). Copy and parked identities use the vault key of crypto/encryption-v2.json. See README.md in this folder.",
                "identity": ["protection": "encrypted", "vaultKeyFrom": "crypto/encryption-v2.json recovery.vaultKey"],
                "cases": cases,
            ]
        }
    }

    func testEveryCaseIsSettledAsTheFixtureSays() throws {
        let fixture = try Self.resolutionFixture()
        let ids = ConflictCopyIdentity(vaultKey: try Self.vaultKey())
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 25)
        var rows = Set<Int>()
        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let input = ConformanceConflictCase(
                name: name, note: "", kind: try XCTUnwrap(item["kind"] as? String),
                recordID: try XCTUnwrap(UUID(uuidString: try XCTUnwrap(item["recordID"] as? String))),
                local: try XCTUnwrap(item["local"] as? String), other: try XCTUnwrap(item["other"] as? String))
            let expected = try XCTUnwrap(item["expected"] as? [String: Any])
            XCTAssertTrue(
                try Conformance.same(try ConformanceConflictCases.expected(for: input, ids: ids), expected), name)
            rows.insert(try XCTUnwrap(expected["row"] as? Int))
        }
        XCTAssertEqual(rows, [1, 2, 3, 4, 5, 6, 7], "Every row of the table is exercised")
    }

    // MARK: Identities

    private static func identitiesFixture() throws -> [String: Any] {
        let key = try vaultKey()
        return try Conformance.fixture(identitiesPath) {
            let encrypted = ConflictCopyIdentity(vaultKey: key)
            let plain = ConflictCopyIdentity(vaultKey: nil)
            let cases = ConformanceConflictCases.identityCases.map { testCase -> [String: Any] in
                let identity = testCase.protection == "encrypted" ? encrypted : plain
                let record = UUID(uuidString: testCase.recordID) ?? UUID()
                let bytes = Data(testCase.text.utf8)
                let digest = hex(SHA256.hash(data: bytes))
                let message = "\(testCase.label.rawValue)\n\(testCase.recordID)\n\(digest)"
                let tag = HMAC<SHA256>.authenticationCode(
                    for: Data(message.utf8), using: SymmetricKey(data: identity.subkeyBytes))
                return [
                    "name": testCase.name, "note": testCase.note, "protection": testCase.protection,
                    "label": testCase.label.rawValue, "recordID": testCase.recordID, "text": testCase.text,
                    "textSha256": digest, "message": message, "tag": hex(tag),
                    "id": identity.copyID(testCase.label, record: record, plaintext: bytes).uuidString.lowercased(),
                ]
            }
            return [
                "corpusVersion": 1,
                "purpose":
                    "The identity of a parked entry or copy (protocol/conflicts.md, Identities): HKDF-SHA-256 over the vault key, HMAC-SHA-256 over the label, the record's identity and the SHA-256 of the exact text, with the version and variant bits set. See README.md in this folder.",
                "info": ConflictCopyIdentity.info,
                "derivation": [
                    "encrypted": [
                        "vaultKeyFrom": "crypto/encryption-v2.json recovery.vaultKey",
                        "hkdfOutput": hex(encrypted.subkeyBytes),
                    ],
                    "plaintext": ["sha256OfInfo": hex(plain.subkeyBytes)],
                ],
                "cases": cases,
            ]
        }
    }

    /// The vectors follow the contract when computed with the primitives directly, not only with this app's function.
    func testIdentitiesFollowTheContractComputedFromPrimitives() throws {
        let fixture = try Self.identitiesFixture()
        let info = try XCTUnwrap(fixture["info"] as? String)
        let derivation = try XCTUnwrap(fixture["derivation"] as? [String: Any])
        let encrypted = SymmetricKey(
            data: Data(
                HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: SymmetricKey(data: try Self.vaultKey()), salt: Data(), info: Data(info.utf8),
                    outputByteCount: 32
                ).withUnsafeBytes { Data($0) }))
        let plain = SymmetricKey(data: Data(SHA256.hash(data: Data(info.utf8))))
        let keys = try XCTUnwrap(derivation["encrypted"] as? [String: Any])
        XCTAssertEqual(keys["hkdfOutput"] as? String, Self.hex(encrypted.withUnsafeBytes { Data($0) }))
        XCTAssertEqual(
            (derivation["plaintext"] as? [String: Any])?["sha256OfInfo"] as? String,
            Self.hex(plain.withUnsafeBytes { Data($0) }))
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        var seen = Set<String>()
        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let text = try XCTUnwrap(item["text"] as? String)
            let record = try XCTUnwrap(item["recordID"] as? String)
            let label = try XCTUnwrap(item["label"] as? String)
            let digest = Self.hex(SHA256.hash(data: Data(text.utf8)))
            XCTAssertEqual(item["textSha256"] as? String, digest, name)
            let message = "\(label)\n\(record.lowercased())\n\(digest)"
            XCTAssertEqual(item["message"] as? String, message, name)
            let key = item["protection"] as? String == "encrypted" ? encrypted : plain
            var bytes = Array(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key).prefix(16))
            XCTAssertEqual(
                item["tag"] as? String, Self.hex(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)),
                name)
            bytes[6] = (bytes[6] & 0x0F) | 0x80
            bytes[8] = (bytes[8] & 0x3F) | 0x80
            let hexText = Self.hex(bytes)
            let id = [
                hexText.prefix(8), hexText.dropFirst(8).prefix(4), hexText.dropFirst(12).prefix(4),
                hexText.dropFirst(16).prefix(4), hexText.dropFirst(20),
            ].map(String.init).joined(separator: "-")
            XCTAssertEqual(item["id"] as? String, id, name)
            XCTAssertEqual(String(id.dropFirst(14).prefix(1)), "8", "Version nibble 8, which readers must not reject")
            XCTAssertTrue(["8", "9", "a", "b"].contains(String(id.dropFirst(19).prefix(1))), "RFC 4122 variant bits")
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, cases.count, "Every case has its own identity")
    }

    // MARK: A journal written back keeps what it does not show

    private static func rewriteFixture() async throws -> [String: Any] {
        let key = try vaultKey()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var journal = JournalItem(
            id: ConformanceConflictCases.journalID, kind: "journal", title: "Personal", document: .init(),
            date: ConformanceConflictCases.utc("2026-01-02T03:04:05Z"))
        journal.modifiedAt = ConformanceConflictCases.utc("2026-01-02T03:04:05Z")
        journal.defaultTemplateID = ConformanceConflictCases.templateRefID
        let store = try JournalStore(directory: root, key: key)
        try await store.save(journal)
        var cases: [[String: Any]] = []
        func record(_ name: String, _ note: String, _ operation: String, _ before: JournalItem, _ after: JournalItem) {
            cases.append([
                "name": name, "note": note, "operation": operation, "before": ConformanceConflictCases.text(before),
                "after": [
                    "title": after.title,
                    "deletedAt": after.deletedAt.map { Int($0.timeIntervalSince1970) } ?? NSNull(),
                    "defaultTemplateID": after.defaultTemplateID?.uuidString.lowercased() ?? NSNull(),
                ] as [String: Any],
            ])
        }
        var renamed = journal
        renamed.title = "Personal, renamed"
        try await store.save(renamed)
        let storedRename = try await store.item(journal.id)
        let afterRename = try XCTUnwrap(storedRename)
        record(
            "rename",
            "Renaming keeps the default template that 1.0 and earlier set, which 1.1 and later neither show nor use.",
            "title = \"Personal, renamed\"", journal, afterRename)
        let plan = try await store.prepareJournalDeletion(journal.id)
        let afterDelete = try await store.deleteJournal(plan)
        record("delete", "Deleting a journal sets only its deletedAt.", "deletedAt = now", afterRename, afterDelete)
        let afterRestore = try await store.restoreJournal(journal.id)
        record(
            "restore", "Restoring clears deletedAt and keeps everything else.", "deletedAt = null", afterDelete,
            afterRestore)
        try await store.close()
        return [
            "corpusVersion": 1,
            "purpose":
                "A journal with a defaultTemplateID, written back after a rename, a deletion and a restoration (protocol/records.md, Writing a journal back). A client that drops the member breaks the setting of a device that still uses it. See README.md in this folder.",
            "cases": cases,
        ]
    }

    func testAJournalKeepsItsDefaultTemplateWhateverIsWrittenToIt() async throws {
        let fixture: [String: Any]
        if Conformance.regenerating {
            fixture = try await Self.rewriteFixture()
            try Conformance.write(fixture, to: Self.rewritePath)
        } else {
            fixture = try Conformance.object(Self.rewritePath)
        }
        let regenerated = try await Self.rewriteFixture()
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        let recomputed = try XCTUnwrap(regenerated["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)
        for (item, again) in zip(cases, recomputed) {
            let name = try XCTUnwrap(item["name"] as? String)
            let after = try XCTUnwrap(item["after"] as? [String: Any])
            // Every case keeps the member, and what this app writes now says the same as the file.
            XCTAssertEqual(
                after["defaultTemplateID"] as? String, ConformanceConflictCases.templateRefID.uuidString.lowercased(),
                name)
            let current = try XCTUnwrap(again["after"] as? [String: Any])
            XCTAssertEqual(after["title"] as? String, current["title"] as? String, name)
            XCTAssertEqual(after["defaultTemplateID"] as? String, current["defaultTemplateID"] as? String, name)
            // The "before" plaintext reads as an editable journal with the member.
            let before = try PortableRecord.decode(Data(try XCTUnwrap(item["before"] as? String).utf8))
            XCTAssertNil(before.preservedJSON, name)
            XCTAssertEqual(before.defaultTemplateID, ConformanceConflictCases.templateRefID, name)
        }
    }
}
