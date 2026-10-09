import XCTest

final class PermanentDeletionUITests: XCTestCase {
    @MainActor func testCancelThenPermanentlyDeleteEntryAndRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.createPasswordJournal(app)
        XCTAssertTrue(app.buttons["New Entry"].firstMatch.waitToAppear(timeout: 10))
        app.buttons["New Entry"].firstMatch.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        title.tap()
        title.typeText("A disposable reflection")
        let body = app.textViews["Entry text"]
        body.tap()
        body.typeText("Only this entry should be removed.")
        app.buttons["Entry Actions"].firstMatch.tap()
        app.buttons["Delete Entry"].tap()
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        let row = app.staticTexts["A disposable reflection"].firstMatch
        XCTAssertTrue(row.waitToAppear(timeout: 5))
        row.press(forDuration: 1)
        app.buttons["Delete Permanently…"].tap()
        let alert = app.alerts["Delete “A disposable reflection” Permanently?"]
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        XCTAssertTrue(
            alert.staticTexts["You can’t undo this. Copies may remain in archives, backups, and server history."].exists
        )
        capture(app, "Permanent deletion confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitToDisappear(timeout: 5))
        XCTAssertTrue(row.waitToAppear(timeout: 5))
        row.tap()
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        assertEventually(title.value as? String, equals: "A disposable reflection")
        assertEventually((body.value as? String ?? "").contains("Only this entry should be removed."))
        app.buttons["Entry Actions"].firstMatch.tap()
        app.buttons["Delete Permanently…"].tap()
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No Deleted Items"].waitToAppear(timeout: 10))
        app.terminate()
        app.launch()
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        XCTAssertTrue(app.staticTexts["No Deleted Items"].waitToAppear(timeout: 5))
        XCTAssertFalse(row.exists)
    }
    /// Cancelling the alert after swiping keeps the row in view. A destructive swipe action hid the row before the
    /// alert asked, and it stayed hidden after Cancel.
    @MainActor func testCancelledSwipeKeepsDeletedRowVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.selectCollection("Default", app: app)
        for title in ["Kept", "Other"] {
            if app.buttons["Finish Editing"].exists { app.buttons["Finish Editing"].tap() }
            NavigationTestSupport.newEntryFromList(app)
            XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 5))
            app.typeText(title)
            app.textViews["Entry text"].tap()
            app.typeText("Text")
            app.buttons["Entry Actions"].firstMatch.tap()
            app.buttons["Delete Entry"].tap()
        }
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        func row(_ title: String) -> XCUIElement { app.cells.containing(.staticText, identifier: title).firstMatch }
        XCTAssertTrue(row("Kept").waitToAppear(timeout: 5))
        capture(app, "Recently Deleted")
        row("Kept").swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let alert = app.alerts["Delete “Kept” Permanently?"]
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitToDisappear(timeout: 5))
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in row("Kept").exists && row("Kept").isHittable }, object: app)
        XCTAssertEqual(Waiting.wait(for: visible, timeout: 5), .completed)
        capture(app, "Recently Deleted after Cancel")
        XCTAssertTrue(row("Other").isHittable)
    }
    /// Going back from Recently Deleted to the journals keeps the remaining journal listed and New Entry available.
    /// New Entry stayed disabled there, as if Recently Deleted were still shown.
    @MainActor func testNewEntryWorksAfterLeavingRecentlyDeleted() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.showJournals(app)
        app.buttons["New Journal"].tap()
        let create = app.alerts["New Journal"]
        XCTAssertTrue(create.waitToAppear(timeout: 5))
        create.textFields["Name"].tap()
        create.textFields["Name"].typeText("Work")
        create.buttons["Create"].tap()
        NavigationTestSupport.showJournals(app)
        app.staticTexts["Default"].firstMatch.press(forDuration: 1)
        app.buttons["Delete Journal…"].tap()
        let deletion = app.alerts["Delete “Default”?"]
        XCTAssertTrue(deletion.waitToAppear(timeout: 5))
        deletion.buttons["Delete"].tap()
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        let journal = app.cells.containing(.staticText, identifier: "Default").firstMatch
        XCTAssertTrue(journal.waitToAppear(timeout: 5))
        journal.tap()
        app.buttons["Delete Permanently…"].tap()
        let permanent = app.alerts["Delete “Default” Permanently?"]
        XCTAssertTrue(permanent.waitToAppear(timeout: 5))
        permanent.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No Deleted Items"].waitToAppear(timeout: 10))
        NavigationTestSupport.showJournals(app)
        XCTAssertTrue(app.collectionViews["Journals"].staticTexts["Work"].waitToAppear(timeout: 5))
        let newEntry = app.buttons["New Entry"].firstMatch
        XCTAssertTrue(newEntry.waitToAppear(timeout: 5))
        assertEventually(newEntry.isEnabled)
        newEntry.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 5))
        capture(app, "New entry after Recently Deleted")
        // With the Default journal gone, Work takes its place as the default.
        NavigationTestSupport.openSettings(app)
        app.buttons["General"].tap()
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Default Journal'")).firstMatch
        XCTAssertTrue(picker.waitToAppear(timeout: 5))
        assertEventually(picker.label.contains("Work") || (picker.value as? String) == "Work")
        capture(app, "Default Journal setting")
    }
    /// Delete All empties Recently Deleted after saying what it deletes; Cancel keeps everything. The button is only
    /// there while Recently Deleted has something in it.
    @MainActor func testDeleteAllEmptiesRecentlyDeleted() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        XCTAssertTrue(app.staticTexts["No Deleted Items"].waitToAppear(timeout: 5))
        let deleteAll = app.navigationBars.buttons["Delete All"]
        XCTAssertFalse(deleteAll.exists)
        NavigationTestSupport.selectCollection("Default", app: app)
        for title in ["First", "Second"] {
            if app.buttons["Finish Editing"].exists { app.buttons["Finish Editing"].tap() }
            NavigationTestSupport.newEntryFromList(app)
            XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 5))
            app.typeText(title)
            app.buttons["Entry Actions"].firstMatch.tap()
            app.buttons["Delete Entry"].tap()
        }
        NavigationTestSupport.showJournals(app)
        app.buttons["New Journal"].tap()
        let create = app.alerts["New Journal"]
        XCTAssertTrue(create.waitToAppear(timeout: 5))
        create.textFields["Name"].typeText("Work")
        create.buttons["Create"].tap()
        NavigationTestSupport.showJournals(app)
        app.staticTexts["Work"].firstMatch.press(forDuration: 1)
        app.buttons["Delete Journal…"].tap()
        let deleteJournal = app.alerts["Delete “Work”?"]
        XCTAssertTrue(deleteJournal.waitToAppear(timeout: 5))
        deleteJournal.buttons["Delete"].tap()
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        func row(_ title: String) -> XCUIElement { app.cells.containing(.staticText, identifier: title).firstMatch }
        XCTAssertTrue(row("Second").waitToAppear(timeout: 5))
        XCTAssertTrue(deleteAll.waitToAppear(timeout: 5))
        capture(app, "Recently Deleted with Delete All")
        deleteAll.tap()
        let alert = app.alerts["Delete 3 Items Permanently?"]
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        XCTAssertTrue(
            alert.staticTexts[
                "Includes 1 journal and 2 entries. You can’t undo this. Copies may remain in archives, backups, and "
                    + "server history."
            ].exists)
        capture(app, "Delete All confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitToDisappear(timeout: 5))
        for title in ["First", "Second", "Work"] { XCTAssertTrue(row(title).waitToAppear(timeout: 5)) }
        deleteAll.tap()
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No Deleted Items"].waitToAppear(timeout: 10))
        XCTAssertTrue(deleteAll.waitToDisappear(timeout: 5))
        capture(app, "Recently Deleted after Delete All")
        NavigationTestSupport.showJournals(app)
        XCTAssertFalse(app.collectionViews["Journals"].staticTexts["Work"].exists)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
