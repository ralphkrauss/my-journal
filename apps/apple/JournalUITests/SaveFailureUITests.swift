import JournalCore
import SQLite3
import XCTest

final class SaveFailureUITests: XCTestCase {
    @MainActor func testDismissedSaveErrorKeepsDraftAndOffersRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SaveFailure-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launch()
        guard app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15) else {
            throw InteractionError.unreachable
        }
        app.secureTextFields["Recovery Key"].tap()
        app.secureTextFields["Recovery Key"].typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        guard NavigationTestSupport.title(app).waitToAppear(timeout: 15) else { throw InteractionError.unreachable }
        try rejectWrites(true, root: root)
        let body = app.textViews["Entry text"]
        body.tap()
        body.typeText("X")
        let alert = app.alerts["Journal"]
        guard alert.waitToAppear(timeout: 10) else { throw InteractionError.unreachable }
        capture(app, "Local save failure retains writing")
        let dismiss = alert.buttons["OK"]
        for _ in 0..<6 {
            let label = dismiss.staticTexts.firstMatch
            let frame = label.exists ? label.frame : dismiss.frame
            if frame.maxY < alert.frame.maxY - 8 { break }
            alert.swipeUp()
        }
        capture(app, "Save error explanation and dismissal after scrolling")
        dismiss.tap()
        guard alert.waitToDisappear(timeout: 5) else { throw InteractionError.unreachable }
        assertEventually(body.value as? String, equals: "X")
        capture(app, "Persistent warning immediately after dismissing the alert")
        let beforeRetry = try JournalStore(directory: root, key: fixture.key)
        let stored = try await beforeRetry.items().first { $0.id == fixture.entry.id }
        XCTAssertEqual(stored?.document, fixture.entry.document)
        try await beforeRetry.close()
        let header = app.descendants(matching: .any).matching(identifier: "Entry header").firstMatch
        let retry = header.buttons["Try Again"]
        guard retry.waitToAppear(timeout: 5) else {
            capture(app, "Dismissed failure has no retry action")
            throw InteractionError.unreachable
        }
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        XCTAssertLessThanOrEqual(retry.frame.maxY, header.frame.maxY)
        try reveal(retry, header: header, app: app)
        capture(app, "Draft retained with a reachable retry action")
        try rejectWrites(false, root: root)
        retry.tap()
        guard retry.waitToDisappear(timeout: 10) else { throw InteractionError.unreachable }
        assertEventually(body.value as? String, equals: "X")
        capture(app, "Retry saves the retained draft")
        app.terminate()
        app.launch()
        guard NavigationTestSupport.title(app).waitToAppear(timeout: 15) else { throw InteractionError.unreachable }
        assertEventually(body.value as? String, equals: "X")
        XCTAssertFalse(header.buttons["Try Again"].exists)
        let store = try JournalStore(directory: root, key: fixture.key)
        let entries = try await store.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, fixture.entry.id)
        XCTAssertEqual(entries.first?.document.blocks.map { $0.runs.map(\.text).joined() }, ["X"])
        try await store.close()
    }

    @MainActor private func rejectWrites(_ reject: Bool, root: URL) throws {
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(
            root.appendingPathComponent("journal.sqlite").path, &database, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(database) }
        guard opened == SQLITE_OK else { throw InteractionError.database }
        sqlite3_busy_timeout(database, 2000)
        let sql =
            reject
            ? """
            CREATE TRIGGER test_save_failure BEFORE INSERT ON records
            BEGIN SELECT RAISE(ABORT, 'Synthetic save failure'); END;
            """
            : "DROP TRIGGER test_save_failure"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw InteractionError.database }
    }

    private enum InteractionError: Error { case unreachable, database }

    @MainActor private func reveal(_ element: XCUIElement, header: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<8 {
            let top = max(header.frame.minY, app.navigationBars.firstMatch.frame.maxY)
            let bottom = min(header.frame.maxY, app.frame.maxY)
            if element.isHittable, element.frame.minY >= top + 4,
                element.frame.maxY <= bottom - 4
            {
                return
            }
            let earlier = element.frame.minY < top + 4
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: header.frame.maxX - 20, dy: earlier ? top + 20 : bottom - 20))
            let end = origin.withOffset(CGVector(dx: header.frame.maxX - 20, dy: earlier ? bottom - 20 : top + 20))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        throw InteractionError.unreachable
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
        let entry: JournalItem
    }
    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
        let lastEntryID: UUID
    }
    @MainActor private func seed(_ root: URL) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Daily notes")
        try await store.save(journal)
        try await store.save(entry)
        try await store.close()
        try JournalCoding.encoder().encode(
            Configuration(recovery: recovery, lastJournalID: journal.id, lastEntryID: entry.id)
        ).write(to: root.appendingPathComponent("configuration.json"))
        return Fixture(key: key, phrase: phrase, entry: entry)
    }
}
