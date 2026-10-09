import JournalCore
import XCTest

final class AppLockUITests: XCTestCase {
    /// App Lock uses the device's authentication, which a test build answers from `JOURNAL_UI_TEST_DEVICE_AUTH`
    /// (docs/design/app-lock-system-auth.md). The seeded library has no device key, so the first launch recovers.
    @MainActor func testDeviceAuthenticationLocksAndUnlocksWithoutLosingWriting() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppLock-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "success"
        app.launch()
        try recover(fixture, app: app)
        try openEntry(fixture.entry.title, app: app)
        NavigationTestSupport.openSettings(app)
        try turnOnAppLock(app: app)
        let lock = app.buttons["Lock My Journal"]
        try reveal(lock, app: app)
        capture(app, "App Lock on in Privacy settings")
        lock.tap()
        // Locking by hand doesn't ask at once, or Face ID would open the journal again.
        let unlock = app.buttons["Unlock with Face ID"]
        XCTAssertTrue(unlock.waitToAppear(timeout: 10))
        XCTAssertTrue(app.staticTexts["My Journal Is Locked"].exists)
        XCTAssertFalse(app.textViews["Entry text"].exists)
        capture(app, "Locked with Unlock with Face ID")
        unlock.tap()
        try openEntry(fixture.entry.title, app: app)

        // A cancelled request keeps the journal locked and says nothing.
        app.terminate()
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "cancel"
        app.launch()
        XCTAssertTrue(unlock.waitToAppear(timeout: 15))
        XCTAssertFalse(app.textViews["Entry text"].exists)
        XCTAssertFalse(app.staticTexts["My Journal couldn’t be unlocked. Try again."].exists)
        XCTAssertFalse(app.buttons["Use Recovery Key"].exists)
        capture(app, "Cancelled request stays locked")

        // When the device can't authenticate, the recovery key still opens the journal, and App Lock stays on.
        app.terminate()
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "unavailable"
        app.launch()
        let problem = app.staticTexts["My Journal couldn’t be unlocked. Try again."]
        XCTAssertTrue(problem.waitToAppear(timeout: 15))
        let recoverInstead = app.buttons["Use Recovery Key"]
        try reveal(recoverInstead, app: app, container: app.scrollViews.firstMatch)
        capture(app, "Unavailable device authentication offers the recovery key")
        recoverInstead.tap()
        try enter("Recovery Key", value: fixture.phrase, app: app)
        try reveal(app.buttons["Unlock"], app: app, container: app.scrollViews.firstMatch)
        app.buttons["Unlock"].tap()
        try openEntry(fixture.entry.title, app: app)

        // At launch the system is asked without a tap.
        app.terminate()
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "success"
        app.launch()
        try openEntry(fixture.entry.title, app: app)
        capture(app, "Launch unlocks after Face ID")
        app.terminate()
        let configuration = try JournalCoding.decoder().decode(
            Configuration.self, from: Data(contentsOf: root.appendingPathComponent("configuration.json")))
        XCTAssertEqual(configuration.appLock, true)
        let store = try JournalStore(directory: root, key: fixture.key)
        let entry = try await store.item(fixture.entry.id)
        XCTAssertEqual(entry, fixture.entry)
        try await store.close()
    }

    @MainActor func testMissingDeviceKeyRequiresRecoveryWithAppLockOn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MissingKeyUI-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root, appLock: true)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "success"
        app.launch()
        let explanation = app.staticTexts[
            "Your device key is unavailable. Use your recovery key to unlock your journals."]
        guard explanation.waitToAppear(timeout: 15) else { throw NavigationFailure.unreachableAction }
        XCTAssertFalse(app.buttons["Unlock with Face ID"].exists, "Face ID can’t replace a missing key.")
        XCTAssertFalse(app.textViews["Entry title"].exists)
        try reveal(explanation, app: app, container: app.scrollViews.firstMatch)
        capture(app, "Missing device key asks for the recovery key")
        try enter("Recovery Key", value: fixture.phrase, app: app)
        try reveal(app.buttons["Unlock"], app: app, container: app.scrollViews.firstMatch)
        app.buttons["Unlock"].tap()
        try openEntry(fixture.entry.title, app: app)
        app.terminate()
        app.launch()
        try openEntry(fixture.entry.title, app: app)
        capture(app, "Missing-key recovery keeps App Lock and writing after relaunch")
        app.terminate()
        let store = try JournalStore(directory: root, key: fixture.key)
        let entry = try await store.item(fixture.entry.id)
        XCTAssertEqual(entry, fixture.entry)
        try await store.close()
    }

    @MainActor func testBackgroundLockHidesTheKeptVersionNoticeAndLosesNeitherVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConflictLock-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root, withConflict: true)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        // Turning on succeeds; the prompt on return from the background is cancelled; the button then unlocks.
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "success,cancel,success"
        app.launch()
        try recover(fixture, app: app)
        try openEntry(fixture.entry.title, app: app)
        NavigationTestSupport.openSettings(app)
        try turnOnAppLock(app: app)
        NavigationTestSupport.closeSettings(app)
        try openEntry(fixture.entry.title, app: app)
        // The version an earlier build left for review was kept as a separate entry when the library opened.
        let showOther = app.buttons["Show Other Version"]
        guard showOther.waitToAppear(timeout: 10) else { throw NavigationFailure.unreachableAction }
        capture(app, "Kept-version notice before background lock")
        XCUIDevice.shared.press(.home)
        app.activate()
        guard app.staticTexts["My Journal Is Locked"].waitToAppear(timeout: 10) else {
            throw NavigationFailure.unreachableAction
        }
        XCTAssertFalse(showOther.exists)
        XCTAssertFalse(app.textViews["Entry text"].exists)
        capture(app, "Returning from background hides the notice")
        let unlock = app.buttons["Unlock with Face ID"]
        try reveal(unlock, app: app, container: app.scrollViews.firstMatch)
        unlock.tap()
        try openEntry(fixture.entry.title, app: app)
        guard showOther.waitToAppear(timeout: 10) else { throw NavigationFailure.unreachableAction }
        capture(app, "Unseen notice available after unlocking")
        app.terminate()
        let store = try JournalStore(directory: root, key: fixture.key)
        let local = try await store.item(fixture.entry.id)
        XCTAssertEqual(local?.document, fixture.entry.document, "This device's version is unchanged")
        let entries = try await store.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 2, "The other version is an entry of its own")
        XCTAssertEqual(entries.filter { $0.document.text == "Preserve the other version too." }.count, 1)
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        try await store.close()
    }

    /// The seeded library has no device key: the lock screen asks for the recovery key at once.
    @MainActor private func recover(_ fixture: Fixture, app: XCUIApplication) throws {
        try enter("Recovery Key", value: fixture.phrase, app: app)
        capture(app, "Recovery key entered securely")
        try reveal(app.buttons["Unlock"], app: app, container: app.scrollViews.firstMatch)
        app.buttons["Unlock"].tap()
    }
    @MainActor private func openEntry(_ title: String, app: XCUIApplication) throws {
        let editor = app.textViews["Entry title"]
        let row = app.staticTexts[title].firstMatch
        let journals = app.collectionViews["Journals"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in editor.exists || row.exists || journals.exists }, object: nil)
        guard Waiting.wait(for: ready, timeout: 15) == .completed else {
            throw NavigationFailure.unreachableAction
        }
        // After leaving an entry for the list, unlocking or relaunching shows the list rather than the entry.
        if !editor.exists, !row.exists { NavigationTestSupport.selectCollection("All Entries", app: app) }
        if !editor.exists {
            guard row.waitToAppear(timeout: 10) else { throw NavigationFailure.unreachableAction }
            row.tap()
        }
        guard editor.waitToAppear(timeout: 10) else { throw NavigationFailure.unreachableAction }
        assertEventually(editor.value as? String, equals: title)
    }
    /// Turns App Lock on from the open Settings; the test build answers the Face ID request.
    @MainActor private func turnOnAppLock(app: XCUIApplication) throws {
        app.buttons["Privacy"].tap()
        let appLock = app.switches["Require Face ID"]
        try reveal(appLock, app: app)
        XCTAssertEqual(appLock.value as? String, "0")
        appLock.switches.firstMatch.tap()
        guard app.buttons["Lock My Journal"].waitToAppear(timeout: 10) else {
            throw NavigationFailure.unreachableAction
        }
        XCTAssertEqual(appLock.value as? String, "1")
    }
    @MainActor private func type(_ value: String, into name: String, app: XCUIApplication) throws {
        let field = app.secureTextFields[name]
        guard field.waitToAppear(timeout: 10) else { throw NavigationFailure.unreachableAction }
        field.tap()
        field.typeText(value)
    }
    @MainActor private func enter(_ name: String, value: String, app: XCUIApplication) throws {
        let field = app.secureTextFields[name]
        XCTAssertTrue(field.waitToAppear(timeout: 10))
        if name == "Recovery Key" {
            try reveal(field, app: app, container: app.scrollViews.firstMatch)
        }
        field.tap()
        field.typeText(value)
    }
    private enum NavigationFailure: Error { case unreachableAction }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication, container: XCUIElement? = nil) throws {
        for _ in 0..<20 {
            guard let scroll = container ?? app.collectionViews.allElementsBoundByIndex.last else {
                throw NavigationFailure.unreachableAction
            }
            var viewport = scroll.frame.intersection(app.frame)
            let keyboard = app.keyboards.firstMatch
            let tabBar = app.tabBars.firstMatch
            if keyboard.exists {
                viewport.size.height = max(
                    0,
                    min(
                        viewport.maxY,
                        app.otherElements["inputView"].firstMatch.exists
                            ? app.otherElements["inputView"].firstMatch.frame.minY : keyboard.frame.minY)
                        - viewport.minY)
            }
            if tabBar.exists { viewport.size.height = max(0, min(viewport.maxY, tabBar.frame.minY) - viewport.minY) }
            viewport = viewport.insetBy(dx: 0, dy: 12)
            guard !viewport.isEmpty else { throw NavigationFailure.unreachableAction }
            if element.exists && element.isHittable && viewport.contains(element.frame) { return }
            let shift =
                element.exists
                ? min(viewport.height / 4, max(-viewport.height / 4, viewport.midY - element.frame.midY))
                : -viewport.height / 4
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY)).press(
                forDuration: 0,
                thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY + shift)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        capture(app, "Unreachable app lock action")
        throw NavigationFailure.unreachableAction
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private struct Configuration: Codable {
        let recovery: RecoveryEnvelope
        var recoveryConfirmed = true
        let lastJournalID: UUID
        let lastEntryID: UUID
        var appLock: Bool?
    }
    private struct Fixture {
        let key: Data
        let phrase: String
        let entry: JournalItem
    }
    @MainActor private func seed(_ root: URL, appLock: Bool = false, withConflict: Bool = false) async throws
        -> Fixture
    {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Private reflection",
            document: .plain("Preserve these words."), date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.save(journal)
        try await store.save(entry)
        let saved = try await store.item(entry.id)
        if withConflict {
            var remote = try XCTUnwrap(saved)
            remote.document = .plain("Preserve the other version too.")
            let payload = try VaultCrypto.seal(
                PortableRecord.encode(remote), key: key,
                context: VaultCrypto.recordContext(id: remote.id, kind: remote.kind))
            try await store.recordConflict(
                RemoteChange(
                    cursor: 1, recordId: remote.id, revision: 1,
                    kind: remote.kind, payload: payload.base64EncodedString(), deviceId: UUID(),
                    modifiedAt: remote.modifiedAt))
        }
        try await store.close()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        var configuration = Configuration(recovery: recovery, lastJournalID: journal.id, lastEntryID: entry.id)
        if appLock { configuration.appLock = true }
        try JournalCoding.encoder().encode(configuration).write(to: root.appendingPathComponent("configuration.json"))
        return Fixture(key: key, phrase: phrase, entry: try XCTUnwrap(saved))
    }
}
