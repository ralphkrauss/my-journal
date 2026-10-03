import JournalCore
import UIKit
import XCTest

/// Actions that move the list to another collection show that collection, with its own title and actions: New Entry
/// from Templates or Recently Deleted, Merge Into…, Delete Journal… and Restore Journal.
final class CollectionNavigationUITests: XCTestCase {
    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// New Entry from Templates and from Recently Deleted opens one new entry in the default journal. It used to save
    /// an empty entry without opening it, leaving a blank page still titled Templates or Recently Deleted.
    @MainActor func testNewEntryFromTemplatesAndRecentlyDeletedOpensIt() async throws {
        let app = try await launch()
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Templates", app: app)
        XCTAssertTrue(app.staticTexts["Weekly review"].firstMatch.waitToAppear(timeout: 10))
        try newEntry(app, from: "Templates")

        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        let deleted = app.staticTexts["Lunch"].firstMatch
        XCTAssertTrue(deleted.waitToAppear(timeout: 10))
        // Beside the list, an open deleted entry closes for the new one.
        if !usesStack {
            deleted.tap()
            XCTAssertTrue(app.buttons["Restore and Move…"].firstMatch.waitToAppear(timeout: 10))
        }
        try newEntry(app, from: "Recently Deleted")

        NavigationTestSupport.selectCollection("Default", app: app)
        let empty = app.staticTexts.matching(NSPredicate(format: "label == %@", "No additional text"))
        XCTAssertTrue(empty.firstMatch.waitToAppear(timeout: 10))
        assertEventually(empty.count, equals: 2, "Each New Entry made one entry.")
    }

    /// On iPhone, Merge Into… shows the journal the entries went to, Delete Journal… returns to Journals, and Restore
    /// Journal shows the restored journal. Each used to leave a page for a journal that wasn't shown, titled
    /// "Untitled Journal" or "Recently Deleted", whose actions still worked.
    @MainActor func testJournalPageFollowsMergeDeleteAndRestore() async throws {
        try XCTSkipUnless(usesStack, "Beside the list, the sidebar's selection shows the journal.")
        let app = try await launch()
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Work", app: app)
        XCTAssertTrue(app.staticTexts["Work plan"].firstMatch.waitToAppear(timeout: 10))
        journalAction("Merge Into…", app: app)
        let merge = app.navigationBars["Merge “Work”"]
        XCTAssertTrue(merge.waitToAppear(timeout: 5))
        app.buttons["Travel"].firstMatch.tap()
        merge.buttons["Merge"].tap()
        XCTAssertTrue(merge.waitToDisappear(timeout: 10))
        XCTAssertTrue(app.navigationBars["Travel"].waitToAppear(timeout: 10))
        XCTAssertTrue(app.staticTexts["Work plan"].firstMatch.waitToAppear(timeout: 5))
        capture(app, "After Merge Into")

        journalAction("Delete Journal…", app: app)
        let deletion = app.alerts["Delete “Travel”?"]
        XCTAssertTrue(deletion.waitToAppear(timeout: 5))
        deletion.buttons["Delete"].tap()
        XCTAssertTrue(app.collectionViews["Journals"].waitToAppear(timeout: 10))
        XCTAssertFalse(app.navigationBars["Untitled Journal"].exists)
        XCTAssertFalse(app.collectionViews["Journals"].staticTexts["Travel"].exists)
        capture(app, "After Delete Journal")

        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        let journal = app.cells.containing(.staticText, identifier: "Travel").firstMatch
        XCTAssertTrue(journal.waitToAppear(timeout: 10))
        journal.tap()
        app.buttons["Restore Journal…"].tap()
        let restore = app.buttons["Restore Journal"]
        XCTAssertTrue(restore.waitToAppear(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.navigationBars["Travel"].waitToAppear(timeout: 10))
        XCTAssertTrue(app.staticTexts["Work plan"].firstMatch.waitToAppear(timeout: 5))
        XCTAssertFalse(app.navigationBars["Recently Deleted"].exists)
        capture(app, "After Restore Journal")
        // The entry deleted on its own is still in Recently Deleted.
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        XCTAssertTrue(app.staticTexts["Lunch"].firstMatch.waitToAppear(timeout: 10))
    }

    /// Restore and Move's title fits beside its buttons. Its confirm button had the same long label and truncated it.
    @MainActor func testRestoreAndMoveTitleFits() async throws {
        let app = try await launch()
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        let deleted = app.staticTexts["Lunch"].firstMatch
        XCTAssertTrue(deleted.waitToAppear(timeout: 10))
        deleted.tap()
        let action = NavigationTestSupport.readingButton("Restore and Move…", app: app)
        action.tap()
        let bar = app.navigationBars["Restore and Move"]
        XCTAssertTrue(bar.waitToAppear(timeout: 5))
        let title = bar.staticTexts["Restore and Move"]
        XCTAssertTrue(title.exists)
        let font = UIFont.preferredFont(forTextStyle: .headline)
        let needed = ("Restore and Move" as NSString).size(withAttributes: [.font: font]).width
        capture(app, "Restore and Move")
        XCTAssertGreaterThanOrEqual(title.frame.width, needed - 2, "The title isn't truncated.")
        XCTAssertTrue(bar.buttons["Restore"].exists)
    }

    // MARK: - Support

    /// iPhone shows one screen at a time; iPad shows the list beside the entry.
    @MainActor private var usesStack: Bool { !isPad }
    @MainActor private func newEntry(_ app: XCUIApplication, from collection: String) throws {
        let create = app.buttons["New Entry"].firstMatch
        XCTAssertTrue(create.waitToAppear(timeout: 5))
        create.tap()
        let title = NavigationTestSupport.title(app)
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (title.value(forKey: "hasKeyboardFocus") as? Bool) == true },
            object: title)
        let opened = Waiting.wait(for: focused, timeout: 10) == .completed
        capture(app, "New Entry from \(collection)")
        XCTAssertTrue(opened, "New Entry from \(collection) opens the entry with its title ready for typing.")
        XCTAssertFalse(app.navigationBars[collection].exists, "The new entry shows where it was filed.")
    }
    @MainActor private func journalAction(_ name: String, app: XCUIApplication) {
        let menu = app.navigationBars.buttons["Journal Actions"].firstMatch
        XCTAssertTrue(menu.waitToAppear(timeout: 5))
        menu.tap()
        let action = app.buttons[name].firstMatch
        XCTAssertTrue(action.waitToAppear(timeout: 5))
        action.tap()
    }
    /// Journals Default (the oldest), Travel and Work; "Work plan" in Work; "Lunch", deleted from Default on its own;
    /// and the template "Weekly review".
    @MainActor private func launch() async throws -> XCUIApplication {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Collections-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root, key: key)
        let start = Date().addingTimeInterval(-3_600)
        let journals = ["Default", "Travel", "Work"].enumerated().map { index, name in
            JournalItem(kind: "journal", title: name, date: start.addingTimeInterval(Double(index) * 60))
        }
        for journal in journals { try await store.save(journal) }
        try await store.save(JournalItem(kind: "entry", journalID: journals[2].id, title: "Work plan"))
        var lunch = JournalItem(kind: "entry", journalID: journals[0].id, title: "Lunch")
        lunch.deletedAt = Date()
        try await store.save(lunch)
        try await store.save(
            JournalItem(
                kind: "template", title: "Weekly review", document: JournalDocument(markdown: "What went well?")))
        try await store.close()
        try JournalCoding.encoder().encode(Configuration(recovery: recovery, lastJournalID: journals[0].id))
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
        NavigationTestSupport.showJournals(app)
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
