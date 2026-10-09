import XCTest

/// Settings ▸ Backup ▸ Export as Markdown… saves a folder through the system's save dialog
/// (docs/design/client-only-mac-lists-markdown-2026-10-05.md §3), and the app shows no error afterwards.
final class MarkdownExportUITests: XCTestCase {
    @MainActor func testExportAsMarkdownSavesAFolderThroughTheSaveDialog() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        let newEntry = app.buttons["New Entry"].firstMatch
        XCTAssertTrue(newEntry.waitToAppear(timeout: 10))
        newEntry.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        NavigationTestSupport.dismissKeyboardTips(app)
        app.typeText("Exported entry\nA line to keep")
        NavigationTestSupport.openSettings(app)
        app.buttons["Backup"].firstMatch.tap()
        let export = app.buttons["Export as Markdown…"].firstMatch
        XCTAssertTrue(export.waitToAppear(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saves your journals and their images'"))
                .firstMatch.exists)
        export.tap()

        let saveDialog = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(saveDialog.waitToAppear(timeout: 15))
        let suggested = app.textFields.matching(NSPredicate(format: "value BEGINSWITH 'Journal Markdown '")).firstMatch
        XCTAssertTrue(suggested.waitToAppear(timeout: 5), "The save dialog suggests the folder's name.")
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "Move", "Export"])).firstMatch
        XCTAssertTrue(save.waitToAppear(timeout: 5))
        save.tap()
        XCTAssertTrue(saveDialog.waitToDisappear(timeout: 15))
        XCTAssertTrue(export.waitToAppear(timeout: 5))
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Couldn’t'")).firstMatch.exists,
            "Saved without an error")
    }
}
