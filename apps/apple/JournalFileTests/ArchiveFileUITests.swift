import JournalCore
import XCTest

final class ArchiveFileUITests: XCTestCase {
    @MainActor func testNativeArchiveSaveAndRestorePreservesRecordsAndImage() async throws {
        continueAfterFailure = false
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveFiles-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await seed(root.appendingPathComponent("source"))
        let name = try XCTUnwrap(ProcessInfo.processInfo.environment["JOURNAL_IMPORT_NAME"])
            .replacingOccurrences(of: ".png", with: "-backup")
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchEnvironment["JOURNAL_DATA_DIR"] = root.appendingPathComponent("source").path
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitForExistence(timeout: 15))
        let key = app.secureTextFields["Recovery Key"]
        key.tap()
        key.typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        XCTAssertTrue(app.buttons["Entry Actions"].firstMatch.waitForExistence(timeout: 15))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Journal actions"].firstMatch.tap()
        app.buttons["Privacy"].tap()
        let export = app.buttons["Export Archive…"]
        reveal(export, app: app)
        capture(app, "Archive backup controls")
        export.tap()
        try saveArchive(name, app: app)
        app.terminate()
        let destination = root.appendingPathComponent("destination")
        app.launchEnvironment["JOURNAL_DATA_DIR"] = destination.path
        app.launch()
        XCTAssertTrue(app.buttons["Start a Journal"].waitForExistence(timeout: 15))
        app.buttons["Import Archive…"].tap()
        chooseArchive(name, app: app)
        XCTAssertTrue(key.waitForExistence(timeout: 15))
        key.tap()
        key.typeText(fixture.phrase + "\n")
        let restore = app.buttons["Restore Journals"]
        XCTAssertTrue(restore.waitForExistence(timeout: 15))
        reveal(restore, app: app)
        capture(app, "Saved archive ready to restore")
        restore.tap()
        XCTAssertTrue(app.staticTexts["Journals Restored"].waitForExistence(timeout: 15))
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Entry Actions"].firstMatch.waitForExistence(timeout: 15))
        capture(app, "Restored archive after relaunch")
        app.terminate()
        let configuration = try JournalCoding.decoder().decode(
            RestoredConfiguration.self, from: Data(contentsOf: destination.appendingPathComponent("configuration.json"))
        )
        let store = try JournalStore(
            directory: destination.appendingPathComponent(configuration.storageFolder), key: fixture.key)
        let recovered = try await store.items()
        XCTAssertEqual(Set(recovered.map(\.id)), Set(fixture.items.map(\.id)))
        for item in fixture.items { XCTAssertEqual(recovered.first { $0.id == item.id }, item) }
        let bytes = try await store.attachment(fixture.imageID)
        XCTAssertEqual(bytes, fixture.image)
        try await store.close()
    }

    @MainActor private func saveArchive(_ name: String, app: XCUIApplication) throws {
        let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 15))
        let local = app.cells["DOC.sidebar.item.On My iPhone"]
        if local.exists { local.tap() }
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 10))
        filename.tap()
        let current = try XCTUnwrap(filename.value as? String)
        filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        filename.typeText(name)
        capture(app, "Named encrypted archive")
        navigation.buttons["Save"].tap()
        XCTAssertTrue(navigation.waitForNonExistence(timeout: 15))
    }

    @MainActor private func chooseArchive(_ name: String, app: XCUIApplication) {
        let browse = app.tabBars.buttons["Browse"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 10))
        browse.tap()
        let local = app.cells["DOC.sidebar.item.On My iPhone"]
        if !local.exists {
            let back = app.navigationBars.buttons["Browse"].firstMatch
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        XCTAssertTrue(local.waitForExistence(timeout: 10))
        local.tap()
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        capture(app, "Saved archive in Files")
        file.tap()
    }

    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 100 { return }
            app.swipeUp()
        }
        capture(app, "Archive control not reached")
        XCTFail("Archive control must be reachable: \(element.label)")
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
        let items: [JournalItem]
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
    private struct RestoredConfiguration: Decodable { let storageFolder: String }

    @MainActor private func seed(_ directory: URL) async throws -> Fixture {
        let key = try VaultCrypto.generateKey()
        let phrase = try VaultCrypto.recoveryPhrase()
        let image = try XCTUnwrap(
            Data(base64Encoded: XCTUnwrap(ProcessInfo.processInfo.environment["JOURNAL_IMPORT_BYTES"])))
        let store = try JournalStore(directory: directory, key: key)
        let imageID = try await store.addAttachment(image)
        let journal = JournalItem(kind: "journal", title: "Archive journal")
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Archive reflection",
            document: JournalDocument(blocks: [
                DocumentBlock(runs: [TextRun("Preserved writing", bold: true)]),
                DocumentBlock(
                    kind: "image", attachmentID: imageID, imageDescription: "Blue square", mediaType: "image/png"),
            ]))
        var deleted = JournalItem(kind: "entry", journalID: journal.id, title: "Deleted reflection")
        deleted.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        for item in [journal, entry, deleted] { try await store.save(item) }
        let items = try await store.items()
        try await store.close()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        try JournalCoding.encoder().encode(
            Configuration(recovery: recovery, lastJournalID: journal.id, lastEntryID: entry.id)
        )
        .write(to: directory.appendingPathComponent("configuration.json"))
        return Fixture(key: key, phrase: phrase, items: items, imageID: imageID, image: image)
    }
}
