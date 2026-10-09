import Foundation

/// The library archive (protocol/archive.md). Two kinds exist, told apart by what the picked item is:
///
/// - A **file archive**, one ZIP file, is what 1.1 writes (`exportFile`). Only libraries with a password have one.
/// - A **directory archive**, a folder, is what 1.0 wrote. It is only read: nothing writes one any more.
///
/// `restore` and `requiresPassword` read either kind.
public enum VaultArchive {
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
}
