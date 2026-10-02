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
    var canIndent = false
    var paragraph: String?

    init() {}
    /// `source` is whether the editor shows the Markdown source; table cells never do.
    init(text: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any], source: Bool? = nil) {
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
        guard !samples.isEmpty else { return }
        var kinds = Set(samples.map { $0[.journalKind] as? String ?? "paragraph" })
        if range.length == 0, text.length > 0 {
            // The block comes from the text at the caret; typing attributes only carry pending inline styles.
            let line = (text.string as NSString).paragraphRange(
                for: NSRange(location: min(range.location, text.length), length: 0))
            let kind = text.attribute(.journalKind, at: min(line.location, text.length - 1), effectiveRange: nil)
            kinds = [kind as? String ?? "paragraph"]
        }
        let caretKind = range.length == 0 ? kinds.first : nil
        // A heading's bold weight is its style, not the Bold format.
        bold = Self.toggle(
            samples.map {
                Self.traits($0).0
                    && !RichText.boldBlockKinds.contains(caretKind ?? $0[.journalKind] as? String ?? "paragraph")
            })
        italic = Self.toggle(samples.map { Self.traits($0).1 })
        underline = Self.toggle(samples.map { ($0[.underlineStyle] as? Int ?? 0) != 0 })
        strikethrough = Self.toggle(samples.map { ($0[.strikethroughStyle] as? Int ?? 0) != 0 })
        code = Self.toggle(samples.map { ($0[.journalCode] as? Int ?? 0) != 0 })
        paragraph = kinds.count == 1 ? kinds.first : nil
        let tasks = samples.compactMap { attributes -> Bool? in
            let kind = attributes[.journalKind] as? String
            return kind == "checked" ? true : kind == "task" ? false : nil
        }
        if !tasks.isEmpty { taskCompletion = Self.toggle(tasks) }
        canIndent = !sourceMode && !kinds.isDisjoint(with: ["bullet", "numbered", "task", "checked", "codeBlock"])
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
    private static func traits(_ attributes: [NSAttributedString.Key: Any]) -> (Bool, Bool) {
        guard let font = attributes[.font] as? PlatformFont else { return (false, false) }
        #if os(macOS)
            let traits = NSFontManager.shared.traits(of: font)
            return (traits.contains(.boldFontMask), traits.contains(.italicFontMask))
        #else
            let traits = font.fontDescriptor.symbolicTraits
            return (traits.contains(.traitBold), traits.contains(.traitItalic))
        #endif
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
