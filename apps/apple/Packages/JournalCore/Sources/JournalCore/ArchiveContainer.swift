import Foundation

/// What the sealed manifest of a file archive lists: `journal.sqlite` and every image, with SHA-256 and exact sizes.
struct ArchiveManifest {
    struct File: Equatable {
        let sha256: String
        let bytes: UInt64
    }
    let database: File
    let attachments: [String: File]

    /// Unknown members are ignored so the manifest can grow; a repeated member, a key that is not a lower-case UUID, a
    /// hash that is not lower-case hex and a size that is not a plain integer up to 2^53 - 1 are damage.
    static func parse(_ data: Data) throws -> ArchiveManifest {
        let parsed = try StrictJSON.parse(
            data, keeping: ["database", "attachments"], maximumValues: ArchiveLimits.manifestJSONValues)
        guard let root = parsed.object, let database = root["database"]?.object,
            let images = root["attachments"]?.object
        else { throw JournalError.invalidData }
        var attachments: [String: File] = [:]
        for (key, value) in images {
            guard ArchiveNames.isLowercaseUUID(key.bytes) else { throw JournalError.invalidData }
            attachments[key.text] = try file(value.object)
        }
        return ArchiveManifest(database: try file(database), attachments: attachments)
    }

    private static func file(_ members: [ArchiveJSONKey: ArchiveJSONValue]?) throws -> File {
        guard let members, let hash = members["sha256"]?.string, ArchiveNames.isHexDigest(hash),
            let text = members["bytes"]?.number, let bytes = ArchiveJSONValue.exactSize(text)
        else { throw JournalError.invalidData }
        return File(sha256: hash, bytes: bytes)
    }

    var declaredBytes: UInt64 {
        get throws {
            try attachments.values.reduce(database.bytes) { try $0.adding($1.bytes) }
        }
    }
}

/// `archive.json` of a file archive. Everything here is checked before a password is asked for.
struct FileArchiveHeader {
    let recovery: RecoveryEnvelope
    /// The sealed manifest: AES-256-GCM combined bytes, under the vault key and `journal:v2:archive`.
    let sealedManifest: Data

    static let archiveVersion: UInt64 = 2
    /// The context the manifest is sealed under: `journal:v{archiveVersion}:archive`, so a later version's manifest
    /// can't be passed off as this one's.
    static let manifestContext = "journal:v2:archive"

    static func parse(_ data: Data) throws -> FileArchiveHeader {
        let parsed = try StrictJSON.parse(
            data, keeping: ["archiveVersion", "recovery", "manifest"], maximumValues: ArchiveLimits.headerJSONValues)
        guard let root = parsed.object, let versionText = root["archiveVersion"]?.number,
            let version = ArchiveJSONValue.exactSize(versionText)
        else { throw JournalError.invalidData }
        guard version <= archiveVersion else { throw JournalError.newerVersion }
        guard version == archiveVersion, let recovery = root["recovery"]?.object,
            let manifest = root["manifest"]?.string, let sealed = Data(base64Encoded: manifest)
        else { throw JournalError.invalidData }
        return FileArchiveHeader(recovery: try envelope(recovery), sealedManifest: sealed)
    }

    /// The bounds are the CPU limit before a password is typed: a 16-byte salt, 100,000 to 2,000,000 iterations and
    /// recovery format 1 or 2. A file archive is always encrypted, so formats 3 and 4 are damage here.
    private static func envelope(_ members: [ArchiveJSONKey: ArchiveJSONValue]) throws -> RecoveryEnvelope {
        guard let salt = members["salt"]?.string, Data(base64Encoded: salt)?.count == 16,
            let wrapped = members["wrappedKey"]?.string, Data(base64Encoded: wrapped) != nil,
            let iterationsText = members["iterations"]?.number,
            let iterations = ArchiveJSONValue.exactSize(iterationsText),
            (100_000...2_000_000).contains(iterations),
            let formatText = members["formatVersion"]?.number, let format = ArchiveJSONValue.exactSize(formatText),
            format == 1 || format == 2
        else { throw JournalError.invalidData }
        return RecoveryEnvelope(
            salt: salt, wrappedKey: wrapped, iterations: Int(iterations), formatVersion: Int(format))
    }
}

/// A file archive's ZIP container, opened once: the end records and the central directory have been read, and
/// nothing proportional to the library has.
final class ArchiveContainer {
    /// The reader's order (protocol/archive.md, Reading a file archive) is: `init`, `headerData`, `plan`, `extract`.
    struct Plan {
        let ranges: [ZipDataRange]
        let declaredBytes: UInt64
    }
    private let input: ArchiveInput
    private let directory: ZipDirectory
    private let options: ArchiveOptions

    init(at url: URL, options: ArchiveOptions = .standard) throws {
        input = try ArchiveInput(path: url.path)
        directory = try ZipDirectory.read(from: input)
        self.options = options
    }

    /// `archive.json`, after its size limit, expansion limit and CRC-32 were checked.
    func headerData() throws -> Data {
        guard let entry = directory.header, entry.size <= ArchiveLimits.headerBytes else {
            throw JournalError.invalidData
        }
        let range = try directory.range(of: entry, in: input)
        var data = Data()
        data.reserveCapacity(try entry.size.asInt())
        _ = try ZipExtractor.extract(range, from: input, options: options) { data.append(contentsOf: $0) }
        return data
    }

    /// Checks the listed entries against the manifest and the data ranges against each other, before anything is
    /// written. A listed entry that is missing, differs in size, or cannot be read is damage.
    func plan(for manifest: ArchiveManifest) throws -> Plan {
        guard manifest.database.bytes <= ArchiveLimits.databaseBytes,
            let databaseEntry = directory.database, databaseEntry.size == manifest.database.bytes
        else { throw JournalError.invalidData }
        var listed = [databaseEntry]
        for identifier in manifest.attachments.keys.sorted() {
            guard let file = manifest.attachments[identifier], file.bytes <= ArchiveLimits.imageBytes,
                let entry = directory.attachments[identifier], entry.size == file.bytes
            else { throw JournalError.invalidData }
            listed.append(entry)
        }
        let declared = try manifest.declaredBytes
        guard declared <= ArchiveLimits.totalBytes, let header = directory.header else {
            throw JournalError.invalidData
        }
        var ranges: [ZipDataRange] = []
        for entry in listed + [header] {
            try Task.checkCancellation()
            try entry.requireReadable()
            ranges.append(try directory.range(of: entry, in: input))
        }
        try ZipDirectory.requireDisjoint(ranges)
        // The header is read like the others but is not extracted to disk.
        return Plan(ranges: Array(ranges.dropLast()), declaredBytes: declared)
    }

    /// Writes `journal.sqlite` and `attachments/<uuid>` into `destination`, which exists and is owned by the caller.
    /// File names come from the UUIDs the reader validated, never from entry names. Each file is hashed as it is
    /// written and must match the manifest.
    func extract(_ plan: Plan, manifest: ArchiveManifest, into destination: URL) throws {
        let images = destination.appendingPathComponent(ArchiveNames.attachmentsFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        var written: UInt64 = 0
        for range in plan.ranges {
            let expected: ArchiveManifest.File
            let target: URL
            switch range.entry.role {
            case .database:
                expected = manifest.database
                target = destination.appendingPathComponent(ArchiveNames.database)
            case .attachment(let identifier):
                guard let file = manifest.attachments[identifier] else { throw JournalError.invalidData }
                expected = file
                target = images.appendingPathComponent(identifier)
            case .header: throw JournalError.invalidData
            }
            let output = try OutputFile(creating: target)
            let extraction = try ZipExtractor.extract(range, from: input, options: options) { chunk in
                try output.write(chunk)
                written += UInt64(chunk.count)
                options.didExtract?(written)
            }
            try output.close()
            guard extraction.sha256 == expected.sha256 else { throw JournalError.invalidData }
        }
    }
}

/// The new folder a restore extracts into. It is created without its parents and an existing folder is an error, so a
/// folder that is already there, or appears between a check and this call, is never taken for the restore's own and
/// removed when the restore fails.
enum StagingFolder {
    static func create(at url: URL) throws {
        guard mkdir(url.path, 0o700) == 0 else {
            if errno == EEXIST { throw JournalError.invalidData }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

/// A new file written in chunks. It is created exclusively, readable only by the owner.
final class OutputFile {
    private var descriptor: Int32

    init(creating url: URL) throws {
        descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        guard let base = bytes.baseAddress else { return }
        var done = 0
        while done < bytes.count {
            let written = Darwin.write(descriptor, base + done, bytes.count - done)
            if written < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            done += written
        }
    }

    func write(_ data: Data) throws {
        try data.withUnsafeBytes { try write($0) }
    }

    /// Writes `bytes` at an earlier position, for a field that is only known after the data (the CRC-32).
    func write(_ bytes: [UInt8], at offset: UInt64) throws {
        let written = bytes.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, off_t(offset)) }
        guard written == bytes.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    func synchronize() throws {
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    func close() throws {
        guard descriptor >= 0 else { return }
        let result = Darwin.close(descriptor)
        descriptor = -1
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
