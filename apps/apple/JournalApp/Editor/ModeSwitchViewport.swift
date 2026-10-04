import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Keeps the caret's line at the same height in the window when the whole entry changes representation.
extension NativeEditor.Coordinator {
    func caretViewportOffset() -> CGFloat? {
        guard let view, let caret = caretLineTop(in: view) else { return nil }
        #if os(macOS)
            return caret - view.visibleRect.minY
        #else
            return caret - view.contentOffset.y
        #endif
    }

    func restoreCaretViewportOffset(_ offset: CGFloat?) {
        guard let view, let offset, let caret = caretLineTop(in: view) else { return }
        #if os(macOS)
            // The room below the line being typed is part of the visible rectangle and can be scrolled into.
            let room = view.enclosingScrollView?.contentInsets.bottom ?? 0
            let maximum = max(0, view.frame.height - view.visibleRect.height + room)
            view.scroll(NSPoint(x: 0, y: min(maximum, max(0, caret - offset))))
        #else
            let minimum = -view.adjustedContentInset.top
            let maximum = max(
                minimum, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
            view.setContentOffset(CGPoint(x: 0, y: min(maximum, max(minimum, caret - offset))), animated: false)
        #endif
    }

    func announceMode(source: Bool) {
        let announcement = source ? "Source" : "Preview"
        #if os(macOS)
            guard let view else { return }
            NSAccessibility.post(
                element: view, notification: .announcementRequested,
                userInfo: [
                    .announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
        #else
            UIAccessibility.post(notification: .announcement, argument: announcement)
        #endif
    }

    #if os(macOS)
        private func caretLineTop(in view: JournalTextView) -> CGFloat? {
            guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
            layout.ensureLayout(for: container)
            let location = view.selectedRange().location
            let rect: NSRect
            if location >= layout.numberOfGlyphs || location >= view.string.utf16.count {
                let extra = layout.extraLineFragmentRect
                guard !extra.isEmpty || layout.numberOfGlyphs > 0 else { return nil }
                rect =
                    extra.isEmpty
                    ? layout.lineFragmentRect(forGlyphAt: layout.numberOfGlyphs - 1, effectiveRange: nil) : extra
            } else {
                let glyph = layout.glyphIndexForCharacter(at: location)
                rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            return rect.minY + view.textContainerOrigin.y
        }
    #else
        private func caretLineTop(in view: JournalTextView) -> CGFloat? {
            view.layoutIfNeeded()
            guard let position = view.selectedTextRange?.start else { return nil }
            let rect = view.caretRect(for: position)
            return rect.isNull || rect.isInfinite ? nil : rect.minY
        }
    #endif
}
