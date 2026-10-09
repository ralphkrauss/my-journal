import Foundation

/// The words of a stored `CREATE` statement that decide whether a table or index is one the migrations create.
///
/// The structure check reads SQLite's own descriptions (`PRAGMA table_xinfo`, `foreign_key_list` and the others)
/// rather than comparing `CREATE` text, because writers word the same table differently. A few clauses change what a
/// table does but no pragma reports them: a `CHECK` that rejects writes, a `COLLATE` that changes what is equal, an
/// `ON CONFLICT` clause that turns an insert into a replace, `DEFERRABLE` constraints, a generated column written
/// without `GENERATED`, and a virtual table. A stored statement that contains one of these words (outside quotes and
/// comments) is refused. Another client's reader makes the same split (protocol/archive.md, Database).
enum ArchiveSchemaWords {
    /// Words no table or index of the library has.
    static let refused: Set<String> = ["AS", "CHECK", "COLLATE", "CONFLICT", "DEFERRABLE", "GENERATED", "VIRTUAL"]

    /// The refused words that `sql` contains, in upper case.
    static func refusedWords(in sql: String) -> [String] {
        words(in: sql).intersection(refused).sorted()
    }

    /// The upper-case words of `sql`: runs of ASCII letters, digits, `_` and `$` and of bytes of 0x80 or more (SQLite
    /// reads those as one identifier, so `CHECKé` is not `CHECK`), outside `'…'`, `"…"`, `` `…` `` and `[…]` and
    /// outside `--` and `/* */` comments. An unterminated quote or comment runs to the end.
    static func words(in sql: String) -> Set<String> {
        let bytes = Array(sql.utf8)
        var found: Set<String> = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x27, 0x22, 0x60: index = end(ofQuoted: bytes, from: index, closing: byte)
            case 0x5B: index = end(ofQuoted: bytes, from: index, closing: 0x5D)
            case 0x2D where bytes[safe: index + 1] == 0x2D: index = end(ofLineComment: bytes, from: index)
            case 0x2F where bytes[safe: index + 1] == 0x2A: index = end(ofBlockComment: bytes, from: index)
            case _ where isWordByte(byte):
                var last = index
                while let following = bytes[safe: last + 1], isWordByte(following) { last += 1 }
                found.insert(String(decoding: bytes[index...last], as: UTF8.self).uppercased())
                index = last + 1
            default: index += 1
            }
        }
        return found
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x24: return true
        default: return byte >= 0x80
        }
    }

    /// A doubled quote inside `'…'`, `"…"` and `` `…` `` closes the text and opens the next one at once, which skips the
    /// same bytes as an escape would.
    private static func end(ofQuoted bytes: [UInt8], from start: Int, closing: UInt8) -> Int {
        guard let close = bytes[(start + 1)...].firstIndex(of: closing) else { return bytes.count }
        return close + 1
    }

    private static func end(ofLineComment bytes: [UInt8], from start: Int) -> Int {
        guard let newline = bytes[start...].firstIndex(of: 0x0A) else { return bytes.count }
        return newline + 1
    }

    private static func end(ofBlockComment bytes: [UInt8], from start: Int) -> Int {
        var index = start + 2
        while index + 1 < bytes.count {
            if bytes[index] == 0x2A, bytes[index + 1] == 0x2F { return index + 2 }
            index += 1
        }
        return bytes.count
    }
}

extension [UInt8] {
    fileprivate subscript(safe index: Int) -> UInt8? {
        index >= 0 && index < count ? self[index] : nil
    }
}
