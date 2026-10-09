import JournalCore
import XCTest

@testable import Journal

@MainActor
final class PermanentDeletionLifecycleTests: XCTestCase {
    func testLockAfterDeletionCommitCannotFlushDeletedDraftBackToStorage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock { try await store.close() }
        let journal = JournalItem(kind: "journal", title: "Personal")
        var entry = JournalItem(kind: "entry", journalID: journal.id, title: "Deleted draft")
        entry.deletedAt = Date()
        try await store.save(journal)
        try await store.save(entry)
        let model = AppModel(directory: root)
        model.store = store
        model.items = [journal, entry]
        model.draft = entry
        model.selectedID = entry.id
        model.selectedJournalID = journal.id
        model.configuration = LocalConfiguration(
            recovery: try VaultCrypto.makeRecovery(masterKey: key, phrase: "Disposable test recovery").0)
        await model.turnOnAppLockForTesting()
        let confirmation = try await model.preparePermanentDeletion(entry.id)
        let committed = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let deleting = Task {
            try await model.commitDeletionMutation {
                let marker = try await store.permanentlyDelete(confirmation)
                committed.continuation.yield(())
                committed.continuation.finish()
                for await _ in release.stream { break }
                return marker
            }
        }
        for await _ in committed.stream { break }
        let locking = Task { await model.lock() }
        while !model.locked { await Task.yield() }
        release.continuation.yield(())
        release.continuation.finish()
        _ = try await deleting.value
        await locking.value
        XCTAssertNil(model.draft)
        XCTAssertNil(model.selectedID)
        XCTAssertTrue(model.items.isEmpty)
        let persisted = try await store.item(entry.id)
        XCTAssertEqual(persisted?.isPermanentlyDeleted, true)
        XCTAssertFalse(model.saveFailure)
    }

    func testChangedDeletionScopeIsRefusedWithoutClearingSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock { try await store.close() }
        var journal = JournalItem(kind: "journal", title: "Personal", date: Date(timeIntervalSince1970: 1_700_000_000))
        journal.deletedAt = journal.date
        let entry = JournalItem(kind: "entry", journalID: journal.id, title: "Retain this entry")
        try await store.save(journal)
        try await store.save(entry)
        let model = AppModel(directory: root)
        model.store = store
        model.items = [journal, entry]
        model.draft = entry
        model.selectedID = entry.id
        let confirmation = try await model.preparePermanentDeletion(journal.id)
        let arriving = JournalItem(kind: "entry", journalID: journal.id, title: "Newly arrived")
        try await store.save(arriving)
        do {
            _ = try await model.permanentlyDelete(confirmation)
            XCTFail("Changed membership requires a new review.")
        } catch PermanentDeletionError.changed {}
        XCTAssertEqual(model.draft, entry)
        XCTAssertEqual(model.selectedID, entry.id)
        XCTAssertFalse(model.replacingVault)
        let persisted = try await store.item(journal.id)
        XCTAssertEqual(persisted, journal)
        model.locked = true
        do {
            _ = try await model.preparePermanentDeletion(journal.id)
            XCTFail("A locked model must not publish a deletion preview.")
        } catch JournalError.locked {}
    }

    /// Delete in the confirmation takes the row out of Recently Deleted at once, so it leaves with the list's animation
    /// as a deleted entry's row does; it used to stay until the library was read again, then vanish. A deletion
    /// that is refused brings the row back, and a stored one keeps it gone.
    func testConfirmedRowLeavesAtOnceAndComesBackWhenRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock { try await store.close() }
        var journal = JournalItem(kind: "journal", title: "Old", date: Date(timeIntervalSince1970: 1_700_000_000))
        journal.deletedAt = journal.date
        let live = JournalItem(kind: "journal", title: "Personal")
        var entry = JournalItem(kind: "entry", journalID: live.id, title: "Deleted entry")
        entry.deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        for item in [journal, live, entry] { try await store.save(item) }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        try await model.refresh()
        model.showingTrash = true
        XCTAssertEqual(model.filteredDeletedJournals.map(\.id), [journal.id])
        XCTAssertEqual(model.entries.map(\.id), [entry.id])

        let refused = try await model.preparePermanentDeletion(journal.id)
        model.removePermanentlyDeletedFromLists(refused)
        XCTAssertTrue(model.filteredDeletedJournals.isEmpty)
        try await store.save(JournalItem(kind: "entry", journalID: journal.id, title: "Arrived meanwhile"))
        do {
            _ = try await model.permanentlyDeleteListed(refused)
            XCTFail("Changed membership requires a new review.")
        } catch PermanentDeletionError.changed {}
        XCTAssertEqual(model.filteredDeletedJournals.map(\.id), [journal.id])

        let confirmed = try await model.preparePermanentDeletion(entry.id)
        model.removePermanentlyDeletedFromLists(confirmed)
        XCTAssertTrue(model.entries.isEmpty)
        let refreshed = try await model.permanentlyDeleteListed(confirmed)
        XCTAssertTrue(refreshed)
        XCTAssertFalse(model.entries.contains { $0.id == entry.id })
        let stored = try await store.item(entry.id)
        XCTAssertEqual(stored?.isPermanentlyDeleted, true)
    }

    /// Delete All in Recently Deleted takes every row away at once, then deletes every journal (with its entries),
    /// template and entry there the way Delete Permanently does, so each deletion is queued for the server and other
    /// devices. Entries deleted with their journal aren't reported as failures; entries in use stay.
    func testDeleteAllDeletesEverythingInRecentlyDeletedAndQueuesEachDeletion() async throws {
        let (model, store) = try await recentlyDeletedModel()
        let live = JournalItem(kind: "journal", title: "Personal")
        var old = JournalItem(kind: "journal", title: "Old", date: Date(timeIntervalSince1970: 1_700_000_000))
        old.deletedAt = old.date
        let oldEntries = (1...2).map { JournalItem(kind: "entry", journalID: old.id, title: "Old entry \($0)") }
        var template = JournalItem(kind: "template", title: "Weekly review")
        template.deletedAt = Date()
        var deletedEntry = JournalItem(kind: "entry", journalID: live.id, title: "Deleted entry")
        deletedEntry.deletedAt = Date()
        let kept = JournalItem(kind: "entry", journalID: live.id, title: "Kept entry")
        let removed = [old, template, deletedEntry] + oldEntries
        for item in [live, kept] + removed { try await store.save(item) }
        try await model.refresh()
        model.showingTrash = true
        try await markSent(store)

        let review = try await model.reviewDeleteAll()
        XCTAssertTrue(review.held.isEmpty)
        XCTAssertEqual(review.summary, DeleteAllSummary(journals: 1, templates: 1, entries: 3))
        XCTAssertEqual(Set(review.rows), Set(removed.map(\.id)))
        model.removeFromLists(review)
        XCTAssertTrue(model.listedIDs.isEmpty, "Every row leaves in the same update as Delete.")
        let batch = try await model.permanentlyDeleteAll(review)

        XCTAssertTrue(batch.failedRows.isEmpty, "Entries deleted with their journal aren't failures.")
        XCTAssertTrue(batch.refreshed)
        XCTAssertTrue(model.listedIDs.isEmpty)
        XCTAssertTrue(model.recentlyDeletedContents.isEmpty)
        let queued = try await store.pending()
        for item in removed {
            let stored = try await store.item(item.id)
            XCTAssertEqual(stored?.isPermanentlyDeleted, true, item.title)
            XCTAssertTrue(queued.contains { $0.recordID == item.id }, "\(item.title)'s deletion is queued to sync.")
        }
        let stillThere = try await store.item(kept.id)
        XCTAssertEqual(stillThere?.isPermanentlyDeleted, false)
        XCTAssertNil(stillThere?.deletedAt)
    }

    /// Delete All checks before its alert: an item with changes from another device to review isn't offered, and a
    /// deleted journal that can't be deleted keeps its entries, so restoring it never leaves entries missing.
    func testDeleteAllLeavesOutWhatCannotBeDeletedAndKeepsAJournalWithItsEntries() async throws {
        let (model, store) = try await recentlyDeletedModel()
        let live = JournalItem(kind: "journal", title: "Personal")
        var reviewed = JournalItem(kind: "entry", journalID: live.id, title: "Changed elsewhere")
        reviewed.deletedAt = Date()
        var old = JournalItem(kind: "journal", title: "Old", date: Date(timeIntervalSince1970: 1_700_000_000))
        old.deletedAt = old.date
        let oldEntries = (1...2).map { JournalItem(kind: "entry", journalID: old.id, title: "Old entry \($0)") }
        var deletable = JournalItem(kind: "entry", journalID: live.id, title: "Deletable")
        deletable.deletedAt = Date()
        for item in [live, reviewed, old, deletable] + oldEntries { try await store.save(item) }
        try await arriveChanged(reviewed, store: store, cursor: 1)
        try await arriveChanged(oldEntries[0], store: store, cursor: 2)
        try await model.refresh()
        model.showingTrash = true

        let review = try await model.reviewDeleteAll()
        XCTAssertEqual(review.rows, [deletable.id])
        XCTAssertEqual(
            Set(review.held.map(\.id)), Set([reviewed.id, old.id] + oldEntries.map(\.id)),
            "The journal stays with both its entries.")
        XCTAssertTrue(review.held.allSatisfy { $0.reason == .review })
        model.removeFromLists(review)
        let batch = try await model.permanentlyDeleteAll(review)

        XCTAssertTrue(batch.failedRows.isEmpty)
        XCTAssertEqual(Set(model.listedIDs), Set([reviewed.id, old.id] + oldEntries.map(\.id)))
        let deleted = try await store.item(deletable.id)
        XCTAssertEqual(deleted?.isPermanentlyDeleted, true)
        for item in [reviewed, old] + oldEntries {
            let stored = try await store.item(item.id)
            XCTAssertEqual(stored?.isPermanentlyDeleted, false, item.title)
        }
    }

    /// Delete All deletes what its alert counted. An entry deleted while the alert is open (here, synced from
    /// another device) stays in Recently Deleted.
    func testDeleteAllDeletesOnlyWhatItsAlertCounted() async throws {
        let (model, store) = try await recentlyDeletedModel()
        let live = JournalItem(kind: "journal", title: "Personal")
        var counted = JournalItem(kind: "entry", journalID: live.id, title: "Counted")
        counted.deletedAt = Date()
        for item in [live, counted] { try await store.save(item) }
        try await model.refresh()
        model.showingTrash = true
        let review = try await model.reviewDeleteAll()
        var arrived = JournalItem(kind: "entry", journalID: live.id, title: "Deleted meanwhile")
        arrived.deletedAt = Date()
        try await store.save(arrived)
        try await model.refresh()

        model.removeFromLists(review)
        _ = try await model.permanentlyDeleteAll(review)
        XCTAssertEqual(model.listedIDs, [arrived.id])
        let stored = try await store.item(arrived.id)
        XCTAssertEqual(stored?.isPermanentlyDeleted, false)
    }

    /// Delete All starts only in Recently Deleted with something in it and no search, and one at a time: a second
    /// request (the Mac's ⇧⌘⌫ pressed again) while one is checking or deleting is ignored rather than cancelling the
    /// deletion that is running. An item that stays keeps Recently Deleted non-empty throughout.
    func testDeleteAllStartsOnlyInANonEmptyRecentlyDeletedAndOneAtATime() async throws {
        let (model, store) = try await recentlyDeletedModel()
        model.configuration = LocalConfiguration(recovery: .unprotected, recoveryConfirmed: true)
        model.encryption.notNow()
        let journal = JournalItem(kind: "journal", title: "Personal")
        var deleted = (1...2).map { JournalItem(kind: "entry", journalID: journal.id, title: "Deleted \($0)") }
        var changed = JournalItem(kind: "entry", journalID: journal.id, title: "Changed elsewhere")
        changed.deletedAt = Date()
        for index in deleted.indices { deleted[index].deletedAt = Date() }
        for item in [journal, changed] + deleted { try await store.save(item) }
        try await arriveChanged(changed, store: store, cursor: 1)
        try await model.refresh()
        model.selectedJournalID = journal.id
        XCTAssertFalse(model.canDeleteAll, "Not from another collection.")
        model.showingTrash = true
        model.query = "Deleted"
        XCTAssertFalse(model.canDeleteAll, "Not while searching.")
        model.query = ""

        XCTAssertTrue(model.beginDeleteAll())
        XCTAssertFalse(model.beginDeleteAll(), "Not while checking.")
        let review = try await model.reviewDeleteAll()
        XCTAssertEqual(review.held.map(\.id), [changed.id])
        model.deleteAllPhase = .confirming
        model.removeFromLists(review)
        let deletion = Task { try await model.permanentlyDeleteAll(review, settle: .milliseconds(300)) }
        for _ in 0..<100 where model.deleteAllPhase != .deleting { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.deleteAllPhase, .deleting)
        XCTAssertTrue(model.offersDeleteAll, "The item that stays is still listed.")
        XCTAssertFalse(model.beginDeleteAll(), "Not while deleting.")
        let batch = try await deletion.value

        XCTAssertTrue(batch.failedRows.isEmpty)
        for item in deleted {
            let stored = try await store.item(item.id)
            XCTAssertEqual(stored?.isPermanentlyDeleted, true, item.title)
        }
        XCTAssertEqual(model.listedIDs, [changed.id])
        XCTAssertTrue(model.canDeleteAll, "It can start again once the deletion has ended.")
    }

    /// Two entries deleted in quick succession: the library is read again only after the last row has finished
    /// moving, and neither row is listed again meanwhile, not even when a sync reads the library.
    func testQuickDeletionsStayUnlistedUntilTheLastOneIsReadBack() async throws {
        let (model, store) = try await recentlyDeletedModel()
        let journal = JournalItem(kind: "journal", title: "Personal")
        let first = JournalItem(kind: "entry", journalID: journal.id, title: "First")
        let second = JournalItem(kind: "entry", journalID: journal.id, title: "Second")
        for item in [journal, first, second] { try await store.save(item) }
        try await model.refresh()
        model.selectedJournalID = journal.id
        XCTAssertEqual(Set(model.entries.map(\.id)), [first.id, second.id])

        let firstRemoval = try XCTUnwrap(model.removeFromLists(first.id, selectingNext: false))
        let firstDeletion = Task { _ = await model.deleteListed(firstRemoval, settle: .milliseconds(300)) }
        let secondRemoval = try XCTUnwrap(model.removeFromLists(second.id, selectingNext: false))
        let secondDeletion = Task {
            await firstDeletion.value
            return await model.deleteListed(secondRemoval, settle: .milliseconds(300))
        }
        try await model.refresh()
        XCTAssertTrue(model.entries.isEmpty, "A sync reading the library meanwhile doesn't bring a row back.")
        await firstDeletion.value
        XCTAssertTrue(model.entries.isEmpty)
        _ = await secondDeletion.value

        XCTAssertTrue(model.entries.isEmpty)
        model.showingTrash = true
        XCTAssertEqual(Set(model.entries.map(\.id)), [first.id, second.id])
    }

    /// Delete All's alert names what it deletes and what stays.
    func testDeleteAllAlertWording() {
        let entries = DeleteAllCopy(DeleteAllSummary(entries: 3))
        XCTAssertEqual(entries.title, "Delete 3 Entries Permanently?")
        XCTAssertEqual(entries.message, PermanentDeletionCopy.retention)
        XCTAssertEqual(DeleteAllCopy(DeleteAllSummary(templates: 1, entries: 1)).title, "Delete 2 Items Permanently?")
        let mixed = DeleteAllCopy(
            DeleteAllSummary(journals: 2, templates: 1, entries: 11, held: [.review, .review, .review]))
        XCTAssertEqual(mixed.title, "Delete 14 Items Permanently?")
        XCTAssertEqual(
            mixed.message,
            "Includes 2 journals, 1 template, and 11 entries. 3 items have changes that need review and will stay in "
                + "Recently Deleted. You can’t undo this. Copies may remain in archives, backups, and server history.")
        let journal = DeleteAllCopy(
            DeleteAllSummary(journals: 1, entries: 3, held: [.newerVersion], single: ("journal", "Work", 3)))
        XCTAssertEqual(journal.title, "Delete “Work” and Its Entries Permanently?")
        XCTAssertEqual(
            journal.message,
            "Its 3 entries are deleted too. 1 item was saved by a newer version and stays in Recently Deleted. "
                + "Update My Journal to delete it. You can’t undo this. Copies may remain in archives, backups, and "
                + "server history.")
        XCTAssertEqual(
            DeleteAllCopy.heldSentence([.review, .newerVersion]),
            "2 items can’t be deleted yet and will stay in Recently Deleted.")
        XCTAssertEqual(DeleteAllCopy.nothingDeletable([.review]).title, "Item Can’t Be Deleted")
        XCTAssertEqual(
            DeleteAllCopy.nothingDeletable([.newerVersion, .newerVersion]).message,
            "Update My Journal to delete these items.")
    }

    private var testKey: Data?
    private func recentlyDeletedModel() async throws -> (AppModel, JournalStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let key = try VaultCrypto.generateKey()
        testKey = key
        let store = try JournalStore(directory: root, key: key)
        addTeardownBlock { try await store.close() }
        let model = AppModel(directory: root)
        model.store = store
        model.loaded = true
        return (model, store)
    }
    /// As after a sync: nothing is waiting to be sent.
    private func markSent(_ store: JournalStore) async throws {
        for pending in try await store.pending() {
            try await store.acknowledge(
                pending,
                receipt: RemoteChange(
                    cursor: 1, recordId: pending.recordID, revision: pending.baseRevision + 1, kind: pending.kind,
                    payload: pending.payload, deviceId: UUID(), modifiedAt: Date()))
        }
        let nothingQueued = try await store.pending()
        XCTAssertTrue(nothingQueued.isEmpty)
    }
    /// Another device's version of `item` arrives before this device sent its own: a conflict to review.
    private func arriveChanged(_ item: JournalItem, store: JournalStore, cursor: Int64) async throws {
        var arriving = item
        arriving.title = item.title + " (iPad)"
        let sealed = try VaultCrypto.seal(
            PortableRecord.encode(arriving), key: XCTUnwrap(testKey),
            context: VaultCrypto.recordContext(id: item.id, kind: item.kind))
        try await store.apply(
            [
                RemoteChange(
                    cursor: cursor, recordId: item.id, revision: 1, kind: item.kind,
                    payload: sealed.base64EncodedString(), deviceId: UUID(), modifiedAt: Date())
            ], cursor: cursor)
    }
}
