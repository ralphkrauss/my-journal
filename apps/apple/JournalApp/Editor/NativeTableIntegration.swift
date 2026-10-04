import JournalCore
import SwiftUI

extension NativeEditor.Coordinator {
    func configureTables() {
        guard let view else { return }
        view.receiveMarkdown = { [weak self] value in self?.pasteMarkdown(value) }
        view.receiveFragment = { [weak self] fragment in self?.paste(fragment) }
        view.selectionMarkdown = { [weak self] range in self?.markdown(for: range) }
        #if os(iOS)
            view.showsSource = { [weak self] in self?.showsSource ?? false }
            view.copySelectedImage = { [weak self, weak view] image in
                let markdown = view?.selectionMarkdown?(NSRange(location: image.index, length: 1))
                return self?.copySelected(image, markdown: markdown) ?? false
            }
            view.leavingWindow = { [weak self] in self?.dismissImagePresentations() }
            view.enteringBackground = { [weak self] in self?.dismissImageMenu() }
        #endif
        #if os(macOS)
            configurePictures(view)
            view.textStorage?.delegate = self
        #else
            view.textStorage.delegate = self
        #endif
        if taskControls == nil {
            taskControls = InlineTasks(host: view) { [weak self, weak view] range in
                guard let self, let view else { return }
                #if os(macOS)
                    let previous = view.selectedRange()
                    view.setSelectedRange(range)
                    self.performStructuralKey(.toggleTask)
                    view.setSelectedRange(previous)
                #else
                    let previous = view.selectedRange
                    view.selectedRange = range
                    self.performStructuralKey(.toggleTask)
                    view.selectedRange = previous
                #endif
            }
        }
        parent.actions.toggleSource = { [weak self] in self?.perform(.source) }
        #if os(macOS)
            parent.actions.tableAction = { [weak self] action in self?.tables?.active?.applyToActiveCell(action) }
        #endif
        if tables == nil {
            tables = InlineTables(host: view, actions: parent.actions) { [weak self] text, range, cell in
                self?.replace(text, range: range, typingIn: cell.map(AnyHashable.init))
            }
        }
        if lastID != parent.itemID { tables?.reset() }
    }
    func synchronizeTables() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.parent.actions.sourceMode != self.showsSource { self.parent.actions.sourceMode = self.showsSource }
            self.applySubstitutions()
        }
        taskControls?.synchronize(editable: parent.editable)
        #if os(iOS)
            synchronizePictureElements()
        #else
            synchronizePictureCells()
        #endif
        tables?.synchronize(size: parent.fontSize, editable: parent.editable, images: parent.images)
    }
    /// Code must stay exactly as typed: in source view and inside code blocks or inline code, smart dashes and
    /// quotes, autocorrection, capitalization and spelling marks are off. Prose follows the person's own settings: on
    /// the Mac, the choices in Edit ▸ Substitutions and Spelling are put back when the caret leaves code.
    func applySubstitutions() {
        guard let view else { return }
        #if os(macOS)
            let text = view.textStorage ?? NSTextStorage()
            let selection = view.selectedRange()
        #else
            let text = view.textStorage
            let selection = view.selectedRange
        #endif
        let literal = showsSource || Self.isCode(text, at: selection.location, typing: view.typingAttributes)
        #if os(macOS)
            if literal {
                if proseChecking == nil { proseChecking = TextChecking(view) }
                TextChecking.literal.apply(to: view)
            } else if let proseChecking {
                proseChecking.apply(to: view)
                self.proseChecking = nil
            }
        #else
            let traits:
                (
                    UITextSmartDashesType, UITextSmartQuotesType, UITextAutocorrectionType,
                    UITextAutocapitalizationType, UITextSpellCheckingType
                ) =
                    literal ? (.no, .no, .no, .none, .no) : (.default, .default, .default, .sentences, .default)
            guard
                view.smartDashesType != traits.0 || view.smartQuotesType != traits.1
                    || view.autocorrectionType != traits.2 || view.autocapitalizationType != traits.3
                    || view.spellCheckingType != traits.4
            else { return }
            view.smartDashesType = traits.0
            view.smartQuotesType = traits.1
            view.autocorrectionType = traits.2
            view.autocapitalizationType = traits.3
            view.spellCheckingType = traits.4
            if view.isFirstResponder { view.reloadInputViews() }
        #endif
    }
    /// Keeps Format ▸ Mark as Checked/Unchecked in step with the line the caret is on.
    func updateCaretState() {
        guard let view else { return }
        #if os(macOS)
            let text = view.textStorage ?? NSTextStorage()
            let location = view.selectedRange().location
        #else
            let text = view.textStorage
            let location = view.selectedRange.location
        #endif
        var checked: Bool?
        if text.length > 0, !editingSource {
            let line = (text.string as NSString).paragraphRange(
                for: NSRange(location: min(location, text.length), length: 0))
            switch text.attribute(.journalKind, at: min(line.location, text.length - 1), effectiveRange: nil) as? String
            {
            case "task": checked = false
            case "checked": checked = true
            default: checked = nil
            }
        }
        if parent.actions.caretTaskChecked != checked { parent.actions.caretTaskChecked = checked }
    }
    private static func isCode(_ text: NSAttributedString, at location: Int, typing: [NSAttributedString.Key: Any])
        -> Bool
    {
        if (typing[.journalCode] as? Int ?? 0) != 0 { return true }
        guard text.length > 0 else { return false }
        let index = min(max(0, location - 1), text.length - 1)
        let kind = text.attribute(.journalKind, at: min(location, text.length - 1), effectiveRange: nil) as? String
        return ["codeBlock", "html"].contains(kind ?? "")
            || (text.attribute(.journalCode, at: index, effectiveRange: nil) as? Int ?? 0) != 0
    }
    /// Whether the editor currently shows Markdown source, including an empty entry started in source.
    var editingSource: Bool { showsSource }
    /// How rendered blocks lay out their images in this editor.
    var imageLayout: RichText.ImageLayout {
        guard let view else { return RichText.ImageLayout(loading: parent.loadingImages, thumbnails: thumbnails) }
        #if os(macOS)
            let scale = view.window?.backingScaleFactor ?? 2
        #else
            let scale = view.traitCollection.displayScale > 0 ? view.traitCollection.displayScale : 2
        #endif
        return RichText.ImageLayout(
            width: max(40, view.bounds.width - 20), loading: parent.loadingImages,
            placeholderColor: ImagePresentation.placeholderColor(in: view), scale: scale, thumbnails: thumbnails)
    }
    func applyMarkdownEdit(_ command: EditorCommand) -> Bool {
        if !editingSource {
            if case .toggleTask = command { return performStructuralKey(.toggleTask) }
            if case .indent = command { return performStructuralKey(.indent) }
            if case .outdent = command { return performStructuralKey(.outdent) }
        }
        guard let view else { return false }
        #if os(macOS)
            guard let storage = view.textStorage else { return false }
            let selection = view.selectedRange()
        #else
            let storage = view.textStorage
            let selection = view.selectedRange
        #endif
        let wasSource = showsSource
        guard
            let edit = MarkdownEditing.edit(
                command, text: storage, selection: selection,
                document: parent.document, size: parent.fontSize, images: parent.images, source: wasSource,
                layout: imageLayout)
        else { return false }
        let changingMode: Bool
        if case .source = command { changingMode = true } else { changingMode = false }
        let viewportOffset = changingMode ? caretViewportOffset() : nil
        #if os(iOS)
            let wasEditing = parent.actions.editing
        #endif
        let remainsSource = changingMode ? !wasSource : wasSource
        if edit.text.length > 0 || edit.range.length > 0 {
            replace(
                edit.text, range: edit.range,
                actionName: changingMode ? (wasSource ? "View Preview" : "View Source") : nil,
                showingSource: remainsSource)
        }
        showsSource = remainsSource
        #if os(macOS)
            if let range = edit.selection { view.setSelectedRange(range) }
            let location = view.selectedRange().location
        #else
            if let range = edit.selection { view.selectedRange = range }
            let location = view.selectedRange.location
        #endif
        view.typingAttributes =
            remainsSource
            ? MarkdownEditing.attributes(size: parent.fontSize)
            : (location < storage.length
                ? storage.attributes(at: location, effectiveRange: nil)
                : RichText.attributes(kind: "paragraph", size: parent.fontSize))
        parent.actions.sourceMode = remainsSource
        #if os(macOS)
            view.window?.makeFirstResponder(view)
        #else
            if !changingMode || wasEditing { view.becomeFirstResponder() }
        #endif
        if changingMode {
            restoreCaretViewportOffset(viewportOffset)
            announceMode(source: remainsSource)
        }
        if case .insert = command { tables?.focus(at: NSRange(location: location, length: 0)) }
        return true
    }

}

extension NativeEditor.Coordinator {
    /// The entry's Markdown for a selection. Text within one paragraph is copied as text, so it joins the paragraph it
    /// is pasted into rather than bringing its own paragraph style along.
    func markdown(for range: NSRange) -> String? {
        guard let view, range.length > 0 else { return nil }
        #if os(macOS)
            guard let storage = view.textStorage else { return nil }
        #else
            let storage = view.textStorage
        #endif
        guard NSMaxRange(range) <= storage.length else { return nil }
        if showsSource { return (storage.string as NSString).substring(with: range) }
        let selected = storage.attributedSubstring(from: range)
        var document = RichText.document(selected)
        if selected.string.contains("\n") {
            // A line copied from inside it is text, not a list item or quote: its formatting belongs to its start.
            let source = storage.string as NSString
            if source.paragraphRange(for: NSRange(location: range.location, length: 0)).location != range.location,
                let first = document.blocks.first, ListMarkers.itemKinds.contains(first.kind)
            {
                document.blocks[0] = RichText.restyling(.init(blocks: [first]), kind: "paragraph").blocks[0]
            }
            return document.markdown
        }
        return RichText.restyling(document, kind: "paragraph").markdown.trimmingCharacters(in: .newlines)
    }

    func pasteMarkdown(_ value: String) {
        guard let view, parent.editable else { return }
        #if os(macOS)
            guard !view.hasMarkedText(), let storage = view.textStorage else { return }
            let selection = view.selectedRange()
        #else
            guard view.markedTextRange == nil else { return }
            let storage = view.textStorage
            let selection = view.selectedRange
        #endif
        guard !showsSource else {
            replace(MarkdownEditing.render(value, size: parent.fontSize), range: selection)
            return
        }
        let fragment = JournalDocument(markdown: value)
        let text = NSMutableAttributedString(
            attributedString: RichText.render(
                fragment, size: parent.fontSize, images: parent.images, layout: imageLayout, endsText: false))
        let lineStart =
            selection.location == 0 || (storage.string as NSString).character(at: selection.location - 1) == 0x0A
        let inline = !value.hasSuffix("\n") && fragment.blocks.count == 1 && fragment.blocks[0].kind == "paragraph"
        // Text pasted within a paragraph becomes part of it, as its first line of pasted text does in any editor.
        if !lineStart || inline { RichText.joinParagraph(text) }
        replace(text, range: selection, adopting: true)
    }
}

#if os(macOS)
    import AppKit

    /// The text checking a text view does as the person types, as set in Edit ▸ Substitutions and Spelling.
    @MainActor struct TextChecking {
        var dashes: Bool
        var quotes: Bool
        var correction: Bool
        var replacement: Bool
        var spelling: Bool

        /// Code and Markdown source are checked for nothing, so they stay exactly as typed.
        static let literal = TextChecking(
            dashes: false, quotes: false, correction: false, replacement: false, spelling: false)

        init(dashes: Bool, quotes: Bool, correction: Bool, replacement: Bool, spelling: Bool) {
            self.dashes = dashes
            self.quotes = quotes
            self.correction = correction
            self.replacement = replacement
            self.spelling = spelling
        }

        init(_ view: NSTextView) {
            dashes = view.isAutomaticDashSubstitutionEnabled
            quotes = view.isAutomaticQuoteSubstitutionEnabled
            correction = view.isAutomaticSpellingCorrectionEnabled
            replacement = view.isAutomaticTextReplacementEnabled
            spelling = view.isContinuousSpellCheckingEnabled
        }

        func apply(to view: NSTextView) {
            if view.isAutomaticDashSubstitutionEnabled != dashes { view.isAutomaticDashSubstitutionEnabled = dashes }
            if view.isAutomaticQuoteSubstitutionEnabled != quotes { view.isAutomaticQuoteSubstitutionEnabled = quotes }
            if view.isAutomaticSpellingCorrectionEnabled != correction {
                view.isAutomaticSpellingCorrectionEnabled = correction
            }
            if view.isAutomaticTextReplacementEnabled != replacement {
                view.isAutomaticTextReplacementEnabled = replacement
            }
            if view.isContinuousSpellCheckingEnabled != spelling { view.isContinuousSpellCheckingEnabled = spelling }
        }
    }
#endif
