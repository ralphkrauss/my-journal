import JournalCore
import SwiftUI

enum FormattingToggle: String { case on, off, mixed }

struct FormattingState: Equatable {
    var bold = FormattingToggle.off
    var italic = FormattingToggle.off
    var underline = FormattingToggle.off
    var strikethrough = FormattingToggle.off
    var code = FormattingToggle.off
    var sourceOnly = false
    var sourceMode = false
    var taskCompletion: FormattingToggle?
    /// Whether Increase and Decrease Indent apply (docs/design/list-indentation-2026-10-04.md).
    var indent = ListIndentation.Availability()
    /// Whether Edit Link… and Remove Link apply (docs/design/build-18-fixes-2026-10-06.md §2.4).
    var link = LinkAvailability()
    var paragraph: String?

    init() {}
    /// `source` is whether the editor shows the Markdown source; table cells never do. `size` is the editor's text
    /// size, which limits how deep a list can be indented.
    @MainActor init(
        text: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any], source: Bool? = nil,
        size: CGFloat = 17
    ) {
        var samples: [[NSAttributedString.Key: Any]] = []
        if range.length == 0 {
            samples = [typing]
        } else if NSMaxRange(range) <= text.length {
            text.enumerateAttributes(in: range) { attributes, _, _ in samples.append(attributes) }
        }
        sourceMode = source ?? false
        sourceOnly = sourceMode && JournalDocument(markdown: text.string).requiresMarkdownSource
        if sourceMode {
            readSource(text.string, range: range)
            return
        }
        link = LinkEditing.availability(text, selection: range)
        guard !samples.isEmpty else { return }
        var kinds = Set(samples.map { $0[.journalKind] as? String ?? "paragraph" })
        if range.length == 0, text.length > 0 {
            // The block comes from the text at the caret; typing attributes only carry pending inline styles.
            kinds = [Self.caretKind(text, at: range.location, typing: typing)]
        }
        readInlineStyles(text, range: range, typing: typing, caretKind: range.length == 0 ? kinds.first : nil)
        paragraph = kinds.count == 1 ? kinds.first : nil
        let tasks = samples.compactMap { attributes -> Bool? in
            let kind = attributes[.journalKind] as? String
            return kind == "checked" ? true : kind == "task" ? false : nil
        }
        if !tasks.isEmpty { taskCompletion = Self.toggle(tasks) }
        indent = Self.indentation(text, range: range, kinds: kinds, size: size)
    }
    /// The kind of the line at a caret: its paragraph's, or on the empty last line after a list, which is a plain
    /// line, what typing there starts.
    @MainActor static func caretKind(
        _ text: NSAttributedString, at location: Int, typing: [NSAttributedString.Key: Any]
    ) -> String {
        guard text.length > 0 else { return typing[.journalKind] as? String ?? "paragraph" }
        if RichText.continuesAfterList(text, at: location) {
            let kind = typing[.journalKind] as? String ?? "paragraph"
            return ListIndentation.kinds.contains(kind) ? "paragraph" : kind
        }
        let line = (text.string as NSString).paragraphRange(
            for: NSRange(location: min(location, text.length), length: 0))
        let kind = text.attribute(.journalKind, at: min(line.location, text.length - 1), effectiveRange: nil)
        return kind as? String ?? "paragraph"
    }
    /// Increase and Decrease Indent for a selection, for the menus, without reading its other formatting.
    @MainActor static func indentation(
        _ text: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any], size: CGFloat
    ) -> ListIndentation.Availability {
        guard text.length > 0, NSMaxRange(range) <= text.length else { return ListIndentation.Availability() }
        var kinds: Set<String> = []
        if range.length == 0 {
            kinds = [caretKind(text, at: range.location, typing: typing)]
        } else {
            text.enumerateAttribute(.journalKind, in: range) { value, _, _ in
                kinds.insert(value as? String ?? "paragraph")
            }
        }
        return indentation(text, range: range, kinds: kinds, size: size)
    }
    /// Increase and Decrease Indent: list items by their structure, code by whether a line has a tab to add or remove.
    @MainActor private static func indentation(
        _ text: NSAttributedString, range: NSRange, kinds: Set<String>, size: CGFloat
    ) -> ListIndentation.Availability {
        if kinds.contains("codeBlock") {
            return ListIndentation.Availability(
                increase: StructuredKeyboard.edit(.indent, text: text, selection: range, size: size) != nil,
                decrease: StructuredKeyboard.edit(.outdent, text: text, selection: range, size: size) != nil)
        }
        guard !kinds.isDisjoint(with: ListIndentation.kinds) else { return ListIndentation.Availability() }
        return ListIndentation.availability(text, selection: range, size: size)
    }
    /// The five inline styles, each from the characters that can carry it (InlineStyles.carries), which is also what
    /// the commands change, so a control that shows Mixed shows On after one press. A caret reads the block's kind
    /// from the text, since typing attributes only carry pending inline styles.
    @MainActor private mutating func readInlineStyles(
        _ text: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any], caretKind: String?
    ) {
        func state(_ style: InlineStyle) -> FormattingToggle {
            guard let caretKind else { return InlineStyles.state(style, in: text, range: range) }
            return InlineStyles.state(style, typing: typing.merging([.journalKind: caretKind]) { $1 })
        }
        bold = state(.bold)
        italic = state(.italic)
        underline = state(.underline)
        strikethrough = state(.strikethrough)
        code = state(.code)
    }
    func toggle(for style: InlineStyle) -> FormattingToggle {
        switch style {
        case .bold: return bold
        case .italic: return italic
        case .underline: return underline
        case .strikethrough: return strikethrough
        case .code: return code
        }
    }
    /// In source mode the state comes from the Markdown syntax around the selection.
    private mutating func readSource(_ source: String, range: NSRange) {
        let text = source as NSString
        guard NSMaxRange(range) <= text.length else { return }
        func wrapped(_ command: EditorCommand) -> FormattingToggle {
            guard let pair = SourceFormatting.delimiters(for: command) else { return .off }
            return SourceFormatting.wrappedRange(pair, in: text, around: range) == nil ? .off : .on
        }
        bold = wrapped(.bold)
        italic = wrapped(.italic)
        underline = wrapped(.underline)
        strikethrough = wrapped(.strikethrough)
        code = wrapped(.code)
        let lines = text.substring(with: SourceFormatting.lineRange(in: text, containing: range))
            .components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let kinds = Set(lines.map(SourceFormatting.kind(ofLine:)))
        paragraph = kinds.count <= 1 ? (kinds.first ?? "paragraph") : nil
        let tasks = kinds.compactMap { $0 == "checked" ? true : $0 == "task" ? false : nil }
        if !tasks.isEmpty { taskCompletion = Self.toggle(tasks) }
    }
    private static func toggle(_ values: [Bool]) -> FormattingToggle {
        if values.allSatisfy({ $0 }) { return .on }
        return values.contains(true) ? .mixed : .off
    }
}

/// The web and email addresses Add Link accepts. The sheet and every editor check with this, so an address the sheet
/// allows is never dropped by the editor.
enum LinkAddress {
    /// The address with its scheme in lowercase, or nil when it isn't a web or email address. As in Notes, an
    /// address without a scheme is completed: name@example.com becomes a mailto: link and www.example.com an
    /// https:// link.
    static func url(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let schemes = ["http:", "https:", "mailto:"]
        guard schemes.contains(where: lowered.hasPrefix) || trimmed.contains("://") else {
            return completed(trimmed)
        }
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased() else {
            return nil
        }
        components.scheme = scheme
        guard let url = components.url else { return nil }
        if scheme == "mailto" { return url.path.contains("@") ? url : nil }
        return ["http", "https"].contains(scheme) && !(url.host ?? "").isEmpty ? url : nil
    }
    /// An email address or a host name with a domain, written without a scheme.
    private static func completed(_ address: String) -> URL? {
        guard !address.contains(where: { $0.isWhitespace }) else { return nil }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard !parts[0].isEmpty, !address.contains(where: { "/:?#".contains($0) }), isDomain(parts[1]) else {
                return nil
            }
            return URL(string: "mailto:" + address)
        }
        guard parts.count == 1, let url = URL(string: "https://" + address), let host = url.host, isDomain(host[...])
        else { return nil }
        return url
    }
    /// A name such as example.com: labels separated by dots, ending in a top-level domain of two or more letters.
    private static func isDomain(_ host: Substring) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1, labels.allSatisfy({ !$0.isEmpty }), let last = labels.last else { return false }
        return last.count >= 2 && last.allSatisfy(\.isLetter)
    }
}

@MainActor
enum LinkInsertion {
    static func text(
        _ source: NSAttributedString, selection: NSRange, address: String, displayText: String?,
        attributes: [NSAttributedString.Key: Any], url: URL
    ) -> NSAttributedString {
        let original = source.attributedSubstring(from: selection)
        let label = displayText.flatMap { $0.isEmpty ? nil : $0 } ?? (selection.length == 0 ? address : original.string)
        let result =
            label == original.string
            ? NSMutableAttributedString(attributedString: original)
            : NSMutableAttributedString(string: label, attributes: attributes)
        result.addAttribute(.link, value: url, range: NSRange(location: 0, length: result.length))
        return result
    }
}
