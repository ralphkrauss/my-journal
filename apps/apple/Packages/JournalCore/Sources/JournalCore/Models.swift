import Foundation

public enum JournalError: Error, LocalizedError {
    case unsupportedFormat, invalidData, invalidRecoveryKey, locked, unauthorized, server(String), conflict,
        invalidAddress, newerVersion, invalidSetupCode
    /// Journals on this device were saved by a newer version, so they can't be merged with a server's yet.
    case mergeNeedsUpdate
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Update My Journal to edit this entry."
        case .newerVersion:
            return "These journals were saved by a newer version of My Journal. Update My Journal to open them."
        case .invalidData: return "This data couldn’t be read."
        case .invalidRecoveryKey: return "That password or recovery key couldn’t unlock your journals."
        case .locked: return "Unlock My Journal to continue."
        case .unauthorized: return "This device no longer has access."
        case .server(let message): return message
        case .conflict: return "This entry has changes from another device."
        case .invalidAddress: return "Enter a valid HTTPS server address."
        case .invalidSetupCode: return "That setup code isn’t valid. Check it and try again."
        case .mergeNeedsUpdate:
            return "Update My Journal to merge the journals on this device. Some of them were saved by a newer version."
        }
    }
}

public struct TextRun: Codable, Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var link: String?
    public var strikethrough: Bool = false
    public var code: Bool = false
    public var linkTitle: String?
    public var breakKind: String?
    public var rawHTML = false
    public var imageSource: String?
    public var imageTitle: String?
    public var imageMediaType: String?
    private enum CodingKeys: String, CodingKey {
        case text, bold, italic, underline, link, strikethrough, code, linkTitle, breakKind, rawHTML, imageSource,
            imageTitle, imageMediaType
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decode(String.self, forKey: .text)
        bold = try values.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try values.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try values.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        link = try values.decodeIfPresent(String.self, forKey: .link)
        strikethrough = try values.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        code = try values.decodeIfPresent(Bool.self, forKey: .code) ?? false
        linkTitle = try values.decodeIfPresent(String.self, forKey: .linkTitle)
        breakKind = try values.decodeIfPresent(String.self, forKey: .breakKind)
        rawHTML = try values.decodeIfPresent(Bool.self, forKey: .rawHTML) ?? false
        imageSource = try values.decodeIfPresent(String.self, forKey: .imageSource)
        imageTitle = try values.decodeIfPresent(String.self, forKey: .imageTitle)
        imageMediaType = try values.decodeIfPresent(String.self, forKey: .imageMediaType)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(text, forKey: .text)
        try values.encode(bold, forKey: .bold)
        try values.encode(italic, forKey: .italic)
        try values.encode(underline, forKey: .underline)
        try values.encodeIfPresent(link, forKey: .link)
        if strikethrough { try values.encode(true, forKey: .strikethrough) }
        if code { try values.encode(true, forKey: .code) }
        try values.encodeIfPresent(linkTitle, forKey: .linkTitle)
        try values.encodeIfPresent(breakKind, forKey: .breakKind)
        if rawHTML { try values.encode(true, forKey: .rawHTML) }
        try values.encodeIfPresent(imageSource, forKey: .imageSource)
        try values.encodeIfPresent(imageTitle, forKey: .imageTitle)
        try values.encodeIfPresent(imageMediaType, forKey: .imageMediaType)
    }
    public init(_ text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, link: String? = nil)
    {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.link = link
    }
}
public struct DocumentBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: String
    public var runs: [TextRun]
    public var attachmentID: UUID?
    public var imageDescription: String?
    public var mediaType: String?
    public var table: DocumentTable?
    public var codeLanguage: String?
    public var markdownPrefix: String?
    public var markdownContinuation: String?
    public var listIndents: [Int]?
    public var listNumber: Int?
    /// The list marker as read from Markdown, such as "* " or "1) ", so a rewritten item stays in its list.
    public var listMarker: String?
    public init(
        kind: String = "paragraph", runs: [TextRun] = [], attachmentID: UUID? = nil, imageDescription: String? = nil,
        mediaType: String? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.runs = runs
        self.attachmentID = attachmentID

        self.imageDescription = imageDescription
        self.mediaType = mediaType
    }
}
public struct JournalDocument: Codable, Equatable, Sendable {
    public var version: Int = 2
    var source: String?
    var sourceSegments: [String] = []
    var sourceLeading = ""
    var sourceTails: [String] = []
    var requiresSource = false
    public var blocks: [DocumentBlock] {
        didSet {
            if oldValue != blocks {
                source = nil
                sourceSegments = []
                sourceLeading = ""
                sourceTails = []
                requiresSource = false
            }
        }
    }
    public init(blocks: [DocumentBlock] = []) { self.blocks = blocks }
    public var text: String {
        if requiresSource { return markdown }
        return blocks.map(Self.text).joined(separator: "\n")
    }
    /// The start of `text`, at least `length` bytes of it when the document has that much, without reading on.
    public func text(prefix length: Int) -> String {
        if requiresSource { return String(markdown.prefix(length)) }
        var result = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 { result += "\n" }
            result += Self.text(of: block)
            if result.utf8.count >= length { break }
        }
        return result
    }
    /// The first line of `text` that has any characters.
    var firstLine: String? {
        var length = 512
        while true {
            let start = text(prefix: length)
            let lines = start.split(separator: "\n")
            // A later line shows the first one is complete; a start shorter than asked for is the whole text.
            if lines.count > 1 || start.utf8.count < length { return lines.first.map(String.init) }
            length *= 4
        }
    }
    private static func text(of block: DocumentBlock) -> String {
        block.table?.text
            ?? (block.kind == "image" ? (block.imageDescription ?? "Image") : block.runs.map(\.text).joined())
    }
    public var isEditable: Bool {
        (version == 1 || version == 2) && (requiresSource || blocks.allSatisfy { Self.editableKinds.contains($0.kind) })
    }
    static let editableKinds: Set<String> = [
        "paragraph", "heading", "subheading", "heading3", "heading4", "heading5", "heading6", "bullet", "numbered",
        "task", "checked", "quote", "rule", "image", "codeBlock", "html", "table",
    ]
    public static func plain(_ text: String) -> Self {
        Self(blocks: text.components(separatedBy: "\n").map { DocumentBlock(runs: [TextRun($0)]) })
    }
}
/// Identifies the exact stored record an item was read from. Saving compares it with the record being replaced,
/// so a copy read before another change can't silently overwrite that change.
public struct StoredVersion: Hashable, Sendable {
    let digest: Data
}
public struct JournalItem: Codable, Equatable, Sendable, Identifiable {
    /// Original JSON retained for lossless export when this client cannot safely edit the record.
    public var preservedJSON: Data?
    /// The stored record this item was read from. It isn't part of the item's value or its encoding.
    public var storedVersion: StoredVersion?
    private enum CodingKeys: String, CodingKey {
        case id, kind, journalID, title, document, date, modifiedAt, deletedAt, deletedWithJournal, defaultTemplateID
        case permanentlyDeletedAt, permanentDeletionID, restoredFromDeletionID, archivedAt
    }
    public var id: UUID
    public var kind: String
    public var journalID: UUID?
    public var title: String
    public var document: JournalDocument
    // Timestamps keep the whole-second precision records are stored with, so an item equals its stored copy.
    public var date: Date { didSet { date = date.portableTimestamp } }
    public var modifiedAt: Date { didSet { modifiedAt = modifiedAt.portableTimestamp } }
    public var archivedAt: Date? { didSet { archivedAt = archivedAt?.portableTimestamp } }
    public var deletedAt: Date? { didSet { deletedAt = deletedAt?.portableTimestamp } }
    public var deletedWithJournal: Bool
    public var defaultTemplateID: UUID?
    public var permanentlyDeletedAt: Date? { didSet { permanentlyDeletedAt = permanentlyDeletedAt?.portableTimestamp } }
    public var permanentDeletionID: UUID?
    public var restoredFromDeletionID: UUID?
    public var isPermanentlyDeleted: Bool { permanentlyDeletedAt != nil }
    public init(
        id: UUID = UUID(), kind: String, journalID: UUID? = nil, title: String = "",
        document: JournalDocument = .init(), date: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.journalID = journalID
        self.title = title
        self.document = document

        self.date = date.portableTimestamp
        self.modifiedAt = date.portableTimestamp
        self.deletedWithJournal = false
    }
    /// Decoding keeps whatever precision another client wrote; saving would store whole seconds.
    mutating func normalizeTimestamps() {
        date = date.portableTimestamp
        modifiedAt = modifiedAt.portableTimestamp
        archivedAt = archivedAt?.portableTimestamp
        deletedAt = deletedAt?.portableTimestamp
        permanentlyDeletedAt = permanentlyDeletedAt?.portableTimestamp
    }
    /// Compares content only: `storedVersion` records where an item came from, not what it contains.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.journalID == rhs.journalID && lhs.title == rhs.title
            && lhs.document == rhs.document && lhs.date == rhs.date && lhs.modifiedAt == rhs.modifiedAt
            && lhs.archivedAt == rhs.archivedAt && lhs.deletedAt == rhs.deletedAt
            && lhs.deletedWithJournal == rhs.deletedWithJournal && lhs.defaultTemplateID == rhs.defaultTemplateID
            && lhs.permanentlyDeletedAt == rhs.permanentlyDeletedAt
            && lhs.permanentDeletionID == rhs.permanentDeletionID
            && lhs.restoredFromDeletionID == rhs.restoredFromDeletionID && lhs.preservedJSON == rhs.preservedJSON
    }
    public var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return document.firstLine ?? "New Entry"
    }
}
/// The templates builds up to 14 saved in every new library. New libraries start without templates
/// (docs/design/no-built-in-templates-2026-10-04.md), but libraries made earlier keep theirs, so they're still recognized
/// when libraries connect or merge.
public enum BuiltInTemplates {
    /// The templates as an earlier build created them in a new library, each with a new identity. Only for checking
    /// that such libraries still connect and merge as before; nothing creates them in a library anymore.
    public static func asEarlierBuildsCreated() -> [JournalItem] {
        [
            template(
                "Daily Reflection", ["What went well?", "What felt difficult?", "What will I carry into tomorrow?"]),
            template("Gratitude", ["What am I grateful for today?"]),
            template(
                "Workday Log",
                [
                    "What I worked on", "Decisions and context", "Blockers and open questions",
                    "Where to pick up tomorrow",
                ]
            ),
            template(
                "Weekly Reflection", ["What stood out this week?", "What did I learn?", "What would I like to change?"]
            ),
        ]
    }
    /// Every built-in template text that has ever shipped, as Markdown lines without blank ones. Append an entry when
    /// the wording changes and never edit or remove one, so a template someone never touched is still recognized as
    /// unedited (docs/design/join-with-local-journals.md §2.3).
    public static let shipped: [(title: String, text: String)] = [
        ("Daily Reflection", "# What went well?\n# What felt difficult?\n# What will I carry into tomorrow?"),
        ("Gratitude", "# What am I grateful for today?"),
        (
            "Workday Log",
            "# What I worked on\n# Decisions and context\n# Blockers and open questions\n# Where to pick up tomorrow"
        ),
        ("Weekly Reflection", "# What stood out this week?\n# What did I learn?\n# What would I like to change?"),
    ]
    /// A template exactly as a built-in one was created, never edited. Its text is compared as Markdown, since a stored
    /// document may hold the same text in another form.
    public static func isUnedited(_ item: JournalItem) -> Bool {
        item.kind == "template"
            && shipped.contains { $0.title == item.title && $0.text == item.document.comparableText }
    }
    private static func template(_ title: String, _ questions: [String]) -> JournalItem {
        JournalItem(
            kind: "template", title: title,
            document: .init(
                blocks: questions.flatMap { [DocumentBlock(kind: "heading", runs: [TextRun($0)]), DocumentBlock()] }))
    }
}
public enum JournalCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        return encoder
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            return try date(from: value)
        }
        return decoder
    }
    public static func date(from value: String) throws -> Date {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
        guard let date = try? Date.ISO8601FormatStyle().parse(value) else { throw JournalError.invalidData }
        return date
    }
    /// The whole-second UTC text used for local timestamps, such as when a conflict or version was recorded.
    static func timestamp(_ date: Date) -> String { Date.ISO8601FormatStyle().format(date) }
}

extension Date {
    /// Portable records store whole seconds, rounded down like the ISO 8601 encoding.
    var portableTimestamp: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded(.down)) }
}
