import JournalCore
import XCTest

@testable import Journal

/// Restore in Recently Deleted acts at once and names where the entry goes when it can't return to its own journal
/// (docs/design/1-1-library-simplifications.md, N).
@MainActor
final class EntryRestorationLifecycleTests: XCTestCase {
    func testAnEntryWhoseJournalIsInUseGoesHomeAndNothingIsAnnounced() async throws {
        let library = try await fixture()
        let model = library.model
        try await library.store.save(library.deleted(library.entry))
        try await model.refresh()
        let deleted = try XCTUnwrap(model.items.first { $0.id == library.entry.id })

        let offer = try XCTUnwrap(model.restoreOffer(for: deleted))
        XCTAssertEqual(offer.title, "Restore")
        XCTAssertTrue(offer.returnsToOwnJournal, "A full swipe is offered only when the entry goes home")
        var announced: [String] = []
        model.announce = { announced.append($0) }
        await model.showCollection(trash: true)

        let restored = await model.restore(deleted)
        XCTAssertTrue(restored)
        XCTAssertEqual(model.draft?.id, library.entry.id)
        XCTAssertEqual(model.draft?.journalID, library.work.id)
        XCTAssertNil(model.draft?.deletedAt)
        XCTAssertEqual(model.selectedJournalID, library.work.id)
        XCTAssertFalse(model.showingTrash, "The journal it returned to is shown")
        XCTAssertTrue(model.canEdit)
        XCTAssertEqual(announced, [])
    }

    func testAnEntryWhoseJournalIsDeletedGoesToTheDefaultJournalAndTheDeletedJournalStaysDeleted() async throws {
        let library = try await fixture()
        let model = library.model
        let sibling = JournalItem(kind: "entry", journalID: library.work.id, title: "Deleted with Work")
        try await library.store.save(sibling)
        try await library.store.save(library.deletedJournal(library.work))
        try await model.refresh()
        let deleted = try XCTUnwrap(model.items.first { $0.id == library.entry.id })
        XCTAssertTrue(model.isRecentlyDeleted(deleted))

        let offer = try XCTUnwrap(model.restoreOffer(for: deleted))
        XCTAssertEqual(offer.title, "Restore to “Personal”")
        XCTAssertFalse(offer.returnsToOwnJournal, "Never on a swipe")
        var announced: [String] = []
        model.announce = { announced.append($0) }
        await model.showCollection(trash: true)

        let restored = await model.restore(deleted)
        XCTAssertTrue(restored)
        XCTAssertEqual(model.draft?.journalID, library.personal.id)
        XCTAssertEqual(model.selectedJournalID, library.personal.id)
        XCTAssertEqual(announced, ["Restored to Personal."])
        let work = try await library.store.item(library.work.id)
        XCTAssertNotNil(work?.deletedAt, "The journal stays deleted")
        let kept = try await library.store.item(sibling.id)
        XCTAssertEqual(kept?.journalID, library.work.id, "Its other entries stay where they were")
        XCTAssertNil(kept?.deletedAt, "…and are still deleted with the journal, not by themselves")
        XCTAssertTrue(model.deletedJournals.contains { $0.id == library.work.id })
    }

    /// The label was drawn for a deleted journal; the journal came back before the tap. The store decides again, so
    /// the entry goes home and the person is told nothing.
    func testAJournalRestoredBetweenDrawingAndTappingSendsTheEntryHomeWithoutAnnouncing() async throws {
        let library = try await fixture()
        let model = library.model
        try await library.store.save(library.deletedJournal(library.work))
        try await model.refresh()
        let deleted = try XCTUnwrap(model.items.first { $0.id == library.entry.id })
        XCTAssertEqual(model.restoreOffer(for: deleted)?.title, "Restore to “Personal”")
        var announced: [String] = []
        model.announce = { announced.append($0) }

        // Another window or a sync restores the journal; this model hasn't read it yet.
        _ = try await library.store.restoreJournal(library.work.id)
        let restored = await model.restore(deleted)

        XCTAssertTrue(restored)
        XCTAssertEqual(model.draft?.journalID, library.work.id)
        XCTAssertEqual(model.selectedJournalID, library.work.id)
        XCTAssertEqual(announced, [])
    }

    /// The control said "Restore" because the entry's own journal was in use; another window deleted the journal before
    /// the tap. The Default Journal wasn't named, so nothing is restored and the entry is not filed there.
    func testAnOwnJournalDeletedBetweenDrawingAndTappingRefusesInsteadOfFilingTheEntryElsewhere() async throws {
        let library = try await fixture()
        let model = library.model
        try await library.store.save(library.deleted(library.entry))
        try await model.refresh()
        let deleted = try XCTUnwrap(model.items.first { $0.id == library.entry.id })
        XCTAssertEqual(model.restoreOffer(for: deleted)?.title, "Restore")
        var announced: [String] = []
        model.announce = { announced.append($0) }

        try await library.store.save(library.deletedJournal(library.work))
        let restored = await model.restore(deleted)
        XCTAssertFalse(restored)
        XCTAssertEqual(model.error, "The journal to restore into is no longer available. Nothing was restored.")
        XCTAssertEqual(announced, [])
        let stored = try await library.store.item(library.entry.id)
        XCTAssertNotNil(stored?.deletedAt, "Nothing was written")
        XCTAssertEqual(stored?.journalID, library.work.id)
    }

    func testWithNoJournalInUseRestoreIsNotOfferedAndSaysNothingWasRestored() async throws {
        let library = try await fixture()
        let model = library.model
        try await library.store.save(library.deletedJournal(library.work))
        try await library.store.save(library.deletedJournal(library.personal))
        try await model.refresh()
        let deleted = try XCTUnwrap(model.items.first { $0.id == library.entry.id })
        XCTAssertEqual(model.restoreAvailability(for: deleted), .createJournalFirst)
        XCTAssertNil(model.restoreOffer(for: deleted))

        let restored = await model.restore(deleted)
        XCTAssertFalse(restored)
        XCTAssertEqual(model.error, "The journal to restore into is no longer available. Nothing was restored.")
        let stored = try await library.store.item(library.entry.id)
        XCTAssertEqual(stored?.journalID, library.work.id, "Nothing was written")
    }

    /// An entry whose journal was deleted permanently is in Unavailable Journals with its own deletion; Restore
    /// brings it into the Default Journal, which Move Entry can't do for a deleted entry.
    func testAnEntryWithItsOwnDeletionWhoseJournalIsGoneRestoresIntoTheDefaultJournal() async throws {
        let library = try await fixture()
        let model = library.model
        let orphan = library.deleted(JournalItem(kind: "entry", journalID: UUID(), title: "Parked"))
        try await library.store.save(orphan)
        try await model.refresh()
        let listed = try XCTUnwrap(model.items.first { $0.id == orphan.id })
        XCTAssertEqual(model.lifecycle.location(of: listed), .unavailable(.missing))
        XCTAssertEqual(model.restoreOffer(for: listed)?.title, "Restore to “Personal”")
        XCTAssertFalse(model.isRecentlyDeleted(listed), "It is listed under Unavailable Journals, so never on a swipe")

        let restored = await model.restore(listed)
        XCTAssertTrue(restored)
        XCTAssertEqual(model.draft?.journalID, library.personal.id)
        XCTAssertNil(model.draft?.deletedAt)
    }

    // MARK: Support

    private struct Library {
        let model: AppModel
        let store: JournalStore
        let personal: JournalItem
        let work: JournalItem
        let entry: JournalItem

        func deleted(_ item: JournalItem) -> JournalItem {
            var copy = item
            copy.deletedAt = Date()
            return copy
        }
        func deletedJournal(_ journal: JournalItem) -> JournalItem { deleted(journal) }
    }

    /// Two journals, "Personal" the oldest and so the Default Journal, and an entry in "Work".
    private func fixture() async throws -> Library {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let personal = JournalItem(kind: "journal", title: "Personal", date: Date(timeIntervalSince1970: 1_600_000_000))
        let work = JournalItem(kind: "journal", title: "Work", date: Date(timeIntervalSince1970: 1_700_000_000))
        let entry = JournalItem(
            kind: "entry", journalID: work.id, title: "Recovered work", document: .plain("Keep this writing"),
            date: Date(timeIntervalSince1970: 1_700_000_100))
        // The entry in the first test is deleted on its own; the others delete its journal or leave it.
        for item in [personal, work, entry] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.masterKey = key
        model.configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: "Disposable recovery fixture").0,
            recoveryConfirmed: true)
        try await model.refresh()
        model.selectedJournalID = work.id
        return Library(model: model, store: store, personal: personal, work: work, entry: entry)
    }
}
