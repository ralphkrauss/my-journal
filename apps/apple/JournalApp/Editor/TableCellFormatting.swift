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
            typing: cell.typingAttributes, size: textSize)
        {
            cell.typingAttributes = typing
            return true
        }
        let mutation = TableCellFormatting.edit(
            command, text: storage, selection: selection, typing: cell.typingAttributes, size: textSize)
        guard let mutation else { return false }
        if selection.length == 0, mutation.typingOnly {
            cell.typingAttributes = mutation.text.attributes(at: 0, effectiveRange: nil)
        } else {
            storage.replaceCharacters(in: mutation.range, with: mutation.text)
            // Formatting is an undo step of its own, apart from the typing around it.
            #if os(macOS)
                cell.setSelectedRange(mutation.selection)
            #else
                cell.selectedRange = mutation.selection
            #endif
            commit(cell, typing: false)
        }
        return true
    }
}

@MainActor private enum TableCellFormatting {
    struct Mutation {
        let text: NSAttributedString
        let range: NSRange
        let selection: NSRange
        var typingOnly = false
    }
    static func edit(
        _ command: EditorCommand, text: NSAttributedString, selection: NSRange,
        typing: [NSAttributedString.Key: Any], size: CGFloat
    ) -> Mutation? {
        switch command {
        case .bold, .italic, .underline:
            let selected =
                selection.length > 0
                ? text.attributedSubstring(from: selection) : NSAttributedString(string: " ", attributes: typing)
            let result = NSMutableAttributedString(attributedString: selected)
            let state = FormattingState(
                text: selected, range: NSRange(location: 0, length: selected.length), typing: typing)
            result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attributes, range, _ in
                var updated = attributes
                switch command {
                case .underline:
                    updated[.underlineStyle] = state.underline == .on ? 0 : NSUnderlineStyle.single.rawValue
                case .bold, .italic:
                    let font = attributes[.font] as? PlatformFont ?? RichText.font(size: size)
                    updated[.font] = toggledFont(font, command: command, enabled: isEnabled(command, state: state))
                default: break
                }
                result.setAttributes(updated, range: range)
            }
            return Mutation(text: result, range: selection, selection: selection, typingOnly: selection.length == 0)
        case .strikethrough, .code:
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
    private static func isEnabled(_ command: EditorCommand, state: FormattingState) -> Bool {
        if case .bold = command { return state.bold != .on }
        return state.italic != .on
    }
    private static func toggledFont(_ font: PlatformFont, command: EditorCommand, enabled: Bool) -> PlatformFont {
        #if os(macOS)
            let trait: NSFontTraitMask
            if case .bold = command { trait = .boldFontMask } else { trait = .italicFontMask }
            return enabled
                ? NSFontManager.shared.convert(font, toHaveTrait: trait)
                : NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        #else
            let trait: UIFontDescriptor.SymbolicTraits
            if case .bold = command { trait = .traitBold } else { trait = .traitItalic }
            var traits = font.fontDescriptor.symbolicTraits
            if enabled { traits.insert(trait) } else { traits.remove(trait) }
            return UIFont(
                descriptor: font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor, size: font.pointSize)
        #endif
    }
}
