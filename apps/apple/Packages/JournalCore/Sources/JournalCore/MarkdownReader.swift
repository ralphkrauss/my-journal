import Foundation
import Markdown

enum MarkdownReader {
    struct Result {
        var blocks: [DocumentBlock] = []
        var segments: [String] = []
        var starts: [Int] = []
        var ends: [Int] = []
        var leading = ""
        var tails: [String] = []
        var requiresSource = false
    }
    /// Byte offsets where each line starts. Like cmark, a line ends at LF, CR or CRLF.
    static func lineStarts(_ bytes: [UInt8]) -> [Int] {
        var starts = [0]
        var index = 0
        while index < bytes.count {
            if bytes[index] == 13, index + 1 < bytes.count, bytes[index + 1] == 10 { index += 1 }
            if bytes[index] == 10 || bytes[index] == 13 { starts.append(index + 1) }
            index += 1
        }
        return starts
    }
    /// The source's lines without their line endings, numbered as cmark numbers them.
    static func lines(_ source: String) -> [String] {
        lines(Array(source.utf8), starts: lineStarts(Array(source.utf8)))
    }
    private static func lines(_ bytes: [UInt8], starts: [Int]) -> [String] {
        starts.indices.map { index in
            var end = index + 1 < starts.count ? starts[index + 1] : bytes.count
            while end > starts[index], [10, 13].contains(bytes[end - 1]) { end -= 1 }
            return String(decoding: bytes[starts[index]..<end], as: UTF8.self)
        }
    }
    static func read(_ source: String) -> Result {
        let tree = Document(parsing: source, options: .disableSmartOpts)
        var result = Result()
        let bytes = Array(source.utf8)
        let offsets = lineStarts(bytes)
        let lines = lines(bytes, starts: offsets)
        var found: [(DocumentBlock, Markup)] = []
        for node in tree.children {
            guard let leaves = leaves(node, lines: lines) else {
                result.requiresSource = true
                continue
            }
            found += leaves
        }
        let positions = positions(of: found.map(\.1), offsets: offsets, lines: lines, bytes: bytes)
        // Blocks whose place in the source is unknown can only be edited as Markdown source.
        if positions == nil { result.requiresSource = true }
        if result.requiresSource {
            result.blocks = images(in: tree)
            return result
        }
        result.blocks = found.map(\.0)
        var starts = positions?.starts ?? []
        result.ends = positions?.ends ?? []
        if starts.isEmpty {
            if !source.isEmpty {
                result.blocks = [DocumentBlock()]
                result.segments = [source]
                result.leading = source
                result.tails = [""]
            }
            return result
        }
        result.starts = starts
        result.leading = String(decoding: bytes[..<starts[0]], as: UTF8.self)
        starts[0] = 0
        for index in starts.indices {
            let end = index + 1 < starts.count ? starts[index + 1] : bytes.count
            result.segments.append(String(decoding: bytes[starts[index]..<end], as: UTF8.self))
            result.tails.append(String(decoding: bytes[min(result.ends[index], end)..<end], as: UTF8.self))
        }
        return result
    }
    /// Where each block's first line starts and where the block ends, as byte offsets. Nil unless the blocks follow
    /// one another in the source.
    private static func positions(of nodes: [Markup], offsets: [Int], lines: [String], bytes: [UInt8]) -> (
        starts: [Int], ends: [Int]
    )? {
        var starts: [Int] = []
        var ends: [Int] = []
        var tableLines: [Int: Int] = [:]
        for (index, node) in nodes.enumerated() {
            let startLine: Int
            let end: Int
            if let range = node.range {
                // A paragraph that starts with link reference definitions still reports their first line. Its text
                // is on its last lines, one per line break, so the definitions stay out of the block's own source.
                let textLine = node is Paragraph ? range.upperBound.line - lineBreaks(in: node) : 0
                startLine = tableLines[index] ?? max(range.lowerBound.line, textLine)
                let endLine = min(max(1, range.upperBound.line), offsets.count)
                end = min(bytes.count, offsets[endLine - 1] + max(0, range.upperBound.column - 1))
            } else if let paragraph = node as? Paragraph, index + 1 < nodes.count, nodes[index + 1] is Table,
                let table = nodes[index + 1].range
            {
                // A table interrupting a paragraph takes the paragraph's position, and the paragraph gets none:
                // the paragraph keeps its lines and the table starts at its header row.
                let count = lineBreaks(in: paragraph) + 1
                startLine = table.lowerBound.line
                let endLine = startLine + count - 1
                guard lines.indices.contains(endLine - 1) else { return nil }
                end = offsets[endLine - 1] + lines[endLine - 1].utf8.count
                tableLines[index + 1] = endLine + 1
            } else {
                return nil
            }
            guard offsets.indices.contains(startLine - 1) else { return nil }
            let start = offsets[startLine - 1]
            guard start >= (starts.last ?? 0), end >= start else { return nil }
            starts.append(start)
            // A setext heading or indented code ends after its line ending, which belongs with the text after it.
            var trimmed = end
            if trimmed > start, bytes[trimmed - 1] == 10 { trimmed -= 1 }
            if trimmed > start, bytes[trimmed - 1] == 13 { trimmed -= 1 }
            ends.append(trimmed)
        }
        return (starts, ends)
    }
    private static func lineBreaks(in node: Markup) -> Int {
        node.children.reduce(node is SoftBreak || node is LineBreak ? 1 : 0) { $0 + lineBreaks(in: $1) }
    }
    private static func leaves(_ node: Markup, prefix: String = "", indents: [Int] = [], lines: [String]) -> [(
        DocumentBlock, Markup
    )]? {
        if node is OrderedList || node is UnorderedList {
            return listLeaves(node, prefix: prefix, indents: indents, lines: lines)
        }
        if node is BlockQuote {
            var result: [(DocumentBlock, Markup)] = []
            for child in node.children {
                guard let nested = leaves(child, prefix: prefix + "> ", indents: indents, lines: lines) else {
                    return nil
                }
                result += nested
            }
            return result
        }
        guard var block = readBlock(node) else { return nil }
        if block.kind == "paragraph", prefix.hasSuffix("> ") {
            block.kind = "quote"
            block.markdownPrefix = String(prefix.dropLast(2))
            block.markdownContinuation = prefix
        } else {
            block.markdownPrefix = prefix.isEmpty ? nil : prefix
        }
        block.listIndents = indents.isEmpty ? nil : indents
        return [(block, node)]
    }
    private static func listLeaves(_ node: Markup, prefix: String, indents: [Int], lines: [String]) -> [(
        DocumentBlock, Markup
    )]? {
        var result: [(DocumentBlock, Markup)] = []
        let start = Int((node as? OrderedList)?.startIndex ?? 1)
        for (index, child) in node.children.enumerated() {
            guard let item = child as? ListItem else { return nil }
            let checkbox = MarkdownTasks.checkbox(item, lines: lines)
            let kind =
                checkbox.map { $0 == .checked ? "checked" : "task" }
                ?? (node is OrderedList ? "numbered" : "bullet")
            let written = sourceMarker(item, lines: lines)
            let marker = written ?? (node is OrderedList ? "\(start + index). " : "- ")
            let continuation = prefix + String(repeating: " ", count: marker.count)
            if item.childCount == 0 {
                var block = DocumentBlock(kind: kind)
                block.markdownPrefix = prefix.isEmpty ? nil : prefix
                block.listNumber = node is OrderedList ? start + index : nil
                block.listIndents = indents.isEmpty ? nil : indents
                block.listMarker = written
                result.append((block, child))
            }
            for (position, content) in item.children.enumerated() {
                // An item's first paragraph is read as its text, even when it holds only an image.
                if position == 0, let paragraph = content as? Paragraph, let runs = readRuns(paragraph) {
                    var block = DocumentBlock(kind: kind, runs: runs)
                    block.listMarker = written
                    if checkbox != nil, item.checkbox == nil, !block.runs.isEmpty {
                        block.runs[0].text = String(block.runs[0].text.dropFirst(4))
                    }
                    block.markdownPrefix = prefix.isEmpty ? nil : prefix
                    block.markdownContinuation = continuation
                    block.listNumber = node is OrderedList ? start + index : nil
                    block.listIndents = indents.isEmpty ? nil : indents
                    result.append((block, content))
                } else {
                    let contentPrefix = position == 0 ? prefix + marker : continuation
                    guard
                        var nested = leaves(
                            content, prefix: contentPrefix, indents: indents + [marker.count], lines: lines)
                    else {
                        return nil
                    }
                    if position == 0, !nested.isEmpty { nested[0].0.markdownContinuation = continuation }
                    result += nested
                }
            }
        }
        return result
    }
    /// The item's marker as written, such as "* " or "2) ", with the spaces before its content, so a rewritten item
    /// stays in its list and keeps its children nested. Nil when the spelling can't be kept exactly.
    private static func sourceMarker(_ item: ListItem, lines: [String]) -> String? {
        guard let start = item.range?.lowerBound,
            let content = item.children.first(where: { _ in true })?.range?.lowerBound,
            content.line == start.line, lines.indices.contains(start.line - 1)
        else { return nil }
        let bytes = Array(lines[start.line - 1].utf8)
        guard start.column >= 1, content.column > start.column, content.column - 1 <= bytes.count else { return nil }
        var marker = String(decoding: bytes[(start.column - 1)..<(content.column - 1)], as: UTF8.self)
        if item.checkbox != nil, let box = marker.firstIndex(of: "[") { marker = String(marker[..<box]) }
        return MarkdownWriter.isListMarker(marker) ? marker : nil
    }
    private static func images(in node: Markup) -> [DocumentBlock] {
        if let image = node as? Image, let path = image.source, path.hasPrefix("attachments/"),
            let id = UUID(uuidString: String(path.dropFirst("attachments/".count)))
        {
            return [
                DocumentBlock(
                    kind: "image", attachmentID: id, imageDescription: image.plainText.isEmpty ? nil : image.plainText)
            ]
        }
        return node.children.flatMap { images(in: $0) }
    }
    private static func readBlock(_ node: Markup, ordered: Bool = false) -> DocumentBlock? {
        if let table = node as? Table {
            let rows = [Array(table.head.children)] + table.body.children.map { Array($0.children) }
            var cells: [[[TextRun]]] = []
            for row in rows {
                var values: [[TextRun]] = []
                for cell in row {
                    guard let runs = readRuns(cell) else { return nil }
                    values.append(runs)
                }
                cells.append(values)
            }
            let alignments: [String?] = table.columnAlignments.map { alignment in
                switch alignment {
                case .left: return "left"
                case .center: return "center"
                case .right: return "right"
                case nil: return nil
                }
            }
            var block = DocumentBlock(kind: "table")
            block.table = DocumentTable(rows: cells, alignments: alignments)
            return block
        }
        if let code = node as? CodeBlock {
            var block = DocumentBlock(kind: "codeBlock", runs: [TextRun(code.code)])
            block.codeLanguage = code.language
            return block
        }
        if let html = node as? HTMLBlock {
            return DocumentBlock(kind: "html", runs: [TextRun(html.rawHTML)])
        }
        if node is ThematicBreak { return DocumentBlock(kind: "rule") }
        if let item = node as? ListItem {
            guard item.childCount == 1, let paragraph = item.children.first(where: { _ in true }) as? Paragraph,
                let runs = readRuns(paragraph)
            else { return nil }
            let kind = item.checkbox.map { $0 == .checked ? "checked" : "task" } ?? (ordered ? "numbered" : "bullet")
            return DocumentBlock(kind: kind, runs: runs)
        }
        if let quote = node as? BlockQuote {
            guard quote.childCount == 1, let paragraph = quote.children.first(where: { _ in true }) as? Paragraph,
                let runs = readRuns(paragraph)
            else { return nil }
            return DocumentBlock(kind: "quote", runs: runs)
        }
        if let heading = node as? Heading, let runs = readRuns(heading) {
            let kind = heading.level == 1 ? "heading" : heading.level == 2 ? "subheading" : "heading\(heading.level)"
            return DocumentBlock(kind: kind, runs: runs)
        }
        guard let paragraph = node as? Paragraph else { return nil }
        if paragraph.childCount == 1, let image = paragraph.children.first(where: { _ in true }) as? Image,
            let path = image.source, path.hasPrefix("attachments/"),
            let id = UUID(uuidString: String(path.dropFirst("attachments/".count))), (image.title ?? "").isEmpty
        {
            return DocumentBlock(
                kind: "image", attachmentID: id, imageDescription: image.plainText.isEmpty ? nil : image.plainText)
        }
        guard let runs = readRuns(paragraph) else { return nil }
        return DocumentBlock(runs: runs)
    }
    private static func readRuns(_ node: Markup, style: TextRun = TextRun("")) -> [TextRun]? {
        var runs: [TextRun] = []
        var current = style
        let closesUnderline = node.children.contains { ($0 as? InlineHTML)?.rawHTML == "</u>" }
        for child in node.children {
            if let html = child as? InlineHTML {
                if html.rawHTML == "<!-- -->" { continue }
                if html.rawHTML == "<u>", !current.underline, closesUnderline {
                    current.underline = true
                    continue
                }
                if html.rawHTML == "</u>", current.underline {
                    current.underline = false
                    continue
                }
                var literal = current
                literal.text = html.rawHTML
                literal.rawHTML = true
                runs.append(literal)
                continue
            }
            var run = current
            if let text = child as? Text {
                run.text = text.string
                runs.append(run)
            } else if let code = child as? InlineCode {
                run.text = code.code
                run.code = true
                runs.append(run)
            } else if let image = child as? Image {
                run.text = image.plainText
                run.imageSource = image.source ?? ""
                run.imageTitle = image.title
                runs.append(run)
            } else if child is SoftBreak || child is LineBreak {
                run.text = "\n"
                run.breakKind = child is SoftBreak ? "soft" : "hard"
                runs.append(run)
            } else {
                if child is Strong {
                    run.bold = true
                } else if child is Emphasis {
                    run.italic = true
                } else if child is Strikethrough {
                    run.strikethrough = true
                } else if let link = child as? Link {
                    run.link = link.destination
                    run.linkTitle = link.title
                } else {
                    return nil
                }
                guard let nested = readRuns(child, style: run) else { return nil }
                runs += nested
            }
        }
        return runs
    }
}
