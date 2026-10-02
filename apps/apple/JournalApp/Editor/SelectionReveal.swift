#if os(iOS)
    import UIKit

    /// Where the entry was scrolled before a sheet made room for the selection, and how much room it had then.
    struct RevealedScroll {
        let offset: CGPoint
        let bottomInset: CGFloat
        let adjustedBottom: CGFloat
        let height: CGFloat
    }

    /// A sheet over the lower part of the entry, such as Format on iPhone, mustn't hide the text being styled.
    extension NativeEditor.Coordinator {
        /// Remembers where the entry is scrolled, before a sheet opens and the keyboard goes away.
        func rememberScroll() {
            guard let view, revealedScroll == nil else { return }
            revealedScroll = RevealedScroll(
                offset: view.contentOffset, bottomInset: view.contentInset.bottom,
                adjustedBottom: view.adjustedContentInset.bottom, height: view.bounds.height)
        }
        /// Scrolls so the caret or selection ends above `top` (window coordinates), as the text view does for the
        /// keyboard, adding room below the text when the selection is near its end.
        func revealSelection(above top: CGFloat) {
            guard let view, let window = view.window, let range = view.selectedTextRange else { return }
            let selection = range.isEmpty ? view.caretRect(for: range.end) : view.firstRect(for: range)
            let bottom = view.convert(selection, to: window).maxY
            let margin: CGFloat = 16
            guard !selection.isNull, bottom > top - margin else { return }
            rememberScroll()
            let covered = view.convert(view.bounds, to: window).maxY - top
            view.contentInset.bottom = max(revealedScroll?.bottomInset ?? 0, covered)
            let offset = CGPoint(x: view.contentOffset.x, y: view.contentOffset.y + bottom - (top - margin))
            view.setContentOffset(offset, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        /// Keeps the caret above the keyboard and its formatting bar after a picture is inserted. The picture's final
        /// size and the returning keyboard both arrive after the insertion, and either pushes the caret out of view,
        /// so the caret is checked again as they do, for a moment, unless the person scrolls.
        func revealCaretAfterImage() {
            revealCaret(for: 2)
        }
        /// Keeps the line being typed clear of the writing controls, whose height follows the text size, after an
        /// edit or once the entry has its new size after rotating. The keyboard and the controls may still be moving
        /// into place, so the caret is checked again as they do.
        func revealCaretWhileWriting() {
            guard let view, view.isFirstResponder else { return }
            revealCaret(for: 0.6)
        }
        /// After a rotation or a window resize, the line being typed is brought back above the writing controls.
        func revealCaretAfterResize() {
            guard let view, view.bounds.size != laidOutSize else { return }
            let resized = laidOutSize != .zero
            laidOutSize = view.bounds.size
            if resized { revealCaretWhileWriting() }
        }
        private func revealCaret(for duration: TimeInterval) {
            let deadline = Date().addingTimeInterval(duration)
            if caretRevealDeadline.map({ $0 < deadline }) ?? true { caretRevealDeadline = deadline }
            DispatchQueue.main.async { [weak self] in self?.keepCaretRevealed() }
            for delay in [0.25, 0.5] where delay < duration {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.keepCaretRevealed() }
            }
        }
        func keepCaretRevealed() {
            guard let deadline = caretRevealDeadline, let view else { return }
            guard Date() < deadline, !view.isTracking, !view.isDecelerating else {
                caretRevealDeadline = nil
                return
            }
            guard view.isFirstResponder, let window = view.window, let range = view.selectedTextRange else { return }
            let caret = view.caretRect(for: range.end)
            guard !caret.isNull, !caret.isInfinite else { return }
            let screen = window.screen.coordinateSpace
            let frame = view.convert(view.bounds, to: screen)
            let controlsTop: CGFloat
            if let capsule = (view.inputAccessoryView as? WritingAccessory)?.capsuleFrame(in: screen) {
                // The writing controls, measured, since they grow with the text size; the caret line stays clear of
                // them with a little room.
                controlsTop = capsule.minY - 12
            } else {
                // The writing bar's capsule is drawn about 17 points above the top of the keyboard's area.
                controlsTop = view.convert(view.keyboardLayoutGuide.layoutFrame, to: screen).minY - 30
            }
            let visibleBottom = min(frame.maxY - view.safeAreaInsets.bottom, controlsTop)
            let overlap = view.convert(caret, to: screen).maxY - visibleBottom
            guard overlap > 0.5 else { return }
            // Short text can't scroll that far by itself; room below it lets the caret line rise above the bar.
            let limit =
                view.contentSize.height + view.adjustedContentInset.bottom - view.bounds.height
            let target = view.contentOffset.y + overlap
            if target > limit { view.contentInset.bottom += target - limit }
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: false)
        }
        /// Puts the entry back where it was, once the sheet has closed. The keyboard, which shortens the entry, may
        /// still be on its way back, so the position is checked against the room there was when the sheet opened.
        func restoreRevealedSelection() {
            guard let view, let original = revealedScroll else { return }
            revealedScroll = nil
            view.contentInset.bottom = original.bottomInset
            let limit = max(
                -view.adjustedContentInset.top, view.contentSize.height + original.adjustedBottom - original.height)
            let offset = CGPoint(x: original.offset.x, y: min(original.offset.y, limit))
            view.setContentOffset(offset, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
#endif
