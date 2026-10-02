import XCTest

@testable import Journal

/// A second click on Formatting or Use a Template… closes the popover on its mouse-down; the action that follows on the
/// mouse-up must not open it again. Other clicks and keyboard activation must still toggle it.
final class PopoverClickGuardTests: XCTestCase {
    func testTheClickThatClosedThePopoverDoesNotReopenIt() {
        var clickGuard = PopoverClickGuard()
        let click = PopoverClickGuard.Click(number: 41, timestamp: 100)
        clickGuard.popoverClosed(by: click)
        clickGuard.buttonPressed(click)
        XCTAssertFalse(clickGuard.actionShouldToggle())
    }

    func testClickingElsewhereThenQuicklyOnTheButtonOpensThePopover() {
        var clickGuard = PopoverClickGuard()
        // The click in the text closed the popover; the next click, on the button, is another one.
        clickGuard.popoverClosed(by: .init(number: 41, timestamp: 100))
        clickGuard.buttonPressed(.init(number: 42, timestamp: 100.15))
        XCTAssertTrue(clickGuard.actionShouldToggle())
    }

    func testKeyboardAndVoiceOverActivationToggle() {
        var clickGuard = PopoverClickGuard()
        // Escape or a choice closed it; Space with Full Keyboard Access, or VoiceOver's press, has no mouse-down.
        clickGuard.popoverClosed(by: nil)
        XCTAssertFalse(clickGuard.actionIsClick)
        XCTAssertTrue(clickGuard.actionShouldToggle())
        clickGuard.popoverClosed(by: .init(number: 41, timestamp: 100))
        XCTAssertTrue(clickGuard.actionShouldToggle())
    }

    func testEachClickIsDecidedOnce() {
        var clickGuard = PopoverClickGuard()
        let click = PopoverClickGuard.Click(number: 41, timestamp: 100)
        clickGuard.popoverClosed(by: click)
        clickGuard.buttonPressed(click)
        XCTAssertFalse(clickGuard.actionShouldToggle())
        // The next click on the button opens it again.
        clickGuard.buttonPressed(.init(number: 57, timestamp: 103))
        XCTAssertTrue(clickGuard.actionShouldToggle())
    }

    /// A click on the disabled button (a read-only entry) sends no action; opening it later from the keyboard must
    /// still move focus into the popover, as keyboard activation does.
    func testAClickThatSentNoActionDoesNotCountForTheKeyboard() {
        var clickGuard = PopoverClickGuard()
        clickGuard.buttonPressed(.init(number: 41, timestamp: 100))
        clickGuard.buttonReleased()
        XCTAssertFalse(clickGuard.actionIsClick)
        XCTAssertTrue(clickGuard.actionShouldToggle())
    }

    /// Pressing the button closes the popover; dragging off before releasing sends no action. The next keyboard
    /// activation opens it at once rather than being taken for that click.
    func testDraggingOffTheButtonLeavesTheNextActivationToToggle() {
        var clickGuard = PopoverClickGuard()
        let click = PopoverClickGuard.Click(number: 41, timestamp: 100)
        clickGuard.popoverClosed(by: click)
        clickGuard.buttonPressed(click)
        clickGuard.buttonReleased()
        XCTAssertFalse(clickGuard.actionIsClick)
        XCTAssertTrue(clickGuard.actionShouldToggle())
    }
}
