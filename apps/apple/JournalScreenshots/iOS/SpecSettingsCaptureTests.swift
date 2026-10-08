import XCTest

/// Spec screenshots of Settings and its pages.
final class SpecSettingsCaptureTests: SpecCaptureCase {
    /// Opens Settings and, when `page` is given, that page, then captures it as `<id>-default`.
    @MainActor private func capturePage(_ page: String?, id: String, extra: ((XCUIApplication) throws -> Void)? = nil)
        throws
    {
        let app = try launch(environment: ["JOURNAL_UI_TEST_DEVICE_AUTH": "success"])
        if isPad { try openEntry("Slow Sunday", journal: "Personal", app: app) }
        NavigationTestSupport.openSettings(app)
        if let page { try tapButton(page, in: app) }
        try shot(app, id + "-default")
        try extra?(app)
    }

    @MainActor func testSettingsRoot() throws { try capturePage(nil, id: "settings") }
    @MainActor func testWriting() throws { try capturePage("Writing", id: "settings-general") }
    @MainActor func testPrivacy() throws { try capturePage("Privacy", id: "settings-privacy") }
    @MainActor func testSync() throws { try capturePage("Sync", id: "settings-sync") }
    @MainActor func testDevices() throws { try capturePage("Devices", id: "settings-devices") }
    @MainActor func testBackup() throws { try capturePage("Backup", id: "settings-backup") }
    @MainActor func testAgentAccess() throws { try capturePage("Agent Access", id: "settings-agent-access") }
}
