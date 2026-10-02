import JournalCore
import SwiftUI

struct JournalConflictView: View {
    let conflict: ConflictVersion
    var body: some View { ConflictReview(id: conflict.id) }
}

struct ConflictReview: View {
    @EnvironmentObject var model: AppModel
    let id: UUID
    @State private var entryReviewStarted = false
    private var entryConflict: Bool {
        guard let conflict = model.conflicts.first(where: { $0.id == id }) else { return entryReviewStarted }
        return !conflict.local.isPermanentlyDeleted && !conflict.remote.isPermanentlyDeleted
            && conflict.local.preservedJSON == nil && conflict.remote.preservedJSON == nil
            && conflict.local.document.isEditable && conflict.remote.document.isEditable
            && conflict.local.kind != "journal"
    }
    var body: some View {
        Group {
            if model.locked {
                Text("Unlock My Journal to review changes.").padding()
            } else if entryConflict {
                EntryConflictReview(id: id).onAppear { entryReviewStarted = true }
            } else if let conflict = model.conflicts.first(where: { $0.id == id }) {
                if conflict.local.isPermanentlyDeleted || conflict.remote.isPermanentlyDeleted {
                    DeletionConflictView(recordID: id)
                } else if conflict.local.preservedJSON != nil || conflict.remote.preservedJSON != nil
                    || !conflict.local.document.isEditable || !conflict.remote.document.isEditable
                {
                    DeletionSheet(title: "Review Changes", busy: false) {
                        Text("Update My Journal to review these changes.")
                        ArchiveExportControls()
                    }
                } else if conflict.local.kind == "journal" {
                    JournalMetadataConflictReview(conflict: conflict)
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
                    let item = conflict.local.isPermanentlyDeleted ? conflict.remote : conflict.local
                    let title = item.isPermanentlyDeleted ? DeletionConflictView.deletedTitle(item) : item.displayTitle
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).fixedSize(horizontal: false, vertical: true)
                        Text(item.permanentlyDeletedAt ?? item.date, format: .dateTime).foregroundStyle(.secondary)
                        Button("Review Changes") { review(conflict) }
                            .accessibilityLabel("Review Changes for \(title)")
                    }
                }
            }
        }
    }
}
