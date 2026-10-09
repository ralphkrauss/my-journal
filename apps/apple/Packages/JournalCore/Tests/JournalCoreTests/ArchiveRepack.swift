import Foundation

@testable import JournalCore

/// Writes a file archive again with its entries deflated, which the app's writer never does (it stores everything) but
/// the reader accepts and other clients' writers may produce. The bytes, sizes and CRC-32 of every entry stay the
/// same, so the sealed manifest in `archive.json` still holds.
enum ArchiveRepack {
    /// The archive at `source` with every entry deflated whose compressed size is at least a quarter of its size (the
    /// profile's rule for `journal.sqlite`; the others are stored when they would not compress at all). Returns how
    /// many entries are deflated.
    @discardableResult
    static func deflate(_ source: URL, to destination: URL) throws -> Int {
        let input = try ArchiveInput(path: source.path)
        let directory = try ZipDirectory.read(from: input)
        var body = Data()
        var central = Data()
        var deflated = 0
        let entries = directory.all.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        for entry in entries {
            var content = Data()
            let range = try directory.range(of: entry, in: input)
            _ = try ZipExtractor.extract(range, from: input, options: .standard) { content.append(contentsOf: $0) }
            let compressed = try (content as NSData).compressed(using: .zlib) as Data
            let useDeflate =
                !content.isEmpty && compressed.count < content.count && compressed.count * 4 >= content.count
            let stored = useDeflate ? compressed : content
            let method = useDeflate ? ZipEntry.deflated : ZipEntry.stored
            if useDeflate { deflated += 1 }
            let name = Array(entry.role.name.utf8)
            central.append(
                centralRecord(
                    entry, name: name, method: method, compressedSize: stored.count, offset: UInt32(body.count)))
            body.append(localHeader(entry, name: name, method: method, compressedSize: stored.count))
            body.append(stored)
        }
        var end = Data([0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0])
        end.append(littleEndian(UInt32(entries.count) | UInt32(entries.count) << 16, 4))
        end.append(littleEndian(UInt32(central.count), 4))
        end.append(littleEndian(UInt32(body.count), 4))
        end.append(littleEndian(0, 2))
        try (body + central + end).write(to: destination)
        return deflated
    }

    private static func localHeader(_ entry: ZipEntry, name: [UInt8], method: UInt16, compressedSize: Int) -> Data {
        var record = Data([0x50, 0x4B, 0x03, 0x04])
        record.append(littleEndian(20, 2))
        record.append(littleEndian(0, 2))
        record.append(littleEndian(UInt32(method), 2))
        record.append(littleEndian(0, 2))
        record.append(littleEndian(UInt32(ArchiveLimits.dosDate), 2))
        record.append(littleEndian(entry.crc32, 4))
        record.append(littleEndian(UInt32(compressedSize), 4))
        record.append(littleEndian(UInt32(entry.size), 4))
        record.append(littleEndian(UInt32(name.count), 2))
        record.append(littleEndian(0, 2))
        record.append(contentsOf: name)
        return record
    }

    private static func centralRecord(
        _ entry: ZipEntry, name: [UInt8], method: UInt16, compressedSize: Int, offset: UInt32
    ) -> Data {
        var record = Data([0x50, 0x4B, 0x01, 0x02])
        record.append(littleEndian(20, 2))
        record.append(littleEndian(20, 2))
        record.append(littleEndian(0, 2))
        record.append(littleEndian(UInt32(method), 2))
        record.append(littleEndian(0, 2))
        record.append(littleEndian(UInt32(ArchiveLimits.dosDate), 2))
        record.append(littleEndian(entry.crc32, 4))
        record.append(littleEndian(UInt32(compressedSize), 4))
        record.append(littleEndian(UInt32(entry.size), 4))
        record.append(littleEndian(UInt32(name.count), 2))
        record.append(Data(count: 12))
        record.append(littleEndian(offset, 4))
        record.append(contentsOf: name)
        return record
    }

    private static func littleEndian(_ value: UInt32, _ width: Int) -> Data {
        Data((0..<width).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) })
    }
}
