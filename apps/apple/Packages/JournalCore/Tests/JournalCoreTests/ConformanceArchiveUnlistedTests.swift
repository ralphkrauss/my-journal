import XCTest

@testable import JournalCore

/// protocol/conformance/archive/v1/unlisted-files-v1.json: what a reader of the directory archive does with files the
/// manifest does not list (it ignores them), and the hostile folders it refuses without following a link, creating a
/// file outside the restore, or reading past the limits (protocol/archive.md, Reading an archive).
final class ConformanceArchiveUnlistedTests: XCTestCase {
    private static let path = "archive/v1/unlisted-files-v1.json"
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private static let image = "attachments/01234567-89ab-4cde-8fab-0123456789ab"

    private static var mutations: [[String: Any]] {
        [
            [
                "name": "unlisted-non-uuid-file", "note": "A file in attachments/ whose name is not a UUID is ignored.",
                "ops": [["op": "add", "file": "attachments/notes.txt", "text": "hello"]], "result": "restores",
            ],
            [
                "name": "unlisted-uuid-file",
                "note": "A UUID-named image the manifest does not list is ignored: only listed files are read.",
                "ops": [
                    [
                        "op": "add", "file": "attachments/11111111-2222-4333-8444-555555555555",
                        "text": "not in the manifest",
                    ]
                ], "result": "restores",
            ],
            [
                "name": "unlisted-upper-case-uuid-file",
                "note": "An upper-case UUID name is just another unlisted name.",
                "ops": [
                    ["op": "add", "file": "attachments/11111111-2222-4333-8444-ABCDEFABCDEF", "text": "ignored"]
                ], "result": "restores",
            ],
            [
                "name": "unlisted-directory-in-attachments", "note": "A folder in attachments/ is ignored.",
                "ops": [["op": "add", "file": "attachments/Thumbs/readme.txt", "text": "ignored"]],
                "result": "restores",
            ],
            [
                "name": "link-in-place-of-database", "note": "journal.sqlite is a link: never followed.",
                "ops": [
                    [
                        "op": "symlink", "file": "journal.sqlite",
                        "target": "attachments/" + "01234567-89ab-4cde-8fab-0123456789ab",
                    ]
                ],
                "result": "damaged",
            ],
            [
                "name": "link-in-place-of-listed-image", "note": "A listed image is a link: never followed.",
                "ops": [["op": "symlink", "file": image, "target": "journal.sqlite"]], "result": "damaged",
            ],
            [
                "name": "link-in-place-of-attachments-folder",
                "note": "attachments/ is a link to a folder: never followed.",
                "ops": [["op": "symlinkFolder", "file": "attachments", "target": "attachments-elsewhere"]],
                "result": "damaged",
            ],
            [
                "name": "sparse-database-above-limit",
                "note": "journal.sqlite of 33 GiB (a sparse file): refused before it is copied.",
                "ops": [["op": "sparse", "file": "journal.sqlite", "bytes": 33 * 1024 * 1024 * 1024]],
                "result": "damaged",
            ],
            [
                "name": "sparse-image-above-limit",
                "note": "A listed image of 26 MiB (a sparse file): refused before it is copied.",
                "ops": [["op": "sparse", "file": image, "bytes": 26 * 1024 * 1024]], "result": "damaged",
            ],
        ]
    }

    /// Folders whose header is plain JSON, written by hand: refused without creating anything.
    private static var packages: [[String: Any]] {
        [
            [
                "name": "manifest-names-a-file-outside",
                "note":
                    "A header of version 2 (no password) whose readable manifest lists the name ../x: refused before any file is created, inside or outside the restore.",
                "directory": "hostile/manifest-traversal", "result": "damaged",
            ],
            [
                "name": "unpacked-file-archive",
                "note":
                    "A folder holding an unpacked file archive (archive.json with archiveVersion): not a directory archive.",
                "directory": "hostile/unpacked-file-archive", "result": "damaged",
            ],
        ]
    }

    // MARK: Hand-written packages

    private static func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    private static let zeros = String(repeating: "0", count: 64)

    private static func plainHeader(manifest: String) -> String {
        "{\"manifest\":\"\(base64(manifest))\",\"recovery\":{\"formatVersion\":4,\"iterations\":0,\"salt\":\"\",\"wrappedKey\":\"\"},\"version\":2}\n"
    }

    private static var packageFiles: [String: String] {
        [
            "hostile/manifest-traversal/archive.json": plainHeader(
                manifest: "{\"attachments\":{\"../x\":\"\(zeros)\"},\"database\":\"\(zeros)\"}"),
            "hostile/unpacked-file-archive/archive.json":
                "{\"archiveVersion\":2,\"manifest\":\"\(base64("sealed"))\",\"recovery\":{\"formatVersion\":2,\"iterations\":600000,\"salt\":\"AQIDBAUGBwgJCgsMDQ4PEA==\",\"wrappedKey\":\"AAAA\"}}\n",
        ]
    }

    private func fixture() throws -> [String: Any] {
        try Conformance.fixture(Self.path) {
            for (path, text) in Self.packageFiles {
                let url = Conformance.url("archive/v1/" + path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            return [
                "corpusVersion": 1,
                "purpose":
                    "What the directory archive reader does with files the manifest does not list, and the hostile folders it refuses (protocol/archive.md). The mutations apply to a copy of encrypted/ in expected.json's archive; the packages are folders in this directory. See README.md.",
                "passwordSource": "expected.json, archives.encrypted.password",
                "mutations": Self.mutations, "packages": Self.packages,
                "operations":
                    "add: write a file (creating folders) with the text; symlink: replace a file with a link to target (relative to the package); symlinkFolder: replace a folder with a link to a new empty folder target; sparse: replace a file with a sparse file of that many bytes; delete: remove a file.",
            ]
        }
    }

    // MARK: Harness

    private func apply(_ operations: [[String: Any]], to directory: URL) throws {
        let manager = FileManager.default
        for operation in operations {
            let kind = try XCTUnwrap(operation["op"] as? String)
            let file = directory.appendingPathComponent(try XCTUnwrap(operation["file"] as? String))
            switch kind {
            case "add":
                try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(try XCTUnwrap(operation["text"] as? String).utf8).write(to: file)
            case "delete": try manager.removeItem(at: file)
            case "symlink":
                try? manager.removeItem(at: file)
                let target = directory.appendingPathComponent(try XCTUnwrap(operation["target"] as? String))
                try manager.createSymbolicLink(at: file, withDestinationURL: target)
            case "symlinkFolder":
                let target = directory.appendingPathComponent(try XCTUnwrap(operation["target"] as? String))
                try manager.moveItem(at: file, to: target)
                try manager.createSymbolicLink(at: file, withDestinationURL: target)
            case "sparse":
                try? manager.removeItem(at: file)
                XCTAssertTrue(manager.createFile(atPath: file.path, contents: nil))
                let handle = try FileHandle(forWritingTo: file)
                try handle.truncate(atOffset: UInt64(try XCTUnwrap(operation["bytes"] as? Int)))
                try handle.close()
            default: XCTFail("Unknown operation \(kind)")
            }
        }
    }

    private func password() throws -> String {
        let expected = try Conformance.object("archive/v1/expected.json")
        let archives = try XCTUnwrap(expected["archives"] as? [String: Any])
        return try XCTUnwrap((archives["encrypted"] as? [String: Any])?["password"] as? String)
    }

    func testUnlistedFilesAreIgnoredAndHostileFoldersRefused() async throws {
        let fixture = try fixture()
        let phrase = try password()
        let mutations = try XCTUnwrap(fixture["mutations"] as? [[String: Any]])
        for (index, mutation) in mutations.enumerated() {
            let name = try XCTUnwrap(mutation["name"] as? String)
            let copy = root.appendingPathComponent("mutated-\(index)")
            try FileManager.default.copyItem(at: Conformance.url("archive/v1/encrypted"), to: copy)
            try apply(try XCTUnwrap(mutation["ops"] as? [[String: Any]]), to: copy)
            let destination = root.appendingPathComponent("restored-\(index)")
            do {
                let restored = try await VaultArchive.restore(from: copy, to: destination, phrase: phrase)
                try await restored.store.close()
                XCTAssertEqual(mutation["result"] as? String, "restores", name)
            } catch {
                XCTAssertEqual(
                    ConformanceContainerTests.outcome(of: error), mutation["result"] as? String, "\(name): \(error)")
                XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), name)
            }
        }
    }

    /// A name such as ../x is refused before any file operation: nothing is created in the restore's folder or beside it.
    func testHostilePackagesAreRefusedBeforeAnythingIsCreated() async throws {
        let fixture = try fixture()
        let packages = try XCTUnwrap(fixture["packages"] as? [[String: Any]])
        for (index, package) in packages.enumerated() {
            let name = try XCTUnwrap(package["name"] as? String)
            let source = Conformance.url("archive/v1/" + (try XCTUnwrap(package["directory"] as? String)))
            let workplace = root.appendingPathComponent("work-\(index)")
            let destination = workplace.appendingPathComponent("restore/inside")
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                _ = try await VaultArchive.restore(from: source, to: destination, phrase: "")
                XCTFail("\(name) must be refused")
            } catch {
                XCTAssertEqual(ConformanceContainerTests.outcome(of: error), package["result"] as? String, name)
            }
            let created = FileManager.default.enumerator(atPath: workplace.path)?.allObjects as? [String] ?? []
            XCTAssertEqual(created.sorted(), ["restore"], name)
        }
    }
}
