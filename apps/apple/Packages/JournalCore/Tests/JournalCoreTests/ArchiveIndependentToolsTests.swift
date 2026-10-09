import XCTest

@testable import JournalCore

/// The writer's output is read by tools that share no code with it: a bug in the writer that the reader forgives would
/// show here (Tests/check-archive-with-tools.sh).
final class ArchiveIndependentToolsTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func setUp() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("check-archive-with-tools.sh")

    /// A database-sized file, an empty image, a small one and one larger than the chunk, so every kind of entry is there.
    private func write(_ name: String, options: ArchiveOptions) throws -> URL {
        let database = root.appendingPathComponent("\(name).sqlite")
        try Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) }).write(to: database)
        var images: [FileArchive.Image] = []
        for (identifier, size) in [
            ("fedcba98-7654-4321-8fed-cba987654321", 0), ("01234567-89ab-4cde-8fab-0123456789ab", 70),
            ("22222222-2222-4222-8222-222222222222", 700_000),
        ] {
            let file = root.appendingPathComponent("\(name)-\(identifier)")
            try Data(repeating: 0x5A, count: size).write(to: file)
            images.append(FileArchive.Image(identifier: identifier, file: file))
        }
        let key = try VaultCrypto.generateKey()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: "tools", formatVersion: 2).0
        let archive = root.appendingPathComponent("\(name).journalarchive")
        try FileArchive.write(
            databaseFile: database, images: images, recovery: recovery, key: key, to: archive, options: options)
        return archive
    }

    func testStandardToolsReadWhatTheWriterWrites() throws {
        var forced = ArchiveOptions.standard
        forced.forceZip64 = true
        var small = ArchiveOptions.standard
        small.chunkBytes = 1000
        let archives = [
            try write("plain", options: .standard), try write("zip64", options: forced),
            try write("chunks", options: small),
        ]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [Self.script.path] + archives.map(\.path)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, text)
    }
}
