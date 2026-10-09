import JournalCore
import SwiftUI

/// The review of changes to an entry or template made on two devices. Journals and permanent deletions are settled
/// by the app itself (ConflictNotes.swift); what a newer version of the app saved can only be exported.
struct ConflictReview: View {
    @EnvironmentObject var model: AppModel
    let id: UUID
    @State private var entryReviewStarted = false
    private var entryConflict: Bool {
        guard let conflict = model.conflicts.first(where: { $0.id == id }) else { return entryReviewStarted }
        return conflict.local.preservedJSON == nil && conflict.remote.preservedJSON == nil
            && conflict.local.document.isEditable && conflict.remote.document.isEditable
    }
    var body: some View {
        Group {
            if model.locked {
                Text("Unlock My Journal to review changes.").padding()
            } else if entryConflict {
                EntryConflictReview(id: id).onAppear { entryReviewStarted = true }
            } else if model.conflicts.contains(where: { $0.id == id }) {
                DeletionSheet(title: "Review Changes", busy: false) {
                    Text("Update My Journal to review these changes.")
                    ArchiveExportControls()
                }
            } else {
                DeletionSheet(title: "Review Changes", busy: false, completed: true) {
                    Text("These changes have been resolved.")
                }
            }
        }
    }
}

struct ConflictSettingsSection: View {
    @EnvironmentObject var model: AppModel
    let review: (ConflictVersion) -> Void
    var body: some View {
        if !model.locked, !model.conflicts.isEmpty {
            Section("Changes to Review") {
                ForEach(model.conflicts) { conflict in
                    let item = conflict.local
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle).fixedSize(horizontal: false, vertical: true)
                        Text(item.date, format: .dateTime).foregroundStyle(.secondary)
                        Button("Review Changes") { review(conflict) }
                            .accessibilityLabel("Review Changes for \(item.displayTitle)")
                    }
                }
            }
        }
    }
}
