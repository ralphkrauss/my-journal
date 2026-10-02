import JournalCore
import XCTest

final class RotationUITests: XCTestCase {
    @MainActor func testRotationWhileWritingPreservesEntryAcrossRelaunch() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Rotation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Daily notes")
        try await store.save(journal)
        try await store.save(entry)
        try await store.close()
        try JournalCoding.encoder().encode(
            Configuration(recovery: recovery, lastJournalID: journal.id, lastEntryID: entry.id)
        ).write(to: root.appendingPathComponent("configuration.json"))
        let app = XCUIApplication()
        let originalOrientation = XCUIDevice.shared.orientation
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = originalOrientation
        }
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitForExistence(timeout: 15))
        app.secureTextFields["Recovery Key"].tap()
        app.secureTextFields["Recovery Key"].typeText(phrase)
        app.buttons["Unlock"].tap()
        NavigationTestSupport.openEntry(entry.title, journal: journal.title, app: app)
        let body = app.textViews["Entry text"]
        capture(app, "Empty body beneath the title")
        body.tap()
        body.typeText("Before rotation. ")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        XCTAssertEqual(body.value as? String, "Before rotation. ")
        app.typeText("After rotation.")
        capture(app, "Landscape writing with keyboard")
        let title = NavigationTestSupport.title(app)
        for _ in 0..<8 {
            if title.frame.minY >= body.frame.minY + 4, title.frame.maxY <= body.frame.maxY - 4 { break }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: body.frame.maxX - 16, dy: body.frame.minY + 12))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: body.frame.maxX - 16, dy: body.frame.maxY - 12))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertGreaterThanOrEqual(title.frame.minY, body.frame.minY + 4)
        XCTAssertLessThanOrEqual(title.frame.maxY, body.frame.maxY - 4)
        capture(app, "Complete title after scrolling upward")
        title.tap()
        XCTAssertTrue(app.keyboards.buttons["Next:"].waitForExistence(timeout: 5))
        // Return, as the Next key sends it; the on-screen key is hidden once the simulator has seen a hardware
        // keyboard, which an earlier test's key presses cause.
        title.typeText("\n")
        app.typeText(" Again.")
        capture(app, "Continued body writing after title focus and Next")
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.frame.height > app.frame.width }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
        let expected = "Before rotation. After rotation. Again."
        XCTAssertEqual(body.value as? String, expected)
        XCTAssertEqual(NavigationTestSupport.title(app).value as? String, entry.title)
        capture(app, "Portrait writing retained after rotation")
        NavigationTestSupport.showJournals(app)
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry(entry.title, journal: journal.title, app: app)
        XCTAssertEqual(body.value as? String, expected)
        let reopened = try JournalStore(directory: root, key: key)
        let entries = try await reopened.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, entry.id)
        XCTAssertEqual(entries.first?.journalID, journal.id)
        XCTAssertEqual(entries.first?.title, entry.title)
        XCTAssertEqual(entries.first?.document.blocks.map { $0.runs.map(\.text).joined() }, [expected])
        try await reopened.close()
    }

    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
        let lastEntryID: UUID
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let geometry = XCTAttachment(
            string: """
                App: \(app.frame)
                Navigation: \(app.navigationBars.firstMatch.frame)
                Header: \(app.descendants(matching: .any).matching(identifier: "Entry header").firstMatch.frame)
                Title: \(NavigationTestSupport.title(app).frame)
                Body: \(app.textViews["Entry text"].frame)
                Keyboard: \(app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame : .zero)
                """)
        geometry.name = name + " geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
