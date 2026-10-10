import XCTest

/// Spec screenshots of backup, export, passwords, encryption and erasing.
final class SpecDataCaptureTests: SpecCaptureCase {
    private let samplePassword = "Sample password for the spec"

    @MainActor private func openSettings(_ app: XCUIApplication) {
        if isPad { try? openEntry("Slow Sunday", journal: "Personal", app: app) }
        NavigationTestSupport.openSettings(app)
    }

    @MainActor func testAboutAndErase() throws {
        let app = try launch(environment: ["JOURNAL_UI_TEST_ERASE_WARNING": "notSyncing"])
        openSettings(app)
        let erase = app.buttons["Erase Journals and Settings…"]
        for _ in 0..<6 where !(erase.exists && erase.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        try require(erase, app: app, timeout: 5)
        try shot(app, "settings-about-default")
        try shot(app, "settings-erase-default")
        erase.tap()
        try require(app.alerts["Erase Journals and Settings?"], app: app, timeout: 10)
        try shot(app, "erase-default")
    }

    @MainActor func testExport() throws {
        let app = try launch()
        openSettings(app)
        try tapButton("Backup", in: app)
        try tapButton("Export Archive…", in: app)
        try shot(app, "export-archive-default")
    }

    @MainActor func testExportMarkdown() throws {
        let app = try launch()
        openSettings(app)
        try tapButton("Backup", in: app)
        try tapButton("Export as Markdown…", in: app)
        try shot(app, "export-markdown-default")
    }

    @MainActor func testChangePassword() throws {
        let app = try launch(environment: ["JOURNAL_UI_TEST_DEVICE_AUTH": "success"])
        openSettings(app)
        try tapButton("Privacy", in: app)
        try tapButton("Change Password…", in: app)
        try shot(app, "change-password-default")
    }
}
