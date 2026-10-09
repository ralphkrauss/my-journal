import XCTest

/// Settings ▸ Erase Journals and Settings… (docs/design/erase-device-2026-10-04.md): after the warning, the
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
        // A standalone section at the end of Settings, not in a pane.
        XCTAssertTrue(app.buttons["Privacy"].waitToAppear(timeout: 5))
        let erase = app.buttons["Erase Journals and Settings…"]
        for _ in 0..<6 where !(erase.exists && erase.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(erase.waitToAppear(timeout: 5))
        capture(app, "Settings with Erase Journals and Settings")
        erase.tap()

        let alert = app.alerts["Erase Journals and Settings?"]
        XCTAssertTrue(alert.waitToAppear(timeout: 10))
        XCTAssertTrue(
            alert.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Export an archive first"))
                .firstMatch.exists, "the journals exist only here")
        XCTAssertTrue(alert.buttons["Export Archive…"].exists)
        capture(app, "Erase alert")
        alert.buttons["Erase"].tap()

        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        XCTAssertTrue(app.navigationBars["Settings"].waitToDisappear(timeout: 10), "Settings closed")
        capture(app, "First screen after erasing")
        startJournal(app)
        NavigationTestSupport.selectCollection("Default", app: app)
        XCTAssertFalse(app.staticTexts["Only on this iPhone"].waitForExistence(timeout: 2))
    }

    /// Each warning leads with exporting an archive whenever something isn't safely on a server, and offers Export
    /// Archive…; only journals confirmed on the server don't. A debug build shows the warning the test chooses, and
    /// Cancel leaves everything as it was.
    @MainActor func testEachWarningSaysWhatToDoFirst() throws {
        for (state, exports) in [
            ("notSyncing", true), ("unsent:3", true), ("unconfirmed", true), ("onServer", false),
            ("nothingWritten", false),
        ] {
            let app = XCUIApplication()
            app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
            app.launchEnvironment["JOURNAL_UI_TEST_ERASE_WARNING"] = state
            app.launch()
            startJournal(app)
            NavigationTestSupport.openSettings(app)
            let erase = app.buttons["Erase Journals and Settings…"]
            for _ in 0..<6 where !(erase.exists && erase.isHittable) { app.collectionViews.firstMatch.swipeUp() }
            erase.tap()
            let alert = app.alerts["Erase Journals and Settings?"]
            XCTAssertTrue(alert.waitToAppear(timeout: 10), state)
            let advice = alert.staticTexts.containing(
                NSPredicate(format: "label BEGINSWITH %@", "Export an archive first")
            ).firstMatch
            XCTAssertEqual(advice.exists, exports, state)
            XCTAssertEqual(alert.buttons["Export Archive…"].exists, exports, state)
            capture(app, "Erase alert, \(state)")
            alert.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["Privacy"].waitToAppear(timeout: 5), "Cancel keeps Settings open")
            app.terminate()
        }
    }

    @MainActor private func startJournal(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
