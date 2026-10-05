import JournalCore
import XCTest

/// Captures the iPhone and iPad App Store screenshots from the seeded sample library
/// (docs/app-store/screenshots-plan.md). It isn't part of the checks: design/app-store/capture-ios.sh seeds the
/// library, sets the simulator's status bar and appearance, and passes these through `TEST_RUNNER_` variables:
/// `JOURNAL_SCREENSHOT_LIBRARY` (the app data folder), `JOURNAL_SCREENSHOT_PASSWORD_FILE` and
/// `JOURNAL_SCREENSHOT_OUTPUT` (the folder the PNG captures are written to).
final class ScreenshotCaptureUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Frame 1: writing. iPhone shows the editor; iPad the three columns.
    @MainActor func test1Writing() throws {
        let app = try launch()
        NavigationTestSupport.openEntry("Slow Sunday", journal: "Personal", app: app)
        if isPad { showSidebar(app) }
        try capture(app, "01-writing-light")
    }

    /// Frame 3: a server that "MacBook Pro" set up with the sample library. The iPad joins first, approved by the
    /// Mac, then approves the iPhone and shows the check code; the iPhone then lists all three devices. Both
    /// simulators run this test at the same time and meet through files next to the approving device's state.
    /// design/app-store/capture-sync.sh starts a disposable local server and passes its address and setup code.
    @MainActor func test3Sync() async throws {
        guard let address = environment["JOURNAL_SCREENSHOT_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let empty = environment["JOURNAL_SCREENSHOT_EMPTY_LIBRARY"]
        else { throw CaptureError("Run design/app-store/capture-sync.sh, which starts the server.") }
        let (owner, key, version) = try await approvingDevice(address: address)
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = empty
        app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        app.launch()
        let connectToServer = app.buttons["Connect to a Server…"].firstMatch
        try require(connectToServer, timeout: 15)
        connectToServer.tap()
        let field = app.textFields["Server Address"]
        try require(field, timeout: 5)
        field.tap()
        field.typeText(address)
        app.buttons["Continue"].tap()
        let useDevice = app.buttons["Use a Connected Device Instead…"]
        try require(useDevice, timeout: 10)
        useDevice.tap()
        let codeView = app.staticTexts["pairing-code"]
        try require(codeView, timeout: 10)
        let code = (codeView.value as? String ?? codeView.label).filter(\.isNumber)
        let meeting = try meetingPlace()
        if isPad {
            let candidate = try await owner.pairingCandidate(code: code)
            let approval = try await owner.preparePairingApproval(PairingChallenge(candidate))
            try await owner.approvePairing(approval, masterKey: key, recoveryVersion: version)
        } else {
            try code.write(to: meeting.appendingPathComponent("iphone-code"), atomically: true, encoding: .utf8)
        }
        let connect = app.buttons["Connect"]
        try require(connect, timeout: isPad ? 10 : 180)
        connect.tap()
        NavigationTestSupport.showJournals(app)
        try require(app.staticTexts["Personal"].firstMatch, timeout: 30)
        if isPad {
            NavigationTestSupport.openEntry("Slow Sunday", journal: "Personal", app: app)
        } else {
            // The same journals on the phone, for the Mac frame about sync.
            NavigationTestSupport.selectCollection("Personal", app: app)
            try require(app.staticTexts["Slow Sunday"].firstMatch, timeout: 30)
            try capture(app, "03-personal-list-light")
        }
        NavigationTestSupport.openSettings(app)
        app.buttons["Devices"].tap()
        try require(app.staticTexts["MacBook Pro"].firstMatch, timeout: 10)
        if isPad { try approveIPhone(app, meeting: meeting) } else { try capture(app, "03-devices-light") }
    }

    /// On the iPad: Add Device… with the code the iPhone shows, captured at the check code, then approved.
    @MainActor private func approveIPhone(_ app: XCUIApplication, meeting: URL) throws {
        let add = app.buttons["Add Device…"]
        try require(add, timeout: 10)
        add.tap()
        let enterCode = app.buttons["Enter Code Instead…"]
        try require(enterCode, timeout: 10)
        enterCode.tap()
        let field = app.textFields["Pairing Code"]
        try require(field, timeout: 10)
        try "ready".write(to: meeting.appendingPathComponent("ipad-ready"), atomically: true, encoding: .utf8)
        let file = meeting.appendingPathComponent("iphone-code")
        for _ in 0..<600 where !FileManager.default.fileExists(atPath: file.path) {
            Thread.sleep(forTimeInterval: 0.5)
        }
        field.tap()
        field.typeText(try String(contentsOf: file, encoding: .utf8))
        let hide = app.buttons["Hide keyboard"].firstMatch
        if hide.exists, hide.isHittable { hide.tap() }
        let proceed = app.buttons.matching(identifier: "Continue").allElementsBoundByIndex.last { $0.isHittable }
        try XCTUnwrap(proceed, "No Continue button").tap()
        try require(app.staticTexts["check-code"], timeout: 60)
        try capture(app, "03-pairing-light")
        app.buttons["Approve"].tap()
        // The iPhone's run finishes once it is connected; the iPad only has to wait for the approval to be sent.
        XCTAssertTrue(app.staticTexts["check-code"].waitForNonExistence(timeout: 60))
    }

    /// The folder both simulators' runs share for the pairing code.
    private func meetingPlace() throws -> URL {
        guard let state = environment["JOURNAL_SCREENSHOT_SERVER_STATE"] else {
            throw CaptureError("Run design/app-store/capture-sync.sh.")
        }
        return URL(fileURLWithPath: state).deletingLastPathComponent()
    }

    /// The device that set up the server: it uploads the sample library as "MacBook Pro" the first time and keeps its
    /// credentials in the state file, so the next device is approved by it as well.
    @MainActor private func approvingDevice(address: String) async throws -> (ServerClient, Data, Int) {
        guard let library = environment["JOURNAL_SCREENSHOT_LIBRARY"],
            let passwordFile = environment["JOURNAL_SCREENSHOT_PASSWORD_FILE"],
            let statePath = environment["JOURNAL_SCREENSHOT_SERVER_STATE"]
        else { throw CaptureError("Run design/app-store/capture-sync.sh.") }
        let stateURL = URL(fileURLWithPath: statePath)
        if let data = try? Data(contentsOf: stateURL) {
            let state = try JSONDecoder().decode(ApprovingDevice.self, from: data)
            return (try ServerClient(address: address, token: state.token), state.key, state.version)
        }
        let folder = URL(fileURLWithPath: library, isDirectory: true)
        let configuration = try JournalCoding.decoder().decode(
            SeededConfiguration.self, from: Data(contentsOf: folder.appendingPathComponent("configuration.json")))
        let password = try String(contentsOfFile: passwordFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let (key, secret) = try VaultCrypto.recover(configuration.recovery, phrase: password)
        guard let setupCode = environment["JOURNAL_SCREENSHOT_SETUP_CODE"] else {
            throw CaptureError("No setup code for the server.")
        }
        let grant = try await ServerClient(address: address).initialize(
            code: setupCode, envelope: configuration.recovery, recoverySecret: secret, deviceName: "MacBook Pro")
        let owner = try ServerClient(address: address, token: grant.token)
        let store = try JournalStore(
            directory: folder.appendingPathComponent(configuration.storageFolder), key: key,
            protection: configuration.recovery.contentProtection)
        try await SyncEngine(store: store, client: owner).synchronize()
        try await store.close()
        let version = configuration.recovery.formatVersion
        try JSONEncoder().encode(ApprovingDevice(token: grant.token, key: key, version: version)).write(to: stateURL)
        return (owner, key, version)
    }

    /// Frame 4: the Personal list with its Pinned section, then search, on iPhone; Version History on iPad.
    @MainActor func test4FindAgain() throws {
        let app = try launch()
        if isPad {
            NavigationTestSupport.openEntry("Bread, attempt four", journal: "Personal", app: app)
            app.buttons["Entry Actions"].firstMatch.tap()
            let history = app.buttons["Version History…"]
            try require(history, timeout: 5)
            history.tap()
            try require(app.navigationBars["Version History"], timeout: 10)
            try capture(app, "04-history-light")
        } else {
            NavigationTestSupport.selectCollection("Personal", app: app)
            let search = app.searchFields["Search Personal"]
            try capturePinned(app, search: search)
            search.tap()
            search.typeText("walk\n")
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            try capture(app, "04-search-light")
        }
    }

    /// The Personal list from the top: its search field shown but not focused, then the Pinned section.
    @MainActor private func capturePinned(_ app: XCUIApplication, search: XCUIElement) throws {
        for _ in 0..<3 where !(search.exists && search.isHittable) {
            app.swipeDown()
        }
        try require(search, timeout: 5)
        try require(app.staticTexts["Pinned"].firstMatch, timeout: 10)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The search field isn't focused")
        try capture(app, "04-pinned-light")
    }

    /// Frame 5: the journals in their chosen order, in edit mode, on iPhone; the Work journal with a table on iPad.
    @MainActor func test5Journals() throws {
        let app = try launch()
        if isPad {
            NavigationTestSupport.openEntry("Offsite ideas", journal: "Work", app: app)
            showSidebar(app)
            try capture(app, "05-journals-light")
        } else {
            NavigationTestSupport.selectCollection("Work", app: app)
            try capture(app, "05-work-list")
            NavigationTestSupport.showJournals(app)
            try capture(app, "05-journals-list")
            try captureJournalsInEditMode(app)
        }
    }

    /// Edit in Journals, captured once the reorder handles show, then Done.
    @MainActor private func captureJournalsInEditMode(_ app: XCUIApplication) throws {
        let edit = app.buttons["Edit"].firstMatch
        try require(edit, timeout: 5)
        edit.tap()
        let handle = app.collectionViews["Journals"].descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder")).firstMatch
        try require(handle, timeout: 5)
        try capture(app, "05-journals-edit-light")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
    }

    /// Frame 6 runs with the simulator in dark appearance.
    @MainActor func test6Dark() throws {
        let app = try launch()
        NavigationTestSupport.openEntry("Porto, day two", journal: "Travel", app: app)
        if isPad { showSidebar(app) }
        try capture(app, "06-dark")
    }

    /// Frame 2: Privacy with App Lock on. It turns App Lock on, so it runs last.
    @MainActor func test9Privacy() throws {
        // A test build answers Face ID itself; the simulator can't be looked at.
        let app = try launch(environment: ["JOURNAL_UI_TEST_DEVICE_AUTH": "success"])
        if isPad { NavigationTestSupport.openEntry("Slow Sunday", journal: "Personal", app: app) }
        NavigationTestSupport.openSettings(app)
        app.buttons["Privacy"].tap()
        let appLock = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Require'")).firstMatch
        try require(appLock, timeout: 5)
        if appLock.value as? String == "0" { appLock.switches.firstMatch.tap() }
        XCTAssertTrue(app.buttons["Lock My Journal"].waitForExistence(timeout: 10))
        try capture(app, "02-privacy-light")
    }

    // MARK: - Helpers

    @MainActor private func launch(environment extra: [String: String] = [:]) throws -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        guard let library = environment["JOURNAL_SCREENSHOT_LIBRARY"],
            let passwordFile = environment["JOURNAL_SCREENSHOT_PASSWORD_FILE"]
        else { throw CaptureError("Run design/app-store/capture-ios.sh, which names the library.") }
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = library
        app.launchEnvironment.merge(extra) { _, new in new }
        app.launchArguments += ["-AppleLanguages", "(en-US)", "-AppleLocale", "en_US"]
        app.launch()
        // The seeded library has no device key yet, so the lock screen asks for the master password.
        let unlock = app.secureTextFields["Master Password"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                unlock.exists || app.collectionViews["Journals"].exists || NavigationTestSupport.title(app).exists
                    || app.buttons["Show Sidebar"].exists
            }, object: app)
        if XCTWaiter.wait(for: [ready], timeout: 20) != .completed { try require(unlock, timeout: 0) }
        if unlock.exists {
            let field = unlock
            field.tap()
            let password = try String(contentsOfFile: passwordFile, encoding: .utf8)
            field.typeText(password.trimmingCharacters(in: .whitespacesAndNewlines))
            app.buttons["Unlock"].firstMatch.tap()
            XCTAssertTrue(unlock.waitForNonExistence(timeout: 30))
        }
        return app
    }

    /// Waits for an element. When it doesn't appear, the screen and its accessibility tree are written next to
    /// the captures to show what was there instead.
    @MainActor private func require(_ element: XCUIElement, timeout: TimeInterval = 10) throws {
        guard !element.waitForExistence(timeout: timeout) else { return }
        let name = "failed-" + self.name.filter { $0.isLetter || $0.isNumber }
        try? capture(XCUIApplication(), name, settle: false)
        throw CaptureError("Missing \(element.description)")
    }

    @MainActor private func showSidebar(_ app: XCUIApplication) {
        let sidebar = app.buttons["Show Sidebar"].firstMatch
        if sidebar.exists, sidebar.isHittable { sidebar.tap() }
    }

    /// Waits for animations to finish, then writes the screen at its native size.
    @MainActor private func capture(_ app: XCUIApplication, _ name: String, settle: Bool = true) throws {
        guard let output = environment["JOURNAL_SCREENSHOT_OUTPUT"] else {
            throw CaptureError("Run design/app-store/capture-ios.sh, which names the output folder.")
        }
        if settle { Thread.sleep(forTimeInterval: 1.5) }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"))
        try app.debugDescription.write(
            to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
    }
}

struct CaptureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The part of the seeded library's configuration the approving device needs.
private struct SeededConfiguration: Decodable {
    var recovery: RecoveryEnvelope
    var storageFolder: String
}

/// The approving device's credentials, kept between the iPad and iPhone runs.
private struct ApprovingDevice: Codable {
    var token: String
    var key: Data
    var version: Int
}
