import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Wires Markdown shortcuts into the editor: the space that completes a shortcut goes in, then the conversion follows
/// as a separate undo step, so Backspace or ⌘Z straight after it restores exactly what was typed.
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
            revealOnTheMac()
            return false
        }
        if replacement.isEmpty, removeItemFormatting(deleting: range) { return false }
        if !editingSource, applyItemEdit(in: range, replacement: replacement) { return false }
        // The last item's own line break goes only with all of the text (ListEditing.swift).
        if replacement.isEmpty, range.length == 1, range.location > 0, NSMaxRange(range) == storage(of: view).length,
            ListMarkers.hasOwnEnd(storage(of: view))
        {
            return false
        }
        if replacement.isEmpty, deleteHiddenMarker(range) { return false }
        if replacement == " ", range.length == 0, MarkdownShortcuts.enabled, !editingSource,
            convertShortcut(typingSpaceAt: range.location)
        {
            return false
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
        revealOnTheMac()
        announce(value == "---" ? "Horizontal rule" : "Code block")
        return true
    }

    /// The space that completes a Markdown shortcut at the start of a line converts the line within the same change:
    /// the editor types the space and then converts the line, as two undo steps, and the text view doesn't type it.
    /// Nothing is left for later, so keys the keyboard already has on their way arrive after both, where the caret
    /// then is. Build 15's first fix converted on a later turn of the run loop, and letters typed in between could
    /// land in the item above or leave the marker as typed. Returns false when the space completes no shortcut.
    private func convertShortcut(typingSpaceAt location: Int) -> Bool {
        guard let view, parent.editable else { return false }
        let text = storage(of: view)
        guard let line = MarkdownShortcuts.plainParagraph(text, at: location), location > line.location,
            location <= NSMaxRange(line)
        else { return false }
        let marker = (text.string as NSString).substring(
            with: NSRange(location: line.location, length: location - line.location))
        guard MarkdownShortcuts.style(forMarker: marker + " ") != nil else { return false }
        // The space as typed, its own undo step.
        beginOwnUndoStep(view)
        replace(
            NSAttributedString(string: " ", attributes: view.typingAttributes),
            range: NSRange(location: location, length: 0), actionName: "Typing")
        let caret = location + 1
        select(NSRange(location: caret, length: 0), in: view)
        guard
            let conversion = MarkdownShortcuts.afterSpace(
                storage(of: view), caret: caret, size: parent.fontSize, images: parent.images,
                width: max(40, view.bounds.width - 20))
        else { return true }
        let original = storage(of: view).attributedSubstring(from: conversion.range)
        // The typing and the conversion are separate steps, so ⌘Z first gives back what was typed.
        beginOwnUndoStep(view)
        replace(conversion.replacement, range: conversion.range, actionName: conversion.announcement)
        select(NSRange(location: conversion.caret, length: 0), in: view)
        view.typingAttributes = conversion.typing
        shortcutRevert = MarkdownShortcuts.Revert(
            range: NSRange(location: conversion.range.location, length: conversion.replacement.length),
            original: original, caret: caret, convertedCaret: conversion.caret, length: storage(of: view).length)
        revealOnTheMac()
        announce(conversion.announcement)
        return true
    }

    /// Return in a list item or quote, and deletions that join lines when an item is one of them, as the editor's own
    /// undoable step (ListEditing.swift). Returns false when the text view can make
    /// the change itself.
    private func applyItemEdit(in range: NSRange, replacement: String) -> Bool {
        guard let view, parent.editable, !checkingOwnReplacement else { return false }
        // An input method composing over the selection replaces it itself.
        guard replacement.isEmpty || replacement == "\n" || !view.settingMarkedText else { return false }
        let text = storage(of: view)
        let typing = view.typingAttributes
        let action: RichText.NewlineAction?
        if replacement == "\n" {
            action = RichText.newlineAction(text, selection: range, size: parent.fontSize)
        } else {
            action = RichText.joining(text, range: range, replacement: replacement, typing: typing)
        }
        guard let action else { return false }
        breakTypingUndo(view)
        replace(action.replacement, range: action.range)
        if let caret = action.caret { select(NSRange(location: caret, length: 0), in: view) }
        view.typingAttributes = RichText.typing(after: action, in: storage(of: view), size: parent.fontSize)
        revealOnTheMac()
        return true
    }

    /// Backspace at the start of the text, where the text view itself does nothing: on a list item, task or quote it
    /// removes one level of its formatting. Returns false otherwise.
    func removeItemFormattingAtStart() -> Bool {
        guard let view, selection(of: view) == NSRange(location: 0, length: 0), !hasMarkedText(view) else {
            return false
        }
        let revert = shortcutRevert
        shortcutRevert = nil
        // Straight after a shortcut on the first line, Backspace gives back what was typed, as it does elsewhere.
        if let revert, revert.convertedCaret == 0, storage(of: view).length == revert.length {
            replace(revert.original, range: revert.range, actionName: "Typing")
            select(NSRange(location: revert.caret, length: 0), in: view)
            revealOnTheMac()
            return true
        }
        return removeItemFormatting(deleting: NSRange(location: 0, length: 0), atStart: true)
    }

    /// Backspace (or Option- or Command-Backspace) at the start of a list item, task or quote removes one level of
    /// its formatting. Returns false when the text view can delete as asked.
    private func removeItemFormatting(deleting range: NSRange, atStart: Bool = false) -> Bool {
        guard let view, parent.editable, !editingSource else { return false }
        let caret = selection(of: view)
        guard caret.length == 0, range.length > 0 || atStart, NSMaxRange(range) == caret.location,
            let edit = ItemFormattingRemoval.edit(
                storage(of: view), caret: caret.location, size: parent.fontSize, images: parent.images)
        else { return false }
        breakTypingUndo(view)
        replace(edit.text, range: edit.range, actionName: edit.actionName)
        select(NSRange(location: edit.caret, length: 0), in: view)
        view.typingAttributes = edit.typing
        revealOnTheMac()
        announce(edit.announcement)
        return true
    }
    /// iPhone and iPad reveal the caret after every edit of the editor's own (SelectionReveal.swift).
    private func revealOnTheMac() {
        #if os(macOS)
            revealCaretAfterKey()
        #endif
    }
    /// Makes the next change an undo step of its own, also within one key press, whose changes the undo manager
    /// would otherwise undo together.
    private func beginOwnUndoStep(_ view: JournalTextView) {
        breakTypingUndo(view)
        guard let undo = view.undoManager, undo.groupsByEvent, undo.groupingLevel == 1 else { return }
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
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
