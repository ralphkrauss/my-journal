import XCTest

/// Turning on encryption for a journal created without it (docs/design/enable-encryption.md).
final class EncryptionUITests: XCTestCase {
    @MainActor func testTurningOnEncryptionForAnExistingJournal() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.openSettings(app)
        app.buttons["Privacy"].tap()
        XCTAssertTrue(app.staticTexts["Encryption Is Off"].waitToAppear(timeout: 10))
        capture(app, "1 Privacy with encryption off")
        app.buttons["Turn On Encryption…"].tap()

        let about = app.navigationBars["Turn On Encryption"]
        XCTAssertTrue(about.waitToAppear(timeout: 10))
        XCTAssertTrue(
            app.staticTexts[
                "Encryption protects your journals on this device. Only your devices can read them. You can’t turn encryption off later."
            ].exists)
        capture(app, "2 Turn On Encryption")
        about.buttons["Continue"].tap()

        let choose = app.navigationBars["Choose a Master Password"]
        XCTAssertTrue(choose.waitToAppear(timeout: 10))
        let turnOn = choose.buttons["Turn On"]
        XCTAssertFalse(turnOn.isEnabled, "Turn On waits for both fields")
        let password = app.secureTextFields["Master Password"]
        XCTAssertTrue(password.waitToAppear(timeout: 5))
        password.tap()
        password.typeText("Encryption UI fixture")
        let verify = app.secureTextFields["Verify"]
        verify.tap()
        verify.typeText("Encryption UI typo")
        turnOn.tap()
        XCTAssertTrue(app.staticTexts["The passwords don’t match."].waitToAppear(timeout: 5))
        capture(app, "3 Passwords don't match")
        replaceText(in: verify, with: "Encryption UI fixture")
        capture(app, "4 Choose a master password")
        turnOn.tap()

        XCTAssertTrue(app.staticTexts["Your Journals Are Encrypted"].waitToAppear(timeout: 30))
        XCTAssertTrue(
            app.staticTexts[
                "Archives and backups made before now aren’t encrypted. Anyone who has them can still read them."
            ]
            .exists)
        capture(app, "5 Your journals are encrypted")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Your Journals Are Encrypted"].waitToAppear(timeout: 10))
        XCTAssertTrue(app.buttons["Change Password…"].exists)
        XCTAssertFalse(app.buttons["Turn On Encryption…"].exists)
        capture(app, "6 Privacy with encryption on")
    }

    @MainActor private func replaceText(in field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + text)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
