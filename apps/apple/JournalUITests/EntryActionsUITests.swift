import XCTest

final class EntryActionsUITests: XCTestCase {
    /// A swiped row leaves the list in the same update as the swipe. A row that stayed until the deletion was stored
    /// sprang back, and a full swipe could stop the app.
    @MainActor func testSwipeDeletionRemovesOnlyThatRow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        for title in ["First", "Second", "Third"] {
            if app.buttons["Finish Editing"].exists { app.buttons["Finish Editing"].tap() }
            NavigationTestSupport.newEntryFromList(app)
            XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 5))
            app.typeText(title)
            app.textViews["Entry text"].tap()
            app.typeText("Text")
        }
        if app.buttons["Finish Editing"].exists { app.buttons["Finish Editing"].tap() }
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
        ).firstMatch
        if back.exists, back.isHittable { back.tap() }
        func row(_ title: String) -> XCUIElement { app.cells.containing(.staticText, identifier: title).firstMatch }
        XCTAssertTrue(row("Second").waitToAppear(timeout: 5))
        row("Second").swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(row("Second").waitToDisappear(timeout: 5))
        let third = row("Third")
        third.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).press(
            forDuration: 0.05, thenDragTo: third.coordinate(withNormalizedOffset: CGVector(dx: -0.3, dy: 0.5)),
            withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(third.waitToDisappear(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(row("First").exists)
    }
    @MainActor func testFormattingAndDateActionsPreserveWritingAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.createPasswordJournal(app)
        let create = app.buttons["New Entry"].firstMatch
        XCTAssertTrue(create.waitToAppear(timeout: 10))
        create.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        app.typeText("A quiet writing surface for the things I want to remember")
        NavigationTestSupport.dismissKeyboardTips(app)
        XCTAssertEqual(title.value as? String, "A quiet writing surface for the things I want to remember")
        capture(app, "Title editing with keyboard")
        let header = app.descendants(matching: .any).matching(identifier: "Entry header").firstMatch
        let top = max(header.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 16
        let bottom = header.frame.maxY - 16
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<5 {
            origin.withOffset(CGVector(dx: 12, dy: top)).press(
                forDuration: 0,
                thenDragTo: origin.withOffset(CGVector(dx: 12, dy: bottom)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        capture(app, "Beginning of the long title")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Title scrolling hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        header.swipeUp()
        capture(app, "End of the long title")
        // The title's Return key reads Next. It's typed rather than tapped by its position, which a keyboard tip
        // over the keys turned into a tap on a letter key.
        XCTAssertTrue(app.keyboards.buttons["Next:"].waitToAppear(timeout: 5))
        app.typeText("\n")
        let body = app.textViews["Entry text"]
        app.typeText("A useful reflection")
        NavigationTestSupport.dismissKeyboardTips(app)
        XCTAssertEqual(title.value as? String, "A quiet writing surface for the things I want to remember")
        XCTAssertTrue((body.value as? String ?? "").contains("A useful reflection"))
        capture(app, "Next moves from title to body")
        checkImagePickerCancellation(app, body: body)
        XCTAssertFalse(app.datePickers.firstMatch.exists)
        app.buttons["Formatting"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Heading 1"].waitToAppear(timeout: 5))
        capture(app, "Visual formatting on iPhone")
        // Close sits in the sheet's header, reachable without scrolling.
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitToAppear(timeout: 5))
        assertEventually(close.isHittable)
        capture(app, "Reachable formatting dismissal")
        close.tap()
        app.buttons["Formatting"].firstMatch.tap()
        app.buttons["Heading 1"].tap()
        XCTAssertTrue((body.value as? String ?? "").contains("A useful reflection"))
        app.buttons["Entry Actions"].firstMatch.tap()
        app.buttons["Change Date…"].tap()
        // Cancel and Save sit in the sheet's navigation bar, as in other iOS sheets.
        let dateSheet = app.navigationBars["Change Date"]
        XCTAssertTrue(dateSheet.waitToAppear(timeout: 5))
        XCTAssertTrue(dateSheet.buttons["Save"].exists)
        capture(app, "Contextual date sheet")
        dateSheet.buttons["Cancel"].tap()
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        capture(app, "Quiet editor")
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry(
            "A quiet writing surface for the things I want to remember", journal: "All Entries", app: app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        assertEventually(title.value as? String, equals: "A quiet writing surface for the things I want to remember")
        assertEventually((body.value as? String ?? "").contains("A useful reflection"))
        let row = app.staticTexts["A quiet writing surface for the things I want to remember"].firstMatch
        if !row.isHittable { app.navigationBars.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(row.waitToAppear(timeout: 5))
        row.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Change Date…"].waitToAppear(timeout: 5))
        capture(app, "Entry context menu")
        app.buttons["Change Date…"].tap()
        XCTAssertTrue(dateSheet.waitToAppear(timeout: 5))
        dateSheet.buttons["Save"].tap()
        XCTAssertTrue(dateSheet.waitToDisappear(timeout: 5))
    }
    @MainActor private func checkImagePickerCancellation(_ app: XCUIApplication, body: XCUIElement) {
        // Cancelling either picker, the photo library or the file browser, leaves the writing untouched.
        for source in ["Photo Library", "Choose File…"] {
            // The keyboard comes back after each picker, sometimes with a tip of its own.
            NavigationTestSupport.dismissKeyboardTips(app)
            app.buttons["Insert Image"].firstMatch.tap()
            let choice = app.buttons[source]
            XCTAssertTrue(choice.waitToAppear(timeout: 5))
            choice.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitToAppear(timeout: 10))
            capture(app, "Native image picker: \(source)")
            cancel.tap()
            XCTAssertTrue(body.waitToAppear(timeout: 5))
            assertEventually((body.value as? String ?? "").contains("A useful reflection"))
            XCTAssertFalse(app.alerts["Journal"].exists)
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
