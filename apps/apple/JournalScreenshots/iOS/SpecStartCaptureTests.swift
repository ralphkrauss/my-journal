import XCTest

/// Spec screenshots of a first launch, creating a library, the lock screens and the screens for a library that
/// can't be opened. The problems are crafted on copies of the sample library, as the checks in JournalTests do.
final class SpecStartCaptureTests: SpecCaptureCase {
    @MainActor func testWelcomeAndCreateLibrary() throws {
        let app = try launch(library: emptyLibraryFolder(), unlocking: false)
        try require(app.buttons["Start a Journal"], app: app, timeout: 20)
        try shot(app, "welcome-default")
        app.buttons["Start a Journal"].tap()
        let password = app.secureTextFields["Master Password"]
        try require(password, app: app, timeout: 10)
        try shot(app, "create-library-password")
        password.tap()
        password.typeText("Sample password 1")
        NavigationTestSupport.dismissKeyboardTips(app)
        let verify = app.secureTextFields["Verify"]
        verify.tap()
        verify.typeText("Sample password 2")
        app.buttons["Create"].tap()
        try require(app.staticTexts["The passwords don’t match."], app: app, timeout: 5)
        try shot(app, "create-library-mismatch")
    }

    @MainActor func testMasterPasswordLockScreen() throws {
        let app = try launch(unlocking: false)
        try require(app.secureTextFields["Master Password"], app: app, timeout: 20)
        try shot(app, "lock-screen-master-password")
        let field = app.secureTextFields["Master Password"]
        field.tap()
        NavigationTestSupport.dismissKeyboardTips(app)
        field.typeText("not the password")
        app.buttons["Unlock"].firstMatch.tap()
        try require(
            app.staticTexts["That password or recovery key couldn’t unlock your journals."], app: app, timeout: 15)
        try shot(app, "lock-screen-wrong-password")
    }

    @MainActor func testAppLockScreen() throws {
        let app = try launch(environment: ["JOURNAL_UI_TEST_DEVICE_AUTH": "success"])
        if isPad { try openEntry("Slow Sunday", journal: "Personal", app: app) }
        NavigationTestSupport.openSettings(app)
        try tapButton("Privacy", in: app)
        let appLock = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Require'")).firstMatch
        try require(appLock, app: app, timeout: 5)
        if appLock.value as? String == "0" { appLock.switches.firstMatch.tap() }
        try require(app.buttons["Lock My Journal"], app: app, timeout: 10)
        try shot(app, "settings-privacy-app-lock-on")
        app.buttons["Lock My Journal"].tap()
        try require(app.buttons["Unlock with Face ID"], app: app, timeout: 10)
        try shot(app, "lock-screen-default")
    }

    @MainActor func testSettingsUnread() throws {
        try captureProblem("settings-unread", .settingsUnread)
    }

    @MainActor func testCannotOpen() throws {
        try captureProblem("cant-open", .cantOpen)
    }

    @MainActor func testNewerVersion() throws {
        try captureProblem("newer-version", .newerVersion)
    }

    @MainActor func testNotEncrypted() throws {
        try captureProblem("not-encrypted", .notEncrypted)
    }

    // MARK: - Crafting

    /// Opens the sample library once, so the device has its key, then damages the copy and opens it again.
    @MainActor private func captureProblem(_ name: String, _ problem: SpecLibraryFixtures.Problem) throws {
        let library = try copyOfSampleLibrary()
        let app = try launch(library: library)
        try require(NavigationTestSupport.title(app), app: app, timeout: 20)
        app.terminate()
        try SpecLibraryFixtures.damage(problem, in: library)
        app.launch()
        try require(app.buttons["Learn More"], app: app, timeout: 20)
        try shot(app, "unavailable-content-library-\(name)")
    }
}
