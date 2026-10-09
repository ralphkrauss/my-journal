import Foundation
import JournalCore

extension AppModel {
    func restoreHistoricalVersion(_ version: JournalItem, to journalID: UUID?) async throws -> Bool {
        guard !locked, !replacingVault else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, let store else { throw JournalError.locked }
        return try await commitHistoricalCopy { try await store.restoreHistoryCopy(version, to: journalID) }
    }
    func commitHistoricalCopy(_ operation: @escaping @Sendable () async throws -> JournalItem) async throws -> Bool {
        try await commitMutation(operation) { copy in
            self.showingTrash = false
            self.showingUnavailable = false
            self.showingTemplates = copy.kind == "template"
            self.query = ""
            self.selectedID = copy.id
            self.draft = copy
            if let journalID = copy.journalID {
                self.selectedJournalID = journalID
                self.persistSelection(journalID: journalID, entryID: copy.id)
            }
        }
    }
    func restoreHistoricalJournalSettings(_ version: JournalItem, expectedJournal: JournalItem) async throws -> Bool {
        guard !locked, !replacingVault else { throw JournalError.locked }
        guard await finishPendingSave() else {
            throw JournalError.saveRequired
        }
        try Task.checkCancellation()
        guard !locked, !replacingVault, let store else { throw JournalError.locked }
        return try await commitJournalResolution {
            try await store.restoreJournalSettings(version, expectedJournal: expectedJournal)
        }
    }
}
