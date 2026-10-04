import Foundation
import Markdown

/// Markdown is the body; this metadata preserves identities and local image media types.
struct MarkdownMetadata: Codable, Equatable, Sendable {
    var blockIDs: [UUID]
    var segmentLengths: [Int]?
    var imageTypes: [String: String]
}

extension MarkdownMetadata {
    private enum CodingKeys: String, CodingKey { case blockIDs, segmentLengths, imageTypes }
    /// Another client may leave out identities or image types. A value of an unexpected type is still an error.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        blockIDs = try values.decodeIfPresent([UUID].self, forKey: .blockIDs) ?? []
        segmentLengths = try values.decodeIfPresent([Int].self, forKey: .segmentLengths)
        imageTypes = try values.decodeIfPresent([String: String].self, forKey: .imageTypes) ?? [:]
    }
}

extension JournalDocument {
    /// Marks content this client can show but must not rewrite; its record keeps the original bytes.
    static let unfamiliarVersion = Int.max

    public init(markdown: String) {
        // New Markdown, such as an inserted fragment, gets new identities so repeated insertions stay distinct.
        self.init(markdown: markdown, metadata: nil, freshIdentities: true)
    }
    init(markdown: String, metadata: MarkdownMetadata?, freshIdentities: Bool = false) {
        var parsed = MarkdownReader.read(markdown)
        if !parsed.requiresSource, let metadata, let segmented = Self.segmented(parsed, markdown, metadata) {
            parsed = segmented
        }
        var blocks = Self.identified(
            parsed.blocks, stored: metadata?.blockIDs ?? [], segments: parsed.segments, fresh: freshIdentities)
        if let types = metadata?.imageTypes {
            for index in blocks.indices {
                if let id = blocks[index].attachmentID { blocks[index].mediaType = types[id.uuidString.lowercased()] }
            }
            Self.mapImageRuns(in: &blocks) { run in
                var run = run
                if let id = run.imageAttachmentID { run.imageMediaType = types[id.uuidString.lowercased()] }
                return run
            }
        }
        version = 2
        self.blocks = blocks
        source = markdown
        sourceSegments = parsed.segments
        sourceLeading = parsed.leading
        sourceTails = parsed.tails
        requiresSource = parsed.requiresSource
    }
    /// Splits the source along stored segment lengths, which keep native paragraph boundaries and empty paragraphs.
    /// Nil unless each segment holds at most one block and that block ends within it.
    private static func segmented(_ parsed: MarkdownReader.Result, _ markdown: String, _ metadata: MarkdownMetadata)
        -> MarkdownReader.Result?
    {
        let bytes = Array(markdown.utf8)
        guard let lengths = metadata.segmentLengths, lengths.count == metadata.blockIDs.count,
            lengths.allSatisfy({ (0...bytes.count).contains($0) }),
            lengths.reduce(UInt64(0), { $0 + UInt64($1) }) == UInt64(bytes.count)
        else { return nil }
        var bounds: [Int] = []
        var found: [Int?] = []
        var offset = 0
        var next = 0
        // Block starts ascend, so one pass assigns each to its segment.
        for length in lengths {
            let end = offset + length
            var block: Int?
            while next < parsed.starts.count, parsed.starts[next] < end {
                guard block == nil else { return nil }
                block = next
                next += 1
            }
            if let block, parsed.ends[block] > end { return nil }
            // Text before a block belongs to the previous segment's tail, so rewriting the block keeps it.
            bounds.append(bounds.isEmpty ? 0 : block.map { parsed.starts[$0] } ?? offset)
            found.append(block)
            offset = end
        }
        var result = MarkdownReader.Result()
        result.leading = found.first.flatMap { $0 } == nil ? "" : parsed.leading
        for index in bounds.indices {
            let end = index + 1 < bounds.count ? bounds[index + 1] : bytes.count
            guard let segment = String(bytes: bytes[bounds[index]..<end], encoding: .utf8) else { return nil }
            let blockEnd = found[index].map { parsed.ends[$0] } ?? bounds[index]
            result.blocks.append(found[index].map { parsed.blocks[$0] } ?? DocumentBlock())
            result.segments.append(segment)
            result.starts.append(bounds[index])
            result.ends.append(blockEnd)
            result.tails.append(String(decoding: bytes[blockEnd..<end], as: UTF8.self))
        }
        return result
    }
    /// Stored identities where present. Otherwise an identity derived from the block's position and source, so
    /// reading the same Markdown again, such as a record another client saved without metadata, gives an equal
    /// document.
    private static func identified(_ blocks: [DocumentBlock], stored: [UUID], segments: [String], fresh: Bool)
        -> [DocumentBlock]
    {
        var result = blocks
        var used = Set<UUID>()
        for index in result.indices {
            let segment = index < segments.count ? segments[index] : ""
            var attempt = 0
            var identity = result[index].id
            if index < stored.count {
                identity = stored[index]
            } else if !fresh {
                identity = derivedIdentity("journal:block:\(index):\(attempt)\n" + segment)
            }
            while used.contains(identity) {
                attempt += 1
                identity = fresh ? UUID() : derivedIdentity("journal:block:\(index):\(attempt)\n" + segment)
            }
            used.insert(identity)
            result[index].id = identity
        }
        return result
    }
    public var markdown: String { source ?? MarkdownWriter.segments(blocks).joined() }
    public func replacingMarkdown(_ value: String) -> JournalDocument {
        if value == markdown { return self }
        var metadata = markdownMetadata
        metadata.segmentLengths = nil
        return JournalDocument(markdown: value, metadata: metadata)
    }
    public func insertingMarkdown(_ value: String, after blockID: UUID?) -> (text: String, caret: Int) {
        let segments =
            sourceSegments.count == blocks.count ? sourceSegments : MarkdownWriter.segments(blocks)
        let index = blockID.flatMap { id in blocks.firstIndex { $0.id == id } } ?? (blocks.count - 1)
        let before = index >= 0 ? segments.prefix(index + 1).joined() : ""
        let after = segments.dropFirst(max(0, index + 1)).joined()
        let separator =
            MarkdownText.endsWithBlankLine(before) ? "" : MarkdownText.endsWithLineEnding(before) ? "\n" : "\n\n"
        let prefix = before.isEmpty ? before : before + separator
        let inserted = prefix + value
        return (inserted + (after.isEmpty ? "" : "\n\n" + after), inserted.utf16.count)
    }
    public var requiresMarkdownSource: Bool { requiresSource }
    /// Each block's text within `markdown`, in block order, so a position can be carried between the Markdown
    /// source and the rendered blocks. Nil when the source can't be split along the blocks.
    public var markdownBlockSegments: [String]? {
        let segments =
            sourceSegments.count == blocks.count ? sourceSegments : MarkdownWriter.segments(blocks)
        guard !requiresSource, !segments.isEmpty, segments.joined() == markdown else { return nil }
        return segments
    }
    /// Applies the editor's blocks. Unchanged blocks keep their source bytes; changed and new blocks are written
    /// again, and blank lines are added only where needed to keep every block apart when the Markdown is read back.
    /// A document that can only be edited as Markdown source has no blocks that stand for all of its text, so it is
    /// returned unchanged: callers edit it with `replacingMarkdown` (the editor shows its source, and image
    /// descriptions are refused for it). Debug builds stop here so a new caller can't drop edits unnoticed.
    public func applyingRichEdit(_ edited: JournalDocument) -> JournalDocument {
        guard edited.blocks != blocks else { return self }
        guard !requiresSource else {
            assertionFailure("A document that requires Markdown source was edited as rich text.")
            return self
        }
        var layout = SourceLayout(from: self, to: edited)
        layout.separate()
        return layout.document(with: edited.blocks)
    }
    /// Each block's own source text and the text after it, or nil when the source doesn't follow the blocks.
    fileprivate var sourceParts: [SourceLayout.Part]? {
        guard source != nil, !requiresSource, sourceSegments.count == blocks.count, sourceTails.count == blocks.count
        else { return nil }
        var parts: [SourceLayout.Part] = []
        parts.reserveCapacity(sourceSegments.count)
        // Compared and cut as UTF-8 in place: copying every segment's bytes took most of an edit of a long entry.
        for (index, segment) in sourceSegments.enumerated() {
            let bytes = segment.utf8
            let leading = index == 0 ? sourceLeading.utf8.count : 0
            let tail = sourceTails[index].utf8
            guard bytes.count >= leading + tail.count, index > 0 || bytes.starts(with: sourceLeading.utf8),
                bytes.suffix(tail.count).elementsEqual(tail)
            else { return nil }
            let start = bytes.index(bytes.startIndex, offsetBy: leading)
            let end = bytes.index(bytes.endIndex, offsetBy: -tail.count)
            parts.append(
                SourceLayout.Part(body: String(decoding: bytes[start..<end], as: UTF8.self), tail: sourceTails[index]))
        }
        return parts
    }
    var markdownMetadata: MarkdownMetadata {
        var types: [String: String] = [:]
        for block in blocks {
            if let id = block.attachmentID, let type = block.mediaType { types[id.uuidString.lowercased()] = type }
        }
        for run in imageRuns {
            if let id = run.imageAttachmentID, let type = run.imageMediaType {
                types[id.uuidString.lowercased()] = type
            }
        }
        return MarkdownMetadata(
            blockIDs: blocks.map(\.id),
            segmentLengths: source == nil
                ? MarkdownWriter.segments(blocks).map(\.utf8.count)
                : (sourceSegments.count == blocks.count ? sourceSegments.map { $0.utf8.count } : nil), imageTypes: types
        )
    }
    /// Points image references at new attachment identities, as when importing into another library. Throws rather
    /// than change any other text or leave an image pointing at an identity that was replaced.
    public mutating func remapAttachments(_ mapping: [UUID: UUID]) throws {
        if let source {
            let updated = try MarkdownAttachments.remap(source, mapping: mapping)
            var metadata = markdownMetadata
            for (old, new) in mapping {
                if let type = metadata.imageTypes.removeValue(forKey: old.uuidString.lowercased()) {
                    metadata.imageTypes[new.uuidString.lowercased()] = type
                }
            }
            // Identities are replaced with text of the same length, so every block keeps its segment.
            if updated.utf8.count != source.utf8.count { metadata.segmentLengths = nil }
            self = JournalDocument(markdown: updated, metadata: metadata)
        } else {
            for index in blocks.indices {
                if let old = blocks[index].attachmentID, let new = mapping[old] { blocks[index].attachmentID = new }
            }
            mapImageRuns { run in
                var run = run
                if let old = run.imageAttachmentID, let new = mapping[old] {
                    run.imageSource = "attachments/" + new.uuidString.lowercased()
                }
                return run
            }
        }
    }

}

/// The Markdown source along the rich blocks: optional leading text, then for each block its own text (body) and
/// the text up to the next block (tail). Joined, they are the stored Markdown.
private struct SourceLayout {
    struct Part {
        var body: String
        var tail: String
    }
    private static let headings: Set<String> = [
        "heading", "subheading", "heading3", "heading4", "heading5", "heading6",
    ]
    private var leading = ""
    private var parts: [Part] = []
    /// Blocks without content, which may have no Markdown of their own.
    private var blanks: [Bool] = []
    private var lists: [Bool] = []
    private let blocks: [DocumentBlock]
    /// Blocks whose Markdown was written by this edit rather than kept from the source.
    private var written = Set<Int>()
    /// Tails (by block index, or -1 for the leading text) this edit wrote or placed next to different text.
    private var touched = Set<Int>()

    var markdown: String { leading + parts.map { $0.body + $0.tail }.joined() }

    init(from previous: JournalDocument, to edited: JournalDocument) {
        blocks = edited.blocks
        let old = previous.sourceParts
        let indices = Dictionary(
            previous.blocks.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        leading = old == nil ? "" : previous.sourceLeading
        // The old position of the previous block; -1 stands for the start of the document.
        var before: Int? = -1
        for block in edited.blocks {
            let position = parts.count
            let index = indices[block.id]
            blanks.append(Self.isBlank(block))
            lists.append(["bullet", "numbered", "task", "checked"].contains(block.kind))
            if index == nil || before.map({ $0 + 1 }) != index { touched.insert(position - 1) }
            before = index
            guard let index, let part = old?[index] else {
                // A new block takes the spacing near it, so a new list item keeps a tight list tight.
                parts.append(Part(body: MarkdownWriter.block(block), tail: spacing(near: position - 1) ?? "\n\n"))
                touched.formUnion([position - 1, position])
                written.insert(position)
                continue
            }
            if previous.blocks[index] == block {
                parts.append(part)
            } else {
                let tail = Self.tail(after: part, replacing: previous.blocks[index], with: block)
                parts.append(Part(body: MarkdownWriter.block(block), tail: tail))
                touched.formUnion([position - 1, position])
                written.insert(position)
            }
        }
        if let old { keepTrivia(of: previous, old, edited: edited) }
        for index in parts.indices.dropLast() where !MarkdownText.endsWithLineEnding(parts[index].tail) {
            // The previous end of the document takes the spacing used before it.
            parts[index].tail += spacing(near: index - 1) ?? "\n\n"
        }
        // An empty item keeps the item nested under it on the next line; a blank line would end the item.
        for index in parts.indices.dropLast()
        where MarkdownWriter.opensNested(blocks[index], blocks[index + 1])
            && parts[index].tail.allSatisfy(\.isWhitespace) && MarkdownText.endsWithBlankLine(parts[index].tail)
        {
            parts[index].tail = parts[index].tail.contains("\r\n") ? "\r\n" : "\n"
            touched.formUnion([index - 1, index])
        }
        if !leading.isEmpty, !parts.isEmpty, !MarkdownText.endsWithLineEnding(leading) { leading += "\n" }
    }
    /// The whitespace that ends the tail at `index` or the one before it, if either is only spacing.
    private func spacing(near index: Int) -> String? {
        [index, index - 1].filter { parts.indices.contains($0) }.map { parts[$0].tail }.first { tail in
            tail.allSatisfy(\.isWhitespace) && MarkdownText.endsWithLineEnding(tail)
        }
    }
    /// The text after a rewritten block. A heading's closing hashes leave with the heading, and text that stood in
    /// place of an empty paragraph stays apart from the new text.
    private static func tail(after part: Part, replacing old: DocumentBlock, with new: DocumentBlock) -> String {
        let (remainder, _) = MarkdownText.firstLine(part.tail)
        if part.body.isEmpty {
            return remainder.allSatisfy(\.isWhitespace) ? part.tail : "\n\n" + part.tail
        }
        let keepsHeading = headings.contains(old.kind) && headings.contains(new.kind)
        return MarkdownText.isClosingSequence(remainder) && !keepsHeading
            ? MarkdownText.afterFirstLine(part.tail) : part.tail
    }
    /// Keeps reference definitions and other text that followed a removed block, after the nearest earlier block.
    private mutating func keepTrivia(of previous: JournalDocument, _ old: [Part], edited: JournalDocument) {
        let positions = Dictionary(
            edited.blocks.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var preceding: Int?
        for (index, block) in previous.blocks.enumerated() {
            if let position = positions[block.id] {
                preceding = position
                continue
            }
            let (remainder, _) = MarkdownText.firstLine(old[index].tail)
            let ownsRemainder = !old[index].body.isEmpty && MarkdownText.isClosingSequence(remainder)
            let trivia = ownsRemainder ? MarkdownText.afterFirstLine(old[index].tail) : old[index].tail
            guard !trivia.allSatisfy(\.isWhitespace) else { continue }
            if let preceding {
                parts[preceding].tail = MarkdownText.appending(trivia, to: parts[preceding].tail)
            } else {
                leading = MarkdownText.appending(trivia, to: leading)
            }
            touched.insert(preceding ?? -1)
        }
    }
    private static func isBlank(_ block: DocumentBlock) -> Bool {
        block.kind != "rule" && block.attachmentID == nil && block.table == nil
            && block.runs.allSatisfy { $0.imageSource == nil && $0.text.allSatisfy(\.isWhitespace) }
    }
    /// Adds blank lines where the Markdown would join neighbouring blocks or split one, until each block is read
    /// back on its own. Only line breaks are added, so a block the parser still reads differently keeps its text.
    mutating func separate() {
        // The earliest boundary first: one missing blank line can make every later block in a list look wrong.
        for _ in 0..<32 {
            let check = unparsed()
            guard let boundary = check.boundaries.sorted().first(where: { separable($0) }) else {
                // Unchanged text the parser now reads as something else, such as a reference definition, is written
                // again from the block so it keeps showing what it showed.
                let stale = check.absorbed.subtracting(written)
                guard !stale.isEmpty else { return }
                for index in stale { parts[index].body = MarkdownWriter.block(blocks[index]) }
                written.formUnion(stale)
                continue
            }
            if boundary < 0 {
                leading = MarkdownText.blankLineEnded(leading)
            } else {
                parts[boundary].tail = MarkdownText.separated(parts[boundary].tail)
            }
        }
    }
    private func separable(_ boundary: Int) -> Bool {
        if boundary < 0 { return MarkdownText.blankLineEnded(leading) != leading }
        return MarkdownText.separated(parts[boundary].tail) != parts[boundary].tail
    }
    /// Tails (by block index, or -1 for the leading text) after which the parser didn't find the expected block,
    /// and blocks with text that no longer reads as a block of its own. Only the blocks around the ones this edit
    /// wrote are read again (`verifiedParts`); reading a long entry whole took most of the time of each keystroke.
    private func unparsed() -> (boundaries: Set<Int>, absorbed: Set<Int>) {
        guard !parts.isEmpty else { return ([], []) }
        let window = verifiedParts()
        let start = window.lowerBound == 0 ? leading : ""
        let parsed = MarkdownReader.read(start + parts[window].map { $0.body + $0.tail }.joined())
        var result = Set<Int>()
        var absorbedBlocks = Set<Int>()
        // Without block positions, only the places this edit changed can be the cause.
        if parsed.requiresSource { return (touched, []) }
        var next = 0
        var position = start.utf8.count
        for index in window {
            let bodyStart = position
            let bodyEnd = bodyStart + parts[index].body.utf8.count
            let end = bodyEnd + parts[index].tail.utf8.count
            var found: [Int] = []
            while next < parsed.starts.count, parsed.starts[next] < end {
                found.append(next)
                next += 1
            }
            let absorbed = found.isEmpty && !blanks[index]
            if absorbed { absorbedBlocks.insert(index) }
            // An ordered list not starting at 1 cannot interrupt a paragraph, so an item can turn into its text.
            let unlisted =
                lists[index]
                && found.contains { !["bullet", "numbered", "task", "checked"].contains(parsed.blocks[$0].kind) }
            if found.count > 1 || absorbed || unlisted || found.contains(where: { parsed.starts[$0] < bodyStart }) {
                result.insert(index - 1)
            }
            if found.count > 1 || found.contains(where: { parsed.ends[$0] > bodyEnd }) { result.insert(index) }
            position = end
        }
        return (result, absorbedBlocks)
    }
    /// The parts to read again: those this edit wrote or placed next to different text, and their neighbours out to
    /// a blank line between two top-level blocks on either side. Markdown doesn't carry the structure of top-level
    /// blocks across such a line, so these parts read as they do within the whole entry.
    private func verifiedParts() -> ClosedRange<Int> {
        let changed = touched.flatMap { [$0, $0 + 1] } + Array(written)
        var lower = max(0, min(changed.min() ?? 0, parts.count - 1))
        var upper = min(parts.count - 1, max(changed.max() ?? 0, lower))
        while lower > 0, !separates(lower - 1) { lower -= 1 }
        while upper < parts.count - 1, !separates(upper) { upper += 1 }
        return lower...upper
    }
    /// Whether a blank line after part `index` ends one top-level block before the next begins, so that neither reads
    /// differently whatever the other one holds.
    private func separates(_ index: Int) -> Bool {
        // Two items of a top-level list, the second starting on a line of its own at the margin: each reads as its own
        // item whatever the other holds, so a long list isn't read whole for an edit in one of its items.
        if Self.isTopLevelItem(blocks[index]), Self.isTopLevelItem(blocks[index + 1]),
            MarkdownText.endsWithLineEnding(parts[index].tail),
            parts[index].tail.allSatisfy(\.isWhitespace),
            let first = parts[index + 1].body.unicodeScalars.first, first != " " && first != "\t"
        {
            return true
        }
        guard MarkdownText.endsWithBlankLine(parts[index].tail), Self.isTopLevel(blocks[index]),
            Self.isTopLevel(blocks[index + 1]), let first = parts[index + 1].body.unicodeScalars.first
        else { return false }
        // An indented first line could continue a block above it.
        return first != " " && first != "\t"
    }
    /// A list item at the margin: in no quote and in no other item.
    private static func isTopLevelItem(_ block: DocumentBlock) -> Bool {
        ["bullet", "numbered", "task", "checked"].contains(block.kind) && (block.markdownPrefix ?? "").isEmpty
            && (block.listIndents ?? []).isEmpty
    }
    /// A block outside any list or quote that nothing after a blank line can continue.
    private static func isTopLevel(_ block: DocumentBlock) -> Bool {
        let kinds: Set<String> = headings.union(["paragraph", "rule", "image", "table"])
        return kinds.contains(block.kind) && block.markdownPrefix == nil && block.markdownContinuation == nil
            && (block.listIndents ?? []).isEmpty
    }
    func document(with blocks: [DocumentBlock]) -> JournalDocument {
        var result = JournalDocument(blocks: blocks)
        result.version = 2
        result.source = markdown
        result.sourceSegments = parts.indices.map { ($0 == 0 ? leading : "") + parts[$0].body + parts[$0].tail }
        result.sourceLeading = leading
        result.sourceTails = parts.map(\.tail)
        return result
    }
}

/// Line handling that follows CommonMark: a line ends at LF, CR or CRLF, and a blank line holds only spaces or tabs.
enum MarkdownText {
    static func endsWithLineEnding(_ text: String) -> Bool {
        text.unicodeScalars.last == "\n" || text.unicodeScalars.last == "\r"
    }
    static func endsWithBlankLine(_ text: String) -> Bool {
        var scalars = Array(text.unicodeScalars)
        guard endsWithLineEnding(text) else { return false }
        if scalars.last == "\n" { scalars.removeLast() }
        if scalars.last == "\r" { scalars.removeLast() }
        while let last = scalars.last, last == " " || last == "\t" { scalars.removeLast() }
        return scalars.isEmpty || scalars.last == "\n" || scalars.last == "\r"
    }
    /// The text before the first line ending, and the text after that line ending.
    static func firstLine(_ text: String) -> (String, String) {
        let scalars = Array(text.unicodeScalars)
        guard let end = scalars.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else { return (text, "") }
        let after = scalars[end] == "\r" && end + 1 < scalars.count && scalars[end + 1] == "\n" ? end + 2 : end + 1
        return (string(scalars[..<end]), string(scalars[after...]))
    }
    /// The text from its first line ending on, leaving out what precedes it on the first line.
    static func afterFirstLine(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        return string(scalars.drop { $0 != "\n" && $0 != "\r" })
    }
    /// An ATX heading's optional closing hashes, as left after the heading's text.
    static func isClosingSequence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return text.first.map { $0 == " " || $0 == "\t" } == true && !trimmed.isEmpty
            && trimmed.allSatisfy { $0 == "#" }
    }
    /// The text after a block, starting with a blank line so nothing in it or after it continues the block.
    /// Any other text in it is kept as it is.
    static func separated(_ text: String) -> String {
        let ending = text.contains("\r\n") ? "\r\n" : "\n"
        let (remainder, rest) = firstLine(text)
        let kept = lines(rest).drop { isBlank($0) }
        guard !kept.isEmpty else { return remainder + ending + ending }
        return remainder + ending + ending + kept.joined(separator: ending) + (endsWithLineEnding(rest) ? ending : "")
    }
    /// The text ending in a blank line, unless it is empty.
    static func blankLineEnded(_ text: String) -> String {
        guard !text.isEmpty, !endsWithBlankLine(text) else { return text }
        let ending = text.contains("\r\n") ? "\r\n" : "\n"
        return text + (endsWithLineEnding(text) ? ending : ending + ending)
    }
    /// The text, then a blank line, then `trivia` without its leading blank lines.
    static func appending(_ trivia: String, to text: String) -> String {
        let kept = lines(trivia).drop { isBlank($0) }
        guard !kept.isEmpty else { return text }
        let ending = text.contains("\r\n") ? "\r\n" : "\n"
        return blankLineEnded(text) + kept.joined(separator: ending) + (endsWithLineEnding(trivia) ? ending : "")
    }
    private static func lines(_ text: String) -> [String] {
        var result: [String] = []
        var rest = text
        while !rest.isEmpty {
            let (line, after) = firstLine(rest)
            result.append(line)
            rest = after
        }
        return result
    }
    private static func isBlank(_ line: String) -> Bool {
        line.unicodeScalars.allSatisfy { $0 == " " || $0 == "\t" }
    }
    private static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var result = String.UnicodeScalarView()
        result.append(contentsOf: scalars)
        return String(result)
    }
}

extension JournalDocument {
    private enum CodingKeys: String, CodingKey { case version, blocks, markdown, metadata }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        switch version {
        case 2:
            let markdown = try? values.decode(String.self, forKey: .markdown)
            let metadata = Result { try values.decodeIfPresent(MarkdownMetadata.self, forKey: .metadata) }
            if let markdown, case .success(let metadata) = metadata {
                self.init(markdown: markdown, metadata: metadata)
            } else {
                // Another shape of this version: show what can be read, and keep the record unchanged.
                self.init(markdown: markdown ?? "", metadata: nil)
                self.version = Self.unfamiliarVersion
            }
        case 1:
            let blocks = Result { try values.decodeIfPresent([DocumentBlock].self, forKey: .blocks) }
            if case .success(let blocks) = blocks {
                self.init(blocks: blocks ?? [])
                self.version = 1
            } else {
                self.init(blocks: [])
                self.version = Self.unfamiliarVersion
            }
        default:
            // A newer version is shown where its blocks are familiar, and never rewritten; its record is kept as is.
            self.init(blocks: (try? values.decodeIfPresent([DocumentBlock].self, forKey: .blocks)) ?? [])
            self.version = version
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        if version == 2 {
            try values.encode(markdown, forKey: .markdown)
            try values.encode(markdownMetadata, forKey: .metadata)
        } else {
            try values.encode(blocks, forKey: .blocks)
        }
    }
    public static func == (lhs: JournalDocument, rhs: JournalDocument) -> Bool {
        lhs.version == rhs.version && lhs.blocks == rhs.blocks && lhs.markdown == rhs.markdown
    }
}
