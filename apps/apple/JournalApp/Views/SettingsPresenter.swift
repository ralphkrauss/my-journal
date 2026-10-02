#if os(macOS)
    import AppKit
    import SwiftUI

    struct SettingsPresenter: View {
        @Binding var requested: Bool
        var body: some View {
            if #available(macOS 14, *) {
                ModernSettingsPresenter(requested: $requested)
            } else {
                Color.clear.frame(width: 0, height: 0).onValueChange(of: requested) { value in
                    if value {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        requested = false
                    }
                }
            }
        }
    }
    @available(macOS 14, *)
    private struct ModernSettingsPresenter: View {
        @Environment(\.openSettings) private var openSettings
        @Binding var requested: Bool
        var body: some View {
            Color.clear.frame(width: 0, height: 0).onValueChange(of: requested) { value in
                if value {
                    openSettings()
                    requested = false
                }
            }
        }
    }
#endif
