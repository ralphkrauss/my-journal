import JournalCore
import SwiftUI

struct TableCellAddress: Hashable {
    let row: Int
    let column: Int
}

extension NSAttributedString.Key {
    static let journalTable = Self("JournalTable")
}

@MainActor enum TablePresentation {
    struct Layout {
        let columnWidth: CGFloat
        let rowHeights: [CGFloat]
        var width: CGFloat { columnWidth * CGFloat(columns) }
        let columns: Int
        var height: CGFloat { rowHeights.reduce(0, +) }
        func cell(row: Int, column: Int) -> CGRect {
            CGRect(
                x: CGFloat(column) * columnWidth, y: rowHeights.prefix(row).reduce(0, +),
                width: columnWidth, height: rowHeights[row])
        }
    }
    /// Cell padding and minimum row height: compact rows on the Mac, touch-sized rows on iPhone and iPad.
    #if os(macOS)
        static let padding = CGSize(width: 8, height: 6)
        static let minimumRowHeight: CGFloat = 0
    #else
        static let padding = CGSize(width: 10, height: 10)
        static let minimumRowHeight: CGFloat = 44
    #endif
    static func layout(_ table: DocumentTable, width: CGFloat, size: CGFloat) -> Layout {
        let columns = max(1, table.columnCount)
        let cellWidth = max(size * 7, width / CGFloat(columns))
        let heights: [CGFloat] = table.rows.enumerated().map { index, row in
            row.map { runs in
                let value = text(runs, size: size, header: index == 0)
                let bounds = value.boundingRect(
                    with: CGSize(width: cellWidth - padding.width * 2, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                let font = RichText.font(size: size)
                #if os(macOS)
                    let line = ceil(font.ascender - font.descender + font.leading)
                #else
                    let line = ceil(font.lineHeight)
                #endif
                return max(minimumRowHeight, ceil(max(bounds.height, line)) + padding.height * 2)
            }.max() ?? minimumRowHeight
        }
        return Layout(columnWidth: cellWidth, rowHeights: heights, columns: columns)
    }
    /// Header cells (Markdown's first row) are semibold for display only; the stored text is unchanged.
    static func text(_ runs: [TextRun], size: CGFloat, images: [UUID: Data] = [:], header: Bool = false)
        -> NSAttributedString
    {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            if run.imageSource != nil {
                result.append(RichText.inlineImage(run, size: size, images: images))
                continue
            }
            result.append(
                NSAttributedString(
                    string: run.text,
                    attributes: RichText.attributes(kind: header ? "tableHeader" : "paragraph", size: size, run: run)))
        }
        return result
    }
    static func render(_ block: DocumentBlock, width: CGFloat, size: CGFloat) -> NSAttributedString {
        guard let table = block.table, let data = try? JournalCoding.encoder().encode(block) else {
            return NSAttributedString()
        }
        let layout = layout(table, width: width, size: size)
        let attachment = NSTextAttachment()
        #if os(macOS)
            let image = NSImage(size: NSSize(width: width, height: layout.height), flipped: false) { _ in true }
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        #else
            // The grid draws the table. Without an image UIKit would draw its file placeholder behind the cells.
            attachment.image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
            attachment.bounds = CGRect(x: 0, y: 0, width: width, height: layout.height)
        #endif
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttributes(
            [.journalTable: data, .journalKind: "table", .journalBlockID: block.id.uuidString],
            range: NSRange(location: 0, length: result.length))
        return result
    }
    /// Header cells are bold by style, so their bold font never becomes Markdown emphasis. UIKit drops the
    /// block kind from typing attributes, so the row decides instead of the typed text.
    static func runs(_ text: NSAttributedString, header: Bool) -> [TextRun] {
        guard header, text.length > 0 else { return RichText.document(text).blocks.flatMap(\.runs) }
        let marked = NSMutableAttributedString(attributedString: text)
        marked.addAttribute(.journalKind, value: "tableHeader", range: NSRange(location: 0, length: marked.length))
        return RichText.document(marked).blocks.flatMap(\.runs)
    }
}

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension RichText {
    static func tableSelectionMarkdown(_ text: NSAttributedString, range: NSRange) -> String? {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        var containsTable = false
        text.enumerateAttribute(.journalTable, in: range) { value, _, _ in if value != nil { containsTable = true } }
        guard containsTable else { return nil }
        return document(text.attributedSubstring(from: range)).markdown
    }
}
