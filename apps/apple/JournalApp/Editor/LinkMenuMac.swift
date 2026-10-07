#if os(macOS)
    import AppKit

    /// Right-click on a link: Edit Link… selects it and opens the sheet as ⌘K does, so the sheet's range and the
    /// selection agree; Remove Link takes it off at once and leaves the selection where it was
    /// (docs/design/build-18-fixes-2026-10-06.md §2.4).
    extension NativeEditor.Coordinator {
        func linkMenuItems(for event: NSEvent) -> [NSMenuItem] {
            guard parent.editable, !editingSource, tables?.active == nil, let view, let storage = view.textStorage,
                let index = characterIndex(under: event, in: view),
                let link = LinkEditing.link(in: storage, selection: NSRange(location: index, length: 1))
            else { return [] }
            let actions: [MenuAction] = [
                .command("Edit Link…", symbol: "link") { [weak self] in
                    guard let self, let view = self.view else { return }
                    view.window?.makeFirstResponder(view)
                    view.setSelectedRange(link.range)
                    self.parent.actions.openLinkFromKeyboard()
                },
                .command("Remove Link", symbol: "link.badge.minus") { [weak self] in
                    self?.perform(.removeLink(link.range))
                },
            ]
            let scratch = NSMenu()
            linkMenuTarget.fill(scratch, with: actions)
            let items = scratch.items
            scratch.removeAllItems()
            return items
        }

        /// The character under the pointer, only where the pointer is on the character itself: the empty space after a
        /// line's last character belongs to no link.
        private func characterIndex(under event: NSEvent, in view: JournalTextView) -> Int? {
            guard let layout = view.layoutManager, let container = view.textContainer, view.textStorage?.length ?? 0 > 0
            else { return nil }
            let origin = view.textContainerOrigin
            let converted = view.convert(event.locationInWindow, from: nil)
            let point = NSPoint(x: converted.x - origin.x, y: converted.y - origin.y)
            let glyph = layout.glyphIndex(for: point, in: container)
            let bounds = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            guard bounds.contains(point) else { return nil }
            return layout.characterIndexForGlyph(at: glyph)
        }
    }
#endif
