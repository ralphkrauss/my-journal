#if os(macOS)
    import AppKit
    import JournalCore
    import SwiftUI
    import UniformTypeIdentifiers

    /// The selected picture as Copy, Cut and dragging hand it to other apps.
    enum SelectedPicture {
        /// No single shown picture is selected: the text view copies as it does for text.
        case none
        /// Its original is still being read.
        case pending
        /// Its original, under its own type first.
        case ready([(type: NSPasteboard.PasteboardType, data: Data)])
    }

    /// A picture's stored original and what other apps paste.
    struct PictureOriginal: Sendable {
        let data: Data
        let type: UTType
        let representations: [(type: NSPasteboard.PasteboardType, data: Data)]

        /// Reads the original from the store; the JPEG copy of a HEIC image is made away from the main thread.
        @MainActor static func read(_ item: ImageItem, from store: @MainActor (UUID) async -> Data?) async
            -> PictureOriginal?
        {
            guard let id = item.attachmentID, let data = await store(id) else { return nil }
            let type = item.type(of: data)
            let byType = await Task.detached(priority: .userInitiated) {
                ImageItem.pasteboardRepresentations(of: data, type: type)
            }.value
            // The original's own type first, so apps that take the first image type they read get the original.
            let order = [type.identifier] + byType.keys.filter { $0 != type.identifier }.sorted()
            let representations = order.compactMap { identifier in
                byType[identifier].map { (type: NSPasteboard.PasteboardType(identifier), data: $0) }
            }
            return PictureOriginal(data: data, type: type, representations: representations)
        }
    }

    /// Reading the selected picture's original, started when it was selected.
    struct PictureRead {
        let item: ImageItem
        let task: Task<PictureOriginal?, Never>
        var original: PictureOriginal?
    }

    /// Keeps a picture's menu to its own items: the system adds AutoFill and Services to every menu a text view
    /// shows, and neither is about a picture. One picture menu is open at a time, so one set of items is kept.
    @MainActor final class PictureMenuItems: NSObject, NSMenuDelegate {
        private var own: Set<ObjectIdentifier> = []

        func keep(_ menu: NSMenu) {
            own = Set(menu.items.map(ObjectIdentifier.init))
            menu.allowsContextMenuPlugIns = false
            menu.delegate = self
        }

        func menuWillOpen(_ menu: NSMenu) {
            for item in menu.items where !own.contains(ObjectIdentifier(item)) {
                menu.removeItem(item)
            }
            while let last = menu.items.last, last.isSeparatorItem {
                menu.removeItem(last)
            }
        }
    }

    /// A picture's own cell, through which VoiceOver gets the picture's actions and its menu.
    final class JournalImageCell: NSTextAttachmentCell {
        weak var host: NativeEditor.Coordinator?
        /// A selected picture is tinted and outlined with the selection colour: the text view draws the selection
        /// behind the text, where the picture would hide it. The outline also takes in the strip of its line below the
        /// picture, where that selection still shows, so the two read as one.
        override func draw(
            withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
            layoutManager: NSLayoutManager
        ) {
            super.draw(withFrame: cellFrame, in: controlView, characterIndex: charIndex, layoutManager: layoutManager)
            guard let view = controlView as? NSTextView,
                view.selectedRanges.contains(where: { NSLocationInRange(charIndex, $0.rangeValue) })
            else { return }
            let focused = view.window?.isKeyWindow == true && view.window?.firstResponder === view
            let color =
                focused ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor
            let shape = highlightRect(cellFrame, characterIndex: charIndex, layoutManager: layoutManager, in: view)
            color.withAlphaComponent(0.18).setFill()
            shape.fill(using: .sourceOver)
            color.setStroke()
            let outline = NSBezierPath(rect: shape.insetBy(dx: 1.5, dy: 1.5))
            outline.lineWidth = 3
            outline.stroke()
        }

        /// The picture's frame together with the selection the text view draws for its character.
        private func highlightRect(
            _ cellFrame: NSRect, characterIndex: Int, layoutManager: NSLayoutManager, in view: NSTextView
        ) -> NSRect {
            guard let container = view.textContainer else { return cellFrame }
            let glyphs = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: characterIndex, length: 1), actualCharacterRange: nil)
            var shape = cellFrame
            let origin = view.textContainerOrigin
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: container
            ) { rect, _ in
                let selected = rect.offsetBy(dx: origin.x, dy: origin.y)
                shape = shape.union(
                    NSRect(x: cellFrame.minX, y: selected.minY, width: cellFrame.width, height: selected.height))
            }
            return shape
        }
        override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
            host?.accessibilityActions(for: self)
        }
        override func accessibilityPerformShowMenu() -> Bool {
            host?.showPictureMenu(for: self) ?? false
        }
    }

    /// Right-click on a picture, its VoiceOver actions, and copying a selected picture on the Mac
    /// (docs/design/image-actions-mac-2026-10-03.md).
    extension NativeEditor.Coordinator {
        enum ImageAction: CaseIterable {
            case copy, share, save, describe, delete

            /// VoiceOver's name for the action: the menu's, without an ellipsis.
            var spoken: String {
                switch self {
                case .copy: return "Copy"
                case .share: return "Share"
                case .save: return "Save Image As"
                case .describe: return "Image Descriptions"
                case .delete: return "Delete"
                }
            }
        }

        func configurePictures(_ view: JournalTextView) {
            view.selectedPicture = { [weak self] in self?.selectedPictureState() ?? .none }
            view.awaitSelectedPicture = { [weak self] failure, then in self?.awaitSelectedPicture(failure, then: then) }
            view.pictureMenu = { [weak self] event in self?.pictureMenu(for: event) }
            view.showPictureMenu = { [weak self] in self?.showSelectedPictureMenu() ?? false }
            view.leavingWindow = { [weak self] in self?.dismissPicturePresentations() }
        }

        /// What can be done with `item` now: the original's actions only while the picture is shown, the entry's only
        /// while it can be edited.
        func imageActions(for item: ImageItem) -> [ImageAction] {
            guard let support = parent.imageActions else { return [] }
            var result: [ImageAction] = []
            if isShown(item) { result += [.copy, .share, .save] }
            if parent.editable {
                if support.describe != nil { result.append(.describe) }
                result.append(.delete)
            }
            return result
        }

        private func isShown(_ item: ImageItem) -> Bool {
            item.attachmentID.map { parent.images[$0] != nil } ?? false
        }

        /// The single shown picture selected, if any.
        private var selectedPictureItem: ImageItem? {
            guard parent.imageActions != nil, let view, let storage = view.textStorage,
                let item = ImageItem.selected(view.selectedRange(), in: storage), isShown(item)
            else { return nil }
            return item
        }

        // MARK: Reading the original

        /// Starts reading the selected picture's original, so Copy, Cut and dragging have it at hand.
        func prepareSelectedPicture() {
            guard let item = selectedPictureItem else {
                forgetPictureRead()
                return
            }
            if pictureRead?.item != item { startPictureRead(item) }
        }

        @discardableResult private func startPictureRead(_ item: ImageItem) -> Task<PictureOriginal?, Never>? {
            forgetPictureRead()
            guard let store = parent.imageActions?.original else { return nil }
            let task = Task { await PictureOriginal.read(item, from: store) }
            pictureRead = PictureRead(item: item, task: task)
            Task { [weak self] in
                let original = await task.value
                self?.finishPictureRead(item, original)
            }
            return task
        }

        private func finishPictureRead(_ item: ImageItem, _ original: PictureOriginal?) {
            guard pictureRead?.item == item else { return }
            if let original {
                pictureRead?.original = original
            } else {
                // A failed read is tried again the next time it's needed.
                pictureRead = nil
            }
        }

        func forgetPictureRead() {
            pictureRead?.task.cancel()
            pictureRead = nil
        }

        func selectedPictureState() -> SelectedPicture {
            guard let item = selectedPictureItem else { return .none }
            if let read = pictureRead, read.item == item, let original = read.original {
                return .ready(original.representations)
            }
            return .pending
        }

        /// Waits for the selected picture's original without blocking, then continues; says so if it can't be read.
        func awaitSelectedPicture(_ failure: String, then: @escaping @MainActor () -> Void) {
            guard let item = selectedPictureItem else { return }
            let task = pictureRead.flatMap { $0.item == item ? $0.task : nil } ?? startPictureRead(item)
            guard let task else { return }
            Task { [weak self] in
                let original = await task.value
                guard let self, self.view?.window != nil else { return }
                self.finishPictureRead(item, original)
                guard original != nil else {
                    self.parent.imageActions?.report(failure)
                    return
                }
                then()
            }
        }

        /// The original of `item`, read for it unless it's the selected picture's; nil once the entry has left the
        /// window, as when the app locks.
        func original(of item: ImageItem) async -> PictureOriginal? {
            guard view?.window != nil else { return nil }
            let task: Task<PictureOriginal?, Never>
            if let read = pictureRead, read.item == item {
                task = read.task
            } else if let store = parent.imageActions?.original {
                task = Task { await PictureOriginal.read(item, from: store) }
            } else {
                return nil
            }
            let original = await task.value
            return view?.window != nil ? original : nil
        }

        // MARK: The menu

        /// The picture's menu when the event is a click on the selected picture, or a menu asked for from the
        /// keyboard while one picture is selected; nil for the standard text menu.
        func pictureMenu(for event: NSEvent?) -> NSMenu? {
            guard let view, parent.imageActions != nil, let storage = view.textStorage,
                let item = ImageItem.selected(view.selectedRange(), in: storage)
            else { return nil }
            if let event, [.rightMouseDown, .leftMouseDown, .otherMouseDown].contains(event.type) {
                let point = view.convert(event.locationInWindow, from: nil)
                guard let rect = imageRect(item), rect.contains(point) else { return nil }
            }
            return pictureMenu(for: item)
        }

        func pictureMenu(for item: ImageItem) -> NSMenu {
            let menu = NSMenu(title: "Image")
            let actions = imageActions(for: item)
            var commands: [MenuAction] = []
            if actions.contains(.save) {
                commands.append(
                    .command("Save Image As…", symbol: "square.and.arrow.down") { [weak self] in
                        self?.perform(.save, on: item)
                    })
            }
            if actions.contains(.describe) {
                commands += [
                    .separator("describe"),
                    .command("Image Descriptions…", symbol: "text.below.photo") { [weak self] in
                        self?.perform(.describe, on: item)
                    },
                ]
            }
            if actions.contains(.delete) {
                commands += [
                    .separator("delete"),
                    .command("Delete", symbol: "trash", destructive: true) { [weak self] in
                        self?.perform(.delete, on: item)
                    },
                ]
            }
            pictureMenuTarget.fill(menu, with: commands)
            if actions.contains(.share) {
                menu.insertItem(shareMenuItem(for: item), at: 0)
            }
            let edits = editMenuItems()
            if menu.numberOfItems > 0, menu.item(at: 0)?.isSeparatorItem == false {
                menu.insertItem(.separator(), at: 0)
            }
            for (offset, edit) in edits.enumerated() { menu.insertItem(edit, at: offset) }
            pictureMenuItems.keep(menu)
            pictureMenuShown = menu
            return menu
        }

        /// Cut, Copy and Paste, acting on the selected picture; only Copy in an entry that can't be edited.
        private func editMenuItems() -> [NSMenuItem] {
            let all: [(String, Selector, String, String)] = [
                ("Cut", #selector(NSText.cut(_:)), "x", "scissors"),
                ("Copy", #selector(NSText.copy(_:)), "c", "doc.on.doc"),
                ("Paste", #selector(NSText.paste(_:)), "v", "doc.on.clipboard"),
            ]
            return all.filter { parent.editable || $0.0 == "Copy" }.map { title, action, key, symbol in
                let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
                item.target = view
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                return item
            }
        }

        /// The system's standard Share item, handing services the original in memory, named “Image”.
        private func shareMenuItem(for item: ImageItem) -> NSMenuItem {
            let picker = NSSharingServicePicker(items: [shareProvider(for: item)])
            sharePicker = picker
            return picker.standardShareMenuItem
        }

        func shareProvider(for item: ImageItem) -> NSItemProvider {
            let shown = item.attachmentID.flatMap { parent.images[$0] }
            let type = pictureRead?.original?.type ?? item.recordedType ?? shown.map { item.type(of: $0) } ?? .image
            let provider = NSItemProvider()
            provider.suggestedName = ImageItem.fileName(for: type)
            provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) {
                [weak self] completion in
                Task { @MainActor in
                    guard let self, let original = await self.original(of: item) else {
                        // After a lock the request fails quietly.
                        if let self, self.view?.window != nil {
                            self.parent.imageActions?.report("The image couldn’t be shared.")
                        }
                        completion(nil, CocoaError(.fileReadUnknown))
                        return
                    }
                    completion(original.data, nil)
                }
                return nil
            }
            return provider
        }

        /// Shows the selected picture's menu at the picture, for VoiceOver's Show Menu on the text.
        func showSelectedPictureMenu() -> Bool {
            guard let view, let storage = view.textStorage,
                let item = ImageItem.selected(view.selectedRange(), in: storage)
            else { return false }
            return popUpPictureMenu(for: item)
        }

        @discardableResult private func popUpPictureMenu(for item: ImageItem) -> Bool {
            guard let view, parent.imageActions != nil, let rect = imageRect(item) else { return false }
            view.setSelectedRange(NSRange(location: item.index, length: 1))
            pictureMenu(for: item).popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY), in: view)
            return true
        }

        // MARK: The actions

        /// Carries out an action on the picture the menu or VoiceOver offered it for, if it is still there.
        func perform(_ action: ImageAction, on item: ImageItem) {
            guard let view, let storage = view.textStorage, ImageItem.at(item.index, in: storage) == item else {
                return
            }
            switch action {
            case .copy: copyPicture(item)
            case .share: sharePicture(item)
            case .save: savePicture(item)
            case .describe: parent.imageActions?.describe?()
            case .delete: deleteImage(item)
            }
        }

        /// Copies a picture VoiceOver is on, without selecting it, as Copy does for a selected picture.
        private func copyPicture(_ item: ImageItem) {
            Task { [weak self] in
                guard let self, let view = self.view else { return }
                guard let original = await self.original(of: item) else {
                    if view.window != nil { self.parent.imageActions?.report("The image couldn’t be copied.") }
                    return
                }
                let board = view.pasteboard
                let markdown = view.selectionMarkdown?(NSRange(location: item.index, length: 1))
                board.declareTypes(original.representations.map(\.type) + [.journalMarkdown], owner: nil)
                for representation in original.representations {
                    board.setData(representation.data, forType: representation.type)
                }
                if let markdown { board.setString(markdown, forType: .journalMarkdown) }
                JournalAccessibility.announce("Copied")
            }
        }

        /// The share picker next to the picture, for VoiceOver's Share action.
        private func sharePicture(_ item: ImageItem) {
            guard let view, let rect = imageRect(item) else { return }
            let picker = NSSharingServicePicker(items: [shareProvider(for: item)])
            sharePicker = picker
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        }

        private func savePicture(_ item: ImageItem) {
            guard let window = view?.window else { return }
            let shown = item.attachmentID.flatMap { parent.images[$0] }
            let type = pictureRead?.original?.type ?? item.recordedType ?? shown.map { item.type(of: $0) } ?? .image
            let panel = NSSavePanel()
            panel.nameFieldStringValue = ImageItem.fileName(for: type)
            panel.allowedContentTypes = [type]
            savePanel = panel
            panel.beginSheetModal(for: window) { [weak self, weak panel] response in
                guard response == .OK, let url = panel?.url else { return }
                self?.write(item, to: url)
            }
        }

        private func write(_ item: ImageItem, to url: URL) {
            Task { [weak self] in
                guard let self else { return }
                let original = await self.original(of: item)
                guard self.view?.window != nil else { return }
                guard let data = original?.data else {
                    self.parent.imageActions?.report("The image couldn’t be saved.")
                    return
                }
                let written = await Task.detached(priority: .userInitiated) {
                    (try? data.write(to: url)) != nil
                }.value
                if !written { self.parent.imageActions?.report("The image couldn’t be saved.") }
            }
        }

        /// Removes the picture: on its own line with that line, inside a line alone. One undo step.
        func deleteImage(_ item: ImageItem) {
            guard parent.editable, let view, let storage = view.textStorage,
                ImageItem.at(item.index, in: storage) == item
            else { return }
            let range = item.deletionRange(in: storage.string as NSString)
            // The editor takes focus, as a click on the picture would, so ⌘Z reaches the step at once.
            view.window?.makeFirstResponder(view)
            replace(NSAttributedString(), range: range, actionName: "Delete Image")
            // Focus moves to the text first, so the announcement isn't cut off by the change.
            NSAccessibility.post(element: view, notification: .focusedUIElementChanged)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { JournalAccessibility.announce("Image deleted") }
        }

        /// The picture's menu, share picker and save panel close when the entry leaves the window, as when the app
        /// locks, and the read original is forgotten.
        func dismissPicturePresentations() {
            pictureMenuShown?.cancelTrackingWithoutAnimation()
            pictureMenuShown = nil
            sharePicker?.close()
            sharePicker = nil
            if let savePanel, let parent = savePanel.sheetParent { parent.endSheet(savePanel, returnCode: .cancel) }
            savePanel = nil
            forgetPictureRead()
        }

        /// The picture's rectangle in the text view.
        func imageRect(_ item: ImageItem) -> NSRect? {
            guard let view, let layout = view.layoutManager, let container = view.textContainer,
                let storage = view.textStorage, item.index < storage.length
            else { return nil }
            let glyphs = layout.glyphRange(
                forCharacterRange: NSRange(location: item.index, length: 1), actualCharacterRange: nil)
            guard glyphs.length > 0 else { return nil }
            let origin = view.textContainerOrigin
            return layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
        }

        // MARK: VoiceOver

        /// Lets each picture's cell offer its actions to VoiceOver.
        func synchronizePictureCells() {
            guard let storage = view?.textStorage else { return }
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if let cell = (value as? NSTextAttachment)?.attachmentCell as? JournalImageCell, cell.host !== self {
                    cell.host = self
                }
            }
        }

        /// The picture a cell draws, where it is in the text now.
        private func item(for cell: NSTextAttachmentCell) -> ImageItem? {
            guard let storage = view?.textStorage else { return nil }
            var found: ImageItem?
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) {
                value, range, stop in
                guard (value as? NSTextAttachment)?.attachmentCell === cell else { return }
                found = ImageItem.at(range.location, in: storage)
                stop.pointee = true
            }
            return found
        }

        func accessibilityActions(for cell: NSTextAttachmentCell) -> [NSAccessibilityCustomAction] {
            guard let item = item(for: cell) else { return [] }
            return imageActions(for: item).map { kind in
                NSAccessibilityCustomAction(name: kind.spoken) { [weak self] in
                    guard let self else { return false }
                    self.perform(kind, on: item)
                    return true
                }
            }
        }

        func showPictureMenu(for cell: NSTextAttachmentCell) -> Bool {
            guard let item = item(for: cell) else { return false }
            return popUpPictureMenu(for: item)
        }
    }
#endif
