import Foundation
import JournalCore

extension AppModel {
    func preparePermanentDeletion(_ id: UUID) async throws -> PermanentDeletionConfirmation {
        let store = try await deletionStoreAfterSaving()
        let confirmation = try await store.preparePermanentDeletion(id)
        try Task.checkCancellation()
        guard !locked, !replacingVault, self.store === store else { throw JournalError.locked }
        return confirmation
    }
    func permanentlyDelete(_ confirmation: PermanentDeletionConfirmation, settle: Duration = .zero) async throws
        -> Bool
    {
        let store = try await deletionStoreAfterSaving()
        return try await commitDeletionMutation(settle: settle) { try await store.permanentlyDelete(confirmation) }
    }
    /// Takes the item's row out of the lists in the same update as Delete in the confirmation, so it leaves as a
    /// deleted entry's row does, rather than staying until the deletion is stored and the library read again.
    func removePermanentlyDeletedFromLists(_ confirmation: PermanentDeletionConfirmation) {
        hideInLists(confirmation.plan.recordID)
    }
    /// Permanently deletes an item that `removePermanentlyDeletedFromLists` took out of the lists. When the deletion
    /// isn't stored, the row comes back.
    func permanentlyDeleteListed(_ confirmation: PermanentDeletionConfirmation, settle: Duration = .zero)
        async throws -> Bool
    {
        defer { showInLists(confirmation.plan.recordID) }
        return try await permanentlyDelete(confirmation, settle: settle)
    }
    private func deletionStoreAfterSaving() async throws -> JournalStore {
        guard !locked, !replacingVault else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, let store else { throw JournalError.locked }
        return store
    }
    /// Reconcile durable results even if lock cancels the caller after the transaction commits.
    func commitDeletionMutation(
        settle: Duration = .zero, _ operation: @escaping @Sendable () async throws -> JournalItem
    ) async throws -> Bool {
        try await commitMutation(settle: settle, operation) { saved in
            if saved.isPermanentlyDeleted {
                self.closePermanentlyDeleted(saved)
            } else if saved.kind == "entry" {
                self.showingTrash = false
                self.showingTemplates = false
                self.showingUnavailable = false
                self.query = ""
                self.selectedJournalID = saved.journalID
                self.selectedID = saved.id
                self.draft = saved
                if let journalID = saved.journalID {
                    self.persistSelection(journalID: journalID, entryID: saved.id)
                }
            } else if saved.kind == "template" {
                // A kept template stays open in Templates, as a restored one does.
                self.showingAllEntries = false
                self.showingTrash = false
                self.showingUnavailable = false
                self.showingTemplates = true
                self.query = ""
                self.selectedID = saved.id
                self.draft = saved
            } else {
                self.selectedJournalID = saved.id
                self.selectedID = nil
                self.draft = nil
                self.showingTrash = false
                self.showingTemplates = false
                self.showingUnavailable = false
                self.query = ""
                self.persistSelection(journalID: saved.id, entryID: nil)
            }
        }
    }
    /// Closes the open item, and the journal shown, when they were permanently deleted.
    private func closePermanentlyDeleted(_ marker: JournalItem) {
        if draft?.id == marker.id || (marker.kind == "journal" && draft?.journalID == marker.id) {
            draft = nil
            selectedID = nil
        }
        if selectedJournalID == marker.id { selectedJournalID = nil }
    }
}

/// Everything Recently Deleted lists: deleted journals, templates and entries (including a deleted journal's).
struct RecentlyDeletedContents {
    var journals: [UUID] = []
    var templates: [UUID] = []
    var entries: [(id: UUID, journalID: UUID?)] = []
    var isEmpty: Bool { journals.isEmpty && templates.isEmpty && entries.isEmpty }
    var count: Int { journals.count + templates.count + entries.count }
}

/// Where Delete All is. One runs at a time: a request while one is checking, asking or deleting is ignored, so it
/// never cancels a deletion that is running.
enum DeleteAllPhase: Equatable {
    case idle, checking, confirming, deleting
}

/// Why Delete All leaves an item in Recently Deleted.
enum DeletionHold: Error, Sendable {
    case review, newerVersion, other
}

/// What Delete All checked before its confirmation: the items it will delete, journals first, each with the rows that
/// leave with it, and the items that stay. The deletion covers exactly these items.
struct DeleteAllReview: Sendable {
    struct Item: Sendable {
        let confirmation: PermanentDeletionConfirmation
        /// The item's row and, for a journal, its entries' rows.
        let rows: [UUID]
    }
    var items: [Item] = []
    /// Rows that stay, by reason; a journal that stays keeps its entries.
    var held: [(id: UUID, reason: DeletionHold)] = []
    var journals: Int { items.filter { $0.confirmation.plan.kind == "journal" }.count }
    var templates: Int { items.filter { $0.confirmation.plan.kind == "template" }.count }
    /// Entries deleted, on their own or with their journal.
    var entries: Int {
        items.reduce(0) { count, item in
            let plan = item.confirmation.plan
            return count + (plan.kind == "entry" ? 1 : plan.kind == "journal" ? plan.entryCount : 0)
        }
    }
    var rows: [UUID] { items.flatMap(\.rows) }
}

/// What Delete All did: the items it deleted, the rows of those it couldn't, and whether the view shows the result.
struct PermanentDeletionBatch: Sendable {
    var deleted: [JournalItem] = []
    var failedRows: [UUID] = []
    var refreshed = true
}

// Delete All in Recently Deleted (docs/design/ios-delete-all-and-settings-2026-10-03.md §2, the Mac §4).
extension AppModel {
    /// Recently Deleted is shown with something in it, and no search, where “All” could mean the results. Rows that
    /// are leaving don't count.
    var offersDeleteAll: Bool { destination == .deleted && query.isEmpty && !listedIDs.isEmpty }
    /// Delete All can start: the toolbar button, the Mac's menu command and the iPhone's bar button.
    var canDeleteAll: Bool { offersDeleteAll && deleteAllPhase == .idle && isReady && !locked && !replacingVault }
    /// Starts Delete All's check, unless it can't start now.
    func beginDeleteAll() -> Bool {
        guard canDeleteAll else { return false }
        deleteAllPhase = .checking
        return true
    }
    /// Delete All ends without deleting: cancelled, nothing to ask about, or the check failed. A deletion that is
    /// running ends by itself.
    func endDeleteAll() {
        guard deleteAllPhase != .deleting else { return }
        deleteAllPhase = .idle
    }
    /// Everything Recently Deleted lists without a search, apart from rows already leaving.
    var recentlyDeletedContents: RecentlyDeletedContents {
        let snapshot = lifecycle
        var contents = RecentlyDeletedContents()
        for item in items where !item.isPermanentlyDeleted && !lists.deleting.contains(item.id) {
            switch item.kind {
            case "journal" where item.deletedAt != nil: contents.journals.append(item.id)
            case "template" where item.deletedAt != nil: contents.templates.append(item.id)
            case "entry" where snapshot.location(of: item) == .recentlyDeleted:
                contents.entries.append((item.id, item.journalID))
            default: break
            }
        }
        return contents
    }
    /// Saves the open entry, then checks everything Recently Deleted lists, as Delete Permanently does before its
    /// confirmation.
    func reviewDeleteAll() async throws -> DeleteAllReview {
        let store = try await deletionStoreAfterSaving()
        let review = await Self.review(recentlyDeletedContents, in: store)
        try Task.checkCancellation()
        guard !locked, !replacingVault, self.store === store else { throw JournalError.locked }
        return review
    }
    /// Takes the rows of everything Delete All deletes out of the lists in the same update as Delete.
    func removeFromLists(_ review: DeleteAllReview) {
        objectWillChange.send()
        lists.hide(review.rows)
    }
    /// Permanently deletes what `reviewDeleteAll` checked, each item in its own transaction checked again as Delete
    /// Permanently does and queued for sync, then reads the library once, `settle` later. An item that changed
    /// meanwhile stays and its rows come back; so do the rest when locking stops the deletion part way.
    func permanentlyDeleteAll(_ review: DeleteAllReview, settle: Duration = .zero) async throws
        -> PermanentDeletionBatch
    {
        deleteAllPhase = .deleting
        defer {
            showInLists(review.rows)
            deleteAllPhase = .idle
        }
        let store = try await deletionStoreAfterSaving()
        let items = review.items
        let result = DeletionBatchResult()
        let refreshed = try await commitMutation(settle: settle, { await Self.permanentlyDelete(items, in: store) }) {
            batch in
            result.batch = batch
            for marker in batch.deleted { self.closePermanentlyDeleted(marker) }
        }
        result.batch.refreshed = refreshed
        return result.batch
    }
    private nonisolated static func review(_ contents: RecentlyDeletedContents, in store: JournalStore) async
        -> DeleteAllReview
    {
        var review = DeleteAllReview()
        var heldJournals: [UUID: DeletionHold] = [:]
        var deletedJournals = Set<UUID>()
        func check(_ id: UUID) async -> Result<PermanentDeletionConfirmation, DeletionHold>? {
            do {
                return .success(try await store.preparePermanentDeletion(id))
            } catch PermanentDeletionError.missing, PermanentDeletionError.permanentlyDeleted {
                return nil
            } catch PermanentDeletionError.conflict {
                return .failure(.review)
            } catch PermanentDeletionError.unsupported {
                return .failure(.newerVersion)
            } catch {
                return .failure(.other)
            }
        }
        for id in contents.journals {
            switch await check(id) {
            case .success(let confirmation):
                deletedJournals.insert(id)
                let entries = contents.entries.filter { $0.journalID == id }.map(\.id)
                review.items.append(.init(confirmation: confirmation, rows: [id] + entries))
            case .failure(let reason):
                heldJournals[id] = reason
                review.held.append((id, reason))
            case nil: break
            }
        }
        for id in contents.templates {
            switch await check(id) {
            case .success(let confirmation): review.items.append(.init(confirmation: confirmation, rows: [id]))
            case .failure(let reason): review.held.append((id, reason))
            case nil: break
            }
        }
        for entry in contents.entries {
            // Entries deleted with their journal aren't deleted again. A journal that stays keeps its entries, so
            // restoring it never leaves entries missing.
            if let journalID = entry.journalID {
                if deletedJournals.contains(journalID) { continue }
                if let reason = heldJournals[journalID] {
                    review.held.append((entry.id, reason))
                    continue
                }
            }
            switch await check(entry.id) {
            case .success(let confirmation): review.items.append(.init(confirmation: confirmation, rows: [entry.id]))
            case .failure(let reason): review.held.append((entry.id, reason))
            case nil: break
            }
        }
        return review
    }
    /// One item after another, each in its own transaction. Locking stops before the next one; what is already
    /// deleted stays deleted and is still reconciled.
    private nonisolated static func permanentlyDelete(_ items: [DeleteAllReview.Item], in store: JournalStore) async
        -> PermanentDeletionBatch
    {
        var batch = PermanentDeletionBatch()
        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else {
                batch.failedRows.append(contentsOf: items[index...].flatMap(\.rows))
                break
            }
            do {
                batch.deleted.append(try await store.permanentlyDelete(item.confirmation))
            } catch PermanentDeletionError.missing, PermanentDeletionError.permanentlyDeleted {
                continue
            } catch {
                batch.failedRows.append(contentsOf: item.rows)
            }
        }
        return batch
    }
}

/// Carries the batch from the stored deletion to its caller.
@MainActor private final class DeletionBatchResult {
    var batch = PermanentDeletionBatch()
}
