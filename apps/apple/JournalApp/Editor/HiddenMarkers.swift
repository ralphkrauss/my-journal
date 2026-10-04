import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// A rule's line holds one hidden character. The caret stays outside it, typing next to it is visible body text, and
/// deleting into it removes it as a whole, so it never ends up in what is saved. List items and quotes have no hidden
/// characters (ListLayout.swift); the caret only stays before a final item's own line break.
@MainActor enum HiddenMarkers {
    /// What typing continues with. It never continues a marker, an image, a table or a rule: text typed after one of
    /// those starts a paragraph of its own.
    static func typingAttributes(_ proposed: [NSAttributedString.Key: Any], size: CGFloat)
        -> [NSAttributedString.Key: Any]
    {
        guard proposed[.journalSource] as? Bool != true else { return proposed }
        if ["image", "table", "rule"].contains(proposed[.journalKind] as? String ?? "")
            || proposed[.journalImage] != nil
            || proposed[.journalTable] != nil
        {
            var paragraph = RichText.attributes(kind: "paragraph", size: size)
            paragraph[.journalBlockID] = UUID().uuidString
            return paragraph
        }
        var result = proposed
        result[.journalMarker] = nil
        result[.journalOwnEnd] = nil
        result[.journalInlineImage] = nil
        result[.attachment] = nil
        if isInvisible(result) {
            result[.foregroundColor] = PlatformColor.labelColorCompat
            if let font = result[.font] as? PlatformFont, font.pointSize < 1 {
                result[.font] = RichText.font(size: size)
            }
        }
        return result
    }

    /// Whether typing with `attributes` would be invisible, as the styling of a hidden marker is.
    static func isInvisible(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let font = attributes[.font] as? PlatformFont, font.pointSize < 1 { return true }
        guard let color = attributes[.foregroundColor] as? PlatformColor else { return false }
        return color.cgColor.alpha == 0
    }

    /// Moves a caret that would sit before or inside a hidden marker to just after it. Moving left out of the start of
    /// a rule goes on to the end of the line before, so the arrow keys never get stuck. A selection ends before a final
    /// item's own line break unless it holds the whole text, and a caret never goes past it.
    static func caret(_ text: NSAttributedString, proposed original: NSRange, previous: NSRange) -> NSRange {
        var proposed = original
        proposed.location = min(proposed.location, text.length)
        proposed.length = min(proposed.length, text.length - proposed.location)
        if ListMarkers.hasOwnEnd(text), NSMaxRange(proposed) == text.length,
            proposed.location > 0 || proposed.length == 0
        {
            if proposed.length > 0 {
                proposed.length -= 1
            } else {
                proposed.location = text.length - 1
            }
        }
        guard proposed.length == 0, proposed.location < text.length,
            text.attribute(.journalMarker, at: proposed.location, effectiveRange: nil) != nil
        else { return proposed }
        var marker = NSRange()
        let line = (text.string as NSString).paragraphRange(for: proposed)
        _ = text.attribute(.journalMarker, at: proposed.location, longestEffectiveRange: &marker, in: line)
        let end = NSMaxRange(marker)
        if previous.length == 0, previous.location == end, proposed.location == end - 1, marker.location > 0 {
            return NSRange(location: marker.location - 1, length: 0)
        }
        return NSRange(location: end, length: 0)
    }

    /// The range to delete instead when a deletion joins a line to the list item, task, quote or rule after it, so that
    /// no hidden marker is left inside the joined line; nil when the text view can delete as asked. Deleting within a
    /// line's own marker is left to the text view.
    static func joiningDeletion(_ text: NSAttributedString, range: NSRange) -> NSRange? {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        let source = text.string as NSString
        let end = NSMaxRange(range)
        let last = RichText.paragraphContentRange(text.string, selection: NSRange(location: end - 1, length: 0))
        // The deletion ends inside the marker of a line it joins to the text before it.
        var marker = NSRange()
        if range.location < last.location, NSLocationInRange(end - 1, last),
            text.attribute(.journalMarker, at: end - 1, longestEffectiveRange: &marker, in: last) != nil,
            NSMaxRange(marker) > end
        {
            return NSRange(location: range.location, length: NSMaxRange(marker) - range.location)
        }
        // The deletion ends with the line break just before a marker.
        guard end < text.length, source.character(at: end - 1) == 0x0A,
            let next = RichText.markerRanges(
                text, in: RichText.paragraphContentRange(text.string, selection: NSRange(location: end, length: 0))
            ).first, next.location == end
        else { return nil }
        return NSRange(location: range.location, length: NSMaxRange(next) - range.location)
    }
}

/// Backspace at the start of a list item, task or quote removes one level of its formatting, as in Notes and Pages;
/// the next Backspace joins the line with the one before it.
@MainActor enum ItemFormattingRemoval {
    struct Edit {
        let text: NSAttributedString
        let range: NSRange
        let caret: Int
        let typing: [NSAttributedString.Key: Any]
        /// The Format menu's name for the result, for Edit ▸ Undo.
        let actionName: String
        let announcement: String
    }
    /// The edit for a deletion that ends at `caret`, when the caret is at the start of an item's line; otherwise nil.
    static func edit(_ text: NSAttributedString, caret: Int, size: CGFloat, images: [UUID: Data]) -> Edit? {
        guard caret < text.length else { return nil }
        let source = text.string as NSString
        let paragraph = source.paragraphRange(for: NSRange(location: caret, length: 0))
        guard paragraph.location == caret, paragraph.length > 0,
            ListMarkers.itemKinds.contains(
                text.attribute(.journalKind, at: caret, effectiveRange: nil) as? String ?? ""),
            let original = RichText.document(text.attributedSubstring(from: paragraph)).blocks.first,
            let change = removingOneLevel(original)
        else { return nil }
        if original.listIndents?.isEmpty == false,
            let outdent = ListIndentation.edit(
                .decrease, text: text, selection: NSRange(location: caret, length: 0), size: size, images: images),
            outdent.range.location <= caret, outdent.text.length > caret - outdent.range.location
        {
            // A nested item moves out a level with the items nested under it, as Decrease Indent moves it.
            return Edit(
                text: outdent.text, range: outdent.range, caret: paragraph.location,
                typing: HiddenMarkers.typingAttributes(
                    outdent.text.attributes(at: caret - outdent.range.location, effectiveRange: nil), size: size),
                actionName: change.actionName, announcement: change.announcement)
        }
        let block = change.block
        let replacement = RichText.paragraphReplacement(
            [block], replacing: paragraph, in: text, size: size, images: images)
        return Edit(
            text: replacement.text, range: paragraph, caret: paragraph.location,
            typing: RichText.itemAttributes(block, number: block.listNumber, size: size), actionName: change.actionName,
            announcement: change.announcement)
    }
    /// One level, innermost first: a nested list item moves out a level, a list item in a quote becomes quote text,
    /// a nested quote moves out a level, and anything else becomes a paragraph where it is.
    static func removingOneLevel(_ original: DocumentBlock) -> (
        block: DocumentBlock, actionName: String, announcement: String
    )? {
        var block = original
        let outer = block.markdownPrefix ?? ""
        switch block.kind {
        case "bullet", "numbered", "task", "checked":
            if block.listIndents?.isEmpty == false {
                StructuredKeyboard.change(&block, key: .outdent, complete: false)
                return (block, "Decrease Indent", "Decrease indent")
            }
            block.listNumber = nil
            block.listMarker = nil
            block.listIndents = nil
            if outer.hasSuffix("> ") {
                quote(&block, outer: outer)
                return (block, "Block Quote", "Block quote")
            }
            block.kind = "paragraph"
            block.markdownPrefix = nil
            block.markdownContinuation = nil
            return (block, "Paragraph", "Paragraph")
        case "quote":
            if outer.hasSuffix("> ") {
                quote(&block, outer: outer)
                return (block, "Block Quote", "Block quote")
            }
            // A quote inside a list item stays in that item as its text.
            block.kind = "paragraph"
            block.markdownPrefix = outer.isEmpty ? nil : outer
            block.markdownContinuation = outer.isEmpty ? nil : outer
            return (block, "Paragraph", "Paragraph")
        default:
            return nil
        }
    }
    /// Makes the block the text of the quote around it; `outer` ends with that quote's "> ".
    private static func quote(_ block: inout DocumentBlock, outer: String) {
        let prefix = String(outer.dropLast(2))
        block.kind = "quote"
        block.markdownPrefix = prefix.isEmpty ? nil : prefix
        block.markdownContinuation = outer
    }
}

extension NativeEditor.Coordinator {
    /// Carries out a deletion that would leave a hidden marker inside a joined line. Returns false when the text view
    /// can go ahead.
    func deleteHiddenMarker(_ range: NSRange) -> Bool {
        guard let view, !editingSource else { return false }
        #if os(macOS)
            guard let text = view.textStorage else { return false }
        #else
            let text = view.textStorage
        #endif
        guard let joined = HiddenMarkers.joiningDeletion(text, range: range) else { return false }
        replace(NSAttributedString(), range: joined)
        return true
    }
}
