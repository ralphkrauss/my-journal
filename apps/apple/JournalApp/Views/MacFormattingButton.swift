#if os(macOS)
    import AppKit
    import SwiftUI

    /// A popover shown from a button, such as Formatting in the toolbar or “Use a Template…” in a new entry, as Notes
    /// shows its Aa popover: at once, without animation. A click anywhere outside closes it, and so do Escape and a second click on its button, which
    /// never opens it again.
    @MainActor
    final class ToolbarPopover: NSObject, NSPopoverDelegate {
        enum CloseReason {
            /// Escape, the button again, or a choice in the popover that finishes it.
            case dismissed
            /// A click elsewhere, which puts focus where the person clicked.
            case outside
            /// The entry changed, editing became unavailable or the window closed.
            case programmatic
        }
        enum InitialFocus {
            /// The first control, when opened from the keyboard or with VoiceOver.
            case firstControl
            /// The search field, whichever way it was opened.
            case searchField
        }

        let button = PopoverButton()
        private let popover = NSPopover()
        private let initialFocus: InitialFocus
        private var clickGuard = PopoverClickGuard()
        private var reason: CloseReason?
        private var openedFromKeyboard = false
        /// Called once the popover has closed.
        var didClose: ((CloseReason) -> Void)?

        var isShown: Bool { popover.isShown }

        init(title: String, symbol: String, initialFocus: InitialFocus) {
            self.initialFocus = initialFocus
            super.init()
            button.bezelStyle = .toolbar
            button.setButtonType(.momentaryPushIn)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imagePosition = .imageOnly
            button.toolTip = title
            button.setAccessibilityLabel(title)
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            button.pressed = { [weak self] event in self?.clickGuard.buttonPressed(Self.click(event)) }
            button.released = { [weak self] in self?.clickGuard.buttonReleased() }
        }

        /// The button's action: closes the popover when it's shown, otherwise shows the content `prepare` returns
        /// (nothing when it returns nil). A click whose mouse-down already closed the popover does nothing.
        /// Without a toolbar item, the popover points at its button, wherever that is shown.
        func toggle(from item: NSToolbarItem? = nil, prepare: () -> NSViewController?) {
            let clicked = clickGuard.actionIsClick
            guard clickGuard.actionShouldToggle() else { return }
            if popover.isShown {
                close(.dismissed)
                return
            }
            guard let content = prepare() else { return }
            if popover.contentViewController !== content { popover.contentViewController = content }
            // Opened with the mouse, the text keeps focus; otherwise, and always with VoiceOver, the popover takes it.
            openedFromKeyboard = NSWorkspace.shared.isVoiceOverEnabled || !clicked
            reason = nil
            if let item {
                popover.show(relativeTo: item)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: button.isFlipped ? .maxY : .minY)
            }
            if openedFromKeyboard || initialFocus == .searchField { focusContent() }
        }

        func close(_ reason: CloseReason = .programmatic) {
            guard popover.isShown else { return }
            self.reason = reason
            popover.close()
        }

        func popoverWillClose(_ notification: Notification) {
            guard notification.object as? NSPopover === popover else { return }
            let event = NSApp.currentEvent
            let mouseDown = event.flatMap { $0.type == .leftMouseDown ? $0 : nil }
            clickGuard.popoverClosed(by: mouseDown.map(Self.click))
            if reason == nil {
                // Closed by AppKit: a click outside it, or Escape. A click on its own button is sorted out by the
                // button's action, which then leaves it closed.
                reason = event?.type == .keyDown ? .dismissed : .outside
            }
        }

        func popoverDidClose(_ notification: Notification) {
            guard notification.object as? NSPopover === popover else { return }
            let reason = self.reason ?? .programmatic
            self.reason = nil
            if reason == .dismissed, openedFromKeyboard, let window = button.window {
                // Back to the button it was opened from; opened with the mouse, the text kept focus throughout.
                window.makeFirstResponder(button)
                NSAccessibility.post(element: button, notification: .focusedUIElementChanged)
            }
            didClose?(reason)
        }

        private func focusContent() {
            guard let view = popover.contentViewController?.view, let window = view.window else { return }
            window.makeKey()
            switch initialFocus {
            case .searchField:
                if let field = Self.searchField(in: view) { window.makeFirstResponder(field) }
            case .firstControl:
                window.makeFirstResponder(nil)
                window.selectNextKeyView(nil)
            }
            let focused = window.firstResponder ?? view
            NSAccessibility.post(element: focused, notification: .focusedUIElementChanged)
        }

        private static func click(_ event: NSEvent) -> PopoverClickGuard.Click {
            PopoverClickGuard.Click(number: event.eventNumber, timestamp: event.timestamp)
        }

        private static func searchField(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            for subview in view.subviews {
                if let field = searchField(in: subview) { return field }
            }
            return nil
        }
    }

    /// A toolbar button that reports its own mouse-down, so its popover can tell a second click on it from a click
    /// elsewhere without comparing positions.
    final class PopoverButton: NSButton {
        var pressed: ((NSEvent) -> Void)?
        var released: (() -> Void)?
        override func mouseDown(with event: NSEvent) {
            // A disabled button sends no action for this click.
            if isEnabled { pressed?(event) }
            // Tracks the mouse until it's released, sending the action if that happens on the button.
            super.mouseDown(with: event)
            released?()
        }
    }
#endif
