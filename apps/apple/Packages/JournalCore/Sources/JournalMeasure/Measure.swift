import Darwin
import Foundation
import JournalCore

@main
struct Measure {
    static let entryCount = 3_650
    static let imageCount = 100
    static let imageBytes = 256 * 1_024
    static let body = String(repeating: "Daily work and reflection. ", count: 160)

    static func main() async throws {
        let arguments = CommandLine.arguments
        let commands = ["seed", "read", "seed-heavy", "seed-small", "heavy-store", "seed-screenshots"]
        guard arguments.count == 3, commands.contains(arguments[1]) else {
            throw MeasurementError.invalidArguments
        }
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        if arguments[1] == "seed-screenshots" {
            try await seedScreenshots(directory)
            return
        }
        let metrics: [String: Double]
        switch arguments[1] {
        case "seed": metrics = try await seed(directory)
        case "read": metrics = try await read(directory)
        case "seed-heavy", "seed-small":
            let started = ProcessInfo.processInfo.systemUptime
            var library = SyntheticLibrary(directory: directory)
            if arguments[1] == "seed-small" { library.shape = .small }
            let manifest = try await library.seed()
            metrics = [
                "seedSeconds": elapsed(started), "markdownBytes": Double(manifest.markdownBytes),
                "libraryPhotoBytes": Double(manifest.libraryPhotoBytes),
                "cameraPhotoBytes": Double(manifest.cameraPhotoBytes),
            ]
        default: metrics = try await HeavyStore.measure(directory)
        }
        let data = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func seed(_ directory: URL) async throws -> [String: Double] {
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw MeasurementError.existingFixture
        }
        let started = ProcessInfo.processInfo.systemUptime
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: directory, key: key)
        let keyFile = directory.appendingPathComponent("synthetic-key")
        try key.write(to: keyFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        let journal = JournalItem(kind: "journal", title: "Synthetic multi-year journal")
        try await store.save(journal)
        for index in 0..<entryCount {
            var blocks = JournalDocument.plain(body + "Entry index \(index).").blocks
            if index < imageCount {
                let bytes = Data(repeating: UInt8(index), count: imageBytes)
                let image = try await store.addAttachment(bytes)
                blocks.append(
                    DocumentBlock(
                        kind: "image", attachmentID: image, imageDescription: "Synthetic image \(index)",
                        mediaType: "image/png"))
            }
            let entry = JournalItem(
                kind: "entry", journalID: journal.id, title: "Day \(index)", document: .init(blocks: blocks))
            try await store.save(entry)
        }
        try await store.close()
        return ["seedSeconds": elapsed(started), "peakResidentBytes": try peakResidentBytes()]
    }

    /// Seeds the App Store screenshot library. The master password comes from the environment so it never
    /// appears in a command line; `JOURNAL_SCREENSHOT_HISTORY=0` leaves out the earlier versions;
    /// `JOURNAL_SCREENSHOT_FIXED_DATES=1` dates the templates 2026-08-29, not the day of seeding.
    static func seedScreenshots(_ directory: URL) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let password = environment["JOURNAL_SCREENSHOT_PASSWORD"],
            let photos = environment["JOURNAL_SCREENSHOT_PHOTOS"]
        else { throw MeasurementError.invalidArguments }
        let library = ScreenshotLibrary(
            directory: directory, photos: URL(fileURLWithPath: photos, isDirectory: true), password: password,
            includesHistory: environment["JOURNAL_SCREENSHOT_HISTORY"] != "0",
            fixedTemplateDate: environment["JOURNAL_SCREENSHOT_FIXED_DATES"] == "1")
        try await library.seed()
    }

    static func read(_ directory: URL) async throws -> [String: Double] {
        let key = try Data(contentsOf: directory.appendingPathComponent("synthetic-key"))
        let started = ProcessInfo.processInfo.systemUptime
        let store = try JournalStore(directory: directory, key: key)
        var metrics = ["openSeconds": elapsed(started)]
        let firstStart = ProcessInfo.processInfo.systemUptime
        let snapshot = try await store.viewSnapshot()
        metrics["firstSnapshotSeconds"] = elapsed(firstStart)
        guard snapshot.items.count == entryCount + 1, snapshot.conflictedIDs.isEmpty, snapshot.pending else {
            throw MeasurementError.contentMismatch
        }
        let searchStart = ProcessInfo.processInfo.systemUptime
        let results = snapshot.items.filter {
            $0.kind == "entry" && $0.document.text.localizedStandardContains("Entry index 1825.")
        }
        metrics["inMemoryBodySearchSeconds"] = elapsed(searchStart)
        guard results.count == 1, results.first?.title == "Day 1825" else {
            throw MeasurementError.contentMismatch
        }
        let refreshStart = ProcessInfo.processInfo.systemUptime
        let refreshed = try await store.viewSnapshot()
        metrics["secondSnapshotSeconds"] = elapsed(refreshStart)
        guard refreshed.items == snapshot.items else { throw MeasurementError.contentMismatch }
        metrics["peakResidentBeforeImagesBytes"] = try peakResidentBytes()
        let imageStart = ProcessInfo.processInfo.systemUptime
        var count = 0
        for entry in snapshot.items where entry.kind == "entry" {
            guard let index = Int(entry.title.replacingOccurrences(of: "Day ", with: "")) else {
                throw MeasurementError.contentMismatch
            }
            guard entry.document.blocks.first?.runs.first?.text == body + "Entry index \(index)." else {
                throw MeasurementError.contentMismatch
            }
            for block in entry.document.blocks where block.kind == "image" {
                guard let id = block.attachmentID else { throw MeasurementError.contentMismatch }
                let bytes = try await store.attachment(id)
                guard bytes == Data(repeating: UInt8(index), count: imageBytes) else {
                    throw MeasurementError.contentMismatch
                }
                count += 1
            }
        }
        guard count == imageCount else { throw MeasurementError.contentMismatch }
        metrics["verifyContentAndImagesSeconds"] = elapsed(imageStart)
        metrics["peakResidentBytes"] = try peakResidentBytes()
        try await store.close()
        return metrics
    }

    static func elapsed(_ start: Double) -> Double { ProcessInfo.processInfo.systemUptime - start }

    static func peakResidentBytes() throws -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw MeasurementError.resourceUnavailable }
        return Double(usage.ru_maxrss)
    }
}

enum MeasurementError: Error {
    case invalidArguments, existingFixture, contentMismatch, resourceUnavailable
}
