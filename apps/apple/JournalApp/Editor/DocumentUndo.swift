import JournalCore
import SwiftUI

/// Typing in one table cell is a single undo step, as typing in the text is: each key press replaces the step with one
/// that still returns to the text as it was before the typing began.
@MainActor final class CellTypingUndo {
    let cell: AnyHashable
    let snapshot: NativeEditor.Coordinator.Snapshot
    /// The entry as this typing left it. Any other change in between starts a new step.
    var document: JournalDocument
    init(cell: AnyHashable, snapshot: NativeEditor.Coordinator.Snapshot) {
        self.cell = cell
        self.snapshot = snapshot
        document = snapshot.document
    }
}

extension NativeEditor.Coordinator {
    struct Snapshot {
        let text: NSAttributedString
        let document: JournalDocument
        let source: Bool
        let selection: NSRange
        let typing: [NSAttributedString.Key: Any]
    }

    /// Keep canonical Markdown trivia alongside native text when undoing structural edits.
    func registerSnapshot(actionName: String? = nil, typingIn cell: AnyHashable? = nil) {
        guard let view, let undo = view.undoManager else { return }
        guard let cell else {
            cellTyping = nil
            let snapshot = currentSnapshot(of: view)
            undo.registerUndo(withTarget: self) { $0.restore(snapshot, actionName: actionName) }
            if let actionName { undo.setActionName(actionName) }
            return
        }
        let typing =
            cellTyping.flatMap { $0.cell == cell && $0.document == parent.document ? $0 : nil }
            ?? CellTypingUndo(cell: cell, snapshot: currentSnapshot(of: view))
        // The step registered for the previous key press gives way to this one.
        undo.removeAllActions(withTarget: typing)
        // The undo manager doesn't keep its target; the step itself does.
        undo.registerUndo(withTarget: typing) { [weak self, typing] _ in
            self?.restore(typing.snapshot, actionName: actionName)
        }
        if let actionName { undo.setActionName(actionName) }
        cellTyping = typing
    }

    private func currentSnapshot(of view: JournalTextView) -> Snapshot {
        #if os(macOS)
            let text = NSAttributedString(attributedString: view.attributedString())
            let selection = view.selectedRange()
        #else
            let text = NSAttributedString(attributedString: view.attributedText)
            let selection = view.selectedRange
        #endif
        return Snapshot(
            text: text, document: parent.document, source: showsSource, selection: selection,
            typing: view.typingAttributes)
    }

    private func restore(_ snapshot: Snapshot, actionName: String?) {
        restoreSnapshot(
            snapshot.text, document: snapshot.document, source: snapshot.source, selection: snapshot.selection,
            typing: snapshot.typing, actionName: actionName)
    }

    private func restoreSnapshot(
        _ text: NSAttributedString, document: JournalDocument, source: Bool, selection: NSRange,
        typing: [NSAttributedString.Key: Any], actionName: String?
    ) {
        guard let view else { return }
        registerSnapshot(actionName: actionName)
        view.undoManager?.disableUndoRegistration()
        defer { view.undoManager?.enableUndoRegistration() }
        parent.document = document
        rendered = document
        // The view mode is part of the snapshot, so undoing View Source shows the preview again.
        showsSource = source
        cellTyping = nil
        replacingText = true
        #if os(macOS)
            view.textStorage?.setAttributedString(text)
            replacingText = false
            view.setSelectedRange(selection)
            view.typingAttributes = typing
            view.didChangeText()
        #else
            view.attributedText = text
            replacingText = false
            view.selectedRange = selection
            view.typingAttributes = typing
            textViewDidChange(view)
            revealCaretAfterEdit()
        #endif
    }
}
