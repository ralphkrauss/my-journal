import Foundation

/// The file archive: one ZIP file with `journal.sqlite`, `attachments/<uuid>` and `archive.json`
/// (protocol/archive.md). Only libraries with a password have one, so its manifest is always sealed.
enum FileArchive {
    /// An image to archive: its lower-case UUID text and the library's own file.
    struct Image {
        let identifier: String
        let file: URL
    }

    // MARK: Writing

    /// Writes the library as a file archive at `destination`, which must not exist. Everything the call created is
    /// removed on failure or cancellation; a destination that already existed is never touched.
    static func export(
        store: JournalStore, recovery: RecoveryEnvelope, key: Data, to destination: URL, options: ArchiveOptions
    ) async throws {
        try Task.checkCancellation()
        try recovery.requireEncrypted()
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        try options.requireSpace(try await store.archiveBytesEstimate(), at: destination.deletingLastPathComponent())
        let snapshot = manager.temporaryDirectory.appendingPathComponent(
            "export-" + UUID().uuidString.lowercased() + ".sqlite")
        var createdArchive = false
        do {
            let identifiers = try await store.exportDatabase(to: snapshot)
            try Task.checkCancellation()
            let images = identifiers.sorted().map {
                Image(identifier: $0, file: store.directory.appendingPathComponent("attachments/\($0)"))
            }
            try write(
                databaseFile: snapshot, images: images, recovery: recovery, key: key, to: destination, options: options,
                created: { createdArchive = true })
            try? manager.removeItem(at: snapshot)
        } catch {
            try? manager.removeItem(at: snapshot)
            if createdArchive { try? manager.removeItem(at: destination) }
            throw error
        }
    }

    /// The container: the database, then each image in name order, then `archive.json` last, because it holds the
    /// manifest and the manifest needs every hash. `created` is called once the destination file exists, so the caller
    /// knows it owns it. The database file is deleted as soon as its entry is written.
    static func write(
        databaseFile: URL, images: [Image], recovery: RecoveryEnvelope, key: Data, to destination: URL,
        options: ArchiveOptions, created: () -> Void = {}
    ) throws {
        let writer = try ZipWriter(creating: destination, options: options)
        created()
        do {
            let database = try writer.addFile(named: ArchiveNames.database, from: databaseFile)
            try? FileManager.default.removeItem(at: databaseFile)
            var written: [String: ZipWriter.Written] = [:]
            for image in images.sorted(by: { $0.identifier < $1.identifier }) {
                guard ArchiveNames.isLowercaseUUID(image.identifier) else { throw JournalError.invalidData }
                let entry = try writer.addFile(
                    named: "\(ArchiveNames.attachmentsFolder)/\(image.identifier)", from: image.file)
                guard entry.bytes <= ArchiveLimits.imageBytes else { throw JournalError.invalidData }
                written[image.identifier] = entry
            }
            let sealed = try VaultCrypto.seal(
                manifestJSON(database: database, images: written), key: key,
                context: FileArchiveHeader.manifestContext)
            _ = try writer.addData(named: ArchiveNames.header, try headerJSON(recovery: recovery, sealed: sealed))
            try writer.finish()
        } catch {
            writer.abandon()
            throw error
        }
    }

    private static func manifestJSON(database: ZipWriter.Written, images: [String: ZipWriter.Written]) -> Data {
        let listed = images.keys.sorted().compactMap { identifier -> String? in
            guard let entry = images[identifier] else { return nil }
            return "\"\(identifier)\":{\"bytes\":\(entry.bytes),\"sha256\":\"\(entry.sha256)\"}"
        }
        let text =
            "{\"attachments\":{\(listed.joined(separator: ","))},"
            + "\"database\":{\"bytes\":\(database.bytes),\"sha256\":\"\(database.sha256)\"}}"
        return Data(text.utf8)
    }

    private struct HeaderOut: Encodable {
        let archiveVersion = FileArchiveHeader.archiveVersion
        let recovery: RecoveryEnvelope
        let manifest: Data
    }

    private static func headerJSON(recovery: RecoveryEnvelope, sealed: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(HeaderOut(recovery: recovery, manifest: sealed))
    }

    // MARK: Reading

    /// Reads the header: its bounds are checked, no password needed.
    static func checkHeader(at source: URL) throws {
        let container = try ArchiveContainer(at: source)
        _ = try FileArchiveHeader.parse(try container.headerData())
    }

    /// Recovers the key, authenticates the manifest, checks space, extracts the listed entries into a new
    /// `destination` and opens the database there. The destination is removed again if anything fails.
    static func restore(
        from source: URL, to destination: URL, phrase: String, options: ArchiveOptions
    ) async throws -> VaultArchive.Restored {
        try Task.checkCancellation()
        let container = try ArchiveContainer(at: source, options: options)
        let header = try FileArchiveHeader.parse(try container.headerData())
        let recovered = try VaultCrypto.recover(header.recovery, phrase: phrase)
        let manifest = try authenticatedManifest(header, key: recovered.0)
        let plan = try container.plan(for: manifest)
        let parent = destination.deletingLastPathComponent()
        // The staging copy and the install that follows (which writes the images again).
        try options.requireSpace(try plan.declaredBytes.multiplying(by: 2), at: parent)
        let manager = FileManager.default
        try StagingFolder.create(at: destination)
        do {
            try container.extract(plan, manifest: manifest, into: destination)
            try Task.checkCancellation()
            return try await ArchiveStaging.open(
                destination, key: recovered.0, recovery: header.recovery, options: options)
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    private static func authenticatedManifest(_ header: FileArchiveHeader, key: Data) throws -> ArchiveManifest {
        let bytes: Data
        do {
            bytes = try VaultCrypto.open(header.sealedManifest, key: key, context: FileArchiveHeader.manifestContext)
        } catch { throw JournalError.invalidData }
        return try ArchiveManifest.parse(bytes)
    }
}
