#if os(macOS)
    import AppKit

    /// The entry's scroll view on the Mac. Its bottom content inset is room below the line being typed: AppKit counts
    /// the inset as outside the visible area, so the text view, which follows the caret itself, keeps the line above
    /// it, and the end of a long entry can scroll up into it (docs/design/mac-typing-room-2026-10-04.md).
    final class EntryScrollView: NSScrollView {
        /// Lines of body text kept below the line being typed.
        static let typingRoomLines: CGFloat = 2

        /// The entry's text size, which the room follows (View ▸ Zoom In and Zoom Out).
        var textSize: CGFloat = 16 {
            didSet { if textSize != oldValue { updateTypingRoom() } }
        }

        /// The room for `textSize`, never more than a quarter of an editor `height` tall.
        static func typingRoom(textSize: CGFloat, height: CGFloat, layout: NSLayoutManager?) -> CGFloat {
            let font = RichText.font(size: textSize)
            let line = layout?.defaultLineHeight(for: font) ?? ceil(font.ascender - font.descender + font.leading)
            return max(0, min(ceil(typingRoomLines * line), floor(height / 4)))
        }

        /// Laid out again when the editor's size changes, as when the window is resized or a notice appears above it.
        override func tile() {
            super.tile()
            placeFindBar()
            updateTypingRoom()
        }

        /// The find bar's height can change while it shows (Replace).
        override func findBarViewDidChangeHeight() {
            super.findBarViewDidChangeHeight()
            tile()
        }

        /// The find bar (Edit ▸ Find) takes its own room above the text instead of covering the entry's first lines:
        /// AppKit lays it over the text and relies on automatic insets, which this scroll view doesn't use.
        private func placeFindBar() {
            guard isFindBarVisible, let bar = findBarView, bar.superview === self else { return }
            var clip = contentView.frame
            if isFlipped {
                let top = max(clip.minY, bar.frame.maxY)
                clip.size.height = max(0, clip.maxY - top)
                clip.origin.y = top
            } else {
                clip.size.height = max(0, min(clip.maxY, bar.frame.minY) - clip.minY)
            }
            if clip != contentView.frame { contentView.frame = clip }
        }

        private func updateTypingRoom() {
            let room = Self.typingRoom(
                textSize: textSize, height: frame.height, layout: (documentView as? NSTextView)?.layoutManager)
            guard abs(contentInsets.bottom - room) > 0.5 else { return }
            let shrinking = room < contentInsets.bottom
            // The title is above the scroll view, so there is no inset of AppKit's own to keep.
            automaticallyAdjustsContentInsets = false
            contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: room, right: 0)
            // Nothing covers the room, so the scroll bar keeps the editor's whole height.
            scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: -room, right: 0)
            guard shrinking else { return }
            // Less room leaves no empty space below the end of the entry.
            let constrained = contentView.constrainBoundsRect(contentView.bounds)
            guard constrained.origin != contentView.bounds.origin else { return }
            contentView.scroll(to: constrained.origin)
            reflectScrolledClipView(contentView)
        }
    }

    extension NativeEditor.Coordinator {
        /// Shows the caret, with the room below it, after the editor changed the text itself in answer to a key:
        /// Return in a list, checklist, quote or heading, a Markdown shortcut, Delete at the start of an item, undo
        /// and redo. The text view follows only its own typing.
        func revealCaretAfterKey() {
            guard let view else { return }
            view.scrollRangeToVisible(view.selectedRange())
        }

        /// After a picture is pasted, dropped or inserted: the caret now, and again once the picture is laid out at
        /// its size, unless the person has moved the caret or scrolled in between.
        func revealCaretAfterPicture() {
            revealCaretAfterKey()
            guard let view, let clip = view.enclosingScrollView?.contentView else { return }
            let selection = view.selectedRange()
            let position = clip.bounds.origin
            DispatchQueue.main.async { [weak self, weak view, weak clip] in
                guard let view, let clip, view.selectedRange() == selection, clip.bounds.origin == position else {
                    return
                }
                self?.revealCaretAfterKey()
            }
        }
    }
#endif
