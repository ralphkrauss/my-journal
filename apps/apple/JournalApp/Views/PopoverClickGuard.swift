import Foundation

/// Decides whether a toolbar button's action belongs to the click that has just closed its popover.
///
/// A popover that closes when the person clicks outside it closes on the mouse-down, before the button sends its
/// action on the mouse-up. Without this, a second click on the button closed the popover and then opened it again.
struct PopoverClickGuard {
    /// A mouse-down, identified by AppKit's event number and timestamp.
    struct Click: Equatable {
        var number: Int
        var timestamp: TimeInterval
    }

    private var closingClick: Click?
    private var buttonClick: Click?

    /// The popover closed during `mouseDown`, or for another reason (Escape, a choice in it) when nil.
    mutating func popoverClosed(by mouseDown: Click?) {
        closingClick = mouseDown
    }

    /// The button itself received `mouseDown`; its action follows on the mouse-up.
    mutating func buttonPressed(_ mouseDown: Click) {
        buttonClick = mouseDown
    }

    /// The button's mouse tracking has ended. Its action, if any, has been decided by then; a press that sent none,
    /// on a disabled button or released after dragging off it, must not count for a later keyboard activation.
    mutating func buttonReleased() {
        closingClick = nil
        buttonClick = nil
    }

    /// Whether the action comes from a click on the button, rather than the keyboard, a menu or VoiceOver.
    var actionIsClick: Bool { buttonClick != nil }

    /// Whether the button's action should open or close the popover: not when the popover closed on the mouse-down
    /// of this very click. A click elsewhere that closed it, followed quickly by a click on the button, still opens it;
    /// keyboard, menu and VoiceOver activation always toggle. Each click is decided once.
    mutating func actionShouldToggle() -> Bool {
        defer {
            closingClick = nil
            buttonClick = nil
        }
        guard let closingClick, let buttonClick else { return true }
        // The same mouse-down event: AppKit hands the popover and the button the same event.
        return closingClick != buttonClick
    }
}
