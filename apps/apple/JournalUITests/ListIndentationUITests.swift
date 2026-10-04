import XCTest

/// Increase and Decrease Indent in the iPhone's Format panel (docs/design/list-indentation-2026-10-04.md): the row is
/// always there, its buttons dim where they don't apply, and the panel stays open while an item moves.
final class ListIndentationUITests: XCTestCase {
    @MainActor func testTheIndentButtonsFollowTheListAndKeepThePanelOpen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        XCTAssertTrue(app.buttons["Continue Without Encryption"].waitToAppear(timeout: 5))
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Shopping\n")
        let body = app.textViews["Entry text"]
        // As a person types: the shortcut has made the line a list item before the next words. (Typed all at once,
        // the editor's own change can land after later keystrokes.)
        app.typeText("- ")
        assertEventually(body, "NOT (value CONTAINS '-')")
        app.typeText("Milk\n")
        assertEventually(body, "value BEGINSWITH 'Milk' AND value != 'Milk'")
        app.typeText("Eggs")
        XCTAssertEqual(body.value as? String, "Milk\nEggs\n", "typed as written")
        capture(app, "Typed")

        let increase = app.buttons["Increase Indent"]
        let decrease = app.buttons["Decrease Indent"]
        openFormat(app)
        XCTAssertTrue(increase.waitToAppear(timeout: 5))
        XCTAssertTrue(increase.isEnabled, "the second item can nest under the first")
        XCTAssertFalse(decrease.isEnabled, "a top-level item can't move out")
        increase.tap()
        XCTAssertTrue(app.staticTexts["Format"].exists, "the panel stays open")
        XCTAssertFalse(increase.isEnabled, "the item is already one level below the item above")
        XCTAssertTrue(decrease.isEnabled)
        capture(app, "Eggs indented, Format panel open")
        decrease.tap()
        XCTAssertTrue(increase.isEnabled)
        XCTAssertFalse(decrease.isEnabled)
        app.buttons["Close"].tap()

        // Return twice leaves the list: the empty line after it is a plain line.
        app.typeText("\n\n")
        openFormat(app)
        XCTAssertTrue(increase.waitToAppear(timeout: 5), "the row stays in the panel")
        XCTAssertFalse(increase.isEnabled)
        XCTAssertFalse(decrease.isEnabled)
        XCTAssertFalse(app.buttons["Bulleted List"].isSelected, "the line after the list isn't a list item")
        XCTAssertTrue(app.buttons["Paragraph"].isSelected)
        capture(app, "Line after the list, both dimmed")
        app.buttons["Close"].tap()
    }

    @MainActor private func assertEventually(_ element: XCUIElement, _ format: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        XCTAssertEqual(Waiting.wait(for: expectation, timeout: 5), .completed, "\(element.value ?? "")")
    }

    @MainActor private func openFormat(_ app: XCUIApplication) {
        let formatting = app.buttons["Formatting"].firstMatch
        XCTAssertTrue(formatting.waitToAppear(timeout: 5))
        formatting.tap()
        XCTAssertTrue(app.staticTexts["Format"].waitToAppear(timeout: 5))
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
