#if os(iOS)
    import UIKit

    /// The line being typed stays above the writing controls (docs/design/typing-scroll.md). The part of the entry the
    /// controls cover is the text view's bottom inset, so the text view follows the caret itself while typing, as in
    /// Notes, and the editor's own reveals agree with it about what's visible.
    extension NativeEditor.Coordinator {
        /// Room between the line being typed and the writing controls.
        private static let controlsMargin: CGFloat = 12

        /// Measures the writing controls again. Typing never changes the inset; the keyboard, the controls (which grow
        /// with the text size), rotation and the end of editing do.
        func updateWritingInset() {
            guard let view else { return }
            // The safe area, such as the home indicator's, is already part of the adjusted inset.
            let safeArea = view.adjustedContentInset.bottom - view.contentInset.bottom
            let inset = max(0, coveredByWritingControls(view) - safeArea)
            guard abs(view.contentInset.bottom - inset) > 0.5 else { return }
            let shrinking = inset < view.contentInset.bottom
            view.contentInset.bottom = inset
            view.verticalScrollIndicatorInsets.bottom = inset
            guard shrinking else { return }
            // Without the controls, the end of the entry comes back down to the bottom rather than leaving space.
            let limit = max(
                -view.adjustedContentInset.top,
                view.contentSize.height + view.adjustedContentInset.bottom - view.bounds.height)
            if view.contentOffset.y > limit {
                view.setContentOffset(CGPoint(x: view.contentOffset.x, y: limit), animated: false)
            }
        }

        /// How much of the entry's bottom the writing controls cover, with a little room above them: the controls over
        /// the on-screen keyboard, or at the bottom of the screen with a hardware keyboard. Nothing while not writing.
        private func coveredByWritingControls(_ view: UITextView) -> CGFloat {
            let input: UITextView = tables?.active?.activeCell ?? view
            guard input.isFirstResponder, let window = view.window,
                let accessory = input.inputAccessoryView as? WritingAccessory
            else { return 0 }
            let screen = window.screen.coordinateSpace
            guard let capsule = accessory.capsuleFrame(in: screen) else { return 0 }
            let frame = view.convert(view.bounds, to: screen)
            // Controls beside the entry, as with a floating keyboard on iPad or another window in Stage Manager,
            // cover nothing.
            let controlsTop = capsule.minY - Self.controlsMargin
            guard capsule.maxX > frame.minX, capsule.minX < frame.maxX, controlsTop < frame.maxY else { return 0 }
            let covered = frame.maxY - controlsTop
            // Controls high up in a short window still leave a line or two of the entry to write in.
            return min(max(0, covered), max(0, frame.height - 88))
        }

        /// Shows the caret after the editor changed the text itself (a list's Return, a Markdown shortcut, pasting,
        /// undo), which the text view doesn't follow as it does typing.
        func revealCaretAfterEdit() {
            guard let view, view.isFirstResponder, let range = view.selectedTextRange else { return }
            updateWritingInset()
            let caret = view.caretRect(for: range.end)
            guard !caret.isNull, !caret.isInfinite else { return }
            view.scrollRectToVisible(caret, animated: !UIAccessibility.isReduceMotionEnabled)
        }

        /// Keeps the caret above the keyboard and its formatting bar after a picture is inserted. The picture's final
        /// size and the returning keyboard both arrive after the insertion, and either pushes the caret out of view,
        /// so the caret is checked again as they do, for a moment, unless the person scrolls or types.
        func revealCaretAfterImage() {
            revealCaret(for: 2)
        }

        /// After a rotation or a window resize, the line being typed is brought back above the writing controls once
        /// the entry and the keyboard have their new size.
        func revealCaretAfterResize() {
            guard let view, view.bounds.size != laidOutSize else { return }
            let resized = laidOutSize != .zero
            laidOutSize = view.bounds.size
            if resized, view.isFirstResponder { revealCaret(for: 0.6) }
        }

        private func revealCaret(for duration: TimeInterval) {
            let deadline = Date().addingTimeInterval(duration)
            if caretRevealDeadline.map({ $0 < deadline }) ?? true { caretRevealDeadline = deadline }
            DispatchQueue.main.async { [weak self] in self?.keepCaretRevealed() }
            for delay in [0.25, 0.5] where delay < duration {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.keepCaretRevealed() }
            }
        }

        /// Typing takes over from a pending reveal: the text view follows the caret itself from then on.
        func endCaretReveal() {
            caretRevealDeadline = nil
        }

        /// While a reveal is pending, scrolls only as far as the caret needs, and only when it's out of view.
        func keepCaretRevealed() {
            guard let deadline = caretRevealDeadline, let view else { return }
            guard Date() < deadline, !view.isTracking, !view.isDecelerating else {
                caretRevealDeadline = nil
                return
            }
            guard view.isFirstResponder, let range = view.selectedTextRange else { return }
            updateWritingInset()
            let caret = view.caretRect(for: range.end)
            guard !caret.isNull, !caret.isInfinite else { return }
            view.scrollRectToVisible(caret, animated: false)
        }
    }
#endif
