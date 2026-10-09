import JournalCore
import SwiftUI

struct EntryRecoveryNotice: View {
    @EnvironmentObject var model: AppModel
    let entry: JournalItem
    @State private var moving: JournalItem?
    @State private var restoringParent: JournalItem?
    @State private var reviewing: ConflictVersion?
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
            .sheet(item: $moving) { captured in
                MoveEntryView(entryID: captured.id, restoring: true)
            }
            .sheet(item: $restoringParent) { captured in
                if let journalID = captured.journalID {
                    JournalLifecycleView(journalID: journalID, restoringEntryID: captured.id)
                }
            }
            .sheet(item: $reviewing) { JournalConflictView(conflict: $0) }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    moving = nil
                    restoringParent = nil
                    reviewing = nil
                }
            }
    }
    @ViewBuilder private var entryNotice: some View {
        switch model.lifecycle.location(of: entry) {
        case .journal:
            EmptyView()
        case .recentlyDeleted:
            Text(
                entry.deletedWithJournal
                    ? "This entry was deleted by an earlier version of My Journal. Choose a journal to restore this entry."
                    : "This entry is in Recently Deleted.")
            if entry.document.isEditable {
                if parent?.deletedAt == nil && !entry.deletedWithJournal {
                    recoveryButton("Restore") {
                        Task { await model.restore(entry) }
                    }
                }
                if let parent, parent.deletedAt != nil, parent.document.isEditable,
                    !model.conflicts.contains(where: { $0.id == parent.id || $0.id == entry.id })
                {
                    recoveryButton("Restore…") {
                        restoringParent = entry
                    }
                }
                recoveryButton("Restore and Move…") {
                    moving = entry
                }
            }
        case .unavailable(let reason):
            unavailable(reason)
            if reason == .missing, entry.deletedWithJournal, entry.document.isEditable {
                recoveryButton("Restore and Move…") { moving = entry }
            }
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
        case .missing:
            if model.connection != nil {
                Text("This journal hasn’t arrived on this device.")
                recoveryButton("Try Syncing Again") { Task { await model.sync(retryingRefused: true) } }
            } else {
                Text("The journal for this entry is unavailable. Your entry is still saved.")
            }
        case .conflict:
            Text("This journal has changes to review.")
            recoveryButton("Review Changes") { reviewing = model.conflicts.first { $0.id == entry.journalID } }
        }
    }
}
