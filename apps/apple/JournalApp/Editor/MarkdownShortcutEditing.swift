import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Wires Markdown shortcuts into the editor: the typed space goes in as usual, then the conversion follows as a
/// separate undo step, so Backspace or ⌘Z straight after it restores exactly what was typed.
extension NativeEditor.Coordinator {
    /// Called for every change the text view is about to make. Returns false when the change was handled here.
    func markdownShortcutShouldChange(in range: NSRange, replacement: String) -> Bool {
        let revert = shortcutRevert
        shortcutRevert = nil
        // The editor's own replacements are complete already.
        guard let view, !replacingText, !hasMarkedText(view) else { return true }
        if let revert, replacement.isEmpty, range.length == 1, NSMaxRange(range) == revert.convertedCaret,
            storage(of: view).length == revert.length
        {
            replace(revert.original, range: revert.range, actionName: "Typing")
            select(NSRange(location: revert.caret, length: 0), in: view)
            return false
        }
        if replacement.isEmpty, removeItemFormatting(deleting: range) { return false }
        if replacement.isEmpty, deleteHiddenMarker(range) { return false }
        if replacement == " ", range.length == 0, MarkdownShortcuts.enabled, !editingSource {
            let caret = range.location + 1
            DispatchQueue.main.async { [weak self] in self?.applySpaceShortcut(caret: caret) }
        }
        return true
    }

    /// Return on a line that is a code fence (“```”) or a horizontal rule (“---”) turns it into that block.
    func convertLineOnReturn(selection: NSRange) -> Bool {
        guard MarkdownShortcuts.enabled, let view, !hasMarkedText(view), !editingSource, selection.length == 0 else {
            return false
        }
        let text = storage(of: view)
        guard let line = MarkdownShortcuts.plainParagraph(text, at: selection.location),
            NSMaxRange(line) == selection.location, line.length > 0,
            let value = MarkdownShortcuts.block(forLine: (text.string as NSString).substring(with: line))
        else { return false }
        // Typing may not have reached the document yet, so read it from the text as it is now.
        let document = MarkdownEditing.read(text, previous: parent.document)
        let before = RichText.document(text.attributedSubstring(from: NSRange(location: 0, length: line.location)))
        let index = line.location == 0 ? 0 : before.blocks.count - 1
        guard document.blocks.indices.contains(index),
            let edit = MarkdownEditing.convertLine(
                value, blockID: document.blocks[index].id, document: document, size: parent.fontSize,
                images: parent.images, layout: imageLayout, range: NSRange(location: 0, length: text.length))
        else { return false }
        breakTypingUndo(view)
        replace(edit.text, range: edit.range, actionName: value == "---" ? "Horizontal Rule" : "Code Block")
        if let caret = edit.selection { select(caret, in: view) }
        announce(value == "---" ? "Horizontal rule" : "Code block")
        return true
    }

    private func applySpaceShortcut(caret: Int) {
        guard let view, !editingSource, selection(of: view) == NSRange(location: caret, length: 0),
            let conversion = MarkdownShortcuts.afterSpace(
                storage(of: view), caret: caret, size: parent.fontSize, images: parent.images,
                width: max(40, view.bounds.width - 20))
        else { return }
        let original = storage(of: view).attributedSubstring(from: conversion.range)
        // The typing and the conversion are separate steps, so ⌘Z first gives back what was typed.
        breakTypingUndo(view)
        replace(conversion.replacement, range: conversion.range, actionName: conversion.announcement)
        select(NSRange(location: conversion.caret, length: 0), in: view)
        view.typingAttributes = conversion.typing
        shortcutRevert = MarkdownShortcuts.Revert(
            range: NSRange(location: conversion.range.location, length: conversion.replacement.length),
            original: original, caret: caret, convertedCaret: conversion.caret, length: storage(of: view).length)
        announce(conversion.announcement)
    }

    /// Backspace (or Option- or Command-Backspace) at the start of a list item, task or quote removes one level of
    /// its formatting instead of the hidden marker. Returns false when the text view can delete as asked.
    private func removeItemFormatting(deleting range: NSRange) -> Bool {
        guard let view, parent.editable, !editingSource else { return false }
        let caret = selection(of: view)
        guard caret.length == 0, range.length > 0, NSMaxRange(range) == caret.location,
            let edit = ItemFormattingRemoval.edit(
                storage(of: view), caret: caret.location, size: parent.fontSize, images: parent.images)
        else { return false }
        breakTypingUndo(view)
        replace(edit.text, range: edit.range, actionName: edit.actionName)
        select(NSRange(location: edit.caret, length: 0), in: view)
        view.typingAttributes = edit.typing
        announce(edit.announcement)
        return true
    }
    private func breakTypingUndo(_ view: JournalTextView) {
        #if os(macOS)
            view.breakUndoCoalescing()
        #endif
    }
    private func announce(_ message: String) {
        #if os(macOS)
            guard let view else { return }
            NSAccessibility.post(
                element: view, notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        #else
            UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
    private func storage(of view: JournalTextView) -> NSAttributedString {
        #if os(macOS)
            view.attributedString()
        #else
            view.attributedText ?? NSAttributedString()
        #endif
    }
    private func selection(of view: JournalTextView) -> NSRange {
        #if os(macOS)
            view.selectedRange()
        #else
            view.selectedRange
        #endif
    }
    private func select(_ range: NSRange, in view: JournalTextView) {
        #if os(macOS)
            view.setSelectedRange(range)
        #else
            view.selectedRange = range
        #endif
    }
    private func hasMarkedText(_ view: JournalTextView) -> Bool {
        #if os(macOS)
            view.hasMarkedText()
        #else
            view.markedTextRange != nil
        #endif
    }
}
