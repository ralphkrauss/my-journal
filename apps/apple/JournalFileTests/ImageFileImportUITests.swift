import JournalCore
import XCTest

final class ImageFileImportUITests: XCTestCase {
    @MainActor func testLocalFileSelectionPreservesImageBytesAcrossRelaunch() async throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let filename = try XCTUnwrap(environment["JOURNAL_IMPORT_NAME"])
        let expected = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(environment["JOURNAL_IMPORT_BYTES"])))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FileImport-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try await seed(directory)
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_DATA_DIR"] = directory.path
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.secureTextFields["Recovery Key"].waitForExistence(timeout: 15))
        let key = app.secureTextFields["Recovery Key"]
        key.tap()
        key.typeText(fixture.phrase)
        app.buttons["Unlock"].tap()
        let title = app.textViews["Entry title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        app.textViews["Entry text"].tap()
        app.buttons["Insert Image"].firstMatch.tap()
        chooseFile(filename, app: app)
        let formatting = app.buttons["Formatting"].firstMatch
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: formatting)
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 15), .completed)
        verifyImageAction(app)
        capture(app, "Image imported from On My iPhone")
        app.terminate()
        app.launch()
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, "Image entry")
        XCTAssertTrue((app.textViews["Entry text"].value as? String ?? "").contains("Before image"))
        verifyImageAction(app)
        capture(app, "Imported image after relaunch")
        app.terminate()
        let store = try JournalStore(directory: directory, key: fixture.key)
        let items = try await store.items()
        let entry = try XCTUnwrap(items.first { $0.kind == "entry" })
        let images = entry.document.blocks.filter { $0.kind == "image" }
        XCTAssertEqual(images.count, 1)
        let block = try XCTUnwrap(images.first)
        XCTAssertEqual(block.mediaType, "image/png")
        let actual = try await store.attachment(XCTUnwrap(block.attachmentID))
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(entry.document.text.contains("Before image"))
        try await store.close()
    }

    @MainActor private func chooseFile(_ filename: String, app: XCUIApplication) {
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
        let stem = (filename as NSString).deletingPathExtension
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", stem)).firstMatch
        let found = file.waitForExistence(timeout: 15)
        capture(app, "Local image file picker contents")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Local image file picker hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(found)
        file.tap()
    }

    @MainActor private func verifyImageAction(_ app: XCUIApplication) {
        app.buttons["Entry Actions"].firstMatch.tap()
        let descriptions = app.buttons["Image Descriptions…"]
        XCTAssertTrue(descriptions.waitForExistence(timeout: 10))
        descriptions.tap()
        XCTAssertTrue(app.staticTexts["Image Descriptions"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
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
        let envelope = try VaultCrypto.makeRecovery(masterKey: key, phrase: phrase).0
        let store = try JournalStore(directory: directory, key: key)
        let journal = JournalItem(kind: "journal", title: "Test journal")
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Image entry", document: .plain("Before image"))
        try await store.save(journal)
        try await store.save(entry)
        try await store.close()
        try JournalCoding.encoder().encode(
            Configuration(recovery: envelope, lastJournalID: journal.id, lastEntryID: entry.id)
        ).write(to: directory.appendingPathComponent("configuration.json"))
        return Fixture(key: key, phrase: phrase)
    }
}
