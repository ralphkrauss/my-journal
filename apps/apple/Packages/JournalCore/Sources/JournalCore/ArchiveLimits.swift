import Foundation

/// A file or directory archive can't be read or written because the volume is too full. The app words it as the
/// "not enough space" messages; everything else that goes wrong with hostile or damaged input is
/// `JournalError.invalidData`.
public enum ArchiveError: Error, Equatable, Sendable {
    case notEnoughSpace
}

/// What a reader enforces on any archive (protocol/archive.md, Limits). A limit hit is reported as damaged.
enum ArchiveLimits {
    /// `archive.json`, in both archive kinds.
    static let headerBytes: UInt64 = 16 * 1024 * 1024
    static let centralDirectoryBytes: UInt64 = 64 * 1024 * 1024
    static let centralDirectoryEntries: UInt64 = 300_000
    /// The largest image file, encrypted; the server accepts no larger upload.
    static let imageBytes = UInt64(JournalStore.maximumAttachmentBytes)
    static let databaseBytes: UInt64 = 32 << 30
    /// An entry may not declare more than this many times its compressed size.
    static let expansionFactor: UInt64 = 8
    /// The sum of the declared sizes of a database and its images.
    static let totalBytes: UInt64 = 1 << 40
    static let chunkBytes = 256 * 1024
    /// Free space that must remain beyond what a restore or an export writes.
    static let spaceReserve: UInt64 = 256 * 1024 * 1024
    /// The number of nested JSON containers a header or manifest may have.
    static let jsonDepth = 32
    /// ZIP stores times as DOS date and time; every entry is stamped 1980-01-01 00:00:00.
    static let dosDate: UInt16 = 0x0021
}

/// Parameters of the container code that tests vary. The app always uses `standard`.
struct ArchiveOptions: Sendable {
    /// Bytes read and written at a time.
    var chunkBytes = ArchiveLimits.chunkBytes
    /// Writes every size, offset and count in its ZIP64 form even when it would fit in 32 bits.
    var forceZip64 = false
    /// Free space on the volume that holds a path.
    var availableSpace: @Sendable (URL) throws -> UInt64 = { try ArchiveOptions.systemAvailableSpace(at: $0) }

    static let standard = ArchiveOptions()

    static func systemAvailableSpace(at url: URL) throws -> UInt64 {
        var folder = url
        let manager = FileManager.default
        while !manager.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder.deleteLastPathComponent()
        }
        let values = try folder.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return UInt64(important) }
        return UInt64(max(0, values.volumeAvailableCapacity ?? 0))
    }

    /// Throws `ArchiveError.notEnoughSpace` unless `needed` bytes plus the reserve are free where `url` is.
    func requireSpace(_ needed: UInt64, at url: URL) throws {
        let (total, overflow) = needed.addingReportingOverflow(ArchiveLimits.spaceReserve)
        guard !overflow else { throw JournalError.invalidData }
        guard try availableSpace(url) >= total else { throw ArchiveError.notEnoughSpace }
    }
}

extension ArchiveOptions {
    init(availableSpace: @escaping @Sendable (URL) throws -> UInt64) {
        self.init()
        self.availableSpace = availableSpace
    }
}

extension UInt64 {
    /// Arithmetic on sizes and offsets read from a file: an overflow means the file is damaged, never a crash.
    func adding(_ other: UInt64) throws -> UInt64 {
        let (value, overflow) = addingReportingOverflow(other)
        guard !overflow else { throw JournalError.invalidData }
        return value
    }
    func multiplying(by other: UInt64) throws -> UInt64 {
        let (value, overflow) = multipliedReportingOverflow(by: other)
        guard !overflow else { throw JournalError.invalidData }
        return value
    }
    func subtracting(_ other: UInt64) throws -> UInt64 {
        let (value, overflow) = subtractingReportingOverflow(other)
        guard !overflow else { throw JournalError.invalidData }
        return value
    }
    func asInt() throws -> Int {
        guard let value = Int(exactly: self) else { throw JournalError.invalidData }
        return value
    }
}

enum ArchiveNames {
    static let header = "archive.json"
    static let database = "journal.sqlite"
    static let attachmentsFolder = "attachments"

    /// A lower-case UUID exactly as `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`. Parsing and
    /// lower-casing is not the same: UUID parsers accept braces, missing hyphens and capitals.
    static func isLowercaseUUID<Bytes: Collection>(_ bytes: Bytes) -> Bool where Bytes.Element == UInt8 {
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard byte == 0x2D else { return false }
            } else {
                guard (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte) else { return false }
            }
        }
        return true
    }
    static func isLowercaseUUID(_ text: String) -> Bool { isLowercaseUUID(Array(text.utf8)) }

    /// A SHA-256 digest as lower-case hex.
    static func isHexDigest(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.count == 64 && bytes.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
