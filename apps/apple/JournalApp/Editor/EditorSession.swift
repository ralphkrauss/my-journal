import JournalCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Edits, input method compositions and arriving images, the same way on the Mac and on iPhone and iPad.
extension NativeEditor.Coordinator {
    /// Takes the document read from the text after an edit. While a change from elsewhere waits for a composition to
    /// end, the edit is applied on top of that change instead of replacing it.
    func acceptEdit(_ local: JournalDocument) {
        let base = rendered ?? parent.document
        let document =
            pendingExternal == nil ? local : ExternalEdits.rebase(local: local, base: base, remote: parent.document)
        if parent.actions.sourceMode != showsSource { parent.actions.sourceMode = showsSource }
        rendered = local
        if pendingExternal != nil { pendingExternal = document }
        if parent.document != document {
            sessionGeneration = UUID()
            parent.document = document
        }
    }

    /// Shows images that arrived and any change from elsewhere that waited for the composition. The committed text
    /// reaches the document first.
    func compositionEnded() {
        refreshImages()
        guard pendingExternal != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pendingExternal != nil, self.view != nil else { return }
            self.pendingExternal = nil
            self.update(self.parent)
        }
    }

    /// Undo keeps the most recent steps; each structural step holds a copy of the entry's text.
    func limitUndo() {
        guard let undo = view?.undoManager, undo.levelsOfUndo == 0 else { return }
        undo.levelsOfUndo = 100
    }

    /// A command applies to finished text, so an input method's composition is committed first.
    func commitComposition(before command: EditorCommand) {
        if case .focus = command { return }
        commitComposition()
    }

    /// Commits an input method's composition, such as before the keyboard makes way for the Format panel.
    func commitComposition() {
        guard let view else { return }
        #if os(macOS)
            guard view.hasMarkedText() else { return }
            view.unmarkText()
            view.inputContext?.discardMarkedText()
        #else
            guard view.markedTextRange != nil else { return }
            view.unmarkText()
        #endif
    }

    /// Imports pasted or dropped pictures, in order, and inserts each where it was put, even if writing continues
    /// meanwhile.
    func receiveImages(_ images: [PastedImages.Source]) {
        guard !images.isEmpty, let insertion = formattingSession() else { return }
        let id = parent.itemID
        let handler = parent.imageHandler
        Task { [weak self] in
            for image in images {
                guard let data = await PastedImages.data(for: image), let block = await handler(data), let self,
                    self.parent.itemID == id
                else { continue }
                insertion(.image(block))
            }
        }
    }
}
