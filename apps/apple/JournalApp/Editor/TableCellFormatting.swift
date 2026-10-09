import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

extension InlineTables {
    var selectedCellText: String? {
        guard let cell = active?.activeCell else { return nil }
        #if os(macOS)
            return (cell.string as NSString).substring(with: cell.selectedRange())
        #else
            return (cell.text as NSString).substring(with: cell.selectedRange)
        #endif
    }
    var selectedCellStyle: FormattingState? {
        guard let cell = active?.activeCell else { return nil }
        #if os(macOS)
            var result = FormattingState(
                text: cell.attributedString(), range: cell.selectedRange(), typing: cell.typingAttributes)
        #else
            var result = FormattingState(
                text: cell.attributedText, range: cell.selectedRange, typing: cell.typingAttributes)
        #endif
        result.paragraph = "tableCell"
        return result
    }
    func cellFormattingSession(fallback: @escaping (EditorCommand) -> Void) -> ((EditorCommand) -> Void)? {
        guard let grid = active, let cell = grid.activeCell else { return nil }
        #if os(macOS)
            let selection = cell.selectedRange()
        #else
            let selection = cell.selectedRange
        #endif
        return { [weak grid, weak cell] command in
            guard let grid, grid.editable, let cell, cell.superview != nil else { return }
            #if os(macOS)
                cell.window?.makeFirstResponder(cell)
                cell.setSelectedRange(selection)
            #else
                cell.becomeFirstResponder()
                cell.selectedRange = selection
            #endif
            if !grid.formatCell(command) { fallback(command) }
        }
    }
}

extension InlineTableGrid {
    @discardableResult func formatCell(_ command: EditorCommand) -> Bool {
        guard editable, let cell = activeCell else { return false }
        #if os(macOS)
            guard let storage = cell.textStorage else { return false }
            let selection = cell.selectedRange()
        #else
            let storage = cell.textStorage
            let selection = cell.selectedRange
        #endif
        if case .focus = command { return true }
        if case .paragraph = command { return true }
        if let typing = MarkdownEditing.typingCommand(
            command, textIsEmpty: false, selection: selection,
            typing: cell.typingAttributes, size: textSize,
            blockKind: storage.length > 0
                ? FormattingState.caretKind(storage, at: selection.location, typing: cell.typingAttributes) : nil)
        {
            cell.typingAttributes = typing
            return true
        }
        let mutation = TableCellFormatting.edit(
            command, text: storage, selection: selection, typing: cell.typingAttributes, size: textSize)
        guard let mutation else { return false }
        storage.replaceCharacters(in: mutation.range, with: mutation.text)
        // Formatting is an undo step of its own, apart from the typing around it.
        #if os(macOS)
            cell.setSelectedRange(mutation.selection)
        #else
            cell.selectedRange = mutation.selection
        #endif
        commit(cell, typing: false)
        return true
    }
}

@MainActor private enum TableCellFormatting {
    struct Mutation {
        let text: NSAttributedString
        let range: NSRange
        let selection: NSRange
    }
    static func edit(
        _ command: EditorCommand, text: NSAttributedString, selection: NSRange,
        typing: [NSAttributedString.Key: Any], size: CGFloat
    ) -> Mutation? {
        switch command {
        case .bold, .italic, .underline, .strikethrough, .code:
            // The one rule of every inline style, in a cell as in the entry (InlineStyles).
            guard
                let edit = MarkdownEditing.edit(
                    command, text: text, selection: selection,
                    document: .init(), size: size, images: [:])
            else { return nil }
            return Mutation(text: edit.text, range: edit.range, selection: edit.selection ?? selection)
        case .link(let address, let label):
            guard let url = LinkAddress.url(address) else { return nil }
            let value = LinkInsertion.text(
                text, selection: selection, address: url.absoluteString, displayText: label, attributes: typing,
                url: url)
            return Mutation(
                text: value, range: selection, selection: NSRange(location: selection.location, length: value.length))
        default: return nil
        }
    }
}
