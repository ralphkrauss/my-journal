import CryptoKit
import XCTest

@testable import JournalCore

/// protocol/conformance/markdown-export/library-v1.json: a whole library exported by the real export, as the
/// folder every client must write for the same library (protocol/markdown-export.md).
final class ConformanceExportLibraryTests: XCTestCase {
    private static let path = "markdown-export/library-v1.json"
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Stores every record as a synchronized device would hold it, including ones this version can't fully read.
    private func store(_ records: [[String: Any]], in store: JournalStore) async throws {
        for record in records {
            let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(record["id"] as? String)))
            let kind = try XCTUnwrap(record["kind"] as? String)
            let plaintext = Data(try XCTUnwrap(record["plaintext"] as? String).utf8)
            try await store.insertSynchronized(plaintext, id: id, kind: kind)
        }
    }

    /// Exports the fixture's library and lists what was written.
    private func export(_ fixture: [String: Any]) async throws -> [String: Any] {
        let work = root.appendingPathComponent(UUID().uuidString)
        let store = try JournalStore(directory: work.appendingPathComponent("library"), key: VaultCrypto.generateKey())
        try await self.store(try XCTUnwrap(fixture["records"] as? [[String: Any]]), in: store)
        for attachment in try XCTUnwrap(fixture["attachments"] as? [[String: Any]]) {
            let id = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(attachment["id"] as? String)))
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(attachment["base64"] as? String)))
            _ = try await store.addAttachment(bytes, id: id)
        }
        var values: [String: JSONValue?] = [:]
        for (journal, rank) in try XCTUnwrap(fixture["ranks"] as? [String: String]) {
            values["journal-rank/" + journal] = .string(rank)
        }
        for entry in try XCTUnwrap(fixture["pinned"] as? [String]) { values["pinned/" + entry] = .bool(true) }
        try await store.setLibraryValues(values)
        let folder = work.appendingPathComponent("Journal Markdown")
        let minutes = try XCTUnwrap(fixture["timeZoneOffsetMinutes"] as? Int)
        let summary = try await MarkdownExport.write(
            store: store, to: folder, timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: minutes * 60)))
        try await store.close()
        return try Self.listing(of: folder, summary: summary)
    }

    private static func listing(of folder: URL, summary: MarkdownExportSummary) throws -> [String: Any] {
        var text: [[String: Any]] = []
        var binary: [[String: Any]] = []
        var manifest: [String: Any] = [:]
        var directories: [String] = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        let prefix = folder.standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            let path = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            if url.hasDirectoryPath {
                directories.append(path)
                continue
            }
            let data = try Data(contentsOf: url)
            if path == MarkdownExport.manifestName {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                manifest = ["format": object["format"] as Any, "version": object["version"] as Any]
                XCTAssertNotNil(try? JournalCoding.date(from: object["exported"] as? String ?? ""))
            } else if path.hasSuffix(".md") {
                text.append(["path": path, "text": String(decoding: data, as: UTF8.self)])
            } else {
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                binary.append(["path": path, "bytes": data.count, "sha256": hash])
            }
        }
        let order: ([String: Any], [String: Any]) -> Bool = {
            Array(($0["path"] as? String ?? "").utf8).lexicographicallyPrecedes(
                Array(($1["path"] as? String ?? "").utf8))
        }
        let counts: [String: Int] = [
            "imagesNotDownloaded": summary.imagesNotDownloaded, "imagesUnreadable": summary.imagesUnreadable,
            "itemsUnreadable": summary.itemsUnreadable, "itemsWithOtherVersions": summary.itemsWithOtherVersions,
        ]
        return [
            "manifest": manifest,
            "directories": directories.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) },
            "files": text.sorted(by: order), "binaryFiles": binary.sorted(by: order), "summary": counts,
        ]
    }

    private static func inputs() -> [String: Any] {
        [
            "corpusVersion": 1,
            "purpose":
                "A whole library and the folder Export as Markdown writes for it (protocol/markdown-export.md). The library is given as record plaintexts, images and the library record's pins and journal order; the offset is the exporting device's. The manifest's date is left out. See README.md in this folder.",
            "timeZoneOffsetMinutes": ConformanceExportLibrary.offsetMinutes,
            "records": ConformanceExportLibrary.records.map {
                ["id": $0.id, "kind": $0.kind, "plaintext": $0.plaintext]
            },
            "attachments": ConformanceExportLibrary.attachments.map {
                ["id": $0.id, "note": $0.note, "base64": $0.bytes.base64EncodedString()]
            },
            "ranks": ConformanceExportLibrary.ranks, "pinned": ConformanceExportLibrary.pinned,
        ]
    }

    func testTheLibraryExportsToTheFixturesFolder() async throws {
        if Conformance.regenerating {
            var fixture = Self.inputs()
            fixture["expected"] = try await export(fixture)
            try Conformance.write(fixture, to: Self.path)
        }
        let fixture = try Conformance.object(Self.path)
        let actual = try await export(fixture)
        XCTAssertTrue(try Conformance.same(actual, try XCTUnwrap(fixture["expected"])))
    }

    /// What the contract says about the folder, whatever the details: nothing deleted or unreadable is exported,
    /// every image link resolves or is counted, and no two names in a folder are the same.
    func testTheFolderFollowsTheContract() throws {
        let fixture = try Conformance.object(Self.path)
        let expected = try XCTUnwrap(fixture["expected"] as? [String: Any])
        let files = try XCTUnwrap(expected["files"] as? [[String: Any]])
        let binary = Set(
            (try XCTUnwrap(expected["binaryFiles"] as? [[String: Any]])).compactMap { $0["path"] as? String })
        var names = Set<String>()
        for file in files {
            let path = try XCTUnwrap(file["path"] as? String)
            let text = try XCTUnwrap(file["text"] as? String)
            XCTAssertTrue(names.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted, path)
            XCTAssertTrue(text.hasPrefix("---\n"), path)
            XCTAssertFalse(text.contains("\r"), path)
            XCTAssertFalse(text.contains("Hidden."), "Entries of a deleted journal stay in Recently Deleted: \(path)")
            XCTAssertFalse(text.contains("Gone."), path)
            let folder = path.split(separator: "/").dropLast().joined(separator: "/")
            for link in text.components(separatedBy: "](attachments/").dropFirst() {
                let name = link.prefix { ![")", " ", ">"].contains($0) }
                let isMissing = name.hasPrefix(ConformanceExportLibrary.missingImage)
                let isBroken = name.hasPrefix(ConformanceExportLibrary.image(4))
                let exists = binary.contains(folder + "/attachments/" + name)
                XCTAssertTrue(exists || isMissing || isBroken, "\(path): \(name)")
            }
        }
        let summary = try XCTUnwrap(expected["summary"] as? [String: Int])
        XCTAssertEqual(summary["imagesNotDownloaded"], 1)
        XCTAssertEqual(summary["imagesUnreadable"], 1)
        XCTAssertEqual(summary["itemsUnreadable"], 1)
    }
}

extension JournalStore {
    /// Stores a record's plaintext sealed under this store's key, as a payload received from a server.
    func insertSynchronized(_ plaintext: Data, id uuid: UUID, kind: String) throws {
        let payload = try sealedPayload(plaintext, id: uuid, kind: kind)
        try db.write { db in
            try db.execute(
                sql: "INSERT INTO records(id,kind,payload,revision,dirty) VALUES (?,?,?,1,0)",
                arguments: [self.id(uuid), kind, payload])
        }
    }
}
