import JournalCore
import XCTest

final class WritingWorkflowUITests: XCTestCase {
    @MainActor func testDefaultTemplateWritingScopedSearchAndRelaunchPreserveContent() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Writing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15))
        let recovery = app.secureTextFields["Recovery Key"]
        recovery.tap()
        recovery.typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        NavigationTestSupport.openEntry(fixture.source.title, journal: "Work", app: app)
        createDefaultTemplate(app, journalID: fixture.work.id)
        let create = app.buttons["New Entry"].firstMatch
        XCTAssertTrue(create.waitToAppear(timeout: 15))
        create.tap()
        let title = NavigationTestSupport.title(app)
        let body = app.textViews["Entry text"]
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        assertEventually((body.value as? String ?? "").contains("What did I finish?"))
        capture(app, "New work entry from default template")
        title.tap()
        title.typeText("Monday review")
        NavigationTestSupport.dismissKeyboardTips(app)
        // Typed rather than tapped by its position, which a keyboard tip over the keys turned into a letter key.
        XCTAssertTrue(app.keyboards.buttons["Next:"].waitToAppear(timeout: 5))
        title.typeText("\n")
        app.typeText("Orchid project shipped.\n")
        XCTAssertTrue((body.value as? String ?? "").contains("Orchid project shipped."))
        capture(app, "Answer beneath template prompt with keyboard")
        backToEntries(app)
        search("Orchid", app: app)
        let workRow = app.staticTexts["Monday review"].firstMatch
        XCTAssertTrue(workRow.waitToAppear(timeout: 5))
        XCTAssertFalse(app.staticTexts["Garden notes"].exists)
        capture(app, "Body search limited to Work")
        dismissSearch(app)
        selectJournal("Personal", app: app)
        search("Orchid", app: app)
        let personalRow = app.staticTexts["Garden notes"].firstMatch
        XCTAssertTrue(personalRow.waitToAppear(timeout: 5))
        XCTAssertFalse(workRow.exists)
        capture(app, "Same search limited to Personal")
        dismissSearch(app)
        selectJournal("Work", app: app)
        XCTAssertTrue(workRow.waitToAppear(timeout: 5))
        workRow.tap()
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        assertEventually((body.value as? String ?? "").contains("Orchid project shipped."))
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("Monday review", journal: "Work", app: app)
        XCTAssertEqual(title.value as? String, "Monday review")
        XCTAssertTrue((body.value as? String ?? "").contains("What did I finish?"))
        XCTAssertTrue((body.value as? String ?? "").contains("Orchid project shipped."))
        capture(app, "Template-derived writing after relaunch")
        app.terminate()
        let store = try JournalStore(directory: directory, key: fixture.key)
        let items = try await store.items()
        XCTAssertEqual(items.filter { $0.kind == "template" }.count, 1)
        let template = try XCTUnwrap(items.first { $0.kind == "template" && $0.title == "Daily review" })
        XCTAssertEqual(template.document, fixture.source.document)
        let source = try XCTUnwrap(items.first { $0.id == fixture.source.id })
        XCTAssertEqual(source.document, fixture.source.document)
        let work = try XCTUnwrap(items.first { $0.id == fixture.work.id })
        XCTAssertEqual(work.defaultTemplateID, template.id)
        let personal = try XCTUnwrap(items.first { $0.id == fixture.personal.id })
        XCTAssertEqual(personal.document, fixture.personal.document)
        let written = try XCTUnwrap(items.first { $0.title == "Monday review" })
        XCTAssertEqual(written.journalID, fixture.work.id)
        XCTAssertEqual(written.document.blocks.first, fixture.source.document.blocks.first)
        let answer = try XCTUnwrap(written.document.blocks.dropFirst().first)
        XCTAssertEqual(answer.kind, "paragraph")
        XCTAssertEqual(answer.runs.map(\.text).joined(), "Orchid project shipped.")
        XCTAssertTrue(answer.runs.allSatisfy { !$0.bold && !$0.italic && !$0.underline })
        XCTAssertEqual(items.filter { $0.kind == "entry" }.count, 3)
        try await store.close()
    }

    @MainActor func testMultilineTitlePasteThenNextPreservesWritingAcrossRelaunch() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TitlePaste-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pastedTitle = "Monday\nReview"
        let fixture = try await seed(directory, sourceTitle: pastedTitle)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15))
        app.secureTextFields["Recovery Key"].tap()
        app.secureTextFields["Recovery Key"].typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        NavigationTestSupport.openEntry(fixture.source.title, journal: "Work", app: app)
        let sourceTitle = NavigationTestSupport.title(app)
        sourceTitle.tap()
        sourceTitle.tap()
        try tapEditAction("Select All", app: app)
        try tapEditAction("Copy", app: app)
        backToEntries(app)
        app.buttons["New Entry"].firstMatch.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        title.tap()
        title.press(forDuration: 1)
        try tapEditAction("Paste", app: app)
        let pasted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", pastedTitle), object: title)
        XCTAssertEqual(Waiting.wait(for: pasted, timeout: 5), .completed)
        capture(app, "Multiline title pasted through the native menu")
        XCTAssertTrue(app.keyboards.buttons["Next:"].exists)
        // Return, as the Next key sends it; the on-screen key is hidden once the simulator has seen a hardware
        // keyboard, which an earlier test's key presses cause.
        title.typeText("\n")
        app.typeText("Orchid delivery completed.")
        let body = app.textViews["Entry text"]
        XCTAssertEqual(body.value as? String, "Orchid delivery completed.")
        XCTAssertEqual(title.value as? String, pastedTitle)
        capture(app, "Next moves from pasted title to body")
        backToEntries(app)
        app.terminate()
        app.launch()
        NavigationTestSupport.selectCollection("Work", app: app)
        let row = app.staticTexts[pastedTitle].firstMatch
        XCTAssertTrue(row.waitToAppear(timeout: 10))
        row.tap()
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        assertEventually(title.value as? String, equals: pastedTitle)
        assertEventually(body.value as? String, equals: "Orchid delivery completed.")
        capture(app, "Pasted title and body retained after relaunch")
        app.terminate()
        let store = try JournalStore(directory: directory, key: fixture.key)
        let items = try await store.items()
        let entry = try XCTUnwrap(items.first { $0.title == pastedTitle && $0.id != fixture.source.id })
        XCTAssertEqual(entry.journalID, fixture.work.id)
        XCTAssertEqual(entry.document.blocks.map { $0.runs.map(\.text).joined() }, ["Orchid delivery completed."])
        XCTAssertEqual(items.filter { $0.kind == "entry" }.count, 3)
        try await store.close()
    }

    private enum InteractionError: Error { case missingEditAction }

    @MainActor private func tapEditAction(_ name: String, app: XCUIApplication) throws {
        let action = app.descendants(matching: .any).matching(identifier: name).firstMatch
        for _ in 0..<8 {
            if action.waitToAppear(timeout: 1), action.isHittable {
                action.tap()
                return
            }
            let forward = app.buttons["Forward"]
            guard forward.exists, forward.isHittable else { break }
            forward.tap()
        }
        capture(app, "Missing native edit action: " + name)
        throw InteractionError.missingEditAction
    }

    @MainActor private func createDefaultTemplate(_ app: XCUIApplication, journalID: UUID) {
        let alert = openTemplateAlert(app)
        let cancel = alert.buttons["Cancel"]
        for _ in 0..<4 {
            let label = cancel.staticTexts.firstMatch
            let frame = label.exists ? label.frame : cancel.frame
            if frame.maxY < alert.frame.maxY - 8 { break }
            alert.swipeUp()
        }
        capture(app, "Complete template cancellation action")
        cancel.tap()
        XCTAssertTrue(alert.waitToDisappear(timeout: 5))
        let reopened = openTemplateAlert(app)
        capture(app, "Save existing prompts as a template")
        reopened.buttons["Save"].tap()
        XCTAssertTrue(reopened.waitToDisappear(timeout: 5))
        NavigationTestSupport.selectCollection("Templates", app: app)
        XCTAssertTrue(app.staticTexts["Daily review"].firstMatch.waitToAppear(timeout: 5))
        capture(app, "The saved template in Templates")
    }

    @MainActor private func openTemplateAlert(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["Entry Actions"].firstMatch.tap()
        let saveTemplate = app.buttons["Save as Template…"]
        for _ in 0..<8 {
            if saveTemplate.exists && saveTemplate.isHittable { break }
            let menus = app.collectionViews
            guard menus.count > 0 else { break }
            menus.element(boundBy: menus.count - 1).swipeUp()
        }
        XCTAssertTrue(saveTemplate.isHittable)
        saveTemplate.tap()
        let alert = app.alerts["Save as Template"]
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        assertEventually(alert.textFields["Name"].value as? String, equals: "Daily review")
        return alert
    }

    /// Done ends editing from the title as it does from the body: no checkmark, no keyboard, and the reading bar.
    /// The body used to take the keyboard from the title, leaving an entry while its title had focus left the
    /// checkmark behind for good, and an entry reopened soon after leaving it while writing continued the writing
    /// (docs/design/sync-now-and-done.md).
    @MainActor func testDoneEndsEditingFromTitleAndAfterLeavingAFocusedTitle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.selectCollection("Default", app: app)
        NavigationTestSupport.newEntryFromList(app)
        let title = NavigationTestSupport.title(app)
        let body = app.textViews["Entry text"]
        let done = app.buttons["Finish Editing"]
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        // A new entry starts in its title.
        app.typeText("Morning pages")
        XCTAssertTrue(done.waitToAppear(timeout: 5))
        done.tap()
        assertReading(app, body: body)

        body.tap()
        app.typeText("First line")
        title.tap()
        XCTAssertTrue(done.waitToAppear(timeout: 5))
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
        ).firstMatch
        XCTAssertTrue(back.waitToAppear(timeout: 5))
        back.tap()
        let row = app.staticTexts["Morning pages"].firstMatch
        XCTAssertTrue(row.waitToAppear(timeout: 5))
        row.tap()
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        // Absence over time: XCTest's own wait, which first looks after a second.
        XCTAssertFalse(done.waitForExistence(timeout: 2), "Reopening the entry doesn't show the checkmark.")
        assertReading(app, body: body)

        body.tap()
        app.typeText(" and more")
        XCTAssertTrue(done.waitToAppear(timeout: 5))
        done.tap()
        assertReading(app, body: body)

        // Back straight from writing in the body, then reopening at once, opens the entry for reading as well.
        body.tap()
        app.typeText(" and back")
        back.tap()
        XCTAssertTrue(row.waitToAppear(timeout: 5))
        row.tap()
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        XCTAssertFalse(done.waitForExistence(timeout: 2), "Reopening the entry doesn't continue writing.")
        assertReading(app, body: body)
    }

    /// Reading: no checkmark or keyboard, the body doesn't have focus, and the reading bar's Insert Image is shown.
    @MainActor private func assertReading(_ app: XCUIApplication, body: XCUIElement) {
        XCTAssertTrue(app.buttons["Finish Editing"].waitToDisappear(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitToDisappear(timeout: 5))
        assertEventually(body.value(forKey: "hasKeyboardFocus") as? Bool, equals: false)
        let insertImage = app.buttons["Insert Image"].firstMatch
        XCTAssertTrue(insertImage.waitToAppear(timeout: 5))
        assertEventually(insertImage.isHittable)
    }

    @MainActor private func backToEntries(_ app: XCUIApplication) {
        if app.buttons["Finish Editing"].isHittable { app.buttons["Finish Editing"].tap() }
        if !app.searchFields.firstMatch.isHittable { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(app.searchFields.firstMatch.waitToAppear(timeout: 5))
    }

    @MainActor private func selectJournal(_ name: String, app: XCUIApplication) {
        NavigationTestSupport.selectCollection(name, app: app)
        XCTAssertTrue(app.searchFields["Search " + name].waitToAppear(timeout: 5))
    }

    @MainActor private func dismissSearch(_ app: XCUIApplication) {
        let close = app.buttons["close"]
        if close.exists { close.tap() } else { app.buttons["Cancel"].firstMatch.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitToDisappear(timeout: 5))
    }

    @MainActor private func search(_ query: String, app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        if !field.isHittable { app.swipeDown() }
        XCTAssertTrue(field.waitToAppear(timeout: 5))
        field.tap()
        field.typeText(query)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Fixture {
        let key: Data
        let phrase: String
        let work: JournalItem
        let source: JournalItem
        let personal: JournalItem
    }

    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
        let lastEntryID: UUID
    }

    @MainActor private func seed(_ directory: URL, sourceTitle: String = "Daily review") async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: directory, key: key)
        let work = JournalItem(kind: "journal", title: "Work")
        let source = JournalItem(
            kind: "entry", journalID: work.id, title: sourceTitle,
            document: .init(blocks: [
                DocumentBlock(kind: "heading", runs: [TextRun("What did I finish?")]), DocumentBlock(),
            ]))
        let personalJournal = JournalItem(kind: "journal", title: "Personal")
        let personal = JournalItem(
            kind: "entry", journalID: personalJournal.id, title: "Garden notes",
            document: .plain("Orchid flowers opened today."))
        for item in [work, personalJournal, source, personal] { try await store.save(item) }
        try await store.close()
        try JournalCoding.encoder().encode(
            Configuration(recovery: recovery, lastJournalID: work.id, lastEntryID: source.id)
        )
        .write(to: directory.appendingPathComponent("configuration.json"))
        return Fixture(key: key, phrase: phrase, work: work, source: source, personal: personal)
    }
}
