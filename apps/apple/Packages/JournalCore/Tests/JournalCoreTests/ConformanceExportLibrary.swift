import Foundation

@testable import JournalCore

/// The library behind protocol/conformance/markdown-export/library-v1.json: journals, entries and templates that
/// meet every naming, front matter and image rule of the export, with synthetic content.
enum ConformanceExportLibrary {
    struct Record {
        let id: String
        let kind: String
        let plaintext: String
    }
    struct Attachment {
        let id: String
        let note: String
        let bytes: Data
    }

    static func identity(_ prefix: Int, _ number: Int) -> String {
        let digits = String(number)
        return "\(prefix)0000000-0000-4000-8000-" + String(repeating: "0", count: 12 - digits.count) + digits
    }
    static func journal(_ number: Int) -> String { identity(1, number) }
    static func entry(_ number: Int) -> String { identity(2, number) }
    static func template(_ number: Int) -> String { identity(3, number) }
    static func image(_ number: Int) -> String { identity(4, number).lowercased() }

    static let offsetMinutes = 120

    /// 1x1 images: a PNG and a GIF, kept as they are by the export.
    static let png =
        Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
        ?? Data()
    static let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7") ?? Data()

    static let attachments: [Attachment] = [
        Attachment(id: image(1), note: "A PNG: written as it is.", bytes: png),
        Attachment(id: image(2), note: "A GIF: written as it is.", bytes: gif),
        Attachment(id: image(3), note: "A PNG behind a reference definition a link shares.", bytes: png),
        Attachment(
            id: image(4), note: "Bytes that are not an image: counted, link kept.", bytes: Data("not an image".utf8)),
    ]
    /// Referred to but not in the library, like an image that hasn't downloaded yet.
    static let missingImage = image(5)

    private static func date(_ text: String) -> Date { (try? JournalCoding.date(from: text)) ?? Date() }
    private static func uuid(_ text: String) -> UUID { UUID(uuidString: text) ?? UUID() }
    private static func document(_ markdown: String) -> JournalDocument {
        JournalDocument(
            markdown: markdown, metadata: MarkdownMetadata(blockIDs: [], segmentLengths: nil, imageTypes: [:]),
            freshIdentities: false)
    }

    private struct Entry {
        var number: Int
        var journal: Int?
        var title: String
        var date: String
        var markdown: String
        var archived = false
        var deleted = false
    }

    private static func record(_ item: JournalItem) -> Record {
        let data = (try? PortableRecord.encode(item)) ?? Data()
        return Record(
            id: item.id.uuidString.lowercased(), kind: item.kind, plaintext: String(decoding: data, as: UTF8.self))
    }

    private static func entryRecord(_ entry: Entry) -> Record {
        let journalID = entry.journal.map { uuid($0 == 255 ? identity(1, 255) : journal($0)) }
        var item = JournalItem(
            id: uuid(Self.entry(entry.number)), kind: "entry", journalID: journalID, title: entry.title,
            document: document(entry.markdown), date: date(entry.date))
        item.modifiedAt = date(entry.date).addingTimeInterval(1800)
        if entry.archived { item.archivedAt = date(entry.date).addingTimeInterval(3600) }
        if entry.deleted { item.deletedAt = date(entry.date).addingTimeInterval(7200) }
        return record(item)
    }

    private static func journalRecord(_ number: Int, _ title: String, deleted: Bool = false) -> Record {
        var item = JournalItem(
            id: uuid(journal(number)), kind: "journal", title: title, document: document(""),
            date: date("2026-01-01T00:00:00Z"))
        if deleted { item.deletedAt = date("2026-09-30T00:00:00Z") }
        return record(item)
    }

    private static func templateRecord(_ number: Int, _ title: String, _ markdown: String) -> Record {
        record(
            JournalItem(
                id: uuid(template(number)), kind: "template", title: title, document: document(markdown),
                date: date("2026-02-01T00:00:00Z")))
    }

    private static let morning = """
        Morning *walk*.

        ![The bay](attachments/\(image(1)))

        Text with ![a cup](attachments/\(image(2)) "Cup") inside, and `attachments/\(image(2))` in code.

        ![A map][map] and [open the map][map]

        ![Broken](attachments/\(image(4)))

        ![Still downloading](attachments/\(missingImage))

        - [ ] Call the bank
        - [x] Water plants

        [map]: attachments/\(image(3))
        """

    private static let entries: [Entry] = [
        Entry(number: 1, journal: 1, title: "Morning pages", date: "2026-10-05T05:12:00Z", markdown: morning),
        Entry(
            number: 2, journal: 1, title: "", date: "2026-10-04T22:30:00Z", markdown: "Quiet day\nNothing else",
            archived: true),
        Entry(number: 3, journal: 1, title: "Paris", date: "2026-10-03T10:00:00Z", markdown: "First."),
        Entry(number: 4, journal: 1, title: "paris", date: "2026-10-03T10:00:00Z", markdown: "Second."),
        Entry(number: 5, journal: 1, title: "Paris", date: "2026-10-03T10:00:00Z", markdown: "Third."),
        Entry(number: 6, journal: 1, title: "CON", date: "2026-10-02T10:00:00Z", markdown: "A device name."),
        Entry(
            number: 7, journal: 1, title: "Deleted entry", date: "2026-10-01T10:00:00Z", markdown: "Gone.",
            deleted: true),
        Entry(
            number: 8, journal: 2, title: "Plan", date: "2026-10-03T08:00:00Z",
            markdown: "Ship it\n\n![](attachments/\(missingImage))\n"),
        Entry(
            number: 9, journal: 2, title: "Q4: \"plan\" #1 *draft* [x]", date: "2026-10-03T09:00:00Z",
            markdown: "Escapes in front matter and heading.\n"),
        Entry(number: 10, journal: 2, title: "Two\nlines\tand a tab", date: "2026-10-03T09:30:00Z", markdown: "x\n"),
        Entry(
            number: 11, journal: 2, title: String(repeating: "Long title ", count: 10), date: "2026-10-03T09:45:00Z",
            markdown: "Cut at 60 characters.\n"),
        Entry(
            number: 15, journal: 3, title: "Same journal name", date: "2026-09-04T10:00:00Z",
            markdown: "Folder numbering.\n"),
        Entry(
            number: 16, journal: 6, title: "Named like a folder", date: "2026-09-05T10:00:00Z",
            markdown: "Templates folder numbering.\n"),
        Entry(
            number: 12, journal: 255, title: "Journal never synced", date: "2026-09-01T10:00:00Z", markdown: "Orphan.\n"
        ),
        Entry(
            number: 13, journal: 5, title: "In a deleted journal", date: "2026-09-02T10:00:00Z", markdown: "Hidden.\n"),
        Entry(
            number: 14, journal: 4, title: "In CON", date: "2026-09-03T10:00:00Z",
            markdown: "Crème brûlée, 日記 and 🌿.\n"),
    ]

    /// Entries written by a client with a newer format, and one that can't be read at all.
    private static let others = [
        Record(
            id: entry(20).lowercased(), kind: "entry",
            plaintext:
                #"{"id":"\#(entry(20))","kind":"entry","journalID":"\#(journal(1))","title":"Newer client","date":"2026-10-01T08:00:00Z","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false,"mood":4,"document":{"version":2,"markdown":"Kept as written by a newer client.\n"}}"#
        ),
        Record(
            id: entry(21).lowercased(), kind: "entry",
            plaintext:
                #"{"id":"\#(entry(21))","kind":"entry","title":"No date","modifiedAt":"2026-10-01T08:05:00Z","deletedWithJournal":false}"#
        ),
    ]

    static var records: [Record] {
        let journals = [
            journalRecord(1, "Personal"), journalRecord(2, "Work: Q4/Plans"), journalRecord(3, "personal"),
            journalRecord(4, "CON"), journalRecord(5, "Gone", deleted: true), journalRecord(6, "Templates"),
        ]
        let templates = [
            templateRecord(1, "Weekly review", "## Wins\n\n![Chart](attachments/\(image(1)))\n"),
            templateRecord(2, "", "Untitled template body\n"),
            templateRecord(3, "nul", "Reserved name\n"),
            templateRecord(4, "weekly REVIEW", "Same name apart from case\n"),
        ]
        return journals + entries.map(entryRecord) + others + templates
    }

    /// Journal order: ranks put them in this order; the others follow by name.
    static let ranks: [String: String] = [
        journal(1).lowercased(): "V", journal(2).lowercased(): "k", journal(3).lowercased(): "x",
        journal(4).lowercased(): "y",
    ]
    static let pinned = [entry(1).lowercased(), entry(3).lowercased()]
}
