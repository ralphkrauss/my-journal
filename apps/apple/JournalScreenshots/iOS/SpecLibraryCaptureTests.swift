import XCTest

/// Spec screenshots of the journals, entry lists, search, templates and Recently Deleted.
final class SpecLibraryCaptureTests: SpecCaptureCase {
    @MainActor func testSearch() throws {
        let app = try launch()
        NavigationTestSupport.selectCollection("Personal", app: app)
        let search = app.searchFields["Search Personal"]
        try require(search, app: app, timeout: 10)
        search.tap()
        search.typeText("w")
        NavigationTestSupport.dismissKeyboardTips(app)
        search.typeText("alk\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        try shot(app, "search-default")
        search.tap()
        search.typeText(" zebra\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        try shot(app, "search-no-results")
    }

    @MainActor func testAllEntries() throws {
        let app = try launch()
        NavigationTestSupport.selectCollection("All Entries", app: app)
        try require(app.staticTexts["Slow Sunday"], app: app, timeout: 10)
        try shot(app, "entry-list-all-entries")
    }

    @MainActor func testJournalActions() throws {
        let app = try launch()
        NavigationTestSupport.showJournals(app)
        try tapButton("Edit", in: app)
        try tapButton("Done", in: app)
        try tapButton("Edit", in: app)
        try shot(app, "journals-edit")
        let list = app.collectionViews["Journals"]
        let row = list.staticTexts["Travel"].firstMatch
        let buttons = list.buttons.matching(NSPredicate(format: "label == %@", "Journal Actions"))
        let menu = buttons.allElementsBoundByIndex.min {
            abs($0.frame.midY - row.frame.midY) < abs($1.frame.midY - row.frame.midY)
        }
        menu?.tap()
        try require(app.buttons["Rename…"], app: app, timeout: 5)
        try shot(app, "journals-actions-menu")
    }

    @MainActor func testNewJournal() throws {
        let app = try launch()
        NavigationTestSupport.showJournals(app)
        try tapButton("New Journal", in: app)
        try require(app.alerts["New Journal"], app: app, timeout: 5)
        try shot(app, "journals-new-journal")
        app.alerts["New Journal"].buttons["Cancel"].tap()
    }

    @MainActor func testTemplates() throws {
        let app = try launch()
        NavigationTestSupport.showJournals(app)
        try tapButton("Templates", in: app)
        try require(app.staticTexts["Book Notes"], app: app, timeout: 10)
        try shot(app, "templates-default")
    }

    @MainActor func testNewEntryAndTemplateChooser() throws {
        let app = try launch()
        NavigationTestSupport.selectCollection("Travel", app: app)
        NavigationTestSupport.newEntryFromList(app)
        try require(app.buttons["Use a Template"], app: app, timeout: 10)
        try shot(app, "new-entry-default")
        app.buttons["Use a Template"].tap()
        try require(app.searchFields["Search Templates"], app: app, timeout: 10)
        NavigationTestSupport.dismissKeyboardTips(app)
        try shot(app, "template-chooser-default")
    }

    @MainActor func testRecentlyDeleted() throws {
        let app = try launch()
        NavigationTestSupport.showJournals(app)
        try tapButton("Recently Deleted", in: app)
        try require(app.staticTexts["No Deleted Items"], app: app, timeout: 10)
        try shot(app, "recently-deleted-empty")
        try openEntry("Rainy walk", journal: "Personal", app: app)
        try chooseEntryAction("Delete Entry", in: app)
        NavigationTestSupport.showJournals(app)
        try tapButton("Recently Deleted", in: app)
        try require(app.staticTexts["Rainy walk"], app: app, timeout: 10)
        try shot(app, "recently-deleted-default")
        app.staticTexts["Rainy walk"].firstMatch.tap()
        try require(app.buttons["Restore"], app: app, timeout: 10)
        try shot(app, "recently-deleted-entry")
        try chooseEntryAction("Delete Permanently…", in: app)
        try require(app.alerts.firstMatch, app: app, timeout: 5)
        try shot(app, "delete-and-restore-delete-permanently")
    }

    @MainActor func testDeleteJournal() throws {
        let app = try launch()
        NavigationTestSupport.journalAction("Delete Journal…", journal: "Travel", app: app, endEditing: false)
        try require(app.alerts["Delete “Travel”?"], app: app, timeout: 5)
        try shot(app, "journals-delete-confirm")
    }
}
