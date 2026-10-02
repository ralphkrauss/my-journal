import Foundation
import JournalCore

extension AppModel {
    func reloadImageDescriptionEntry(_ entryID: UUID) async throws -> JournalItem {
        guard draft?.id == entryID, !locked, !replacingVault else { throw ImageDescriptionError.unavailable }
        try await awaitEntryAutosave()
        try await refresh()
        try Task.checkCancellation()
        guard draft?.id == entryID, !locked, !replacingVault,
            let current = items.first(where: { $0.id == entryID })
        else { throw ImageDescriptionError.unavailable }
        draft = current
        guard canDescribeImages(in: entryID) else { throw ImageDescriptionError.unavailable }
        return current
    }
    func canDescribeImages(in entryID: UUID) -> Bool {
        draft?.id == entryID && canEdit && draft?.document.requiresMarkdownSource == false
            && !conflicts.contains { $0.id == entryID }
    }
    /// Whether an entry's row offers Image Descriptions. It depends on that entry, not on the open one: a Mac list's
    /// context menu leaves the selection as it is, and choosing the action opens the entry first.
    func offersImageDescriptions(for entry: JournalItem) -> Bool {
        guard !locked, !replacingVault, entry.deletedAt == nil, entry.document.isEditable,
            !entry.document.imageBlocks.isEmpty, !entry.document.requiresMarkdownSource,
            !conflicts.contains(where: { $0.id == entry.id })
        else { return false }
        return entry.kind == "template" || (entry.kind == "entry" && lifecycle.location(of: entry).isInLiveJournal)
    }
    func saveImageDescriptions(
        entryID: UUID, expectedImages: [DocumentBlock], descriptions: [UUID: String]
    ) async throws -> Bool {
        guard canDescribeImages(in: entryID) else { throw ImageDescriptionError.unavailable }
        try await awaitEntryAutosave()
        try Task.checkCancellation()
        guard canDescribeImages(in: entryID), let store else { throw ImageDescriptionError.unavailable }
        return try await commitImageDescriptionUpdate {
            try await store.updateImageDescriptions(entryID, expectedImages: expectedImages, descriptions: descriptions)
        }
    }
    func commitImageDescriptionUpdate(_ operation: @escaping @Sendable () async throws -> JournalItem) async throws
        -> Bool
    {
        try await commitMutation(operation) { saved in
            self.draft = saved
            self.selectedID = saved.id
        }
    }
}
