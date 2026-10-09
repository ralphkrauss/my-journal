import CryptoKit
import Foundation

/// The directory archive that version 1.0 writes and later versions still read: `archive.json`, `journal.sqlite` and
/// `attachments/<uuid>` in a folder (protocol/archive.md, Directory archive). Its manifest is plain for a library without a
/// password, so a folder anyone hands over is hostile input: the reader applies the limits of a file archive, never
/// follows a link, and builds every path from a UUID it checked.
enum DirectoryArchive {
    struct Header {
        let version: UInt64
        let recovery: RecoveryEnvelope
        let manifest: Data
    }
    /// SHA-256 digests in lower-case hex.
    struct Manifest {
        let database: String
        let attachments: [String: String]
    }

    // MARK: Header

    static func readHeader(in source: URL) throws -> Header {
        let data = try readSmallFile(
            source.appendingPathComponent(ArchiveNames.header), limit: ArchiveLimits.headerBytes)
        let parsed = try StrictJSON.parse(
            data, keeping: ["archiveVersion", "version", "recovery", "manifest"],
            maximumValues: ArchiveLimits.headerJSONValues)
        guard let root = parsed.object else { throw JournalError.invalidData }
        // A folder that holds an unpacked file archive is not a directory archive.
        guard root["archiveVersion"] == nil else { throw JournalError.invalidData }
        guard let versionText = root["version"]?.number, let version = ArchiveJSONValue.exactSize(versionText),
            let recovery = root["recovery"]?.object, let manifest = root["manifest"]?.string,
            let sealed = Data(base64Encoded: manifest)
        else { throw JournalError.invalidData }
        let envelope = try envelope(recovery)
        guard version == (envelope.requiresPassword ? 1 : 2) else { throw JournalError.unsupportedFormat }
        _ = try envelope.contentProtection
        return Header(version: version, recovery: envelope, manifest: sealed)
    }

    private static func envelope(_ members: [ArchiveJSONKey: ArchiveJSONValue]) throws -> RecoveryEnvelope {
        guard let salt = members["salt"]?.string, let wrapped = members["wrappedKey"]?.string,
            let iterationsText = members["iterations"]?.number,
            let iterations = ArchiveJSONValue.exactSize(iterationsText),
            let formatText = members["formatVersion"]?.number, let format = ArchiveJSONValue.exactSize(formatText),
            iterations <= UInt64(Int32.max), format <= UInt64(Int32.max)
        else { throw JournalError.invalidData }
        return RecoveryEnvelope(
            salt: salt, wrappedKey: wrapped, iterations: Int(iterations), formatVersion: Int(format))
    }

    static func requiresPassword(at source: URL) throws -> Bool {
        try readHeader(in: source).recovery.requiresPassword
    }

    /// The manifest, whose keys become file names: every key must be a lower-case UUID before any file operation, since
    /// a plain manifest is unauthenticated and a name such as `../x` must not reach outside the staging folder.
    static func parseManifest(_ data: Data) throws -> Manifest {
        let parsed = try StrictJSON.parse(
            data, keeping: ["database", "attachments"], maximumValues: ArchiveLimits.manifestJSONValues)
        guard let root = parsed.object, let database = root["database"]?.string,
            ArchiveNames.isHexDigest(database), let listed = root["attachments"]?.object
        else { throw JournalError.invalidData }
        var attachments: [String: String] = [:]
        for (key, value) in listed {
            guard ArchiveNames.isLowercaseUUID(key.bytes), let digest = value.string, ArchiveNames.isHexDigest(digest)
            else { throw JournalError.invalidData }
            attachments[key.text] = digest
        }
        return Manifest(database: database, attachments: attachments)
    }

    // MARK: Restoring

    static func restore(
        from source: URL, to destination: URL, phrase: String, options: ArchiveOptions
    ) async throws -> VaultArchive.Restored {
        try Task.checkCancellation()
        let header = try readHeader(in: source)
        let recovered =
            header.recovery.requiresPassword
            ? try VaultCrypto.recover(header.recovery, phrase: phrase) : (try VaultCrypto.generateKey(), "")
        let manifestBytes: Data
        if header.recovery.requiresPassword {
            do {
                manifestBytes = try VaultCrypto.open(header.manifest, key: recovered.0, context: "journal:v1:archive")
            } catch { throw JournalError.invalidData }
        } else {
            manifestBytes = header.manifest
        }
        let manifest = try parseManifest(manifestBytes)
        let total = try measure(manifest, in: source)
        try options.requireSpace(try total.multiplying(by: 2), at: destination.deletingLastPathComponent())
        let manager = FileManager.default
        try StagingFolder.create(at: destination)
        do {
            try copy(manifest, from: source, to: destination, options: options)
            try Task.checkCancellation()
            return try await ArchiveStaging.open(
                destination, key: recovered.0, recovery: header.recovery,
                protection: header.recovery.contentProtection, options: options)
        } catch {
            // Only this newly created directory is owned by the failed restore.
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    /// The sizes of the files the manifest lists, from the folder as it is now: each must be a regular file, not a link,
    /// within the limits of a file archive. Nothing is written yet.
    private static func measure(_ manifest: Manifest, in source: URL) throws -> UInt64 {
        let database = try regularFileSize(source.appendingPathComponent(ArchiveNames.database))
        guard database <= ArchiveLimits.databaseBytes else { throw JournalError.invalidData }
        var total = database
        if !manifest.attachments.isEmpty {
            // The reader reads through this folder, so it must itself be a folder and not a link to one.
            let folder = source.appendingPathComponent(ArchiveNames.attachmentsFolder, isDirectory: true)
            try requireFolder(folder)
            for identifier in manifest.attachments.keys {
                try Task.checkCancellation()
                let size = try regularFileSize(folder.appendingPathComponent(identifier))
                guard size <= ArchiveLimits.imageBytes else { throw JournalError.invalidData }
                total = try total.adding(size)
            }
        }
        guard total <= ArchiveLimits.totalBytes else { throw JournalError.invalidData }
        return total
    }

    /// Copies each listed file once, hashing the bytes as they are written; the copy is what gets committed, even if the
    /// source changes meanwhile.
    private static func copy(
        _ manifest: Manifest, from source: URL, to destination: URL, options: ArchiveOptions
    ) throws {
        try copyFile(
            from: source.appendingPathComponent(ArchiveNames.database),
            to: destination.appendingPathComponent(ArchiveNames.database), limit: ArchiveLimits.databaseBytes,
            expecting: manifest.database, chunk: options.chunkBytes)
        let images = destination.appendingPathComponent(ArchiveNames.attachmentsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        for identifier in manifest.attachments.keys.sorted() {
            guard let digest = manifest.attachments[identifier] else { throw JournalError.invalidData }
            try copyFile(
                from: source.appendingPathComponent("\(ArchiveNames.attachmentsFolder)/\(identifier)"),
                to: images.appendingPathComponent(identifier), limit: ArchiveLimits.imageBytes, expecting: digest,
                chunk: options.chunkBytes)
        }
    }

    private static func copyFile(from source: URL, to target: URL, limit: UInt64, expecting digest: String, chunk: Int)
        throws
    {
        // O_NONBLOCK: a named pipe put in the file's place would otherwise hold the open until something writes to it.
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0, (information.st_mode & S_IFMT) == S_IFREG,
            information.st_size >= 0, UInt64(information.st_size) <= limit
        else { throw JournalError.invalidData }
        let output = try OutputFile(creating: target)
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: chunk)
        var copied: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let received = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if received < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if received == 0 { break }
            // Never more than the limit, whatever the file claimed to be when it was opened.
            copied += UInt64(received)
            guard copied <= limit else { throw JournalError.invalidData }
            try buffer.withUnsafeBytes {
                let bytes = UnsafeRawBufferPointer(rebasing: $0[0..<received])
                hash.update(bufferPointer: bytes)
                try output.write(bytes)
            }
        }
        try output.close()
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else {
            throw JournalError.invalidData
        }
    }

    // MARK: Files and folders

    private static func regularFileSize(_ file: URL) throws -> UInt64 {
        var information = stat()
        guard lstat(file.path, &information) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard (information.st_mode & S_IFMT) == S_IFREG, information.st_size >= 0 else {
            throw JournalError.invalidData
        }
        return UInt64(information.st_size)
    }

    private static func requireFolder(_ folder: URL) throws {
        var information = stat()
        guard lstat(folder.path, &information) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard (information.st_mode & S_IFMT) == S_IFDIR else { throw JournalError.invalidData }
    }

    private static func readSmallFile(_ file: URL, limit: UInt64) throws -> Data {
        let size = try regularFileSize(file)
        guard size > 0, size <= limit else { throw JournalError.invalidData }
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        // What was checked by name may have been replaced since.
        var information = stat()
        guard fstat(descriptor, &information) == 0, (information.st_mode & S_IFMT) == S_IFREG else {
            throw JournalError.invalidData
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let received = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if received < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if received == 0 { return data }
            data.append(contentsOf: buffer[0..<received])
            guard UInt64(data.count) <= limit else { throw JournalError.invalidData }
        }
    }
}
