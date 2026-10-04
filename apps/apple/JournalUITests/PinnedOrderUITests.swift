import JournalCore
import UIKit
import XCTest

/// Pinned entries, journal order and the journal a template's entry goes to (docs/design/pinned-entries.md,
/// journal-order.md, template-journal-choice-2026-10-03.md): one journey each.
final class PinnedOrderUITests: XCTestCase {
    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var phrase = ""
    private var dataRoot: URL?

    /// Pin from a row's leading swipe: the entry moves into a Pinned section above the months, in its journal and in
    /// All Entries, and says so to VoiceOver. Unpin Entry in its menu puts it back.
    @MainActor func testPinningMovesAnEntryIntoPinnedAndBack() async throws {
        let app = try await launch()
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Work", app: app)
        let interview = row("Interview notes", app: app)
        XCTAssertTrue(interview.waitToAppear(timeout: 10))
        XCTAssertFalse(app.staticTexts["Pinned"].exists)
        interview.swipeRight()
        let pin = app.buttons["Pin"].firstMatch
        XCTAssertTrue(pin.waitToAppear(timeout: 5))
        pin.tap()
        XCTAssertTrue(app.staticTexts["Pinned"].firstMatch.waitToAppear(timeout: 10), "A Pinned section appears")
        let pinnedRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND value == %@", "Interview notes", "Pinned")
        ).firstMatch
        XCTAssertTrue(pinnedRow.waitToAppear(timeout: 5), "The row's value says Pinned")
        assertEventually(
            self.row("Interview notes", app: app).frame.minY < self.row("Standup", app: app).frame.minY,
            "The older pinned entry is listed above the newer one")
        capture(app, "Pinned section in a journal")

        NavigationTestSupport.selectCollection("All Entries", app: app)
        XCTAssertTrue(app.staticTexts["Pinned"].firstMatch.waitToAppear(timeout: 10), "Pinned in All Entries too")
        let pinnedAll = row("Interview notes", app: app)
        XCTAssertTrue(pinnedAll.waitToAppear(timeout: 5))
        pinnedAll.press(forDuration: 1.2)
        let unpin = app.buttons["Unpin Entry"].firstMatch
        XCTAssertTrue(unpin.waitToAppear(timeout: 5))
        unpin.tap()
        XCTAssertTrue(app.staticTexts["Pinned"].firstMatch.waitToDisappear(timeout: 10), "Unpinned, it leaves Pinned")
    }

    /// Edit, drag Travel above Default with its handle, Done, relaunch: the order stays, and Move Entry… lists the
    /// journals in the same order.
    @MainActor func testReorderingJournalsInEditModeLastsAndIsUsedEverywhere() async throws {
        var app = try await launch()
        defer { app.terminate() }
        NavigationTestSupport.showJournals(app)
        let list = app.collectionViews["Journals"]
        XCTAssertEqual(journalOrder(list), ["Default", "Home", "Travel", "Work"], "By name before any move")
        app.buttons["Edit"].firstMatch.tap()
        let handle = list.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Reorder", "Travel")
        ).firstMatch
        XCTAssertTrue(handle.waitToAppear(timeout: 5), "Edit shows reorder handles")
        XCTAssertTrue(list.buttons.matching(NSPredicate(format: "label == %@", "Journal Actions")).firstMatch.exists)
        capture(app, "Journals in edit mode")
        let target = list.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Default"))
            .firstMatch
        handle.press(forDuration: 0.4, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        assertEventually(self.journalOrder(list), equals: ["Travel", "Default", "Home", "Work"], "Travel moved up")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit"].firstMatch.waitToAppear(timeout: 5))

        app.terminate()
        app = try relaunch()
        NavigationTestSupport.showJournals(app)
        assertEventually(
            self.journalOrder(app.collectionViews["Journals"]), equals: ["Travel", "Default", "Home", "Work"],
            "The order lasts after relaunching")

        NavigationTestSupport.openEntry("Standup", journal: "Work", app: app)
        let actions = app.buttons["Entry Actions"].firstMatch
        XCTAssertTrue(actions.waitToAppear(timeout: 10))
        actions.tap()
        let move = app.buttons["Move Entry…"].firstMatch
        XCTAssertTrue(move.waitToAppear(timeout: 5))
        move.tap()
        let travel = app.buttons["Travel"].firstMatch
        XCTAssertTrue(travel.waitToAppear(timeout: 10))
        let destinations = ["Travel", "Default", "Home"].map { app.buttons[$0].firstMatch.frame.minY }
        XCTAssertEqual(destinations, destinations.sorted(), "Move Entry… lists the journals in the same order")
        app.buttons["Cancel"].firstMatch.tap()
    }

    /// A template's New Entry In ▸ offers the journal that uses it as its Default Template first; choosing another
    /// journal files the entry there and opens it in that journal.
    @MainActor func testANewEntryFromATemplateGoesToTheChosenJournal() async throws {
        let app = try await launch()
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Templates", app: app)
        let template = app.staticTexts["Weekly review"].firstMatch
        XCTAssertTrue(template.waitToAppear(timeout: 10))
        template.press(forDuration: 1.2)
        let submenu = app.buttons["New Entry In"].firstMatch
        XCTAssertTrue(submenu.waitToAppear(timeout: 5))
        submenu.tap()
        let home = app.buttons["Home"].firstMatch
        let travel = app.buttons["Travel"].firstMatch
        XCTAssertTrue(travel.waitToAppear(timeout: 5))
        XCTAssertLessThan(home.frame.minY, app.buttons["Default"].firstMatch.frame.minY, "Home uses the template")
        capture(app, "New Entry In menu")
        travel.tap()
        let body = app.textViews["Entry text"]
        let filled = NSPredicate(format: "value CONTAINS %@", "What went well?")
        XCTAssertEqual(
            Waiting.wait(for: XCTNSPredicateExpectation(predicate: filled, object: body), timeout: 10), .completed)
        if !isPad {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Travel"].waitToAppear(timeout: 5), "Back leads to the chosen journal")
        }
    }

    // MARK: Support

    @MainActor private func row(_ title: String, app: XCUIApplication) -> XCUIElement {
        app.staticTexts[title].firstMatch
    }
    /// The journals of the Journals list, top to bottom.
    @MainActor private func journalOrder(_ list: XCUIElement) -> [String] {
        let names = ["Default", "Home", "Travel", "Work"]
        let rows = names.map { name in
            (name, list.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch)
        }
        guard rows.allSatisfy({ $0.1.exists }) else { return [] }
        return rows.sorted { $0.1.frame.minY < $1.1.frame.minY }.map(\.0)
    }
    /// Journals Default (the oldest), Home, Travel and Work; in Work "Interview notes" (older) and "Standup"; and the
    /// template "Weekly review", Home's Default Template. The last journal opened is Default.
    @MainActor private func launch() async throws -> XCUIApplication {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PinOrder-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root, key: key)
        let template = JournalItem(
            kind: "template", title: "Weekly review", document: JournalDocument(markdown: "What went well?"))
        try await store.save(template)
        let start = Date().addingTimeInterval(-3_600)
        var journals: [JournalItem] = []
        for (index, name) in ["Default", "Home", "Travel", "Work"].enumerated() {
            var journal = JournalItem(kind: "journal", title: name, date: start.addingTimeInterval(Double(index) * 60))
            if name == "Home" { journal.defaultTemplateID = template.id }
            try await store.save(journal)
            journals.append(journal)
        }
        try await store.save(
            JournalItem(
                kind: "entry", journalID: journals[3].id, title: "Interview notes", document: .plain("Three questions"),
                date: Date().addingTimeInterval(-86_400 * 3)))
        try await store.save(
            JournalItem(
                kind: "entry", journalID: journals[3].id, title: "Standup", document: .plain("Nothing blocking")))
        try await store.close()
        try JournalCoding.encoder().encode(Configuration(recovery: recovery, lastJournalID: journals[0].id))
            .write(to: root.appendingPathComponent("configuration.json"))
        XCUIDevice.shared.orientation = .portrait
        dataRoot = root
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launch()
        unlock(app)
        NavigationTestSupport.showJournals(app)
        return app
    }
    @MainActor private func relaunch() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = try XCTUnwrap(dataRoot).path
        app.launch()
        // After the first unlock the device keeps its key, so the journals open without asking again.
        if app.secureTextFields["Recovery Key"].waitToAppear(timeout: 5) { unlock(app) }
        return app
    }
    @MainActor private func unlock(_ app: XCUIApplication) {
        let field = app.secureTextFields["Recovery Key"]
        XCTAssertTrue(field.waitToAppear(timeout: 15))
        field.tap()
        field.typeText(phrase)
        app.buttons["Unlock"].tap()
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
