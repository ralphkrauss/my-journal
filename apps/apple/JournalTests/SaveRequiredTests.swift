import JournalCore
import XCTest

@testable import Journal

/// Operations that need the open entry written first stop with one typed error while its save fails
/// (docs/design/1-1-settings-messages-editor.md §2). The words are chosen where they are shown: the app's alert has a
/// Try Again button, every other place says where to find it.
@MainActor final class SaveRequiredTests: XCTestCase {
    private struct Fixture {
        let model: AppModel
        let journal: JournalItem
        let other: JournalItem
        let entry: JournalItem
        let template: JournalItem
        let root: URL
        let key: Data
    }

    /// A model with an open entry whose save fails because its store is closed.
    private func failingSaveFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        let journal = JournalItem(kind: "journal", title: "Work")
        let other = JournalItem(kind: "journal", title: "Personal")
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Current")
        var template = JournalItem(kind: "template", title: "Weekly review")
        template.deletedAt = Date()
        for item in [journal, other, entry, template] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.masterKey = key
        model.configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: try VaultCrypto.recoveryPhrase()).0,
            recoveryConfirmed: true)
        try await model.refresh()
        model.draft = try await store.item(entry.id)
        model.selectedID = entry.id
        model.selectedJournalID = journal.id
        try await store.close()
        var unsaved = try XCTUnwrap(model.draft)
        unsaved.title = "Keep this unsaved work"
        model.updateDraft(unsaved)
        return Fixture(
            model: model, journal: journal, other: other, entry: entry, template: template, root: root, key: key)
    }

    func testEveryOperationThatNeedsTheEntrySavedStopsWithTheTypedErrorAndChangesNothing() async throws {
        let fixture = try await failingSaveFixture()
        let model = fixture.model
        let (entry, journal, other) = (fixture.entry, fixture.journal, fixture.other)
        let operations: [(String, () async throws -> Void)] = [
            ("Move Entry", { try await model.moveEntry(entry.id, to: other.id) }),
            ("Create a journal from a sheet", { _ = try await model.createRecoveryJournal("Recovered", entryID: nil) }),
            ("Version History", { _ = try await model.restoreHistoricalVersion(entry, to: journal.id) }),
            ("Restore an entry", { _ = try await model.prepareEntryRestoration(entry.id, journalID: journal.id) }),
            ("Restore a journal", { _ = try await model.restoreJournal(journal.id) }),
            ("Delete Journal", { _ = try await model.prepareJournalDeletion(journal.id) }),
            ("Delete Permanently", { _ = try await model.preparePermanentDeletion(entry.id) }),
            ("Export Archive", { _ = try await model.prepareArchive() }),
            ("Export as Markdown", { _ = try await model.prepareMarkdownExport() }),
            ("Change Date", { try await model.changeEntryDate(entry.id, expectedDate: entry.date, to: Date()) }),
            ("Image Descriptions", { try await model.awaitEntryAutosave() }),
            (
                "Connect to a Server",
                {
                    try await model.recoverServer(
                        address: "https://journal.example.net", phrase: "synthetic phrase", uploadLocal: true)
                }
            ),
        ]
        for (name, operation) in operations {
            do {
                try await operation()
                XCTFail("\(name) went ahead with an entry that isn't saved.")
            } catch JournalError.saveRequired {
                XCTAssertTrue(model.saveFailure, name)
            }
        }
        let reopened = try JournalStore(directory: fixture.root, key: fixture.key)
        let stored = try await reopened.items()
        try await reopened.close()
        XCTAssertEqual(stored.first { $0.id == entry.id }?.title, "Current", "the library is as it was")
        XCTAssertEqual(stored.filter { $0.kind == "journal" }.count, 2, "no journal was created")
        XCTAssertNil(stored.first { $0.id == journal.id }?.deletedAt)
    }

    func testTheAppsAlertAsksForTryAgainOnlyWhileTheSaveStillFails() async throws {
        let fixture = try await failingSaveFixture()
        let model = fixture.model
        model.error = nil

        await model.restoreTemplate(fixture.template.id)
        XCTAssertNil(model.error, "the alert chooses its words when it is drawn")
        XCTAssertTrue(model.showsSaveRequiredAlert)
        XCTAssertEqual(
            model.alertText, "Your changes aren’t saved yet. Choose Try Again, then repeat what you were doing.")

        // The retry that runs on every edit saved the entry before the alert was read: nothing is left to say.
        model.saveFailure = false
        model.report(JournalError.saveRequired, .saving)
        XCTAssertNil(model.saveRequiredAlert, "a refusal reported after the save succeeded is not kept")
        XCTAssertNil(model.alertText)
        XCTAssertNil(model.saveRequiredAlert)
        model.saveFailure = true
        XCTAssertNil(model.alertText, "a message about a problem that is gone doesn't return")
    }

    func testEveryOtherPlaceShowsTheTextThatSaysWhereTryAgainIs() {
        let text = JournalError.saveRequired.shown(.saving)
        XCTAssertEqual(
            text,
            "Your changes aren’t saved yet. Go back to your entry, choose Try Again under Not Saved, then repeat what you were doing."
        )
        XCTAssertNotEqual(text, FailureMessage.saveRequiredWithTryAgain)
    }
}
