import XCTest

/// Small native details of starting a journal and writing an entry on iPhone.
final class EntryBasicsUITests: XCTestCase {
    /// The welcome screen's picture is decoration, and the encrypted step of Start a Journal has the system back button
    /// where Cancel was, with Create alone on the trailing side.
    @MainActor func testWelcomeAndEncryptedStartFollowNativeConventions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        let start = app.buttons["Start a Journal"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["book.closed"].exists, "VoiceOver would read the symbol's name.")
        capture(app, "Welcome")
        start.tap()
        let encrypt = app.buttons["Use Encryption"]
        XCTAssertTrue(encrypt.waitForExistence(timeout: 5))
        encrypt.tap()
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
        ).firstMatch
        let create = bar.buttons["Create"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(create.exists)
        XCTAssertFalse(bar.buttons["Cancel"].exists)
        XCTAssertLessThan(back.frame.midX, bar.frame.midX)
        XCTAssertGreaterThan(create.frame.midX, bar.frame.midX)
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: app.secureTextFields["Master Password"])
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: 3), .completed)
        capture(app, "Choose a Master Password")
        back.tap()
        XCTAssertTrue(encrypt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.firstMatch.buttons["Cancel"].exists)
        NavigationTestSupport.createPasswordJournal(app)
        XCTAssertTrue(encrypt.waitForNonExistence(timeout: 15))
    }

    /// Tab from a hardware keyboard moves from the title to the text, as Return does; the title never holds a tab.
    @MainActor func testTabInTitleMovesToText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        NavigationTestSupport.newEntryFromList(app)
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Rich")
        app.typeText("\t")
        app.typeText("paste")
        XCTAssertEqual(title.value as? String, "Rich")
        XCTAssertEqual(app.textViews["Entry text"].value as? String, "paste")
    }

    /// Tapping in the empty space below an entry's text, after opening it, continues at the end, as in Notes. It used
    /// to select a misspelled last word, so the next letter typed replaced it.
    @MainActor func testTapBelowTheTextAfterReopeningContinuesAtTheEnd() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        NavigationTestSupport.newEntryFromList(app)
        XCTAssertTrue(NavigationTestSupport.title(app).waitForExistence(timeout: 10))
        app.typeText("Spell test\n")
        let body = app.textViews["Entry text"]
        app.typeText("Coffee and pastries blorptz")
        XCTAssertEqual(body.value as? String, "Coffee and pastries blorptz")
        app.buttons["Finish Editing"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        NavigationTestSupport.openEntry("Spell test", journal: "Default", app: app)
        // Well below the only line, in the entry's empty space.
        let below = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(
            CGVector(dx: 0, dy: 160))
        below.tap()
        let writing = NSPredicate { _, _ in (body.value(forKey: "hasKeyboardFocus") as? Bool) == true }
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: writing, object: nil)], timeout: 5), .completed)
        capture(app, "After tapping below the text")
        app.typeText("K")
        XCTAssertEqual(body.value as? String, "Coffee and pastries blorptzK")
        // While writing, too.
        below.tap()
        app.typeText("L")
        XCTAssertEqual(body.value as? String, "Coffee and pastries blorptzKL")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
