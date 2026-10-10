import UIKit
import XCTest

/// The pre-release interface changes (docs/design/pre-release-ui-2026-09-27.md), checked on iPhone and iPad, with
/// screenshots in light and dark appearance and at the largest text size for the new rows and sheets.
final class PreReleaseUITests: XCTestCase {
    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Item 1: a deleted template is in Recently Deleted, comes back with Restore, and can be deleted permanently.
    @MainActor func testDeletedTemplateRestoresAndDeletesPermanently() throws {
        let app = launchWithNewJournal(dark: false)
        defer { app.terminate() }
        // A new library has no templates: the empty Templates list says how to make one.
        NavigationTestSupport.selectCollection("Templates", app: app)
        // VoiceOver reads the title and its explanation as one element.
        let empty = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No Templates")).firstMatch
        XCTAssertTrue(empty.waitToAppear(timeout: 10))
        XCTAssertTrue(empty.label.contains("To create a template, open an entry and choose Save"), empty.label)
        capture(app, "No templates")
        saveTemplates(["Daily Reflection", "Gratitude"], app: app)
        NavigationTestSupport.selectCollection("Templates", app: app)
        let template = app.staticTexts["Gratitude"].firstMatch
        XCTAssertTrue(template.waitToAppear(timeout: 10))
        template.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Delete Template"].waitToAppear(timeout: 5))
        capture(app, "Template context menu")
        app.buttons["Delete Template"].tap()
        XCTAssertTrue(template.waitToDisappear(timeout: 5))
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        XCTAssertTrue(app.staticTexts["Gratitude"].firstMatch.waitToAppear(timeout: 10))
        XCTAssertTrue(app.staticTexts["Templates"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Items stay here until you delete them permanently."].firstMatch.exists)
        capture(app, "Recently Deleted with a template")
        app.staticTexts["Gratitude"].firstMatch.tap()
        let notice = app.staticTexts["This template is in Recently Deleted."]
        XCTAssertTrue(notice.waitToAppear(timeout: 10))
        capture(app, "Deleted template notice")
        app.buttons["Restore"].firstMatch.tap()
        XCTAssertTrue(notice.waitToDisappear(timeout: 10))
        capture(app, "Restored template")
        // Back leads to Templates, where the template is again.
        NavigationTestSupport.selectCollection("Templates", app: app)
        XCTAssertTrue(app.staticTexts["Gratitude"].firstMatch.waitToAppear(timeout: 10))
        app.staticTexts["Gratitude"].firstMatch.press(forDuration: 1)
        app.buttons["Delete Template"].tap()
        NavigationTestSupport.selectCollection("Recently Deleted", app: app)
        let deleted = app.staticTexts["Gratitude"].firstMatch
        XCTAssertTrue(deleted.waitToAppear(timeout: 10))
        deleted.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Restore"].waitToAppear(timeout: 5))
        app.buttons["Delete Permanently…"].tap()
        let alert = app.alerts["Delete “Gratitude” Permanently?"]
        XCTAssertTrue(alert.waitToAppear(timeout: 5))
        XCTAssertTrue(
            alert.staticTexts["You can’t undo this. Copies may remain in archives, backups, and server history."].exists
        )
        capture(app, "Delete template permanently")
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No Deleted Items"].waitToAppear(timeout: 10))
        app.terminate()
        app.launch()
        NavigationTestSupport.selectCollection("Templates", app: app)
        XCTAssertTrue(app.staticTexts["Daily Reflection"].firstMatch.waitToAppear(timeout: 10))
        XCTAssertFalse(app.staticTexts["Gratitude"].firstMatch.exists)
    }

    /// Item 1 in dark appearance and at the largest text size: the Templates section and its footer.
    @MainActor func testRecentlyDeletedTemplateRowsInDarkAndLargestText() throws {
        for (dark, largest) in [(true, false), (false, true)] {
            let app = launchWithNewJournal(dark: dark, largestText: largest)
            saveTemplates(["Weekly Reflection"], app: app)
            NavigationTestSupport.selectCollection("Templates", app: app)
            let template = app.staticTexts["Weekly Reflection"].firstMatch
            for _ in 0..<4 where !template.waitToAppear(timeout: 3) { app.collectionViews.firstMatch.swipeUp() }
            XCTAssertTrue(template.waitToAppear(timeout: 10))
            template.press(forDuration: 1)
            app.buttons["Delete Template"].tap()
            NavigationTestSupport.selectCollection("Recently Deleted", app: app)
            XCTAssertTrue(app.staticTexts["Weekly Reflection"].firstMatch.waitToAppear(timeout: 10))
            capture(app, "Recently Deleted with a template" + (dark ? ", dark" : ", largest text"))
            app.terminate()
        }
    }

    /// Item 2 on a keyboard: the arrow keys move the highlight, which shows the template Return creates. (Escape
    /// can't be sent to a simulator by a UI test; it is handled by the same key commands.)
    @MainActor func testArrowKeysChooseTheTemplateReturnCreates() throws {
        let app = launchWithNewJournal(dark: false)
        defer { app.terminate() }
        saveTemplates(["Daily Reflection", "Gratitude"], app: app)
        NavigationTestSupport.selectCollection("Default", app: app)
        NavigationTestSupport.openTemplateChooserInNewEntry(app)
        let search = app.searchFields["Search Templates"]
        search.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        search.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        let gratitude = app.buttons["Gratitude"].firstMatch
        XCTAssertTrue(gratitude.isSelected, "The second template is highlighted.")
        XCTAssertFalse(app.buttons["Daily Reflection"].firstMatch.isSelected)
        capture(app, "Highlighted template")
        search.typeText("\n")
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        XCTAssertTrue(
            (app.textViews["Entry text"].value as? String ?? "").contains("What am I grateful for"),
            "Return creates an entry from the highlighted template.")
    }

    /// The template sheet's search field sits fully below its title bar and the sheet's grabber, and stays usable,
    /// in both orientations and with the keyboard shown.
    @MainActor func testTemplatePickerSearchFieldIsFullyVisible() throws {
        let app = launchWithNewJournal(dark: false)
        let orientation = XCUIDevice.shared.orientation
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = orientation
        }
        XCUIDevice.shared.orientation = .portrait
        saveTemplates(["Gratitude", "Workday Log"], app: app)
        NavigationTestSupport.selectCollection("Default", app: app)
        NavigationTestSupport.openTemplateChooserInNewEntry(app)
        let search = app.searchFields["Search Templates"]
        let title = app.navigationBars["Choose a Template"]
        for turned in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = turned
            let name = turned == .portrait ? "portrait" : "landscape"
            // Frames are compared once the rotation has finished.
            sleep(1)
            captureScreen("Template picker, \(name)")
            XCTAssertTrue(search.isHittable, name)
            // On iPhone the sheet's title bar, with Cancel, keeps the search field clear of the grabber and top edge.
            // A regular-width iPad shows a popover without one.
            XCTAssertTrue(isPad || title.exists, name)
            if title.exists {
                XCTAssertGreaterThanOrEqual(
                    search.frame.minY, title.frame.maxY - 1, name)
                XCTAssertTrue(title.buttons.firstMatch.isHittable, name)
            }
        }
        search.typeText("grat")
        let gratitude = app.buttons["Gratitude"].firstMatch
        XCTAssertTrue(gratitude.waitToAppear(timeout: 5))
        XCTAssertFalse(app.buttons["Workday Log"].exists)
        captureScreen("Template picker, landscape, filtered")
        XCTAssertTrue(gratitude.isHittable)
    }

    /// The Format panel takes the keyboard's place on iPhone, at the keyboard's height (owner decision 2026-09-30), so
    /// the entry doesn't move and the text being styled stays visible; the rows scroll to every option.
    @MainActor func testFormatSheetShowsEveryOption() throws {
        for dark in [false, true] {
            let app = launchWithNewJournal(dark: dark)
            let body = writeLongEntry(app)
            capture(app, "Before Format" + (dark ? ", dark" : ""))
            let formatting = app.buttons["Formatting"].firstMatch
            let barBefore = formatting.frame.minY
            formatting.tap()
            XCTAssertTrue(app.buttons["Heading 1"].waitToAppear(timeout: 5))
            // On iPad, Format is a popover beside the keyboard, and scrolls when the keyboard leaves it too little room.
            if !isPad {
                // Exactly where the keyboard was: the bar above it, and the entry, stay put.
                XCTAssertEqual(formatting.frame.minY, barBefore, accuracy: 1)
                for name in ["Close", "Bold", "Paragraph"] {
                    XCTAssertTrue(app.buttons[name].firstMatch.isHittable, name)
                }
                let insert = app.buttons["Insert"].firstMatch
                for _ in 0..<6 where !insert.isHittable { app.buttons["Heading 2"].firstMatch.swipeUp() }
                XCTAssertTrue(insert.isHittable)
                capture(app, "Format panel scrolled" + (dark ? ", dark" : ""))
                // Back up from the bottom, on a row that's on screen there: the panel only keeps visible rows.
                for _ in 0..<6 where !app.buttons["Bold"].firstMatch.isHittable { insert.swipeDown() }
                if !dark {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    XCTAssertTrue(app.buttons["Bold"].firstMatch.waitToAppear(timeout: 5))
                    captureScreen("Format panel, landscape")
                    XCUIDevice.shared.orientation = .portrait
                    XCTAssertTrue(app.buttons["Bold"].firstMatch.waitToAppear(timeout: 5))
                }
            }
            // The panel replaces the keyboard: the text keeps focus.
            assertEventually(body.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
            capture(app, "Format sheet with the caret at the end" + (dark ? ", dark" : ""))
            app.buttons["Bold"].firstMatch.tap()
            capture(app, "Format sheet after Bold" + (dark ? ", dark" : ""))
            app.buttons["Close"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Heading 1"].waitToDisappear(timeout: 5))
            assertEventually((body.value as? String ?? "").contains("Line 30"))
            capture(app, "After closing Format" + (dark ? ", dark" : ""))
            app.terminate()
        }
    }

    /// While the Format panel is open, its commands follow the selection the person makes, and closing it leaves the
    /// caret where they put it, with the keyboard back.
    @MainActor func testFormatPanelFollowsTheSelectionAndKeepsTheCaret() throws {
        let app = launchWithNewJournal(dark: false)
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Styles\n")
        let body = app.textViews["Entry text"]
        app.typeText("alpha beta")
        // “alpha” selected, as with a keyboard's arrow keys.
        body.typeKey(.leftArrow, modifierFlags: .command)
        body.typeKey(.rightArrow, modifierFlags: [.option, .shift])
        app.buttons["Formatting"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Bold"].firstMatch.waitToAppear(timeout: 2))
        assertEventually(body.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
        capture(app, "Format panel in place of the keyboard")
        // Another word, chosen while the panel is open, is the one made bold.
        body.typeKey(.rightArrow, modifierFlags: .command)
        body.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        if isPad {
            // On iPad, Format is a popover beside the text; moving the selection closes it, as a tap outside does.
            XCTAssertTrue(app.buttons["Bold"].firstMatch.waitToDisappear(timeout: 2))
            app.buttons["Formatting"].firstMatch.tap()
        }
        app.buttons["Bold"].firstMatch.tap()
        // The caret where the person last put it: at the end. (On iPad that closes the popover by itself.)
        if isPad { app.buttons["Close"].firstMatch.tap() }
        body.typeKey(.rightArrow, modifierFlags: .command)
        if !isPad { app.buttons["Close"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["Bold"].firstMatch.waitToDisappear(timeout: 2))
        assertEventually(body.value(forKey: "hasKeyboardFocus") as? Bool ?? false)
        app.typeText(" done")
        capture(app, "Keyboard back after Format")
        NavigationTestSupport.readingButton("View Source", app: app).tap()
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in (body.value as? String ?? "").contains("**") }, object: nil)
        XCTAssertEqual(Waiting.wait(for: shown, timeout: 5), .completed)
        capture(app, "Source after Format")
        let source = body.value as? String ?? ""
        XCTAssertTrue(source.contains("**beta"), source)
        XCTAssertFalse(source.contains("**alpha"), source)
        XCTAssertTrue(source.contains("done"), source)
    }
    /// Item 5 at the largest text size: the sheet is as tall as it can be, Close is reachable and the list scrolls.
    @MainActor func testFormatSheetAtTheLargestTextSize() throws {
        let app = launchWithNewJournal(dark: false, largestText: true)
        defer { app.terminate() }
        _ = writeLongEntry(app, lines: 3)
        app.buttons["Formatting"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Heading 1"].waitToAppear(timeout: 5))
        assertEventually(app.buttons["Close"].firstMatch.isHittable)
        capture(app, "Format sheet, largest text")
        let insert = app.buttons["Insert"].firstMatch
        // The panel's rows scroll. A swipe is made on the scroll view, slowly, so it travels across the panel: one
        // made on a row only partly in view was too short to scroll, and became a tap that chose that row's
        // style and closed the panel.
        let rows = app.scrollViews.containing(NSPredicate(format: "label == %@", "Heading 1")).firstMatch
        XCTAssertTrue(rows.waitToAppear(timeout: 5))
        for _ in 0..<8 where !insert.isHittable { rows.swipeUp(velocity: .slow) }
        XCTAssertTrue(insert.isHittable)
        capture(app, "Format sheet, largest text, scrolled")
        // Opened again, it starts at the top, with Bold in view.
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Heading 1"].waitToDisappear(timeout: 5))
        app.buttons["Formatting"].firstMatch.tap()
        let bold = app.buttons["Bold"].firstMatch
        XCTAssertTrue(bold.waitToAppear(timeout: 5))
        assertEventually(bold.isHittable, "Format opens at the top again.")
    }

    /// Item 4: Backspace at the start of a task removes the checkbox and keeps the line.
    @MainActor func testBackspaceAtTheStartOfATaskRemovesTheCheckbox() throws {
        let app = launchWithNewJournal(dark: false)
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Errands\n")
        let body = app.textViews["Entry text"]
        app.typeText("[] ")
        let checkbox = app.buttons["Empty checklist item"]
        XCTAssertTrue(checkbox.waitToAppear(timeout: 5), "[] starts a checklist item.")
        app.typeText("Buy milk\n")
        XCTAssertTrue(app.buttons["Buy milk"].waitToAppear(timeout: 5))
        XCTAssertTrue(app.buttons["Empty checklist item"].waitToAppear(timeout: 5), "Return starts the next item.")
        capture(app, "Second task, empty")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        app.typeText("Then a plain line")
        let value = body.value as? String ?? ""
        XCTAssertTrue(value.hasSuffix("\nThen a plain line"), value)
        XCTAssertFalse(app.buttons["Then a plain line"].exists, "Only the first line keeps its checkbox.")
        XCTAssertTrue(app.buttons["Buy milk"].exists)
        capture(app, "Backspace removed the checkbox")
    }

    /// A new list item starts a line, so the keyboard capitalizes its first letter as on any new line. Build 13 kept
    /// hidden marker characters before the caret, and the keyboard stayed lowercase.
    @MainActor func testNewListItemsStartWithACapitalLetter() throws {
        let app = launchWithNewJournal(dark: false)
        defer { app.terminate() }
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Lists\n")
        for (shortcut, name) in [
            ("[] ", "checklist"), ("- ", "bulleted list"), ("1. ", "numbered list"), ("> ", "quote"),
        ] {
            app.typeText(shortcut)
            // The keyboard shows capitals at the start of the first item, and again on the next one.
            XCTAssertTrue(app.keys["B"].waitToAppear(timeout: 5), "The first \(name) item starts with a capital.")
            app.typeText("buy milk\n")
            XCTAssertTrue(app.keys["B"].waitToAppear(timeout: 5), "A new \(name) item starts with a capital.")
            XCTAssertFalse(app.keys["b"].exists, name)
            capture(app, "New \(name) item")
            // Return on the empty item leaves the list for the next one.
            app.typeText("\n")
        }
    }

    /// Item 6: on an iPad keyboard, ⌥⌘F searches the entries, as in Notes, and ⇧⌘F opens Find and Replace in the
    /// entry. The two must not share a shortcut.
    @MainActor func testSearchEntriesAndFindAndReplaceShortcutsOnIPad() throws {
        try XCTSkipUnless(isPad, "Menu bar shortcuts are an iPad feature.")
        let app = launchWithNewJournal(dark: false)
        defer { app.terminate() }
        let body = writeLongEntry(app, lines: 2)
        let written = body.value as? String
        // The simulator connects its keyboard with the first key and drops that key; this one moves nothing.
        body.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        body.typeKey("f", modifierFlags: [.command, .shift])
        let replace = app.descendants(matching: .any).matching(identifier: "Replace").firstMatch
        XCTAssertTrue(replace.waitToAppear(timeout: 5), "⇧⌘F opens Find and Replace in the entry.")
        assertEventually(body.value as? String, equals: written)
        capture(app, "Find and Replace from the keyboard")
        // Close Find and finish writing, then search the entries.
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(replace.waitToDisappear(timeout: 5))
        let finish = app.buttons["Finish Editing"].firstMatch
        if finish.waitToAppear(timeout: 2) { finish.tap() }
        app.typeKey("f", modifierFlags: [.command, .option])
        let search = app.searchFields["Search Default"]
        XCTAssertTrue(search.waitToAppear(timeout: 5))
        app.typeText("Line 2")
        assertEventually(search.value as? String, equals: "Line 2", "⌥⌘F puts the typing in the entry search.")
        XCTAssertEqual(body.value as? String, written, "The entry keeps its text.")
        capture(app, "Search Entries from the keyboard")
    }

    /// Export Archive goes straight to the save dialog, with no password check first; Settings ▸ Backup points to
    /// Change Password for anyone unsure of their password (docs/design/1-1-encryption-and-passwords.md §4.2).
    @MainActor func testArchiveExportGoesStraightToSavingAndPointsToChangePassword() throws {
        if #available(iOS 17.0, *) { XCUIDevice.shared.appearance = .light }
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.createPasswordJournal(app)
        XCTAssertTrue(app.buttons["New Entry"].firstMatch.waitToAppear(timeout: 10))
        NavigationTestSupport.openSettings(app)
        app.buttons["Backup"].firstMatch.tap()
        let export = app.buttons["Export Archive…"].firstMatch
        XCTAssertTrue(export.waitToAppear(timeout: 5))
        let pointer = app.buttons["Change Password…"]
        XCTAssertTrue(pointer.waitToAppear(timeout: 5))
        capture(app, "Export Archive with the Change Password pointer")
        export.tap()
        // The save dialog, which is closed without saving.
        let saveDialog = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(saveDialog.waitToAppear(timeout: 15))
        XCTAssertFalse(app.staticTexts["Check Your Password"].exists, "Nothing asks for the password first.")
        capture(app, "Save dialog")
        let suggested = app.textFields.matching(NSPredicate(format: "value BEGINSWITH 'Journal Archive '")).firstMatch
        XCTAssertTrue(suggested.waitToAppear(timeout: 5), "The save dialog suggests a readable name.")
        // iPad's save dialog has a close button; iPhone's is a sheet that closes with a swipe.
        let close = saveDialog.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch
        let sidebarClose = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "Cancel"])).firstMatch
        if close.exists {
            close.tap()
        } else if isPad, sidebarClose.exists {
            sidebarClose.tap()
        } else {
            saveDialog.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(saveDialog.waitToDisappear(timeout: 10))
        XCTAssertFalse(
            app.staticTexts["Archive saved. Keep your master password with it."].exists,
            "Nothing was saved, so nothing says so.")
        pointer.tap()
        let change = app.navigationBars["Change Password"]
        XCTAssertTrue(change.waitToAppear(timeout: 5))
        capture(app, "Change Password")
        change.buttons["Cancel"].tap()
        XCTAssertTrue(change.waitToDisappear(timeout: 5))
    }

    // MARK: - Support

    @MainActor private func launchWithNewJournal(dark: Bool, largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if #available(iOS 17.0, *) { XCUIDevice.shared.appearance = dark ? .dark : .light }
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        return app
    }
    /// Templates with the questions of the ones earlier builds started libraries with; a new library has none.
    @MainActor private func saveTemplates(_ names: [String], app: XCUIApplication) {
        let questions = [
            "Daily Reflection": "What went well?",
            "Gratitude": "What am I grateful for today?",
            "Workday Log": "What I worked on",
            "Weekly Reflection": "What stood out this week?",
        ]
        for name in names { NavigationTestSupport.saveTemplate(name, text: questions[name] ?? name, app: app) }
    }
    /// A new entry long enough that the caret, at its end, is where a sheet would cover it.
    @MainActor private func writeLongEntry(_ app: XCUIApplication, lines: Int = 30) -> XCUIElement {
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("A long entry\n")
        let body = app.textViews["Entry text"]
        app.typeText((1...lines).map { "Line \($0)" }.joined(separator: "\n"))
        return body
    }
    /// The whole screen: an app screenshot taken in landscape can be cropped to the portrait frame.
    @MainActor private func captureScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = (isPad ? "iPad: " : "iPhone: ") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = (isPad ? "iPad: " : "iPhone: ") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
