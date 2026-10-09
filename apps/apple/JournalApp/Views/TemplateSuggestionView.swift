import JournalCore
import SwiftUI

/// The button over the link “[template symbol] use a template” in the empty body's placeholder, which the editor
/// draws as text (PlaceholderText). It opens the template chooser, and a choice fills the body in place
/// (docs/design/new-entry-template-suggestion.md). VoiceOver reads it as “Use a Template”.
struct TemplateSuggestionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        #if os(macOS)
            MacTemplateSuggestionButton(model: model)
        #else
            TemplateSuggestionButton()
        #endif
    }
}

#if os(iOS)
    /// The chooser is a popover in a regular-width window and a sheet otherwise, decided when it opens; it belongs
    /// to this window alone.
    private struct TemplateSuggestionButton: View {
        private enum Presentation { case popover, sheet }
        @EnvironmentObject private var model: AppModel
        @Environment(\.horizontalSizeClass) private var sizeClass
        @State private var presentation: Presentation?

        var body: some View {
            Button {
                present(sizeClass == .regular ? .popover : .sheet)
            } label: {
                // The link's text is drawn by the placeholder below; this covers its glyphs.
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use a Template")
            .hoverEffect(.automatic)
            .popover(isPresented: isPresented(.popover)) { chooser(anchored: true) }
            .sheet(isPresented: isPresented(.sheet)) {
                chooser(anchored: false).presentationDetents([.medium, .large])
            }
            // A popover doesn't become a sheet: it closes, and nothing is applied.
            .onValueChange(of: sizeClass) { _ in present(nil) }
        }

        private func isPresented(_ kind: Presentation) -> Binding<Bool> {
            Binding(get: { presentation == kind }, set: { if !$0, presentation == kind { present(nil) } })
        }

        /// Writing-time panels open and close at once, without the presentation's animation.
        private func present(_ kind: Presentation?) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { presentation = kind }
        }

        private func chooser(anchored: Bool) -> some View {
            TemplateChooserView(entryID: model.draft?.id, anchored: anchored).environmentObject(model)
        }
    }

#else
    import AppKit

    /// An AppKit button with the toolbar's popover: shown and closed without animation, with focus handled as the
    /// Formatting and former Templates… popovers do (menus-and-popovers.md D1).
    private struct MacTemplateSuggestionButton: NSViewRepresentable {
        let model: AppModel

        func makeCoordinator() -> Coordinator { Coordinator(model: model) }

        func makeNSView(context: Context) -> PopoverButton {
            let button = context.coordinator.popover.button
            // The link's text is drawn by the placeholder below; the button covers its glyphs.
            button.isTransparent = true
            button.toolTip = nil
            button.setAccessibilityLabel("Use a Template")
            return button
        }

        func updateNSView(_ button: PopoverButton, context: Context) {
            context.coordinator.model = model
        }

        static func dismantleNSView(_ button: PopoverButton, coordinator: Coordinator) {
            coordinator.popover.close()
        }

        @MainActor final class Coordinator: NSObject {
            var model: AppModel
            let popover = ToolbarPopover(title: "Use a Template…", symbol: "doc.on.doc", initialFocus: .searchField)
            private let presentation = TemplateChooserPresentation()
            private var content: NSViewController?
            private var draftWhenOpened: JournalItem?

            init(model: AppModel) {
                self.model = model
                super.init()
                popover.button.target = self
                popover.button.action = #selector(choose)
                // Opens afresh next time: no previous search, highlight or error.
                popover.didClose = { [weak self] _ in self?.presentation.reset() }
            }

            @objc private func choose() {
                popover.toggle {
                    presentation.entryID = model.draft?.id
                    draftWhenOpened = model.draft
                    if let content { return content }
                    let close: () -> Void = { [weak self] in self?.close() }
                    let host = NSHostingController(
                        rootView: AnyView(
                            TemplateChooserView(
                                entryID: nil, anchored: true, close: close, presentation: presentation
                            )
                            .environmentObject(model)))
                    host.sceneBridgingOptions = []
                    host.sizingOptions = .preferredContentSize
                    content = host
                    return host
                }
            }

            /// After a choice the entry's title takes focus; after Escape or Cancel focus returns the way it came.
            private func close() {
                let chosen = model.draft != draftWhenOpened
                popover.close(chosen ? .programmatic : .dismissed)
            }
        }
    }
#endif
