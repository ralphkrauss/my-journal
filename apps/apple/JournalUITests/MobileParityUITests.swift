import XCTest

final class MobileParityUITests: XCTestCase {
    @MainActor func testSourceFormattingAndNativeBackNavigationPreserveEntry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        // Going straight back keeps the new entry, even though it's empty (owner decision, 2026-09-30).
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitForExistence(timeout: 5))
        swipeBack(app)
        let emptyEntry = app.cells.containing(.staticText, identifier: "No additional text").firstMatch
        XCTAssertTrue(emptyEntry.waitForExistence(timeout: 5))
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitForExistence(timeout: 5))
        app.typeText("Source formatting")
        let body = app.textViews["Entry text"]
        body.tap()
        app.buttons["View Source"].firstMatch.tap()
        app.buttons["Formatting"].firstMatch.tap()
        app.buttons["Heading 1"].firstMatch.tap()
        XCTAssertEqual(body.value as? String, "# ")
        app.typeText("A heading")
        XCTAssertEqual(body.value as? String, "# A heading")
        XCTAssertFalse(app.buttons["Share Entry"].exists)
        XCTAssertFalse(app.buttons["Insert Table"].exists)
        XCTAssertFalse(app.buttons["Task List"].exists)
        XCTAssertFalse(app.buttons["Undo"].exists)
        XCTAssertFalse(app.buttons["Redo"].exists)
        app.buttons["Finish Editing"].tap()
        for _ in 0..<2 {
            swipeBack(app)
            XCTAssertTrue(app.searchFields["Search Default"].waitForExistence(timeout: 5))
            XCTAssertTrue(emptyEntry.exists)
            XCTAssertFalse(app.cells.containing(.staticText, identifier: "Source formatting").firstMatch.isSelected)
            swipeBack(app)
            let journals = app.collectionViews["Journals"]
            XCTAssertTrue(journals.waitForExistence(timeout: 5))
            XCTAssertFalse(journals.cells.containing(.staticText, identifier: "Default").firstMatch.isSelected)
            NavigationTestSupport.openEntry("Source formatting", journal: "Default", app: app)
            if app.buttons["View Source"].firstMatch.exists {
                NavigationTestSupport.readingButton("View Source", app: app).tap()
            }
            XCTAssertEqual(body.value as? String, "# A heading")
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Source retained after native back gestures"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func swipeBack(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
