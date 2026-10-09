import JournalCore
import XCTest

/// Every action Settings ▸ Sync offers when sync breaks (docs/design/sync-health-and-recovery.md §2), end to end
/// against a real server that scripts/test-sync-recovery-ui.sh changes when a test asks: removing this device,
/// restoring a backup, wiping the data folder, stopping it and putting another web server at its address. Each journey ends with a new device downloading every
/// entry exactly once.
final class SyncRecoveryUITests: XCTestCase {
    private let password = "Native UI fixture password"
    private var control: URL?
    private var address = ""
    /// The state message last seen, which a sync that succeeds must replace.
    private var shownMessage: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let server = environment["JOURNAL_TEST_HEALTH_SERVER"], server.hasPrefix("http://127.0.0.1:"),
            let controlPath = environment["JOURNAL_TEST_HEALTH_CONTROL"], !controlPath.isEmpty
        else {
            throw XCTSkip("Run scripts/test-sync-recovery-ui.sh for the sync recovery journeys.")
        }
        address = server
        control = URL(fileURLWithPath: controlPath)
    }

    /// Reconnect after a removal, after a restore and after a reset, Try Again while the server is down for two days'
    /// worth of waiting, Check Again for another web server at its address, and Stop Syncing, then connecting again.
    @MainActor func testEveryRecoveryActionWithAPasswordLibrary() async throws {
        try request("reset")
        let library = UUID().uuidString
        var app = launch(library)
        let start = app.buttons["Start a Journal"]
        XCTAssertTrue(start.waitToAppear(timeout: 15))
        start.tap()
        NavigationTestSupport.createPasswordJournal(app)
        writeEntry("First entry", app: app)
        openSyncSettings(app)
        tap(app.buttons["Connect to a Server…"])
        chooseServer(app)
        try setUpServer(app)
        XCTAssertTrue(app.staticTexts["Last Synced"].waitToAppear(timeout: 30))
        capture(app, "1 Syncing normally")

        // Removed in Devices on another device: Reconnect signs in, with no Merge step.
        try await Self.removeThisDevice(address: address, password: password)
        tap(app.buttons["Sync Now"])
        expectMessage(
            "This device no longer has access to the server. Your journals are still on this device. To reconnect, you need your password or a connected device.",
            app: app)
        XCTAssertFalse(app.buttons["Add Device…"].exists, "Devices is absent while the server refuses this device.")
        capture(app, "2 This device was removed")
        tap(app.buttons["Reconnect…"])
        XCTAssertTrue(app.navigationBars["Reconnect"].waitToAppear(timeout: 15))
        signIn(app)
        expectSynced(app)
        // Devices lists the devices again without reopening the pane, this one included.
        XCTAssertTrue(scrollTo(app.buttons["Add Device…"], app: app))
        XCTAssertTrue(scrollTo(labeled("Fixture iPad", app: app), app: app))

        // Restored from a backup that lacks the latest entry: Reconnect sends it back.
        try request("backup")
        app.terminate()
        app = launch(library)
        writeEntry("After the backup", app: app)
        openSyncSettings(app)
        tap(app.buttons["Sync Now"])
        expectSynced(app)
        app.terminate()
        try request("restore")
        app = launch(library)
        openSyncSettings(app)
        expectMessage(
            "The server was restored or replaced and doesn’t recognize this device. Your journals are still on this device.",
            app: app)
        capture(app, "3 Restored from a backup")
        tap(app.buttons["Reconnect…"])
        signIn(app)
        expectSynced(app)

        // Wiped: automatic sync stopped, so opening the app again checks it; Reconnect uses the new code.
        app.terminate()
        try request("reset")
        app = launch(library)
        openSyncSettings(app)
        expectMessage("The server isn’t set up. Your journals are still on this device.", app: app)
        capture(app, "4 The server isn't set up")
        tap(app.buttons["Reconnect…"])
        try setUpServer(app)
        expectSynced(app)

        // Down, with the last sync two days ago: Try Again once it's back.
        app.terminate()
        try request("stop-and-age")
        app = launch(library)
        writeEntry("Written while the server was down", app: app)
        openSyncSettings(app)
        expectMessage(
            "Can’t reach the server right now. Your changes are saved on this device and will sync automatically.",
            app: app)
        XCTAssertTrue(labeled("Not on Server Yet, 1 item", app: app).waitToAppear(timeout: 30))
        capture(app, "5 Unreachable with a change waiting two days")
        try request("start")
        tap(app.buttons["Try Again"])
        expectSynced(app)

        // Another web server answers at the address: Check Again once the journal server is back.
        try request("impostor")
        tap(app.buttons["Sync Now"])
        expectMessage(
            "The server address doesn’t lead to a My Journal server. Your changes are saved on this device.", app: app)
        capture(app, "6 Not a My Journal server")
        try request("genuine")
        // The app may notice the journal server is back and recover before the tap; both end synced. A tap at the
        // button's place lands on Sync Now in its row if recovery wins the race after the check.
        let checkAgain = app.buttons["Check Again"]
        if checkAgain.exists { checkAgain.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        expectSynced(app)

        // Stop Syncing keeps everything; connecting again joins by identity after Merge Journals asks.
        tap(app.buttons["Stop Syncing…"])
        let stop = app.buttons["Stop Syncing"]
        XCTAssertTrue(stop.waitToAppear(timeout: 5))
        capture(app, "7 Stop Syncing")
        stop.tap()
        // The footer continues with a How to Set Up a Server link in the same text.
        let savedHere = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Your journals are saved on this device.")
        ).firstMatch
        XCTAssertTrue(savedHere.waitToAppear(timeout: 10))
        capture(app, "8 After Stop Syncing")
        tap(app.buttons["Connect to a Server…"])
        chooseServer(app)
        let merge = app.navigationBars["Merge Journals"]
        XCTAssertTrue(merge.waitToAppear(timeout: 15))
        merge.buttons["Merge"].tap()
        signIn(app)
        expectSynced(app)
        app.terminate()
        try await Self.expectEveryEntryOnce(
            ["First entry", "After the backup", "Written while the server was down"], address: address,
            password: password)
    }

    // MARK: The other device

    /// Another device signs in and revokes every other device.
    private static func removeThisDevice(address: String, password: String) async throws {
        let anonymous = try ServerClient(address: address)
        let other = try await anonymous.recoverVault(
            password, parameters: anonymous.recoveryParameters(), deviceName: "Fixture iPad")
        let owner = try ServerClient(address: address, token: other.grant.token)
        for device in try await owner.devices() where device.id != other.grant.deviceId && !device.revoked {
            try await owner.revoke(device.id)
        }
    }
    /// A new device downloads the library: every entry written in the journey is there exactly once, and no journal
    /// or template name repeats.
    private static func expectEveryEntryOnce(_ titles: [String], address: String, password: String) async throws {
        let anonymous = try ServerClient(address: address)
        let recovered = try await anonymous.recoverVault(
            password, parameters: anonymous.recoveryParameters(), deviceName: "Fixture check")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: recovered.key, protection: .encrypted)
        try await SyncEngine(store: store, client: ServerClient(address: address, token: recovered.grant.token))
            .synchronize()
        let items = try await store.items().filter { $0.deletedAt == nil }
        try await store.close()
        let entries = items.filter { $0.kind == "entry" }.map(\.title)
        for title in titles { XCTAssertEqual(entries.filter { $0 == title }.count, 1, "“\(title)” on the server") }
        for kind in ["journal", "template"] {
            let names = items.filter { $0.kind == kind }.map { $0.title.lowercased() }
            XCTAssertEqual(Set(names).count, names.count, "A \(kind) name repeats: \(names)")
        }
    }

    // MARK: The app

    @MainActor private func launch(_ library: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = library
        app.launch()
        return app
    }
    /// A new entry with `text` as its title. The app may open on the entry it showed last, where New Entry is a step
    /// back.
    @MainActor private func writeEntry(_ text: String, app: XCUIApplication) {
        let create = app.buttons["New Entry"].firstMatch
        let title = NavigationTestSupport.title(app)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in create.exists || title.exists }, object: app)
        XCTAssertEqual(Waiting.wait(for: ready, timeout: 15), .completed)
        NavigationTestSupport.newEntryFromList(app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        app.typeText(text)
    }
    @MainActor private func openSyncSettings(_ app: XCUIApplication) {
        NavigationTestSupport.openSettings(app)
        tap(app.buttons["Sync"])
    }
    @MainActor private func chooseServer(_ app: XCUIApplication) {
        let field = app.textFields["Server Address"]
        XCTAssertTrue(field.waitToAppear(timeout: 5))
        field.tap()
        field.typeText(address)
        app.navigationBars["Connect to a Server"].buttons["Continue"].tap()
    }
    /// The setup-code step, then the library's password, through to Server Is Ready.
    @MainActor private func setUpServer(_ app: XCUIApplication) throws {
        let setUp = app.navigationBars["Set Up Server"]
        XCTAssertTrue(setUp.waitToAppear(timeout: 15))
        let code = try String(contentsOf: try file("setup-code"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let field = app.textFields["Setup Code"]
        field.tap()
        field.typeText(code)
        setUp.buttons["Continue"].tap()
        let enter = app.navigationBars["Enter Master Password"]
        XCTAssertTrue(enter.waitToAppear(timeout: 15))
        let phrase = app.secureTextFields["Master Password"]
        phrase.tap()
        phrase.typeText(password)
        enter.buttons["Set Up"].tap()
        XCTAssertTrue(app.staticTexts["Server Is Ready"].waitToAppear(timeout: 30))
        app.buttons["Done"].tap()
    }
    /// Reconnect, opened by an action, goes straight to signing in to this device's server.
    @MainActor private func signIn(_ app: XCUIApplication) {
        let enter = app.navigationBars["Enter Master Password"]
        XCTAssertTrue(enter.waitToAppear(timeout: 20))
        let phrase = app.secureTextFields["Master Password"]
        phrase.tap()
        phrase.typeText(password)
        enter.buttons["Sign In"].tap()
    }
    /// A sync just succeeded: the state message shown before is gone, Sync Now is the action again, Last Synced says
    /// "Just now", and nothing waits for the server.
    @MainActor private func expectSynced(_ app: XCUIApplication, line: UInt = #line) {
        if let message = shownMessage {
            let gone = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: app.staticTexts[message])
            XCTAssertEqual(Waiting.wait(for: gone, timeout: 40), .completed, "Still: \(message)", line: line)
            shownMessage = nil
        }
        XCTAssertTrue(app.buttons["Sync Now"].waitToAppear(timeout: 40), line: line)
        XCTAssertTrue(labeled("Last Synced, Just now", app: app).waitToAppear(timeout: 10), line: line)
        let waiting = labeled("Not on Server Yet", app: app)
        let sent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: waiting)
        if Waiting.wait(for: sent, timeout: 15) != .completed {
            capture(app, "Still waiting at line \(line)")
            XCTFail("Items still wait for the server", line: line)
        }
    }
    /// An element whose label starts with `text`, such as a row read as one element ("Last Synced, Just now").
    @MainActor private func labeled(_ text: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }
    @MainActor private func expectMessage(_ message: String, app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts[message].waitToAppear(timeout: 30), message)
        shownMessage = message
    }
    /// Scrolls the pane until `element` exists, which a list may not build until it is near the screen.
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.waitToAppear(timeout: 5) { return true }
            app.swipeUp()
        }
        return element.exists
    }
    @MainActor private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitToAppear(timeout: 15))
        element.tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: The script

    private func file(_ name: String) throws -> URL { try XCTUnwrap(control).appendingPathComponent(name) }
    /// Asks the script to change the server, and waits until it has.
    private func request(_ command: String) throws {
        let done = try file("done-" + command)
        try? FileManager.default.removeItem(at: done)
        try command.write(to: try file("request"), atomically: true, encoding: .utf8)
        for _ in 0..<900 where !FileManager.default.fileExists(atPath: done.path) { usleep(100_000) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: done.path), "The script didn't \(command) the server")
    }
}
