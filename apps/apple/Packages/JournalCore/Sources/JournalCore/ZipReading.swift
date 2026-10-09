import Foundation

/// A file opened once for reading at absolute offsets. A file archive is read through one descriptor, so what is
/// checked and what is extracted is the same file even if the name is replaced meanwhile.
final class ArchiveInput {
    let descriptor: Int32
    let size: UInt64

    init(path: String) throws {
        // Without O_NONBLOCK, opening a named pipe waits until something writes to it. The file is a regular one or
        // refused, and reads of a regular file are not affected by the flag, which is cleared again below.
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var information = stat()
        guard fstat(descriptor, &information) == 0 else {
            let failure = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(descriptor)
            throw failure
        }
        guard (information.st_mode & S_IFMT) == S_IFREG, information.st_size >= 0 else {
            close(descriptor)
            throw JournalError.invalidData
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
        self.descriptor = descriptor
        self.size = UInt64(information.st_size)
    }

    deinit { close(descriptor) }

    /// Exactly `count` bytes at `offset`; a file that ends first is damaged.
    func read(at offset: UInt64, count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        try bytes.withUnsafeMutableBytes { try read(at: offset, into: $0) }
        return bytes
    }

    func read(at offset: UInt64, into buffer: UnsafeMutableRawBufferPointer) throws {
        guard !buffer.isEmpty else { return }
        let end = try offset.adding(UInt64(buffer.count))
        guard end <= size, offset <= UInt64(Int64.max), let base = buffer.baseAddress else {
            throw JournalError.invalidData
        }
        var done = 0
        while done < buffer.count {
            let received = pread(descriptor, base + done, buffer.count - done, off_t(offset) + off_t(done))
            if received < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard received > 0 else { throw JournalError.invalidData }
            done += received
        }
    }
}

extension [UInt8] {
    func le16(_ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw JournalError.invalidData }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }
    func le32(_ offset: Int) throws -> UInt32 {
        UInt32(try le16(offset)) | UInt32(try le16(offset + 2)) << 16
    }
    func le64(_ offset: Int) throws -> UInt64 {
        UInt64(try le32(offset)) | UInt64(try le32(offset + 4)) << 32
    }
}

/// One entry of the central directory that the archive profile names (protocol/archive.md, ZIP profile).
struct ZipEntry {
    enum Role: Hashable {
        case header
        case database
        case attachment(String)

        /// The entry name, which a local header must repeat.
        var name: String {
            switch self {
            case .header: return ArchiveNames.header
            case .database: return ArchiveNames.database
            case .attachment(let identifier): return "\(ArchiveNames.attachmentsFolder)/\(identifier)"
            }
        }
    }
    let role: Role
    let flags: UInt16
    let method: UInt16
    let crc32: UInt32
    let compressedSize: UInt64
    let size: UInt64
    let localHeaderOffset: UInt64

    static let stored: UInt16 = 0
    static let deflated: UInt16 = 8
    /// Bit 0 (encrypted) and bit 6 (strong encryption).
    static let encryptionFlags: UInt16 = 1 << 0 | 1 << 6
    static let encryptedDirectoryFlag: UInt16 = 1 << 13
}

/// The end of a ZIP file: the ordinary end record and, when there is one, the ZIP64 records.
struct ZipEndRecords {
    let entryCount: UInt64
    let directorySize: UInt64
    let directoryOffset: UInt64
    /// Where the end records begin: the central directory must end exactly here.
    let boundary: UInt64

    static let signature: UInt32 = 0x0605_4B50
    static let zip64Signature: UInt32 = 0x0606_4B50
    static let locatorSignature: UInt32 = 0x0706_4B50
    static let fixedLength = 22
    static let maximumComment = 65_535

    /// The end record is the last `22 + commentLength` bytes of the file. Only candidates whose comment reaches the end
    /// of the file are considered, and a second one (a record forged inside a comment) refuses the file.
    static func locate(in input: ArchiveInput) throws -> ZipEndRecords {
        guard input.size >= UInt64(fixedLength) else { throw JournalError.invalidData }
        let tailLength = Int(min(input.size, UInt64(fixedLength + maximumComment)))
        let tailStart = input.size - UInt64(tailLength)
        let tail = try input.read(at: tailStart, count: tailLength)
        var candidates: [Int] = []
        var index = tailLength - fixedLength
        while index >= 0 {
            if try tail.le32(index) == signature, Int(try tail.le16(index + 20)) == tailLength - index - fixedLength {
                candidates.append(index)
            }
            index -= 1
        }
        guard candidates.count == 1, let found = candidates.first else { throw JournalError.invalidData }
        let recordStart = tailStart + UInt64(found)
        return try parse(Array(tail[found..<(found + fixedLength)]), at: recordStart, in: input)
    }

    private static func parse(_ record: [UInt8], at recordStart: UInt64, in input: ArchiveInput) throws -> ZipEndRecords
    {
        let disk = try record.le16(4)
        let directoryDisk = try record.le16(6)
        let entriesOnDisk = try record.le16(8)
        let entries = try record.le16(10)
        let size = try record.le32(12)
        let offset = try record.le32(16)
        if recordStart >= 20, try input.read(at: recordStart - 20, count: 4).le32(0) == locatorSignature {
            let zip64 = try readZip64(locatorAt: recordStart - 20, in: input)
            try requireAgreement(
                zip64, disk: disk, directoryDisk: directoryDisk, entriesOnDisk: entriesOnDisk, entries: entries,
                size: size, offset: offset)
            return try validated(zip64)
        }
        // Without ZIP64 records nothing may be saturated and the one disk is disk 0.
        guard disk == 0, directoryDisk == 0, entriesOnDisk == entries, entries != 0xFFFF, size != 0xFFFF_FFFF,
            offset != 0xFFFF_FFFF
        else { throw JournalError.invalidData }
        return try validated(
            ZipEndRecords(
                entryCount: UInt64(entries), directorySize: UInt64(size), directoryOffset: UInt64(offset),
                boundary: recordStart))
    }

    private static func readZip64(locatorAt locatorStart: UInt64, in input: ArchiveInput) throws -> ZipEndRecords {
        let locator = try input.read(at: locatorStart, count: 20)
        guard try locator.le32(4) == 0, try locator.le32(16) <= 1 else { throw JournalError.invalidData }
        let recordStart = try locator.le64(8)
        guard recordStart <= locatorStart, locatorStart - recordStart >= 56 else { throw JournalError.invalidData }
        let record = try input.read(at: recordStart, count: 56)
        guard try record.le32(0) == zip64Signature, try record.le64(4) >= 44 else { throw JournalError.invalidData }
        let recordEnd = try recordStart.adding(12).adding(try record.le64(4))
        guard recordEnd <= locatorStart, try record.le32(16) == 0, try record.le32(20) == 0 else {
            throw JournalError.invalidData
        }
        guard try record.le64(24) == record.le64(32) else { throw JournalError.invalidData }
        return ZipEndRecords(
            entryCount: try record.le64(32), directorySize: try record.le64(40), directoryOffset: try record.le64(48),
            boundary: recordStart)
    }

    /// Every field of the ordinary end record that is not saturated must equal the ZIP64 value.
    private static func requireAgreement(
        _ zip64: ZipEndRecords, disk: UInt16, directoryDisk: UInt16, entriesOnDisk: UInt16, entries: UInt16,
        size: UInt32, offset: UInt32
    ) throws {
        guard disk == 0 || disk == 0xFFFF, directoryDisk == 0 || directoryDisk == 0xFFFF else {
            throw JournalError.invalidData
        }
        let counts = [entriesOnDisk, entries]
        for count in counts where count != 0xFFFF {
            guard UInt64(count) == zip64.entryCount else { throw JournalError.invalidData }
        }
        guard size == 0xFFFF_FFFF || UInt64(size) == zip64.directorySize,
            offset == 0xFFFF_FFFF || UInt64(offset) == zip64.directoryOffset
        else { throw JournalError.invalidData }
    }

    private static func validated(_ records: ZipEndRecords) throws -> ZipEndRecords {
        guard records.directorySize <= ArchiveLimits.centralDirectoryBytes,
            records.entryCount <= ArchiveLimits.centralDirectoryEntries,
            try records.directoryOffset.adding(records.directorySize) == records.boundary,
            try records.entryCount.multiplying(by: 46) <= records.directorySize
        else { throw JournalError.invalidData }
        return records
    }
}

/// The entries the profile names, from a file's central directory. Every other entry is skipped as it streams past.
struct ZipDirectory {
    let fileSize: UInt64
    let directoryOffset: UInt64
    private(set) var header: ZipEntry?
    private(set) var database: ZipEntry?
    private(set) var attachments: [String: ZipEntry] = [:]

    private static let entrySignature: UInt32 = 0x0201_4B50
    private static let entryFixedLength = 46

    static func read(from input: ArchiveInput) throws -> ZipDirectory {
        let records = try ZipEndRecords.locate(in: input)
        var directory = ZipDirectory(fileSize: input.size, directoryOffset: records.directoryOffset)
        var cursor = DirectoryCursor(input: input, position: records.directoryOffset, end: records.boundary)
        for _ in 0..<records.entryCount {
            try Task.checkCancellation()
            try directory.readEntry(from: &cursor)
        }
        // The entry count must account for every byte of the directory.
        guard cursor.remaining == 0 else { throw JournalError.invalidData }
        return directory
    }

    private init(fileSize: UInt64, directoryOffset: UInt64) {
        self.fileSize = fileSize
        self.directoryOffset = directoryOffset
    }

    /// The entries that must have a data range, in no particular order.
    var all: [ZipEntry] {
        [header, database].compactMap { $0 } + attachments.values
    }

    private mutating func readEntry(from cursor: inout DirectoryCursor) throws {
        let fixed = try cursor.take(Self.entryFixedLength)
        guard try fixed.le32(0) == Self.entrySignature else { throw JournalError.invalidData }
        // Central directory encryption hides every entry's size and offset.
        guard try fixed.le16(8) & ZipEntry.encryptedDirectoryFlag == 0 else { throw JournalError.invalidData }
        let nameLength = Int(try fixed.le16(28))
        let extraLength = Int(try fixed.le16(30))
        let commentLength = Int(try fixed.le16(32))
        guard UInt64(nameLength + extraLength + commentLength) <= cursor.remaining else {
            throw JournalError.invalidData
        }
        let name = try cursor.take(nameLength)
        guard let role = Self.role(of: name) else {
            try cursor.skip(extraLength + commentLength)
            return
        }
        let extra = try cursor.take(extraLength)
        try cursor.skip(commentLength)
        try add(try Self.entry(role: role, fixed: fixed, extra: extra))
    }

    private mutating func add(_ entry: ZipEntry) throws {
        switch entry.role {
        case .header:
            guard header == nil else { throw JournalError.invalidData }
            header = entry
        case .database:
            guard database == nil else { throw JournalError.invalidData }
            database = entry
        case .attachment(let identifier):
            // A UUID-named entry is stored even if the manifest turns out not to list it: a duplicate refuses the
            // archive whatever the manifest says, so two readers can't disagree about which duplicate counts.
            guard attachments[identifier] == nil else { throw JournalError.invalidData }
            attachments[identifier] = entry
        }
    }

    /// Names are compared as bytes. A name that differs from a profile name by case, or holds NUL, a backslash or `..`,
    /// is just another name.
    private static func role(of name: [UInt8]) -> ZipEntry.Role? {
        if name == Array(ArchiveNames.header.utf8) { return .header }
        if name == Array(ArchiveNames.database.utf8) { return .database }
        let prefix = Array("\(ArchiveNames.attachmentsFolder)/".utf8)
        guard name.count == prefix.count + 36, name.starts(with: prefix) else { return nil }
        let identifier = name[prefix.count...]
        guard ArchiveNames.isLowercaseUUID(identifier) else { return nil }
        return .attachment(String(decoding: identifier, as: UTF8.self))
    }

    private static func entry(role: ZipEntry.Role, fixed: [UInt8], extra: [UInt8]) throws -> ZipEntry {
        var compressed = UInt64(try fixed.le32(20))
        var size = UInt64(try fixed.le32(24))
        var offset = UInt64(try fixed.le32(42))
        var disk = UInt64(try fixed.le16(34))
        let saturatedSizes = compressed == 0xFFFF_FFFF || size == 0xFFFF_FFFF
        if saturatedSizes || offset == 0xFFFF_FFFF || disk == 0xFFFF {
            // The ZIP64 field holds only the members whose 32-bit field is saturated, in this order.
            var members = try zip64Members(in: extra)
            if size == 0xFFFF_FFFF { size = try members.next(8) }
            if compressed == 0xFFFF_FFFF { compressed = try members.next(8) }
            if offset == 0xFFFF_FFFF { offset = try members.next(8) }
            if disk == 0xFFFF { disk = try members.next(4) }
        }
        guard disk == 0 else { throw JournalError.invalidData }
        return ZipEntry(
            role: role, flags: try fixed.le16(8), method: try fixed.le16(10), crc32: try fixed.le32(16),
            compressedSize: compressed, size: size, localHeaderOffset: offset)
    }

    /// The data of the ZIP64 extended information field (header ID 1) among the extra fields. Two of them are damage:
    /// readers disagree about which one counts. A field that runs past the end ends the search; it is damage only when
    /// the ZIP64 field was not found before it.
    private static func zip64Members(in extra: [UInt8]) throws -> ZipMembers {
        var position = 0
        var found: ZipMembers?
        while position + 4 <= extra.count {
            let identifier = try extra.le16(position)
            let length = Int(try extra.le16(position + 2))
            guard position + 4 + length <= extra.count else {
                // A broken field after the ZIP64 one is as unknown to this reader as any other field.
                if found != nil { break }
                throw JournalError.invalidData
            }
            if identifier == 1 {
                guard found == nil else { throw JournalError.invalidData }
                found = ZipMembers(bytes: Array(extra[(position + 4)..<(position + 4 + length)]))
            }
            position += 4 + length
        }
        guard let found else { throw JournalError.invalidData }
        return found
    }
}

/// Values read one after another from the ZIP64 extra field. A value that isn't there is damage.
private struct ZipMembers {
    let bytes: [UInt8]
    var position = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func next(_ width: Int) throws -> UInt64 {
        guard position + width <= bytes.count else { throw JournalError.invalidData }
        defer { position += width }
        return width == 8 ? try bytes.le64(position) : UInt64(try bytes.le32(position))
    }
}

/// Reads the central directory in order without holding more than a window of it.
private struct DirectoryCursor {
    let input: ArchiveInput
    var position: UInt64
    let end: UInt64
    private var window: [UInt8] = []
    private var windowStart: UInt64 = 0
    private static let windowBytes = 1 << 20

    init(input: ArchiveInput, position: UInt64, end: UInt64) {
        self.input = input
        self.position = position
        self.end = end
        self.windowStart = position
    }

    var remaining: UInt64 { end - position }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard UInt64(count) <= remaining else { throw JournalError.invalidData }
        if count == 0 { return [] }
        let windowEnd = windowStart + UInt64(window.count)
        if position < windowStart || position + UInt64(count) > windowEnd {
            let length = Int(min(remaining, UInt64(max(count, Self.windowBytes))))
            window = try input.read(at: position, count: length)
            windowStart = position
        }
        let from = Int(position - windowStart)
        position += UInt64(count)
        return Array(window[from..<(from + count)])
    }

    mutating func skip(_ count: Int) throws {
        guard UInt64(count) <= remaining else { throw JournalError.invalidData }
        position += UInt64(count)
    }
}
