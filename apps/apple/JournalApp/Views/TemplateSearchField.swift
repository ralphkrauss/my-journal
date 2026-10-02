import SwiftUI

#if os(macOS)
    import AppKit

    struct TemplateSearchField: NSViewRepresentable {
        @Binding var text: String
        let move: (Int) -> Void
        let submit: () -> Void
        /// Escape. It reaches the field only after an input method has finished composing.
        let cancel: () -> Void
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        func makeNSView(context: Context) -> SearchField {
            let field = SearchField()
            field.placeholderString = "Search Templates"
            field.setAccessibilityLabel("Search Templates")
            field.delegate = context.coordinator
            field.target = context.coordinator
            field.action = #selector(Coordinator.submitSearch)
            return field
        }
        func updateNSView(_ field: SearchField, context: Context) {
            context.coordinator.parent = self
            // Cleared when a reused chooser starts afresh, also while the field still has focus.
            if field.stringValue != text, field.currentEditor() == nil || text.isEmpty { field.stringValue = text }
            field.updatePlaceholder()
        }
        final class SearchField: NSSearchField {
            private var focusedOnce = false
            func updatePlaceholder() {
                let value = currentEditor()?.string ?? stringValue
                placeholderString = value.isEmpty ? "Search Templates" : nil
                needsDisplay = true
            }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard let window, !focusedOnce else { return }
                focusedOnce = true
                window.makeFirstResponder(self)
            }
        }
        @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
            var parent: TemplateSearchField
            init(_ parent: TemplateSearchField) { self.parent = parent }
            func controlTextDidChange(_ notification: Notification) {
                if let field = notification.object as? SearchField {
                    field.updatePlaceholder()
                    parent.text = field.stringValue
                }
            }
            @objc func submitSearch() { parent.submit() }
            func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
                guard !textView.hasMarkedText() else { return false }
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    parent.move(1)
                    return true
                }
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    parent.move(-1)
                    return true
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    parent.submit()
                    return true
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    parent.cancel()
                    return true
                }
                return false
            }
        }
    }
#else
    import UIKit

    struct TemplateSearchField: UIViewRepresentable {
        @Binding var text: String
        let move: (Int) -> Void
        let submit: () -> Void
        /// Escape on a hardware keyboard, unless an input method is composing.
        let cancel: () -> Void
        func makeCoordinator() -> Coordinator { Coordinator(self) }
        func makeUIView(context: Context) -> SearchBar {
            let bar = SearchBar()
            bar.placeholder = "Search Templates"
            bar.searchBarStyle = .minimal
            bar.delegate = context.coordinator
            bar.move = move
            bar.cancel = cancel
            bar.searchTextField.font = .preferredFont(forTextStyle: .body)
            bar.searchTextField.adjustsFontForContentSizeCategory = true
            // As search fields in navigation bars: larger text still grows the field, but it leaves room for results
            // beside the keyboard, also on a small iPhone in landscape.
            bar.maximumContentSizeCategory = .accessibilityMedium
            bar.searchTextField.autocorrectionType = .no
            bar.searchTextField.autocapitalizationType = .none
            // Return creates the highlighted template, also before anything is typed.
            bar.searchTextField.enablesReturnKeyAutomatically = false
            return bar
        }
        func updateUIView(_ bar: SearchBar, context: Context) {
            context.coordinator.parent = self
            bar.move = move
            bar.cancel = cancel
        }
        final class SearchBar: UISearchBar {
            var move: ((Int) -> Void)?
            var cancel: (() -> Void)?
            private var focusedOnce = false
            override func didMoveToWindow() {
                super.didMoveToWindow()
                guard window != nil, !focusedOnce else { return }
                focusedOnce = true
                becomeFirstResponder()
            }
            override var keyCommands: [UIKeyCommand]? {
                let commands = [
                    UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(moveDown)),
                    UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(moveUp)),
                    UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape)),
                ]
                // The search field would otherwise take these keys for itself.
                for command in commands { command.wantsPriorityOverSystemBehavior = true }
                return commands
            }
            @objc private func escape() { if searchTextField.markedTextRange == nil { cancel?() } }
            @objc private func moveDown() { if searchTextField.markedTextRange == nil { move?(1) } }
            @objc private func moveUp() { if searchTextField.markedTextRange == nil { move?(-1) } }
        }
        @MainActor final class Coordinator: NSObject, UISearchBarDelegate {
            var parent: TemplateSearchField
            init(_ parent: TemplateSearchField) { self.parent = parent }
            func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { parent.text = searchText }
            func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { parent.submit() }
        }
    }
#endif
