import JournalCore
import SwiftUI

/// A link in the text as Edit Link… shows it (docs/design/build-18-fixes-2026-10-06.md §2.4).
struct EditableLink: Equatable {
    /// The whole link, however much of it the selection covers.
    let range: NSRange
    /// The address as the field shows it: an email link without “mailto:”, an address the app doesn't open as it is.
    let address: String
    /// The link's characters.
    let text: String
    /// Whether the characters are plain text on one line. Only then can the Text row change them without dropping
    /// an inline image or flattening paragraphs.
    let editsText: Bool
}

/// Which link commands apply to the caret or selection, for the menus.
struct LinkAvailability: Equatable {
    /// The caret or selection is in one link, so Add Link… reads Edit Link….
    var edit = false
    /// The caret or selection touches a link, so Remove Link applies.
    var remove = false
}

/// Finding, changing and removing the links of the text. A link is the longest run of characters that share one
/// address; an address the app doesn't open is kept as an inert link, which is a link here too.
@MainActor
enum LinkEditing {
    /// The link at the caret, or the one the selection lies in. A caret in a link, or at either end of one, counts:
    /// the character before it first, then the one after.
    static func link(in text: NSAttributedString, selection: NSRange) -> EditableLink? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        let range: NSRange
        if selection.length == 0 {
            guard let found = caretRange(in: text, at: selection.location) else { return nil }
            range = found
        } else {
            guard let found = linkRange(at: selection.location, in: text),
                NSMaxRange(selection) <= NSMaxRange(found)
            else { return nil }
            range = found
        }
        let characters = text.attributedSubstring(from: range)
        return EditableLink(
            range: range, address: address(at: range.location, in: text), text: characters.string,
            editsText: isPlainLine(characters))
    }

    static func availability(_ text: NSAttributedString, selection: NSRange) -> LinkAvailability {
        LinkAvailability(
            edit: link(in: text, selection: selection) != nil, remove: !ranges(in: text, touching: selection).isEmpty)
    }

    /// Every link the caret or selection touches, each whole, in order.
    static func ranges(in text: NSAttributedString, touching selection: NSRange) -> [NSRange] {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return [] }
        if selection.length == 0 { return caretRange(in: text, at: selection.location).map { [$0] } ?? [] }
        var found: [NSRange] = []
        var position = selection.location
        while position < NSMaxRange(selection) {
            if let range = linkRange(at: position, in: text) {
                found.append(range)
                position = NSMaxRange(range)
            } else {
                position += 1
            }
        }
        return found
    }

    /// The characters of `link` with their formatting and the address `url`. Text that differs from the link's own
    /// replaces it, formatted as its first character was; the link's title stays.
    static func editing(_ text: NSAttributedString, link: EditableLink, url: URL, newText: String?)
        -> NSAttributedString
    {
        let original = text.attributedSubstring(from: link.range)
        let result: NSMutableAttributedString
        if link.editsText, let newText, !newText.isEmpty, newText != link.text, original.length > 0 {
            result = NSMutableAttributedString(
                string: newText, attributes: original.attributes(at: 0, effectiveRange: nil))
        } else {
            result = NSMutableAttributedString(attributedString: original)
        }
        let whole = NSRange(location: 0, length: result.length)
        result.removeAttribute(.journalInertLink, range: whole)
        result.addAttribute(.link, value: url, range: whole)
        updateInlineImages(in: result, range: whole) { $0.link = url.absoluteString }
        return result
    }

    /// A picture in the text carries its link inside the run it is stored as.
    private static func updateInlineImages(
        in text: NSMutableAttributedString, range within: NSRange, change: (inout TextRun) -> Void
    ) {
        var changed: [(NSRange, Data)] = []
        text.enumerateAttribute(.journalInlineImage, in: within) { value, range, _ in
            guard let data = value as? Data, var run = try? JournalCoding.decoder().decode(TextRun.self, from: data)
            else { return }
            change(&run)
            if let updated = try? JournalCoding.encoder().encode(run) { changed.append((range, updated)) }
        }
        for (range, data) in changed { text.addAttribute(.journalInlineImage, value: data, range: range) }
    }

    /// The text from the first link the caret or selection touches to the last, without the links, and the range it
    /// replaces. The text and its other formatting stay.
    static func removing(_ text: NSAttributedString, touching selection: NSRange) -> (
        range: NSRange, text: NSAttributedString
    )? {
        let links = ranges(in: text, touching: selection)
        guard let first = links.first, let last = links.last else { return nil }
        let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        let result = NSMutableAttributedString(attributedString: text.attributedSubstring(from: span))
        for range in links {
            let local = NSRange(location: range.location - span.location, length: range.length)
            for key in linkKeys { result.removeAttribute(key, range: local) }
            updateInlineImages(in: result, range: local) {
                $0.link = nil
                $0.linkTitle = nil
            }
        }
        return (span, result)
    }

    /// The link's address as the field shows it.
    private static func address(at index: Int, in text: NSAttributedString) -> String {
        let value = target(at: index, in: text) ?? ""
        return value.lowercased().hasPrefix("mailto:") ? String(value.dropFirst("mailto:".count)) : value
    }

    /// Where the character at `index` links to, if it does. A picture inside a line of text keeps its link in the
    /// run it is stored as (`.journalInlineImage`), not in a `.link` attribute.
    private static func target(at index: Int, in text: NSAttributedString) -> String? {
        if let url = text.attribute(.link, at: index, effectiveRange: nil) as? URL { return url.absoluteString }
        if let value = text.attribute(.link, at: index, effectiveRange: nil) as? String { return value }
        if let value = text.attribute(.journalInertLink, at: index, effectiveRange: nil) as? String { return value }
        guard let run = inlineImageRun(at: index, in: text), let value = run.link else { return nil }
        return URL(string: value)?.absoluteString ?? value
    }

    private static func inlineImageRun(at index: Int, in text: NSAttributedString) -> TextRun? {
        guard let data = text.attribute(.journalInlineImage, at: index, effectiveRange: nil) as? Data else {
            return nil
        }
        return try? JournalCoding.decoder().decode(TextRun.self, from: data)
    }

    private static let linkKeys: [NSAttributedString.Key] = [.link, .journalLinkTitle, .journalInertLink]

    /// Typing attributes without a link: after Remove Link with the caret at the end of the link, what is typed next
    /// must not carry the link the caret was just in.
    static func withoutLink(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        attributes.filter { !linkKeys.contains($0.key) }
    }

    private static func caretRange(in text: NSAttributedString, at location: Int) -> NSRange? {
        linkRange(at: location - 1, in: text) ?? linkRange(at: location, in: text)
    }

    /// The whole link that holds the character at `index`: the characters around it that link to the same address.
    private static func linkRange(at index: Int, in text: NSAttributedString) -> NSRange? {
        guard index >= 0, index < text.length, let address = target(at: index, in: text) else { return nil }
        var start = index
        while start > 0, target(at: start - 1, in: text) == address { start -= 1 }
        var end = index + 1
        while end < text.length, target(at: end, in: text) == address { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Whether the characters hold no line break, paragraph break or inline image.
    private static func isPlainLine(_ characters: NSAttributedString) -> Bool {
        let string = characters.string
        guard string.rangeOfCharacter(from: .newlines) == nil, !string.contains("\u{FFFC}") else { return false }
        var plain = true
        characters.enumerateAttribute(.attachment, in: NSRange(location: 0, length: characters.length)) {
            value, _, stop in
            if value != nil {
                plain = false
                stop.pointee = true
            }
        }
        return plain
    }
}
