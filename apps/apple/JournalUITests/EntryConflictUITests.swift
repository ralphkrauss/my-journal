import JournalCore
import SQLite3
import UIKit
import XCTest

final class EntryConflictUITests: XCTestCase {
    @MainActor func testReviewRemoteImageCancelThenKeepBothAcrossRelaunch() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "EntryConflict-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // The other device also moved the entry to another journal.
        let fixture = try await seed(directory, remoteJournal: "Home")
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15))
        let recovery = app.secureTextFields["Recovery Key"]
        recovery.tap()
        recovery.typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 15))
        for attempt in 0..<2 {
            app.buttons["Review Changes"].firstMatch.tap()
            let versions = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
            XCTAssertTrue(versions.waitToAppear(timeout: 10))
            try selectVersion("Other Device", in: app)
            let remote = reviewScroll(app).textViews.matching(
                NSPredicate(format: "label == %@ AND value CONTAINS %@", "Entry text", "Words from the other device")
            ).firstMatch
            XCTAssertTrue(remote.waitToAppear(timeout: 10))
            XCTAssertTrue(app.staticTexts["In Home"].exists)
            capture(app, "Remote-only image in conflict review \(attempt)")
            if attempt == 0 {
                try reveal(remote, in: app)
                remote.swipeUp()
                capture(app, "Complete remote image after scrolling its preview")
            }
            try selectVersion("This Device", in: app)
            XCTAssertTrue(
                reviewScroll(app).textViews.matching(
                    NSPredicate(format: "label == %@ AND value CONTAINS %@", "Entry text", "Words from this device")
                ).firstMatch.waitToAppear(timeout: 5))
            XCTAssertTrue(app.staticTexts["In Work"].exists)
            capture(app, "Local conflict version without remote image \(attempt)")
            try selectVersion("Other Device", in: app)
            XCTAssertTrue(remote.waitToAppear(timeout: 5))
            if attempt == 0 {
                app.buttons["Cancel"].firstMatch.tap()
                XCTAssertTrue(versions.waitToDisappear(timeout: 5))
            } else {
                let keepOne = app.buttons["Keep One Version"]
                try reveal(keepOne, in: app)
                capture(app, "Complete Keep One Version action")
                keepOne.tap()
                app.buttons["Keep Version from Other Device…"].tap()
                XCTAssertTrue(app.buttons["Keep Version"].waitToAppear(timeout: 5))
                capture(app, "Cancel keeping only the remote version")
                let cancelButtons = app.buttons.matching(identifier: "Cancel")
                cancelButtons.element(boundBy: cancelButtons.count - 1).tap()
                let keepBoth = app.buttons["Keep Both"]
                try reveal(keepBoth, in: app)
                capture(app, "Reachable Keep Both conflict action")
                keepBoth.tap()
                XCTAssertTrue(versions.waitToDisappear(timeout: 10))
            }
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 15))
        XCTAssertFalse(app.buttons["Review Changes"].exists)
        capture(app, "Both conflict versions retained after relaunch")
        app.terminate()
        let store = try JournalStore(directory: directory, key: fixture.key)
        let entries = try await store.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 2)
        // Keep Both keeps each version where the review said it was.
        XCTAssertEqual(entries.first { $0.document == fixture.local.document }?.journalID, fixture.local.journalID)
        XCTAssertEqual(entries.first { $0.document == fixture.remote.document }?.journalID, fixture.remote.journalID)
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        let bytes = try await store.attachment(fixture.imageID)
        XCTAssertEqual(bytes, fixture.image)
        try await store.close()
    }

    @MainActor func testStaleResolutionRefreshesVersionsBeforeRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "StaleReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        guard app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15) else {
            throw InteractionError.unreachable
        }
        app.secureTextFields["Recovery Key"].tap()
        app.secureTextFields["Recovery Key"].typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        guard app.buttons["Review Changes"].firstMatch.waitToAppear(timeout: 15) else {
            throw InteractionError.unreachable
        }
        capture(app, "Conflict notice in the writing surface")
        app.buttons["Review Changes"].firstMatch.tap()
        let versions = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
        guard versions.waitToAppear(timeout: 10) else { throw InteractionError.unreachable }
        let updated = try await replaceRemote(fixture, directory: directory)
        let baselineStore = try JournalStore(directory: directory, key: fixture.key)
        let baselineEntries = try await baselineStore.items().filter { $0.kind == "entry" }
        let baselineHistory = try await baselineStore.history(for: fixture.local.id)
        try await baselineStore.close()
        let keepBoth = app.buttons["Keep Both"]
        try reveal(keepBoth, in: app)
        keepBoth.tap()
        let changed = app.staticTexts["These changes were updated. Review both versions again."]
        guard changed.waitToAppear(timeout: 10) else {
            capture(app, "Stale conflict recovery failed")
            throw InteractionError.unreachable
        }
        XCTAssertTrue(changed.isHittable)
        XCTAssertGreaterThanOrEqual(changed.frame.minY, app.navigationBars["Review Changes"].frame.maxY)
        XCTAssertLessThanOrEqual(changed.frame.maxY, app.frame.maxY)
        capture(app, "Updated notice automatically brought into view")
        let rejectedStore = try JournalStore(directory: directory, key: fixture.key)
        let rejectedEntries = try await rejectedStore.items().filter { $0.kind == "entry" }
        let rejectedConflicts = try await rejectedStore.conflicts()
        let rejectedHistory = try await rejectedStore.history(for: fixture.local.id)
        XCTAssertEqual(rejectedEntries, baselineEntries)
        XCTAssertEqual(rejectedConflicts, [updated])
        XCTAssertEqual(rejectedHistory, baselineHistory)
        try await rejectedStore.close()
        try reveal(changed, in: app)
        capture(app, "Stale choice requires reviewing updated versions")
        try selectVersion("Other Device", in: app)
        let preview = reviewScroll(app).textViews.matching(
            NSPredicate(format: "label == %@ AND value CONTAINS %@", "Entry text", "Newer words arrived during review")
        ).firstMatch
        guard preview.waitToAppear(timeout: 5) else { throw InteractionError.unreachable }
        try reveal(preview, in: app)
        capture(app, "Newer remote version available before retry")
        try reveal(keepBoth, in: app)
        keepBoth.tap()
        guard versions.waitToDisappear(timeout: 10) else { throw InteractionError.unreachable }
        app.terminate()
        let store = try JournalStore(directory: directory, key: fixture.key)
        let entries = try await store.items().filter { $0.kind == "entry" }
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.document == fixture.local.document })
        XCTAssertTrue(entries.contains { $0.document == updated.remote.document })
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
        let bytes = try await store.attachment(fixture.imageID)
        XCTAssertEqual(bytes, fixture.image)
        try await store.close()
    }

    @MainActor func testAlreadyResolvedConflictDoesNotReplayStaleKeepBoth() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ResolvedReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15))
        app.secureTextFields["Recovery Key"].tap()
        app.secureTextFields["Recovery Key"].typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.buttons["Review Changes"].firstMatch.waitToAppear(timeout: 15))
        app.buttons["Review Changes"].firstMatch.tap()
        let versions = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
        XCTAssertTrue(versions.waitToAppear(timeout: 10))

        let peer = try JournalStore(directory: directory, key: fixture.key)
        let conflicts = try await peer.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        try await peer.resolve(conflict, choice: .remote)
        let baselineItems = try await peer.items()
        let baselineHistory = try await peer.history(for: fixture.local.id)
        try await peer.close()

        let keepBoth = app.buttons["Keep Both"]
        try reveal(keepBoth, in: app)
        keepBoth.tap()
        XCTAssertTrue(versions.waitToDisappear(timeout: 10))
        XCTAssertFalse(keepBoth.exists)
        XCTAssertFalse(app.buttons["Keep One Version"].exists)
        let resolvedText = app.textViews.matching(
            NSPredicate(format: "label == %@ AND value CONTAINS %@", "Entry text", "Words from the other device")
        ).firstMatch
        XCTAssertTrue(resolvedText.waitToAppear(timeout: 5))
        capture(app, "Already resolved entry replaces obsolete review without replaying Keep Both")
        app.terminate()
        app.launch()
        XCTAssertTrue(NavigationTestSupport.title(app).waitToAppear(timeout: 15))
        XCTAssertFalse(app.buttons["Review Changes"].exists)
        app.terminate()

        let store = try JournalStore(directory: directory, key: fixture.key)
        let items = try await store.items()
        let history = try await store.history(for: fixture.local.id)
        let remaining = try await store.conflicts()
        let image = try await store.attachment(fixture.imageID)
        XCTAssertEqual(items, baselineItems)
        XCTAssertEqual(history, baselineHistory)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(image, fixture.image)
        XCTAssertEqual(items.first { $0.id == fixture.local.id }?.document, fixture.remote.document)
        try await store.close()
    }

    @MainActor func testFailedStaleRefreshBlocksResolutionUntilRetryLoadsCurrentVersions() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FailedReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15))
        app.secureTextFields["Recovery Key"].tap()
        app.secureTextFields["Recovery Key"].typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.buttons["Review Changes"].firstMatch.waitToAppear(timeout: 15))
        app.buttons["Review Changes"].firstMatch.tap()
        let versions = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
        XCTAssertTrue(versions.waitToAppear(timeout: 10))
        let updated = try await replaceRemote(fixture, directory: directory)
        let baseline = try JournalStore(directory: directory, key: fixture.key)
        let baselineItems = try await baseline.items()
        let baselineHistory = try await baseline.history(for: fixture.local.id)
        try await baseline.close()
        try setHistoryUnavailable(true, directory: directory)
        defer { try? setHistoryUnavailable(false, directory: directory) }

        let keepBoth = app.buttons["Keep Both"]
        try reveal(keepBoth, in: app)
        keepBoth.tap()
        let failed = app.staticTexts["Changes couldn’t be updated."]
        XCTAssertTrue(failed.waitToAppear(timeout: 10))
        assertEventually(failed.isHittable)
        XCTAssertFalse(keepBoth.exists)
        XCTAssertFalse(app.buttons["Keep One Version"].exists)
        XCTAssertFalse(versions.exists)
        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.isHittable)
        capture(app, "Failed refresh hides obsolete conflict choices and offers retry")
        retry.tap()
        XCTAssertTrue(failed.waitToAppear(timeout: 10))
        XCTAssertFalse(keepBoth.exists)
        try setHistoryUnavailable(false, directory: directory)
        retry.tap()
        XCTAssertTrue(versions.waitToAppear(timeout: 10))
        XCTAssertTrue(app.staticTexts["These changes were updated. Review both versions again."].exists)
        try selectVersion("Other Device", in: app)
        let current = reviewScroll(app).textViews.matching(
            NSPredicate(format: "label == %@ AND value CONTAINS %@", "Entry text", "Newer words arrived during review")
        ).firstMatch
        XCTAssertTrue(current.waitToAppear(timeout: 5))
        capture(app, "Retry exposes current versions without replaying the old choice")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(versions.waitToDisappear(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Review Changes"].firstMatch.waitToAppear(timeout: 15))
        app.terminate()

        let store = try JournalStore(directory: directory, key: fixture.key)
        let items = try await store.items()
        let history = try await store.history(for: fixture.local.id)
        let conflicts = try await store.conflicts()
        let image = try await store.attachment(fixture.imageID)
        XCTAssertEqual(items, baselineItems)
        XCTAssertEqual(history, baselineHistory)
        XCTAssertEqual(conflicts, [updated])
        XCTAssertEqual(image, fixture.image)
        try await store.close()
    }

    @MainActor func testNewerFormatArrivingDuringReviewPreventsStaleResolution() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ChangedFormatReview-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15))
        app.secureTextFields["Recovery Key"].tap()
        app.secureTextFields["Recovery Key"].typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.buttons["Review Changes"].firstMatch.waitToAppear(timeout: 15))
        app.buttons["Review Changes"].firstMatch.tap()
        let versions = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
        XCTAssertTrue(versions.waitToAppear(timeout: 10))

        var future = try XCTUnwrap(
            JSONSerialization.jsonObject(with: PortableRecord.encode(fixture.remote)) as? [String: Any])
        future["futureLayout"] = ["columns": 2, "caption": "Keep this unknown layout."] as [String: Any]
        let futureBytes = try JSONSerialization.data(withJSONObject: future, options: .sortedKeys)
        let sealed = try VaultCrypto.seal(
            futureBytes, key: fixture.key,
            context: VaultCrypto.recordContext(id: fixture.remote.id, kind: fixture.remote.kind))
        let peer = try JournalStore(directory: directory, key: fixture.key)
        try await peer.recordConflict(
            RemoteChange(
                cursor: 2, recordId: fixture.remote.id, revision: 2, kind: fixture.remote.kind,
                payload: sealed.base64EncodedString(), deviceId: UUID(), modifiedAt: fixture.remote.modifiedAt))
        let baselineItems = try await peer.items()
        let baselineHistory = try await peer.history(for: fixture.local.id)
        let baselineConflicts = try await peer.conflicts()
        try await peer.close()

        let keepBoth = app.buttons["Keep Both"]
        try reveal(keepBoth, in: app)
        keepBoth.tap()
        let guidance = app.staticTexts["Update My Journal to review these changes."]
        for attempt in 0..<2 {
            XCTAssertTrue(guidance.waitToAppear(timeout: 10))
            assertEventually(app.buttons["Export Archive…"].isEnabled)
            XCTAssertFalse(versions.exists)
            for action in ["Keep Both", "Keep One Version", "Keep Entry", "Keep Deletion", "Delete Permanently"] {
                XCTAssertFalse(app.buttons[action].exists)
            }
            capture(app, "Newer format replaces obsolete conflict choices \(attempt)")
            app.navigationBars["Review Changes"].buttons["Cancel"].tap()
            XCTAssertTrue(guidance.waitToDisappear(timeout: 5))
            app.terminate()
            if attempt == 0 {
                app.launch()
                XCTAssertTrue(app.buttons["Review Changes"].firstMatch.waitToAppear(timeout: 15))
                app.buttons["Review Changes"].firstMatch.tap()
            }
        }
        let store = try JournalStore(directory: directory, key: fixture.key)
        let items = try await store.items()
        let history = try await store.history(for: fixture.local.id)
        let conflicts = try await store.conflicts()
        let image = try await store.attachment(fixture.imageID)
        XCTAssertEqual(items, baselineItems)
        XCTAssertEqual(history, baselineHistory)
        XCTAssertEqual(conflicts, baselineConflicts)
        let retained = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(try PortableRecord.encode(retained.remote), futureBytes)
        XCTAssertEqual(image, fixture.image)
        try await store.close()
    }

    /// Keep Both shows both versions at once, with the entry still open. The review closed the entry before the
    /// view refreshed, which stopped the refresh: the list kept one entry marked "Changes need review" and the
    /// editor showed nothing until the app was reopened.
    @MainActor func testKeepBothUpdatesTheListAndKeepsTheEntryOpen() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeepBothView-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        unlock(app, phrase: fixture.phrase, directory: directory)
        let review = app.buttons["Review Changes"].firstMatch
        XCTAssertTrue(review.waitToAppear(timeout: 15))
        review.tap()
        let versions = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
        XCTAssertTrue(versions.waitToAppear(timeout: 10))
        let keepBoth = app.buttons["Keep Both"]
        try reveal(keepBoth, in: app)
        keepBoth.tap()
        XCTAssertTrue(versions.waitToDisappear(timeout: 10))
        XCTAssertTrue(review.waitToDisappear(timeout: 10), "The notice goes once the changes are resolved.")
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 5), "The entry stays open.")
        assertEventually(title.value as? String, equals: "A reflection")
        capture(app, "Entry after Keep Both")
        if UIDevice.current.userInterfaceIdiom != .pad {
            app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch.tap()
        }
        let rows = app.staticTexts.matching(NSPredicate(format: "label == %@", "A reflection"))
        let both = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: rows)
        XCTAssertEqual(Waiting.wait(for: both, timeout: 10), .completed, "The list shows both versions.")
        let flagged = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Changes need review"))
        XCTAssertEqual(flagged.count, 0, "Neither version waits for review.")
        capture(app, "List after Keep Both")
    }

    /// The notice about another device's changes stays in view however far the entry is scrolled. As part of the
    /// writing, it could sit under the navigation bar, out of view, when it arrived with the entry scrolled.
    @MainActor func testConflictNoticeStaysInViewInALongEntry() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "LongConflict-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory, paragraphs: 60)
        let app = XCUIApplication()
        defer { app.terminate() }
        unlock(app, phrase: fixture.phrase, directory: directory)
        let review = app.buttons["Review Changes"].firstMatch
        XCTAssertTrue(review.waitToAppear(timeout: 15))
        let body = app.textViews["Entry text"]
        XCTAssertTrue(body.waitToAppear(timeout: 5))
        for _ in 0..<4 { body.swipeUp() }
        capture(app, "Conflict notice in a scrolled entry")
        XCTAssertTrue(review.isHittable, "The notice is in view.")
        let bar = app.navigationBars.allElementsBoundByIndex.filter { $0.frame.intersects(review.frame) }
        XCTAssertTrue(bar.isEmpty, "Nothing covers the notice.")
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

    private func setHistoryUnavailable(_ unavailable: Bool, directory: URL) throws {
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(
            directory.appendingPathComponent("journal.sqlite").path, &database, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close(database) }
        guard opened == SQLITE_OK else { throw InteractionError.database }
        sqlite3_busy_timeout(database, 2000)
        // Resolution rejects a stale revision before touching history. The subsequent
        // atomic viewSnapshot read then fails without modifying any journal payload.
        let sql =
            unavailable
            ? "ALTER TABLE history RENAME TO test_unavailable_history"
            : "ALTER TABLE test_unavailable_history RENAME TO history"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw InteractionError.database }
    }

    @MainActor private func replaceRemote(_ fixture: Fixture, directory: URL) async throws -> ConflictVersion {
        var updated = fixture.remote
        updated.document.blocks[0].runs = [TextRun("Newer words arrived during review")]
        let payload = try VaultCrypto.seal(
            PortableRecord.encode(updated), key: fixture.key,
            context: VaultCrypto.recordContext(id: updated.id, kind: updated.kind))
        let store = try JournalStore(directory: directory, key: fixture.key)
        try await store.recordConflict(
            RemoteChange(
                cursor: 2, recordId: updated.id, revision: 2,
                kind: updated.kind, payload: payload.base64EncodedString(), deviceId: UUID(),
                modifiedAt: updated.modifiedAt))
        let conflicts = try await store.conflicts()
        let conflict = try XCTUnwrap(conflicts.first)
        try await store.close()
        return conflict
    }

    @MainActor private func selectVersion(_ name: String, in app: XCUIApplication) throws {
        let control = app.descendants(matching: .any).matching(identifier: "conflict-version").firstMatch
        try reveal(control, in: app, down: true)
        if name == "This Device" { capture(app, "Version picker after scrolling back from preview") }
        let segmented = app.segmentedControls["conflict-version"]
        if segmented.exists {
            segmented.buttons[name].tap()
        } else {
            control.tap()
            app.buttons[name].tap()
        }
    }

    @MainActor private func reviewScroll(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews.containing(.button, identifier: "Keep Both").firstMatch
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = false) throws {
        let scroll = reviewScroll(app)
        for _ in 0..<10 {
            let visible = scroll.frame.intersection(app.frame)
            let top = max(visible.minY, app.navigationBars["Review Changes"].frame.maxY)
            if element.isHittable, element.frame.minY >= top + 4,
                element.frame.maxY <= visible.maxY - 4
            {
                return
            }
            let towardEarlier = element.frame.isEmpty ? down : element.frame.minY < top + 4
            let preview = scroll.textViews["Entry text"].frame
            let upper = CGRect(
                x: visible.minX, y: top + 8, width: visible.width,
                height: max(0, min(preview.minY, visible.maxY) - top - 16))
            let lowerY = max(top + 8, preview.maxY)
            let lower = CGRect(
                x: visible.minX, y: lowerY, width: visible.width,
                height: max(0, visible.maxY - lowerY - 16))
            let area = upper.height > lower.height ? upper : lower
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let startY = area.minY + area.height * (towardEarlier ? 0.2 : 0.8)
            let endY = area.minY + area.height * (towardEarlier ? 0.8 : 0.2)
            let start = origin.withOffset(CGVector(dx: area.midX, dy: startY))
            let end = origin.withOffset(CGVector(dx: area.midX, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        capture(app, "Unreachable conflict control")
        XCTFail("Conflict control \(element.frame) must be fully visible in \(scroll.frame).")
        throw InteractionError.unreachable
    }
    private enum InteractionError: Error { case unreachable, database }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Fixture {
        let key: Data
        let phrase: String
        let local: JournalItem
        let remote: JournalItem
        let imageID: UUID
        let image: Data
    }
    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
        let lastEntryID: UUID
    }
    /// `paragraphs` makes this device's version that many paragraphs long.
    @MainActor private func seed(
        _ directory: URL, remoteJournal: String? = nil, paragraphs: Int = 1
    ) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let more = (1..<max(1, paragraphs)).map {
            DocumentBlock(runs: [TextRun("Paragraph \($0) of a long entry, written over several days.")])
        }
        let local = JournalItem(
            kind: "entry", journalID: journal.id, title: "A reflection",
            document: .init(blocks: [DocumentBlock(runs: [TextRun("Words from this device")])] + more))
        try await store.save(journal)
        try await store.save(local)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        }
        let imageID = try await store.addAttachment(image)
        var remote = local
        if let remoteJournal {
            let other = JournalItem(kind: "journal", title: remoteJournal)
            try await store.save(other)
            remote.journalID = other.id
        }
        remote.document = .init(blocks: [
            DocumentBlock(runs: [TextRun("Words from the other device")]),
            DocumentBlock(
                kind: "image", attachmentID: imageID, imageDescription: "Remote blue sketch", mediaType: "image/png"),
        ])
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
        return Fixture(key: key, phrase: phrase, local: local, remote: remote, imageID: imageID, image: image)
    }
}
