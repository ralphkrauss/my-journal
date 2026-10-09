import JournalCore
import SwiftUI

/// What the open entry says when it is in Recently Deleted or Unavailable Journals, and the one Restore it offers
/// (docs/design/1-1-library-simplifications.md, N).
struct EntryRecoveryNotice: View {
    @EnvironmentObject var model: AppModel
    let entry: JournalItem
    private var parent: JournalItem? { model.items.first { $0.id == entry.journalID && $0.kind == "journal" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.kind == "template" {
                // Only templates in Recently Deleted have a notice.
                Text("This template is in Recently Deleted.")
                if entry.document.isEditable {
                    recoveryButton("Restore") { Task { await model.restore(entry) } }
                }
            } else {
                entryNotice
            }
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var entryNotice: some View {
        switch model.lifecycle.location(of: entry) {
        case .journal:
            EmptyView()
        case .recentlyDeleted:
            Text(
                entry.deletedWithJournal
                    ? "This entry was deleted by an earlier version of My Journal."
                    : "This entry is in Recently Deleted."
            )
            if parent?.deletedAt != nil { Text("The journal is in Recently Deleted.") }
            restoreActions
        case .unavailable(let reason):
            unavailable(reason)
            if reason == .missing { restoreActions }
        }
    }
    /// Restore, named by where the entry goes when that is not its own journal, or why it can't be offered.
    @ViewBuilder private var restoreActions: some View {
        switch model.restoreAvailability(for: entry) {
        case .offer(let offer):
            recoveryButton(offer.title) { Task { await model.restore(entry) } }
        case .needsUpdate:
            Text("Update My Journal to restore this entry.")
            ArchiveExportControls()
        case .createJournalFirst:
            Text("Create a journal to restore this entry.")
        case .unavailable:
            EmptyView()
        }
    }
    private func recoveryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
    }
    @ViewBuilder private func unavailable(_ reason: UnavailableJournal) -> some View {
        switch reason {
        case .unsupported:
            Text("Update My Journal to restore this entry.")
            ArchiveExportControls()
        case .missing:
            if model.connection != nil {
                Text("This journal hasn’t arrived on this device.")
                recoveryButton("Try Syncing Again") { Task { await model.sync(retryingRefused: true) } }
            } else {
                Text("The journal for this entry is unavailable. Your entry is still saved.")
            }
        }
    }
}
