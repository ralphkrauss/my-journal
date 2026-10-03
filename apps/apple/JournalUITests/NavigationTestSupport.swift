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
