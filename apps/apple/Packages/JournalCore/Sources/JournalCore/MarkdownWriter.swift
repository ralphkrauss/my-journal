import Foundation

enum MarkdownWriter {
    private static let listKinds: Set<String> = ["bullet", "numbered", "task", "checked"]
    private static let separator = "<!-- -->"

    static func write(_ blocks: [DocumentBlock]) -> String {
        blocks.map(block).joined(separator: "\n\n")
    }
    static func block(_ block: DocumentBlock) -> String {
        let prefix = block.markdownPrefix ?? ""
        let continuation = continuation(of: block, prefix: prefix)
        // Every following line, whichever line ending it follows, stays inside the block's list or quote.
        var result = prefix
        var previous: Unicode.Scalar?
        for scalar in content(block).unicodeScalars {
            if previous == "\n" || previous == "\r" && scalar != "\n" { result += continuation }
            result.unicodeScalars.append(scalar)
            previous = scalar
        }
        return previous == "\n" || previous == "\r" ? result + continuation : result
    }
    private static func continuation(of block: DocumentBlock, prefix: String) -> String {
        let stored = block.markdownContinuation ?? prefix
        // A block restyled from a quote would otherwise start a separate quote on its second line.
        guard block.kind != "quote", stored == prefix + "> " else { return stored }
        return listKinds.contains(block.kind) ? prefix + String(repeating: " ", count: marker(block).count) : prefix
    }
    private static func content(_ block: DocumentBlock) -> String {
        if let table = block.table { return self.table(table) }
        if block.kind == "image", let id = block.attachmentID {
            return "![" + escape(label(block.imageDescription ?? "")) + "](attachments/" + id.uuidString.lowercased()
                + ")"
        }
        if block.kind == "rule" { return "---" }
        if block.kind == "html" {
            // The parser includes the line ending that ends raw HTML; the block separator supplies it again.
            var text = block.runs.map(\.text).joined().unicodeScalars
            if text.last == "\n" { text.removeLast() }
            if text.last == "\r" { text.removeLast() }
            return String(text)
        }
        if block.kind == "codeBlock" {
            let text = block.runs.map(\.text).joined()
            let fence = String(repeating: "`", count: max(3, longestBacktickRun(text) + 1))
            return fence + (block.codeLanguage ?? "") + "\n" + text + (text.isEmpty || text.hasSuffix("\n") ? "" : "\n")
                + fence
        }
        let prefixes = [
            "heading": "# ", "subheading": "## ", "heading3": "### ", "heading4": "#### ",
            "heading5": "##### ", "heading6": "###### ", "quote": "> ",
        ]
        let body = inline(block.runs)
        let text = String(body.reversed().drop(while: \.isNewline).reversed())
        if ["heading", "subheading"].contains(block.kind), text.contains(where: \.isNewline) {
            // Only a setext heading can hold a line break.
            return text + "\n" + (block.kind == "heading" ? "===" : "---")
        }
        if listKinds.contains(block.kind) {
            let box = block.kind == "task" ? "[ ] " : block.kind == "checked" ? "[x] " : ""
            return marker(block) + box + body
        }
        return (prefixes[block.kind] ?? "") + body
    }
    private static func table(_ table: DocumentTable) -> String {
        var lines = table.rows.map { row in
            "| " + row.map { inline($0, table: true) }.joined(separator: " | ") + " |"
        }
        let separator = (0..<table.columnCount).map { column -> String in
            switch table.alignments.indices.contains(column) ? table.alignments[column] : nil {
            case "left": return ":---"
            case "center": return ":---:"
            case "right": return "---:"
            default: return "---"
            }
        }.joined(separator: " | ")
        if !lines.isEmpty { lines.insert("| " + separator + " |", at: 1) }
        return lines.joined(separator: "\n")
    }
    /// The list marker written for an item, keeping the spelling it was read with where it still fits the item.
    /// A task's marker excludes its checkbox.
    private static func marker(_ block: DocumentBlock) -> String {
        let stored = block.listMarker.flatMap { isListMarker($0) ? $0 : nil }
        let ordered = stored.map { $0.first?.isNumber == true } ?? false
        switch block.kind {
        case "bullet":
            return stored.flatMap { ordered ? nil : $0 } ?? "- "
        case "numbered":
            return numbered(ordered ? stored : nil, number: block.listNumber ?? 1)
        default:
            if ordered { return numbered(stored, number: block.listNumber ?? 1) }
            return stored ?? "- "
        }
    }
    private static func numbered(_ marker: String?, number: Int) -> String {
        guard let marker else { return "\(number). " }
        let digits = marker.prefix(while: \.isNumber)
        return Int(digits) == number ? marker : "\(number)" + marker.dropFirst(digits.count)
    }
    /// A bullet ("-", "*" or "+") or ordered ("1." or "1)") marker followed by one to four spaces.
    static func isListMarker(_ marker: String) -> Bool {
        let digits = marker.prefix(while: { $0.isASCII && $0.isNumber })
        let rest = marker.dropFirst(digits.count)
        guard let symbol = rest.first, digits.count <= 9 else { return false }
        let delimiters: Set<Character> = digits.isEmpty ? ["-", "*", "+"] : [".", ")"]
        let spaces = rest.dropFirst()
        return delimiters.contains(symbol) && (1...4).contains(spaces.count) && spaces.allSatisfy { $0 == " " }
    }
    /// Image descriptions are single labels; a blank line inside one would end the image syntax.
    private static func label(_ text: String) -> String { ImageDescription.singleLine(text) }
    private static func inline(_ runs: [TextRun], table: Bool = false) -> String {
        var body = ""
        let lastText = runs.lastIndex { $0.breakKind == nil && !$0.text.isEmpty } ?? -1
        for (index, text) in runs.enumerated() {
            let lineStart = body.isEmpty || body.unicodeScalars.last == "\n" || body.unicodeScalars.last == "\r"
            let edges = LineEdges(start: lineStart, end: endsLine(after: index, in: runs))
            var fragment = run(text, table: table, edges: edges)
            if text.breakKind != nil, lineStart, index < lastText {
                // An empty line would end the paragraph; a backslash break keeps it.
                fragment = "\\\n"
            }
            if needsSeparator(body, fragment) { body += separator }
            body += fragment
        }
        return body
    }
    /// Whether adjacent fragments need an inert comment between them to keep their meaning.
    private static func needsSeparator(_ body: String, _ fragment: String) -> Bool {
        guard let last = body.unicodeScalars.last, let first = fragment.unicodeScalars.first else { return false }
        let delimiters = "*~`".unicodeScalars
        if delimiters.contains(last) && delimiters.contains(first) { return true }
        // "!" directly before a link would make it an image.
        if last == "!" && first == "[" { return true }
        return !canOpen(fragment, after: last) || !canClose(body, before: first)
    }
    /// An emphasis run opens only if it is left-flanking: after a word character it must not be followed by
    /// punctuation, as when a mark starts with an encoded space or a parenthesis.
    private static func canOpen(_ fragment: String, after previous: Unicode.Scalar) -> Bool {
        let scalars = fragment.unicodeScalars
        guard let first = scalars.first, first == "*" || first == "~" else { return true }
        let next = scalars.first { $0 != first }
        guard let next, !isWord(next), !isSpace(next) else { return true }
        return isSpace(previous) || isPunctuation(previous)
    }
    private static func canClose(_ body: String, before next: Unicode.Scalar) -> Bool {
        let scalars = body.unicodeScalars.reversed()
        guard let last = scalars.first, last == "*" || last == "~" else { return true }
        let previous = scalars.first { $0 != last }
        guard let previous, !isWord(previous), !isSpace(previous) else { return true }
        return isSpace(next) || isPunctuation(next)
    }
    private static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }
    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII {
            return scalar.properties.generalCategory != .control && !isWord(scalar) && !isSpace(scalar)
        }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
            .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }
    /// Escapes only characters that would otherwise begin or end Markdown syntax where they appear,
    /// so ordinary punctuation stays readable in the stored source. Decisions are per Unicode scalar, as the
    /// parser sees them, so a "*" inside an emoji sequence such as *️⃣ is escaped too.
    static func escape(_ text: String, atLineStart: Bool = false) -> String {
        let scalars = Array(text.unicodeScalars)
        // A position is at a line start when only spaces or tabs precede it on its line.
        var lineStarts: [Bool] = []
        var lineStart = atLineStart
        for scalar in scalars {
            lineStarts.append(lineStart)
            if scalar == "\n" || scalar == "\r" {
                lineStart = true
            } else if scalar != " " && scalar != "\t" {
                lineStart = false
            }
        }
        var result = String.UnicodeScalarView()
        for index in scalars.indices {
            if needsEscape(scalars, at: index, lineStarts: lineStarts) { result.append("\\") }
            result.append(scalars[index])
        }
        return String(result)
    }
    private static func needsEscape(_ scalars: [Unicode.Scalar], at index: Int, lineStarts: [Bool]) -> Bool {
        let scalar = scalars[index]
        let previous = index > 0 ? scalars[index - 1] : nil
        let next = index + 1 < scalars.count ? scalars[index + 1] : nil
        let separated = next.map { [" ", "\t", "\n", "\r"].contains($0) } ?? true
        func restOfLine(_ allowed: Set<Unicode.Scalar>) -> Bool {
            scalars[index...].prefix { $0 != "\n" && $0 != "\r" }.allSatisfy { allowed.contains($0) }
        }
        switch scalar {
        case "\\", "`", "*", "[", "]", "<", "~", "|":
            return true
        case "_":
            // Intraword underscores cannot open or close emphasis.
            return !(previous.map(isWordCharacter) == true && next.map(isWordCharacter) == true)
        case "&":
            return next == "#" || next?.properties.isAlphabetic == true
        case "#":
            // A trailing run of # after a space would close an ATX heading.
            return lineStarts[index] || previous == " " && restOfLine(["#", " "])
        case ">":
            return lineStarts[index]
        case "-", "+":
            return lineStarts[index] && (separated || next == scalar)
        case "=":
            return lineStarts[index] && restOfLine(["=", " "])
        case ".", ")":
            // Up to nine digits followed by "." or ")" at the start of a line would begin an ordered list.
            var start = index
            while start > 0, ("0"..."9").contains(scalars[start - 1]) { start -= 1 }
            return (1...9).contains(index - start) && lineStarts[start] && separated
        default:
            return false
        }
    }
    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
    private static func longestBacktickRun(_ text: String) -> Int {
        var longest = 0
        var current = 0
        for scalar in text.unicodeScalars {
            current = scalar == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
    /// Whether a run's text begins a line, and whether only spaces follow it before the line ends.
    private struct LineEdges {
        var start: Bool
        var end: Bool
    }
    private static func endsLine(after index: Int, in runs: [TextRun]) -> Bool {
        for next in runs[(index + 1)...] {
            if next.breakKind != nil { return true }
            if next.imageSource != nil || next.rawHTML { return false }
            let scalars = next.text.unicodeScalars
            if scalars.isEmpty || isPlain(next) && scalars.allSatisfy(isEdgeSpace) { continue }
            return !next.code && (scalars.first == "\n" || scalars.first == "\r")
        }
        return true
    }
    private static func isPlain(_ run: TextRun) -> Bool {
        !run.bold && !run.italic && !run.strikethrough && !run.underline && run.link == nil && !run.code
    }
    private static func isEdgeSpace(_ scalar: Unicode.Scalar) -> Bool { scalar == " " || scalar == "\t" }
    private static func run(_ run: TextRun, table: Bool = false, edges: LineEdges) -> String {
        if let image = run.imageSource {
            let destination = image.replacingOccurrences(of: "\\", with: "%5C").replacingOccurrences(
                of: "<", with: "%3C"
            )
            .replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "\n", with: "%0A")
            var value =
                "![" + escape(label(run.text)) + "](<" + cell(destination, table) + ">"
                + quoted(run.imageTitle, table: table) + ")"
            if let link = run.link {
                value = linked(value, address: link, title: run.linkTitle, table: table)
            }
            return value
        }
        guard !run.text.isEmpty else { return "" }
        if run.rawHTML { return run.text }
        if let kind = run.breakKind { return kind == "hard" ? "  \n" : "\n" }
        guard run.code else { return spaced(run, table: table, edges: edges) }
        let fence = String(repeating: "`", count: longestBacktickRun(run.text) + 1)
        let scalars = run.text.unicodeScalars
        let padding =
            scalars.first == "`" || scalars.last == "`"
            || (scalars.first == " " && scalars.last == " " && !scalars.allSatisfy({ $0 == " " }))
        let content = table ? run.text.replacingOccurrences(of: "|", with: "\\|") : run.text
        let span = fence + (padding ? " " : "") + content + (padding ? " " : "") + fence
        return wrapped(emphasized(span, run), run, table: table)
    }
    /// Where a run's edge spaces are written. The parser strips spaces at a line's start or end, and a space just
    /// inside an emphasis delimiter stops it from opening or closing, so those become character references.
    /// Elsewhere they're moved outside the emphasis delimiters, which keeps ordinary text readable in the source.
    private enum SpacePlacement {
        case insideAsReferences
        case insideLinkOrUnderline
        case outside
    }
    private static func spaced(_ run: TextRun, table: Bool, edges: LineEdges) -> String {
        let scalars = Array(run.text.unicodeScalars)
        let leadCount = scalars.prefix(while: isEdgeSpace).count
        let trailCount = scalars.dropFirst(leadCount).reversed().prefix(while: isEdgeSpace).count
        let lead = String(String.UnicodeScalarView(scalars[..<leadCount]))
        let trail = String(String.UnicodeScalarView(scalars[(scalars.count - trailCount)...]))
        let core = String(String.UnicodeScalarView(scalars[leadCount..<(scalars.count - trailCount)]))
        // A run of only spaces is both at the start and at the end of its own text.
        let leadAtEdge = edges.start || core.isEmpty && edges.end
        let leadPlacement = placement(of: run, emptyCore: core.isEmpty, atLineEdge: leadAtEdge)
        let trailPlacement = placement(of: run, emptyCore: core.isEmpty, atLineEdge: edges.end)
        func part(_ spaces: String, _ placement: SpacePlacement, _ wanted: SpacePlacement) -> String {
            placement == wanted ? spaces : ""
        }
        let plainAtLineStart = isPlain(run) && edges.start && lead.isEmpty
        var result =
            references(part(lead, leadPlacement, .insideAsReferences)) + escape(core, atLineStart: plainAtLineStart)
            + references(part(trail, trailPlacement, .insideAsReferences))
        result =
            part(lead, leadPlacement, .insideLinkOrUnderline) + emphasized(result, run)
            + part(trail, trailPlacement, .insideLinkOrUnderline)
        result = wrapped(result, run, table: table)
        let outerLead = part(lead, leadPlacement, .outside)
        let outerTrail = part(trail, trailPlacement, .outside)
        return (leadAtEdge ? references(outerLead) : outerLead) + result
            + (edges.end ? references(outerTrail) : outerTrail)
    }
    private static func placement(of run: TextRun, emptyCore: Bool, atLineEdge: Bool) -> SpacePlacement {
        let wrapped = run.underline || run.link != nil
        guard run.bold || run.italic || run.strikethrough else { return wrapped ? .insideLinkOrUnderline : .outside }
        // Moving a struck space out would visibly break the line, and empty emphasis would not parse.
        if emptyCore || run.strikethrough { return .insideAsReferences }
        if wrapped { return .insideLinkOrUnderline }
        // At a line's edge a reference is needed anyway, so the space keeps its marks.
        return atLineEdge ? .insideAsReferences : .outside
    }
    private static func references(_ spaces: String) -> String {
        spaces.unicodeScalars.map { $0 == " " ? "&#32;" : "&#9;" }.joined()
    }
    private static func emphasized(_ text: String, _ run: TextRun) -> String {
        var result = text
        if run.bold { result = "**" + result + "**" }
        if run.italic { result = "*" + result + "*" }
        if run.strikethrough { result = "~~" + result + "~~" }
        return result
    }
    private static func wrapped(_ text: String, _ run: TextRun, table: Bool) -> String {
        var result = text
        if run.underline { result = "<u>" + result + "</u>" }
        if let link = run.link { result = linked(result, address: link, title: run.linkTitle, table: table) }
        return result
    }
    private static func linked(_ text: String, address: String, title: String?, table: Bool) -> String {
        let destination = address.replacingOccurrences(of: "\\", with: "%5C")
            .replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "<", with: "%3C")
            .replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "\n", with: "%0A")
        return "[" + text + "](<" + cell(destination, table) + ">" + quoted(title, table: table) + ")"
    }
    private static func quoted(_ title: String?, table: Bool) -> String {
        guard let title else { return "" }
        let escaped = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return " \"" + cell(escaped, table) + "\""
    }
    /// Inside a table cell an unescaped pipe would end the cell, even within a link.
    private static func cell(_ text: String, _ table: Bool) -> String {
        table ? text.replacingOccurrences(of: "|", with: "\\|") : text
    }

}
