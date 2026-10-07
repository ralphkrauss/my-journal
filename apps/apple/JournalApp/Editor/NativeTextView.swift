import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
    import AppKit
    final class JournalTextView: NSTextView {
        /// The text view keeps its own text system, laid out with TextKit 1 by the list layout manager from the start
        /// (ListLayout.swift).
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            textContainer?.replaceLayoutManager(ListLayoutManager())
        }
        override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
            super.init(frame: frameRect, textContainer: container)
        }
        required init?(coder: NSCoder) { nil }
        /// An input method is starting or continuing a composition: what it replaces is left to the text system.
        private(set) var settingMarkedText = false
        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            settingMarkedText = true
            defer { settingMarkedText = false }
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        }
        /// Controls shown over empty space in the text, such as “Use a Template…”, which VoiceOver reaches from here.
        var accessoryViews: [NSView] = []
        override func accessibilityChildren() -> [Any]? {
            let accessories = accessoryViews.filter { !$0.isHidden }
            guard !accessories.isEmpty else { return super.accessibilityChildren() }
            return accessories + (super.accessibilityChildren() ?? [])
        }
        /// Closes the Formatting popover when it's shown; false when there's none.
        var cancelFormatting: (() -> Bool)?
        /// Escape closes the Formatting popover while the text keeps focus, unless an input method is composing.
        override func cancelOperation(_ sender: Any?) {
            if !hasMarkedText(), cancelFormatting?() == true { return }
            super.cancelOperation(sender)
        }
        override func layout() {
            super.layout()
            layoutChanged?()
        }
        override func drawBackground(in rect: NSRect) {
            super.drawBackground(in: rect)
            guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return }
            let shapes = BlockDecorations.shapes(
                storage: storage, layout: layout, container: container, origin: textContainerOrigin, visible: rect,
                blockWidth: max(40, bounds.width - 20))
            BlockDecorations.draw(shapes, scale: window?.backingScaleFactor ?? 2)
        }
        var receiveMarkdown: ((String) -> Void)?
        /// Text pasted or dropped from another app.
        var receiveFragment: ((PastedFragment) -> Void)?
        var receiveImages: (([PastedImages.Source]) -> Void)?
        /// The entry's Markdown for a selection, so copying, cutting and dragging within the journal keep images,
        /// tables and lists.
        var selectionMarkdown: ((NSRange) -> String?)?
        var compositionEnded: (() -> Void)?
        var layoutChanged: (() -> Void)?
        override func unmarkText() {
            super.unmarkText()
            compositionEnded?()
        }
        /// Where Copy and Cut put a selected picture: the general pasteboard, or a private one in tests.
        var pasteboard = NSPasteboard.general
        /// The selected picture as other apps paste it, when exactly one shown picture is selected
        /// (ImageActionsMac.swift).
        var selectedPicture: (() -> SelectedPicture)?
        /// Reads the selected picture's original, then continues; on failure it says so and doesn't continue.
        var awaitSelectedPicture: ((_ failure: String, _ then: @escaping @MainActor () -> Void) -> Void)?
        /// The selected picture's menu, for a right-click on it or a menu asked for from the keyboard.
        var pictureMenu: ((NSEvent?) -> NSMenu?)?
        /// Shows the selected picture's menu at the picture; false when no picture is selected.
        var showPictureMenu: (() -> Bool)?
        /// The view leaves the window, as when the app locks.
        var leavingWindow: (() -> Void)?
        /// Keyboard focus came to or left the view, which the Format menu follows.
        var focusChanged: ((Bool) -> Void)?
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { focusChanged?(true) }
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { focusChanged?(false) }
            return resigned
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                leavingWindow?()
                focusChanged?(false)
            }
            super.viewWillMove(toWindow: newWindow)
        }
        /// Edit Link… and Remove Link for the link under the pointer, placed with the system's own link items.
        var linkItems: ((NSEvent) -> [NSMenuItem])?
        /// The system's own items for editing a link in a text view (Edit Link… and Remove Link). They don't know
        /// the entry's link titles or Markdown, so they give way to the app's two items, which do the same.
        private static let systemLinkEditing: Set<Selector> = [
            #selector(NSTextView.orderFrontLinkPanel(_:)), Selector(("_removeLinkFromMenu:")),
        ]
        override func menu(for event: NSEvent) -> NSMenu? {
            // The text view's own handling selects a picture that was clicked, so it goes first.
            let standard = super.menu(for: event)
            if let picture = pictureMenu?(event) { return picture }
            guard let standard, let items = linkItems?(event), !items.isEmpty else { return standard }
            for item in standard.items.reversed() where item.action.map(Self.systemLinkEditing.contains) == true {
                standard.removeItem(item)
            }
            let existing = standard.items.lastIndex { $0.title.localizedCaseInsensitiveContains("Link") }
            var position = existing.map { $0 + 1 } ?? 0
            for item in items {
                standard.insertItem(item, at: position)
                position += 1
            }
            if existing == nil { standard.insertItem(.separator(), at: position) }
            return standard
        }
        override func accessibilityPerformShowMenu() -> Bool {
            showPictureMenu?() == true || super.accessibilityPerformShowMenu()
        }
        override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
            // A selected picture goes to other apps as the image itself, with the entry's own Markdown for pasting
            // into an entry, and no text, which other apps would take instead.
            if case .ready(let representations) = selectedPicture?() ?? .none {
                return representations.map(\.type) + [.journalMarkdown]
            }
            return [.journalMarkdown] + super.writablePasteboardTypes
        }
        override func copy(_ sender: Any?) {
            switch selectedPicture?() ?? .none {
            case .none: super.copy(sender)
            case .ready: copyPicture()
            case .pending:
                awaitSelectedPicture?("The image couldn’t be copied.") { [weak self] in self?.copyPicture() }
            }
        }
        override func cut(_ sender: Any?) {
            switch selectedPicture?() ?? .none {
            case .none: super.cut(sender)
            case .ready: cutPicture()
            case .pending:
                awaitSelectedPicture?("The image couldn’t be copied.") { [weak self] in self?.cutPicture() }
            }
        }
        @discardableResult private func copyPicture() -> Bool {
            guard case .ready = selectedPicture?() ?? .none else { return false }
            return writeSelection(to: pasteboard, types: writablePasteboardTypes)
        }
        private func cutPicture() {
            guard isEditable, copyPicture() else { return }
            delete(nil)
            undoManager?.setActionName("Cut")
        }
        /// Another app gets a copy of what is dragged to it; only a drop within the journal moves it.
        override func draggingSession(
            _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            let operations = super.draggingSession(session, sourceOperationMaskFor: context)
            return context == .outsideApplication ? operations.intersection([.copy, .generic]) : operations
        }
        override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
            [.journalMarkdown] + super.readablePasteboardTypes + PastedImages.readableImageTypes + [.fileURL]
        }
        /// Drops read the first of these types the drag offers.
        override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
            let own: [NSPasteboard.PasteboardType] = [.journalMarkdown, .fileURL] + PastedImages.readableImageTypes
            return own + super.acceptableDragTypes.filter { !own.contains($0) }
        }
        override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
            let ranges = selectedRanges.map(\.rangeValue)
            guard ranges.count == 1, let range = ranges.first, range.length > 0 else {
                return type != .journalMarkdown && super.writeSelection(to: pboard, type: type)
            }
            if type == .journalMarkdown {
                guard let markdown = selectionMarkdown?(range) else { return false }
                return pboard.setString(markdown, forType: type)
            }
            if case .ready(let representations) = selectedPicture?() ?? .none,
                let representation = representations.first(where: { $0.type == type })
            {
                return pboard.setData(representation.data, forType: type)
            }
            // Other apps take lists with their markers (ListEditing.swift).
            let shared = RichText.otherAppsText(attributedString(), range: range)
            // Text views still name plain text by its original pasteboard type.
            if type == .string || type == NSPasteboard.PasteboardType("NSStringPboardType") {
                // A table's Markdown is the most useful plain text for it; pictures have no text at all.
                let plain =
                    RichText.tableSelectionMarkdown(attributedString(), range: range)
                    ?? shared.string.replacingOccurrences(of: "\u{FFFC}", with: "")
                return pboard.setString(plain, forType: .string)
            }
            let whole = NSRange(location: 0, length: shared.length)
            if type == .rtf, let data = shared.rtf(from: whole) {
                return pboard.setData(data, forType: .rtf)
            }
            if type == .rtfd, let data = shared.rtfd(from: whole) {
                return pboard.setData(data, forType: .rtfd)
            }
            return super.writeSelection(to: pboard, type: type)
        }
        override func paste(_ sender: Any?) {
            if !pasteJournalContent(from: NSPasteboard.general) { super.paste(sender) }
        }
        /// Pastes the journal's own content or pictures; false when the pasteboard holds text, which the text view
        /// reads itself.
        func pasteJournalContent(from board: NSPasteboard) -> Bool {
            if let markdown = board.string(forType: .journalMarkdown) {
                receiveMarkdown?(markdown)
                return true
            }
            let images = PastedImages.images(on: board)
            if !images.isEmpty {
                receiveImages?(images)
                return true
            }
            return false
        }
        /// Drops, and pastes of a type the text view reads itself, arrive here.
        override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
            if type == .journalMarkdown, let markdown = pboard.string(forType: type) {
                receiveMarkdown?(markdown)
                return true
            }
            // Text from another app becomes the entry's own blocks, with its lists, headings, quotes and code. The
            // text view never reads it itself, which could load what a web page refers to.
            if PastedRichText.readsText(of: type) {
                if let fragment = PastedRichText.fragment(on: pboard, type: type) { receiveFragment?(fragment) }
                return true
            }
            if type == .fileURL || PastedImages.readableImageTypes.contains(type) {
                let images = PastedImages.images(on: pboard)
                if !images.isEmpty {
                    receiveImages?(images)
                    return true
                }
                if type != .fileURL { return false }
            }
            return super.readSelection(from: pboard, type: type)
        }
        /// Dropped text goes before the last list item's own line break, never after it.
        override func characterIndexForInsertion(at point: NSPoint) -> Int {
            let index = super.characterIndexForInsertion(at: point)
            guard let storage = textStorage, ListMarkers.hasOwnEnd(storage) else { return index }
            return min(index, storage.length - 1)
        }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let board = sender.draggingPasteboard
            let images = board.availableType(from: [.journalMarkdown]) == nil ? PastedImages.images(on: board) : []
            guard !images.isEmpty, isEditable else { return super.performDragOperation(sender) }
            // Every dropped picture goes where it was dropped, in order.
            let point = convert(sender.draggingLocation, from: nil)
            setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
            receiveImages?(images)
            return true
        }
    }
#else
    import UIKit
    final class JournalTextView: UITextView, FormattingPanelClosing {
        /// Controls over empty text, such as the placeholder's “use a template”: a tap there is theirs, so the text
        /// view neither raises the keyboard nor moves the caret first.
        var gestureExclusions: [UIView] = []
        /// An input method is starting or continuing a composition: what it replaces is left to the text system.
        private(set) var settingMarkedText = false
        override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
            settingMarkedText = true
            defer { settingMarkedText = false }
            super.setMarkedText(markedText, selectedRange: selectedRange)
        }
        override func setAttributedMarkedText(_ markedText: NSAttributedString?, selectedRange: NSRange) {
            settingMarkedText = true
            defer { settingMarkedText = false }
            super.setAttributedMarkedText(markedText, selectedRange: selectedRange)
        }
        /// The TextKit 1 text system the view is made with (ListLayoutManager.makeTextSystem); the view doesn't keep
        /// its storage itself.
        private var ownedStorage: NSTextStorage?
        /// Made with TextKit 1 and the list layout manager unless given a container of its own.
        override init(frame: CGRect, textContainer: NSTextContainer?) {
            if let textContainer {
                super.init(frame: frame, textContainer: textContainer)
            } else {
                let (storage, container) = ListLayoutManager.makeTextSystem(width: frame.width)
                ownedStorage = storage
                super.init(frame: frame, textContainer: container)
            }
            addGestureRecognizer(tapBelowText)
        }
        required init?(coder: NSCoder) { nil }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let point = gestureRecognizer.location(in: self)
            if gestureExclusions.contains(where: { !$0.isHidden && $0.frame.contains(point) }) { return false }
            if gestureRecognizer === tapBelowText { return continuesAtEnd(after: point) }
            // UIKit would take a tap below the text as a tap on the last word.
            if gestureRecognizer is UITapGestureRecognizer, continuesAtEnd(after: point) { return false }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        /// A tap in the empty space below the text continues the entry at its end, as in Notes. UIKit takes it as a
        /// tap on the last word, which selects that word when it's misspelled, so the next letter typed replaced it.
        private lazy var tapBelowText = UITapGestureRecognizer(target: self, action: #selector(continueAtEnd(_:)))
        /// Whether a tap at `point` is below the text and should put the caret at the end.
        private func continuesAtEnd(after point: CGPoint) -> Bool {
            guard isEditable, markedTextRange == nil else { return false }
            let textBottom = layoutManager.usedRect(for: textContainer).maxY + textContainerInset.top
            return point.y > textBottom
        }
        @objc private func continueAtEnd(_ tap: UITapGestureRecognizer) {
            let end = NSRange(location: textStorage.length, length: 0)
            if !isFirstResponder { guard becomeFirstResponder() else { return } }
            selectedRange = end
        }
        /// Shows the Format panel in place of the keyboard while it's open.
        weak var formattingActions: EditorActions?
        override var inputView: UIView? {
            get { formattingActions?.formattingInputView ?? super.inputView }
            set { super.inputView = newValue }
        }
        func closeFormattingPanel() {
            if markedTextRange == nil { formattingActions?.closeFormatting?(true) }
        }
        /// Backspace at the very start of the text, which UIKit ignores; true when it was handled (a list item's
        /// formatting removed).
        var deleteBackwardAtStart: (() -> Bool)?
        override func deleteBackward() {
            if selectedRange == NSRange(location: 0, length: 0), markedTextRange == nil,
                deleteBackwardAtStart?() == true
            {
                return
            }
            super.deleteBackward()
        }
        var keyboardFormatting: ((EditorCommand) -> Void)?
        var keyboardStructure: ((StructuredKeyboard.Key) -> Bool)?
        /// Whether the entry shows its Markdown source, where structural keys keep their usual meaning.
        var showsSource: (() -> Bool)?
        override var keyCommands: [UIKeyCommand]? {
            // While an input method composes text, its keys belong to the composition.
            guard markedTextRange == nil else { return super.keyCommands }
            var result = KeyboardFormatting.commands(action: #selector(applyFormatKey(_:)))
            if let escape = formattingActions?.formattingEscapeCommand() { result.append(escape) }
            if showsSource?() != true {
                for (input, flags, key) in [
                    ("\t", UIKeyModifierFlags(), StructuredKeyboard.Key.indent),
                    ("\t", .shift, .outdent), (UIKeyCommand.inputDownArrow, [], .down),
                ] {
                    if StructuredKeyboard.edit(
                        key, text: textStorage, selection: selectedRange, size: font?.pointSize ?? 17) != nil
                    {
                        result.append(
                            UIKeyCommand(input: input, modifierFlags: flags, action: #selector(applyStructuralKey(_:))))
                    }
                }
            }
            return result + (super.keyCommands ?? [])
        }
        @objc private func applyStructuralKey(_ key: UIKeyCommand) {
            _ = keyboardStructure?(
                key.input == UIKeyCommand.inputDownArrow
                    ? .down : key.modifierFlags.contains(.shift) ? .outdent : .indent)
        }
        @objc private func applyFormatKey(_ key: UIKeyCommand) {
            if let command = KeyboardFormatting.command(for: key) {
                keyboardFormatting?(command)
            }
        }

        /// TextKit adds paragraph spacing to a paragraph's last line, which made the caret reach into the next
        /// paragraph. The caret spans the font's ascender and descender on the line's baseline instead.
        override func caretRect(for position: UITextPosition) -> CGRect {
            let rect = super.caretRect(for: position)
            let offset = offset(from: beginningOfDocument, to: position)
            guard !rect.isNull, !rect.isInfinite, textStorage.length > 0,
                let (font, character) = caretFont(at: offset)
            else { return rect }
            let height = ceil(font.ascender - font.descender)
            guard rect.height > height + 1 else { return rect }
            // The system caret starts at the top of the line fragment; the baseline is measured within it, also on an
            // empty line, where the only glyph is the line break's.
            let baseline =
                rect.minY
                + ListMarkers.baseline(
                    ofCharacter: character, glyph: layoutManager.glyphIndexForCharacter(at: character),
                    layout: layoutManager)
            return CGRect(x: rect.minX, y: baseline - ceil(font.ascender), width: rect.width, height: height)
        }
        /// The font the caret sits in, and the character it's taken from: the character before the caret on the same
        /// line, else the one after it.
        private func caretFont(at offset: Int) -> (UIFont, Int)? {
            let text = textStorage.string as NSString
            let index: Int
            if offset > 0, offset <= text.length, ![0x0A, 0x2028].contains(text.character(at: offset - 1)) {
                index = offset - 1
            } else if offset < text.length {
                // At the start of a line, including an empty one whose only character is its line break.
                index = offset
            } else {
                return nil
            }
            guard text.character(at: index) != 0xFFFC,
                let font = textStorage.attribute(.font, at: index, effectiveRange: nil) as? UIFont
            else { return nil }
            return (font, index)
        }

        private let decorations = BlockDecorationView()
        /// A layout change resigns the keyboard just before removing the view; remember where the writing was.
        private var resigned: (selection: NSRange, time: Date)?
        /// Declines the keyboard UIKit offers when the title inside this view gives it up to Done.
        @discardableResult override func becomeFirstResponder() -> Bool {
            if formattingActions?.endingEditing == true { return false }
            return super.becomeFirstResponder()
        }
        @discardableResult override func resignFirstResponder() -> Bool {
            let wasWriting = isFirstResponder && window != nil
            let selection = selectedRange
            let resigned = super.resignFirstResponder()
            if resigned, wasWriting { self.resigned = (selection, Date()) }
            return resigned
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            if decorations.superview !== self {
                decorations.host = self
                insertSubview(decorations, at: 0)
            }
            // Covers only the visible area; redrawn as the text scrolls or changes.
            decorations.frame = CGRect(origin: contentOffset, size: bounds.size)
            decorations.setNeedsDisplay()
            containerLayoutChanged?()
            layoutChanged?()
        }
        /// Reports the selection when the view leaves its window while it holds the keyboard.
        var leftWhileWriting: ((NSRange) -> Void)?
        var enteredWindow: (() -> Void)?
        /// The view leaves the screen, as when the app locks.
        var leavingWindow: (() -> Void)?
        /// The app goes to the background while this view is on screen.
        var enteringBackground: (() -> Void)? {
            didSet {
                NotificationCenter.default.removeObserver(
                    self, name: UIScene.didEnterBackgroundNotification, object: nil)
                guard enteringBackground != nil else { return }
                NotificationCenter.default.addObserver(
                    self, selector: #selector(sceneEnteredBackground), name: UIScene.didEnterBackgroundNotification,
                    object: nil)
            }
        }
        @objc private func sceneEnteredBackground() { enteringBackground?() }
        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil {
                leavingWindow?()
                if isFirstResponder {
                    leftWhileWriting?(selectedRange)
                } else if let resigned, Date().timeIntervalSince(resigned.time) < 0.5 {
                    leftWhileWriting?(resigned.selection)
                }
                resigned = nil
                // Leaving while focused may never report the end of editing.
                formattingActions?.forget(self)
            }
            super.willMove(toWindow: newWindow)
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                formattingActions?.forgetDeparted()
                enteredWindow?()
            }
        }
        var containerLayoutChanged: (() -> Void)?
        var containerInteractionBegan: (() -> Void)?
        var receiveMarkdown: ((String) -> Void)?
        /// Text pasted from another app.
        var receiveFragment: ((PastedFragment) -> Void)?
        var receiveImages: (([PastedImages.Source]) -> Void)?
        /// The entry's Markdown for a selection, so copying and cutting within the journal keep images, tables and
        /// lists.
        var selectionMarkdown: ((NSRange) -> String?)?
        var compositionEnded: (() -> Void)?
        var layoutChanged: (() -> Void)?
        /// Where Copy, Cut and Paste go: the general pasteboard, or a private one in tests, which the simulator doesn't
        /// share with the Mac and which never asks to allow pasting.
        var pasteboard = UIPasteboard.general
        override func unmarkText() {
            super.unmarkText()
            compositionEnded?()
        }
        /// Copies a selected picture itself, for other apps; false when there is no picture to copy that way.
        var copySelectedImage: ((ImageItem) -> Bool)?
        override func copy(_ sender: Any?) {
            if let image = ImageItem.selected(selectedRange, in: textStorage), copySelectedImage?(image) == true {
                return
            }
            guard let item = pasteboardItem() else {
                super.copy(sender)
                return
            }
            pasteboard.setItems([item])
        }
        override func cut(_ sender: Any?) {
            guard let item = pasteboardItem() else {
                super.cut(sender)
                return
            }
            super.cut(sender)
            pasteboard.setItems([item])
        }
        /// The selection as the entry's Markdown, formatted text for other apps and plain text.
        private func pasteboardItem() -> [String: Any]? {
            let range = selectedRange
            guard range.length > 0, NSMaxRange(range) <= textStorage.length,
                let markdown = selectionMarkdown?(range)
            else { return nil }
            // Other apps take lists with their markers (ListEditing.swift).
            let selected = RichText.otherAppsText(textStorage, range: range)
            var item: [String: Any] = [
                PastedImages.markdownType: Data(markdown.utf8),
                // A table's Markdown is the most useful plain text for it; pictures have no text at all.
                UTType.utf8PlainText.identifier: RichText.tableSelectionMarkdown(textStorage, range: range)
                    ?? selected.string.replacingOccurrences(of: "\u{FFFC}", with: ""),
            ]
            if let rtf = try? selected.data(
                from: NSRange(location: 0, length: selected.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            {
                item[UTType.rtf.identifier] = rtf
            }
            return item
        }
        override func paste(_ sender: Any?) {
            if !pasteJournalContent(from: pasteboard) { super.paste(sender) }
        }
        override func pasteAndMatchStyle(_ sender: Any?) {
            guard let fragment = pasteboard.string.flatMap({ PastedRichText.fragment(plain: $0) }) else {
                super.pasteAndMatchStyle(sender)
                return
            }
            receiveFragment?(fragment)
        }
        /// Pastes the journal's own content, pictures, or text from another app; false when the pasteboard holds
        /// nothing the entry can take.
        func pasteJournalContent(from board: UIPasteboard) -> Bool {
            if let data = board.data(forPasteboardType: PastedImages.markdownType),
                let markdown = String(data: data, encoding: .utf8)
            {
                receiveMarkdown?(markdown)
                return true
            }
            let images = PastedImages.images(on: board)
            if !images.isEmpty {
                receiveImages?(images)
                return true
            }
            // Text from another app becomes the entry's own blocks, with its lists, headings, quotes and code. The
            // text view never reads it itself, which could load what a web page refers to.
            guard PastedRichText.hasText(on: board) else { return false }
            if let fragment = PastedRichText.fragment(on: board) { receiveFragment?(fragment) }
            return true
        }
    }
#endif
