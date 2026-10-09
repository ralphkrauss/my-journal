import JournalCore
import SwiftUI

/// A journal in Recently Deleted: Restore Journal acts at once, and Delete Permanently… asks first
/// (docs/design/1-1-library-simplifications.md, N).
struct DeletedJournalView: View {
    @EnvironmentObject var model: AppModel
    let journal: JournalItem
    /// Called as Delete Permanently is confirmed, so an iPhone can go back to the list at once.
    var leave: (UUID) -> Void = { _ in }
    @State private var permanentDeletionRequest: PermanentDeletionRequest?
    @State private var operation: Task<Void, Never>?
    private var canRestore: Bool {
        journal.document.isEditable && journal.preservedJSON == nil && !model.conflictedIDs.contains(journal.id)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(journal.title.isEmpty ? "Untitled Journal" : journal.title).font(.title2)
                Text(
                    model.restorableEntryCount(journal.id) == 1
                        ? "1 entry on this device" : "\(model.restorableEntryCount(journal.id)) entries on this device"
                )
                .foregroundStyle(.secondary)
                if canRestore {
                    restoreControls
                } else {
                    Text("Update My Journal to restore this journal.")
                    ArchiveExportControls()
                }
                Button("Delete Permanently…", role: .destructive) { permanentDeletionRequest = .init(id: journal.id) }
                    .disabled(model.replacingVault)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .permanentDeletionPrompt($permanentDeletionRequest, leave: leave)
        .onDisappear { operation?.cancel() }
    }
    /// The rename that restoring causes comes right before the button, because it changes the result; the longer
    /// explanation follows it, so the button is near the top at every text size.
    @ViewBuilder private var restoreControls: some View {
        if let renamed = model.restoredName(of: journal) {
            Text(
                "Another journal is named “\(JournalNames.displayName(journal.title))”, so this one will be restored as “\(renamed)”."
            )
        }
        Button("Restore Journal") {
            operation = Task { await model.restoreDeletedJournal(journal.id) }
        }.disabled(model.replacingVault)
        Text(
            "Entries deleted with this journal will return, including entries that sync later. Entries you deleted separately will stay in Recently Deleted."
        )
        let legacy = model.legacyEntryCount(journal.id)
        if legacy > 0 {
            Text(
                legacy == 1
                    ? "1 entry from an earlier version of My Journal needs to be restored individually."
                    : "\(legacy) entries from an earlier version of My Journal need to be restored individually."
            )
            .foregroundStyle(.secondary)
        }
    }
}
