import JournalCore
import SwiftUI

extension NSAttributedString.Key {
    static let journalSource = Self("JournalMarkdownSource")
    static let journalCode = Self("JournalInlineCode")
}

@MainActor
enum MarkdownEditing {
    struct Edit {
        let text: NSAttributedString
        let range: NSRange
        var selection: NSRange? = nil
    }
    nonisolated static func isSource(_ text: NSAttributedString) -> Bool {
        text.length > 0 && text.attribute(.journalSource, at: 0, effectiveRange: nil) as? Bool == true
    }
    static func attributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            .font: PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular),
            .foregroundColor: PlatformColor.labelColorCompat, .journalSource: true,
        ]
    }
    static func render(_ source: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: source, attributes: attributes(size: size))
    }
    /// Reads the editor's text: Markdown source when the editor shows the source, rich text otherwise. The mode is
    /// the editor's, never guessed from the text, which pasted or typed text can carry any attributes into.
    static func read(_ text: NSAttributedString, previous: JournalDocument, source: Bool = false) -> JournalDocument {
        source ? previous.replacingMarkdown(text.string) : previous.applyingRichEdit(RichText.document(text))
    }
    static func edit(
        _ command: EditorCommand, text: NSAttributedString, selection: NSRange,
        document: JournalDocument, size: CGFloat, images: [UUID: Data], source sourceMode: Bool = false,
        layout: RichText.ImageLayout = .init()
    ) -> Edit? {
        let whole = NSRange(location: 0, length: text.length)
        if case .source = command {
            if sourceMode {
                let parsed = document.replacingMarkdown(text.string)
                guard !parsed.requiresMarkdownSource else { return nil }
                let rendered = RichText.render(parsed, size: size, images: images, layout: layout)
                return Edit(
                    text: rendered, range: whole,
                    selection: MarkdownSelection.toPreview(
                        selection, source: text.string, parsed: parsed, preview: rendered))
            }
            return Edit(
                text: render(document.markdown, size: size), range: whole,
                selection: MarkdownSelection.toSource(selection, preview: text, document: document))
        }
        if sourceMode {
            guard let change = SourceFormatting.change(command, in: text.string, selection: selection) else {
                return nil
            }
            return Edit(text: render(change.replacement, size: size), range: change.range, selection: change.selection)
        }
        if case .insert(let value) = command, value.isEmpty {
            return exitCodeBlock(text, selection: selection, size: size)
        }
        if case .insert(let value) = command {
            let identifier =
                text.length > 0
                ? (text.attribute(.journalBlockID, at: min(selection.location, text.length - 1), effectiveRange: nil)
                    as? String).flatMap(UUID.init(uuidString:)) : nil
            let position =
                (identifier.flatMap { id in document.blocks.firstIndex { $0.id == id } } ?? (document.blocks.count - 1))
                + 1
            if let edit = insertFormatted(
                value, at: max(0, position), document: document, size: size, images: images, layout: layout,
                range: whole)
            {
                return edit
            }
            let inserted = document.insertingMarkdown(value, after: identifier)
            return Edit(
                text: render(inserted.text, size: size), range: whole,
                selection: NSRange(location: inserted.caret, length: 0))
        }
        if case .strikethrough = command {
            return toggle(.strikethroughStyle, text: text, selection: selection, size: size)
        }
        if case .code = command { return toggle(.journalCode, text: text, selection: selection, size: size) }
        return nil
    }
    /// Moves the caret to the block after the code block, adding one empty paragraph only at the end.
    private static func exitCodeBlock(_ text: NSAttributedString, selection: NSRange, size: CGFloat) -> Edit? {
        guard text.length > 0 else { return nil }
        var block = NSRange()
        guard
            text.attribute(
                .journalStructuredBlock, at: min(selection.location, text.length - 1), longestEffectiveRange: &block,
                in: NSRange(location: 0, length: text.length)) != nil
        else { return nil }
        let end = NSMaxRange(block)
        if end < text.length {
            return Edit(
                text: NSAttributedString(), range: NSRange(location: end, length: 0),
                selection: NSRange(location: end, length: 0))
        }
        let paragraph = NSMutableAttributedString(
            string: "\n", attributes: RichText.attributes(kind: "paragraph", size: size))
        RichText.spaceAfterCode(paragraph, range: NSRange(location: 0, length: paragraph.length))
        return Edit(
            text: paragraph, range: NSRange(location: end, length: 0), selection: NSRange(location: end + 1, length: 0))
    }
    /// Replaces the line holding block `blockID` with the blocks of `value`, as Return does after “```” or “---”.
    static func convertLine(
        _ value: String, blockID: UUID, document: JournalDocument, size: CGFloat, images: [UUID: Data],
        layout: RichText.ImageLayout, range: NSRange
    ) -> Edit? {
        guard let index = document.blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        return insertFormatted(
            value, at: index, replacingBlock: true, document: document, size: size, images: images, layout: layout,
            range: range)
    }
    /// Inserts `value` as blocks at `position`, optionally replacing the block there.
    private static func insertFormatted(
        _ value: String, at position: Int, replacingBlock: Bool = false, document: JournalDocument,
        size: CGFloat, images: [UUID: Data], layout: RichText.ImageLayout, range: NSRange
    ) -> Edit? {
        let fragment = JournalDocument(markdown: value)
        if !fragment.requiresMarkdownSource {
            var edited = document
            if replacingBlock, edited.blocks.indices.contains(position) { edited.blocks.remove(at: position) }
            let index = min(position, edited.blocks.count) - 1
            // An empty paragraph is added only at the end, so there is somewhere to continue writing. A code
            // block keeps the caret inside it; Exit Code Block or the down arrow adds the paragraph when needed.
            let atEnd = index + 1 >= edited.blocks.count
            let continues = atEnd && !fragment.blocks.contains { $0.kind == "codeBlock" }
            let insertedBlocks = fragment.blocks + (continues ? [DocumentBlock()] : [])
            edited.blocks.insert(contentsOf: insertedBlocks, at: max(0, index + 1))
            let updated = document.applyingRichEdit(edited)
            let rendered = RichText.render(updated, size: size, images: images, layout: layout)
            // The caret goes into the new block, or past a horizontal rule to the text after it.
            let target =
                fragment.blocks.allSatisfy { $0.kind == "rule" }
                ? edited.blocks[min(edited.blocks.count - 1, max(0, index + 1) + fragment.blocks.count)].id
                : insertedBlocks.first?.id
            var caret = rendered.length
            rendered.enumerateAttribute(.journalBlockID, in: NSRange(location: 0, length: rendered.length)) {
                id, range, stop in
                if id as? String == target?.uuidString {
                    caret = range.location
                    stop.pointee = true
                }
            }
            return Edit(text: rendered, range: range, selection: NSRange(location: caret, length: 0))
        }
        return nil
    }
    static func typingCommand(
        _ command: EditorCommand, textIsEmpty: Bool, selection: NSRange,
        typing: [NSAttributedString.Key: Any], size: CGFloat, source: Bool = false
    ) -> [NSAttributedString.Key: Any]? {
        if case .source = command, textIsEmpty {
            return source ? RichText.attributes(kind: "paragraph", size: size) : attributes(size: size)
        }
        guard selection.length == 0, !source else { return nil }
        let key: NSAttributedString.Key
        switch command {
        case .strikethrough: key = .strikethroughStyle
        case .code: key = .journalCode
        default: return nil
        }
        var result = typing
        let enabled = (typing[key] as? Int ?? 0) == 0
        result[key] = enabled ? 1 : 0
        if key == .journalCode {
            result[.font] = codeFont(typing[.font] as? PlatformFont, enabled: enabled, size: size)
            result[.backgroundColor] = enabled ? BlockDecorations.codeFill : nil
        }
        return result
    }
    private static func codeFont(_ original: PlatformFont?, enabled: Bool, size: CGFloat) -> PlatformFont {
        let base =
            enabled ? PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular) : RichText.font(size: size)
        guard let original else { return base }
        #if os(macOS)
            let traits = NSFontManager.shared.traits(of: original).intersection([.boldFontMask, .italicFontMask])
            return NSFontManager.shared.convert(base, toHaveTrait: traits)
        #else
            let traits = original.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic])
            return UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: size)
        #endif
    }
    private static func toggle(
        _ key: NSAttributedString.Key, text: NSAttributedString, selection: NSRange, size: CGFloat
    ) -> Edit? {
        guard selection.length > 0 else { return nil }
        let replacement = NSMutableAttributedString(attributedString: text.attributedSubstring(from: selection))
        let enabled = (replacement.attribute(key, at: 0, effectiveRange: nil) as? Int ?? 0) == 0
        replacement.addAttribute(key, value: enabled ? 1 : 0, range: NSRange(location: 0, length: replacement.length))
        if key == .journalCode {
            let whole = NSRange(location: 0, length: replacement.length)
            replacement.enumerateAttribute(.font, in: whole) { value, range, _ in
                replacement.addAttribute(
                    .font, value: codeFont(value as? PlatformFont, enabled: enabled, size: size), range: range)
            }
            if enabled {
                replacement.addAttribute(.backgroundColor, value: BlockDecorations.codeFill, range: whole)
            } else {
                replacement.removeAttribute(.backgroundColor, range: whole)
            }
        }
        return Edit(text: replacement, range: selection, selection: selection)
    }
}
