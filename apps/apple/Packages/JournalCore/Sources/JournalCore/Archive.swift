import CryptoKit
import Foundation

/// A directory package containing a SQLite snapshot and original image files.
/// Encrypted libraries authenticate the inventory; passwordless libraries use readable checksums.
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

    public static func restore(from source: URL, to destination: URL, phrase: String) async throws -> Restored {
        try Task.checkCancellation()
        let headerURL = source.appendingPathComponent("archive.json")
        try regularFile(headerURL)
        let headerSize = try headerURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard headerSize > 0, headerSize <= 16 * 1024 * 1024 else { throw JournalError.invalidData }
        let header = try JournalCoding.decoder().decode(Header.self, from: Data(contentsOf: headerURL))
        guard header.version == (header.recovery.requiresPassword ? 1 : 2) else { throw JournalError.unsupportedFormat }
        _ = try header.recovery.contentProtection
        let recovered =
            header.recovery.requiresPassword
            ? try VaultCrypto.recover(header.recovery, phrase: phrase) : (try VaultCrypto.generateKey(), "")
        let bytes =
            header.recovery.requiresPassword
            ? try VaultCrypto.open(header.manifest, key: recovered.0, context: "journal:v1:archive") : header.manifest
        let manifest = try JournalCoding.decoder().decode(Manifest.self, from: bytes)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw JournalError.invalidData }
        try manager.createDirectory(
            at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var stagedStore: JournalStore?
        do {
            try manager.copyItem(
                at: source.appendingPathComponent("journal.sqlite"),
                to: destination.appendingPathComponent("journal.sqlite"))
            let images = destination.appendingPathComponent("attachments", isDirectory: true)
            try manager.createDirectory(at: images, withIntermediateDirectories: true)
            for identifier in manifest.attachments.keys {
                try manager.copyItem(
                    at: source.appendingPathComponent("attachments/\(identifier)"),
                    to: images.appendingPathComponent(identifier))
            }
            // The copied bytes are verified, not the source's: the copy is what is committed, even if the source changes
            // meanwhile, and reading every image twice would double the time a large archive takes.
            try verify(destination, against: manifest)
            let store = try JournalStore(
                directory: destination, key: recovered.0, protection: header.recovery.contentProtection)
            stagedStore = store
            try await store.validateSchema()
            try await store.validateSnapshot()
            try Task.checkCancellation()
            return Restored(store: store, key: recovered.0, recovery: header.recovery)
        } catch {
            // Only this newly created directory is owned by the failed restore.
            try? await stagedStore?.close()
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    public static func requiresPassword(at source: URL) throws -> Bool {
        let file = source.appendingPathComponent("archive.json")
        try regularFile(file)
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else {
            throw JournalError.invalidData
        }
        let header = try JournalCoding.decoder().decode(Header.self, from: Data(contentsOf: file))
        _ = try header.recovery.contentProtection
        guard header.version == (header.recovery.requiresPassword ? 1 : 2) else { throw JournalError.unsupportedFormat }
        return header.recovery.requiresPassword
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
            guard let identifier = UUID(uuidString: name), identifier.uuidString.lowercased() == name else {
                throw JournalError.invalidData
            }
            files.append(file)
        }
        // A few files are read at once, which storage serves faster than one after another.
        let digests = try Parallel.map(files, width: 4, cancellableEvery: 16) { file in
            (file.lastPathComponent, try digest(file))
        }
        let hashes = Dictionary(digests, uniquingKeysWith: { first, _ in first })
        return Manifest(database: try digest(directory.appendingPathComponent("journal.sqlite")), attachments: hashes)
    }
    private static func verify(_ directory: URL, against expected: Manifest) throws {
        let actual = try inventory(directory)
        guard actual.database == expected.database, actual.attachments == expected.attachments else {
            throw JournalError.invalidData
        }
    }
    private static func regularFile(_ file: URL) throws {
        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true else {
            throw JournalError.invalidData
        }
    }
    private static func digest(_ file: URL) throws -> String {
        try regularFile(file)
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
