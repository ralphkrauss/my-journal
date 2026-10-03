import JournalCore
import XCTest

final class UnsupportedConflictUITests: XCTestCase {
    @MainActor func testNewerFormatConflictRemainsIntactAfterCancelAndRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Unsupported-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        app.launch()
        guard app.secureTextFields["Recovery Key"].waitToAppear(timeout: 15) else {
            throw InteractionError.unavailable
        }
        let recovery = app.secureTextFields["Recovery Key"]
        recovery.tap()
        recovery.typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        for attempt in 0..<2 {
            let review = app.buttons["Review Changes"].firstMatch
            guard review.waitToAppear(timeout: 15) else { throw InteractionError.unavailable }
            review.tap()
            let explanation = app.staticTexts["Update My Journal to review these changes."]
            guard explanation.waitToAppear(timeout: 10) else { throw InteractionError.unavailable }
            assertEventually(app.buttons["Export Archive…"].isEnabled)
            for action in ["Keep Both", "Keep One Version", "Keep Entry", "Keep Deletion", "Delete Permanently"] {
                XCTAssertFalse(app.buttons[action].exists, "Unsupported content must not offer \(action).")
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Newer-format conflict preserved \(attempt)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.navigationBars["Review Changes"].buttons["Cancel"].tap()
            guard explanation.waitToDisappear(timeout: 5) else { throw InteractionError.unavailable }
            app.terminate()
            try await verify(fixture, directory: directory)
            if attempt == 0 { app.launch() }
        }
    }

    private enum InteractionError: Error { case unavailable }
    private struct Fixture {
        let key: Data
        let phrase: String
        let entry: JournalItem
        let remote: Data
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
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Compatible writing",
            document: .plain("Keep my original reflection."), date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.save(journal)
        try await store.save(entry)
        let stored = try await store.item(entry.id)
        let saved = try XCTUnwrap(stored)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: PortableRecord.encode(saved)) as? [String: Any])
        object["title"] = "Writing from a newer version"
        object["futureLayout"] = ["columns": 2, "caption": "Preserve this unknown field exactly."] as [String: Any]
        let remote = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let payload = try VaultCrypto.seal(
            remote, key: key, context: VaultCrypto.recordContext(id: saved.id, kind: saved.kind))
        try await store.recordConflict(
            RemoteChange(
                cursor: 1, recordId: saved.id, revision: 1, kind: saved.kind,
                payload: payload.base64EncodedString(), deviceId: UUID(), modifiedAt: saved.modifiedAt))
        try await store.close()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        try JournalCoding.encoder().encode(
            Configuration(recovery: recovery, lastJournalID: journal.id, lastEntryID: saved.id)
        )
        .write(to: directory.appendingPathComponent("configuration.json"))
        return Fixture(key: key, phrase: phrase, entry: saved, remote: remote)
    }
    @MainActor private func verify(_ fixture: Fixture, directory: URL) async throws {
        let store = try JournalStore(directory: directory, key: fixture.key)
        let local = try await store.item(fixture.entry.id)
        XCTAssertEqual(local, fixture.entry)
        let conflicts = try await store.conflicts()
        XCTAssertEqual(conflicts.count, 1)
        let conflict = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(try PortableRecord.encode(conflict.remote), fixture.remote)
        let history = try await store.history(for: fixture.entry.id)
        XCTAssertTrue(history.isEmpty)
        try await store.close()
    }
}
