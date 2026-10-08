import XCTest

/// Spec screenshots of the entry editor: formatting, links, tables, images, source and the entry's actions.
final class SpecEditorCaptureTests: SpecCaptureCase {
    @MainActor func testFormatPanelAndLinkEditor() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        try tapButton("Formatting", in: app)
        try shot(app, "format-sheet-default")
        try tapButton("Insert", in: app, timeout: 5)
        try shot(app, "format-sheet-insert-menu")
        try tapButton("Add Link…", in: app, timeout: 5)
        try require(app.navigationBars["Add Link"], app: app, timeout: 5)
        try shot(app, "link-editor-default")
    }

    @MainActor func testEntryActionsMenu() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        try tapButton("Entry Actions", in: app)
        try require(app.buttons["Move Entry…"], app: app, timeout: 5)
        try shot(app, "entry-editor-actions-menu")
    }

    @MainActor func testViewSource() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        try tapButton("View Source", in: app)
        try require(app.buttons["View Preview"], app: app, timeout: 5)
        try shot(app, "source-view-default")
    }

    @MainActor func testTableChecklistAndImage() throws {
        let app = try launch()
        try openEntry("Offsite ideas", journal: "Work", app: app)
        try shot(app, "edit-table-default")
        try shot(app, "entry-editor-table")
        try openEntry("Packing list", journal: "Travel", app: app)
        try shot(app, "entry-editor-checklist")
    }

    @MainActor func testEditingWithKeyboard() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        let body = app.textViews["Entry text"]
        body.tap()
        NavigationTestSupport.dismissKeyboardTips(app)
        try require(app.buttons["Finish Editing"], app: app, timeout: 5)
        try shot(app, "entry-editor-editing")
    }

    @MainActor func testImageDescriptionsChangeDateMove() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        try chooseEntryAction("Image Descriptions…", in: app)
        try require(app.navigationBars["Image Descriptions"], app: app, timeout: 10)
        try shot(app, "image-description-default")
        try tapButton("Done", in: app)
        try chooseEntryAction("Change Date…", in: app)
        try require(app.navigationBars["Change Date"], app: app, timeout: 10)
        try shot(app, "change-date-default")
        try tapButton("Cancel", in: app)
        try chooseEntryAction("Move Entry…", in: app)
        try require(app.navigationBars["Move Entry"], app: app, timeout: 10)
        try shot(app, "move-entry-default")
    }

    @MainActor func testVersionHistory() throws {
        let app = try launch()
        try openEntry("Bread, attempt four", journal: "Personal", app: app)
        try chooseEntryAction("Version History…", in: app)
        try require(app.navigationBars["Version History"], app: app, timeout: 10)
        try shot(app, "version-history-default")
    }
}
