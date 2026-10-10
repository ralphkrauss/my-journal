import JournalCore
import XCTest

@testable import Journal

/// Export as Markdown in the app: one prepared folder for the save dialog, kept out of backups, and gone once the
/// dialog closes or the export stops (docs/design/client-only-mac-lists-markdown-2026-10-05.md §3.2).
@MainActor final class MarkdownExportControllerTests: XCTestCase {
    func testThePreparedFolderIsSavedOnceAndThenRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root.appendingPathComponent("library"))
        addTeardownBlock { @MainActor in
            if let account = model.configuration?.keyID { try? Keychain.remove(account) }
            _ = await model.finishPendingSave()
            try? await model.store?.close()
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        let store = try XCTUnwrap(model.store)
        let journal = try await store.save(JournalItem(kind: "journal", title: "Notes"))
        try await store.save(
            JournalItem(
                kind: "entry", journalID: journal.id, title: "Hello",
                document: JournalDocument(markdown: "First line\n\n- [ ] A task")))
        let staged = {
            try FileManager.default.contentsOfDirectory(atPath: model.directory.path).filter {
                ArchiveExportLeftovers.isStagedExport($0)
            }
        }
        let export = MarkdownExportController(dialogFolder: root.appendingPathComponent("dialog"))
        export.start(with: model)
        export.start(with: model)
        try await waitUntil { export.presenting || export.error != nil }

        XCTAssertNil(export.error)
        let folder = try XCTUnwrap(export.document?.staged)
        XCTAssertEqual(try staged(), [folder.lastPathComponent], "One folder for repeated presses")
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(export.document?.filename, MarkdownExport.folderName())
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Notes").path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files.first?.hasSuffix(" Hello.md") == true, "\(files)")

        export.finish(.success(root.appendingPathComponent("saved")))
        export.presenting = false
        XCTAssertNil(export.note, "Nothing was left out")
        XCTAssertEqual(try staged(), [])

        // Stopped while the dialog is open, as when the app locks: the prepared copy goes too.
        export.start(with: model)
        try await waitUntil { export.presenting || export.error != nil }
        XCTAssertEqual(try staged().count, 1)
        export.cancel()
        XCTAssertFalse(export.presenting)
        XCTAssertEqual(try staged(), [])
    }

    func testTheNoteSaysWhatWasLeftOutAndWhatToDo() {
        var summary = MarkdownExportSummary()
        XCTAssertNil(MarkdownExportController.note(summary))
        summary.imagesNotDownloaded = 2
        summary.itemsWithOtherVersions = 1
        XCTAssertEqual(
            MarkdownExportController.note(summary),
            "2 images weren’t included because they haven’t downloaded yet. Export again after syncing. 1 entry has another version that wasn’t included. Choose a version, then export again."
        )
    }

    /// Waits, without blocking the main actor, for up to ten seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(nanoseconds: 25_000_000) }
    }
}
