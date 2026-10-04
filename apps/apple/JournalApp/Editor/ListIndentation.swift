import JournalCore
import SwiftUI

/// Increase and Decrease Indent for list items (docs/design/list-indentation-2026-10-04.md). An indent makes items
/// children of the item above them, as Markdown nests lists, so what the editor draws is what is saved and what the
/// entry shows when it is read again: a list's first item can't be indented, an item goes at most one level below the
/// item above it, nested items move with their parent, and numbered lists are numbered as Markdown reads them.
@MainActor enum ListIndentation {
    /// Which of the two commands would change the selection; the Format panel and menus enable them by it.
    struct Availability: Equatable {
        var increase = false
        var decrease = false
    }

    enum Direction { case increase, decrease }

    /// The list item kinds that nest; quotes and other blocks don't.
    static let kinds: Set<String> = ["bullet", "numbered", "task", "checked"]

    /// One list item's line: its paragraph, its block's list structure, and the prefix around the list (a quote's
    /// "> ", or nothing).
    struct Line {
        let range: NSRange
        var block: DocumentBlock
        let base: String
        var depth: Int { block.listIndents?.count ?? 0 }
    }

    /// The list around the selection: its lines, and which of them are selected.
    struct Region {
        var lines: [Line]
        var selected: Range<Int>
    }

    enum Scope {
        /// The selection has no list item: the keys keep their usual meaning.
        case none
        /// The selection is in a list that can't change safely: items of several lists are selected, or the list
        /// holds other content nested in an item (only from Markdown written elsewhere).
        case unsupported
        case list(Region)
    }

    // MARK: Availability and the edit

    static func availability(_ text: NSAttributedString, selection: NSRange, size: CGFloat) -> Availability {
        guard case .list(let region) = scope(text, selection: selection) else { return Availability() }
        return Availability(
            increase: plan(.increase, region, size: size) != nil, decrease: plan(.decrease, region, size: size) != nil)
    }

    /// The edit for Increase or Decrease Indent: nil when the selection has no list item; an edit that changes
    /// nothing when the command doesn't apply there (so Tab doesn't type into the item).
    static func edit(
        _ direction: Direction, text: NSAttributedString, selection: NSRange, size: CGFloat, images: [UUID: Data]
    ) -> MarkdownEditing.Edit? {
        let unchanged = MarkdownEditing.Edit(
            text: NSAttributedString(), range: NSRange(location: selection.location, length: 0), selection: selection)
        switch scope(text, selection: selection) {
        case .none: return nil
        case .unsupported: return unchanged
        case .list(let region):
            guard let planned = plan(direction, region, size: size),
                let replacement = replacement(planned, region: region, text: text, size: size, images: images)
            else { return unchanged }
            return MarkdownEditing.Edit(text: replacement.text, range: replacement.range, selection: selection)
        }
    }

    /// The level of the list item at `location` (1 at the top), for VoiceOver after an indent.
    static func level(_ text: NSAttributedString, at location: Int) -> Int? {
        guard text.length > 0 else { return nil }
        let source = text.string as NSString
        let paragraph = source.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
        guard case .item(let line) = read(text, paragraph: paragraph) else { return nil }
        return line.depth + 1
    }

    // MARK: Reading the list

    private enum Reading {
        case item(Line)
        /// A paragraph that belongs to a list item without being one (its text, a quote or code inside it), or an
        /// item this can't change safely (one holding a picture).
        case nested
        case outside
    }

    /// One decoder for every line: the menus check the caret's list on each selection change.
    private static let decoder = JournalCoding.decoder()

    private static func read(_ text: NSAttributedString, paragraph: NSRange) -> Reading {
        guard paragraph.length > 0 else { return .outside }
        let kind = text.attribute(.journalKind, at: paragraph.location, effectiveRange: nil) as? String ?? ""
        let stored = (text.attribute(.journalBlockMetadata, at: paragraph.location, effectiveRange: nil) as? Data)
            .flatMap { try? decoder.decode(DocumentBlock.self, from: $0) }
        guard kinds.contains(kind) else {
            return (stored?.listIndents ?? []).isEmpty ? .outside : .nested
        }
        var block = stored ?? DocumentBlock(kind: kind)
        block.kind = kind
        if let number = text.attribute(.journalListNumber, at: paragraph.location, effectiveRange: nil) as? Int {
            block.listNumber = number
        }
        var attachment = false
        text.enumerateAttribute(.attachment, in: paragraph) { value, _, stop in
            if value != nil {
                attachment = true
                stop.pointee = true
            }
        }
        guard !attachment, let base = base(of: block) else { return .nested }
        return .item(Line(range: paragraph, block: block, base: base))
    }

    /// The item's prefix without its list indentation; nil when the prefix doesn't end with that indentation.
    private static func base(of block: DocumentBlock) -> String? {
        let prefix = block.markdownPrefix ?? ""
        let indentation = (block.listIndents ?? []).reduce(0, +)
        guard indentation > 0 else { return prefix }
        guard prefix.hasSuffix(String(repeating: " ", count: indentation)) else { return nil }
        return String(prefix.dropLast(indentation))
    }

    static func scope(_ text: NSAttributedString, selection: NSRange) -> Scope {
        guard text.length > 0, selection.location >= 0, NSMaxRange(selection) <= text.length,
            !MarkdownEditing.isSource(text)
        else { return .none }
        let source = text.string as NSString
        // The selected paragraphs; a selection ending at a line's start doesn't include that line.
        let end = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let first = source.paragraphRange(for: NSRange(location: min(selection.location, text.length), length: 0))
        let last = source.paragraphRange(
            for: NSRange(location: min(max(end, selection.location), text.length), length: 0))
        var selected: [Reading] = []
        var offset = first.location
        repeat {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            selected.append(read(text, paragraph: paragraph))
            offset = NSMaxRange(paragraph)
        } while offset <= last.location && offset < source.length
        guard let firstItem = selected.firstIndex(where: { if case .item = $0 { return true } else { return false } }),
            let lastItem = selected.lastIndex(where: { if case .item = $0 { return true } else { return false } })
        else {
            return selected.contains { if case .nested = $0 { return true } else { return false } }
                ? .unsupported : .none
        }
        var lines: [Line] = []
        for reading in selected[firstItem...lastItem] {
            guard case .item(let line) = reading, line.base == lines.first?.base ?? line.base else {
                return .unsupported
            }
            lines.append(line)
        }
        return extended(Region(lines: lines, selected: 0..<lines.count), in: text)
    }

    /// The region with the rest of its list before and after the selected lines.
    private static func extended(_ region: Region, in text: NSAttributedString) -> Scope {
        guard let firstLine = region.lines.first, let lastLine = region.lines.last else { return .none }
        let source = text.string as NSString
        var result = region
        var start = firstLine.range.location
        while start > 0 {
            let paragraph = source.paragraphRange(for: NSRange(location: start - 1, length: 0))
            switch read(text, paragraph: paragraph) {
            case .item(let line) where line.base == firstLine.base:
                result.lines.insert(line, at: 0)
                result.selected = (result.selected.lowerBound + 1)..<(result.selected.upperBound + 1)
            case .nested: return .unsupported
            default: return extendedForward(result, from: NSMaxRange(lastLine.range), in: text)
            }
            start = paragraph.location
        }
        return extendedForward(result, from: NSMaxRange(lastLine.range), in: text)
    }

    private static func extendedForward(_ region: Region, from location: Int, in text: NSAttributedString) -> Scope {
        let source = text.string as NSString
        var result = region
        var offset = location
        while offset < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: offset, length: 0))
            switch read(text, paragraph: paragraph) {
            case .item(let line) where line.base == region.lines.first?.base:
                result.lines.append(line)
            case .nested: return .unsupported
            default: return .list(result)
            }
            offset = NSMaxRange(paragraph)
        }
        return .list(result)
    }

    // MARK: Planning

    /// Each line's parent: the nearest line above it one level up.
    private static func parents(_ depths: [Int]) -> [Int?] {
        var chain: [Int] = []
        return depths.indices.map { index in
            let depth = depths[index]
            if chain.count > depth { chain.removeLast(chain.count - depth) }
            let parent = depth > 0 && chain.count == depth ? chain.last : nil
            chain.append(index)
            return parent
        }
    }

    /// Whether every line is at most one level below the line above it, and the first is at the top.
    private static func valid(_ depths: [Int]) -> Bool {
        zip(depths.indices, depths).allSatisfy { index, depth in
            depth >= 0 && depth <= (index == 0 ? 0 : depths[index - 1] + 1)
        }
    }

    /// The region's lines after the command, or nil when it doesn't apply.
    static func plan(_ direction: Direction, _ region: Region, size: CGFloat) -> [Line]? {
        let lines = region.lines
        var depths = lines.map(\.depth)
        let before = parents(depths)
        guard let moved = movedLines(direction, region: region, depths: depths, parents: before) else { return nil }
        for index in lines.indices where moved[index] { depths[index] += direction == .increase ? 1 : -1 }
        if direction == .increase {
            let deepest = RichText.visibleNestingLevels(size: size)
            guard lines.indices.allSatisfy({ !moved[$0] || depths[$0] <= deepest }) else { return nil }
        }
        guard valid(depths) else { return nil }
        let after = parents(depths)
        var result = lines
        renumber(&result, depths: depths, moved: moved, before: before, after: after)
        restructure(&result, original: lines, parents: after)
        let changed = zip(lines, result).contains { old, new in
            old.block.listIndents != new.block.listIndents || old.block.listNumber != new.block.listNumber
        }
        return changed ? result : nil
    }

    /// Which lines move: the selected items that can, and every line nested under a moving line.
    private static func movedLines(_ direction: Direction, region: Region, depths: [Int], parents: [Int?]) -> [Bool]? {
        var moved = Array(repeating: false, count: depths.count)
        let selected = region.selected
        switch direction {
        case .increase:
            // The first selected item needs an item at its own level above it, to become its child.
            let first = selected.lowerBound
            guard
                let sibling = (0..<first).last(where: { depths[$0] <= depths[first] }),
                depths[sibling] == depths[first]
            else { return nil }
            for index in selected { moved[index] = true }
        case .decrease:
            for index in selected where depths[index] > 0 { moved[index] = true }
            guard moved.contains(true) else { return nil }
        }
        let shallowest = selected.map { depths[$0] }.min() ?? 0
        for index in selected.upperBound..<depths.count {
            guard depths[index] > shallowest else { break }
            if let parent = parents[index], moved[parent] { moved[index] = true }
        }
        return moved
    }

    /// Numbers numbered items as Markdown reads them, in the lists where something moved: each continues the numbered
    /// item before it at its level; an item that starts a list keeps its number, unless it moved or has a new parent,
    /// which starts it at 1.
    private static func renumber(_ lines: inout [Line], depths: [Int], moved: [Bool], before: [Int?], after: [Int?]) {
        // The lists that changed, by their parent (-1 for the top level).
        var changedLists = Set<Int>()
        for index in lines.indices where moved[index] || before[index] != after[index] {
            changedLists.insert(before[index] ?? -1)
            changedLists.insert(after[index] ?? -1)
        }
        var chain: [Int] = []
        for index in lines.indices {
            let depth = depths[index]
            if chain.count > depth + 1 { chain.removeLast(chain.count - depth - 1) }
            let sibling = chain.count == depth + 1 ? chain.last : nil
            if ordered(lines[index].block), changedLists.contains(after[index] ?? -1) {
                if let sibling, ordered(lines[sibling].block) {
                    lines[index].block.listNumber = (lines[sibling].block.listNumber ?? 0) + 1
                } else if moved[index] || before[index] != after[index] {
                    lines[index].block.listNumber = 1
                }
            }
            if chain.count == depth + 1 { chain[depth] = index } else { chain.append(index) }
        }
    }

    private static func ordered(_ block: DocumentBlock) -> Bool {
        block.kind == "numbered" || block.listMarker?.first?.isNumber == true
    }

    /// Gives each line the Markdown indentation of its new place: its parent's indentation and marker width. Lines
    /// whose place and number stay as they were keep their Markdown exactly.
    private static func restructure(_ lines: inout [Line], original: [Line], parents: [Int?]) {
        var indents: [[Int]] = []
        for index in lines.indices {
            let own = parents[index].map { indents[$0] + [lines[$0].block.listMarkerWidth] } ?? []
            indents.append(own)
            guard own != original[index].block.listIndents ?? [] else { continue }
            let prefix = lines[index].base + String(repeating: " ", count: own.reduce(0, +))
            lines[index].block.listIndents = own.isEmpty ? nil : own
            lines[index].block.markdownPrefix = prefix.isEmpty ? nil : prefix
        }
        for index in lines.indices
        where lines[index].block.listIndents != original[index].block.listIndents
            || lines[index].block.listNumber != original[index].block.listNumber
        {
            // Where the item's own further lines continue, after its marker (which a new number can widen).
            lines[index].block.markdownContinuation =
                (lines[index].block.markdownPrefix ?? "")
                + String(repeating: " ", count: lines[index].block.listMarkerWidth)
        }
    }

    // MARK: The text

    /// The changed lines rendered again, from the first changed line to the last, each keeping its text.
    private static func replacement(
        _ planned: [Line], region: Region, text: NSAttributedString, size: CGFloat, images: [UUID: Data]
    ) -> (text: NSAttributedString, range: NSRange)? {
        let changed = planned.indices.filter { index in
            let old = region.lines[index].block
            let new = planned[index].block
            return old.listIndents != new.listIndents || old.listNumber != new.listNumber
                || old.markdownPrefix != new.markdownPrefix || old.markdownContinuation != new.markdownContinuation
        }
        guard let first = changed.first, let last = changed.last else { return nil }
        var blocks: [DocumentBlock] = []
        for index in first...last {
            let line = planned[index]
            guard var block = RichText.document(text.attributedSubstring(from: line.range)).blocks.first,
                block.kind == line.block.kind
            else { return nil }
            block.listIndents = line.block.listIndents
            block.listNumber = line.block.listNumber
            block.markdownPrefix = line.block.markdownPrefix
            block.markdownContinuation = line.block.markdownContinuation
            blocks.append(block)
        }
        let range = NSRange(
            location: planned[first].range.location,
            length: NSMaxRange(planned[last].range) - planned[first].range.location)
        let rendered = RichText.paragraphReplacement(blocks, replacing: range, in: text, size: size, images: images)
        guard rendered.text.length == range.length else { return nil }
        return (rendered.text, range)
    }
}
