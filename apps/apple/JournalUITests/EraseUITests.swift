import XCTest

/// Settings ▸ Privacy ▸ Erase Journals and Settings… (docs/design/erase-device-2026-10-04.md): after the warning, the
/// app is back at its first screen, and a new journal starts empty.
final class EraseUITests: XCTestCase {
    @MainActor func testErasingReturnsToTheFirstScreen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        startJournal(app)
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Only on this iPhone")

        NavigationTestSupport.openSettings(app)
        XCTAssertTrue(app.buttons["Privacy"].waitToAppear(timeout: 5))
        app.buttons["Privacy"].tap()
        let erase = app.buttons["Erase Journals and Settings…"]
        for _ in 0..<6 where !(erase.exists && erase.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(erase.waitToAppear(timeout: 5))
        capture(app, "Privacy with Erase Journals and Settings")
        erase.tap()

        let alert = app.alerts["Erase Journals and Settings?"]
        XCTAssertTrue(alert.waitToAppear(timeout: 10))
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "aren’t synced to a server"))
                .firstMatch.exists, "the journals exist only here")
        XCTAssertTrue(alert.buttons["Export Archive…"].exists)
        capture(app, "Erase alert")
        alert.buttons["Erase"].tap()

        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        XCTAssertTrue(app.navigationBars["Privacy"].waitToDisappear(timeout: 10), "Settings closed")
        capture(app, "First screen after erasing")
        startJournal(app)
        NavigationTestSupport.selectCollection("Default", app: app)
        XCTAssertFalse(app.staticTexts["Only on this iPhone"].waitForExistence(timeout: 2))
    }

    @MainActor private func startJournal(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        XCTAssertTrue(app.buttons["Continue Without Encryption"].waitToAppear(timeout: 5))
        app.buttons["Continue Without Encryption"].tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
