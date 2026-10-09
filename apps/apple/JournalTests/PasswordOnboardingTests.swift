import CryptoKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

@MainActor
final class PasswordOnboardingTests: XCTestCase {
    func testPasswordlessLibraryReopensWithItsProtectionAndMetadataEditsRemainOrdered() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let account = "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
        defer {
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        let model = AppModel(directory: root)
        if ProcessInfo.processInfo.environment["JOURNAL_CAPTURE_DESIGN"] == "1",
            let preview = await NativeTestPreview.capture(
                CreateJournalView().environmentObject(model), name: "Encryption choice", width: 520, height: 480)
        {
            add(preview)
        }
        await model.start(password: nil, encrypted: false)
        XCTAssertNil(model.error)
        XCTAssertNil(model.recoveryKey)
        XCTAssertEqual(model.configuration?.recoveryConfirmed, true)
        XCTAssertEqual(model.configuration?.recovery.formatVersion, 4)
        let journal = try XCTUnwrap(model.journals.first)
        XCTAssertEqual(journal.title, "Default")
        if ProcessInfo.processInfo.environment["JOURNAL_CAPTURE_DESIGN"] == "1" {
            if let preview = await NativeTestPreview.capture(
                TemplateChooserView(entryID: nil).environmentObject(model), name: "Template picker",
                width: 400, height: 180)
            {
                add(preview)
            }
            let actions = EditorActions()
            if let preview = await NativeTestPreview.capture(
                FormattingPopover(editor: actions, session: actions.formatting, close: {}), name: "Formatting",
                width: 250, height: 470)
            {
                add(preview)
            }
        }
        XCTAssertTrue(model.templates.isEmpty, "A new library has no templates.")
        model.changeJournal(journal.id, name: "Work")
        await model.journalEditTask?.value
        XCTAssertEqual(model.journals.first?.title, "Work")
        try await model.store?.close()
        let reopened = AppModel(directory: root)
        await reopened.load()
        XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.journals.first?.title, "Work")
        let store = try XCTUnwrap(reopened.store)
        let protection = await store.protection
        XCTAssertEqual(protection, .plaintext)
        try await store.close()
    }

    func testFailedInitialCommitDoesNotExposePartialLibraryAndCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let account = "master-" + SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
        defer {
            try? Keychain.remove(account)
            try? FileManager.default.removeItem(at: root)
        }
        let config = root.appendingPathComponent("configuration.json")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        let model = AppModel(directory: root)
        await model.start(password: "Fixture password for retry")
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.configuration)
        XCTAssertNil(model.store)
        let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(contents, ["configuration.json"])
        try FileManager.default.removeItem(at: config)
        model.error = nil
        await model.start(password: "Fixture password for retry")
        XCTAssertNil(model.error)
        XCTAssertEqual(model.journals.map(\.title), ["Default"])
        XCTAssertEqual(model.configuration?.recovery.formatVersion, 2)
        try await model.store?.close()
    }
}
