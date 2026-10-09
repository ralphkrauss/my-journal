import CJournalArchive
import CryptoKit
import Foundation

/// Where an entry's bytes are: its local header checked against the central directory.
struct ZipDataRange {
    let entry: ZipEntry
    let dataOffset: UInt64
    /// The local header's first byte and the end of the entry's data, which no other entry may overlap.
    let start: UInt64
    let end: UInt64
}

extension ZipDirectory {
    private static let localSignature: UInt32 = 0x0403_4B50
    private static let localFixedLength = 30

    /// Checks an entry's local header: the signature, the name and the method must agree with the central directory.
    /// The local header's sizes and CRC-32 are never used, whether or not flag bit 3 is set: some writers fill them,
    /// some leave them zero and some saturate them. The data starts after the local header's own name and extra field.
    func range(of entry: ZipEntry, in input: ArchiveInput) throws -> ZipDataRange {
        let start = entry.localHeaderOffset
        let fixedEnd = try start.adding(UInt64(Self.localFixedLength))
        guard fixedEnd <= directoryOffset else { throw JournalError.invalidData }
        let fixed = try input.read(at: start, count: Self.localFixedLength)
        guard try fixed.le32(0) == Self.localSignature, try fixed.le16(8) == entry.method else {
            throw JournalError.invalidData
        }
        let name = Array(entry.role.name.utf8)
        let nameLength = Int(try fixed.le16(26))
        guard nameLength == name.count, try input.read(at: fixedEnd, count: nameLength) == name else {
            throw JournalError.invalidData
        }
        let dataOffset = try fixedEnd.adding(UInt64(nameLength)).adding(UInt64(try fixed.le16(28)))
        let end = try dataOffset.adding(entry.compressedSize)
        guard end <= directoryOffset else { throw JournalError.invalidData }
        return ZipDataRange(entry: entry, dataOffset: dataOffset, start: start, end: end)
    }

    /// No two data ranges (header and listed entries) may overlap each other; each already ends before the directory.
    static func requireDisjoint(_ ranges: [ZipDataRange]) throws {
        let ordered = ranges.sorted { $0.start < $1.start }
        var previousEnd: UInt64 = 0
        for range in ordered {
            guard range.start >= previousEnd else { throw JournalError.invalidData }
            previousEnd = range.end
        }
    }
}

extension ZipEntry {
    /// Whether this entry can be read: not encrypted, stored or deflated, with sizes that fit the method and the
    /// expansion limit. Entries that are not listed are never asked.
    func requireReadable() throws {
        guard flags & Self.encryptionFlags == 0, method == Self.stored || method == Self.deflated else {
            throw JournalError.invalidData
        }
        if method == Self.stored {
            guard compressedSize == size else { throw JournalError.invalidData }
        } else {
            guard compressedSize > 0, size <= (try compressedSize.multiplying(by: ArchiveLimits.expansionFactor)) else {
                throw JournalError.invalidData
            }
        }
    }
}

/// What reading an entry produced besides its bytes, which went to the caller's sink.
struct ZipExtraction {
    /// SHA-256 of the bytes read, lower-case hex. The caller compares it with the manifest, after the CRC-32 and the
    /// byte count (which `extract` checked already).
    let sha256: String
}

enum ZipExtractor {
    /// Reads the entry's bytes in chunks, inflating a deflated entry, never producing more than the declared size.
    /// The CRC-32 and the exact byte count are checked before returning. `sink` receives each chunk.
    static func extract(
        _ range: ZipDataRange, from input: ArchiveInput, options: ArchiveOptions,
        sink: (UnsafeRawBufferPointer) throws -> Void
    ) throws -> ZipExtraction {
        try range.entry.requireReadable()
        var hash = SHA256()
        var crc: UInt32 = 0
        var produced: UInt64 = 0
        let emit = { (bytes: UnsafeRawBufferPointer) throws -> Void in
            guard !bytes.isEmpty else { return }
            guard UInt64(bytes.count) <= range.entry.size - produced else { throw JournalError.invalidData }
            hash.update(bufferPointer: bytes)
            if let base = bytes.baseAddress {
                crc = journal_crc32(crc, base.assumingMemoryBound(to: UInt8.self), bytes.count)
            }
            produced += UInt64(bytes.count)
            try sink(bytes)
        }
        if range.entry.method == ZipEntry.stored {
            try copyStored(range, from: input, chunk: options.chunkBytes, emit: emit)
        } else {
            try inflate(range, from: input, chunk: options.chunkBytes, emit: emit)
        }
        guard produced == range.entry.size, crc == range.entry.crc32 else { throw JournalError.invalidData }
        return ZipExtraction(sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private static func copyStored(
        _ range: ZipDataRange, from input: ArchiveInput, chunk: Int,
        emit: (UnsafeRawBufferPointer) throws -> Void
    ) throws {
        var buffer = [UInt8](repeating: 0, count: chunk)
        var offset = range.dataOffset
        var left = range.entry.size
        while left > 0 {
            try Task.checkCancellation()
            let count = Int(min(UInt64(chunk), left))
            try buffer.withUnsafeMutableBytes { raw in
                try input.read(at: offset, into: UnsafeMutableRawBufferPointer(rebasing: raw[0..<count]))
                try emit(UnsafeRawBufferPointer(rebasing: raw[0..<count]))
            }
            offset += UInt64(count)
            left -= UInt64(count)
        }
    }

    /// The deflate stream must end exactly where the compressed size says: not early, and with no bytes left over.
    private static func inflate(
        _ range: ZipDataRange, from input: ArchiveInput, chunk: Int,
        emit: (UnsafeRawBufferPointer) throws -> Void
    ) throws {
        let inflater = try RawInflater()
        var compressed = [UInt8](repeating: 0, count: chunk)
        var output = [UInt8](repeating: 0, count: chunk)
        var unread = 0..<0
        var offset = range.dataOffset
        var left = range.entry.compressedSize
        var produced: UInt64 = 0
        var stalled = 0
        while true {
            try Task.checkCancellation()
            if unread.isEmpty, left > 0 {
                let count = Int(min(UInt64(chunk), left))
                try compressed.withUnsafeMutableBytes {
                    try input.read(at: offset, into: UnsafeMutableRawBufferPointer(rebasing: $0[0..<count]))
                }
                offset += UInt64(count)
                left -= UInt64(count)
                unread = 0..<count
            }
            // One byte more than is still expected, so that a stream which would expand further is noticed.
            let capacity = Int(min(UInt64(chunk), range.entry.size - produced + 1))
            let step = try inflater.step(
                input: compressed, range: unread, output: &output, capacity: capacity)
            unread = (unread.lowerBound + step.consumed)..<unread.upperBound
            guard UInt64(step.produced) <= range.entry.size - produced else { throw JournalError.invalidData }
            try output.withUnsafeBytes { try emit(UnsafeRawBufferPointer(rebasing: $0[0..<step.produced])) }
            produced += UInt64(step.produced)
            if step.finished {
                guard unread.isEmpty, left == 0, produced == range.entry.size else { throw JournalError.invalidData }
                return
            }
            stalled = step.consumed == 0 && step.produced == 0 ? stalled + 1 : 0
            guard stalled < 2 else { throw JournalError.invalidData }
        }
    }
}

/// Raw deflate through the system's zlib. A decoder that buffers its input can't say where the stream ended, and a
/// reader must refuse bytes left over inside the compressed size, so zlib's `inflate` is used rather than the
/// Compression framework.
final class RawInflater {
    struct Step {
        let consumed: Int
        let produced: Int
        let finished: Bool
    }
    private let inflater: OpaquePointer

    init() throws {
        guard let created = journal_inflater_create() else { throw JournalError.invalidData }
        inflater = created
    }

    deinit { journal_inflater_destroy(inflater) }

    func step(input: [UInt8], range: Range<Int>, output: inout [UInt8], capacity: Int) throws -> Step {
        guard capacity > 0, capacity <= output.count, range.upperBound <= input.count else {
            throw JournalError.invalidData
        }
        var consumed = 0
        var produced = 0
        let status = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                journal_inflater_step(
                    inflater, source.baseAddress.map { $0 + range.lowerBound }, range.count, destination.baseAddress,
                    capacity, &consumed, &produced)
            }
        }
        guard status >= 0 else { throw JournalError.invalidData }
        return Step(consumed: consumed, produced: produced, finished: status == 1)
    }
}
