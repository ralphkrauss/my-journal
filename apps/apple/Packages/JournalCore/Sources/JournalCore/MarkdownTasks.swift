import Foundation
import Markdown

enum MarkdownTasks {
    /// cmark can leave a nested task marker as literal text. Check its source spelling so escaped markers stay literal.
    static func checkbox(_ item: ListItem, lines: [String]) -> Checkbox? {
        if let checkbox = item.checkbox { return checkbox }
        guard let paragraph = item.children.first(where: { _ in true }) as? Paragraph,
            let start = paragraph.range?.lowerBound,
            lines.indices.contains(start.line - 1)
        else { return nil }
        let bytes = Array(lines[start.line - 1].utf8)
        let offset = start.column - 1
        guard offset >= 0, offset + 3 < bytes.count, bytes[offset] == 91, bytes[offset + 2] == 93,
            [9, 32].contains(bytes[offset + 3])
        else { return nil }
        switch bytes[offset + 1] {
        case 32: return .unchecked
        case 88, 120: return .checked
        default: return nil
        }
    }
}
