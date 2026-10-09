import CryptoKit
import XCTest

@testable import JournalCore

/// protocol/conformance/archive/v2/container-v2.json: archives that exercise the ZIP container layer of the file
/// archive. Each case gives the manifest the reader is handed; the reader must accept it and extract exactly the listed
/// entries, or refuse it in the stated message class (damaged or newer). The reasons in the notes are not compared.
final class ConformanceContainerTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The message class of an error, as protocol/archive.md (Failures) names them.
    static func outcome(of error: Error) -> String {
        switch error {
        case JournalError.invalidData: return "damaged"
        case JournalError.newerVersion, JournalError.unsupportedFormat: return "newer"
        case JournalError.invalidRecoveryKey: return "wrongPassword"
        default: return "couldntOpen"
        }
    }

    private struct Case: Decodable {
        let name: String
        let file: String
        let expect: String
        let manifestText: String?
        let manifest: ManifestObject?
        let parseHeader: Bool?
    }
    private struct ManifestObject: Decodable {
        struct Item: Decodable {
            let sha256: String
            let bytes: UInt64
        }
        let database: Item
        let attachments: [String: Item]
    }
    private struct Corpus: Decodable {
        let cases: [Case]
    }

    /// Reads the archive as the file archive reader does, without a password: header bounds, then the listed entries.
    private func read(_ item: Case, destination: URL) throws {
        let container = try ArchiveContainer(at: Conformance.url("archive/v2/" + item.file))
        let header = try container.headerData()
        if item.parseHeader == true { _ = try FileArchiveHeader.parse(header) }
        let text: String
        if let manifestText = item.manifestText {
            text = manifestText
        } else if let manifest = item.manifest {
            text = Self.json(manifest)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manifest = try ArchiveManifest.parse(Data(text.utf8))
        let plan = try container.plan(for: manifest)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try container.extract(plan, manifest: manifest, into: destination)
    }

    private static func json(_ manifest: ManifestObject) -> String {
        func item(_ value: ManifestObject.Item) -> String {
            "{\"sha256\":\"\(value.sha256)\",\"bytes\":\(value.bytes)}"
        }
        let images = manifest.attachments.keys.sorted().map {
            "\"\($0)\":\(item(manifest.attachments[$0] ?? manifest.database))"
        }
        return "{\"database\":\(item(manifest.database)),\"attachments\":{\(images.joined(separator: ","))}}"
    }

    func testEveryContainerCaseGivesTheStatedOutcome() throws {
        let corpus = try Conformance.decode(Corpus.self, "archive/v2/container-v2.json")
        XCTAssertGreaterThan(corpus.cases.count, 90)
        var failures: [String] = []
        for (index, item) in corpus.cases.enumerated() {
            let destination = root.appendingPathComponent("case-\(index)")
            do {
                try read(item, destination: destination)
                if item.expect != "accept" { failures.append("\(item.name): accepted, expected \(item.expect)") }
            } catch {
                let outcome = Self.outcome(of: error)
                if outcome != item.expect {
                    failures.append("\(item.name): \(outcome) (\(error)), expected \(item.expect)")
                }
            }
        }
        XCTAssertEqual(failures, [])
    }

    /// An accepted case extracts the listed entries to files named from the validated UUIDs, with the manifest's bytes,
    /// and nothing else (unlisted entries never reach the disk).
    func testAcceptedCasesExtractExactlyTheListedEntries() throws {
        let corpus = try Conformance.decode(Corpus.self, "archive/v2/container-v2.json")
        let accepted = corpus.cases.filter { $0.expect == "accept" && $0.parseHeader != true && $0.manifest != nil }
        XCTAssertGreaterThan(accepted.count, 20)
        for (index, item) in accepted.enumerated() {
            let destination = root.appendingPathComponent("accepted-\(index)")
            try read(item, destination: destination)
            let manifest = try XCTUnwrap(item.manifest)
            let names = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
            XCTAssertEqual(names, ["attachments", "journal.sqlite"], item.name)
            let images = try FileManager.default.contentsOfDirectory(
                atPath: destination.appendingPathComponent("attachments").path)
            XCTAssertEqual(images.sorted(), manifest.attachments.keys.sorted(), item.name)
            let database = try Data(contentsOf: destination.appendingPathComponent("journal.sqlite"))
            XCTAssertEqual(UInt64(database.count), manifest.database.bytes, item.name)
            XCTAssertEqual(
                SHA256.hash(data: database).map { String(format: "%02x", $0) }.joined(), manifest.database.sha256,
                item.name)
        }
    }

    /// A deflate stream that expands past its declared size is stopped at that size: the surplus never reaches the disk.
    func testADeflateBombIsStoppedAtTheDeclaredSize() throws {
        let corpus = try Conformance.decode(Corpus.self, "archive/v2/container-v2.json")
        let item = try XCTUnwrap(corpus.cases.first { $0.name == "deflate-expands-past-declared-size" })
        let destination = root.appendingPathComponent("bomb")
        XCTAssertThrowsError(try read(item, destination: destination))
        let image = destination.appendingPathComponent("attachments/01234567-89ab-4cde-8fab-0123456789ab")
        let size = (try? FileManager.default.attributesOfItem(atPath: image.path)[.size] as? Int) ?? 0
        XCTAssertLessThanOrEqual(size, 60)
    }
}
