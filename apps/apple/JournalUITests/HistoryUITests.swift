import JournalCore
import UIKit
import XCTest

final class HistoryUITests: XCTestCase {
    @MainActor func testRestoreHistoricalEntryAndJournalSettingsThenReopen() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("History-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15))
        let recovery = app.secureTextFields["Recovery Key"]
        recovery.tap()
        recovery.typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        NavigationTestSupport.openEntry("Current reflection", journal: "All Entries", app: app)
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 15))
        assertEventually(title.value as? String, equals: "Current reflection")
        app.buttons["Entry Actions"].firstMatch.tap()
        try tap(app.buttons["Version History…"], scrolling: app.collectionViews.firstMatch)
        XCTAssertTrue(app.buttons["history-version"].waitToAppear(timeout: 10))
        capture(app, "Loaded version history")
        try reviewVersions(app, fixture: fixture)
        let preview = app.textViews.matching(
            NSPredicate(format: "label == %@ AND value CONTAINS %@", "Entry text", "Preserved earlier words")
        ).firstMatch
        XCTAssertTrue((preview.value as? String ?? "").contains("Preserved earlier words"))
        let restoreEntry = app.buttons["Restore as New Entry"]
        try scrollTo(restoreEntry, in: app.scrollViews.firstMatch)
        capture(app, "Reachable historical entry restore")
        restoreEntry.tap()
        XCTAssertTrue(app.navigationBars["Version History"].waitToDisappear(timeout: 10))
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        assertEventually(title.value as? String, equals: "Earlier reflection")
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("Earlier reflection", journal: "All Entries", app: app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        assertEventually(title.value as? String, equals: "Earlier reflection")
        capture(app, "Reopened historical copy")
        try restoreJournalSettings(app)
        app.terminate()
        app.launch()
        NavigationTestSupport.openEntry("Earlier reflection", journal: "All Entries", app: app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        assertEventually(title.value as? String, equals: "Earlier reflection")
        app.terminate()
        let reopened = try JournalStore(directory: directory, key: fixture.key)
        let items = try await reopened.items()
        let copy = try XCTUnwrap(items.first { $0.kind == "entry" && $0.id != fixture.entry.id })
        XCTAssertEqual(copy.title, fixture.historicalEntry.title)
        XCTAssertEqual(copy.document, fixture.historicalEntry.document)
        XCTAssertEqual(copy.date, fixture.historicalEntry.date)
        XCTAssertEqual(copy.journalID, fixture.journal.id)
        let imageID = try XCTUnwrap(copy.document.blocks.first { $0.kind == "image" }?.attachmentID)
        let restoredImage = try await reopened.attachment(imageID)
        XCTAssertEqual(restoredImage, fixture.image)
        XCTAssertEqual(items.filter { $0.kind == "entry" }.count, 2)
        let source = try XCTUnwrap(items.first { $0.id == fixture.entry.id })
        XCTAssertEqual(source.title, fixture.entry.title)
        let journal = try XCTUnwrap(items.first { $0.id == fixture.journal.id })
        XCTAssertEqual(journal.title, "Earlier Work")
        XCTAssertEqual(journal.defaultTemplateID, fixture.missingTemplate)
        XCTAssertEqual(journal.deletedAt, fixture.journal.deletedAt)
        let history = try await reopened.history(for: fixture.entry.id)
        XCTAssertTrue(history.contains(fixture.historicalEntry))
        let settingsHistory = try await reopened.history(for: fixture.journal.id)
        XCTAssertTrue(settingsHistory.contains { $0.title == "Current Work" })
        try await reopened.close()
    }

    @MainActor private func reviewVersions(_ app: XCUIApplication, fixture: Fixture) throws {
        let version = app.buttons["history-version"]
        XCTAssertTrue(version.waitToAppear(timeout: 5))
        version.tap()
        // Versions are listed newest first by their time, whatever order they were recorded in.
        let current = app.buttons[fixture.currentVersionTime].firstMatch
        let earlier = app.buttons[fixture.historicalVersionTime].firstMatch
        XCTAssertTrue(current.waitToAppear(timeout: 5))
        XCTAssertLessThan(current.frame.minY, earlier.frame.minY)
        capture(app, "History version menu")
        current.tap()
        XCTAssertTrue(app.staticTexts["Current reflection"].waitToAppear(timeout: 5))
        version.tap()
        let historical = app.buttons[fixture.historicalVersionTime].firstMatch
        XCTAssertTrue(historical.waitToAppear(timeout: 5))
        capture(app, "Selected current version")
        historical.tap()
        XCTAssertTrue(app.staticTexts["Earlier reflection"].waitToAppear(timeout: 5))
        let destination = app.buttons["history-destination"]
        try scrollTo(destination, in: app.scrollViews.firstMatch)
        capture(app, "Historical destination label")
        destination.tap()
        let journal = app.buttons["Current Work"]
        XCTAssertTrue(journal.waitToAppear(timeout: 5))
        capture(app, "History destination menu")
        journal.tap()
    }

    @MainActor private func restoreJournalSettings(_ app: XCUIApplication) throws {
        NavigationTestSupport.showJournals(app)
        app.staticTexts["Current Work"].firstMatch.press(forDuration: 1)
        app.buttons["Version History…"].tap()
        XCTAssertTrue(app.staticTexts["Earlier Work"].waitToAppear(timeout: 10))
        try tap(app.buttons["Restore Settings…"], scrolling: app.scrollViews.firstMatch)
        XCTAssertTrue(app.navigationBars["Restore Settings"].waitToAppear(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current Work"].exists)
        XCTAssertTrue(app.staticTexts["Earlier Work"].exists)
        capture(app, "Journal settings comparison")
        let comparisonContent = app.scrollViews["journal-settings-comparison"]
        try scrollTo(comparisonContent.staticTexts["Default Template, Unavailable Template"], in: comparisonContent)
        capture(app, "Historical default template comparison")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Restore Settings…"].waitToAppear(timeout: 5))
        try tap(app.buttons["Restore Settings…"], scrolling: app.scrollViews.firstMatch)
        XCTAssertTrue(app.navigationBars["Restore Settings"].waitToAppear(timeout: 5))
        app.buttons["Restore"].tap()
        XCTAssertTrue(app.navigationBars["Version History"].waitToDisappear(timeout: 10))
        NavigationTestSupport.showJournals(app)
        XCTAssertTrue(app.staticTexts["Earlier Work"].firstMatch.waitToAppear(timeout: 10))
        capture(app, "Restored journal settings")
    }
    @MainActor private func tap(_ element: XCUIElement, scrolling container: XCUIElement) throws {
        try scrollTo(element, in: container)
        element.tap()
    }
    private enum InteractionError: Error { case unreachable }
    @MainActor private func scrollTo(_ element: XCUIElement, in container: XCUIElement) throws {
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            container.swipeUp()
        }
        guard element.exists && element.isHittable else {
            XCTFail("The content must be reachable by scrolling.")
            throw InteractionError.unreachable
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private struct Fixture {
        let key: Data
        let phrase: String
        let journal: JournalItem
        let entry: JournalItem
        let historicalEntry: JournalItem
        let missingTemplate: UUID
        let image: Data
        let currentVersionTime: String
        let historicalVersionTime: String
    }
    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
        let lastEntryID: UUID
    }
    @MainActor private func seed(_ directory: URL) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Current Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Current reflection")
        try await store.save(journal)
        try await store.save(entry)
        var historicalEntry = entry
        historicalEntry.title = "Earlier reflection"
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let attachment = try await store.addAttachment(image)
        historicalEntry.document = JournalDocument(blocks: [
            DocumentBlock(runs: [TextRun("Preserved earlier words", bold: true)]),
            DocumentBlock(
                kind: "image", attachmentID: attachment, imageDescription: "Earlier blue sketch", mediaType: "image/png"
            ),
        ])
        historicalEntry.date = Date(timeIntervalSince1970: 1_700_000_000)
        // Older than the current version, though it is recorded after it.
        historicalEntry.modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await retainHistory(historicalEntry, store: store, key: key)
        var historicalJournal = journal
        historicalJournal.title = "Earlier Work"
        let missingTemplate = UUID()
        historicalJournal.defaultTemplateID = missingTemplate
        try await retainHistory(historicalJournal, store: store, key: key)
        let versions = try await store.history(for: entry.id)
        let storedHistoricalEntry = try XCTUnwrap(versions.first { $0.title == historicalEntry.title })
        let currentVersion = try XCTUnwrap(versions.first { $0.title == entry.title })
        func time(_ version: JournalItem) -> String {
            version.modifiedAt.formatted(date: .abbreviated, time: .standard)
        }
        try await store.close()
        let configuration = Configuration(recovery: recovery, lastJournalID: journal.id, lastEntryID: entry.id)
        try JournalCoding.encoder().encode(configuration).write(
            to: directory.appendingPathComponent("configuration.json"))
        return Fixture(
            key: key, phrase: phrase, journal: journal, entry: entry,
            historicalEntry: storedHistoricalEntry, missingTemplate: missingTemplate, image: image,
            currentVersionTime: time(currentVersion), historicalVersionTime: time(storedHistoricalEntry))
    }
    @MainActor private func retainHistory(_ historical: JournalItem, store: JournalStore, key: Data) async throws {
        let payload = try VaultCrypto.seal(
            JournalCoding.encoder().encode(historical), key: key,
            context: VaultCrypto.recordContext(id: historical.id, kind: historical.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: historical.id, revision: 1, kind: historical.kind,
                payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: Date()))
        let conflicts = try await store.conflicts()
        try await store.resolve(try XCTUnwrap(conflicts.first { $0.id == historical.id }), choice: .local)
    }
}
