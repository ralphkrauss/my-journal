import JournalCore
import UIKit
import XCTest

/// An entry changed on two devices keeps both versions (docs/design/1-1-conflicts-and-reconnect.md, 4.2 and 4.3). The
/// library is opened with the other device's version left for review by an earlier version, which this version settles
/// when it opens; the open entry says so, and Settings ▸ Sync lists it.
final class KeptBothUITests: XCTestCase {
    private let noticeText =
        "This entry was also changed on another device. The other version is saved as a separate entry."

    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor func testTheNoticeOffersTheOtherVersionAndSettingsListsItAcrossRelaunch() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeptBoth-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        unlock(app, phrase: fixture.phrase, directory: directory)
        XCTAssertTrue(app.staticTexts[noticeText].waitToAppear(timeout: 20))
        XCTAssertTrue(app.buttons["Dismiss"].exists)
        capture(app, "Notice above the open entry")

        // Show Other Version opens the entry the other version was saved as, and marks the notice seen.
        let show = app.buttons["Show Other Version"]
        show.tap()
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        assertEventually(title.value as? String, equals: "A reflection (other version)")
        XCTAssertFalse(app.staticTexts[noticeText].exists)
        capture(app, "The other version, saved as a separate entry")

        // It is still listed in Settings until it expires, and the row opens it.
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "A reflection (other version). Changed on two devices")
        ).firstMatch
        try reveal(row, app: app)
        XCTAssertTrue(
            app.staticTexts["Both versions are kept. This list clears after 30 days."].waitToAppear(timeout: 5))
        capture(app, "Changed on Two Devices with an entry")
        let clear = app.buttons["Clear List"]
        try reveal(clear, app: app)
        clear.tap()
        XCTAssertTrue(clear.waitToDisappear(timeout: 5), "Clearing needs no confirmation")
        app.terminate()

        let store = try JournalStore(directory: directory, key: fixture.key)
        let entries = try await store.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first { $0.id == fixture.local.id }?.document, fixture.local.document)
        XCTAssertEqual(entries.first { $0.id != fixture.local.id }?.document, fixture.remote.document)
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        try await store.close()
    }

    @MainActor func testDismissHidesTheNoticeAndKeepsBothVersions() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeptBoth-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        unlock(app, phrase: fixture.phrase, directory: directory)
        XCTAssertTrue(app.staticTexts[noticeText].waitToAppear(timeout: 20))
        app.buttons["Dismiss"].tap()
        XCTAssertTrue(app.staticTexts[noticeText].waitToDisappear(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 15))
        XCTAssertFalse(app.staticTexts[noticeText].exists, "A dismissed notice stays dismissed")
    }

    // MARK: Support

    private enum InteractionError: Error { case unreachable }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            app.swipeUp()
        }
        guard element.waitToAppear(timeout: 5) else { throw InteractionError.unreachable }
    }

    @MainActor private func unlock(_ app: XCUIApplication, phrase: String, directory: URL) {
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        let recovery = app.secureTextFields["Recovery Key"]
        XCTAssertTrue(recovery.waitToAppear(timeout: 15))
        recovery.tap()
        recovery.typeText(phrase)
        app.buttons["Unlock"].tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = (isPad ? "iPad: " : "iPhone: ") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Fixture {
        let key: Data
        let phrase: String
        let local: JournalItem
        let remote: JournalItem
    }
    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
        let lastEntryID: UUID
    }

    /// An entry edited here whose other version, written on another device, an earlier version left for review.
    @MainActor private func seed(_ directory: URL) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let local = JournalItem(
            kind: "entry", journalID: journal.id, title: "A reflection",
            document: .init(blocks: [DocumentBlock(runs: [TextRun("Words from this device")])]))
        try await store.save(journal)
        try await store.save(local)
        var remote = local
        remote.document = .init(blocks: [DocumentBlock(runs: [TextRun("Words from the other device")])])
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(remote), key: key,
            context: VaultCrypto.recordContext(id: remote.id, kind: remote.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: remote.id, revision: 1, kind: remote.kind,
                payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
        try await store.close()
        try JournalCoding.encoder().encode(
            Configuration(recovery: recovery, lastJournalID: journal.id, lastEntryID: local.id)
        )
        .write(to: directory.appendingPathComponent("configuration.json"))
        return Fixture(key: key, phrase: phrase, local: local, remote: remote)
    }
}
