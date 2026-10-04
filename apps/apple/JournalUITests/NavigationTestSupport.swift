import XCTest

@MainActor
enum NavigationTestSupport {
    static func createPasswordJournal(_ app: XCUIApplication) {
        let encrypt = app.buttons["Use Encryption"]
        XCTAssertTrue(encrypt.waitToAppear(timeout: 10))
        encrypt.tap()
        let password = app.secureTextFields["Master Password"]
        XCTAssertTrue(password.waitToAppear(timeout: 10))
        password.tap()
        password.typeText("Native UI fixture password")
        let verify = app.secureTextFields["Verify"]
        verify.tap()
        verify.typeText("Native UI fixture password")
        app.buttons["Create"].tap()
    }

    /// A new simulator's keyboard first shows one-time tips over its keys ("Type English and French", then sliding to
    /// type), which take taps meant for the keys and for menus that open over them. Each closes with Continue, the
    /// only Continue on a writing screen.
    static func dismissKeyboardTips(_ app: XCUIApplication) {
        let proceed = app.buttons["Continue"].firstMatch
        for _ in 0..<3 {
            guard proceed.waitToAppear(timeout: 2) else { return }
            proceed.tap()
            XCTAssertTrue(proceed.waitToDisappear(timeout: 5))
        }
    }

    static func title(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "Entry title").firstMatch
    }

    static func closeSettings(_ app: XCUIApplication) {
        if !app.buttons["Done"].firstMatch.isHittable {
            app.navigationBars.buttons["BackButton"].tap()
        }
        app.buttons["Done"].firstMatch.tap()
    }

    static func showJournals(_ app: XCUIApplication) {
        if app.buttons["Finish Editing"].exists, app.buttons["Finish Editing"].isHittable {
            app.buttons["Finish Editing"].tap()
        }
        let list = app.collectionViews["Journals"]
        let sidebar = app.buttons["Show Sidebar"].firstMatch
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
        ).firstMatch
        for _ in 0..<3 {
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    list.exists || (sidebar.exists && sidebar.isHittable)
                        || (back.exists && back.isHittable)
                }, object: app)
            // XCTest's own wait, which first looks after a second: just after launching or unlocking, the app can
            // still be restoring the last journal or entry, and a look at once would act on the screen it is leaving.
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            if list.exists { return }
            if sidebar.exists, sidebar.isHittable { sidebar.tap() } else if back.exists, back.isHittable { back.tap() }
        }
        XCTAssertTrue(list.waitToAppear(timeout: 10))
    }
    /// Chooses one of a journal's actions through Edit and the journal's ⋯ (Journal Actions), then ends edit mode
    /// unless the action leaves an alert or sheet open (`endEditing: false`). A held row's context menu offers the same
    /// actions, but while it's open the reorderable list never reports its animations finished, so each step after
    /// a long press waits a minute (journal-order.md, prototype).
    static func journalAction(_ action: String, journal name: String, app: XCUIApplication, endEditing: Bool = false) {
        showJournals(app)
        let list = app.collectionViews["Journals"]
        if !app.buttons["Done"].firstMatch.exists {
            let edit = app.buttons["Edit"].firstMatch
            XCTAssertTrue(edit.waitToAppear(timeout: 5))
            edit.tap()
        }
        let row = list.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(row.waitToAppear(timeout: 5))
        let buttons = list.buttons.matching(NSPredicate(format: "label == %@", "Journal Actions"))
        XCTAssertTrue(buttons.firstMatch.waitToAppear(timeout: 5))
        let menu = buttons.allElementsBoundByIndex.min {
            abs($0.frame.midY - row.frame.midY) < abs($1.frame.midY - row.frame.midY)
        }
        menu?.tap()
        let item = app.buttons[action].firstMatch
        XCTAssertTrue(item.waitToAppear(timeout: 5))
        item.tap()
        if endEditing { finishJournalEditing(app) }
    }
    /// Done in the Journals list's edit mode.
    static func finishJournalEditing(_ app: XCUIApplication) {
        showJournals(app)
        let done = app.buttons["Done"].firstMatch
        if done.waitToAppear(timeout: 3) { done.tap() }
    }
    static func selectCollection(_ name: String, app: XCUIApplication) {
        showJournals(app)
        let list = app.collectionViews["Journals"]
        let first = list.buttons["all"].firstMatch
        for _ in 0..<8 {
            if first.exists, first.isHittable { break }
            list.swipeDown()
        }
        let row = list.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
        for _ in 0..<8 {
            if row.exists, row.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(row.waitToAppear(timeout: 10))
        assertEventually(row.isHittable)
        row.tap()
    }
    static func readingButton(_ name: String, app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[name].firstMatch
        let controls = app.scrollViews["Reading Controls"]
        if controls.exists {
            for _ in 0..<4 {
                if button.exists, button.isHittable { break }
                controls.swipeLeft()
            }
            for _ in 0..<4 {
                if button.exists, button.isHittable { break }
                controls.swipeRight()
            }
        }
        XCTAssertTrue(button.waitToAppear(timeout: 5))
        assertEventually(button.isHittable)
        return button
    }
    /// New Entry lives with the entries list; on iPhone that means going back from the editor first.
    static func newEntryFromList(_ app: XCUIApplication) {
        let create = app.buttons["New Entry"].firstMatch
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
        ).firstMatch
        // The list can still be arriving (after Start a Journal, say), with New Entry not there or not yet usable.
        let editor = title(app)
        XCTAssertTrue(
            Waiting.until(timeout: 10) {
                (create.exists && create.isHittable) || editor.exists || (!create.exists && back.exists)
            })
        if !(create.exists && create.isHittable) {
            XCTAssertTrue(back.waitToAppear(timeout: 5))
            back.tap()
        }
        XCTAssertTrue(create.waitToAppear(timeout: 5))
        create.tap()
    }
    /// A new entry, then “Use a Template…” in it, which opens the template chooser.
    static func openTemplateChooserInNewEntry(_ app: XCUIApplication) {
        newEntryFromList(app)
        let suggestion = app.buttons["Use a Template"].firstMatch
        XCTAssertTrue(suggestion.waitToAppear(timeout: 10))
        suggestion.tap()
        XCTAssertTrue(app.searchFields["Search Templates"].waitToAppear(timeout: 5))
    }
    /// Saves a template as a person does, since a new library has none (no-built-in-templates-2026-10-04.md): a new
    /// entry in Default titled “‹name› draft” with `text` as its body, then Entry Actions ▸ Save as Template…, named
    /// `name`. The entry's title differs, so the template's name matches only the template.
    static func saveTemplate(_ name: String, text: String, app: XCUIApplication) {
        selectCollection("Default", app: app)
        newEntryFromList(app)
        saveNewEntryAsTemplate(name, text: text, app: app)
    }
    /// Writes the new entry that is open, with its title focused, and saves it as a template as `saveTemplate` does.
    static func saveNewEntryAsTemplate(_ name: String, text: String, app: XCUIApplication) {
        let suffix = " draft"
        XCTAssertTrue(title(app).waitToAppear(timeout: 10))
        app.typeText(name + suffix + "\n" + text)
        let finish = app.buttons["Finish Editing"]
        if finish.exists, finish.isHittable { finish.tap() }
        app.buttons["Entry Actions"].firstMatch.tap()
        let save = app.buttons["Save as Template…"]
        for _ in 0..<8 {
            if save.exists, save.isHittable { break }
            let menus = app.collectionViews
            guard menus.count > 0 else { break }
            menus.element(boundBy: menus.count - 1).swipeUp()
        }
        XCTAssertTrue(save.isHittable)
        save.tap()
        let alert = app.alerts["Save as Template"]
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        // The name starts as the entry's title, with the caret at its end.
        let field = alert.textFields["Name"]
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: suffix.count))
        XCTAssertEqual(field.value as? String, name)
        alert.buttons["Save"].tap()
        XCTAssertTrue(alert.waitToDisappear(timeout: 5))
    }
    static func openEntry(_ title: String, journal: String, app: XCUIApplication) {
        selectCollection(journal, app: app)
        let row = app.staticTexts[title].firstMatch
        XCTAssertTrue(row.waitToAppear(timeout: 10))
        row.tap()
        XCTAssertTrue(Self.title(app).waitToAppear(timeout: 10))
    }
    static func openSettings(_ app: XCUIApplication) {
        showJournals(app)
        let settings = app.buttons["Settings"].firstMatch
        for _ in 0..<8 {
            if settings.exists, settings.isHittable { break }
            app.collectionViews["Journals"].swipeUp()
        }
        XCTAssertTrue(settings.waitToAppear(timeout: 5))
        settings.tap()
    }
}
