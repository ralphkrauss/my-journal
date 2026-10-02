import JournalCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Text pasted from another app, as the entry's own blocks.
struct PastedFragment {
    var blocks: [DocumentBlock]
    /// Whether the copied text ended with a line break, as a whole copied paragraph does.
    var endsWithBreak: Bool
    /// Plain text has no blocks of its own; its lines continue a list they are pasted into.
    var isPlain = false
    /// Pictures in the copied text, in order. Each waits in a paragraph of its own, `pictureBlocks`, until it is
    /// imported like any other image.
    var pictures: [NSTextAttachment] = []
    var pictureBlocks: Set<UUID> = []

    private var textBlocks: [DocumentBlock] { blocks.filter { !pictureBlocks.contains($0.id) } }
    /// The text alone, as code or Markdown source takes it.
    var text: String { textBlocks.map { $0.runs.map(\.text).joined() }.joined(separator: "\n") }
    /// The pasted text as Markdown source. A single paragraph keeps the spaces around it, which written on its own
    /// it would escape.
    var markdown: String {
        guard !isPlain else { return text }
        var written = JournalDocument(blocks: textBlocks).markdown.trimmingCharacters(in: .newlines)
        if textBlocks.count == 1, textBlocks[0].kind == "paragraph" {
            if written.hasPrefix("&#32;") { written = " " + written.dropFirst(5) }
            if written.hasSuffix("&#32;") { written = written.dropLast(5) + " " }
        }
        return written + (endsWithBreak ? "\n" : "")
    }
}

/// Formatted text pasted from another app, such as a web page or a document. As in Notes, its lists, headings, quotes
/// and code become the entry's own blocks, and its own fonts, colours and sizes are left behind. Text that can't be
/// read cleanly is pasted as plain paragraphs.
@MainActor enum PastedRichText {
    /// The pasted text as the entry's blocks, or nil when it has no text or pictures.
    static func fragment(_ text: NSAttributedString) -> PastedFragment? {
        guard text.length > 0 else { return nil }
        var reader = Reader(text: text, bodySize: bodySize(text))
        let source = text.string as NSString
        var position = 0
        while position < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = NSMaxRange(paragraph)
            reader.read(paragraph)
        }
        let blocks = reader.finish()
        guard !blocks.isEmpty else { return nil }
        let trailing = text.string.reversed().prefix(while: \.isWhitespace)
        return PastedFragment(
            blocks: blocks, endsWithBreak: trailing.contains(where: \.isNewline), pictures: reader.pictures,
            pictureBlocks: reader.pictureBlocks)
    }

    /// Plain text as paragraphs, one for each line, kept exactly as written. In place of formatted text, its empty
    /// lines are left out as the formatted text's would be.
    static func fragment(plain: String, keepingEmptyLines: Bool = true) -> PastedFragment? {
        guard !plain.isEmpty else { return nil }
        var lines = plain.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        let endsWithBreak = lines.count > 1 && lines.last == ""
        if endsWithBreak { lines.removeLast() }
        if !keepingEmptyLines {
            lines.removeAll(where: isBlank)
            guard !lines.isEmpty else { return nil }
        }
        return PastedFragment(
            blocks: lines.map { DocumentBlock(runs: $0.isEmpty ? [] : [TextRun($0)]) }, endsWithBreak: endsWithBreak,
            isPlain: true)
    }

    #if os(macOS)
        // Text views still name the formatted types by their original pasteboard names.
        private static let rtfTypes: Set<NSPasteboard.PasteboardType> = [
            .rtf, .rtfd, .init("NeXT Rich Text Format v1.0 pasteboard type"), .init("NeXT RTFD pasteboard type"),
        ]
        private static let htmlTypes: Set<NSPasteboard.PasteboardType> = [.html, .init("Apple HTML pasteboard type")]
        /// Paste and Match Style reads the plain text as "NSStringWithLinksPboardType".
        private static let plainTypes: Set<NSPasteboard.PasteboardType> = [
            .string, .init("NSStringPboardType"), .init("NSStringWithLinksPboardType"),
        ]

        /// Whether `type` is text, which the entry reads as its own blocks.
        static func readsText(of type: NSPasteboard.PasteboardType) -> Bool {
            rtfTypes.contains(type) || htmlTypes.contains(type) || plainTypes.contains(type)
        }

        /// The text the text view would read as `type`, or nil for a type that isn't text.
        static func fragment(on board: NSPasteboard, type: NSPasteboard.PasteboardType) -> PastedFragment? {
            let plain = board.string(forType: .string)
            if rtfTypes.contains(type) {
                // Pictures are only in the RTFD a document or web page offers beside its RTF.
                for (formatted, documentType) in [
                    (NSPasteboard.PasteboardType.rtfd, NSAttributedString.DocumentType.rtfd), (.rtf, .rtf),
                ] {
                    if let data = board.data(forType: formatted) {
                        return formattedFragment(data, type: documentType, plain: plain)
                    }
                }
            } else if htmlTypes.contains(type), let data = board.data(forType: .html) {
                return formattedFragment(data, type: .html, plain: plain)
            }
            return plain.flatMap { fragment(plain: $0) }
        }
    #else
        /// Whether the pasteboard holds text, formatted or plain.
        static func hasText(on board: UIPasteboard) -> Bool {
            board.hasStrings || board.contains(pasteboardTypes: [UTType.html, .rtf, .flatRTFD].map(\.identifier))
        }

        /// The pasteboard's text: its formatted text when it has any, else its plain text.
        static func fragment(on board: UIPasteboard) -> PastedFragment? {
            let offered = Set(board.types)
            // The pasteboard offers a web page converted to RTF and RTFD as well, read again with other sizes. Only
            // without a web page are they the app's own.
            let order: [(UTType, NSAttributedString.DocumentType)] =
                offered.contains(UTType.html.identifier) ? [(.html, .html)] : [(.flatRTFD, .rtfd), (.rtf, .rtf)]
            for (type, documentType) in order where offered.contains(type.identifier) {
                if let data = board.data(forPasteboardType: type.identifier) {
                    return formattedFragment(data, type: documentType, plain: board.string)
                }
            }
            return board.string.flatMap { fragment(plain: $0) }
        }
    #endif

    /// Formatted text as blocks, or its plain text when the formatted text can't be read without loading what it
    /// refers to.
    private static func formattedFragment(_ data: Data, type: NSAttributedString.DocumentType, plain: String?)
        -> PastedFragment?
    {
        let fallback = { plain.flatMap { fragment(plain: $0, keepingEmptyLines: false) } }
        guard let text = text(data, type: type) else { return fallback() }
        return fragment(text) ?? fallback()
    }

    private static func text(_ data: Data, type: NSAttributedString.DocumentType) -> NSAttributedString? {
        #if os(iOS)
            // UIKit reads a table as a paragraph for each cell; its plain text keeps each row on a line.
            let source = String(decoding: data, as: UTF8.self)
            guard !source.contains("\\cell"), !source.lowercased().contains("<table") else { return nil }
        #endif
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        guard type == .html else {
            return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
        }
        guard let page = pageWithoutResources(String(decoding: data, as: UTF8.self)) else { return nil }
        options[.characterEncoding] = String.Encoding.utf8.rawValue
        return try? NSAttributedString(data: Data(page.utf8), options: options, documentAttributes: nil)
    }

    /// The page without anything reading it could load: pictures, media, frames, scripts, linked style sheets,
    /// fonts and background pictures. Nil when something the page refers to remains. A link to part of the page, or to a
    /// script, would go nowhere from the entry, so it is read as text rather than as underlined text without a link.
    private static func pageWithoutResources(_ source: String) -> String? {
        let removed = [
            "<(script|iframe|object|video|audio|svg|picture|noscript|template|canvas)\\b[^>]*>[\\s\\S]*?</\\1\\s*>",
            "<(img|link|source|track|embed|iframe|frame|input|base|meta)\\b[^>]*>",
            "\\shref\\s*=\\s*(\"(?!https?:|mailto:)[^\"]*\"|'(?!https?:|mailto:)[^']*')",
            "url\\s*\\([^)]*\\)", "@import[^;]*;?",
        ]
        var page = source
        for element in removed {
            page = page.replacingOccurrences(of: element, with: "", options: [.regularExpression, .caseInsensitive])
        }
        let resources = ["<img", "<link", "<iframe", "<object", "<embed", "<video", "<audio", "<frame", "url(", "src="]
        let lowered = page.lowercased()
        return resources.contains(where: lowered.contains) ? nil : page
    }

    /// The blocks read so far, and the marker widths of the list items enclosing the next one.
    @MainActor private struct Reader {
        let text: NSAttributedString
        let bodySize: CGFloat
        private(set) var pictures: [NSTextAttachment] = []
        private(set) var pictureBlocks: Set<UUID> = []
        private var blocks: [DocumentBlock] = []
        private var enclosing: [Int] = []
        /// How many items of each list have been read.
        private var itemCounts: [ObjectIdentifier: Int] = [:]
        private var continuesCode = false
        /// Empty lines after code, which belong to it when more code follows.
        private var blankCodeLines = 0
        private var table: TableReader?

        init(text: NSAttributedString, bodySize: CGFloat) {
            self.text = text
            self.bodySize = bodySize
        }

        mutating func finish() -> [DocumentBlock] {
            finishTable()
            return blocks
        }

        mutating func read(_ paragraph: NSRange) {
            let source = text.string as NSString
            var end = NSMaxRange(paragraph)
            while end > paragraph.location, [0x0A, 0x0D, 0x2028, 0x2029].contains(source.character(at: end - 1)) {
                end -= 1
            }
            let content = NSRange(location: paragraph.location, length: end - paragraph.location)
            let style =
                text.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            if readTableCell(content, style: style) { return }
            finishTable()
            if PastedRichText.isBlank(source.substring(with: content)) {
                // Empty lines are spacing in another app's layout; the entry spaces its own paragraphs. Within
                // code they are part of it.
                if continuesCode { blankCodeLines += 1 }
                return
            }
            if let lists = style?.textLists, let list = lists.last {
                endCode()
                readItem(content, list: list, depth: lists.count - 1)
                return
            }
            enclosing = []
            if PastedRichText.isMonospaced(text, in: content) {
                readCode(source.substring(with: content))
                return
            }
            endCode()
            if let written = PastedRichText.writtenMarker(source.substring(with: content)) {
                let body = NSRange(
                    location: content.location + written.length, length: content.length - written.length)
                var block = DocumentBlock(kind: written.number == nil ? "bullet" : "numbered")
                block.runs = PastedRichText.runs(text, in: body)
                block.listNumber = written.number
                blocks.append(block)
                return
            }
            readParagraph(content, style: style)
        }

        private mutating func readParagraph(_ content: NSRange, style: NSParagraphStyle?) {
            var start = content.location
            // Each picture is a paragraph of its own, between the text around it.
            text.enumerateAttribute(.attachment, in: content) { value, part, _ in
                guard let attachment = value as? NSTextAttachment else { return }
                appendText(NSRange(location: start, length: part.location - start), style: style)
                for _ in 0..<part.length {
                    let place = DocumentBlock(runs: [TextRun("\u{FFFC}")])
                    pictures.append(attachment)
                    pictureBlocks.insert(place.id)
                    blocks.append(place)
                }
                start = NSMaxRange(part)
            }
            appendText(NSRange(location: start, length: NSMaxRange(content) - start), style: style)
        }

        private mutating func appendText(_ range: NSRange, style: NSParagraphStyle?) {
            guard range.length > 0, !PastedRichText.isBlank((text.string as NSString).substring(with: range)) else {
                return
            }
            var block = DocumentBlock(runs: PastedRichText.runs(text, in: range))
            if let kind = headingKind(range) {
                block.kind = kind
                // A heading is drawn bold by its style; its words aren't bold text.
                for index in block.runs.indices { block.runs[index].bold = false }
            } else if let style, style.headIndent > 0, style.tailIndent != 0 {
                // Indented from both sides, as a web page's quotation is. A trailing indent is negative from the
                // trailing margin, or positive from the leading one, as RTF gives it.
                block.kind = "quote"
            }
            blocks.append(block)
        }

        private mutating func readItem(_ content: NSRange, list: NSTextList, depth: Int) {
            let source = text.string as NSString
            let marker = PastedRichText.markerRange(source, in: content)
            let body = NSRange(location: NSMaxRange(marker), length: NSMaxRange(content) - NSMaxRange(marker))
            guard !PastedRichText.isBlank(source.substring(with: body)) else { return }
            var block = DocumentBlock(kind: PastedRichText.kind(of: list), runs: PastedRichText.runs(text, in: body))
            let position = itemCounts[ObjectIdentifier(list), default: 0]
            itemCounts[ObjectIdentifier(list)] = position + 1
            if block.kind == "numbered" {
                // Formatted text from a web page writes each item's number; RTF leaves it to its list.
                let digits = source.substring(with: marker).filter(\.isNumber)
                block.listNumber = Int(digits) ?? list.startingItemNumber + position
            }
            let width = block.kind == "numbered" ? "\(block.listNumber ?? 1). ".count : 2
            // A nested item is indented to the text of the items around it, as Markdown requires.
            enclosing = Array(enclosing.prefix(depth))
            while enclosing.count < depth { enclosing.append(2) }
            if depth > 0 {
                let prefix = String(repeating: " ", count: enclosing.reduce(0, +))
                block.markdownPrefix = prefix
                block.markdownContinuation = prefix + String(repeating: " ", count: width)
                block.listIndents = enclosing
            }
            enclosing.append(width)
            blocks.append(block)
        }

        private mutating func readCode(_ line: String) {
            if continuesCode, var last = blocks.last, last.kind == "codeBlock" {
                let blank = String(repeating: "\n", count: blankCodeLines)
                last.runs = [TextRun((last.runs.first?.text ?? "") + "\n" + blank + line)]
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(DocumentBlock(kind: "codeBlock", runs: [TextRun(line)]))
            }
            continuesCode = true
            blankCodeLines = 0
        }

        private mutating func endCode() {
            continuesCode = false
            blankCodeLines = 0
        }

        /// A short paragraph set in a larger font than the text around it, as headings are. A longer one, such as
        /// an article's introduction, stays a paragraph.
        private func headingKind(_ content: NSRange) -> String? {
            guard content.length > 0, content.length <= 100, bodySize > 0 else { return nil }
            var smallest = CGFloat.greatestFiniteMagnitude
            text.enumerateAttribute(.font, in: content) { value, _, _ in
                smallest = min(smallest, (value as? PlatformFont)?.pointSize ?? bodySize)
            }
            let ratio = smallest / bodySize
            if ratio >= 1.75 { return "heading" }
            if ratio >= 1.35 { return "subheading" }
            return ratio >= 1.12 ? "heading3" : nil
        }

        /// Reads a table's cell into the table it belongs to; false when the paragraph isn't in a table.
        private mutating func readTableCell(_ content: NSRange, style: NSParagraphStyle?) -> Bool {
            #if os(macOS)
                guard let cell = style?.textBlocks.last as? NSTextTableBlock else { return false }
                endCode()
                enclosing = []
                if let table, table.table !== cell.table { finishTable() }
                var reader = table ?? TableReader(table: cell.table)
                reader.add(PastedRichText.runs(text, in: content), row: cell.startingRow, column: cell.startingColumn)
                table = reader
                return true
            #else
                return false
            #endif
        }

        private mutating func finishTable() {
            guard let table else { return }
            self.table = nil
            if let block = table.block { blocks.append(block) }
        }
    }

    /// A table's cells as they are read, a paragraph at a time.
    private struct TableReader {
        let table: AnyObject
        private var cells: [Int: [Int: [TextRun]]] = [:]

        init(table: AnyObject) { self.table = table }

        mutating func add(_ runs: [TextRun], row: Int, column: Int) {
            var cell = cells[row, default: [:]][column] ?? []
            if !cell.isEmpty, !runs.isEmpty { cell.append(TextRun(" ")) }
            cell += runs
            cells[row, default: [:]][column] = cell
        }

        /// The table as the entry's table, or nil when it has no text.
        var block: DocumentBlock? {
            let columns = (cells.values.flatMap(\.keys).max() ?? -1) + 1
            let rows = cells.keys.sorted().map { row in
                (0..<columns).map { column in cells[row]?[column] ?? [] }
            }
            guard columns > 0, rows.contains(where: { $0.contains { !$0.isEmpty } }) else { return nil }
            var block = DocumentBlock(kind: "table")
            block.table = DocumentTable(rows: rows, alignments: Array(repeating: nil, count: columns))
            return block
        }
    }

    /// A list item's bullet or number that another app wrote as text, as Word does, with the tab or spaces after it.
    fileprivate static func writtenMarker(_ line: String) -> (number: Int?, length: Int)? {
        let pattern =
            "^[ \\t]*(?:([•·◦▪▫‣⁃●○■□o§\u{F0B7}\u{F0A7}-])|([0-9]{1,3})[.)])(\\t[\\t \u{00A0}]*|[ \u{00A0}]{2,})"
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
            match.range.length < (line as NSString).length
        else { return nil }
        let digits = match.range(at: 2)
        let number = digits.location == NSNotFound ? nil : Int((line as NSString).substring(with: digits))
        return (number, match.range.length)
    }

    /// Text with nothing but spaces, including the no-break spaces word processors use for empty lines.
    fileprivate static func isBlank(_ text: String) -> Bool {
        text.allSatisfy { $0.isWhitespace }
    }

    /// The size most of the text is set in, which headings are compared with.
    private static func bodySize(_ text: NSAttributedString) -> CGFloat {
        var lengths: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? PlatformFont, !isMonospaced(font) else { return }
            // Sizes scaled when the text was read differ in their last digits.
            lengths[(font.pointSize * 2).rounded() / 2, default: 0] += range.length
        }
        return lengths.max { $0.value < $1.value }?.key ?? 0
    }

    private static func isMonospaced(_ text: NSAttributedString, in range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        var monospaced = true
        text.enumerateAttribute(.font, in: range) { value, _, stop in
            guard let font = value as? PlatformFont, isMonospaced(font) else {
                monospaced = false
                stop.pointee = true
                return
            }
        }
        return monospaced
    }

    private static func isMonospaced(_ font: PlatformFont) -> Bool {
        #if os(macOS)
            if font.fontDescriptor.symbolicTraits.contains(.monoSpace) { return true }
        #else
            if font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) { return true }
        #endif
        return ["Courier", "Menlo", "Monaco", "Mono"].contains { font.fontName.contains($0) }
    }

    /// The list marker the system writes before an item's text, such as "\t•\t" or "\t1.\t".
    private static func markerRange(_ source: NSString, in content: NSRange) -> NSRange {
        let line = source.substring(with: content)
        let leading = line.hasPrefix("\t") ? 1 : 0
        guard let tab = line.dropFirst(leading).firstIndex(of: "\t") else {
            return NSRange(location: content.location, length: 0)
        }
        let marker = line[line.index(line.startIndex, offsetBy: leading)..<tab]
        guard marker.count <= 8, !marker.contains(" ") else { return NSRange(location: content.location, length: 0) }
        return NSRange(location: content.location, length: line[...tab].utf16.count)
    }

    private static func kind(of list: NSTextList) -> String {
        switch list.markerFormat {
        case .box: return "task"
        case .check: return "checked"
        default: return list.isOrdered ? "numbered" : "bullet"
        }
    }

    /// The text's formatting as runs, with neighbouring runs of the same formatting joined. Text in a monospaced
    /// font within other text is code.
    private static func runs(_ text: NSAttributedString, in range: NSRange) -> [TextRun] {
        var result: [TextRun] = []
        let source = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, part, _ in
            var run = InsertedText.foreignRun(attributes, text: source.substring(with: part))
            if let font = attributes[.font] as? PlatformFont, isMonospaced(font), !isBlank(run.text) {
                run.code = true
                run.bold = false
                run.italic = false
            }
            if var last = result.last, sameFormatting(last, run) {
                last.text += run.text
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        return result
    }

    private static func sameFormatting(_ first: TextRun, _ second: TextRun) -> Bool {
        var first = first
        first.text = second.text
        return first == second
    }
}
