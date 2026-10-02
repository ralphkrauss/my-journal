import UIKit
import XCTest

final class FeedbackWorkflowUITests: XCTestCase {
    @MainActor func testNotesNavigationTemplatesAndKeyboardDismissalRetainWriting() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        let orientation = XCUIDevice.shared.orientation
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = orientation
        }
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 10))
        app.buttons["Start a Journal"].tap()
        XCTAssertTrue(app.buttons["Continue Without Encryption"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["Master Password"].exists)
        capture(app, "Encryption choice")
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.showJournals(app)
        XCTAssertTrue(app.staticTexts["All Entries"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "Journals")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Journal row ")).firstMatch.tap()
        XCTAssertTrue(app.buttons["New Entry"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Entries")
        NavigationTestSupport.newEntryFromList(app)
        let suggestion = app.buttons["Use a Template"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        capture(app, "Empty entry with template suggestion")
        // Part of the body's placeholder: a title keeps it; the body's first character hides it; an empty body brings
        // it back.
        app.typeText("A")
        XCTAssertTrue(suggestion.exists)
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        app.typeText("\n")
        app.typeText("B")
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 5))
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertTrue(app.searchFields["Search Templates"].waitForExistence(timeout: 5))
        capture(app, "Template picker")
        app.buttons["Workday Log"].firstMatch.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let body = app.textViews["Entry text"]
        // The template fills the entry itself, which now has content, so the suggestion is gone.
        let filled = NSPredicate(format: "value CONTAINS %@", "What I worked on")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: filled, object: body)], timeout: 10), .completed)
        XCTAssertFalse(suggestion.exists)
        app.typeText("A focused workday")
        XCTAssertEqual(title.value as? String, "A focused workday")
        body.tap()
        app.buttons["Formatting"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Paragraph"].waitForExistence(timeout: 5))
        capture(app, "Formatting choices")
        app.buttons["Paragraph"].tap()
        app.typeText("A useful note. ")
        // One set of writing controls while typing: the keyboard's, never the bottom bar as well.
        XCTAssertEqual(
            app.buttons.matching(identifier: "Formatting").allElementsBoundByIndex.filter(\.isHittable).count, 1)
        capture(app, "Editing above keyboard")
        let done = app.buttons["Finish Editing"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        _ = NavigationTestSupport.readingButton("View Source", app: app)
        XCTAssertEqual(
            app.buttons.matching(identifier: "Formatting").allElementsBoundByIndex.filter(\.isHittable).count, 1)
        capture(app, "Reading after Done")
        let expected = body.value as? String
        NavigationTestSupport.openSettings(app)
        XCTAssertTrue(app.buttons["Agent Access"].waitForExistence(timeout: 5))
        capture(app, "Settings sections")
        app.buttons["Privacy"].tap()
        XCTAssertTrue(app.staticTexts["Encryption Is Off"].waitForExistence(timeout: 5))
        NavigationTestSupport.closeSettings(app)
        app.terminate()
        app.launch()
        NavigationTestSupport.showJournals(app)
        XCTAssertTrue(app.staticTexts["All Entries"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["All Entries"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["A focused workday"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No additional text"].exists, "There is still a single entry")
        XCTAssertTrue(app.searchFields["Search All Entries"].exists)
        capture(app, "All Entries after relaunch")
        app.staticTexts["A focused workday"].firstMatch.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, expected)
        XCTAssertEqual(NavigationTestSupport.title(app).value as? String, "A focused workday")
        checkTable(app, body: body)
        checkChecklist(app, body: body, title: title)
    }
    @MainActor private func checkTable(_ app: XCUIApplication, body: XCUIElement) {
        body.tap()
        app.buttons["Formatting"].firstMatch.tap()
        app.buttons["Insert"].firstMatch.tap()
        app.buttons["Table"].firstMatch.tap()
        let header = app.textViews["Header, column 1"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        header.tap()
        header.typeText("Project")
        XCTAssertEqual(header.value as? String, "Project")
        capture(app, "Native table editing")
        app.buttons["Finish Editing"].tap()
        NavigationTestSupport.readingButton("View Source", app: app).tap()
        XCTAssertTrue((body.value as? String ?? "").contains("Project"))
        XCTAssertTrue((body.value as? String ?? "").contains("|"))
        NavigationTestSupport.readingButton("View Preview", app: app).tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, "Project")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture(app, "Table after preview switch")
    }
    @MainActor private func checkChecklist(_ app: XCUIApplication, body: XCUIElement, title: XCUIElement) {
        NavigationTestSupport.newEntryFromList(app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Checklist")
        XCTAssertEqual(title.value as? String, "Checklist")
        body.tap()
        app.buttons["Formatting"].firstMatch.tap()
        let taskList = app.buttons["Task List"].firstMatch
        XCTAssertTrue(taskList.waitForExistence(timeout: 5))
        // At half height on a smaller iPhone, the Format sheet's edge cuts through Task List; open it fully first.
        let grabber = app.buttons["Sheet Grabber"]
        if grabber.exists { grabber.tap() }
        taskList.tap()
        app.typeText("Review the day")
        app.buttons["Finish Editing"].tap()
        let task = app.buttons["Mark as Complete: Review the day"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        XCTAssertTrue(app.buttons["Mark as Incomplete: Review the day"].exists)
        capture(app, "Completed checklist item")
        NavigationTestSupport.readingButton("View Source", app: app).tap()
        XCTAssertTrue((body.value as? String ?? "").contains("- [x] Review the day"))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        NavigationTestSupport.readingButton("View Preview", app: app).tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
            NavigationTestSupport.selectCollection("Default", app: app)
            XCTAssertTrue(app.searchFields["Search Default"].waitForExistence(timeout: 5))
            if app.collectionViews["Journals"].exists {
                XCTAssertTrue(app.collectionViews["Journals"].staticTexts["Default"].firstMatch.isHittable)
            } else {
                app.staticTexts["Checklist"].firstMatch.tap()
                XCTAssertTrue(title.waitForExistence(timeout: 5))
            }
            XCTAssertEqual(title.value as? String, "Checklist")
            capture(app, "Landscape navigation and writing")
        }

    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
