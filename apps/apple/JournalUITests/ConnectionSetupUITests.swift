import JournalCore
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

    /// A server whose journals are not encrypted (set up by an earlier version) is never joined by a device that has
    /// no journals: the refusal says what to do, and nothing is created or sent.
    @MainActor func testANewDeviceIsRefusedByAServerWithoutEncryption() async throws {
        let (address, code) = try server("PLAIN")
        // An earlier version's device sets the server up without a password.
        _ = try await ServerClient(address: address).initialize(
            code: code, envelope: RecoveryEnvelope(salt: "", wrappedKey: "", iterations: 0, formatVersion: 4),
            recoverySecret: VaultCrypto.random(32).map { String(format: "%02x", $0) }
                .joined(), deviceName: "Fixture Mac")
        let app = launchFresh()
        chooseServer(address, app: app)
        // The app names the server by its host and port.
        let host = address.replacingOccurrences(of: "http://", with: "")
        let refusal =
            host.prefix(1).uppercased() + host.dropFirst()
            + " doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption."
        XCTAssertTrue(app.staticTexts[refusal].waitToAppear(timeout: 10))
        attachScreen(app, name: "A server without encryption is refused")
        XCTAssertFalse(app.navigationBars["Add This Device"].exists)
        XCTAssertFalse(app.navigationBars["Choose a Master Password"].exists)
        app.terminate()
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
