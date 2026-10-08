import XCTest

/// The shared parts of the spec screenshot tests (design/spec-screenshots/README.md): they launch the app on a copy of
/// the seeded sample library and write raw PNG captures named `<page-id>-<state>.png`. Like the App Store captures they
/// are opt-in and not part of the checks. design/spec-screenshots/capture.sh seeds the library and passes, through
/// `TEST_RUNNER_` variables, `JOURNAL_SCREENSHOT_LIBRARY` (the pristine seeded library, which each launch copies),
/// `JOURNAL_SCREENSHOT_PASSWORD_FILE` and `JOURNAL_SCREENSHOT_OUTPUT` (the folder the captures are written to).
class SpecCaptureCase: XCTestCase {
    var environment: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // MARK: - Launching

    /// A new folder holding a copy of the seeded sample library, removed with the test.
    func copyOfSampleLibrary() throws -> URL {
        guard let seeded = environment["JOURNAL_SCREENSHOT_LIBRARY"] else {
            throw CaptureError("Run design/spec-screenshots/capture.sh, which seeds the library.")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spec-" + UUID().uuidString)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: seeded), to: folder)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// A new empty folder, for the first launch.
    func emptyLibraryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spec-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Launches the app on `library` (a copy of the sample library by default) and, for the sample library, unlocks it
    /// with the master password: the seeded library has no device key yet.
    @MainActor func launch(
        library: URL? = nil, unlocking: Bool = true, environment extra: [String: String] = [:],
        arguments: [String] = []
    ) throws -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        let folder = try library ?? copyOfSampleLibrary()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = folder.path
        app.launchEnvironment.merge(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        addTeardownBlock { app.terminate() }
        if unlocking { try unlock(app) }
        return app
    }

    /// Relaunches the same app, keeping its library and environment.
    @MainActor func relaunch(_ app: XCUIApplication, unlocking: Bool = true) throws {
        app.terminate()
        app.launch()
        if unlocking { try unlock(app) }
    }

    @MainActor func unlock(_ app: XCUIApplication) throws {
        let field = app.secureTextFields["Master Password"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                field.exists || app.collectionViews["Journals"].exists || NavigationTestSupport.title(app).exists
                    || app.buttons["Show Sidebar"].exists
            }, object: app)
        if XCTWaiter.wait(for: [ready], timeout: 25) != .completed { try require(field, app: app, timeout: 0) }
        guard field.exists else { return }
        field.tap()
        field.typeText(try password())
        app.buttons["Unlock"].firstMatch.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 30))
    }

    func password() throws -> String {
        guard let file = environment["JOURNAL_SCREENSHOT_PASSWORD_FILE"] else {
            throw CaptureError("Run design/spec-screenshots/capture.sh, which names the password file.")
        }
        return try String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Finding things

    /// Waits for an element. When it doesn't appear, the screen and its accessibility tree are written next to the
    /// captures as `failed-<test>`, to show what was there instead.
    @MainActor func require(_ element: XCUIElement, app: XCUIApplication, timeout: TimeInterval = 10) throws {
        guard !element.waitToAppear(timeout: timeout) else { return }
        try? write(app, "failed-" + name.filter { $0.isLetter || $0.isNumber }, settle: false, tree: true)
        throw CaptureError("Missing \(element.description)")
    }

    /// Taps a button by label, waiting for it first.
    @MainActor func tapButton(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 10) throws {
        let button = app.buttons[label].firstMatch
        try require(button, app: app, timeout: timeout)
        button.tap()
    }

    /// Opens an entry of a journal, scrolling the list when the entry is below the visible rows.
    @MainActor func openEntry(_ title: String, journal: String, app: XCUIApplication) throws {
        NavigationTestSupport.selectCollection(journal, app: app)
        let row = app.staticTexts[title].firstMatch
        // Rows under the search field at the bottom of the list count as hittable, so scroll until it is clear of it.
        let clearOfSearch = app.windows.firstMatch.frame.height * 0.8
        for _ in 0..<8 where !(row.exists && row.isHittable && row.frame.midY < clearOfSearch) { app.swipeUp() }
        try require(row, app: app, timeout: 5)
        row.tap()
        try require(NavigationTestSupport.title(app), app: app, timeout: 10)
    }

    /// Goes back one level on iPhone (the entry to its list, the list to the journals).
    @MainActor func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")
        ).firstMatch
        if back.exists, back.isHittable { back.tap() }
    }

    @MainActor func showSidebar(_ app: XCUIApplication) {
        let sidebar = app.buttons["Show Sidebar"].firstMatch
        if sidebar.exists, sidebar.isHittable { sidebar.tap() }
    }

    /// Entry Actions (the entry's ⋯ menu), then an item of it.
    @MainActor func chooseEntryAction(_ item: String, in app: XCUIApplication) throws {
        try tapButton("Entry Actions", in: app)
        try tapMenuItem(item, in: app)
    }

    /// An item of the menu that is open, scrolling the menu when the item is below the visible part.
    @MainActor func tapMenuItem(_ item: String, in app: XCUIApplication) throws {
        let button = app.buttons[item].firstMatch
        try require(button, app: app, timeout: 5)
        for _ in 0..<6 where !button.isHittable {
            let menus = app.collectionViews
            guard menus.count > 0 else { break }
            menus.element(boundBy: menus.count - 1).swipeUp()
        }
        button.tap()
    }

    // MARK: - Capturing

    /// Writes the screen as `<name>.png` in the output folder once animations have finished.
    @MainActor func shot(_ app: XCUIApplication, _ name: String, settle: Bool = true) throws {
        try write(app, name, settle: settle, tree: environment["JOURNAL_SPEC_TREES"]?.isEmpty == false)
    }

    /// Captures the screen unless `marker` is showing, which means the screen lists something of the machine's own
    /// network (servers found by Bonjour): the capture is then removed and written to `skipped.txt` instead, so
    /// nothing that isn't sample data reaches the repository.
    @MainActor func shot(_ app: XCUIApplication, _ name: String, unlessShowing marker: String) throws {
        try write(app, name, settle: false, tree: false)
        guard app.staticTexts[marker].exists, let output = environment["JOURNAL_SCREENSHOT_OUTPUT"] else { return }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".png"))
        let note = "\(name): the screen shows \"\(marker)\", which lists servers found on this network.\n"
        let skipped = folder.appendingPathComponent("skipped.txt")
        let existing = (try? String(contentsOf: skipped, encoding: .utf8)) ?? ""
        try (existing + note).write(to: skipped, atomically: true, encoding: .utf8)
    }

    @MainActor private func write(_ app: XCUIApplication, _ name: String, settle: Bool, tree: Bool) throws {
        guard let output = environment["JOURNAL_SCREENSHOT_OUTPUT"] else {
            throw CaptureError("Run design/spec-screenshots/capture.sh, which names the output folder.")
        }
        if settle { Thread.sleep(forTimeInterval: 1.2) }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"))
        if tree {
            try app.debugDescription.write(
                to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        }
    }
}
