import Foundation

/// Counts the rows of `sqlite_master` by reading the file's own b-tree pages, before SQLite is asked anything.
/// SQLite parses every row of the schema the first time a statement is prepared on a connection, so a hostile file
/// with a million `CREATE VIEW` rows would cost minutes and hundreds of megabytes to open. Nothing here executes SQL
/// or depends on the schema's contents, only on page structure that SQLite documents (file format, "The Schema
/// Table" and "B-tree Pages").
///
/// The scan accepts only what SQLite itself would walk the same way: every page it reads is a table b-tree page and
/// is read once. It stops at the first limit it passes, so its own cost is bounded by `ArchiveLimits.schemaPages`
/// pages.
enum ArchiveSchemaScan {
    struct Summary: Equatable {
        /// The objects (tables, indexes, views, triggers) the schema table holds.
        var rows = 0
        /// The sum of the stored sizes of all its rows, overflow included.
        var payloadBytes: UInt64 = 0
        var pages = 0
    }

    private static let headerLength = 100
    private static let tableLeaf: UInt8 = 0x0D
    private static let tableInterior: UInt8 = 0x05
    /// SQLite's own limit on the depth of a b-tree.
    private static let maximumDepth = 20

    /// Throws `JournalError.invalidData` for a file whose schema is over the limits or whose first pages are not a
    /// readable table b-tree, and `CancellationError` when the task is cancelled.
    static func scan(_ file: URL) throws -> Summary {
        let input = try ArchiveInput(path: file.path)
        let pageSize = try pageSize(of: try input.read(at: 0, count: headerLength))
        let pageCount = input.size / UInt64(pageSize)
        var summary = Summary()
        var pending: [(number: UInt64, depth: Int)] = [(1, 1)]
        var visited: Set<UInt64> = []
        while let (number, depth) = pending.popLast() {
            try Task.checkCancellation()
            guard depth <= maximumDepth, number >= 1, number <= pageCount, visited.insert(number).inserted,
                visited.count <= ArchiveLimits.schemaPages
            else { throw JournalError.invalidData }
            let page = try input.read(at: (number - 1) * UInt64(pageSize), count: pageSize)
            let offset = number == 1 ? headerLength : 0
            switch try page.byte(offset) {
            case tableLeaf: try add(leaf: page, at: offset, to: &summary)
            case tableInterior:
                let children = try children(ofInteriorPage: page, at: offset)
                guard pending.count + visited.count + children.count <= ArchiveLimits.schemaPages else {
                    throw JournalError.invalidData
                }
                pending.append(contentsOf: children.map { ($0, depth + 1) })
            default: throw JournalError.invalidData
            }
            summary.pages = visited.count
        }
        return summary
    }

    /// Bytes 16 and 17: a power of two from 512 to 32768, or 1 for 65536.
    private static func pageSize(of header: [UInt8]) throws -> Int {
        guard header.starts(with: Array("SQLite format 3\0".utf8)) else { throw JournalError.invalidData }
        let stored = Int(try header.be16(16))
        let size = stored == 1 ? 65_536 : stored
        guard (512...65_536).contains(size), size & (size - 1) == 0 else { throw JournalError.invalidData }
        return size
    }

    /// The cell pointers of a b-tree page: the cell count at offset 3 of its header and the array after the header.
    private static func cellPointers(of page: [UInt8], at offset: Int, headerSize: Int) throws -> [Int] {
        let count = Int(try page.be16(offset + 3))
        let start = offset + headerSize
        guard start + 2 * count <= page.count else { throw JournalError.invalidData }
        return try (0..<count).map { index in
            let pointer = Int(try page.be16(start + 2 * index))
            guard pointer >= start + 2 * count, pointer < page.count else { throw JournalError.invalidData }
            return pointer
        }
    }

    /// A leaf cell starts with the size of its payload (a varint) and the row number; the payload may overflow onto
    /// other pages, so the size is what counts, not what the page holds.
    private static func add(leaf page: [UInt8], at offset: Int, to summary: inout Summary) throws {
        for pointer in try cellPointers(of: page, at: offset, headerSize: 8) {
            let (size, _) = try page.varint(at: pointer)
            summary.rows += 1
            summary.payloadBytes = try summary.payloadBytes.adding(size)
            guard summary.rows <= ArchiveLimits.schemaObjects, summary.payloadBytes <= ArchiveLimits.schemaBytes else {
                throw JournalError.invalidData
            }
        }
    }

    /// An interior cell starts with the 4-byte number of its left child; the right-most child is in the header.
    private static func children(ofInteriorPage page: [UInt8], at offset: Int) throws -> [UInt64] {
        var children = try cellPointers(of: page, at: offset, headerSize: 12).map { UInt64(try page.be32($0)) }
        children.append(UInt64(try page.be32(offset + 8)))
        return children
    }
}

extension [UInt8] {
    fileprivate func byte(_ offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < count else { throw JournalError.invalidData }
        return self[offset]
    }

    fileprivate func be16(_ offset: Int) throws -> UInt16 {
        UInt16(try byte(offset)) << 8 | UInt16(try byte(offset + 1))
    }

    fileprivate func be32(_ offset: Int) throws -> UInt32 {
        UInt32(try be16(offset)) << 16 | UInt32(try be16(offset + 2))
    }

    /// SQLite's varint: up to nine bytes, seven bits each with the high bit set while more follow, and eight bits in
    /// the ninth. Returns the value and the number of bytes it took.
    fileprivate func varint(at offset: Int) throws -> (UInt64, Int) {
        var value: UInt64 = 0
        for index in 0..<8 {
            let byte = try byte(offset + index)
            value = value << 7 | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 { return (value, index + 1) }
        }
        return (value << 8 | UInt64(try byte(offset + 8)), 9)
    }
}
