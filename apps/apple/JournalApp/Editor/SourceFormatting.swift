import Foundation
import JournalCore

/// Formatting commands applied to Markdown source text: every command edits syntax, nothing is rendered.
enum SourceFormatting {
    struct Change: Equatable {
        let range: NSRange
        let replacement: String
        let selection: NSRange
    }

    static let paragraphPrefixes: [String: String] = [
        "heading": "# ", "subheading": "## ", "heading3": "### ", "heading4": "#### ", "heading5": "##### ",
        "heading6": "###### ", "bullet": "- ", "numbered": "1. ", "task": "- [ ] ", "checked": "- [x] ",
        "quote": "> ", "paragraph": "",
    ]
    /// One leading block marker: heading, task, bullet, ordered item or quote.
    private static let blockPrefix =
        #"^[ \t]{0,3}(#{1,6}[ \t]+|[-+*][ \t]+\[[ xX]\][ \t]+|[-+*][ \t]+|[0-9]{1,9}[.)][ \t]+|>[ \t]?)"#

    static func delimiters(for command: EditorCommand) -> (open: String, close: String)? {
        switch command {
        case .bold: return ("**", "**")
        case .italic: return ("*", "*")
        case .strikethrough: return ("~~", "~~")
        case .code: return ("`", "`")
        case .underline: return ("<u>", "</u>")
        default: return nil
        }
    }

    static func change(_ command: EditorCommand, in source: String, selection: NSRange) -> Change? {
        let text = source as NSString
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        if let pair = delimiters(for: command) {
            return inline(pair, in: text, selection: selection)
        }
        switch command {
        case .paragraph(let kind):
            return paragraph(kind, in: text, selection: selection)
        case .toggleTask:
            return toggleTasks(in: text, selection: selection)
        case .link(let address, let label):
            let selected = text.substring(with: selection)
            let title = label.flatMap { $0.isEmpty ? nil : $0 } ?? (selected.isEmpty ? address : selected)
            let destination = address.contains(where: { " ()<>".contains($0) }) ? "<" + address + ">" : address
            let link = "[" + title + "](" + destination + ")"
            return Change(
                range: selection, replacement: link,
                selection: NSRange(location: selection.location + link.utf16.count, length: 0))
        case .image(let image):
            let markdown = JournalDocument(blocks: [image]).markdown.trimmingCharacters(in: .newlines)
            return block(markdown, in: text, at: NSMaxRange(selection), caretOffset: nil)
        case .insert(let value):
            return insert(value, in: text, selection: selection)
        default:
            return nil
        }
    }

    // MARK: Inline styles

    private static func inline(_ pair: (open: String, close: String), in text: NSString, selection: NSRange) -> Change?
    {
        if let wrapped = wrappedRange(pair, in: text, around: selection) {
            // Remove the syntax around (or included in) the selection.
            let inner = NSRange(
                location: wrapped.location + pair.open.utf16.count,
                length: wrapped.length - pair.open.utf16.count - pair.close.utf16.count)
            let content = text.substring(with: inner)
            let start = max(inner.location, selection.location) - pair.open.utf16.count
            let end = min(NSMaxRange(inner), NSMaxRange(selection)) - pair.open.utf16.count
            let updated =
                selection.length == 0
                ? NSRange(location: selection.location - pair.open.utf16.count, length: 0)
                : NSRange(location: start, length: max(0, end - start))
            return Change(range: wrapped, replacement: content, selection: updated)
        }
        if selection.length == 0 {
            let open = pair.open.utf16.count
            let pairRange = NSRange(location: selection.location - open, length: open + pair.close.utf16.count)
            if pairRange.location >= 0, NSMaxRange(pairRange) <= text.length,
                text.substring(with: pairRange) == pair.open + pair.close
            {
                // A second press with nothing typed removes the empty pair.
                return Change(
                    range: pairRange, replacement: "", selection: NSRange(location: pairRange.location, length: 0))
            }
            return Change(
                range: selection, replacement: pair.open + pair.close,
                selection: NSRange(location: selection.location + pair.open.utf16.count, length: 0))
        }
        // Wrap each line separately, keeping block markers and surrounding spaces outside the syntax.
        let lines = text.substring(with: selection).components(separatedBy: "\n")
        var offset = selection.location
        var output: [String] = []
        var first: NSRange?
        for line in lines {
            let atLineStart = offset == lineStart(in: text, at: offset)
            let marker = atLineStart ? prefixLength(of: line) : 0
            let body = String(line.utf16.dropFirst(marker)) ?? line
            let leading = body.prefix(while: { $0 == " " || $0 == "\t" })
            let trailing = body.dropFirst(leading.count).reversed().prefix(while: { $0 == " " || $0 == "\t" })
            let content = String(body.dropFirst(leading.count).dropLast(trailing.count))
            let head = String(line.utf16.prefix(marker)) ?? ""
            if content.isEmpty {
                output.append(line)
            } else {
                let wrappedLine = head + leading + pair.open + content + pair.close + String(trailing.reversed())
                if first == nil {
                    let location =
                        selection.location + output.joined(separator: "\n").utf16.count + (output.isEmpty ? 0 : 1)
                        + head.utf16.count + leading.utf16.count + pair.open.utf16.count
                    first = NSRange(location: location, length: content.utf16.count)
                }
                output.append(wrappedLine)
            }
            offset += line.utf16.count + 1
        }
        let replacement = output.joined(separator: "\n")
        let updated =
            lines.count == 1
            ? (first ?? NSRange(location: selection.location, length: replacement.utf16.count))
            : NSRange(location: selection.location, length: replacement.utf16.count)
        return Change(range: selection, replacement: replacement, selection: updated)
    }

    /// The range of `open…close` that wraps the selection, whether or not the selection includes the syntax.
    static func wrappedRange(_ pair: (open: String, close: String), in text: NSString, around selection: NSRange)
        -> NSRange?
    {
        let open = pair.open.utf16.count
        let close = pair.close.utf16.count
        let selected = text.substring(with: selection)
        if selection.length >= open + close, selected.hasPrefix(pair.open), selected.hasSuffix(pair.close),
            isExact(pair.open, in: text, at: selection.location),
            isExact(pair.close, in: text, at: NSMaxRange(selection) - close)
        {
            return selection
        }
        let line = lineRange(in: text, containing: selection)
        guard NSMaxRange(selection) <= NSMaxRange(line) else { return nil }
        // Nearest opening delimiter before the selection and closing delimiter after it, on the same line.
        var start = selection.location - open
        while start >= line.location {
            if text.substring(with: NSRange(location: start, length: open)) == pair.open,
                isExact(pair.open, in: text, at: start)
            {
                break
            }
            start -= 1
        }
        guard start >= line.location else { return nil }
        var end = NSMaxRange(selection)
        while end + close <= NSMaxRange(line) {
            if text.substring(with: NSRange(location: end, length: close)) == pair.close,
                isExact(pair.close, in: text, at: end)
            {
                break
            }
            end += 1
        }
        guard end + close <= NSMaxRange(line) else { return nil }
        let inner = text.substring(with: NSRange(location: start + open, length: end - start - open))
        guard !inner.contains(pair.open), pair.open == pair.close || !inner.contains(pair.close) else { return nil }
        return NSRange(location: start, length: end + close - start)
    }

    /// Single-character delimiters must not be part of a longer run (`*` is not half of `**`).
    private static func isExact(_ delimiter: String, in text: NSString, at location: Int) -> Bool {
        guard let first = delimiter.first, delimiter.allSatisfy({ $0 == first }), "*~`".contains(first) else {
            return true
        }
        let marker = String(first)
        let before = location > 0 ? text.substring(with: NSRange(location: location - 1, length: 1)) : ""
        let afterIndex = location + delimiter.utf16.count
        let after = afterIndex < text.length ? text.substring(with: NSRange(location: afterIndex, length: 1)) : ""
        return before != marker && after != marker
    }

    // MARK: Paragraph styles

    private static func paragraph(_ kind: String, in text: NSString, selection: NSRange) -> Change? {
        guard let prefix = paragraphPrefixes[kind] else { return nil }
        let range = lineRange(in: text, containing: selection)
        let lines = text.substring(with: range).components(separatedBy: "\n")
        if lines.count == 1, lines[0].trimmingCharacters(in: .whitespaces).isEmpty {
            return blankLine(prefix, in: text, line: range)
        }
        var number = 0
        var output: [String] = []
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                output.append(line)
                continue
            }
            let marker = prefixLength(of: line)
            let content = String(line.utf16.dropFirst(marker)) ?? line
            number += 1
            output.append((kind == "numbered" ? "\(number). " : prefix) + content)
        }
        var replacement = output.joined(separator: "\n")
        var shift = 0
        // A paragraph directly after a list item or quote would continue it; keep them apart.
        if kind == "paragraph", range.location > 0 {
            let previous = lineRange(in: text, containing: NSRange(location: range.location - 1, length: 0))
            if prefixLength(of: text.substring(with: previous)) > 0 {
                replacement = "\n" + replacement
                shift = 1
            }
        }
        let updated: NSRange
        if lines.count == 1 {
            // Keep the caret on the same content character after the line marker changes.
            let oldMarker = prefixLength(of: lines[0])
            let newMarker = replacement.utf16.count - shift - (lines[0].utf16.count - oldMarker)
            let content = max(0, selection.location - range.location - oldMarker)
            let length = min(selection.length, max(0, NSMaxRange(range) - selection.location))
            updated = NSRange(location: range.location + shift + newMarker + content, length: length)
        } else {
            updated = NSRange(location: range.location + shift, length: replacement.utf16.count - shift)
        }
        return Change(range: range, replacement: replacement, selection: updated)
    }

    /// A style applied on an empty line starts its own block without joining the neighbors.
    private static func blankLine(_ prefix: String, in text: NSString, line: NSRange) -> Change? {
        guard !prefix.isEmpty else { return nil }
        let before = line.location > 0 && !previousLineIsBlank(in: text, before: line.location)
        let after = NSMaxRange(line) < text.length && !nextLineIsBlank(in: text, after: NSMaxRange(line))
        let replacement = (before ? "\n" : "") + prefix + (after ? "\n" : "")
        let caret = line.location + (before ? 1 : 0) + prefix.utf16.count
        return Change(range: line, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    private static func toggleTasks(in text: NSString, selection: NSRange) -> Change? {
        let range = lineRange(in: text, containing: selection)
        let lines = text.substring(with: range).components(separatedBy: "\n")
        let pattern = #"^([ \t]*[-+*][ \t]+\[)([ xX])(\][ \t])"#
        let tasks = lines.compactMap { $0.range(of: pattern, options: .regularExpression) != nil ? $0 : nil }
        guard !tasks.isEmpty else { return nil }
        let complete = !tasks.allSatisfy {
            $0.range(of: #"^[ \t]*[-+*][ \t]+\[[xX]\]"#, options: .regularExpression) != nil
        }
        let output = lines.map { line in
            line.replacingOccurrences(
                of: pattern, with: complete ? "$1x$3" : "$1 $3", options: .regularExpression)
        }
        return Change(range: range, replacement: output.joined(separator: "\n"), selection: selection)
    }

    // MARK: Inserted blocks

    private static func insert(_ value: String, in text: NSString, selection: NSRange) -> Change? {
        guard !value.isEmpty else { return nil }
        let fragment = JournalDocument(markdown: value)
        guard fragment.blocks.contains(where: { ["codeBlock", "rule", "table"].contains($0.kind) }) else {
            return Change(
                range: selection, replacement: value,
                selection: NSRange(location: selection.location + value.utf16.count, length: 0))
        }
        let snippet = value.trimmingCharacters(in: .newlines)
        if snippet.hasPrefix("```") {
            if selection.length > 0 {
                // Fence the selected lines instead of replacing them.
                let lines = lineRange(in: text, containing: selection)
                let body = text.substring(with: lines)
                return block(
                    "```\n" + body + "\n```", in: text, replacing: lines,
                    caretOffset: 4)
            }
            return block(snippet, in: text, at: NSMaxRange(selection), caretOffset: 4)
        }
        return block(snippet, in: text, at: NSMaxRange(selection), caretOffset: snippet.hasPrefix("|") ? 2 : nil)
    }

    private static func block(_ snippet: String, in text: NSString, at location: Int, caretOffset: Int?) -> Change {
        // Insert after the current line so no existing text is split or replaced.
        let line = lineRange(in: text, containing: NSRange(location: location, length: 0))
        let blank = text.substring(with: line).trimmingCharacters(in: .whitespaces).isEmpty
        return block(
            snippet, in: text, replacing: blank ? line : NSRange(location: NSMaxRange(line), length: 0),
            caretOffset: caretOffset)
    }

    private static func block(_ snippet: String, in text: NSString, replacing range: NSRange, caretOffset: Int?)
        -> Change
    {
        let before = text.substring(to: range.location)
        let after = text.substring(from: NSMaxRange(range))
        let leading = before.isEmpty ? 0 : max(0, 2 - before.reversed().prefix(while: { $0 == "\n" }).count)
        let trailing = after.isEmpty ? 1 : max(0, 2 - after.prefix(while: { $0 == "\n" }).count)
        let prefix = String(repeating: "\n", count: leading)
        let replacement = prefix + snippet + String(repeating: "\n", count: trailing)
        // Without a position inside the block, the caret moves on to the following content (or the new last line).
        let following = after.prefix(while: { $0 == "\n" }).utf16.count
        let caret = caretOffset.map { prefix.utf16.count + $0 } ?? replacement.utf16.count + following
        return Change(
            range: range, replacement: replacement,
            selection: NSRange(location: range.location + caret, length: 0))
    }

    // MARK: Lines

    /// The lines touched by the selection, without the final line break.
    static func lineRange(in text: NSString, containing selection: NSRange) -> NSRange {
        var range = text.lineRange(for: selection)
        if range.length > 0, text.character(at: NSMaxRange(range) - 1) == 0x0A { range.length -= 1 }
        return range
    }
    private static func lineStart(in text: NSString, at location: Int) -> Int {
        text.lineRange(for: NSRange(location: location, length: 0)).location
    }
    static func prefixLength(of line: String) -> Int {
        guard let match = line.range(of: blockPrefix, options: .regularExpression) else { return 0 }
        return line[match].utf16.count
    }
    static func kind(ofLine line: String) -> String {
        let marker = (String(line.utf16.prefix(prefixLength(of: line))) ?? "").trimmingCharacters(in: .whitespaces)
        let headings = ["heading", "subheading", "heading3", "heading4", "heading5", "heading6"]
        let level = marker.prefix(while: { $0 == "#" }).count
        if level > 0 { return headings[min(level, headings.count) - 1] }
        if marker.hasPrefix(">") { return "quote" }
        if marker.hasSuffix("]") { return marker.lowercased().contains("[x]") ? "checked" : "task" }
        if marker.first?.isNumber == true { return "numbered" }
        return marker.isEmpty ? "paragraph" : "bullet"
    }
    private static func previousLineIsBlank(in text: NSString, before location: Int) -> Bool {
        let previous = lineRange(in: text, containing: NSRange(location: location - 1, length: 0))
        return text.substring(with: previous).trimmingCharacters(in: .whitespaces).isEmpty
    }
    private static func nextLineIsBlank(in text: NSString, after location: Int) -> Bool {
        guard location + 1 <= text.length else { return true }
        let next = lineRange(in: text, containing: NSRange(location: location + 1, length: 0))
        return text.substring(with: next).trimmingCharacters(in: .whitespaces).isEmpty
    }
}
