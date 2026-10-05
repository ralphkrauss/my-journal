import Foundation
import Markdown

enum MarkdownAttachments {
    private static let prefix = Array("attachments/".utf8)

    /// Replaces the attachment identities that images refer to, including through reference definitions. An
    /// occurrence is replaced only if everything else the parser reads stays the same, so paths quoted in code or
    /// text are left alone. Throws if an image would still refer to a replaced identity.
    static func remap(_ source: String, mapping: [UUID: UUID]) throws -> String {
        try replace(source) { mapping[$0].map { "attachments/" + $0.uuidString.lowercased() } }
    }
    /// Points images at `paths`, by attachment identity, as `remap` does: for example `attachments/<id>.jpg` for a
    /// file written beside the Markdown (MarkdownExport). Identities without a path are left as they are.
    static func rewrite(_ source: String, paths: [UUID: String]) throws -> String {
        try replace(source) { paths[$0] }
    }
    /// The attachments that images refer to, in order, each once.
    static func imageIDs(in source: String) -> [UUID] {
        var result: [UUID] = []
        func visit(_ node: Markup) {
            if let image = node as? Image, let id = identity(image.source ?? ""), !result.contains(id) {
                result.append(id)
            }
            for child in node.children { visit(child) }
        }
        visit(Document(parsing: source, options: .disableSmartOpts))
        return result
    }
    private static func replace(_ source: String, path: (UUID) -> String?) throws -> String {
        let expected = signature(source, path: path)
        let original = Array(source.utf8)
        // From the end, so a replacement of another length leaves the earlier offsets in place.
        let occurrences = occurrences(in: original, path: path).reversed()
        var all = original
        for (offset, replacement) in occurrences {
            all.replaceSubrange(offset..<(offset + occurrenceLength), with: replacement)
        }
        var result = String(decoding: all, as: UTF8.self)
        if signature(result, path: path) != expected {
            // Something besides image references quotes an identity: replace one occurrence at a time.
            var bytes = original
            for (offset, replacement) in occurrences {
                var candidate = bytes
                candidate.replaceSubrange(offset..<(offset + occurrenceLength), with: replacement)
                if signature(String(decoding: candidate, as: UTF8.self), path: path) == expected {
                    bytes = candidate
                }
            }
            result = String(decoding: bytes, as: UTF8.self)
        }
        guard signature(result, path: path) == expected, !refersToReplaced(result, path: path) else {
            throw JournalError.invalidData
        }
        return result
    }
    private static var occurrenceLength: Int { prefix.count + 36 }
    /// Where `attachments/<identity>` appears for a replaced identity, with its replacement.
    private static func occurrences(in bytes: [UInt8], path: (UUID) -> String?) -> [(Int, [UInt8])] {
        var result: [(Int, [UInt8])] = []
        var offset = 0
        let length = occurrenceLength
        while offset + length <= bytes.count {
            if bytes[offset..<(offset + prefix.count)].elementsEqual(prefix),
                let id = UUID(
                    uuidString: String(decoding: bytes[(offset + prefix.count)..<(offset + length)], as: UTF8.self)),
                let replacement = path(id)
            {
                result.append((offset, Array(replacement.utf8)))
                offset += length
            } else {
                offset += 1
            }
        }
        return result
    }
    /// Everything the parser reads, in order, with image references expressed after replacing.
    private static func signature(_ source: String, path: (UUID) -> String?) -> [String] {
        var tokens: [String] = []
        func visit(_ node: Markup) {
            tokens.append(token(node, path: path) + "\u{0}\(node.childCount)")
            for child in node.children { visit(child) }
        }
        visit(Document(parsing: source, options: .disableSmartOpts))
        return tokens
    }
    private static func identity(_ path: String) -> UUID? {
        guard path.hasPrefix("attachments/") else { return nil }
        return UUID(uuidString: String(path.dropFirst("attachments/".count)))
    }
    private static func token(_ node: Markup, path: (UUID) -> String?) -> String {
        let name = String(describing: type(of: node))
        let parts: [String]
        switch node {
        case let text as Text: parts = [text.string]
        case let code as InlineCode: parts = [code.code]
        case let code as CodeBlock: parts = [code.language ?? "", code.code]
        case let html as HTMLBlock: parts = [html.rawHTML]
        case let html as InlineHTML: parts = [html.rawHTML]
        case let link as Link: parts = [link.destination ?? "", link.title ?? ""]
        case let image as Image:
            let source = image.source ?? ""
            parts = [identity(source).flatMap(path) ?? source, image.title ?? ""]
        case let heading as Heading: parts = ["\(heading.level)"]
        case let item as ListItem: parts = [String(describing: item.checkbox)]
        case let list as OrderedList: parts = ["\(list.startIndex)"]
        case let table as Table: parts = [String(describing: table.columnAlignments)]
        default: parts = []
        }
        return ([name] + parts).joined(separator: "\u{0}")
    }
    private static func refersToReplaced(_ source: String, path: (UUID) -> String?) -> Bool {
        func visit(_ node: Markup) -> Bool {
            if let image = node as? Image, let id = identity(image.source ?? ""), path(id) != nil { return true }
            return node.children.contains { visit($0) }
        }
        return visit(Document(parsing: source, options: .disableSmartOpts))
    }
}
