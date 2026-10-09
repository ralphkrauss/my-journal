import CJournalArchive
import CryptoKit
import Foundation

/// Writes the ZIP profile of protocol/archive.md: one disk, stored entries, general-purpose flags 0, the CRC-32 and sizes
/// in the local header (patched in once the data is written) and the central directory, a fixed 1980-01-01 time, no
/// permissions, and ZIP64 records whenever a size, an offset or the entry count needs them.
final class ZipWriter {
    struct Written {
        let sha256: String
        let bytes: UInt64
    }
    private struct Finished {
        let name: [UInt8]
        let crc32: UInt32
        let size: UInt64
        let offset: UInt64
        let zip64Sizes: Bool
    }
    private let output: OutputFile
    private let options: ArchiveOptions
    private var position: UInt64 = 0
    private var finished: [Finished] = []

    /// Creates `url`, which must not exist.
    init(creating url: URL, options: ArchiveOptions) throws {
        output = try OutputFile(creating: url)
        self.options = options
    }

    /// Streams `source` (a regular file, not a link) in as a stored entry. The file's size is read first and must still
    /// be that size at the end, or the entry is refused: a file that changes while it is archived is an error.
    func addFile(named name: String, from source: URL) throws -> Written {
        let descriptor = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0, (information.st_mode & S_IFMT) == S_IFREG,
            information.st_size >= 0
        else { throw JournalError.invalidData }
        let size = UInt64(information.st_size)
        var buffer = [UInt8](repeating: 0, count: options.chunkBytes)
        return try addEntry(named: name, size: size) { emit in
            var left = size
            while left > 0 {
                try Task.checkCancellation()
                let count = Int(min(UInt64(buffer.count), left))
                let received = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, count) }
                guard received > 0 else { throw JournalError.invalidData }
                try buffer.withUnsafeBytes { try emit(UnsafeRawBufferPointer(rebasing: $0[0..<received])) }
                left -= UInt64(received)
            }
            var extra: UInt8 = 0
            guard read(descriptor, &extra, 1) == 0 else { throw JournalError.invalidData }
        }
    }

    func addData(named name: String, _ data: Data) throws -> Written {
        try addEntry(named: name, size: UInt64(data.count)) { emit in
            try data.withUnsafeBytes { try emit($0) }
        }
    }

    /// Writes the central directory and the end records, then closes the file.
    func finish() throws {
        let directoryOffset = position
        for entry in finished {
            try write(centralHeader(for: entry))
        }
        let directorySize = position - directoryOffset
        let count = UInt64(finished.count)
        let needsZip64 =
            options.forceZip64 || count >= 0xFFFF || directoryOffset >= 0xFFFF_FFFF || directorySize >= 0xFFFF_FFFF
        if needsZip64 {
            var records = [UInt8]()
            let recordStart = position
            records += le32(ZipEndRecords.zip64Signature) + le64(44) + le16(20) + le16(45) + le32(0) + le32(0)
            records += le64(count) + le64(count) + le64(directorySize) + le64(directoryOffset)
            records += le32(ZipEndRecords.locatorSignature) + le32(0) + le64(recordStart) + le32(1)
            try write(records)
        }
        let saturated = options.forceZip64
        var end = le32(ZipEndRecords.signature) + le16(0) + le16(0)
        let shortCount = needsZip64 && (saturated || count >= 0xFFFF) ? 0xFFFF : UInt16(count)
        end += le16(shortCount) + le16(shortCount)
        end += le32(needsZip64 && (saturated || directorySize >= 0xFFFF_FFFF) ? 0xFFFF_FFFF : UInt32(directorySize))
        end += le32(needsZip64 && (saturated || directoryOffset >= 0xFFFF_FFFF) ? 0xFFFF_FFFF : UInt32(directoryOffset))
        end += le16(0)
        try write(end)
        try output.synchronize()
        try output.close()
    }

    func abandon() {
        try? output.close()
    }

    // MARK: Entries

    private func addEntry(
        named name: String, size: UInt64,
        stream: (_ emit: (UnsafeRawBufferPointer) throws -> Void) throws -> Void
    ) throws -> Written {
        let nameBytes = Array(name.utf8)
        let offset = position
        let zip64Sizes = options.forceZip64 || size >= 0xFFFF_FFFF
        try write(localHeader(name: nameBytes, size: size, zip64Sizes: zip64Sizes))
        var hash = SHA256()
        var crc: UInt32 = 0
        var written: UInt64 = 0
        try stream { bytes in
            guard let base = bytes.baseAddress, !bytes.isEmpty else { return }
            hash.update(bufferPointer: bytes)
            crc = journal_crc32(crc, base.assumingMemoryBound(to: UInt8.self), bytes.count)
            written += UInt64(bytes.count)
            try write(bytes)
        }
        guard written == size else { throw JournalError.invalidData }
        // The CRC-32 is the one local header field unknown until the data was read.
        try output.write(le32(crc), at: offset + 14)
        finished.append(Finished(name: nameBytes, crc32: crc, size: size, offset: offset, zip64Sizes: zip64Sizes))
        return Written(sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes: size)
    }

    private func localHeader(name: [UInt8], size: UInt64, zip64Sizes: Bool) -> [UInt8] {
        let extra = zip64Sizes ? le16(1) + le16(16) + le64(size) + le64(size) : []
        let sizeField = zip64Sizes ? UInt32(0xFFFF_FFFF) : UInt32(size)
        var header = le32(0x0403_4B50) + le16(zip64Sizes ? 45 : 20) + le16(0) + le16(0)
        header += le16(0) + le16(ArchiveLimits.dosDate) + le32(0) + le32(sizeField) + le32(sizeField)
        header += le16(UInt16(name.count)) + le16(UInt16(extra.count))
        return header + name + extra
    }

    private func centralHeader(for entry: Finished) -> [UInt8] {
        let offsetSaturated = options.forceZip64 || entry.offset >= 0xFFFF_FFFF
        var extra = [UInt8]()
        if entry.zip64Sizes { extra += le64(entry.size) + le64(entry.size) }
        if offsetSaturated { extra += le64(entry.offset) }
        if !extra.isEmpty { extra = le16(1) + le16(UInt16(extra.count)) + extra }
        let sizeField = entry.zip64Sizes ? UInt32(0xFFFF_FFFF) : UInt32(entry.size)
        var header = le32(0x0201_4B50) + le16(20) + le16(extra.isEmpty ? 20 : 45) + le16(0) + le16(0)
        header += le16(0) + le16(ArchiveLimits.dosDate) + le32(entry.crc32) + le32(sizeField) + le32(sizeField)
        header += le16(UInt16(entry.name.count)) + le16(UInt16(extra.count)) + le16(0) + le16(0) + le16(0) + le32(0)
        header += le32(offsetSaturated ? 0xFFFF_FFFF : UInt32(entry.offset))
        return header + entry.name + extra
    }

    private func write(_ bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { try write($0) }
    }

    private func write(_ bytes: UnsafeRawBufferPointer) throws {
        try output.write(bytes)
        position += UInt64(bytes.count)
    }
}

private func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
private func le32(_ value: UInt32) -> [UInt8] { le16(UInt16(value & 0xFFFF)) + le16(UInt16(value >> 16)) }
private func le64(_ value: UInt64) -> [UInt8] { le32(UInt32(value & 0xFFFF_FFFF)) + le32(UInt32(value >> 32)) }
