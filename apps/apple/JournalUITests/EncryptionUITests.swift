import JournalCore
import XCTest

/// Encrypt Your Journals for a library an earlier version made without encryption
/// (docs/design/1-1-encryption-and-passwords.md §3.4): the journals aren't reachable at first, choosing a password
/// and Encrypt leads through Your Journals Are Encrypted to the same entries, now encrypted. The screen's other
/// states are covered by the model tests.
final class EncryptionUITests: XCTestCase {
    private struct Configuration: Codable {
        let recovery: RecoveryEnvelope
        var recoveryConfirmed = true
        let lastJournalID: UUID
        let lastEntryID: UUID
    }

    /// An unencrypted library of an earlier version, in the data folder itself, with one entry.
    @MainActor private func seedUnencryptedLibrary(_ root: URL) async throws {
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey(), protection: .plaintext)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Written before encryption",
            document: .plain("These words were readable."), date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.save(journal)
        try await store.save(entry)
        try await store.close()
        let configuration = Configuration(recovery: .unprotected, lastJournalID: journal.id, lastEntryID: entry.id)
        try JournalCoding.encoder().encode(configuration).write(to: root.appendingPathComponent("configuration.json"))
    }

    @MainActor func testAnUnencryptedLibraryIsAskedToEncryptBeforeItsJournalsOpen() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Encrypt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await seedUnencryptedLibrary(root)
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Encrypt Your Journals"].waitToAppear(timeout: 15))
        XCTAssertFalse(app.buttons["New Entry"].exists, "The journals aren't reachable at first.")
        XCTAssertFalse(app.buttons["Not Now"].exists, "A library that can be encrypted has no way past the form.")
        capture(app, "1 Encrypt Your Journals")

        let password = app.secureTextFields["Master Password"]
        XCTAssertTrue(password.waitToAppear(timeout: 5))
        let encrypt = app.buttons["Encrypt journals"]
        XCTAssertFalse(encrypt.isEnabled, "Encrypt waits for both fields.")
        password.tap()
        password.typeText("Encryption UI fixture")
        let verify = app.secureTextFields["Verify"]
        verify.tap()
        verify.typeText("Encryption UI typo")
        encrypt.tap()
        XCTAssertTrue(app.staticTexts["The passwords don’t match."].waitToAppear(timeout: 5))
        capture(app, "2 Passwords don't match")
        replaceText(in: verify, with: "Encryption UI fixture")
        encrypt.tap()

        // The journals appear read-only with a notice while the copy is made; a small library can be done before a
        // test sees it, so the notice is captured when it is there and not required.
        if app.staticTexts["Writing is paused while your journals are encrypted."].waitForExistence(timeout: 2) {
            capture(app, "3 Encrypting")
        }
        XCTAssertTrue(app.staticTexts["Your Journals Are Encrypted"].waitToAppear(timeout: 30))
        XCTAssertTrue(
            app.staticTexts[
                "Keep your master password somewhere safe. It is the only way to open your journals on a new device."
            ]
            .exists)
        capture(app, "4 Your journals are encrypted")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["New Entry"].firstMatch.waitToAppear(timeout: 15), "The journals are open.")

        NavigationTestSupport.openSettings(app)
        app.buttons["Privacy"].tap()
        XCTAssertTrue(app.staticTexts["Your Journals Are Encrypted"].waitToAppear(timeout: 10))
        XCTAssertTrue(app.buttons["Change Password…"].exists)
        XCTAssertFalse(app.buttons["Turn On Encryption…"].exists)
        capture(app, "5 Privacy with encryption on")
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
