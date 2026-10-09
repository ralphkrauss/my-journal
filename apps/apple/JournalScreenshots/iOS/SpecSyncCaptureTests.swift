import XCTest

/// Spec screenshots of connecting to a server and what follows. design/spec-screenshots/capture.sh starts two
/// disposable servers on the loopback address and passes `JOURNAL_SPEC_SERVER` and `JOURNAL_SPEC_SETUP_CODE` (one that
/// is set up with encryption) and `JOURNAL_SPEC_PLAIN_SERVER` and `JOURNAL_SPEC_PLAIN_CODE` (one without).
final class SpecSyncCaptureTests: SpecCaptureCase {
    private let samplePassword = "Sample password for the spec"

    private func server(_ prefix: String) throws -> (address: String, code: String) {
        let key = prefix.isEmpty ? "JOURNAL_SPEC" : "JOURNAL_SPEC_" + prefix
        guard let address = environment[key + "_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let code = environment[key + "_SETUP_CODE"] ?? environment[key + "_CODE"]
        else { throw CaptureError("Run design/spec-screenshots/capture.sh, which starts the servers.") }
        return (address, code)
    }

    @MainActor func testSetUpEncryptedServerAndSignIn() throws {
        let (address, code) = try server("")
        let app = try launch(library: emptyLibraryFolder(), unlocking: false)
        let connect = app.buttons["Connect to a Server…"]
        try require(connect, app: app, timeout: 20)
        connect.tap()
        let field = app.textFields["Server Address"]
        try require(field, app: app, timeout: 5)
        try shot(app, "connect-to-server-address", unlessShowing: "Servers on This Network")
        field.tap()
        field.typeText(address)
        app.navigationBars["Connect to a Server"].buttons["Continue"].tap()
        let setUp = app.navigationBars["Set Up Server"]
        try require(setUp, app: app, timeout: 15)
        try shot(app, "connect-to-server-setup-code")
        let codeField = app.textFields["Setup Code"]
        codeField.tap()
        codeField.typeText("2345")
        setUp.buttons["Continue"].tap()
        try require(app.staticTexts["Enter the 6-character setup code from your server."], app: app, timeout: 5)
        try shot(app, "connect-to-server-code-short")
        replaceText(in: codeField, with: code.lowercased().filter { $0 != "-" })
        setUp.buttons["Continue"].tap()
        let protect = app.navigationBars["Protect Your Journals"]
        try require(protect, app: app, timeout: 15)
        try shot(app, "connect-to-server-protect")
        protect.buttons["Continue"].tap()
        try require(app.navigationBars["Choose a Master Password"], app: app, timeout: 10)
        let password = app.secureTextFields["Master Password"]
        password.tap()
        password.typeText(samplePassword)
        let verify = app.secureTextFields["Verify"]
        verify.tap()
        verify.typeText(samplePassword)
        try shot(app, "connect-to-server-password")
        app.navigationBars["Choose a Master Password"].buttons["Set Up"].tap()
        try require(app.staticTexts["Server Is Ready"], app: app, timeout: 40)
        try shot(app, "connect-to-server-ready")
        try showAddDevice(app)
        try captureSettingsWhenConnected(app)
        // A second device signs in with the password.
        let other = try launch(library: emptyLibraryFolder(), unlocking: false)
        try chooseServer(address, app: other)
        let signIn = other.navigationBars["Enter Master Password"]
        try require(signIn, app: other, timeout: 15)
        try shot(other, "connect-to-server-sign-in")
        let phrase = other.secureTextFields["Master Password"]
        phrase.tap()
        phrase.typeText("Not the sample password")
        signIn.buttons["Sign In"].tap()
        try require(other.staticTexts["That password isn’t correct."], app: other, timeout: 30)
        try shot(other, "connect-to-server-wrong-password")
        try tapButton("Use a Connected Device Instead…", in: other)
        try require(other.staticTexts["pairing-code"], app: other, timeout: 15)
        try shot(other, "pair-device-default")
    }

    @MainActor func testSetUpServerWithoutEncryption() throws {
        let (address, code) = try server("PLAIN")
        let app = try launch(library: emptyLibraryFolder(), unlocking: false)
        try chooseServer(address, app: app)
        let setUp = app.navigationBars["Set Up Server"]
        try require(setUp, app: app, timeout: 15)
        let codeField = app.textFields["Setup Code"]
        codeField.tap()
        codeField.typeText(code)
        setUp.buttons["Continue"].tap()
        try require(app.navigationBars["Protect Your Journals"], app: app, timeout: 15)
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don’t Encrypt")).firstMatch
        for _ in 0..<4 where !skip.isHittable { app.swipeUp() }
        skip.tap()
        try shot(app, "connect-to-server-protect-off")
        app.navigationBars["Protect Your Journals"].buttons["Set Up"].tap()
        try require(app.staticTexts["Server Is Ready"], app: app, timeout: 40)
        try tapButton("Done", in: app)
        // Another device adds itself with a pairing code, as there is no password to sign in with.
        let other = try launch(library: emptyLibraryFolder(), unlocking: false)
        try chooseServer(address, app: other)
        try require(other.navigationBars["Add This Device"], app: other, timeout: 15)
        try require(other.staticTexts["pairing-code"], app: other, timeout: 10)
        try shot(other, "connect-to-server-add-this-device")
        let recovery = other.buttons["Use a Recovery Code Instead…"]
        for _ in 0..<4 where !recovery.isHittable { other.swipeUp() }
        recovery.tap()
        try require(other.navigationBars["Use a Recovery Code"], app: other, timeout: 10)
        try shot(other, "connect-to-server-recovery-code")
    }

    // MARK: - Steps

    @MainActor private func chooseServer(_ address: String, app: XCUIApplication) throws {
        let connect = app.buttons["Connect to a Server…"]
        try require(connect, app: app, timeout: 20)
        connect.tap()
        let field = app.textFields["Server Address"]
        try require(field, app: app, timeout: 5)
        field.tap()
        field.typeText(address)
        app.navigationBars["Connect to a Server"].buttons["Continue"].tap()
    }

    @MainActor private func replaceText(in field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text)
    }

    /// Add Another Device… on the ready screen: the pairing code, then entering a code instead.
    @MainActor private func showAddDevice(_ app: XCUIApplication) throws {
        let add = app.buttons["Add Another Device…"]
        for _ in 0..<4 where !add.isHittable { app.swipeUp() }
        add.tap()
        try require(app.navigationBars["Add Device"], app: app, timeout: 10)
        try shot(app, "add-device-default")
        let enterCode = app.buttons["Enter Code Instead…"]
        if enterCode.waitToAppear(timeout: 10) {
            enterCode.tap()
            try shot(app, "add-device-enter-code")
        }
        app.navigationBars["Add Device"].buttons["Cancel"].tap()
        try tapButton("Done", in: app)
    }

    /// Settings pages that show the connection.
    @MainActor private func captureSettingsWhenConnected(_ app: XCUIApplication) throws {
        if isPad { try require(app.buttons["New Entry"].firstMatch, app: app, timeout: 15) }
        NavigationTestSupport.openSettings(app)
        try tapButton("Sync", in: app)
        try require(app.buttons["Sync Now"], app: app, timeout: 15)
        try shot(app, "settings-sync-connected")
        // Devices is a section of Sync, below Server, and Stop Syncing… ends the pane.
        let stop = app.buttons["Stop Syncing…"].firstMatch
        for _ in 0..<6 where !(stop.exists && stop.isHittable) { app.swipeUp() }
        try shot(app, "settings-devices-connected")
        try tapButton("Stop Syncing…", in: app)
        try shot(app, "stop-syncing-default")
        // The confirmation has no Cancel button: a tap outside it closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.75)).tap()
        goBack(app)
        try tapButton("Agent Access", in: app)
        try shot(app, "settings-agent-access-connected")
    }
}
