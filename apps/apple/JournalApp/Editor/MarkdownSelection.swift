import Foundation
import JournalCore

enum MarkdownSelection {
    /// Carries a selection from the rendered preview into `document.markdown`.
    static func toSource(_ range: NSRange, preview: NSAttributedString, document: JournalDocument) -> NSRange {
        guard let segments = document.markdownBlockSegments,
            let blocks = blockRanges(in: preview, ids: document.blocks.map(\.id))
        else { return map(range, from: preview.string, to: document.markdown) }
        return carry(
            range, from: (preview.string as NSString, blocks), to: (document.markdown as NSString, ranges(of: segments))
        )
    }

    /// Carries a selection from Markdown source into the preview rendered from `parsed`.
    static func toPreview(
        _ range: NSRange, source: String, parsed: JournalDocument, preview: NSAttributedString
    ) -> NSRange {
        guard let segments = parsed.markdownBlockSegments, segments.joined() == source,
            let blocks = blockRanges(in: preview, ids: parsed.blocks.map(\.id))
        else { return map(range, from: source, to: preview.string) }
        return carry(range, from: (source as NSString, ranges(of: segments)), to: (preview.string as NSString, blocks))
    }

    /// Match content across the syntax inserted or removed by a view change.
    /// Native text selections use UTF-16 offsets, including for emoji.
    static func map(_ range: NSRange, from original: String, to replacement: String) -> NSRange {
        let boundary = boundaries(from: original, to: replacement)
        let start = boundary(range.location, false)
        let end = range.length == 0 ? start : boundary(NSMaxRange(range), true)
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Where an offset lands after the change. A selection's end (`trailing`) stays after the last character it
    /// covered, so syntax that follows it isn't pulled in; a start or caret moves to the next kept character.
    private static func boundaries(from original: String, to replacement: String) -> (Int, Bool) -> Int {
        let old = Array(original.utf16)
        let new = Array(replacement.utf16)
        let changes = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let oldIndices = old.indices.filter { !removed.contains($0) }
        let newIndices = new.indices.filter { !inserted.contains($0) }
        let matches = Array(zip(oldIndices, newIndices))
        return { offset, trailing in
            if trailing, let previous = matches.last(where: { $0.0 < offset }) { return previous.1 + 1 }
            if let next = matches.first(where: { $0.0 >= offset }) { return next.1 }
            return matches.last.map { $0.1 + 1 } ?? min(offset, new.count)
        }
    }

    /// Both sides are split into the same blocks in the same order; each end of the selection moves to the same
    /// block and is matched only against that block's text, so repeated words elsewhere can't pull it away.
    private static func carry(
        _ range: NSRange, from: (text: NSString, blocks: [NSRange]), to: (text: NSString, blocks: [NSRange])
    ) -> NSRange {
        func point(_ offset: Int, trailing: Bool) -> Int {
            guard !from.blocks.isEmpty, !to.blocks.isEmpty else { return min(offset, to.text.length) }
            var index = from.blocks.lastIndex { $0.location <= offset } ?? 0
            // An offset exactly between blocks belongs to the end of the earlier one when it ends a selection.
            if trailing, index > 0, from.blocks[index].location == offset { index -= 1 }
            index = min(index, to.blocks.count - 1)
            let source = from.blocks[index]
            let target = to.blocks[index]
            let local = max(0, min(offset - source.location, source.length))
            let boundary = boundaries(from: from.text.substring(with: source), to: to.text.substring(with: target))
            return target.location + min(boundary(local, trailing), target.length)
        }
        let start = point(range.location, trailing: false)
        let end = range.length == 0 ? start : max(start, point(NSMaxRange(range), trailing: true))
        return NSRange(location: start, length: end - start)
    }

    private static func ranges(of segments: [String]) -> [NSRange] {
        var location = 0
        return segments.map { segment in
            defer { location += segment.utf16.count }
            return NSRange(location: location, length: segment.utf16.count)
        }
    }

    /// The preview's text for each block, in the order of `ids`, covering the whole text without gaps.
    private static func blockRanges(in text: NSAttributedString, ids: [UUID]) -> [NSRange]? {
        guard !ids.isEmpty else { return nil }
        var starts: [UUID: Int] = [:]
        text.enumerateAttribute(.journalBlockID, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let raw = value as? String, let id = UUID(uuidString: raw), starts[id] == nil else { return }
            starts[id] = range.location
        }
        // A block without characters (a trailing empty paragraph) takes the start of the block after it.
        var locations = Array(repeating: text.length, count: ids.count)
        var next = text.length
        for index in ids.indices.reversed() {
            if let start = starts[ids[index]] { next = start }
            locations[index] = next
        }
        guard starts.keys.contains(where: ids.contains), zip(locations, locations.dropFirst()).allSatisfy({ $0 <= $1 })
        else { return nil }
        locations[0] = 0
        return locations.indices.map { index in
            let end = index + 1 < locations.count ? locations[index + 1] : text.length
            return NSRange(location: locations[index], length: end - locations[index])
        }
    }
}
