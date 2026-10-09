import UIKit
import XCTest

/// Lists written on the iPhone's software keyboard, as a person writes them.
final class ListWritingUITests: XCTestCase {
    /// Markdown typed at the start of a line on the software keyboard formats the line, as on the Mac: “- ”, “* ”,
    /// “1. ”, “[] ”, “> ” and “# ”, one of them tapped key by key. Build 14 converted the line only when the
    /// keyboard had put the space in before the editor looked, so a hyphen and space tapped on the keyboard often
    /// stayed as typed.
    @MainActor func testMarkdownShortcutsTypedOnTheKeyboardFormatTheLine() throws {
        let app = launchNewEntry()
        defer { app.terminate() }
        // As a person types it: the hyphen from the numbers keyboard, then the space bar.
        try tap(["-", "space"], app: app)
        app.typeText("Tapped\n\n")
        for (shortcut, line) in [
            ("- ", "Hyphen"), ("* ", "Star"), ("1. ", "Numbered"), ("[] ", "Checklist"), ("> ", "Quote"),
            ("# ", "Heading"),
        ] {
            app.typeText(shortcut + line + "\n")
            // Return on the next, empty item leaves a list, and Delete an empty quote line; Return already left the
            // heading.
            if shortcut == "> " {
                app.typeText(XCUIKeyboardKey.delete.rawValue)
            } else if shortcut != "# " {
                app.typeText("\n")
            }
        }
        capture(app, "Markdown shortcuts typed")
        XCTAssertEqual(
            try source(app),
            "- Tapped\n\n- Hyphen\n\n- Star\n\n1. Numbered\n\n- [ ] Checklist\n\n> Quote\n\n# Heading")
    }

    /// A list written in one fast burst keeps each letter in its own item, in order. Build 15's first shortcut fix
    /// converted the line a moment after the space, and letters already on their way could land in the item above
    /// (“Milks”, “Egg”) or leave the marker as typed.
    @MainActor func testAListTypedInOneBurstKeepsEachItemsText() throws {
        let app = launchNewEntry()
        defer { app.terminate() }
        app.typeText("- Milk\nEggs\nBread")
        capture(app, "List typed in one burst")
        // The Markdown writer separates every block, list items included, with a blank line.
        XCTAssertEqual(try source(app), "- Milk\n\n- Eggs\n\n- Bread")
    }

    /// The checkbox of a new checklist item stays where it is when its first letter is typed. Build 14 placed it
    /// on the empty item's line break, about 7 points too low, so it jumped up with the first letter.
    @MainActor func testANewChecklistItemsCheckboxStaysPutAsItsFirstLetterIsTyped() throws {
        let app = launchNewEntry()
        defer { app.terminate() }
        app.typeText("[] Buy milk\n")
        let empty = app.buttons["Empty checklist item"]
        XCTAssertTrue(empty.waitToAppear(timeout: 5), "Return started the next item.")
        let before = empty.frame
        app.typeText("E")
        let typed = app.buttons["E"]
        XCTAssertTrue(typed.waitToAppear(timeout: 5))
        XCTAssertEqual(typed.frame.minY, before.minY, accuracy: 0.5, "The checkbox stayed on its line.")
        app.typeText("ggs\n")
        XCTAssertTrue(app.buttons["Empty checklist item"].waitToAppear(timeout: 5))
    }

    /// Taps keys of the software keyboard, switching to the numbers keyboard for those that are on it. A simulator
    /// that has seen a hardware keyboard keeps the software keyboard off screen; the same characters are then typed
    /// as key presses of the hardware keyboard, which reach the text view the same way.
    @MainActor private func tap(_ keys: [String], app: XCUIApplication) throws {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitToAppear(timeout: 5))
        guard waitToBeTapped(app.keys["space"]) else {
            app.typeText(keys.map { $0 == "space" ? " " : $0 }.joined())
            return
        }
        for name in keys {
            let key = app.keys[name]
            if !key.exists {
                let more = app.keys.matching(
                    NSPredicate(format: "identifier == 'more' OR label ==[c] 'more' OR label ==[c] 'numbers'")
                ).firstMatch
                XCTAssertTrue(waitToBeTapped(more), "The numbers key is on screen.")
                more.tap()
            }
            XCTAssertTrue(waitToBeTapped(key), name)
            key.tap()
        }
    }

    /// Waits until `element` can be tapped: the keyboard slides in after the title's Return.
    @MainActor private func waitToBeTapped(_ element: XCUIElement) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.exists && element.isHittable }, object: element)
        return Waiting.wait(for: hittable, timeout: 5) == .completed
    }

    /// The entry's Markdown, as View Source shows it, without the line breaks that end it.
    @MainActor private func source(_ app: XCUIApplication) throws -> String {
        let view = app.buttons["View Source"].firstMatch
        XCTAssertTrue(view.waitToAppear(timeout: 5))
        view.tap()
        let body = app.textViews["Entry text"]
        XCTAssertTrue(body.waitToAppear(timeout: 5))
        let markdown = try XCTUnwrap(body.value as? String)
        return String(markdown.reversed().drop(while: \.isNewline).reversed())
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func launchNewEntry() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.selectCollection("Default", app: app)
        app.buttons["New Entry"].firstMatch.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Shortcuts\n")
        return app
    }
}
