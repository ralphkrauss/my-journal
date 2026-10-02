import XCTest

/// A taken journal name is refused with Name Taken, and Merge Into… combines two journals
/// (docs/design/journal-name-uniqueness.md §4.1 and §5).
final class JournalNamesUITests: XCTestCase {
    @MainActor func testNameTakenThenMergeIntoAnotherJournal() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.showJournals(app)
        createJournal("Travel", app: app)

        createJournal(" default ", app: app)
        let taken = app.alerts["Name Taken"]
        XCTAssertTrue(taken.waitForExistence(timeout: 5))
        XCTAssertTrue(
            taken.staticTexts["A journal named “Default” already exists. Choose a different name."].exists)
        attach("Name Taken", app: app)
        taken.buttons["OK"].tap()
        let again = app.alerts["New Journal"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "OK returns to New Journal.")
        XCTAssertEqual(again.textFields["Name"].value as? String, " default ", "The typed name is kept.")
        again.buttons["Cancel"].tap()

        NavigationTestSupport.showJournals(app)
        let list = app.collectionViews["Journals"]
        list.staticTexts["Travel"].firstMatch.press(forDuration: 1)
        app.buttons["Merge Into…"].tap()
        let merge = app.navigationBars["Merge “Travel”"]
        XCTAssertTrue(merge.waitForExistence(timeout: 5))
        app.buttons["Default"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["“Travel” has no entries. It moves to Recently Deleted."].exists)
        attach("Merge Journal", app: app)
        merge.buttons["Merge"].tap()
        XCTAssertTrue(merge.waitForNonExistence(timeout: 5))
        NavigationTestSupport.showJournals(app)
        XCTAssertFalse(list.staticTexts["Travel"].exists, "The merged journal moved to Recently Deleted.")
        XCTAssertTrue(list.staticTexts["Default"].exists)
    }

    @MainActor func testRestoringIntoATakenNameThenRenamingToIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.showJournals(app)
        createJournal("Travel", app: app)
        NavigationTestSupport.showJournals(app)
        let list = app.collectionViews["Journals"]
        list.staticTexts["Travel"].firstMatch.press(forDuration: 1)
        app.buttons["Delete Journal…"].tap()
        let deletion = app.alerts["Delete “Travel”?"]
        XCTAssertTrue(deletion.waitForExistence(timeout: 5))
        deletion.buttons["Delete"].tap()
        NavigationTestSupport.showJournals(app)
        createJournal("Travel", app: app)

        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        app.staticTexts["Travel"].firstMatch.tap()
        app.buttons["Restore Journal…"].tap()
        let sentence = app.staticTexts[
            "Another journal is named “Travel”, so this one will be restored as “Travel 2”."]
        XCTAssertTrue(sentence.waitForExistence(timeout: 5))
        attach("Restore into a taken name", app: app)
        let restore = app.buttons["Restore Journal"]
        if !restore.isHittable { app.scrollViews.firstMatch.swipeUp() }
        restore.tap()
        NavigationTestSupport.showJournals(app)
        XCTAssertTrue(list.staticTexts["Travel 2"].waitForExistence(timeout: 5))

        list.staticTexts["Travel 2"].firstMatch.press(forDuration: 1)
        app.buttons["Rename…"].tap()
        let rename = app.alerts["Rename Journal"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.textFields["Name"].tap()
        rename.textFields["Name"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "TRAVEL")
        rename.buttons["Rename"].tap()
        let taken = app.alerts["Name Taken"]
        XCTAssertTrue(taken.waitForExistence(timeout: 5))
        taken.buttons["OK"].tap()
        XCTAssertTrue(app.alerts["Rename Journal"].waitForExistence(timeout: 5), "OK returns to Rename.")
        app.alerts["Rename Journal"].buttons["Cancel"].tap()
        XCTAssertTrue(list.staticTexts["Travel 2"].exists)
    }

    @MainActor private func createJournal(_ name: String, app: XCUIApplication) {
        app.buttons["New Journal"].tap()
        let create = app.alerts["New Journal"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
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
