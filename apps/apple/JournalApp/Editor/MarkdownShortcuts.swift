import Foundation
import JournalCore

/// Markdown typed at the start of a line becomes formatting, as in Notes, Google Docs and Bear. Each conversion
/// is its own undo step, so ⌘Z — or Backspace straight after it — gives back exactly what was typed.
@MainActor enum MarkdownShortcuts {
    static let settingKey = "formatMarkdownAsYouType"
    static var enabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    /// What Backspace straight after a conversion puts back.
    struct Revert {
        /// The converted line, which is replaced.
        let range: NSRange
        /// The line exactly as typed, and where the caret was.
        let original: NSAttributedString
        let caret: Int
        /// Where the caret went after the conversion; Backspace from here restores the line.
        let convertedCaret: Int
        /// The text length right after the conversion; any other edit in between cancels the revert.
        let length: Int
    }
    struct Conversion {
        let range: NSRange
        let replacement: NSAttributedString
        let caret: Int
        /// What typing continues with: the new block's style, never the marker's.
        let typing: [NSAttributedString.Key: Any]
        /// Spoken to VoiceOver users, who don't see the change.
        let announcement: String
    }

    /// The paragraph style a line-start marker asks for, once the space after it is typed.
    static func style(forMarker prefix: String) -> (kind: String, number: Int?)? {
        switch prefix {
        case "- ", "* ", "+ ": return ("bullet", nil)
        case "[ ] ", "[] ": return ("task", nil)
        case "[x] ", "[X] ": return ("checked", nil)
        case "> ": return ("quote", nil)
        default: break
        }
        let marker = prefix.dropLast()
        guard prefix.hasSuffix(" "), !marker.isEmpty else { return nil }
        if marker.allSatisfy({ $0 == "#" }), marker.count <= 6 {
            return (["heading", "subheading", "heading3", "heading4", "heading5", "heading6"][marker.count - 1], nil)
        }
        if let last = marker.last, ".)".contains(last) {
            let digits = marker.dropLast()
            if (1...9).contains(digits.count), digits.allSatisfy(\.isASCII), let number = Int(digits) {
                return ("numbered", number)
            }
        }
        return nil
    }

    /// Markdown for a whole line that Return turns into a block: a code fence or a horizontal rule.
    static func block(forLine line: String) -> String? {
        if ["---", "***", "___"].contains(line) { return "---" }
        guard line.hasPrefix("```") else { return nil }
        let language = line.dropFirst(3)
        guard language.allSatisfy({ $0.isLetter || $0.isNumber || "+-_#.".contains($0) }) else { return nil }
        return "```" + language + "\n\n```"
    }

    /// Whether the caret's line is a plain paragraph in the preview, where shortcuts apply.
    static func plainParagraph(_ text: NSAttributedString, at location: Int) -> NSRange? {
        guard !MarkdownEditing.isSource(text), location <= text.length else { return nil }
        let range = RichText.paragraphContentRange(text.string, selection: NSRange(location: location, length: 0))
        guard range.location < text.length else { return range }
        let kind = text.attribute(.journalKind, at: range.location, effectiveRange: nil) as? String ?? "paragraph"
        guard kind == "paragraph", text.attribute(.journalTable, at: range.location, effectiveRange: nil) == nil
        else { return nil }
        return range
    }

    /// The conversion for a marker the space before `caret` has just completed.
    static func afterSpace(
        _ text: NSAttributedString, caret: Int, size: CGFloat, images: [UUID: Data], width: CGFloat
    ) -> Conversion? {
        guard let line = plainParagraph(text, at: caret), caret > line.location, caret <= NSMaxRange(line) else {
            return nil
        }
        let prefix = (text.string as NSString).substring(
            with: NSRange(location: line.location, length: caret - line.location))
        guard let style = style(forMarker: prefix) else { return nil }
        let rest = NSRange(location: caret, length: NSMaxRange(line) - caret)
        var document = RichText.document(text.attributedSubstring(from: rest))
        if document.blocks.isEmpty { document.blocks = [DocumentBlock()] }
        document = RichText.restyling(document, kind: style.kind)
        if let number = style.number { document.blocks[0].listNumber = number }
        if let id = text.attribute(.journalBlockID, at: line.location, effectiveRange: nil) as? String,
            let identity = UUID(uuidString: id)
        {
            document.blocks[0].id = identity
        }
        let replacement = RichText.render(document, size: size, images: images, width: width)
        return Conversion(
            range: line, replacement: replacement, caret: line.location + replacement.length - rest.length,
            typing: RichText.blockAttributes(document.blocks[0], size: size), announcement: announcement(style.kind))
    }

    private static func announcement(_ kind: String) -> String {
        switch kind {
        case "bullet": return "Bulleted list"
        case "numbered": return "Numbered list"
        case "task", "checked": return "Checklist"
        case "quote": return "Block quote"
        case "heading": return "Heading 1"
        case "subheading": return "Heading 2"
        default: return kind.hasPrefix("heading") ? "Heading " + kind.dropFirst("heading".count) : "Paragraph"
        }
    }
}
