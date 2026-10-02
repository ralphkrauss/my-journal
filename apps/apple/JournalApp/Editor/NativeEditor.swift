import JournalCore
import SwiftUI

/// Where an entry's text starts in the editor. The title starts its first letter where the body's starts
/// (docs/design/quiet-sync-and-title-alignment.md).
enum EntryTextInset {
    /// The body's text container inset at each side.
    #if os(macOS)
        static let body: CGFloat = 4
    #else
        static let body: CGFloat = 0
    #endif
    /// The body's line fragment padding: the text system's usual 5 points.
    static let linePadding: CGFloat = 5
    /// From the editor's edge to the body's first letter.
    static var text: CGFloat { body + linePadding }
}

#if os(macOS)
    import AppKit

    struct NativeEditor: NSViewRepresentable {
        @Environment(\.colorScheme) private var colorScheme
        @Binding var document: JournalDocument
        var itemID: UUID
        var images: [UUID: Data]
        var loadingImages: Set<UUID> = []
        var initialInsertion: InitialEditorInsertion?
        var fontSize: CGFloat
        var editable: Bool
        var actions: EditorActions
        /// “use a template”, the link in the empty body's placeholder (TemplateSuggestionView).
        var suggestion: AnyView? = nil
        var imageHandler: (Data) async -> DocumentBlock?

        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSScrollView()
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            let view = JournalTextView(frame: .zero)
            view.isRichText = true
            view.importsGraphics = false
            view.allowsUndo = true
            view.drawsBackground = false
            view.textContainerInset = NSSize(width: EntryTextInset.body, height: 8)
            view.textContainer?.lineFragmentPadding = EntryTextInset.linePadding
            view.isVerticallyResizable = true
            view.isHorizontallyResizable = false
            view.autoresizingMask = [.width]
            view.textContainer?.widthTracksTextView = true
            view.textContainer?.containerSize = NSSize(width: 620, height: CGFloat.greatestFiniteMagnitude)
            view.setAccessibilityLabel("Entry text")
            // Edit ▸ Find (⌘F) searches this entry with the standard find bar.
            view.usesFindBar = true
            view.isIncrementalSearchingEnabled = true
            view.delegate = context.coordinator
            view.updateDragTypeRegistration()
            scroll.documentView = view
            context.coordinator.view = view
            context.coordinator.update(self)
            return scroll
        }
        func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(self) }
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
            var parent: NativeEditor
            var tables: InlineTables?
            var taskControls: InlineTasks?
            weak var view: JournalTextView? {
                didSet { if oldValue !== view { sessionGeneration = UUID() } }
            }
            var sessionGeneration = UUID()
            var rendered: JournalDocument?
            var lastID: UUID?
            var appearance: ColorScheme?
            var imageIDs: Set<UUID> = []
            var loadingIDs: Set<UUID> = []
            var size: CGFloat = 0
            var imageWidth: CGFloat = 0
            var applying = false
            /// Whether the entry shows its Markdown source; set by the editor, never inferred from the text.
            var showsSource = false
            /// A change from elsewhere that waits until an input method's composition ends.
            var pendingExternal: JournalDocument?
            /// Set while the editor puts its own, already complete text in place.
            var replacingText = false
            /// The empty body's placeholder: “Start writing…”, or “Start writing or ” followed by the link.
            let placeholder = PlaceholderTextView()
            var suggestionHost: NSHostingView<AnyView>?
            /// Attachments pasted or dropped from elsewhere whose images are being imported.
            var importingAttachments: Set<ObjectIdentifier> = []
            /// Typing in a table cell that extends the current undo step, if any.
            var cellTyping: CellTypingUndo?
            /// What the text read as, so typing reads only the paragraph it changed.
            var reading = EditorReading()
            /// This editor's pictures, decoded at the size they are shown.
            let thumbnails = ImageThumbnails()
            /// The person's own text checking for prose, kept while the caret is in code or Markdown source.
            var proseChecking: TextChecking?
            /// The line as typed before a Markdown shortcut converted it, so Backspace right after can restore it.
            var shortcutRevert: MarkdownShortcuts.Revert?
            init(_ parent: NativeEditor) {
                self.parent = parent
                super.init()
                for name in [
                    Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange,
                ] {
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(undoCompleted(_:)), name: name, object: nil)
                }
            }
            @objc private func undoCompleted(_ notification: Notification) {
                guard let view, !applying, parent.editable,
                    let manager = notification.object as? UndoManager, manager === view.undoManager
                else { return }
                textDidChange(notification)
                refreshImages(force: true)
            }
            func update(_ parent: NativeEditor) {
                if lastID != parent.itemID || self.parent.editable != parent.editable
                    || rendered != parent.document
                {
                    sessionGeneration = UUID()
                }
                self.parent = parent
                thumbnails.keep(parent.images)
                guard let view else { return }
                view.isEditable = parent.editable
                configureTables()
                limitUndo()
                view.compositionEnded = { [weak self] in self?.compositionEnded() }
                view.layoutChanged = { [weak self] in
                    self?.refreshImages()
                    self?.synchronizeTables()
                    self?.placeSuggestion()
                }
                configureKeyboard(view)
                view.receiveImages = { [weak self] images in self?.receiveImages(images) }
                if lastID != parent.itemID || rendered != parent.document || size != parent.fontSize {
                    render(parent, in: view)
                } else if imageIDs != Set(parent.images.keys) || loadingIDs != parent.loadingImages
                    || appearance != parent.colorScheme
                {
                    refreshImages()
                }
                placeLateInsertion(in: view)
                synchronizeTables()
                showSuggestion(parent.suggestion)
            }
            /// A template shown before its answer line was known (the open entry can show it while it's being
            /// saved): the caret goes there once it is, unless the person is already writing.
            private func placeLateInsertion(in view: JournalTextView) {
                guard view.window?.firstResponder !== view,
                    let insertion = parent.initialInsertion,
                    insertion.isPending(itemID: parent.itemID, document: parent.document),
                    let location = insertion.consume(
                        itemID: parent.itemID, document: parent.document, text: view.attributedString())
                else { return }
                view.setSelectedRange(NSRange(location: location, length: 0))
                view.typingAttributes = RichText.attributes(kind: "paragraph", size: parent.fontSize)
            }
            private func render(_ parent: NativeEditor, in view: JournalTextView) {
                let newItem = lastID != parent.itemID
                let external = !newItem && rendered != parent.document
                // An input method's composition keeps its place; the change is shown once it ends.
                if external, view.hasMarkedText() {
                    pendingExternal = parent.document
                    return
                }
                pendingExternal = nil
                let selection = view.selectedRange()
                showsSource = !newItem && showsSource || parent.document.requiresMarkdownSource
                applying = true
                replacingText = true
                view.textStorage?.setAttributedString(
                    RichText.render(
                        parent.document, size: parent.fontSize, images: parent.images, sourceMode: showsSource,
                        layout: imageLayout))
                replacingText = false
                view.typingAttributes =
                    showsSource
                    ? MarkdownEditing.attributes(size: parent.fontSize)
                    : RichText.attributes(kind: "paragraph", size: parent.fontSize)
                let initialLocation =
                    newItem || external
                    ? parent.initialInsertion?.consume(
                        itemID: parent.itemID, document: parent.document, text: view.attributedString()) : nil
                let length = view.string.utf16.count
                let location = initialLocation ?? min(selection.location, length)
                // A change from elsewhere or in text size (View ▸ Zoom) keeps the selection where it still fits;
                // another entry starts at a caret.
                view.setSelectedRange(
                    NSRange(location: location, length: newItem ? 0 : min(selection.length, length - location)))
                if initialLocation != nil {
                    view.typingAttributes = RichText.attributes(kind: "paragraph", size: parent.fontSize)
                }
                // Undo steps refer to the text as it was; after a change from elsewhere they no longer apply.
                if newItem || external { view.undoManager?.removeAllActions() }
                applying = false
                rendered = parent.document
                lastID = parent.itemID
                size = parent.fontSize

                appearance = parent.colorScheme
                imageIDs = Set(parent.images.keys)
                loadingIDs = parent.loadingImages
                imageWidth = max(40, view.bounds.width - 20)
            }
            private func configureKeyboard(_ view: JournalTextView) {
                parent.actions.isEditing = { [weak self, weak view] in
                    view?.window?.firstResponder === view || self?.tables?.active != nil
                }
                parent.actions.handler = { [weak self] command in
                    if case .focus = command {
                        self?.perform(command)
                        return
                    }
                    guard let self, let view = self.view,
                        view.window?.firstResponder === view || self.tables?.active != nil
                    else { return }
                    self.perform(command)
                }
                parent.actions.beginFormatting = { [weak self] in self?.formattingSession() }
                view.cancelFormatting = { [weak self] in
                    guard let close = self?.parent.actions.closeFormatting else { return false }
                    close(true)
                    return true
                }
                parent.actions.selectionText = { [weak self, weak view] in
                    if let selected = self?.tables?.selectedCellText { return selected }
                    guard let view else { return "" }
                    return (view.string as NSString).substring(with: view.selectedRange())
                }
                parent.actions.selectionStyle = { [weak self, weak view] in
                    if let selected = self?.tables?.selectedCellStyle { return selected }
                    guard let view else { return FormattingState() }
                    return FormattingState(
                        text: view.attributedString(), range: view.selectedRange(), typing: view.typingAttributes,
                        source: self?.showsSource)
                }

            }
            func refreshImages(force: Bool = false) {
                guard let view, view.bounds.width.isFinite, view.bounds.width > 20 else { return }
                let width = max(40, view.bounds.width - 20)
                guard
                    force || abs(imageWidth - width) > 0.5 || imageIDs != Set(parent.images.keys)
                        || loadingIDs != parent.loadingImages
                        || appearance != parent.colorScheme
                else { return }
                guard !applying, !view.hasMarkedText(), let storage = view.textStorage,
                    let layout = view.layoutManager, let container = view.textContainer
                else { return }
                applying = true
                defer { applying = false }
                let selection = view.selectedRange()
                let typing = view.typingAttributes
                let origin = view.visibleRect.origin
                let anchor = ImagePresentation.visibleAnchor(
                    storage, layout: layout, container: container, viewport: view.visibleRect)
                let before = ImagePresentation.anchorY(anchor, layout: layout, container: container)
                view.undoManager?.disableUndoRegistration()
                ImagePresentation.update(storage, images: parent.images, size: parent.fontSize, layout: imageLayout)
                view.undoManager?.enableUndoRegistration()
                view.setSelectedRange(selection)
                view.typingAttributes = typing
                if let before, let after = ImagePresentation.anchorY(anchor, layout: layout, container: container) {
                    view.scroll(NSPoint(x: origin.x, y: max(0, origin.y + after - before)))
                }
                appearance = parent.colorScheme
                imageIDs = Set(parent.images.keys)
                loadingIDs = parent.loadingImages
                imageWidth = max(40, view.bounds.width - 20)
            }

            func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
                let structural: StructuredKeyboard.Key? =
                    commandSelector == #selector(NSResponder.insertTab(_:))
                    ? .indent
                    : commandSelector == #selector(NSResponder.insertBacktab(_:))
                        ? .outdent : commandSelector == #selector(NSResponder.moveDown(_:)) ? .down : nil
                if let structural, performStructuralKey(structural) { return true }
                if commandSelector == #selector(NSResponder.insertNewline(_:)), let view,
                    convertLineOnReturn(selection: view.selectedRange())
                {
                    return true
                }
                guard commandSelector == #selector(NSResponder.insertNewline(_:)), let view, !view.hasMarkedText(),
                    !editingSource, let storage = view.textStorage,
                    let action = RichText.newlineAction(storage, selection: view.selectedRange(), size: parent.fontSize)
                else { return false }
                replace(action.replacement, range: action.range)
                if let caret = action.caret { view.setSelectedRange(NSRange(location: caret, length: 0)) }
                view.typingAttributes =
                    action.typing ?? RichText.attributes(kind: action.nextKind, size: parent.fontSize)
                return true
            }
            func textViewDidChangeSelection(_ notification: Notification) {
                guard !applying else { return }
                applySubstitutions()
                updateCaretState()
                parent.actions.formattingSelectionChanged()
            }
            func textView(
                _ textView: NSTextView, willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                toCharacterRange newSelectedCharRange: NSRange
            ) -> NSRange {
                guard !showsSource, !textView.hasMarkedText(), let storage = textView.textStorage else {
                    return newSelectedCharRange
                }
                return HiddenMarkers.caret(storage, proposed: newSelectedCharRange, previous: oldSelectedCharRange)
            }
            func textView(
                _ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any],
                toAttributes newTypingAttributes: [NSAttributedString.Key: Any]
            ) -> [NSAttributedString.Key: Any] {
                showsSource
                    ? newTypingAttributes : HiddenMarkers.typingAttributes(newTypingAttributes, size: parent.fontSize)
            }
            func textView(
                _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?
            ) -> Bool {
                guard !applying else { return true }
                // Attribute changes, such as Underline from the Format menu, replace no text.
                guard let replacementString else {
                    shortcutRevert = nil
                    return true
                }
                guard markdownShortcutShouldChange(in: affectedCharRange, replacement: replacementString) else {
                    return false
                }
                announceChange(in: affectedCharRange, replacement: replacementString)
                return true
            }
            func textDidChange(_ notification: Notification) {
                guard !applying, let view, let storage = view.textStorage else { return }
                // The first character hides the placeholder and its link at once; an empty body brings them back.
                if !view.string.isEmpty, !placeholder.isHidden {
                    placeholder.isHidden = true
                    suggestionHost?.isHidden = true
                }
                acceptEdit(readEdit(storage))
                refreshImages(force: view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true)
                synchronizeTables()
                parent.actions.formattingSelectionChanged()
            }
            /// Replaces text as one undo step. `adopting` text is placed like pasted text: it joins the block it lands in.
            func replace(
                _ text: NSAttributedString, range: NSRange, actionName: String? = nil, showingSource: Bool? = nil,
                typingIn cell: AnyHashable? = nil, adopting: Bool = false
            ) {
                guard let view else { return }
                replacingText = !adopting
                defer { replacingText = false }
                view.undoManager?.disableUndoRegistration()
                let allowed = view.shouldChangeText(in: range, replacementString: text.string)
                view.undoManager?.enableUndoRegistration()
                guard allowed else { return }
                registerSnapshot(actionName: actionName, typingIn: cell)
                if let showingSource { showsSource = showingSource }
                view.undoManager?.disableUndoRegistration()
                defer { view.undoManager?.enableUndoRegistration() }
                view.textStorage?.replaceCharacters(in: range, with: text)
                view.didChangeText()
                view.setSelectedRange(NSRange(location: range.location + text.length, length: 0))
                if cell != nil { cellTyping?.document = parent.document }
            }
            func formattingSession() -> ((EditorCommand) -> Void)? {
                if let cellSession = tables?.cellFormattingSession(fallback: { [weak self] command in
                    self?.perform(command)
                }) {
                    return cellSession
                }
                guard let view, parent.editable else { return nil }
                let id = parent.itemID
                var generation = sessionGeneration
                var range = view.selectedRange()
                var document = parent.document
                var text = view.string
                return { [weak self] command in
                    guard let self, let view = self.view, self.parent.itemID == id, self.parent.editable else { return }
                    if self.sessionGeneration != generation || self.parent.document != document {
                        // Formatting applies only to the text it was chosen for, but an image that finishes
                        // importing after further writing still goes where it was placed.
                        guard case .image = command else { return }
                        range = TextRanges.insertionPoint(following: range, from: text, to: view.string)
                    }
                    guard NSMaxRange(range) <= view.string.utf16.count else { return }
                    view.setSelectedRange(range)
                    self.perform(command)
                    range = view.selectedRange()
                    document = self.parent.document
                    generation = self.sessionGeneration
                    text = view.string
                }
            }
            private func focusEditor() { view?.window?.makeFirstResponder(view) }
            func perform(_ command: EditorCommand) {
                if tables?.active?.formatCell(command) == true { return }
                guard let view, let storage = view.textStorage, parent.editable else { return }
                commitComposition(before: command)
                let selection = view.selectedRange()
                if let typing = MarkdownEditing.typingCommand(
                    command, textIsEmpty: storage.length == 0, selection: selection, typing: view.typingAttributes,
                    size: parent.fontSize, source: showsSource)
                {
                    if case .source = command { showsSource.toggle() }
                    view.typingAttributes = typing
                    parent.actions.sourceMode = showsSource
                    view.window?.makeFirstResponder(view)
                    return
                }
                if applyMarkdownEdit(command) { return }
                // Source text only changes through Markdown syntax; never apply rich attributes to it.
                if editingSource {
                    if case .focus = command { focusEditor() }
                    return
                }
                switch command {
                case .source, .strikethrough, .code, .insert, .linkDialog, .imagePicker, .toggleTask, .indent, .outdent:
                    return
                case .focus: view.window?.makeFirstResponder(view)
                case .bold, .italic, .underline:
                    if selection.length == 0 {
                        view.typingAttributes = RichText.toggling(
                            command, in: view.typingAttributes, size: parent.fontSize)
                    } else {
                        replace(
                            RichText.toggling(command, in: storage.attributedSubstring(from: selection)),
                            range: selection)
                        view.setSelectedRange(selection)
                    }
                case .paragraph(let kind):
                    let range = RichText.paragraphContentRange(view.string, selection: selection)
                    let text = NSMutableAttributedString(
                        attributedString: storage.attributedSubstring(from: range))
                    var doc = RichText.document(text)
                    doc = RichText.restyling(doc, kind: kind)
                    let replacement = RichText.render(
                        doc, size: parent.fontSize, images: parent.images, layout: imageLayout)
                    replace(replacement, range: range)
                    view.typingAttributes = RichText.attributes(kind: kind, size: parent.fontSize)
                case .link(let address, let displayText):
                    guard let url = LinkAddress.url(address) else { return }
                    let replacement = LinkInsertion.text(
                        storage, selection: selection, address: url.absoluteString, displayText: displayText,
                        attributes: view.typingAttributes, url: url)
                    replace(replacement, range: selection)
                case .image(let block):
                    let rendered = RichText.render(
                        .init(blocks: [block, DocumentBlock()]), size: parent.fontSize, images: parent.images,
                        layout: imageLayout)
                    let text = NSMutableAttributedString(
                        string: selection.location > 0
                            && (view.string as NSString).substring(
                                with: NSRange(location: selection.location - 1, length: 1)) != "\n"
                            ? "\n" : "", attributes: RichText.attributes(kind: "paragraph", size: parent.fontSize))
                    text.append(rendered)
                    replace(text, range: selection)
                }
                view.window?.makeFirstResponder(view)
            }
        }
    }
#else
    import UIKit

    struct NativeEditor: UIViewRepresentable {
        @Environment(\.colorScheme) private var colorScheme
        @Binding var document: JournalDocument
        var itemID: UUID
        var images: [UUID: Data]
        var loadingImages: Set<UUID> = []
        var initialInsertion: InitialEditorInsertion?
        var fontSize: CGFloat
        var editable: Bool
        var actions: EditorActions
        var header: AnyView? = nil
        /// Offered over the empty body, below its placeholder (TemplateSuggestionView).
        var suggestion: AnyView? = nil
        var revealSaveFailure = false
        var imageHandler: (Data) async -> DocumentBlock?
        func makeUIView(context: Context) -> JournalWritingView {
            let container = JournalWritingView()
            let view = container.editor
            view.backgroundColor = .clear
            view.isScrollEnabled = true
            view.textContainerInset = UIEdgeInsets(
                top: 8, left: EntryTextInset.body, bottom: 24, right: EntryTextInset.body)
            view.textContainer.lineFragmentPadding = EntryTextInset.linePadding
            view.adjustsFontForContentSizeCategory = true
            view.accessibilityLabel = "Entry text"
            view.delegate = context.coordinator
            view.allowsEditingTextAttributes = true
            let accessory = WritingAccessory(actions: actions)
            accessory.controlsMoved = { [weak coordinator = context.coordinator] in coordinator?.updateWritingInset() }
            view.inputAccessoryView = accessory
            WritingAccessory.hideSystemFormatting(of: view)
            view.isFindInteractionEnabled = true
            view.formattingActions = actions
            actions.findInEntry = { [weak view] in view?.findInteraction?.presentFindNavigator(showingReplace: false) }
            context.coordinator.view = view
            context.coordinator.update(self)
            configure(container)
            continueInterruptedWriting(view, coordinator: context.coordinator)
            return container
        }
        func updateUIView(_ container: JournalWritingView, context: Context) {
            context.coordinator.update(self)
            configure(container)
        }
        static func dismantleUIView(_ container: JournalWritingView, coordinator: Coordinator) {
            container.editor.formattingActions?.forget(container.editor)
        }
        /// Keeps the keyboard up when a layout change replaces this editor mid-sentence, as Notes does on rotation.
        /// The replacement may appear before or after the old editor leaves, so both moments offer the writing.
        private func continueInterruptedWriting(_ view: JournalTextView, coordinator: Coordinator) {
            let resume: @MainActor @Sendable () -> Void = { [weak view, weak actions, weak coordinator] in
                guard let view, view.window != nil, let actions, let interrupted = actions.interruptedWriting,
                    interrupted.itemID == coordinator?.parent.itemID
                else { return }
                actions.interruptedWriting = nil
                // Only an editor that replaces the previous one at once continues; a later visit does not.
                guard Date().timeIntervalSince(interrupted.time) < 1, view.becomeFirstResponder() else { return }
                let length = view.textStorage.length
                let location = min(interrupted.selection.location, length)
                view.selectedRange = NSRange(
                    location: location, length: min(interrupted.selection.length, length - location))
            }
            view.leftWhileWriting = { [weak actions, weak coordinator] selection in
                guard let actions, let id = coordinator?.parent.itemID else { return }
                actions.interruptedWriting = (id, selection, Date())
                DispatchQueue.main.async { [weak actions] in actions?.continueWriting?() }
            }
            view.enteredWindow = { [weak actions] in
                actions?.continueWriting = resume
                DispatchQueue.main.async { resume() }
            }
        }
        private func configure(_ container: JournalWritingView) {
            let empty = document.text.isEmpty && document.blocks.allSatisfy { $0.kind != "image" }
            container.configure(
                header: header, suggestion: suggestion, entryID: itemID, failure: revealSaveFailure,
                placeholderSize: empty ? fontSize : nil)
        }
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        @MainActor final class Coordinator: NSObject, UITextViewDelegate {
            var parent: NativeEditor
            var tables: InlineTables?
            var taskControls: InlineTasks?
            weak var view: JournalTextView? {
                didSet { if oldValue !== view { sessionGeneration = UUID() } }
            }
            var sessionGeneration = UUID()
            var rendered: JournalDocument?
            var lastID: UUID?
            var appearance: ColorScheme?
            var imageIDs: Set<UUID> = []
            var loadingIDs: Set<UUID> = []
            var size: CGFloat = 0
            var imageWidth: CGFloat = 0
            var applyingImages = false
            /// Whether the entry shows its Markdown source; set by the editor, never inferred from the text.
            var showsSource = false
            /// A change from elsewhere that waits until an input method's composition ends.
            var pendingExternal: JournalDocument?
            /// Set while the editor puts its own, already complete text in place.
            var replacingText = false
            /// Attachments pasted or dropped from elsewhere whose images are being imported.
            var importingAttachments: Set<ObjectIdentifier> = []
            /// Typing in a table cell that extends the current undo step, if any.
            var cellTyping: CellTypingUndo?
            /// What the text read as, so typing reads only the paragraph it changed.
            var reading = EditorReading()
            /// This editor's pictures, decoded at the size they are shown.
            let thumbnails = ImageThumbnails()
            /// Until when the caret is kept above the writing controls after a picture was inserted or the entry was
            /// resized (SelectionReveal.swift).
            var caretRevealDeadline: Date?
            /// The entry's size when it was last laid out, to notice rotation.
            var laidOutSize = CGSize.zero
            /// The selection before the latest change, so the caret can step over hidden markers in either direction.
            private var previousSelection = NSRange(location: 0, length: 0)
            /// The line as typed before a Markdown shortcut converted it, so Backspace right after can restore it.
            var shortcutRevert: MarkdownShortcuts.Revert?
            init(_ parent: NativeEditor) {
                self.parent = parent
                super.init()
                // The keyboard, the Format panel and the writing controls change the room left for the entry.
                NotificationCenter.default.addObserver(
                    self, selector: #selector(keyboardChangedFrame),
                    name: UIResponder.keyboardDidChangeFrameNotification,
                    object: nil)
            }
            @objc private func keyboardChangedFrame(_ notification: Notification) {
                updateWritingInset()
            }
            func update(_ parent: NativeEditor) {
                if lastID != parent.itemID || self.parent.editable != parent.editable
                    || rendered != parent.document
                {
                    sessionGeneration = UUID()
                }
                self.parent = parent
                thumbnails.keep(parent.images)
                guard let view else { return }
                view.isEditable = parent.editable
                configureTables()
                limitUndo()
                view.compositionEnded = { [weak self] in self?.compositionEnded() }
                view.layoutChanged = { [weak self] in
                    self?.refreshImages()
                    self?.synchronizeTables()
                    self?.updateWritingInset()
                    self?.revealCaretAfterResize()
                    self?.keepCaretRevealed()
                }
                configureKeyboard(view)
                parent.actions.beginFormatting = { [weak self] in self?.formattingSession() }
                parent.actions.focusedTextInput = { [weak self] in
                    if let cell = self?.tables?.active?.activeCell { return cell }
                    guard let view = self?.view, view.isFirstResponder else { return nil }
                    return view
                }
                parent.actions.commitComposition = { [weak self] in
                    if let cell = self?.tables?.active?.activeCell {
                        if cell.markedTextRange != nil { cell.unmarkText() }
                    } else {
                        self?.commitComposition()
                    }
                }
                parent.actions.selectionText = { [weak self, weak view] in
                    if let selected = self?.tables?.selectedCellText { return selected }
                    guard let view else { return "" }
                    return (view.textStorage.string as NSString).substring(with: view.selectedRange)
                }
                parent.actions.selectionStyle = { [weak self, weak view] in
                    if let selected = self?.tables?.selectedCellStyle { return selected }
                    guard let view else { return FormattingState() }
                    return FormattingState(
                        text: view.textStorage, range: view.selectedRange, typing: view.typingAttributes,
                        source: self?.showsSource)
                }

                view.receiveImages = { [weak self] images in self?.receiveImages(images) }
                if rendered != parent.document || lastID != parent.itemID
                    || size != parent.fontSize
                {
                    render(parent, in: view)
                } else if imageIDs != Set(parent.images.keys) || loadingIDs != parent.loadingImages
                    || appearance != parent.colorScheme
                {
                    refreshImages()
                }
                placeLateInsertion(in: view)
                synchronizeTables()
            }
            /// A template shown before its answer line was known (the open entry can show it while it's being
            /// saved): the caret goes there once it is, unless the person is already writing.
            private func placeLateInsertion(in view: JournalTextView) {
                guard !view.isFirstResponder,
                    let insertion = parent.initialInsertion,
                    insertion.isPending(itemID: parent.itemID, document: parent.document),
                    let location = insertion.consume(
                        itemID: parent.itemID, document: parent.document, text: view.textStorage)
                else { return }
                view.selectedRange = NSRange(location: location, length: 0)
                view.typingAttributes = RichText.attributes(kind: "paragraph", size: parent.fontSize)
            }
            private func render(_ parent: NativeEditor, in view: JournalTextView) {
                let newItem = lastID != parent.itemID
                let external = !newItem && rendered != parent.document
                // An input method's composition keeps its place; the change is shown once it ends.
                if external, view.markedTextRange != nil {
                    pendingExternal = parent.document
                    return
                }
                pendingExternal = nil
                applyingImages = true
                replacingText = true
                defer {
                    applyingImages = false
                    replacingText = false
                }
                let selection = view.selectedRange
                showsSource = !newItem && showsSource || parent.document.requiresMarkdownSource
                view.attributedText = RichText.render(
                    parent.document, size: parent.fontSize, images: parent.images, sourceMode: showsSource,
                    layout: imageLayout)
                view.typingAttributes =
                    showsSource
                    ? MarkdownEditing.attributes(size: parent.fontSize)
                    : RichText.attributes(kind: "paragraph", size: parent.fontSize)
                let initialLocation =
                    newItem || external
                    ? parent.initialInsertion?.consume(
                        itemID: parent.itemID, document: parent.document, text: view.textStorage) : nil
                let length = view.textStorage.length
                let location = initialLocation ?? min(selection.location, length)
                // A change from elsewhere or in text size (View ▸ Zoom) keeps the selection where it still fits;
                // another entry starts at a caret.
                view.selectedRange = NSRange(
                    location: location, length: newItem ? 0 : min(selection.length, length - location))
                if initialLocation != nil {
                    view.typingAttributes = RichText.attributes(kind: "paragraph", size: parent.fontSize)
                }
                // Undo steps refer to the text as it was; after a change from elsewhere they no longer apply.
                if newItem || external { view.undoManager?.removeAllActions() }
                rendered = parent.document
                lastID = parent.itemID
                appearance = parent.colorScheme
                imageIDs = Set(parent.images.keys)
                loadingIDs = parent.loadingImages
                imageWidth = max(40, view.bounds.width - 20)

                size = parent.fontSize
            }
            private func configureKeyboard(_ view: JournalTextView) {
                parent.actions.owningWindow = { [weak view] in view?.window }
                view.keyboardStructure = { [weak self] key in self?.performStructuralKey(key) ?? false }
                parent.actions.isEditing = { [weak self, weak view] in
                    view?.isFirstResponder == true || self?.tables?.active != nil
                }
                parent.actions.handler = { [weak self] command in
                    if case .focus = command {
                        self?.perform(command)
                        return
                    }
                    guard let self, self.view?.isFirstResponder == true || self.tables?.active != nil else { return }
                    self.perform(command)
                }
                view.keyboardFormatting = { [weak self] command in
                    guard let self else { return }
                    if case .linkDialog = command {
                        self.parent.actions.openLinkFromKeyboard()
                    } else {
                        self.perform(command)
                    }
                }

            }
            func refreshImages(force: Bool = false) {
                guard let view, view.bounds.width.isFinite, view.bounds.width > 20 else { return }
                let width = max(40, view.bounds.width - 20)
                guard
                    force || abs(imageWidth - width) > 0.5 || imageIDs != Set(parent.images.keys)
                        || loadingIDs != parent.loadingImages
                        || appearance != parent.colorScheme
                else { return }
                guard !applyingImages, view.markedTextRange == nil else { return }
                applyingImages = true
                defer { applyingImages = false }
                let selection = view.selectedRange
                let typing = view.typingAttributes
                let origin = view.contentOffset
                let layout = view.layoutManager
                let container = view.textContainer
                let viewport = CGRect(
                    x: origin.x, y: origin.y - view.textContainerInset.top, width: view.bounds.width,
                    height: view.bounds.height)
                let anchor = ImagePresentation.visibleAnchor(
                    view.textStorage, layout: layout, container: container, viewport: viewport)
                let before = ImagePresentation.anchorY(anchor, layout: layout, container: container)
                view.undoManager?.disableUndoRegistration()
                ImagePresentation.update(
                    view.textStorage, images: parent.images, size: parent.fontSize, layout: imageLayout)
                view.undoManager?.enableUndoRegistration()
                view.selectedRange = selection
                view.typingAttributes = typing
                if let before, let after = ImagePresentation.anchorY(anchor, layout: layout, container: container) {
                    view.setContentOffset(
                        CGPoint(x: origin.x, y: max(-view.adjustedContentInset.top, origin.y + after - before)),
                        animated: false)
                }
                appearance = parent.colorScheme
                imageIDs = Set(parent.images.keys)
                loadingIDs = parent.loadingImages
                imageWidth = max(40, view.bounds.width - 20)
            }

            func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String)
                -> Bool
            {
                endCaretReveal()
                guard markdownShortcutShouldChange(in: range, replacement: text) else { return false }
                if text == "\n", convertLineOnReturn(selection: range) { return false }
                guard text == "\n", textView.markedTextRange == nil, !editingSource,
                    let action = RichText.newlineAction(
                        textView.textStorage, selection: range, size: parent.fontSize)
                else {
                    announceChange(in: range, replacement: text)
                    return true
                }
                replace(action.replacement, range: action.range)
                if let caret = action.caret { textView.selectedRange = NSRange(location: caret, length: 0) }
                textView.typingAttributes =
                    action.typing ?? RichText.attributes(kind: action.nextKind, size: parent.fontSize)
                return false
            }
            func textViewDidEndEditing(_ textView: UITextView) {
                parent.actions.setEditing(false, by: textView)
                updateWritingInset()
            }
            func textViewDidChangeSelection(_ textView: UITextView) {
                let selection = textView.selectedRange
                if !showsSource, textView.markedTextRange == nil {
                    let caret = HiddenMarkers.caret(
                        textView.textStorage, proposed: selection, previous: previousSelection)
                    if caret != selection {
                        previousSelection = caret
                        textView.selectedRange = caret
                    }
                    // UIKit derives typing attributes from the character before the caret, including a hidden marker.
                    if HiddenMarkers.isInvisible(textView.typingAttributes) {
                        textView.typingAttributes = HiddenMarkers.typingAttributes(
                            textView.typingAttributes, size: parent.fontSize)
                    }
                }
                previousSelection = textView.selectedRange
                applySubstitutions()
                updateCaretState()
                parent.actions.formattingSelectionChanged()
            }
            func textViewDidBeginEditing(_ textView: UITextView) {
                parent.actions.setEditing(true, by: textView)
                view?.containerInteractionBegan?()
            }
            func textViewDidChange(_ view: UITextView) {
                (view.superview as? JournalWritingView)?.editorTextChanged()
                guard !applyingImages else { return }
                self.view?.containerInteractionBegan?()
                acceptEdit(readEdit(view.textStorage))
                // Undo and redo restore earlier attachments; show them with the images loaded now, as on the Mac.
                refreshImages(force: view.undoManager?.isUndoing == true || view.undoManager?.isRedoing == true)
                synchronizeTables()
                parent.actions.formattingSelectionChanged()
            }
            /// Replaces text as one undo step. `adopting` text is placed like pasted text: it joins the block it lands in.
            func replace(
                _ text: NSAttributedString, range: NSRange, actionName: String? = nil, showingSource: Bool? = nil,
                typingIn cell: AnyHashable? = nil, adopting: Bool = false
            ) {
                guard let view else { return }
                registerSnapshot(actionName: actionName, typingIn: cell)
                if let showingSource { showsSource = showingSource }
                let typing = view.typingAttributes
                replacingText = !adopting
                view.textStorage.replaceCharacters(in: range, with: text)
                replacingText = false
                view.selectedRange = NSRange(location: range.location + text.length, length: 0)
                if view.textStorage.length == 0 { view.typingAttributes = typing }
                textViewDidChange(view)
                revealCaretAfterEdit()
                if cell != nil { cellTyping?.document = parent.document }
            }
            func formattingSession() -> ((EditorCommand) -> Void)? {
                if let cellSession = tables?.cellFormattingSession(fallback: { [weak self] command in
                    self?.perform(command)
                }) {
                    return cellSession
                }
                guard let view, parent.editable else { return nil }
                let id = parent.itemID
                var generation = sessionGeneration
                var range = view.selectedRange
                var document = parent.document
                var text = view.textStorage.string
                return { [weak self] command in
                    guard let self, let view = self.view, self.parent.itemID == id, self.parent.editable else { return }
                    if self.sessionGeneration != generation || self.parent.document != document {
                        // Formatting applies only to the text it was chosen for, but an image that finishes
                        // importing after further writing still goes where it was placed.
                        guard case .image = command else { return }
                        range = TextRanges.insertionPoint(following: range, from: text, to: view.textStorage.string)
                    }
                    guard NSMaxRange(range) <= view.textStorage.length else { return }
                    view.selectedRange = range
                    self.perform(command)
                    range = view.selectedRange
                    document = self.parent.document
                    generation = self.sessionGeneration
                    text = view.textStorage.string
                }
            }
            private func focusEditor() { view?.becomeFirstResponder() }
            func perform(_ command: EditorCommand) {
                if tables?.active?.formatCell(command) == true { return }
                guard let view, parent.editable else { return }
                commitComposition(before: command)
                let selection = view.selectedRange
                if let typing = MarkdownEditing.typingCommand(
                    command, textIsEmpty: view.textStorage.length == 0, selection: selection,
                    typing: view.typingAttributes, size: parent.fontSize, source: showsSource)
                {
                    if case .source = command { showsSource.toggle() }
                    view.typingAttributes = typing
                    parent.actions.sourceMode = showsSource
                    if case .source = command {
                        if parent.actions.editing { view.becomeFirstResponder() }
                    } else {
                        view.becomeFirstResponder()
                    }
                    return
                }
                if applyMarkdownEdit(command) { return }
                // Source text only changes through Markdown syntax; never apply rich attributes to it.
                if editingSource {
                    if case .focus = command { focusEditor() }
                    return
                }
                switch command {
                case .source, .strikethrough, .code, .insert, .linkDialog, .imagePicker, .toggleTask, .indent, .outdent:
                    return
                case .focus: view.becomeFirstResponder()
                case .bold:
                    view.toggleBoldface(nil)
                    textViewDidChange(view)
                case .italic:
                    view.toggleItalics(nil)
                    textViewDidChange(view)
                case .underline:
                    view.toggleUnderline(nil)
                    textViewDidChange(view)
                case .paragraph(let kind):
                    let range = RichText.paragraphContentRange(view.textStorage.string, selection: selection)
                    var doc = RichText.document(view.textStorage.attributedSubstring(from: range))
                    doc = RichText.restyling(doc, kind: kind)
                    replace(
                        RichText.render(doc, size: parent.fontSize, images: parent.images, layout: imageLayout),
                        range: range)
                    view.typingAttributes = RichText.attributes(kind: kind, size: parent.fontSize)
                case .link(let address, let displayText):
                    guard let url = LinkAddress.url(address) else { return }
                    let replacement = LinkInsertion.text(
                        view.textStorage, selection: selection, address: url.absoluteString, displayText: displayText,
                        attributes: view.typingAttributes, url: url)
                    replace(replacement, range: selection)
                case .image(let block):
                    // As on the Mac, an image placed on an empty line needs no line break before it.
                    let text = NSMutableAttributedString(
                        string: selection.location > 0
                            && (view.textStorage.string as NSString).character(at: selection.location - 1) != 0x0A
                            ? "\n" : "",
                        attributes: RichText.attributes(kind: "paragraph", size: parent.fontSize))
                    text.append(
                        RichText.render(
                            .init(blocks: [block, DocumentBlock()]), size: parent.fontSize, images: parent.images,
                            layout: imageLayout))
                    replace(text, range: selection)
                    view.becomeFirstResponder()
                    revealCaretAfterImage()
                    return
                }
                view.becomeFirstResponder()
            }
        }
    }
#endif
