import XCTest

/// Setting up a new server from the app, one step at a time (docs/design/connection-onboarding.md), and joining it
/// from another device. scripts/test-native-pairing.sh starts the disposable servers.
final class ConnectionSetupUITests: XCTestCase {
    private let password = "Setup UI fixture password"

    @MainActor func testSetUpEncryptedServerThenSignInOnAnotherDevice() throws {
        let (address, code) = try server("ENCRYPTED")
        let app = launchFresh()
        chooseServer(address, app: app)
        let setUp = app.navigationBars["Set Up Server"]
        XCTAssertTrue(setUp.waitToAppear(timeout: 10))
        let field = app.textFields["Setup Code"]
        // A short code is explained on Continue, not by a button that stays disabled.
        field.tap()
        field.typeText("2345")
        setUp.buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["Enter the 6-character setup code from your server."].waitToAppear(timeout: 5))
        attachScreen(app, name: "Setup code too short")
        // A wrong code is reported on this step, before anything else is asked.
        replaceText(in: field, with: wrongCode(code).lowercased())
        setUp.buttons["Continue"].tap()
        XCTAssertTrue(
            app.staticTexts["That setup code isn’t correct. Check the code on your server."].waitToAppear(
                timeout: 10))
        // Typed in lower case without the hyphen, the code reads as the server shows it.
        replaceText(in: field, with: code.lowercased().filter { $0 != "-" })
        XCTAssertEqual(field.value as? String, formatted(code))
        attachScreen(app, name: "Setup code formatted")
        setUp.buttons["Continue"].tap()

        let protect = app.navigationBars["Protect Your Journals"]
        XCTAssertTrue(protect.waitToAppear(timeout: 10))
        attachScreen(app, name: "Protect your journals")
        protect.buttons["Continue"].tap()

        let choose = app.navigationBars["Choose a Master Password"]
        XCTAssertTrue(choose.waitToAppear(timeout: 10))
        let newPassword = app.secureTextFields["Master Password"]
        XCTAssertTrue(newPassword.waitToAppear(timeout: 5))
        newPassword.tap()
        newPassword.typeText(password)
        let verify = app.secureTextFields["Verify"]
        verify.tap()
        verify.typeText(password + " typo")
        choose.buttons["Set Up"].tap()
        XCTAssertTrue(app.staticTexts["The passwords don’t match."].waitToAppear(timeout: 5))
        attachScreen(app, name: "Passwords don't match")
        replaceText(in: verify, with: password)
        choose.buttons["Set Up"].tap()

        XCTAssertTrue(app.staticTexts["Server Is Ready"].waitToAppear(timeout: 30))
        let addAnother = reveal(app.buttons["Add Another Device…"], in: app)
        attachScreen(app, name: "Server is ready")
        addAnother.tap()
        XCTAssertTrue(app.navigationBars["Add Device"].waitToAppear(timeout: 10))
        let enterCode = app.buttons["Enter Code Instead…"]
        if enterCode.waitToAppear(timeout: 10) { enterCode.tap() }
        XCTAssertTrue(
            app.staticTexts["On the new device, choose Connect to a Server, then Add This Device."].waitToAppear(
                timeout: 10))
        // This test server is reached over plain HTTP, which only the Mac's own local server explains.
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "this Mac")).firstMatch.exists)
        app.navigationBars["Add Device"].buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["New Entry"].firstMatch.waitToAppear(timeout: 10))
        app.terminate()

        // Another device signs in with the password chosen above.
        let other = launchFresh()
        chooseServer(address, app: other)
        let signIn = other.navigationBars["Enter Master Password"]
        XCTAssertTrue(signIn.waitToAppear(timeout: 10))
        let phrase = other.secureTextFields["Master Password"]
        phrase.tap()
        phrase.typeText("Not the fixture password")
        signIn.buttons["Sign In"].tap()
        XCTAssertTrue(other.staticTexts["That password isn’t correct."].waitToAppear(timeout: 30))
        attachScreen(other, name: "Wrong password on sign in")
        XCTAssertTrue(reveal(other.staticTexts["Your journals will download to this device."], in: other).exists)
        replaceText(in: phrase, with: password)
        signIn.buttons["Sign In"].tap()
        XCTAssertTrue(other.buttons["New Entry"].firstMatch.waitToAppear(timeout: 30))
        other.terminate()
    }

    @MainActor func testSetUpServerWithoutEncryptionThenAddAnotherDevice() throws {
        let (address, code) = try server("PLAIN")
        let app = launchFresh()
        chooseServer(address, app: app)
        let setUp = app.navigationBars["Set Up Server"]
        XCTAssertTrue(setUp.waitToAppear(timeout: 10))
        let field = app.textFields["Setup Code"]
        field.tap()
        field.typeText(code)
        setUp.buttons["Continue"].tap()
        let protect = app.navigationBars["Protect Your Journals"]
        XCTAssertTrue(protect.waitToAppear(timeout: 10))
        reveal(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don’t Encrypt")).firstMatch, in: app)
            .tap()
        attachScreen(app, name: "Don't encrypt")
        // No password follows, so the button says what happens next.
        protect.buttons["Set Up"].tap()
        XCTAssertTrue(app.staticTexts["Server Is Ready"].waitToAppear(timeout: 30))
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "You can also sign in")).firstMatch
                .exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["New Entry"].firstMatch.waitToAppear(timeout: 10))
        app.terminate()

        // Without a password, another device is added with a code or a recovery code.
        let other = launchFresh()
        chooseServer(address, app: other)
        let add = other.navigationBars["Add This Device"]
        XCTAssertTrue(add.waitToAppear(timeout: 10))
        XCTAssertTrue(other.staticTexts["pairing-code"].waitToAppear(timeout: 10))
        attachScreen(other, name: "Add this device to a server without encryption")
        reveal(other.buttons["Use a Recovery Code Instead…"], in: other).tap()
        XCTAssertTrue(other.navigationBars["Use a Recovery Code"].waitToAppear(timeout: 10))
        other.navigationBars["Use a Recovery Code"].buttons.element(boundBy: 0).tap()
        // Back on Add This Device, a new code replaces the withdrawn one.
        XCTAssertTrue(other.staticTexts["pairing-code"].waitToAppear(timeout: 10))
        other.terminate()
    }

    // MARK: Support

    /// At the largest text sizes an element can be below the fold, where a list hasn't created it yet.
    @MainActor @discardableResult private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        return element
    }

    private func server(_ kind: String) throws -> (String, String) {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["JOURNAL_TEST_\(kind)_SETUP_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let code = environment["JOURNAL_TEST_\(kind)_SETUP_CODE"], !code.isEmpty
        else {
            throw XCTSkip("Run scripts/test-native-pairing.sh for the disposable-server setup check.")
        }
        return (address, code)
    }
    @MainActor private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        return app
    }
    @MainActor private func chooseServer(_ address: String, app: XCUIApplication) {
        let connect = app.buttons["Connect to a Server…"]
        XCTAssertTrue(connect.waitToAppear(timeout: 15))
        connect.tap()
        let field = app.textFields["Server Address"]
        XCTAssertTrue(field.waitToAppear(timeout: 5))
        field.tap()
        field.typeText(address)
        app.navigationBars["Connect to a Server"].buttons["Continue"].tap()
    }
    @MainActor private func replaceText(in field: XCUIElement, with text: String) {
        // The cursor goes to the end, then everything before it is deleted.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2) + text)
    }
    private func formatted(_ code: String) -> String {
        let plain = code.uppercased().filter { $0 != "-" }
        return String(plain.prefix(3)) + "-" + String(plain.dropFirst(3))
    }
    /// A well-formed code that isn't the server's.
    private func wrongCode(_ code: String) -> String {
        let plain = code.uppercased().filter { $0 != "-" }
        return (plain.first == "A" ? "B" : "A") + String(plain.dropFirst())
    }
    @MainActor private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
