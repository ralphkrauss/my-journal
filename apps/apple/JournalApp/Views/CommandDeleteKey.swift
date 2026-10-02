import SwiftUI

#if os(macOS)
    /// ⌘⌫ in the focused entries list, like Delete; the text editor keeps ⌘⌫ for deleting to the line start.
    struct CommandDeleteKey: ViewModifier {
        let action: () -> Void
        func body(content: Content) -> some View {
            if #available(macOS 14.0, *) {
                content.onKeyPress(.delete, phases: .down) { press in
                    guard press.modifiers == .command else { return .ignored }
                    action()
                    return .handled
                }
            } else {
                content
            }
        }
    }
#endif
