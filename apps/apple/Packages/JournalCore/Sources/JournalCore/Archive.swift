import CryptoKit
import Foundation

/// The library archive (protocol/archive.md). Two kinds exist, told apart by what the picked item is:
///
/// - A **file archive**, one ZIP file, is what 1.1 writes (`exportFile`). Only libraries with a password have one.
/// - A **directory archive**, a folder, is what 1.0 wrote. It is still read, and `export` still writes one until the
///   app switches to `exportFile`; the directory writer is removed with that switch.
///
/// `restore` and `requiresPassword` read either kind.
public enum VaultArchive {
    private struct Header: Codable {
        var version = 1
        let recovery: RecoveryEnvelope
        let manifest: Data
    }
    private struct Manifest: Codable {
        let database: String
        let attachments: [String: String]
    }
    public struct Restored: Sendable {
        public let store: JournalStore
        public let key: Data
        public let recovery: RecoveryEnvelope
    }
    private enum Kind { case directory, file }

    // MARK: File archive

    /// Writes the library as a file archive at `destination`, a new file. The staged file is the only thing
    /// created besides a temporary copy of the database, and both are removed if the export fails or is cancelled.
    public static func exportFile(store: JournalStore, recovery: RecoveryEnvelope, key: Data, to destination: URL)
        async throws
    {
        try await FileArchive.export(
            store: store, recovery: recovery, key: key, to: destination, options: .standard)
    }

    // MARK: Reading either kind

    public static func restore(from source: URL, to destination: URL, phrase: String) async throws -> Restored {
        try await restore(from: source, to: destination, phrase: phrase, options: .standard)
    }

    static func restore(from source: URL, to destination: URL, phrase: String, options: ArchiveOptions) async throws
        -> Restored
    {
        let (kind, resolved) = try identify(source)
        switch kind {
        case .directory:
            return try await DirectoryArchive.restore(from: resolved, to: destination, phrase: phrase, options: options)
        case .file:
            return try await FileArchive.restore(from: resolved, to: destination, phrase: phrase, options: options)
        }
    }

    public static func requiresPassword(at source: URL) throws -> Bool {
        let (kind, resolved) = try identify(source)
        switch kind {
        case .directory: return try DirectoryArchive.requiresPassword(at: resolved)
        case .file: return try FileArchive.requiresPassword(at: resolved)
        }
    }

    /// A directory is a directory archive and a regular file is a file archive. There is no sniffing by name. The item
    /// the person picked is followed if it is a link; nothing inside a directory archive is.
    private static func identify(_ source: URL) throws -> (Kind, URL) {
        let resolved = source.resolvingSymlinksInPath()
        var information = stat()
        guard stat(resolved.path, &information) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        switch information.st_mode & S_IFMT {
        case S_IFDIR: return (.directory, resolved)
        case S_IFREG: return (.file, resolved)
        default: throw JournalError.invalidData
        }
    }

    // MARK: Directory archive writer (kept until the app exports file archives)

    public static func export(store: JournalStore, recovery: RecoveryEnvelope, key: Data, to destination: URL)
        async throws
    {
        try Task.checkCancellation()
        guard try store.protection == recovery.contentProtection else { throw JournalError.invalidData }
        try await store.snapshot(to: destination, requireComplete: true)
        // snapshot owns its own failures; only a successful new snapshot transfers ownership here.
        do {
            let manifest = try inventory(destination)
            let encoded = try JournalCoding.encoder().encode(manifest)
            let sealed =
                recovery.requiresPassword
                ? try VaultCrypto.seal(encoded, key: key, context: "journal:v1:archive") : encoded
            let header = Header(version: recovery.requiresPassword ? 1 : 2, recovery: recovery, manifest: sealed)
            try JournalCoding.encoder().encode(header).write(
                to: destination.appendingPathComponent("archive.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func inventory(_ directory: URL) throws -> Manifest {
        let images = directory.appendingPathComponent("attachments", isDirectory: true)
        let imageProperties = try images.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard imageProperties.isDirectory == true, imageProperties.isSymbolicLink != true else {
            throw JournalError.invalidData
        }
        var files: [URL] = []
        for file in try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil) {
            let name = file.lastPathComponent
            // System files such as .DS_Store or AppleDouble "._" files appear when a package is copied between
            // volumes. They are never part of an archive: only listed files are copied and verified.
            if name.hasPrefix(".") { continue }
            guard ArchiveNames.isLowercaseUUID(name) else { throw JournalError.invalidData }
            files.append(file)
        }
        // A few files are read at once, which storage serves faster than one after another.
        let digests = try Parallel.map(files, width: 4, cancellableEvery: 16) { file in
            (file.lastPathComponent, try digest(file))
        }
        let hashes = Dictionary(digests, uniquingKeysWith: { first, _ in first })
        return Manifest(database: try digest(directory.appendingPathComponent("journal.sqlite")), attachments: hashes)
    }
    private static func digest(_ file: URL) throws -> String {
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else {
            throw JournalError.invalidData
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let bytes = try handle.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            digest.update(data: bytes)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
