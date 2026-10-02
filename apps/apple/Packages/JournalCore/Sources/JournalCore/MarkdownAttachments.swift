import Foundation
import Markdown

enum MarkdownAttachments {
    private static let prefix = Array("attachments/".utf8)

    /// Replaces the attachment identities that images refer to, including through reference definitions. An
    /// occurrence is replaced only if everything else the parser reads stays the same, so paths quoted in code or
    /// text are left alone. Throws if an image would still refer to a replaced identity.
    static func remap(_ source: String, mapping: [UUID: UUID]) throws -> String {
        let expected = signature(source, mapping: mapping)
        let original = Array(source.utf8)
        let occurrences = occurrences(in: original, mapping: mapping)
        var all = original
        for (offset, replacement) in occurrences {
            all.replaceSubrange(offset..<(offset + replacement.count), with: replacement)
        }
        var result = String(decoding: all, as: UTF8.self)
        if signature(result, mapping: mapping) != expected {
            // Something besides image references quotes an identity: replace one occurrence at a time.
            var bytes = original
            for (offset, replacement) in occurrences {
                var candidate = bytes
                candidate.replaceSubrange(offset..<(offset + replacement.count), with: replacement)
                if signature(String(decoding: candidate, as: UTF8.self), mapping: mapping) == expected {
                    bytes = candidate
                }
            }
            result = String(decoding: bytes, as: UTF8.self)
        }
        guard signature(result, mapping: mapping) == expected, !refersToReplaced(result, mapping: mapping) else {
            throw JournalError.invalidData
        }
        return result
    }
    /// Where `attachments/<identity>` appears for a replaced identity, with its replacement of the same length.
    private static func occurrences(in bytes: [UInt8], mapping: [UUID: UUID]) -> [(Int, [UInt8])] {
        var result: [(Int, [UInt8])] = []
        var offset = 0
        let length = prefix.count + 36
        while offset + length <= bytes.count {
            if bytes[offset..<(offset + prefix.count)].elementsEqual(prefix),
                let id = UUID(
                    uuidString: String(decoding: bytes[(offset + prefix.count)..<(offset + length)], as: UTF8.self)),
                let replacement = mapping[id]
            {
                result.append((offset, Array(("attachments/" + replacement.uuidString.lowercased()).utf8)))
                offset += length
            } else {
                offset += 1
            }
        }
        return result
    }
    /// Everything the parser reads, in order, with image references expressed after remapping.
    private static func signature(_ source: String, mapping: [UUID: UUID]) -> [String] {
        var tokens: [String] = []
        func visit(_ node: Markup) {
            tokens.append(token(node, mapping: mapping) + "\u{0}\(node.childCount)")
            for child in node.children { visit(child) }
        }
        visit(Document(parsing: source, options: .disableSmartOpts))
        return tokens
    }
    private static func token(_ node: Markup, mapping: [UUID: UUID]) -> String {
        let name = String(describing: type(of: node))
        let parts: [String]
        switch node {
        case let text as Text: parts = [text.string]
        case let code as InlineCode: parts = [code.code]
        case let code as CodeBlock: parts = [code.language ?? "", code.code]
        case let html as HTMLBlock: parts = [html.rawHTML]
        case let html as InlineHTML: parts = [html.rawHTML]
        case let link as Link: parts = [link.destination ?? "", link.title ?? ""]
        case let image as Image: parts = [remapped(image.source ?? "", mapping: mapping), image.title ?? ""]
        case let heading as Heading: parts = ["\(heading.level)"]
        case let item as ListItem: parts = [String(describing: item.checkbox)]
        case let list as OrderedList: parts = ["\(list.startIndex)"]
        case let table as Table: parts = [String(describing: table.columnAlignments)]
        default: parts = []
        }
        return ([name] + parts).joined(separator: "\u{0}")
    }
    private static func remapped(_ path: String, mapping: [UUID: UUID]) -> String {
        guard path.hasPrefix("attachments/"), let id = UUID(uuidString: String(path.dropFirst("attachments/".count)))
        else { return path }
        return "attachments/" + (mapping[id] ?? id).uuidString.lowercased()
    }
    private static func refersToReplaced(_ source: String, mapping: [UUID: UUID]) -> Bool {
        func visit(_ node: Markup) -> Bool {
            if let image = node as? Image, let path = image.source, path.hasPrefix("attachments/"),
                let id = UUID(uuidString: String(path.dropFirst("attachments/".count))), mapping[id] != nil
            {
                return true
            }
            return node.children.contains { visit($0) }
        }
        return visit(Document(parsing: source, options: .disableSmartOpts))
    }
}
