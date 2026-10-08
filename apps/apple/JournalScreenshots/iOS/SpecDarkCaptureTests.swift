import XCTest

/// Spec screenshots in dark appearance, for a few key screens. design/spec-screenshots/capture.sh runs this class with
/// the simulator set to dark appearance (`simctl ui appearance dark`), as the App Store captures do, and the names end
/// in `-dark`.
final class SpecDarkCaptureTests: SpecCaptureCase {
    @MainActor func testDarkScreens() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        if isPad { showSidebar(app) }
        try shot(app, "library-window-default-dark")
        try shot(app, "entry-editor-default-dark")
        if !isPad { goBack(app) }
        try shot(app, "entry-list-default-dark")
        NavigationTestSupport.showJournals(app)
        try shot(app, "journals-default-dark")
        NavigationTestSupport.openSettings(app)
        try shot(app, "settings-default-dark")
        try tapButton("Privacy", in: app)
        try shot(app, "settings-privacy-default-dark")
    }

    @MainActor func testDarkEditing() throws {
        let app = try launch()
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        try tapButton("Formatting", in: app)
        try shot(app, "format-sheet-default-dark")
    }

    @MainActor func testDarkVersionHistory() throws {
        let app = try launch()
        try openEntry("Bread, attempt four", journal: "Personal", app: app)
        try chooseEntryAction("Version History…", in: app)
        try require(app.navigationBars["Version History"], app: app, timeout: 10)
        try shot(app, "version-history-default-dark")
    }
}
