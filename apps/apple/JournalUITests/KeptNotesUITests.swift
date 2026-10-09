import JournalCore
import UIKit
import XCTest

/// An edit made against another device's permanent deletion is saved separately and listed in Settings ▸ Sync ▸
/// Changed on Two Devices (docs/design/1-1-conflicts-and-reconnect.md). The library is opened with the
/// conflict an earlier version left, which this version settles when it opens.
final class KeptNotesUITests: XCTestCase {
    @MainActor private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor func testAnEditAgainstAPermanentDeletionIsListedAndOpensWhereItWasSaved() async throws {
        continueAfterFailure = false
        let app = try await launch()
        defer { app.terminate() }
        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Offline reflection. Deleted permanently on one device")
        ).firstMatch
        try reveal(row, app: app)
        capture(app, "Changed on Two Devices")
        XCTAssertTrue(
            app.staticTexts["Both versions are kept. This list clears after 30 days."].waitToAppear(timeout: 5))
        row.tap()
        // Settings closes first, then the saved entry opens, read-only, in Recently Deleted.
        let title = NavigationTestSupport.title(app)
        XCTAssertTrue(title.waitToAppear(timeout: 10))
        assertEventually(title.value as? String, equals: "Offline reflection")
        XCTAssertTrue(app.staticTexts["This entry is in Recently Deleted."].waitToAppear(timeout: 5))
        capture(app, "The saved entry in Recently Deleted")

        NavigationTestSupport.openSettings(app)
        app.buttons["Sync"].firstMatch.tap()
        let clear = app.buttons["Clear List"]
        try reveal(clear, app: app)
        clear.tap()
        XCTAssertTrue(clear.waitToDisappear(timeout: 5), "Clearing needs no confirmation")
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

    /// Journal "Personal" with the entry "Offline reflection", edited here while another device deleted it
    /// permanently, as the pull delivered it.
    @MainActor private func launch() async throws -> XCUIApplication {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeptNotes-" + UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let journal = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Offline reflection", document: .plain("Original words."))
        let peer = try JournalStore(directory: root.appendingPathComponent("peer"), key: key)
        try await peer.apply([try remote(journal, revision: 1, cursor: 1, key: key)], cursor: 1)
        try await peer.apply([try remote(entry, revision: 1, cursor: 2, key: key)], cursor: 2)
        var deleted = entry
        deleted.deletedAt = Date()
        try await peer.save(deleted)
        let marker = try await peer.permanentlyDelete(try await peer.preparePermanentDeletion(entry.id))
        try await peer.close()
        let store = try JournalStore(directory: root, key: key)
        try await store.apply([try remote(journal, revision: 1, cursor: 1, key: key)], cursor: 1)
        try await store.apply([try remote(entry, revision: 1, cursor: 2, key: key)], cursor: 2)
        var edited = entry
        edited.document = .plain("Words written offline.")
        try await store.save(edited)
        try await store.apply([try remote(marker, revision: 2, cursor: 3, key: key)], cursor: 3)
        try await store.close()
        try JournalCoding.encoder().encode(Configuration(recovery: recovery, lastJournalID: journal.id))
            .write(to: root.appendingPathComponent("configuration.json"))
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.path
        app.launch()
        let field = app.secureTextFields["Recovery Key"]
        XCTAssertTrue(field.waitToAppear(timeout: 15))
        field.tap()
        field.typeText(phrase)
        app.buttons["Unlock"].tap()
        NavigationTestSupport.showJournals(app)
        return app
    }

    private func remote(_ item: JournalItem, revision: Int64, cursor: Int64, key: Data) throws -> RemoteChange {
        RemoteChange(
            cursor: cursor, recordId: item.id, revision: revision, kind: item.kind,
            payload: try VaultCrypto.seal(
                PortableRecord.encode(item), key: key, context: VaultCrypto.recordContext(id: item.id, kind: item.kind)
            ).base64EncodedString(),
            deviceId: UUID(), modifiedAt: item.modifiedAt)
    }

    private struct Configuration: Encodable {
        let recovery: RecoveryEnvelope
        let recoveryConfirmed = true
        let useBiometrics = false
        let lastJournalID: UUID
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = (isPad ? "iPad: " : "iPhone: ") + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
