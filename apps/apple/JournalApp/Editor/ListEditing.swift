import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Editing list items and quotes, whose paragraphs hold only their text (docs/design/list-markers-2026-10-03.md).
/// Every change to text outside what is typed — splitting an item, continuing a list, joining lines, a final item's
/// own line break — is one of the editor's own replacements, so undo and redo restore it exactly.
extension RichText {
    /// The attributes a paragraph's characters share: its block, its number and its paragraph style.
    static let paragraphKeys: [NSAttributedString.Key] =
        [.journalKind, .journalBlockID, .journalBlockMetadata, .journalListNumber, .journalListColumn, .paragraphStyle]
        + ListAccessibility.keys

    /// `text` with the paragraph attributes of `paragraph`, keeping its own inline formatting and own end.
    static func reattributed(_ text: NSAttributedString, with paragraph: [NSAttributedString.Key: Any])
        -> NSMutableAttributedString
    {
        let result = NSMutableAttributedString(attributedString: text)
        let whole = NSRange(location: 0, length: result.length)
        guard whole.length > 0 else { return result }
        for key in paragraphKeys {
            if let value = paragraph[key] {
                result.addAttribute(key, value: value, range: whole)
            } else {
                result.removeAttribute(key, range: whole)
            }
        }
        return result
    }

    /// What typing continues with from `attributes`: bold, italic, underline, strikethrough and code, never what places
    /// text in a block, a link or a picture.
    private static let notContinued: Set<NSAttributedString.Key> = [
        .journalOwnEnd, .journalMarker, .attachment, .journalInlineImage, .link, .journalInertLink, .journalLinkTitle,
        .journalRawHTML, .journalImage, .journalTable, .journalStructuredBlock,
    ]
    private static func inline(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        attributes.filter { !paragraphKeys.contains($0.key) && !notContinued.contains($0.key) }
    }

    private static func block(_ attributes: [NSAttributedString.Key: Any]) -> DocumentBlock? {
        (attributes[.journalBlockMetadata] as? Data).flatMap {
            try? JournalCoding.decoder().decode(DocumentBlock.self, from: $0)
        }
    }

    /// Whether the paragraph at `range` reaches the end of the text with the last item's own line break.
    private static func endsWithOwnEnd(_ text: NSAttributedString, paragraph range: NSRange) -> Bool {
        NSMaxRange(range) == text.length && ListMarkers.hasOwnEnd(text)
    }

    /// Return in an empty list item: it moves out a level, or leaves the list for a plain line where it is. At the
    /// end of the text the item's own line break goes with it, so the line is the text's empty last line again.
    static func leavingItem(
        _ text: NSAttributedString, paragraph: NSRange, attributes: [NSAttributedString.Key: Any], size: CGFloat
    ) -> NewlineAction {
        let kind = attributes[.journalKind] as? String ?? "bullet"
        if kind == "quote" { return leavingQuote(text, paragraph: paragraph, attributes: attributes, size: size) }
        var block = block(attributes) ?? DocumentBlock(kind: kind)
        let ownEnd = endsWithOwnEnd(text, paragraph: paragraph)
        if let indent = block.listIndents?.popLast() {
            let number = attributes[.journalListNumber] as? Int ?? block.listNumber ?? 1
            block.markdownPrefix = String((block.markdownPrefix ?? "").dropLast(indent))
            let prefix = block.markdownPrefix ?? ""
            block.markdownContinuation =
                prefix + String(repeating: " ", count: kind == "numbered" ? "\(number). ".count : 2)
            var line = itemAttributes(block, number: number, size: size)
            let typing = line
            if ownEnd { line[.journalOwnEnd] = true }
            return NewlineAction(
                range: paragraph, replacement: NSAttributedString(string: "\n", attributes: line), nextKind: kind,
                typing: typing, caret: paragraph.location)
        }
        let plain = self.attributes(kind: "paragraph", size: size)
        return NewlineAction(
            range: paragraph,
            replacement: NSAttributedString(
                string: ownEnd || NSMaxRange(paragraph) == text.length ? "" : "\n",
                attributes: plain),
            nextKind: "paragraph", typing: plain, caret: paragraph.location)
    }

    /// Return in an empty quote line: it leaves the quote one level, as Backspace at the start of the line does
    /// (`ItemFormattingRemoval.removingOneLevel`): the line of an outer quote, the text of the list item around it,
    /// or a plain line where it is, so a quote cut in the middle splits in two. At the end of the text the quote's own
    /// line break goes with it, as for a list.
    private static func leavingQuote(
        _ text: NSAttributedString, paragraph: NSRange, attributes: [NSAttributedString.Key: Any], size: CGFloat
    ) -> NewlineAction {
        let original = block(attributes) ?? DocumentBlock(kind: "quote")
        let remaining = ItemFormattingRemoval.removingOneLevel(original)?.block ?? DocumentBlock()
        let ownEnd = endsWithOwnEnd(text, paragraph: paragraph)
        if remaining.kind == "quote" {
            let line = itemAttributes(remaining, number: nil, size: size)
            var ownLine = line
            if ownEnd { ownLine[.journalOwnEnd] = true }
            return NewlineAction(
                range: paragraph, replacement: NSAttributedString(string: "\n", attributes: ownLine),
                nextKind: "quote", typing: line, caret: paragraph.location)
        }
        let line = blockAttributes(remaining, size: size)
        return NewlineAction(
            range: paragraph,
            replacement: NSAttributedString(
                string: ownEnd || NSMaxRange(paragraph) == text.length ? "" : "\n", attributes: line),
            nextKind: "paragraph", typing: line, caret: paragraph.location)
    }

    /// Return at the very start of an item's text: a new empty item goes above it, and the item keeps its identity
    /// and checked state.
    static func itemAbove(
        _ text: NSAttributedString, paragraph: NSRange, attributes: [NSAttributedString.Key: Any], size: CGFloat
    ) -> NewlineAction {
        let kind = attributes[.journalKind] as? String ?? "bullet"
        let original = block(attributes) ?? DocumentBlock(kind: kind)
        let number = attributes[.journalListNumber] as? Int ?? original.listNumber ?? 1
        var above = original
        above.id = UUID()
        above.runs = []
        if above.kind == "checked" { above.kind = "task" }
        var item = attributes.filter { paragraphKeys.contains($0.key) }
        if kind == "numbered" {
            above.listNumber = number
            var moved = original
            moved.listNumber = number + 1
            item = itemAttributes(moved, number: number + 1, size: size).filter { paragraphKeys.contains($0.key) }
        }
        let style = inline(attributes)
        let replacement = NSMutableAttributedString(
            string: "\n", attributes: itemAttributes(above, number: number, size: size))
        replacement.append(reattributed(text.attributedSubstring(from: paragraph), with: item))
        return NewlineAction(
            range: paragraph, replacement: replacement, nextKind: kind, typing: style.merging(item) { $1 },
            caret: paragraph.location + 1)
    }

    /// `lines` typed, dictated or inserted at `range` in a list item or quote, where the first continues the item
    /// and each further line is another item of the list: a new identity, the next number, unchecked. The rest of
    /// the item's line follows the last one. Return is `["", ""]`. Nil when `range` isn't in an item.
    static func itemLines(
        _ text: NSAttributedString, range: NSRange, lines: [String], typing: [NSAttributedString.Key: Any],
        size: CGFloat
    ) -> NewlineAction? {
        let source = text.string as NSString
        guard NSMaxRange(range) <= source.length, source.length > 0 else { return nil }
        let head = source.paragraphRange(for: NSRange(location: range.location, length: 0))
        guard head.length > 0 else { return nil }
        let headAttributes = text.attributes(at: head.location, effectiveRange: nil)
        let kind = headAttributes[.journalKind] as? String ?? ""
        guard ListMarkers.itemKinds.contains(kind) else { return nil }
        let tailStart = NSMaxRange(range)
        // Return over a selection that ends with a line break (a whole line, as triple-click selects it) leaves the
        // next line as it is.
        let endsLine = range.length > 0 && lines.last == "" && source.character(at: tailStart - 1) == 0x0A
        let tailEnd =
            tailStart < source.length && !endsLine
            ? NSMaxRange(source.paragraphRange(for: NSRange(location: tailStart, length: 0))) : tailStart
        guard isText(text, in: NSRange(location: tailStart, length: tailEnd - tailStart)) else { return nil }
        var block = block(headAttributes) ?? DocumentBlock(kind: kind)
        var number = headAttributes[.journalListNumber] as? Int ?? block.listNumber ?? 1
        var current = headAttributes.filter { paragraphKeys.contains($0.key) }
        let style = inline(typing)
        // Line breaks are in the paragraph's own font, as rendering puts them.
        let lineBreak: [NSAttributedString.Key: Any] = [
            .font: font(size: (headAttributes[.font] as? PlatformFont)?.pointSize ?? size),
            .foregroundColor: PlatformColor.labelColorCompat,
        ]
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: lineBreak.merging(current) { $1 }))
                block.id = UUID()
                block.runs = []
                if block.kind == "checked" { block.kind = "task" }
                if block.kind == "numbered" {
                    number += 1
                    block.listNumber = number
                }
                current = itemAttributes(block, number: number, size: size).filter { paragraphKeys.contains($0.key) }
            }
            result.append(NSAttributedString(string: line, attributes: style.merging(current) { $1 }))
        }
        let caret = range.location + result.length
        let tail = reattributed(
            text.attributedSubstring(from: NSRange(location: tailStart, length: tailEnd - tailStart)), with: current)
        result.append(tail)
        if tail.length == 0, tailEnd == source.length, lines.count > 1 {
            // A new last item has a line break of its own.
            var end = lineBreak.merging(current) { $1 }
            end[.journalOwnEnd] = true
            result.append(NSAttributedString(string: "\n", attributes: end))
        }
        return NewlineAction(
            range: NSRange(location: range.location, length: tailEnd - range.location), replacement: result,
            nextKind: block.kind, typing: style.merging(current) { $1 }, caret: caret)
    }

    /// Lines the text system inserts into a list item or quote with other text (dictation, a drop, Writing Tools):
    /// each new line's inserted characters become the next item of the list, keeping their own formatting. Only the
    /// inserted characters change, so the text system's own undo takes it all back. A line break at the very end of
    /// the inserted text leaves the rest of the item as it was, which reading gives an identity of its own.
    /// Lines that arrive as paragraphs of their own (`keeping`: text that undo or redo puts back, or a drag within
    /// the entry) keep what they are.
    static func continueInsertedLines(
        _ storage: NSTextStorage, inserted: NSRange, size: CGFloat, keeping: Set<Int> = []
    ) {
        let source = storage.string as NSString
        guard inserted.length > 1, NSMaxRange(inserted) <= source.length else { return }
        var position = inserted.location
        while position < NSMaxRange(inserted) {
            let lineBreak = source.range(
                of: "\n", range: NSRange(location: position, length: NSMaxRange(inserted) - position))
            guard lineBreak.location != NSNotFound, NSMaxRange(lineBreak) < NSMaxRange(inserted) else { return }
            position = NSMaxRange(lineBreak)
            guard !keeping.contains(position) else { continue }
            let previous = source.paragraphRange(for: NSRange(location: lineBreak.location, length: 0))
            let head = storage.attributes(at: previous.location, effectiveRange: nil)
            let kind = head[.journalKind] as? String ?? ""
            guard ListMarkers.itemKinds.contains(kind) else { continue }
            var item = block(head) ?? DocumentBlock(kind: kind)
            item.id = UUID()
            item.runs = []
            if item.kind == "checked" { item.kind = "task" }
            let number = (head[.journalListNumber] as? Int ?? item.listNumber ?? 1) + 1
            if item.kind == "numbered" { item.listNumber = number }
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            let own = NSIntersectionRange(paragraph, inserted)
            let attributes = itemAttributes(item, number: number, size: size)
            for key in paragraphKeys {
                if let value = attributes[key] {
                    storage.addAttribute(key, value: value, range: own)
                } else {
                    storage.removeAttribute(key, range: own)
                }
            }
        }
    }

    /// What typing continues with after a paragraph style was chosen in the Format panel or popover: the style's
    /// attributes and the paragraph's own block, so an emptied line keeps one identity (and number) while it's typed.
    static func styledTyping(kind: String, at caret: Int, in storage: NSAttributedString, size: CGFloat)
        -> [NSAttributedString.Key: Any]
    {
        var typing = attributes(kind: kind, size: size)
        if caret < storage.length {
            let paragraph = storage.attributes(at: caret, effectiveRange: nil).filter { paragraphKeys.contains($0.key) }
            typing.merge(paragraph) { $1 }
        }
        return HiddenMarkers.typingAttributes(typing, size: size)
    }

    /// The starts of the inserted lines that arrived as blocks of their own, before inserted text takes on the block
    /// it lands in: their characters name another block than the line before them. Typed or dictated lines arrive
    /// with no block or the item's own.
    static func linesWithTheirOwnBlocks(_ storage: NSTextStorage, inserted: NSRange) -> Set<Int> {
        let source = storage.string as NSString
        guard inserted.length > 1, NSMaxRange(inserted) <= source.length else { return [] }
        var own = Set<Int>()
        let head = source.paragraphRange(for: NSRange(location: inserted.location, length: 0))
        var before = storage.attribute(.journalBlockID, at: head.location, effectiveRange: nil) as? String
        var position = inserted.location
        while position < NSMaxRange(inserted) {
            let lineBreak = source.range(
                of: "\n", range: NSRange(location: position, length: NSMaxRange(inserted) - position))
            guard lineBreak.location != NSNotFound, NSMaxRange(lineBreak) < NSMaxRange(inserted) else { break }
            position = NSMaxRange(lineBreak)
            let arrived = storage.attribute(.journalBlockID, at: position, effectiveRange: nil) as? String
            if let arrived, arrived != before { own.insert(position) }
            if arrived != nil { before = arrived }
        }
        return own
    }

    /// Gives each numbered list around `range` one column that fits its widest number and a space, as lists in
    /// TextEdit and Pages leave room for theirs: two-digit numbers no longer touch their text, and the text of every
    /// item lines up. A list whose numbers fit the shared list column keeps it, so it lines up with bullets and
    /// checklists. A list is the numbered items at one nesting level, with deeper items between them.
    static func alignNumberedLists(_ text: NSMutableAttributedString, around range: NSRange, size: CGFloat) {
        let source = text.string as NSString
        guard source.length > 0 else { return }
        func paragraph(at location: Int) -> NSRange {
            source.paragraphRange(for: NSRange(location: min(location, source.length - 1), length: 0))
        }
        func isItem(_ location: Int) -> Bool {
            let kind = text.attribute(.journalKind, at: location, effectiveRange: nil) as? String ?? ""
            return ListMarkers.itemKinds.contains(kind) && kind != "quote"
        }
        // The list items around the change.
        var start = paragraph(at: range.location).location
        while start > 0, isItem(paragraph(at: start - 1).location) { start = paragraph(at: start - 1).location }
        var end = NSMaxRange(paragraph(at: max(range.location, NSMaxRange(range) - 1)))
        while end < source.length, isItem(end) { end = NSMaxRange(paragraph(at: end)) }
        struct Item {
            let range: NSRange
            let nesting: CGFloat
            let width: CGFloat
            let size: CGFloat
        }
        var groups: [[Item]] = []
        var open: [CGFloat: Int] = [:]
        var location = start
        while location < end {
            let line = paragraph(at: location)
            defer { location = max(NSMaxRange(line), location + 1) }
            let attributes = text.attributes(at: line.location, effectiveRange: nil)
            let kind = attributes[.journalKind] as? String ?? ""
            guard ListMarkers.itemKinds.contains(kind), kind != "quote",
                let style = attributes[.paragraphStyle] as? NSParagraphStyle
            else {
                open = [:]
                continue
            }
            let pointSize = (attributes[.font] as? PlatformFont)?.pointSize ?? size
            let column = attributes[.journalListColumn] as? CGFloat ?? listColumn(size: pointSize)
            let nesting = (style.headIndent - column).rounded()
            open = open.filter { $0.key <= nesting }
            guard kind == "numbered" else {
                open[nesting] = nil
                continue
            }
            let number = attributes[.journalListNumber] as? Int ?? 1
            let font = ListMarkers.font(size: pointSize)
            let width = ("\(number)." as NSString).size(withAttributes: [.font: font]).width
            let item = Item(range: line, nesting: nesting, width: width, size: pointSize)
            if let index = open[nesting] {
                groups[index].append(item)
            } else {
                open[nesting] = groups.count
                groups.append([item])
            }
        }
        for group in groups {
            guard let first = group.first else { continue }
            let font = ListMarkers.font(size: first.size)
            let space = (" " as NSString).size(withAttributes: [.font: font]).width
            let widest = group.map(\.width).max() ?? 0
            let shared = listColumn(size: first.size)
            let column = max(shared, (widest + space).rounded(.up))
            for item in group {
                text.enumerateAttribute(.paragraphStyle, in: item.range) { value, part, _ in
                    guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else {
                        return
                    }
                    guard style.headIndent != item.nesting + column || style.firstLineHeadIndent != style.headIndent
                    else { return }
                    style.headIndent = item.nesting + column
                    style.firstLineHeadIndent = item.nesting + column
                    text.addAttribute(.paragraphStyle, value: style, range: part)
                }
                if column == shared {
                    text.removeAttribute(.journalListColumn, range: item.range)
                } else {
                    text.addAttribute(.journalListColumn, value: column, range: item.range)
                }
            }
        }
    }

    /// What typing continues with after one of the editor's own list edits: the action's typing attributes, with the
    /// paragraph style a numbered list's column gave the line the caret is on (a number wider than the others).
    static func typing(after action: NewlineAction, in text: NSAttributedString, size: CGFloat)
        -> [NSAttributedString.Key: Any]
    {
        var typing = action.typing ?? attributes(kind: action.nextKind, size: size)
        if let caret = action.caret, caret < text.length, typing[.journalKind] as? String == "numbered" {
            let line = text.attributes(at: caret, effectiveRange: nil)
            typing[.paragraphStyle] = line[.paragraphStyle]
            typing[.journalListColumn] = line[.journalListColumn]
        }
        return typing
    }

    /// Whether `range` holds only text: no picture, table, rule or code, which never join a list item.
    private static func isText(_ text: NSAttributedString, in range: NSRange) -> Bool {
        guard range.length > 0 else { return true }
        var plain = true
        for key in [NSAttributedString.Key.attachment, .journalStructuredBlock, .journalMarker, .journalTable] {
            text.enumerateAttribute(key, in: range) { value, _, stop in
                if value != nil {
                    plain = false
                    stop.pointee = true
                }
            }
        }
        return plain
    }

    /// Deleting or typing over text that joins two lines, when a list item or quote is one of them: the joined text
    /// takes the paragraph attributes of the line where the selection starts, as in TextEdit and Notes, so an item's
    /// can't come back later. Nil when the text view can make the change itself: no line break is removed, a deletion
    /// removes the first line whole, the typed text has lines of its own, or no item is involved. (An input method
    /// composing over such a selection is left to the text system; the editor doesn't ask then.)
    static func joining(
        _ text: NSAttributedString, range: NSRange, replacement: String, typing: [NSAttributedString.Key: Any]
    ) -> NewlineAction? {
        let source = text.string as NSString
        guard range.length > 0, !EditorReading.breaksLines(replacement), NSMaxRange(range) < source.length,
            EditorReading.breaksLines(source.substring(with: range))
        else { return nil }
        let head = source.paragraphRange(for: NSRange(location: range.location, length: 0))
        guard range.location > head.location || !replacement.isEmpty else { return nil }
        let tail = source.paragraphRange(for: NSRange(location: NSMaxRange(range), length: 0))
        let headAttributes = text.attributes(at: head.location, effectiveRange: nil)
        let tailAttributes = text.attributes(at: tail.location, effectiveRange: nil)
        let kinds = [headAttributes, tailAttributes].map { $0[.journalKind] as? String ?? "paragraph" }
        guard kinds.contains(where: ListMarkers.itemKinds.contains),
            headAttributes[.journalBlockID] as? String != tailAttributes[.journalBlockID] as? String,
            isText(text, in: NSRange(location: head.location, length: range.location - head.location)),
            isText(text, in: NSRange(location: NSMaxRange(range), length: NSMaxRange(tail) - NSMaxRange(range)))
        else { return nil }
        let paragraph = headAttributes.filter { paragraphKeys.contains($0.key) }
        let result = NSMutableAttributedString(
            string: replacement, attributes: inline(typing).merging(paragraph) { $1 })
        let caret = range.location + result.length
        result.append(
            reattributed(
                text.attributedSubstring(
                    from: NSRange(location: NSMaxRange(range), length: NSMaxRange(tail) - NSMaxRange(range))),
                with: paragraph))
        return NewlineAction(
            range: NSRange(location: range.location, length: NSMaxRange(tail) - range.location),
            replacement: result, nextKind: kinds[0], typing: inline(typing).merging(paragraph) { $1 }, caret: caret)
    }

    /// The blocks of the whole paragraphs at `range`, without the empty paragraph a line break at its end would start.
    static func paragraphBlocks(_ text: NSAttributedString, in range: NSRange) -> [DocumentBlock] {
        guard range.length > 0 else { return [DocumentBlock()] }
        let part = text.attributedSubstring(from: range)
        var blocks = document(part).blocks
        if part.string.hasSuffix("\n"), !ListMarkers.hasOwnEnd(part), blocks.count > 1 { blocks.removeLast() }
        return blocks
    }

    /// Whole paragraphs at `range` (each with its line break, if it has one) rendered again as `blocks`: the line
    /// break carries the last block's attributes, and the last item of the text keeps its own line break. Returns the
    /// text and how much of it comes before that line break.
    static func paragraphReplacement(
        _ blocks: [DocumentBlock], replacing range: NSRange, in text: NSAttributedString, size: CGFloat,
        images: [UUID: Data], layout: ImageLayout = .init()
    ) -> (text: NSMutableAttributedString, content: Int) {
        let result = NSMutableAttributedString(
            attributedString: render(.init(blocks: blocks), size: size, images: images, layout: layout, endsText: false)
        )
        let content = result.length
        let source = text.string as NSString
        let breaks = range.length > 0 && source.character(at: NSMaxRange(range) - 1) == 0x0A
        let atEnd = NSMaxRange(range) == source.length
        guard let last = blocks.last else { return (result, content) }
        let item = ListMarkers.itemKinds.contains(last.kind)
        guard breaks && !(atEnd && ListMarkers.hasOwnEnd(text)) || atEnd && item else { return (result, content) }
        // The number the last block was drawn with, counted as `render` counts it.
        var number = 0
        for block in blocks { number = block.kind == "numbered" ? number + 1 : 0 }
        var attributes =
            item
            ? itemAttributes(last, number: last.listNumber ?? number, size: size) : blockAttributes(last, size: size)
        if atEnd && item { attributes[.journalOwnEnd] = true }
        result.append(NSAttributedString(string: "\n", attributes: attributes))
        return (result, content)
    }

    /// The range one of the editor's own changes replaces: text that ends with a line break, put just before the
    /// last item's own line break, takes its place, so that line break doesn't become an empty item of its own. A
    /// range that ends with a line break of its own ends the paragraph before an empty last item, which stays.
    static func replacedRange(_ range: NSRange, with text: NSAttributedString, in storage: NSAttributedString)
        -> NSRange
    {
        let source = storage.string as NSString
        guard text.string.hasSuffix("\n"), NSMaxRange(range) == storage.length - 1, ListMarkers.hasOwnEnd(storage),
            range.length == 0 || source.character(at: NSMaxRange(range) - 1) != 0x0A
        else { return range }
        return NSRange(location: range.location, length: range.length + 1)
    }

    /// The text's last paragraph after one of the editor's own changes: a list item or quote ends with its own line
    /// break, carrying its paragraph's attributes; any other paragraph doesn't. Tags left elsewhere are removed.
    static func repairEnd(_ storage: NSTextStorage) {
        let whole = NSRange(location: 0, length: storage.length)
        var tagged: [NSRange] = []
        storage.enumerateAttribute(.journalOwnEnd, in: whole) { value, range, _ in
            if value != nil { tagged.append(range) }
        }
        for range in tagged {
            // Only the text's last character can be an own end.
            let stale =
                NSMaxRange(range) == storage.length
                ? NSRange(location: range.location, length: range.length - 1) : range
            if stale.length > 0 { storage.removeAttribute(.journalOwnEnd, range: stale) }
        }
        guard storage.length > 0, !MarkdownEditing.isSource(storage) else { return }
        let source = storage.string as NSString
        let ownEnd = ListMarkers.hasOwnEnd(storage)
        if source.character(at: source.length - 1) == 0x0A, !ownEnd { return }
        let last = source.paragraphRange(for: NSRange(location: source.length - 1, length: 0))
        let attributes = storage.attributes(at: last.location, effectiveRange: nil)
        let item = ListMarkers.itemKinds.contains(attributes[.journalKind] as? String ?? "")
        var end = attributes.filter { paragraphKeys.contains($0.key) }
        end[.font] = font(size: (attributes[.font] as? PlatformFont)?.pointSize ?? 17)
        end[.foregroundColor] = PlatformColor.labelColorCompat
        end[.journalOwnEnd] = true
        switch (ownEnd, item) {
        case (true, true):
            storage.addAttributes(end, range: NSRange(location: source.length - 1, length: 1))
        case (true, false):
            storage.deleteCharacters(in: NSRange(location: source.length - 1, length: 1))
        case (false, true):
            storage.append(NSAttributedString(string: "\n", attributes: end))
        case (false, false):
            break
        }
    }

    /// What typing at a caret at `location` continues with, where the text system's own choice is wrong: the empty
    /// last line after a list is a plain line, and the start of a list item continues the item, not the line before.
    static func typingAttributes(_ text: NSAttributedString, at location: Int, size: CGFloat)
        -> [NSAttributedString.Key: Any]?
    {
        if continuesAfterList(text, at: location) {
            var plain = attributes(kind: "paragraph", size: size)
            plain[.journalBlockID] = UUID().uuidString
            return plain
        }
        // At a line's start, typing continues that line, as AppKit already does; UIKit takes the line before it.
        guard location < text.length,
            location == 0 || (text.string as NSString).character(at: location - 1) == 0x0A,
            text.attribute(.journalKind, at: location, effectiveRange: nil) != nil
        else { return nil }
        return HiddenMarkers.typingAttributes(text.attributes(at: location, effectiveRange: nil), size: size)
    }

    /// Whether typing at `location` is on the empty last line after a list, which is a plain line.
    static func continuesAfterList(_ text: NSAttributedString, at location: Int) -> Bool {
        guard location == text.length, location > 0, !ListMarkers.hasOwnEnd(text),
            (text.string as NSString).character(at: location - 1) == 0x0A
        else { return false }
        return ListMarkers.itemKinds.contains(
            text.attribute(.journalKind, at: location - 1, effectiveRange: nil) as? String ?? "")
    }

    /// The selection as other apps take it: TextKit 1's list representation, where each list item whose start is
    /// selected begins with its marker and a tab, inside a text list, as TextEdit and Pages write lists.
    static func otherAppsText(_ text: NSAttributedString, range: NSRange) -> NSAttributedString {
        let source = text.string as NSString
        var end = NSMaxRange(range)
        if end == text.length, ListMarkers.hasOwnEnd(text), end > range.location { end -= 1 }
        let selected = NSRange(location: range.location, length: end - range.location)
        let result = NSMutableAttributedString(attributedString: text.attributedSubstring(from: selected))
        var items: [(paragraph: NSRange, marker: String, format: NSTextList.MarkerFormat, kind: String)] = []
        var position = selected.location
        while position < NSMaxRange(selected) {
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            position = max(NSMaxRange(paragraph), position + 1)
            guard paragraph.location >= selected.location else { continue }
            let attributes = text.attributes(at: paragraph.location, effectiveRange: nil)
            let kind = attributes[.journalKind] as? String ?? ""
            let number = attributes[.journalListNumber] as? Int ?? 1
            let entry: (String, NSTextList.MarkerFormat)? =
                switch kind {
                case "bullet": ("•", .disc)
                case "numbered": ("\(number).", .decimal)
                case "task": ("☐", .box)
                case "checked": ("☑", .check)
                default: nil
                }
            guard let entry else { continue }
            items.append((NSIntersectionRange(paragraph, selected), entry.0, entry.1, kind))
        }
        var lists: [NSTextList] = []
        for (index, item) in items.enumerated() {
            let continues =
                index > 0 && items[index - 1].kind == item.kind
                && NSMaxRange(items[index - 1].paragraph) == item.paragraph.location
            if !continues || lists.isEmpty {
                lists.append(NSTextList(markerFormat: item.format, options: 0))
            } else {
                lists.append(lists[lists.count - 1])
            }
        }
        for (item, list) in zip(items, lists).reversed() {
            let local = NSRange(location: item.paragraph.location - selected.location, length: item.paragraph.length)
            let size = (result.attribute(.font, at: local.location, effectiveRange: nil) as? PlatformFont)?.pointSize
            let style =
                (result.attribute(.paragraphStyle, at: local.location, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.textLists = [list]
            // The marker where the editor draws it, then a tab to the item's text, so wrapped lines line up with it
            // in other apps too.
            let column =
                result.attribute(.journalListColumn, at: local.location, effectiveRange: nil) as? CGFloat
                ?? listColumn(size: size ?? 17)
            style.firstLineHeadIndent = max(0, style.headIndent - column)
            style.tabStops = [NSTextTab(textAlignment: .natural, location: style.headIndent)]
            result.addAttribute(.paragraphStyle, value: style, range: local)
            result.insert(
                NSAttributedString(
                    string: item.marker + "\t",
                    attributes: [
                        .font: ListMarkers.font(size: size ?? 17), .foregroundColor: PlatformColor.labelColorCompat,
                        .paragraphStyle: style,
                    ]), at: local.location)
        }
        return result
    }
}
