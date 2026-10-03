#if os(iOS)
    import SwiftUI
    import UIKit

    struct EntryTitleEditor: UIViewRepresentable {
        @EnvironmentObject private var actions: EditorActions
        @Binding var text: String
        var initialFocus: InitialTitleFocus?
        let submit: () -> Void

        func makeUIView(context: Context) -> TitleTextView {
            let view = TitleTextView()
            view.delegate = context.coordinator
            view.pasteDelegate = view
            view.backgroundColor = .clear
            view.isScrollEnabled = false
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            view.returnKeyType = .next
            view.accessibilityLabel = "Title"
            view.accessibilityIdentifier = "Entry title"
            view.adjustsFontForContentSizeCategory = true
            return view
        }
        func updateUIView(_ view: TitleTextView, context: Context) {
            context.coordinator.parent = self
            let font = UIFont.preferredFont(forTextStyle: .title1)
            view.font =
                font.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? font
            view.textColor = .label
            if view.text != text { view.text = text }
            view.editorActions = actions
            view.initialFocus = initialFocus
            view.applyInitialFocus()
        }
        static func dismantleUIView(_ view: TitleTextView, coordinator: Coordinator) {
            // Possibly during a view update: forgetting publishes the end of editing after it, the delegate wouldn't.
            view.delegate = nil
            view.endFocusBeforeRemoval()
            view.editorActions?.forget(view)
        }
        func sizeThatFits(_ proposal: ProposedViewSize, uiView: TitleTextView, context: Context) -> CGSize? {
            guard let width = proposal.width else { return nil }
            let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: fitting.height)
        }
        func makeCoordinator() -> Coordinator { Coordinator(self) }

        @MainActor final class Coordinator: NSObject, UITextViewDelegate {
            var parent: EntryTitleEditor
            init(_ parent: EntryTitleEditor) { self.parent = parent }
            func textViewDidChange(_ textView: UITextView) {
                (textView as? TitleTextView)?.updatePlaceholder()
                parent.text = textView.text
                (textView as? TitleTextView)?.revealInsertion()
            }
            func textViewDidEndEditing(_ textView: UITextView) { parent.actions.setEditing(false, by: textView) }
            func textViewDidBeginEditing(_ textView: UITextView) {
                parent.actions.setEditing(true, by: textView)
                (textView as? TitleTextView)?.revealInsertion()
            }
            func textViewDidChangeSelection(_ textView: UITextView) {
                (textView as? TitleTextView)?.revealInsertion()
            }
            func textView(
                _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
            ) -> Bool {
                // Tab from a hardware keyboard moves on to the text, as Return does; a title never holds a tab.
                if text == "\n" || text == "\t", textView.markedTextRange == nil,
                    let titleView = textView as? TitleTextView, !titleView.isPasting
                {
                    parent.submit()
                    return false
                }
                return true
            }
        }
    }

    final class TitleTextView: UITextView, UITextPasteDelegate {
        var initialFocus: InitialTitleFocus? {
            didSet { if oldValue !== initialFocus { focusRetries = 0 } }
        }
        /// Drawn by the view itself, so it disappears with the first keystroke rather than after SwiftUI updates.
        private let placeholder = UILabel()
        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            placeholder.text = "Title"
            placeholder.textColor = .tertiaryLabel
            placeholder.adjustsFontForContentSizeCategory = true
            placeholder.isAccessibilityElement = false
            placeholder.translatesAutoresizingMaskIntoConstraints = false
            addSubview(placeholder)
            NSLayoutConstraint.activate([
                placeholder.leadingAnchor.constraint(equalTo: leadingAnchor),
                placeholder.topAnchor.constraint(equalTo: topAnchor),
            ])
        }
        required init?(coder: NSCoder) { nil }
        override var text: String! { didSet { updatePlaceholder() } }
        override var font: UIFont? { didSet { placeholder.font = font } }
        func updatePlaceholder() { placeholder.isHidden = !text.isEmpty }
        /// Ends the title's part in editing when it leaves the screen, which may not report the end of editing.
        weak var editorActions: EditorActions?
        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow == nil { editorActions?.forget(self) }
            super.willMove(toWindow: newWindow)
        }
        /// Going Back removes the title before the rest of its entry. UIKit would hand the keyboard of a focused title
        /// to the enclosing body as it goes, and the body, leaving the screen focused, would take it for interrupted
        /// writing and continue writing when the entry is opened again: the checkmark and keyboard return
        /// (docs/design/sync-now-and-done.md). The title gives the keyboard up first, with the body declining it.
        func endFocusBeforeRemoval() {
            guard isFirstResponder, let editorActions else { return }
            editorActions.whileEndingEditing { resignFirstResponder() }
        }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { editorActions?.forgetDeparted() }
            applyInitialFocus()
        }
        func applyInitialFocus() {
            guard window != nil, let initialFocus else { return }
            if isCoveredByPresentation {
                // A sheet that closes without animation still covers the title for a moment, and would take focus
                // back as it goes: focus once it has gone.
                retryInitialFocus()
                return
            }
            guard initialFocus.consume(when: { becomeFirstResponder() }) else { return }
            selectedRange = NSRange(location: 0, length: text.utf16.count)
        }
        private var isCoveredByPresentation: Bool {
            window?.rootViewController?.presentedViewController != nil
        }
        private var focusRetries = 0
        private var focusRetryPending = false
        /// Tries again shortly, for up to two seconds; a sheet that stays open keeps the title unfocused.
        private func retryInitialFocus() {
            guard !focusRetryPending, focusRetries < 40 else { return }
            focusRetryPending = true
            focusRetries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.focusRetryPending = false
                self.applyInitialFocus()
            }
        }
        private(set) var isPasting = false
        func revealInsertion() {
            guard isFirstResponder, let range = selectedTextRange else { return }
            var ancestor = superview
            while let current = ancestor {
                if let journal = current as? JournalTextView {
                    journal.containerInteractionBegan?()
                    let caret = convert(caretRect(for: range.end), to: journal)
                    journal.scrollRectToVisible(caret.insetBy(dx: 0, dy: -8), animated: false)
                    return
                }
                ancestor = current.superview
            }
        }
        func textPasteConfigurationSupporting(
            _ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting,
            performPasteOf attributedString: NSAttributedString, to textRange: UITextRange
        ) -> UITextRange {
            isPasting = true
            defer { isPasting = false }
            let location = offset(from: beginningOfDocument, to: textRange.start)
            replace(textRange, withText: attributedString.string)
            guard let start = position(from: beginningOfDocument, offset: location),
                let end = position(from: start, offset: attributedString.string.utf16.count),
                let inserted = self.textRange(from: start, to: end)
            else { return textRange }
            return inserted
        }
    }
#else
    import SwiftUI
    import AppKit

    struct EntryTitleEditor: NSViewRepresentable {
        @Binding var text: String
        var initialFocus: InitialTitleFocus?
        let submit: () -> Void
        func makeNSView(context: Context) -> TitleTextField {
            let view = TitleTextField()
            view.isBordered = false
            view.isBezeled = false
            view.drawsBackground = false
            view.focusRingType = .none
            view.placeholderString = "Title"
            view.font = .boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .title1).pointSize)
            // A long or pasted multiline title wraps and shows in full, as on iPhone and iPad.
            view.usesSingleLineMode = false
            view.maximumNumberOfLines = 0
            view.lineBreakMode = .byWordWrapping
            view.cell?.wraps = true
            view.cell?.isScrollable = false
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            view.delegate = context.coordinator
            view.target = context.coordinator
            view.action = #selector(Coordinator.submit)
            view.setAccessibilityLabel("Title")
            view.setAccessibilityIdentifier("Entry title")
            return view
        }
        func updateNSView(_ view: TitleTextField, context: Context) {
            context.coordinator.parent = self
            if view.stringValue != text { view.stringValue = text }
            view.initialFocus = initialFocus
            view.applyInitialFocus()
        }
        func sizeThatFits(_ proposal: ProposedViewSize, nsView: TitleTextField, context: Context) -> CGSize? {
            guard let width = proposal.width, width.isFinite else { return nil }
            return CGSize(width: width, height: nsView.fittingHeight(width: width))
        }
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
            var parent: EntryTitleEditor
            init(_ parent: EntryTitleEditor) { self.parent = parent }
            func controlTextDidChange(_ notification: Notification) {
                guard let view = notification.object as? NSTextField else { return }
                parent.text = view.stringValue
                view.invalidateIntrinsicContentSize()
            }
            @objc func submit() { parent.submit() }
        }
    }
    final class TitleTextField: NSTextField {
        var initialFocus: InitialTitleFocus?
        /// The height that shows the whole title at `width`, and at least one line for the placeholder.
        func fittingHeight(width: CGFloat) -> CGFloat {
            let measure = NSTextFieldCell(textCell: stringValue.isEmpty ? " " : stringValue)
            measure.font = font
            measure.wraps = true
            measure.lineBreakMode = .byWordWrapping
            measure.isBordered = false
            measure.isBezeled = false
            let bounds = NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
            return ceil(measure.cellSize(forBounds: bounds).height)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyInitialFocus()
        }
        func applyInitialFocus() {
            guard let window, let initialFocus, initialFocus.consume(when: { window.makeFirstResponder(self) }) else {
                return
            }
            selectText(nil)
        }
    }
#endif
