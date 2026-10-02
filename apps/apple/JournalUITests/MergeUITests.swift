import JournalCore
import UIKit
import XCTest

/// A device that already has journals joins a server by scanning a connected device's code, as a new device does,
/// and its journals are merged with the server's after the person agrees on Merge Journals
/// (docs/design/join-with-local-journals.md). Runs against a disposable server from scripts/test-native-pairing.sh.
final class MergeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor func testMergeLocalJournalsWithAScannedCode() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["JOURNAL_TEST_MERGE_SERVER"], address.hasPrefix("http://127.0.0.1:"),
            let setupCode = environment["JOURNAL_TEST_MERGE_CODE"], !setupCode.isEmpty
        else {
            throw XCTSkip("Run scripts/test-native-pairing.sh for the disposable-server merge check.")
        }
        // The connected device set the server up with a "Default" journal of its own.
        let key = try VaultCrypto.generateKey()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: "Synthetic merge fixture password")
        let grant = try await ServerClient(address: address).initialize(
            code: setupCode, envelope: recovery.0, recoverySecret: recovery.1, deviceName: "Fixture Mac")
        let owner = try ServerClient(address: address, token: grant.token)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Default")
        try await store.save(journal)
        try await store.save(JournalItem(kind: "entry", journalID: journal.id, title: "Synced reflection"))
        try await SyncEngine(store: store, client: owner).synchronize()

        // This device tried the app first and wrote an entry.
        let host = try XCTUnwrap(PairingInviteHost(server: address))
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UI_TEST_ID"] = UUID().uuidString
        app.launchEnvironment["JOURNAL_TEST_SCANNED_CODE"] = host.invite.text
        app.launch()
        let start = app.buttons["Start a Journal"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        NavigationTestSupport.createPasswordJournal(app)
        let create = app.buttons["New Entry"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitForExistence(timeout: 10))
        app.typeText("Local note")

        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].tap()
        let connect = app.buttons["Connect to a Server…"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        let scan = app.buttons["Scan Code"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "A device with journals can scan a code too.")
        scan.tap()
        let merge = app.navigationBars["Merge Journals"]
        XCTAssertTrue(merge.waitForExistence(timeout: 10))
        let components = try XCTUnwrap(URLComponents(string: address))
        let serverHost = "\(components.host ?? ""):\(components.port ?? 0)"
        XCTAssertTrue(app.staticTexts["Merge only if \(serverHost) is your server."].exists)
        let early = try? await owner.pairingCandidate(code: host.invite.code)
        XCTAssertNil(early, "Nothing is asked of the connected device before Merge.")
        capture(app, "Merge Journals")
        merge.buttons["Merge"].tap()
        XCTAssertTrue(app.staticTexts["Finish on Your Other Device"].waitForExistence(timeout: 10))

        var candidate: PairingCandidate?
        for _ in 0..<30 where candidate == nil {
            candidate = try? await owner.pairingCandidate(code: host.invite.code)
            if candidate == nil { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        let request = try XCTUnwrap(candidate)
        XCTAssertTrue(host.verifies(request))
        let approval = try await owner.preparePairingApproval(host.challenge(request))
        try await owner.approvePairing(approval, masterKey: key)

        // Both entries are in one "Default" journal.
        XCTAssertTrue(app.buttons["Sync Now"].waitForExistence(timeout: 30))
        // Sync Now shows that it synced (docs/design/sync-now-and-done.md).
        app.buttons["Sync Now"].tap()
        capture(app, "Sync Now running")
        let synced = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Just now"))
        XCTAssertTrue(synced.firstMatch.waitForExistence(timeout: 10))
        capture(app, "Last synced after Sync Now")
        NavigationTestSupport.closeSettings(app)
        NavigationTestSupport.showJournals(app)
        let defaults = app.collectionViews["Journals"].staticTexts.matching(
            NSPredicate(format: "label == %@", "Default"))
        XCTAssertEqual(defaults.count, 1, "Same-name journals are combined.")
        NavigationTestSupport.selectCollection("Default", app: app)
        XCTAssertTrue(app.staticTexts["Synced reflection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Local note"].exists)
        capture(app, "Merged journal")
        try await SyncEngine(store: store, client: owner).synchronize()
        let titles = try await store.items().filter { $0.kind == "entry" }.map(\.title).sorted()
        XCTAssertEqual(titles, ["Local note", "Synced reflection"], "The connected device receives the merged entry.")
        app.terminate()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
