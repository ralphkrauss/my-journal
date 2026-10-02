#if os(macOS)
    import AppKit

    /// The toolbar's search field, which reports focus the person gives it, by clicking it or with Tab.
    final class FocusReportingSearchField: NSSearchField {
        var focused: @MainActor () -> Void = {}
        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            // Only focus the person gave, not focus a window places when it opens.
            let chosen = [.leftMouseDown, .keyDown].contains(NSApp.currentEvent?.type)
            // Focus can change during a view update, which must not change state.
            if became, chosen { DispatchQueue.main.async { [focused] in focused() } }
            return became
        }
    }
#endif
