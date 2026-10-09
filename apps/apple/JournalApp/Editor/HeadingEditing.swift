import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Return in a heading (docs/design/1-1-settings-messages-editor.md §5.2). Every case is one replacement, so undo is
/// one step, and a heading split in two gives the second half an identity of its own in that same replacement.
extension RichText {
    /// `attributes` are those of the heading's first character that belongs to a block; `kind` is its level.
    static func headingReturn(
        _ text: NSAttributedString, selection: NSRange, attributes: [NSAttributedString.Key: Any], kind: String,
        size: CGFloat
    ) -> NewlineAction {
        let lineBreakOverSelection = NewlineAction(
            range: selection,
            replacement: NSAttributedString(string: "\n", attributes: self.attributes(kind: kind, size: size)),
            nextKind: "paragraph")
        guard selection.length > 0 else {
            return splittingHeading(
                text, at: selection.location, attributes: attributes, kind: kind, size: size)
                ?? lineBreakOverSelection
        }
        // A selection inside the heading is replaced first and the result is classified by where the caret lands;
        // one that reaches into another block behaves as before.
        let line = paragraphContentRange(text.string, selection: NSRange(location: selection.location, length: 0))
        guard NSMaxRange(selection) <= NSMaxRange(line) else { return lineBreakOverSelection }
        let remaining = NSMutableAttributedString(attributedString: text)
        remaining.deleteCharacters(in: selection)
        guard
            let action = splittingHeading(
                remaining, at: selection.location, attributes: attributes, kind: kind, size: size)
        else { return lineBreakOverSelection }
        // The same replacement, in the text before the selection was removed.
        let start =
            action.range.location <= selection.location
            ? action.range.location : action.range.location + selection.length
        let end =
            NSMaxRange(action.range) < selection.location
            ? NSMaxRange(action.range) : NSMaxRange(action.range) + selection.length
        return NewlineAction(
            range: NSRange(location: start, length: end - start), replacement: action.replacement,
            nextKind: action.nextKind, typing: action.typing, caret: action.caret)
    }

    /// Return with the caret at `location` of a heading, nothing selected. Nil when the caret is on the empty last
    /// line, which has no characters of its own.
    private static func splittingHeading(
        _ text: NSAttributedString, at location: Int, attributes: [NSAttributedString.Key: Any], kind: String,
        size: CGFloat
    ) -> NewlineAction? {
        let source = text.string as NSString
        guard location <= source.length else { return nil }
        let paragraph = source.paragraphRange(for: NSRange(location: location, length: 0))
        guard paragraph.length > 0 else { return nil }
        let line = paragraphContentRange(text.string, selection: NSRange(location: location, length: 0))
        let hasLineBreak = paragraph.length > line.length
        if line.length == 0 {
            return headingBecomingParagraph(paragraph, hasLineBreak: hasLineBreak, size: size)
        }
        if location == line.location {
            return paragraphAbove(text, heading: line, attributes: attributes, size: size)
        }
        if location == NSMaxRange(line) {
            return NewlineAction(
                range: NSRange(location: location, length: 0),
                replacement: NSAttributedString(string: "\n", attributes: self.attributes(kind: kind, size: size)),
                nextKind: "paragraph")
        }
        return headingSplit(
            text, at: location, line: line, paragraph: paragraph, attributes: attributes, kind: kind, size: size)
    }

    /// Return in an empty heading: it becomes a plain empty paragraph and the caret stays on it.
    private static func headingBecomingParagraph(_ paragraph: NSRange, hasLineBreak: Bool, size: CGFloat)
        -> NewlineAction
    {
        let plain = self.attributes(kind: "paragraph", size: size)
        return NewlineAction(
            range: paragraph,
            replacement: NSAttributedString(string: hasLineBreak ? "\n" : "", attributes: plain),
            nextKind: "paragraph", typing: plain, caret: paragraph.location)
    }

    /// Return at the very start of a heading's text: an empty plain paragraph goes above it, and the heading keeps
    /// its identity, level and text. The caret stays at the start of the heading's text.
    private static func paragraphAbove(
        _ text: NSAttributedString, heading line: NSRange, attributes: [NSAttributedString.Key: Any], size: CGFloat
    ) -> NewlineAction {
        let above = self.attributes(kind: "paragraph", size: size)
        return NewlineAction(
            range: NSRange(location: line.location, length: 0),
            replacement: NSAttributedString(string: "\n", attributes: above),
            nextKind: attributes[.journalKind] as? String ?? "paragraph",
            typing: LinkEditing.withoutLink(text.attributes(at: line.location, effectiveRange: nil)),
            caret: line.location + 1)
    }

    /// Return in the middle of a heading: two headings of the same level. The first keeps the block's identity; the
    /// text after the caret, with the line break that ends it, becomes a block with a new identity, in the same
    /// replacement, so undo restores one block and the document never reads the new identity as random.
    private static func headingSplit(
        _ text: NSAttributedString, at location: Int, line: NSRange, paragraph: NSRange,
        attributes: [NSAttributedString.Key: Any], kind: String, size: CGFloat
    ) -> NewlineAction {
        let hasLineBreak = paragraph.length > line.length
        let end = hasLineBreak ? NSMaxRange(paragraph) : NSMaxRange(line)
        let identity = UUID().uuidString
        var firstBreak = self.attributes(kind: kind, size: size)
        var secondBreak = firstBreak
        let block = attributes.filter { paragraphKeys.contains($0.key) }
        for key in [NSAttributedString.Key.journalBlockID, .journalBlockMetadata] {
            firstBreak[key] = block[key]
            secondBreak[key] = block[key]
        }
        secondBreak[.journalBlockID] = identity
        let tail = reattributed(
            text.attributedSubstring(from: NSRange(location: location, length: NSMaxRange(line) - location)),
            with: block.merging([.journalBlockID: identity]) { $1 })
        let replacement = NSMutableAttributedString(string: "\n", attributes: firstBreak)
        replacement.append(tail)
        if hasLineBreak { replacement.append(NSAttributedString(string: "\n", attributes: secondBreak)) }
        // Typing continues the formatting at the caret in the second heading, without a link.
        let typing = inline(text.attributes(at: location - 1, effectiveRange: nil))
            .merging(block.merging([.journalBlockID: identity]) { $1 }) { $1 }
        return NewlineAction(
            range: NSRange(location: location, length: end - location), replacement: replacement, nextKind: kind,
            typing: typing, caret: location + 1)
    }
}
