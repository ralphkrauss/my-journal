import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension NSAttributedString.Key {
    /// A numbered list item's number, drawn in front of it. It is fixed when the item is shown or made, as Markdown
    /// numbers are (docs/design/list-markers-2026-10-03.md).
    static let journalListNumber = Self("JournalListNumber")
    /// Tags the text's last character when it is the line break that ends a list item or quote of its own: no empty
    /// paragraph follows it, and the caret never goes past it.
    static let journalOwnEnd = Self("JournalOwnEnd")
    /// A numbered list's column, when its widest number needs more room than the shared list column: every item of
    /// the list sits in it, so the numbers keep a space before their text and the text lines up.
    static let journalListColumn = Self("JournalListColumn")
}

/// List items and quotes hold only what the person wrote. Their bullets and numbers are drawn in front of them, so
/// the keyboard, dictation, predictions and VoiceOver read the text as written (list-markers-2026-10-03.md).
enum ListMarkers {
    /// The paragraphs that are list items or quotes.
    static let itemKinds: Set<String> = ["bullet", "numbered", "task", "checked", "quote"]

    /// One bullet or number to draw, in its text container's coordinates.
    struct Marker {
        let text: String
        let font: PlatformFont
        /// The start of the item's list column.
        let x: CGFloat
        /// The first line's baseline.
        let baseline: CGFloat
    }

    /// What is drawn in front of a paragraph with `attributes`: a bullet or a number, or nothing.
    static func text(for attributes: [NSAttributedString.Key: Any]) -> String? {
        switch attributes[.journalKind] as? String {
        case "bullet": return "•"
        case "numbered": return "\(attributes[.journalListNumber] as? Int ?? 1)."
        default: return nil
        }
    }

    /// The font a marker is drawn in: the paragraph's own font at the item's size, never its first word's bold or
    /// code font.
    static func font(size: CGFloat) -> PlatformFont { PlatformFont.systemFont(ofSize: size, weight: .regular) }

    /// Where an item's list column starts, from its line fragment's leading edge: where its bullet, number or
    /// checkbox goes. Its wrapped lines start one column further in.
    static func columnStart(style: NSParagraphStyle?, size: CGFloat, padding: CGFloat, column: CGFloat? = nil)
        -> CGFloat
    {
        padding + max(0, (style?.headIndent ?? 0) - (column ?? RichText.listColumn(size: size)))
    }

    /// The marker of the paragraph that starts at `location`, if it has one and is laid out.
    static func marker(atParagraph location: Int, layout: NSLayoutManager) -> Marker? {
        guard let storage = layout.textStorage, location < storage.length,
            let container = layout.textContainers.first
        else { return nil }
        let attributes = storage.attributes(at: location, effectiveRange: nil)
        guard let text = text(for: attributes), let size = (attributes[.font] as? PlatformFont)?.pointSize else {
            return nil
        }
        let glyph = layout.glyphIndexForCharacter(at: location)
        guard glyph < layout.numberOfGlyphs else { return nil }
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let style = attributes[.paragraphStyle] as? NSParagraphStyle
        return Marker(
            text: text, font: font(size: size),
            x: line.minX
                + columnStart(
                    style: style, size: size, padding: container.lineFragmentPadding,
                    column: attributes[.journalListColumn] as? CGFloat),
            baseline: line.minY + baseline(ofCharacter: location, glyph: glyph, layout: layout))
    }

    /// The baseline of the line that holds `character` (laid out as `glyph`), from the top of its line fragment.
    /// TextKit lays a line break's glyph out below the baseline, so on an empty line, where the line break is all
    /// there is, the baseline is where text in the line break's font sits once it's typed. Markers, checkboxes and
    /// the caret are placed on it, so they don't move with the first character typed.
    private static let paragraphBreaks: Set<unichar> = [0x0A, 0x0D, 0x2029]
    /// Paragraph breaks and the line separator a soft line break is written as.
    private static let lineBreaks = paragraphBreaks.union([0x2028])
    static func baseline(ofCharacter character: Int, glyph: Int, layout: NSLayoutManager) -> CGFloat {
        let location = layout.location(forGlyphAt: glyph).y
        guard let storage = layout.textStorage, character < storage.length,
            lineBreaks.contains((storage.string as NSString).character(at: character)),
            let font = storage.attribute(.font, at: character, effectiveRange: nil) as? PlatformFont
        else { return location }
        // The space a paragraph after a code block or table leaves above its first line.
        let style = storage.attribute(.paragraphStyle, at: character, effectiveRange: nil) as? NSParagraphStyle
        let startsParagraph =
            character > 0 && paragraphBreaks.contains((storage.string as NSString).character(at: character - 1))
        let before = startsParagraph ? style?.paragraphSpacingBefore ?? 0 : 0
        #if os(macOS)
            return before + layout.defaultBaselineOffset(for: font)
        #else
            return before + font.ascender
        #endif
    }

    /// The markers of the paragraphs whose first glyph is in `glyphs`.
    static func markers(in glyphs: NSRange, layout: NSLayoutManager) -> [Marker] {
        guard let storage = layout.textStorage, glyphs.length > 0, storage.length > 0 else { return [] }
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let source = storage.string as NSString
        var result: [Marker] = []
        var position = source.paragraphRange(for: NSRange(location: min(characters.location, source.length), length: 0))
            .location
        while position < storage.length, position < NSMaxRange(characters) {
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            defer { position = max(NSMaxRange(paragraph), position + 1) }
            guard position >= characters.location,
                NSLocationInRange(layout.glyphIndexForCharacter(at: position), glyphs),
                let marker = marker(atParagraph: position, layout: layout)
            else { continue }
            result.append(marker)
        }
        return result
    }

    static func draw(_ marker: Marker, origin: CGPoint) {
        let text = NSAttributedString(
            string: marker.text, attributes: [.font: marker.font, .foregroundColor: PlatformColor.labelColorCompat])
        text.draw(at: CGPoint(x: origin.x + marker.x, y: origin.y + marker.baseline - marker.font.ascender))
    }

    /// Whether the text ends with a list item's or quote's own line break.
    static func hasOwnEnd(_ text: NSAttributedString) -> Bool {
        guard text.length > 0 else { return false }
        return text.attribute(.journalOwnEnd, at: text.length - 1, effectiveRange: nil) != nil
            && (text.string as NSString).character(at: text.length - 1) == 0x0A
    }
}

/// Lays out the entry's text with TextKit 1, as the whole editor is written for, and draws list bullets and numbers
/// with the text, so they show above a selection as glyphs do.
final class ListLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        for marker in ListMarkers.markers(in: glyphsToShow, layout: self) {
            ListMarkers.draw(marker, origin: origin)
        }
    }

    /// No empty line after a final item's own line break: nothing can be written there.
    override func setExtraLineFragmentRect(
        _ fragmentRect: CGRect, usedRect: CGRect, textContainer container: NSTextContainer
    ) {
        if let storage = textStorage, ListMarkers.hasOwnEnd(storage) {
            super.setExtraLineFragmentRect(.zero, usedRect: .zero, textContainer: container)
        } else {
            super.setExtraLineFragmentRect(fragmentRect, usedRect: usedRect, textContainer: container)
        }
    }

    /// A text storage, this layout manager and a container that tracks the text view's width: the TextKit 1
    /// objects the body text view is made with. The text view doesn't keep the storage; its owner must.
    static func makeTextSystem(width: CGFloat) -> (NSTextStorage, NSTextContainer) {
        let storage = NSTextStorage()
        let layout = ListLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        return (storage, container)
    }
}
