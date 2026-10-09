import JournalCore
import UIKit
import XCTest

final class ArchiveUITests: XCTestCase {
    @MainActor func testArchiveWrongKeyRetryRestoreAndReopen() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Archive-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let destination = root.appendingPathComponent("destination")
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = destination.path
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 15))
        app.open(fixture.archive)
        let recovery = app.secureTextFields["Password or Recovery Key"]
        XCTAssertTrue(recovery.waitToAppear(timeout: 10))
        recovery.tap()
        recovery.typeText("wrong")
        recovery.typeText("\n")
        let failure = app.staticTexts[
            "This archive couldn’t be opened. Check the password or recovery key and try again."]
        XCTAssertTrue(failure.waitToAppear(timeout: 10))
        try reveal(failure, in: app)
        capture(app, "Archive recovery key retry")
        try reveal(recovery, in: app)
        recovery.tap()
        recovery.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        recovery.typeText(fixture.phrase + "\n")
        let live = app.staticTexts["1 entry in journals"]
        XCTAssertTrue(live.waitToAppear(timeout: 15))
        XCTAssertTrue(app.staticTexts["2 in Recently Deleted"].exists)
        let unavailable = app.staticTexts["1 in Unavailable"]
        try reveal(unavailable, in: app)
        capture(app, "Archive lifecycle counts")
        let explanation = app.staticTexts[
            "These entries are preserved. You can review them in Unavailable after importing."]
        try reveal(explanation, in: app)
        capture(app, "Archive unavailable explanation")
        let restore = app.buttons["Restore Journals"]
        try reveal(restore, in: app)
        capture(app, "Archive restore action")
        // At the largest text sizes Cancel is below Restore Journals, out of view.
        let cancel = app.buttons["Cancel"]
        try reveal(cancel, in: app)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Import Archive"].waitToDisappear(timeout: 10))
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 10))
        app.open(fixture.archive)
        XCTAssertTrue(recovery.waitToAppear(timeout: 10))
        recovery.tap()
        recovery.typeText(fixture.phrase + "\n")
        XCTAssertTrue(live.waitToAppear(timeout: 15))
        try reveal(restore, in: app)
        restore.tap()
        XCTAssertTrue(app.staticTexts["Journals Restored"].waitToAppear(timeout: 15))
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Entry Actions"].firstMatch.waitToAppear(timeout: 15))
        try reviewAdditiveImport(app, fixture: fixture)
        app.terminate()
        let config = try JournalCoding.decoder().decode(
            Configuration.self, from: Data(contentsOf: destination.appendingPathComponent("configuration.json")))
        let folders = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
        XCTAssertEqual(folders.map(\.lastPathComponent).filter { $0.hasPrefix("import-") }, [config.storageFolder])
        let store = try JournalStore(
            directory: destination.appendingPathComponent(config.storageFolder), key: fixture.key)
        let items = try await store.items()
        XCTAssertEqual(Set(items.map(\.id)), Set(fixture.items.map(\.id)))
        for expected in fixture.items {
            XCTAssertEqual(items.first { $0.id == expected.id }, expected)
        }
        let image = try await store.attachment(fixture.imageID)
        XCTAssertEqual(image, fixture.image)
        let summary = ArchiveSummary(snapshot: try await store.lifecycleSnapshot())
        XCTAssertEqual(summary.entries, 1)
        XCTAssertEqual(summary.recentlyDeleted, 2)
        XCTAssertEqual(summary.unavailable, 1)
        try await store.close()
    }

    /// An archive opened while App Lock keeps the journals locked opens once they're unlocked, even after a cancelled
    /// Face ID request. It was refused with “Unlock My Journal before opening an archive.”, or dropped.
    @MainActor func testArchiveOpenedWhileLockedOpensAfterUnlocking() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LockedArchive-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.appendingPathComponent("destination").path
        // The test build answers Face ID, here when App Lock is turned on.
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "success"
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitToAppear(timeout: 15))
        app.buttons["Start a Journal"].tap()
        NavigationTestSupport.finishStartingAJournal(app)
        NavigationTestSupport.openSettings(app)
        app.buttons["Privacy"].tap()
        let appLock = app.switches["Require Face ID"]
        XCTAssertTrue(appLock.waitToAppear(timeout: 10))
        appLock.switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["Lock My Journal"].waitToAppear(timeout: 10))
        // Opening the archive starts My Journal again, as opening it from Files does when the app isn't running. It
        // asks for Face ID at once; that request is cancelled, the next one succeeds.
        app.launchEnvironment["JOURNAL_UI_TEST_DEVICE_AUTH"] = "cancel,success"
        app.open(fixture.archive)
        let unlock = app.buttons["Unlock with Face ID"]
        XCTAssertTrue(unlock.waitToAppear(timeout: 15))
        assertEventually(unlock.isEnabled)
        XCTAssertFalse(app.staticTexts["Unlock My Journal before opening an archive."].exists)
        capture(app, "Locked with an archive waiting")
        unlock.tap()
        let recovery = app.secureTextFields["Password or Recovery Key"]
        XCTAssertTrue(recovery.waitToAppear(timeout: 10), "The archive opens once the journals are unlocked.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture(app, "Archive opened after unlocking")
        let cancel = app.buttons["Cancel"]
        try reveal(cancel, in: app)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Import Archive"].waitToDisappear(timeout: 10))
    }

    @MainActor private func reviewAdditiveImport(_ app: XCUIApplication, fixture: Fixture) throws {
        app.open(fixture.archive)
        let recovery = app.secureTextFields["Password or Recovery Key"]
        XCTAssertTrue(recovery.waitToAppear(timeout: 10))
        recovery.tap()
        recovery.typeText(fixture.phrase + "\n")
        XCTAssertTrue(app.staticTexts["1 entry in journals"].waitToAppear(timeout: 15))
        let importAction = app.buttons["Import as New Journals"]
        try reveal(importAction, in: app)
        capture(app, "Additive archive import action")
        let cancel = app.buttons["Cancel"]
        try reveal(cancel, in: app)
        capture(app, "Additive archive cancel action")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Import Archive"].waitToDisappear(timeout: 10))
        XCTAssertTrue(app.buttons["Entry Actions"].firstMatch.waitToAppear(timeout: 10))
    }

    private struct Configuration: Decodable { let storageFolder: String }
    private struct Fixture {
        let archive: URL
        let key: Data
        let phrase: String
        let items: [JournalItem]
        let imageID: UUID
        let image: Data
    }
    @MainActor private func seed(_ root: URL) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let store = try JournalStore(directory: root.appendingPathComponent("source"), key: key)
        let journal = JournalItem(kind: "journal", title: "Personal reflections and everyday observations")
        var deletedJournal = JournalItem(kind: "journal", title: "Earlier notes")
        deletedJournal.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let imageID = try await store.addAttachment(image)
        let live = JournalItem(
            kind: "entry", journalID: journal.id, title: "Preserved reflection",
            document: JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("A meaningful day", bold: true)]),
                DocumentBlock(
                    kind: "image", attachmentID: imageID, imageDescription: "Blue sketch", mediaType: "image/png"),
            ]))
        var deleted = JournalItem(kind: "entry", journalID: journal.id, title: "Independent deletion")
        deleted.deletedAt = deletedJournal.deletedAt
        let inherited = JournalItem(kind: "entry", journalID: deletedJournal.id, title: "Inherited deletion")
        let missing = JournalItem(kind: "entry", journalID: UUID(), title: "Unavailable journal")
        for item in [journal, deletedJournal, live, deleted, inherited, missing] { try await store.save(item) }
        let items = try await store.items()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let archive = root.appendingPathComponent("Recovery.journalarchive")
        try await VaultArchive.export(store: store, recovery: recovery, key: key, to: archive)
        try await store.close()
        return Fixture(archive: archive, key: key, phrase: phrase, items: items, imageID: imageID, image: image)
    }
    private enum InteractionError: Error { case unreachable }
    /// Waits until the element stops moving, for up to a second.
    @MainActor private func waitForStillness(_ element: XCUIElement) {
        var previous = element.exists ? element.frame : .null
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.12)
            let current = element.exists ? element.frame : .null
            if current == previous { return }
            previous = current
        }
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<10 {
            var viewport = scroll.frame.intersection(app.frame)
            let input = app.otherElements["inputView"].firstMatch
            if input.exists && app.keyboards.firstMatch.exists {
                viewport.size.height = max(0, min(viewport.maxY, input.frame.minY) - viewport.minY)
            }
            viewport = viewport.insetBy(dx: 0, dy: 8)
            if element.exists && element.isHittable && viewport.contains(element.frame) { return }
            let movingDown = element.exists && element.frame.minY < viewport.minY
            let distance =
                movingDown
                ? viewport.minY - element.frame.minY : element.frame.maxY - viewport.maxY
            let travel = min(viewport.height * 0.45, max(32, distance + 16))
            let start = viewport.minY + viewport.height * (movingDown ? 0.25 : 0.75)
            let end = movingDown ? start + travel : start - travel
            let origin = app.coordinate(withNormalizedOffset: .zero)
            // A slow drag held at its end doesn't coast, so the next measurement sees where the content stopped.
            origin.withOffset(CGVector(dx: viewport.midX, dy: start)).press(
                forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: end)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
            waitForStillness(element)
        }
        capture(app, "Unreachable archive content")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Archive scroll hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail(
            "Archive content must be reachable: \(element.label), frame \(element.frame), viewport \(scroll.frame).")
        throw InteractionError.unreachable
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
