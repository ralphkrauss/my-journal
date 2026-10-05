import Foundation

/// Which folders and files an export writes, with names that are safe on macOS, Windows, Linux and in Obsidian, and
/// that stay the same when the same library is exported again (protocol/markdown-export.md).
struct MarkdownExportPlan {
    struct File {
        let item: JournalItem
        /// Without `.md`.
        let name: String
        let pinned: Bool
    }
    struct Folder {
        let name: String
        /// Nil for templates and for entries whose journal isn't in the library.
        let journal: JournalItem?
        var files: [File]
    }

    private(set) var folders: [Folder] = []
    /// Entries and templates this version can't read.
    private(set) var unreadable = 0

    init(items: [JournalItem], pinned: Set<UUID>, ranks: [UUID: String], timeZone: TimeZone = .current) {
        let present = items.filter { $0.deletedAt == nil && !$0.isPermanentlyDeleted }
        let journals = JournalRanks.arranged(present.filter { $0.kind == "journal" }, ranks: ranks)
        let journalIDs = Set(journals.map(\.id))
        // A deleted journal's entries are in Recently Deleted with it, though only the journal is marked deleted.
        let deletedJournals = Set(
            items.filter { $0.kind == "journal" && ($0.deletedAt != nil || $0.isPermanentlyDeleted) }.map(\.id))
        var entries: [UUID?: [JournalItem]] = [:]
        var templates: [JournalItem] = []
        for item in present where ["entry", "template"].contains(item.kind) {
            if item.kind == "entry", let journal = item.journalID, deletedJournals.contains(journal) {
                continue
            } else if Self.isUnreadable(item) {
                unreadable += 1
            } else if item.kind == "template" {
                templates.append(item)
            } else {
                entries[item.journalID.flatMap { journalIDs.contains($0) ? $0 : nil }, default: []].append(item)
            }
        }
        var names = UniqueNames()
        for journal in journals {
            let name = names.claim(ExportName.safe(journal.title, fallback: "Untitled Journal"))
            let files = Self.entryFiles(entries[journal.id] ?? [], pinned: pinned, timeZone: timeZone)
            folders.append(Folder(name: name, journal: journal, files: files))
        }
        if let unfiled = entries[nil], !unfiled.isEmpty {
            let files = Self.entryFiles(unfiled, pinned: pinned, timeZone: timeZone)
            folders.append(Folder(name: names.claim("Other Entries"), journal: nil, files: files))
        }
        if !templates.isEmpty {
            var fileNames = UniqueNames()
            let sorted = templates.sorted {
                ($0.title.lowercased(), $0.id.uuidString) < ($1.title.lowercased(), $1.id.uuidString)
            }
            let files = sorted.map { template in
                File(
                    item: template,
                    name: fileNames.claim(ExportName.safe(template.title, fallback: "Untitled Template")),
                    pinned: false)
            }
            folders.append(Folder(name: names.claim("Templates"), journal: nil, files: files))
        }
    }

    /// An entry or template whose content couldn't be decoded: its original record is kept, but it has no text.
    static func isUnreadable(_ item: JournalItem) -> Bool {
        item.preservedJSON != nil && item.document.source == nil && item.document.blocks.isEmpty
    }

    private static func entryFiles(_ entries: [JournalItem], pinned: Set<UUID>, timeZone: TimeZone) -> [File] {
        var names = UniqueNames()
        return entries.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }.map { entry in
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = ExportName.safe(title.isEmpty ? entry.document.firstLine ?? "" : title, fallback: "Untitled")
            let day = MarkdownExport.day(entry.date, timeZone: timeZone)
            return File(item: entry, name: names.claim(day + " " + base), pinned: pinned.contains(entry.id))
        }
    }
}

/// Folder and file names: NFC, without characters that are unsafe on some systems or in Obsidian, and short enough
/// for every file system and for Windows' 260-character paths.
enum ExportName {
    static let maximumCharacters = 60
    static let maximumBytes = 120
    private static let replaced: Set<Character> = [
        "/", "\\", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]",
    ]
    private static let reserved: Set<String> = Set(
        ["CON", "PRN", "AUX", "NUL"] + (Array("123456789¹²³").map(String.init)).flatMap { ["COM\($0)", "LPT\($0)"] })

    /// Control characters, characters APFS refuses (noncharacters and unassigned code points), and direction
    /// overrides, which can make a name display as something else.
    private static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .unassigned, .surrogate: return true
        default: return (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
        }
    }

    static func safe(_ name: String, fallback: String) -> String {
        var cleaned = ""
        for character in name.precomposedStringWithCanonicalMapping {
            if character.isNewline || character == "\t" {
                cleaned.append(" ")
            } else if replaced.contains(character) || character.unicodeScalars.contains(where: isUnsafe) {
                cleaned.append("-")
            } else {
                cleaned.append(character)
            }
        }
        var result = ""
        for character in trimmed(cleaned) {
            guard result.count < maximumCharacters,
                result.utf8.count + String(character).utf8.count <= maximumBytes
            else { break }
            result.append(character)
        }
        result = trimmed(result)
        if result.isEmpty { result = fallback }
        // Windows treats `CON.txt` as the device CON too, so the mark goes before the first dot.
        let dot = result.firstIndex(of: ".") ?? result.endIndex
        if reserved.contains(result[..<dot].trimmingCharacters(in: .whitespaces).uppercased()) {
            result.insert("-", at: dot)
        }
        return result
    }

    /// Without spaces at either end, dots at the start, or dots and spaces at the end.
    private static func trimmed(_ name: String) -> String {
        var result = Substring(name.trimmingCharacters(in: .whitespaces))
        while result.first == "." || result.first == " " { result.removeFirst() }
        while result.last == "." || result.last == " " { result.removeLast() }
        return String(result)
    }
}

/// Numbers names that are already used, ignoring letter case: “Name”, “Name 2”, “Name 3”, …
struct UniqueNames {
    private var used: Set<String> = []

    mutating func claim(_ name: String) -> String {
        var candidate = name
        var number = 2
        while used.contains(Self.key(candidate)) {
            candidate = name + " \(number)"
            number += 1
        }
        used.insert(Self.key(candidate))
        return candidate
    }

    /// As APFS compares names: ignoring Unicode form and with full case folding, so “Straße” and “STRASSE” match.
    private static func key(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
            .precomposedStringWithCanonicalMapping
    }
}
