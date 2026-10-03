import JournalCore
import SwiftUI

struct DeletedJournalView: View {
    @EnvironmentObject var model: AppModel
    let journal: JournalItem
    /// Called as Delete Permanently is confirmed, so an iPhone can go back to the list at once.
    var leave: (UUID) -> Void = { _ in }
    @State private var restoring = false
    @State private var reviewing: ConflictVersion?
    @State private var history = false
    @State private var permanentDeletionRequest: PermanentDeletionRequest?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(journal.title.isEmpty ? "Untitled Journal" : journal.title).font(.title2)
                Text(
                    model.restorableEntryCount(journal.id) == 1
                        ? "1 entry on this device" : "\(model.restorableEntryCount(journal.id)) entries on this device"
                )
                .foregroundStyle(.secondary)
                if journal.document.isEditable {
                    Button("Restore Journal…") { restoring = true }.disabled(model.replacingVault)
                } else {
                    Text("Update My Journal to restore this journal.")
                    ArchiveExportControls()
                }
                if let conflict = model.conflicts.first(where: { $0.id == journal.id }) {
                    Button("Review Changes") { reviewing = conflict }.disabled(model.replacingVault)
                }
                if model.journalHistoryIDs.contains(journal.id) {
                    Button("Version History…") { history = true }.disabled(model.replacingVault)
                }
                Button("Delete Permanently…", role: .destructive) { permanentDeletionRequest = .init(id: journal.id) }
                    .disabled(model.replacingVault)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .permanentDeletionPrompt($permanentDeletionRequest, leave: leave)
        .sheet(isPresented: $restoring) { JournalLifecycleView(journalID: journal.id, restoring: true) }
        .sheet(item: $reviewing) { JournalConflictView(conflict: $0) }
        .sheet(isPresented: $history) { JournalHistoryView(journalID: journal.id) }
        .onValueChange(of: model.locked) { locked in
            if locked {
                restoring = false
                reviewing = nil
                history = false
            }
        }
    }
}
