import UIKit
import UniformTypeIdentifiers
import XCTest

/// Pasting with the keyboard, as a person does: the pasted text lands where the caret was, the caret ends after it,
/// and Undo takes the paste back (docs/design/pasted-text.md).
final class PasteUITests: XCTestCase {
    /// A web page's heading and list become the entry's own, on the empty line they were pasted on.
    @MainActor func testPastedWebPageBecomesEntryBlocksAndUndoRemovesIt() throws {
        let (app, body) = newEntry(typing: "Packed bags\n")
        defer { app.terminate() }
        UIPasteboard.general.setItems([
            [
                UTType.html.identifier: Data(
                    ("<meta charset=\"utf-8\"><h2 style=\"font: 24px Georgia; color: #c00\">Day one</h2>"
                        + "<ul><li>Train</li><li>Hotel</li></ul>").utf8),
                UTType.utf8PlainText.identifier: "Day one\nTrain\nHotel",
            ]
        ])
        paste(into: body, app: app)
        XCTAssertTrue(wait(for: body, toContain: "Hotel"))
        app.typeText("s")
        let pasted = body.value as? String ?? ""
        XCTAssertTrue(pasted.hasPrefix("Packed bags\nDay one\n"), pasted)
        XCTAssertTrue(pasted.contains("Train\n"), pasted)
        // An entry that ends with a list item ends with that item's own line break (list-markers-2026-10-03.md).
        XCTAssertTrue(pasted.hasSuffix("Hotels\n"), "The caret is after the pasted text: \(pasted)")
        capture(app, "Web page pasted as a heading and a list")
        body.typeKey("z", modifierFlags: .command)
        body.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(wait(for: body, toEqual: "Packed bags\n"))
    }

    /// Words pasted within a paragraph join it, with the caret after them.
    @MainActor func testWordsPastedWithinAParagraphJoinItAndUndoRemovesThem() throws {
        let (app, body) = newEntry(typing: "Hello world")
        defer { app.terminate() }
        for _ in 0..<" world".count { body.typeKey(.leftArrow, modifierFlags: []) }
        UIPasteboard.general.string = " dear"
        paste(into: body, app: app)
        XCTAssertTrue(wait(for: body, toEqual: "Hello dear world"))
        app.typeText(",")
        XCTAssertEqual(body.value as? String, "Hello dear, world")
        body.typeKey("z", modifierFlags: .command)
        body.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(wait(for: body, toEqual: "Hello world"))
    }

    // MARK: - Steps

    @MainActor private func newEntry(typing text: String) -> (XCUIApplication, XCUIElement) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        XCTAssertTrue(app.buttons["Continue Without Encryption"].waitToAppear(timeout: 5))
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Trip\n")
        let body = app.textViews["Entry text"]
        app.typeText(text)
        XCTAssertTrue(wait(for: body, toEqual: text))
        // The simulator takes the first key from a hardware keyboard, such as ⌘V, to connect that keyboard; the key
        // itself never reaches the app. → at the end of the text connects it and changes nothing.
        body.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(wait(for: body, toEqual: text))
        return (app, body)
    }

    /// ⌘V, as from a hardware keyboard. A paste the person makes needs no permission, but allow it should iOS ask.
    @MainActor private func paste(into body: XCUIElement, app: XCUIApplication) {
        body.typeKey("v", modifierFlags: .command)
        let allow = app.alerts.buttons["Allow Paste"]
        if allow.waitToAppear(timeout: 1) { allow.tap() }
    }

    @MainActor private func wait(for body: XCUIElement, toEqual text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: body)
        return Waiting.wait(for: expectation, timeout: 5) == .completed
    }

    @MainActor private func wait(for body: XCUIElement, toContain text: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", text), object: body)
        return Waiting.wait(for: expectation, timeout: 5) == .completed
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
