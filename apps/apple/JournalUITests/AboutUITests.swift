import XCTest

/// Settings ▸ About (docs/design/about-and-ratings-2026-10-05.md §1). App Store Guideline 5.1.1(i) requires a privacy
/// policy link inside the app; nothing else would notice it going missing.
final class AboutUITests: XCTestCase {
    @MainActor func testSettingsLinksToThePrivacyPolicyAboveErase() throws {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)

        NavigationTestSupport.openSettings(app)
        let erase = app.buttons["Erase Journals and Settings…"]
        for _ in 0..<6 where !(erase.exists && erase.isHittable) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(erase.waitToAppear(timeout: 5))
        let links = ["Privacy Policy", "Support", "Source Code", "Rate My Journal"].map { app.buttons[$0].firstMatch }
        for link in links { XCTAssertTrue(link.exists, link.description) }
        XCTAssertLessThan(links[0].frame.maxY, erase.frame.minY, "About comes before the standalone Erase section")
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Version ")).firstMatch
        XCTAssertTrue(version.exists, "the version and build number, as Apple's apps show them")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settings with About"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
