import XCTest

@testable import JournalCore

/// The reader parses files other people hand over. These tests change every byte of tiny archives, cut them at every
/// length and push the limits, and assert only what must hold for any input: the reader ends, answers either
/// "accepted" or "damaged" (never another error, never a crash), and what it accepts is what the manifest lists.
final class ArchiveSweepTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private struct Corpus: Decodable {
        struct Case: Decodable {
            let name: String
            let file: String
            let manifest: ManifestText?
        }
        struct ManifestText: Decodable {
            struct Item: Decodable {
                let sha256: String
                let bytes: UInt64
            }
            let database: Item
            let attachments: [String: Item]
        }
        let cases: [Case]
    }

    /// Reads the whole container layer with the case's manifest. Throws what the reader throws.
    private func read(_ archive: URL, manifest: Corpus.ManifestText, into destination: URL) throws {
        let container = try ArchiveContainer(at: archive)
        _ = try container.headerData()
        let images = manifest.attachments.keys.sorted().map { identifier -> String in
            let item = manifest.attachments[identifier] ?? manifest.database
            return "\"\(identifier)\":{\"sha256\":\"\(item.sha256)\",\"bytes\":\(item.bytes)}"
        }
        let text =
            "{\"database\":{\"sha256\":\"\(manifest.database.sha256)\",\"bytes\":\(manifest.database.bytes)},"
            + "\"attachments\":{\(images.joined(separator: ","))}}"
        let parsed = try ArchiveManifest.parse(Data(text.utf8))
        let plan = try container.plan(for: parsed)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try container.extract(plan, manifest: parsed, into: destination)
    }

    private func bases() throws -> [(String, Corpus.ManifestText)] {
        let corpus = try Conformance.decode(Corpus.self, "archive/v2/container-v2.json")
        return try ["stored", "deflated", "data-descriptors", "zip64-small", "unlisted-noise"].map { name in
            let item = try XCTUnwrap(corpus.cases.first { $0.name == name })
            return (item.file, try XCTUnwrap(item.manifest))
        }
    }

    private func requireCleanOutcome(_ archive: URL, manifest: Corpus.ManifestText, label: String) {
        let destination = root.appendingPathComponent("sweep")
        defer { try? FileManager.default.removeItem(at: destination) }
        do {
            try read(archive, manifest: manifest, into: destination)
        } catch JournalError.invalidData {
        } catch {
            XCTFail("\(label): \(error)")
        }
    }

    /// The offsets of the bytes inside entries' data, other than their first and last: a change there can only be seen
    /// by the CRC-32 and the hash, which the first and last byte exercise as well.
    private func interiorOfData(_ archive: URL) throws -> Set<Int> {
        let input = try ArchiveInput(path: archive.path)
        let directory = try ZipDirectory.read(from: input)
        var interior = Set<Int>()
        for entry in directory.all {
            let range = try directory.range(of: entry, in: input)
            let start = Int(range.dataOffset)
            let end = Int(range.end)
            if end - start > 2 { interior.formUnion(Set((start + 1)..<(end - 1))) }
        }
        return interior
    }

    /// Every byte of the local headers, the central directory and the end records, and the ends of the data, changed in
    /// turn in the same file.
    func testChangingAnyByteEndsInAcceptanceOrDamage() throws {
        for (file, manifest) in try bases() {
            let mutated = root.appendingPathComponent("mutated.zip")
            try? FileManager.default.removeItem(at: mutated)
            try FileManager.default.copyItem(at: Conformance.url("archive/v2/" + file), to: mutated)
            let skipped = try interiorOfData(mutated)
            let handle = try FileHandle(forUpdating: mutated)
            defer { try? handle.close() }
            let size = Int(try handle.seekToEnd())
            for index in 0..<size where !skipped.contains(index) {
                try handle.seek(toOffset: UInt64(index))
                let byte = try XCTUnwrap(try handle.read(upToCount: 1))
                try handle.seek(toOffset: UInt64(index))
                try handle.write(contentsOf: Data([byte[0] ^ 0xFF]))
                requireCleanOutcome(mutated, manifest: manifest, label: "\(file) byte \(index)")
                try handle.seek(toOffset: UInt64(index))
                try handle.write(contentsOf: byte)
            }
        }
    }

    func testCuttingAnArchiveAtAnyLengthEndsInDamage() throws {
        for (file, manifest) in try bases() {
            let original = try Conformance.data("archive/v2/" + file)
            let cut = root.appendingPathComponent("cut.zip")
            for length in 0..<original.count {
                try original.prefix(length).write(to: cut)
                let destination = root.appendingPathComponent("cut-out")
                defer { try? FileManager.default.removeItem(at: destination) }
                XCTAssertThrowsError(try read(cut, manifest: manifest, into: destination), "\(file) cut at \(length)") {
                    XCTAssertEqual(
                        ConformanceContainerTests.outcome(of: $0), "damaged", "\(file) cut at \(length): \($0)")
                }
            }
        }
    }

    /// Changing a byte of the opaque header is not the container's business; the header parser is, and it must not
    /// trap on any change either.
    func testChangingAnyByteOfTheHeaderEndsInAcceptanceOrAnError() throws {
        let archive = try ArchiveContainer(at: Conformance.url("archive/v2/container/header-valid.zip"))
        let header = try archive.headerData()
        for index in 0..<header.count {
            var bytes = header
            bytes[index] ^= 0xFF
            do {
                _ = try FileArchiveHeader.parse(bytes)
            } catch JournalError.invalidData {
            } catch JournalError.newerVersion {
            } catch {
                XCTFail("byte \(index): \(error)")
            }
        }
        for length in 0..<header.count {
            XCTAssertThrowsError(try FileArchiveHeader.parse(header.prefix(length)), "cut at \(length)")
        }
    }

    func testRandomTextIsNeverTakenForJSON() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let bytes = Data(
                (0..<Int.random(in: 0..<80, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator)
                })
            _ = try? StrictJSON.parse(bytes)
        }
        let deep = Data(String(repeating: "[", count: 5000).utf8)
        XCTAssertThrowsError(try StrictJSON.parse(deep))
    }

    /// A restore can be cancelled while it extracts: the next chunk is not read.
    func testCancellationStopsAnExtractionBetweenChunks() async throws {
        let url = Conformance.url("archive/v2/container/stored.zip")
        let task = Task { () throws -> Int in
            let input = try ArchiveInput(path: url.path)
            let directory = try ZipDirectory.read(from: input)
            let entry = try XCTUnwrap(directory.database)
            var options = ArchiveOptions.standard
            options.chunkBytes = 16
            var chunks = 0
            _ = try ZipExtractor.extract(try directory.range(of: entry, in: input), from: input, options: options) {
                _ in
                chunks += 1
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return chunks
        }
        do {
            let chunks = try await task.value
            XCTFail("Extraction went on after cancellation (\(chunks) chunks)")
        } catch is CancellationError {}
    }

    // MARK: Limits

    private func sparseArchive(size: UInt64, directoryOffset: UInt64, directorySize: UInt64, count: UInt16) throws
        -> URL
    {
        let url = root.appendingPathComponent("sparse-\(size).zip")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: size)
        var record = Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0])
        for value in [count, count] { record.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)]) }
        for value in [UInt32(directorySize), UInt32(directoryOffset)] {
            record.append(contentsOf: (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) })
        }
        record.append(contentsOf: [0, 0])
        try handle.seek(toOffset: size - 22)
        try handle.write(contentsOf: record)
        return url
    }

    /// The central directory may be at most 64 MiB: this one is consistent in every other way (a sparse file of zeros
    /// whose end record is right), and is refused without reading it.
    func testACentralDirectoryAbove64MiBIsRefusedUnread() throws {
        let directorySize: UInt64 = 64 * 1024 * 1024 + 1
        let size = directorySize + 22 + 100
        let url = try sparseArchive(size: size, directoryOffset: 100, directorySize: directorySize, count: 3)
        XCTAssertThrowsError(try ArchiveContainer(at: url)) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }

    private func little(_ value: UInt64, _ width: Int) -> [UInt8] {
        (0..<width).map { UInt8((value >> (8 * UInt64($0))) & 0xFF) }
    }

    /// A ZIP64 archive that is only a central directory of `count` entries named "n".
    private func directoryOfManyEntries(count: Int) throws -> URL {
        var entry = Data([0x50, 0x4B, 0x01, 0x02])
        entry.append(Data(count: 24))
        entry.append(contentsOf: [1, 0])
        entry.append(Data(count: 16))
        entry.append(UInt8(ascii: "n"))
        let size = UInt64(entry.count * count)
        var archive = Data(capacity: Int(size) + 100)
        for _ in 0..<count { archive.append(entry) }
        archive.append(contentsOf: [0x50, 0x4B, 0x06, 0x06] + little(44, 8) + little(0x2D_002D, 4) + little(0, 8))
        archive.append(contentsOf: little(UInt64(count), 8) + little(UInt64(count), 8) + little(size, 8) + little(0, 8))
        archive.append(contentsOf: [0x50, 0x4B, 0x06, 0x07] + little(0, 4) + little(size, 8) + little(1, 4))
        archive.append(contentsOf: [0x50, 0x4B, 0x05, 0x06] + little(0, 4) + [0xFF, 0xFF, 0xFF, 0xFF])
        archive.append(contentsOf: little(size, 4) + little(0, 4) + little(0, 2))
        let url = root.appendingPathComponent("many-\(count).zip")
        try archive.write(to: url)
        return url
    }

    /// 300,000 entries fit; 300,001 are refused. Names the profile doesn't know are skipped, never stored.
    func testTheEntryCountLimit() throws {
        let input = try ArchiveInput(path: try directoryOfManyEntries(count: 300_000).path)
        let directory = try ZipDirectory.read(from: input)
        XCTAssertNil(directory.header)
        XCTAssertTrue(directory.attachments.isEmpty)
        XCTAssertThrowsError(
            try ZipDirectory.read(from: try ArchiveInput(path: try directoryOfManyEntries(count: 300_001).path))
        ) {
            XCTAssertEqual(ConformanceContainerTests.outcome(of: $0), "damaged")
        }
    }
}
