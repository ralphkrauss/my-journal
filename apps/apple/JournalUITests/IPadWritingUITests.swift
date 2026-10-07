import JournalCore
import UIKit
import XCTest

/// Writing beside the entries list on iPad, and Add Link on iPhone and iPad.
final class IPadWritingUITests: XCTestCase {
    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Only the writing controls above the keyboard take touches. An entry row beside them, in the same band, opens
    /// with one tap, as in Notes.
    @MainActor func testEntryRowBesideTheWritingControlsOpens() async throws {
        try XCTSkipUnless(isPad, "The entries list shows beside the editor only on iPad.")
        let app = try await launchWithEntries(count: 12)
        defer { app.terminate() }
        // The entry at the top of the list, well above the keyboard.
        let names = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Row '"))
        XCTAssertTrue(names.firstMatch.waitToAppear(timeout: 10))
        let first = try XCTUnwrap(names.allElementsBoundByIndex.min { $0.frame.minY < $1.frame.minY })
        let opened = first.label
        first.tap()
        XCTAssertTrue(waitForTitle(opened, app: app))
        let body = app.textViews["Entry text"]
        body.tap()
        let formatting = app.buttons["Formatting"].firstMatch
        XCTAssertTrue(formatting.waitToAppear(timeout: 5))
        // Rows in the list column, at the height of the controls but beside them.
        let band = formatting.frame.midY
        let rows = app.cells.allElementsBoundByIndex.filter {
            $0.frame.minY < band - 4 && $0.frame.maxY > band + 4 && $0.frame.maxX < formatting.frame.minX
                && $0.frame.maxX < body.frame.minX + 1
        }
        let row = try XCTUnwrap(rows.first, "An entry row lies beside the controls.")
        let name = row.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Row '")).firstMatch.label
        XCTAssertNotEqual(name, opened)
        capture(app, "Entry row beside the writing controls")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: row.frame.midX, dy: band)).tap()
        XCTAssertTrue(waitForTitle(name, app: app), "The row beside the controls opened.")
        // The controls themselves still work.
        body.tap()
        formatting.tap()
        XCTAssertTrue(app.buttons["Bold"].firstMatch.waitToAppear(timeout: 5), "Formatting opens from Aa.")
    }

    /// Add Link opens ready for the address, from Formatting’s Insert menu and from ⌘K, and Return
    /// adds a valid link.
    @MainActor func testAddLinkFocusesTheLinkField() async throws {
        let app = try await launchWithEntries(count: 1)
        defer { app.terminate() }
        app.staticTexts["Row 01"].firstMatch.tap()
        XCTAssertTrue(waitForTitle("Row 01", app: app))
        let body = app.textViews["Entry text"]
        body.tap()
        app.buttons["Formatting"].firstMatch.tap()
        let insert = app.buttons["Insert"].firstMatch
        XCTAssertTrue(insert.waitToAppear(timeout: 5))
        insert.tap()
        app.buttons["Add Link…"].firstMatch.tap()
        let link = app.textFields["Link"]
        XCTAssertTrue(link.waitToAppear(timeout: 5))
        XCTAssertTrue(hasKeyboardFocus(link), "Insert ▸ Add Link… focuses the Link field.")
        capture(app, "Add Link from Formatting")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(link.waitToDisappear(timeout: 5))
        // Closing Add Link returns to the text, where ⌘K opens it again. No tap first: a tap can show the edit menu,
        // which takes the next keys, so ⌘K would type a K. (LinkInsertionTests checks that ⌘K takes the selection
        // as the link's text.)
        // The first key right after the sheet closes can arrive before the text has the keyboard again, so ⌘K is
        // pressed a second time if the first one wasn't received.
        XCTAssertTrue(hasKeyboardFocus(body))
        // The simulator connects its hardware keyboard to a newly launched app with the first key pressed, which
        // loses that key's modifiers: a first ⌘K types a K, however long after the sheet closed. Shift alone types
        // nothing.
        body.typeKey(XCUIKeyboardKey.shift.rawValue, modifierFlags: [])
        body.typeKey("k", modifierFlags: .command)
        if !link.waitToAppear(timeout: 2) { body.typeKey("k", modifierFlags: .command) }
        XCTAssertTrue(link.waitToAppear(timeout: 5))
        XCTAssertTrue(hasKeyboardFocus(link), "⌘K focuses the Link field.")
        capture(app, "Add Link from Command-K")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(link.waitToDisappear(timeout: 5))

        // Return with an address that isn't valid keeps it ready to correct; with a valid one, Return adds the link
        // and closes the sheet, as in Notes.
        app.buttons["Formatting"].firstMatch.tap()
        XCTAssertTrue(insert.waitToAppear(timeout: 5))
        insert.tap()
        app.buttons["Add Link…"].firstMatch.tap()
        XCTAssertTrue(link.waitToAppear(timeout: 5))
        link.typeText("not a link\n")
        XCTAssertTrue(app.staticTexts["Enter a valid web or email address."].waitToAppear(timeout: 5))
        XCTAssertTrue(hasKeyboardFocus(link), "The address stays ready to correct.")
        link.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        link.typeText("example.com/sprints\n")
        XCTAssertTrue(link.waitToDisappear(timeout: 5), "Return adds the link.")
        NavigationTestSupport.readingButton("View Source", app: app).tap()
        let linked = NSPredicate(format: "value CONTAINS %@", "https://example.com/sprints")
        XCTAssertEqual(
            Waiting.wait(for: XCTNSPredicateExpectation(predicate: linked, object: body), timeout: 5), .completed,
            "The link was added.")
    }

    // MARK: - Support

    @MainActor private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (element.value(forKey: "hasKeyboardFocus") as? Bool) == true },
            object: element)
        return Waiting.wait(for: focused, timeout: 3) == .completed
    }
    @MainActor private func waitForTitle(_ title: String, app: XCUIApplication) -> Bool {
        let field = NavigationTestSupport.title(app)
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title), object: field)
        return Waiting.wait(for: shown, timeout: 10) == .completed
    }
    @MainActor private func launchWithoutEncryption() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        if #available(iOS 17.0, *) { XCUIDevice.shared.appearance = .light }
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        XCTAssertTrue(app.buttons["Continue Without Encryption"].waitToAppear(timeout: 5))
        app.buttons["Continue Without Encryption"].tap()
        return app
    }
    /// A journal of `count` short entries named “Row 01” onwards, open in portrait.
    @MainActor private func launchWithEntries(count: Int) async throws -> XCUIApplication {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IPadWriting-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        try await store.save(journal)
        for index in 1...count {
            var entry = JournalItem(kind: "entry", journalID: journal.id, title: String(format: "Row %02d", index))
            entry.document = JournalDocument(markdown: "Some words to select in row \(index).")
            try await store.save(entry)
        }
        try await store.close()
        try JournalCoding.encoder().encode(Configuration(recovery: recovery, lastJournalID: journal.id))
            .write(to: root.appendingPathComponent("configuration.json"))
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launch()
        let field = app.secureTextFields["Recovery Key"]
        XCTAssertTrue(field.waitToAppear(timeout: 15))
        field.tap()
        field.typeText(phrase)
        app.buttons["Unlock"].tap()
        NavigationTestSupport.selectCollection(journal.title, app: app)
        return app
    }
    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = (isPad ? "iPad: " : "iPhone: ") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
