import SwiftUI

extension View {
    func iconHelp(_ text: String) -> some View {
        help(text)
            #if os(macOS)
                .background(ToolbarTooltip(text: text))
            #endif
    }
}

#if os(macOS)
    import AppKit

    private struct ToolbarTooltip: NSViewRepresentable {
        let text: String
        func makeNSView(context: Context) -> Anchor { Anchor() }
        func updateNSView(_ view: Anchor, context: Context) {
            view.text = text
            view.updateTooltip()
            DispatchQueue.main.async { [weak view] in view?.updateTooltip() }
        }
        final class Anchor: NSView {
            var text = ""
            override func hitTest(_ point: NSPoint) -> NSView? { nil }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                updateTooltip()
            }
            func updateTooltip() {
                toolTip = text
                for item in window?.toolbar?.items ?? [] {
                    let containsAnchor = item.view.map { isDescendant(of: $0) } ?? false
                    guard containsAnchor || item.label == text else { continue }
                    item.toolTip = text
                    item.view?.toolTip = text
                }
            }
        }
    }
#endif
