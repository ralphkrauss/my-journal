import Vision
import XCTest

/// Small native details of starting a journal and writing an entry on iPhone.
final class EntryBasicsUITests: XCTestCase {
    /// The welcome screen's picture is decoration, and the encrypted step of Start a Journal has the system back button
    /// where Cancel was, with Create alone on the trailing side.
    @MainActor func testWelcomeAndEncryptedStartFollowNativeConventions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        let start = app.buttons["Start a Journal"]
        XCTAssertTrue(start.waitToAppear(timeout: 10))
        XCTAssertFalse(app.images["book.closed"].exists, "VoiceOver would read the symbol's name.")
        capture(app, "Welcome")
        start.tap()
        let encrypt = app.buttons["Use Encryption"]
        XCTAssertTrue(encrypt.waitToAppear(timeout: 5))
        encrypt.tap()
        let bar = app.navigationBars.firstMatch
        let back = bar.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
        ).firstMatch
        let create = bar.buttons["Create"]
        XCTAssertTrue(back.waitToAppear(timeout: 5))
        XCTAssertTrue(create.exists)
        XCTAssertFalse(bar.buttons["Cancel"].exists)
        XCTAssertLessThan(back.frame.midX, bar.frame.midX)
        XCTAssertGreaterThan(create.frame.midX, bar.frame.midX)
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: app.secureTextFields["Master Password"])
        XCTAssertEqual(Waiting.wait(for: focused, timeout: 3), .completed)
        capture(app, "Choose a Master Password")
        back.tap()
        XCTAssertTrue(encrypt.waitToAppear(timeout: 5))
        XCTAssertTrue(app.navigationBars.firstMatch.buttons["Cancel"].exists)
        NavigationTestSupport.createPasswordJournal(app)
        XCTAssertTrue(encrypt.waitToDisappear(timeout: 15))
    }

    /// Tab from a hardware keyboard moves from the title to the text, as Return does; the title never holds a tab.
    @MainActor func testTabInTitleMovesToText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        NavigationTestSupport.newEntryFromList(app)
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 5))
        app.typeText("Rich")
        app.typeText("\t")
        app.typeText("paste")
        XCTAssertEqual(title.value as? String, "Rich")
        XCTAssertEqual(app.textViews["Entry text"].value as? String, "paste")
    }

    /// Tapping in the empty space below an entry's text, after opening it, continues at the end, as in Notes. It used
    /// to select a misspelled last word, so the next letter typed replaced it.
    @MainActor func testTapBelowTheTextAfterReopeningContinuesAtTheEnd() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        app.buttons["Continue Without Encryption"].tap()
        NavigationTestSupport.selectCollection("Default", app: app)
        NavigationTestSupport.newEntryFromList(app)
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
        app.typeText("Spell test\n")
        let body = app.textViews["Entry text"]
        app.typeText("Coffee and pastries blorptz")
        XCTAssertEqual(body.value as? String, "Coffee and pastries blorptz")
        app.buttons["Finish Editing"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitToDisappear(timeout: 5))
        NavigationTestSupport.openEntry("Spell test", journal: "Default", app: app)
        // Well below the only line, in the entry's empty space.
        let below = body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(
            CGVector(dx: 0, dy: 160))
        below.tap()
        let writing = NSPredicate { _, _ in (body.value(forKey: "hasKeyboardFocus") as? Bool) == true }
        XCTAssertEqual(
            Waiting.wait(for: XCTNSPredicateExpectation(predicate: writing, object: nil), timeout: 5), .completed)
        capture(app, "After tapping below the text")
        app.typeText("K")
        XCTAssertEqual(body.value as? String, "Coffee and pastries blorptzK")
        // While writing, too.
        below.tap()
        app.typeText("L")
        XCTAssertEqual(body.value as? String, "Coffee and pastries blorptzKL")
    }

    /// Writing line after line, as in Notes: the entry only ever scrolls forward, and the line being typed stays in view
    /// just above the writing controls, at the end of the entry and after Returns in the middle of it, at the default
    /// and the largest text size. Build 9's own caret reveal fought the text view's scrolling on every Return.
    @MainActor func testLineBeingTypedStaysAboveTheWritingControls() throws {
        for largest in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
            if largest {
                app.launchArguments += [
                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                ]
            }
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
            app.buttons["Start a Journal"].tap()
            app.buttons["Continue Without Encryption"].tap()
            NavigationTestSupport.selectCollection("Default", app: app)
            NavigationTestSupport.newEntryFromList(app)
            XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 10))
            NavigationTestSupport.dismissKeyboardTips(app)
            app.typeText("Scrolling\n")
            var writing = TypedLines(app: app, test: self)
            let lines = largest ? 8 : 14
            for line in 1...lines {
                app.typeText(line == 1 ? "Line 1" : "\nLine \(line)")
                writing.check("Line \(line)")
            }
            XCTAssertLessThan(writing.header, writing.firstHeader, "Typing reached the controls and scrolled.")
            // Returns in the middle: the text below moves down until the caret line reaches the controls.
            let earlier = try XCTUnwrap(writing.frame(of: "Line \(lines - 2)"), "An earlier line is in view.")
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: earlier.maxX + 4, dy: earlier.midY))
                .tap()
            for line in 1...(largest ? 4 : 6) {
                app.typeText("\nAdded \(line)")
                writing.check("Added \(line)")
            }
            capture(app, "Writing after Returns in the middle" + (largest ? ", largest text" : ""))
            XCTAssertTrue(
                (app.textViews["Entry text"].value as? String ?? "").hasSuffix(
                    "Added \(largest ? 4 : 6)\nLine \(lines - 1)\nLine \(lines)"))
        }
    }

    /// Where the line being typed is, read from the screen, and how far the entry has scrolled, read from the header,
    /// which scrolls with the text.
    @MainActor private struct TypedLines {
        let app: XCUIApplication
        let test: XCTestCase
        let firstHeader: CGFloat
        var header: CGFloat
        init(app: XCUIApplication, test: XCTestCase) {
            self.app = app
            self.test = test
            firstHeader = app.otherElements["Entry header"].frame.minY
            header = firstHeader
        }

        mutating func check(_ line: String, file: StaticString = #filePath, lineNumber: UInt = #line) {
            let top = app.otherElements["Entry header"].frame.minY
            XCTAssertLessThanOrEqual(
                top, header + 0.5, "\(line): the entry scrolled back.", file: file, line: lineNumber)
            let controls = app.buttons["Formatting"].firstMatch.frame
            let body = app.textViews["Entry text"].frame
            guard let typed = frame(of: line) else {
                XCTFail("\(line) isn't in view.", file: file, line: lineNumber)
                return
            }
            XCTAssertLessThanOrEqual(
                typed.maxY, controls.minY, "\(line) is behind the controls.", file: file, line: lineNumber)
            XCTAssertGreaterThanOrEqual(
                typed.minY, body.minY, "\(line) is above the entry.", file: file, line: lineNumber)
            if top < header - 0.5 {
                // It scrolled only as far as the line needs: the line is just above the controls.
                XCTAssertGreaterThan(
                    typed.maxY, controls.minY - 3 * typed.height, "\(line) scrolled too far.", file: file,
                    line: lineNumber)
            }
            header = top
        }

        /// The recognized text that starts with `line`'s words, in screen points.
        func frame(of line: String) -> CGRect? {
            guard let image = app.screenshot().image.cgImage else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let size = app.frame.size
            let limit = app.buttons["Formatting"].firstMatch.frame.maxY
            for observation in request.results ?? [] {
                guard let text = observation.topCandidates(1).first?.string, Self.reads(text, as: line) else {
                    continue
                }
                let box = observation.boundingBox
                let frame = CGRect(
                    x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width,
                    height: box.height * size.height)
                if frame.minY < limit { return frame }
            }
            return nil
        }

        /// Whether recognized text starts with the line's words. The caret right after the last digit can read as
        /// one more character.
        private static func reads(_ text: String, as line: String) -> Bool {
            let expected = line.split(separator: " ")
            let found = text.split(separator: " ")
            guard found.count >= expected.count else { return false }
            return zip(expected, found).allSatisfy { word, read in
                word == read || (word.allSatisfy(\.isNumber) && read.prefix(while: \.isNumber) == word)
            }
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
