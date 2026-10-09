import XCTest

/// Spec screenshots of deleted journals, images and Markdown as you type.
final class SpecJournalCaptureTests: SpecCaptureCase {
    @MainActor func testInsertImageMenuAndImageActions() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        let image = app.images.matching(NSPredicate(format: "label BEGINSWITH 'A cup of coffee'")).firstMatch
        try require(image, app: app, timeout: 10)
        image.press(forDuration: 1.2)
        try shot(app, "image-actions-default")
        app.tap()
        let insert = app.buttons["Insert Image"].firstMatch
        if insert.exists, insert.isHittable {
            insert.tap()
            try shot(app, "insert-image-default")
        }
    }

    @MainActor func testMarkdownAsYouType() throws {
        let app = try launch()
        NavigationTestSupport.selectCollection("Travel", app: app)
        NavigationTestSupport.newEntryFromList(app)
        try require(NavigationTestSupport.title(app), app: app, timeout: 10)
        app.typeText("Lisbon notes\n")
        app.typeText("# Plans\n- Tram 28\nPastel de nata\n\n1. Museum\nRiver walk\n")
        try shot(app, "markdown-as-you-type-default")
    }

    @MainActor func testDeletedJournal() throws {
        let app = try launch()
        NavigationTestSupport.journalAction("Delete Journal…", journal: "Travel", app: app)
        try require(app.alerts["Delete “Travel”?"], app: app, timeout: 5)
        app.alerts["Delete “Travel”?"].buttons["Delete"].tap()
        NavigationTestSupport.finishJournalEditing(app)
        NavigationTestSupport.showJournals(app)
        try tapButton("Recently Deleted", in: app)
        try require(app.staticTexts["Travel"], app: app, timeout: 10)
        try shot(app, "recently-deleted-journals")
        try tapButton("Delete All", in: app)
        try shot(app, "recently-deleted-delete-all")
    }

    @MainActor func testDeletedJournalPage() throws {
        let app = try launch()
        NavigationTestSupport.journalAction("Delete Journal…", journal: "Travel", app: app)
        app.alerts["Delete “Travel”?"].buttons["Delete"].tap()
        NavigationTestSupport.finishJournalEditing(app)
        NavigationTestSupport.showJournals(app)
        try tapButton("Recently Deleted", in: app)
        let row = app.staticTexts["Travel"].firstMatch
        try require(row, app: app, timeout: 10)
        row.tap()
        try require(app.buttons["Restore Journal"], app: app, timeout: 10)
        try shot(app, "recently-deleted-journal-page")
    }
}
