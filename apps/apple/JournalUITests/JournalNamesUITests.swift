import XCTest

/// A taken journal name is refused with Name Taken, and Rename is how a numbered duplicate gets its own name
/// (docs/design/journal-name-uniqueness.md §4.1 and §5).
final class JournalNamesUITests: XCTestCase {
    @MainActor func testNameTakenThenRenameToAFreeName() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.showJournals(app)
        createJournal("Travel", app: app)

        createJournal(" default ", app: app)
        let taken = app.alerts["Name Taken"]
        XCTAssertTrue(taken.waitToAppear(timeout: 5))
        XCTAssertTrue(
            taken.staticTexts["A journal named “Default” already exists. Choose a different name."].exists)
        attach("Name Taken", app: app)
        taken.buttons["OK"].tap()
        let again = app.alerts["New Journal"]
        XCTAssertTrue(again.waitToAppear(timeout: 5), "OK returns to New Journal.")
        assertEventually(again.textFields["Name"].value as? String, equals: " default ", "The typed name is kept.")
        again.buttons["Cancel"].tap()

        NavigationTestSupport.showJournals(app)
        let list = app.collectionViews["Journals"]
        NavigationTestSupport.journalAction("Rename…", journal: "Travel", app: app)
        let rename = app.alerts["Rename Journal"]
        XCTAssertTrue(rename.waitToAppear(timeout: 5))
        rename.textFields["Name"].tap()
        rename.textFields["Name"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Trips")
        attach("Rename Journal", app: app)
        rename.buttons["Rename"].tap()
        NavigationTestSupport.finishJournalEditing(app)
        XCTAssertTrue(list.staticTexts["Trips"].waitToAppear(timeout: 5))
        XCTAssertFalse(list.staticTexts["Travel"].exists, "The journal has its new name.")
        XCTAssertTrue(list.staticTexts["Default"].exists)
    }

    @MainActor func testRestoringIntoATakenNameThenRenamingToIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.showJournals(app)
        createJournal("Travel", app: app)
        NavigationTestSupport.showJournals(app)
        let list = app.collectionViews["Journals"]
        NavigationTestSupport.journalAction("Delete Journal…", journal: "Travel", app: app)
        let deletion = app.alerts["Delete “Travel”?"]
        XCTAssertTrue(deletion.waitToAppear(timeout: 5))
        deletion.buttons["Delete"].tap()
        NavigationTestSupport.finishJournalEditing(app)
        NavigationTestSupport.showJournals(app)
        createJournal("Travel", app: app)

        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        app.staticTexts["Travel"].firstMatch.tap()
        // The page says what the name will be before the button that restores at once.
        let sentence = app.staticTexts[
            "Another journal is named “Travel”, so this one will be restored as “Travel 2”."]
        XCTAssertTrue(sentence.waitToAppear(timeout: 5))
        attach("Restore into a taken name", app: app)
        let restore = app.buttons["Restore Journal"]
        if !restore.isHittable { app.scrollViews.firstMatch.swipeUp() }
        restore.tap()
        NavigationTestSupport.showJournals(app)
        XCTAssertTrue(list.staticTexts["Travel 2"].waitToAppear(timeout: 5))

        NavigationTestSupport.journalAction("Rename…", journal: "Travel 2", app: app)
        let rename = app.alerts["Rename Journal"]
        XCTAssertTrue(rename.waitToAppear(timeout: 5))
        rename.textFields["Name"].tap()
        rename.textFields["Name"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "TRAVEL")
        rename.buttons["Rename"].tap()
        let taken = app.alerts["Name Taken"]
        XCTAssertTrue(taken.waitToAppear(timeout: 5))
        taken.buttons["OK"].tap()
        XCTAssertTrue(app.alerts["Rename Journal"].waitToAppear(timeout: 5), "OK returns to Rename.")
        app.alerts["Rename Journal"].buttons["Cancel"].tap()
        NavigationTestSupport.finishJournalEditing(app)
        XCTAssertTrue(list.staticTexts["Travel 2"].exists)
    }

    @MainActor private func createJournal(_ name: String, app: XCUIApplication) {
        app.buttons["New Journal"].tap()
        let create = app.alerts["New Journal"]
        XCTAssertTrue(create.waitToAppear(timeout: 5))
        create.textFields["Name"].tap()
        create.textFields["Name"].typeText(name)
        create.buttons["Create"].tap()
    }
    @MainActor private func attach(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
