import SwiftUI

/// A deletion refused because the record has changes to review (docs/design/build-18-fixes-2026-10-06.md §1.3).
struct DeletionConflict: Identifiable, Equatable {
    /// The record with the changes, which Review Changes opens.
    let id: UUID
    /// The title of the alert, such as “Work” Can’t Be Deleted.
    let title: String
    let message: String

    /// A name for the alert's title: blank titles read as the lists show them, and a long one is shortened in the
    /// middle so the title stays short.
    static func name(kind: String, title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch kind {
            case "journal": return "Untitled Journal"
            case "template": return "Untitled Template"
            default: return "Untitled Entry"
            }
        }
        let limit = 40
        guard trimmed.count > limit else { return trimmed }
        let kept = limit - 1
        let head = trimmed.prefix((kept + 1) / 2)
        let tail = trimmed.suffix(kept / 2)
        return "\(head)…\(tail)"
    }
    static func alertTitle(kind: String, title: String) -> String {
        "“\(name(kind: kind, title: title))” Can’t Be Deleted"
    }
}

extension View {
    /// A standard alert with Review Changes and Cancel; Review Changes opens the review for the record.
    func deletionConflictAlert(_ conflict: Binding<DeletionConflict?>) -> some View {
        modifier(DeletionConflictAlert(conflict: conflict))
    }
}

private struct DeletionConflictAlert: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var conflict: DeletionConflict?
    @State private var reviewing: DeletionConflict?

    func body(content: Content) -> some View {
        content
            .alert(
                conflict?.title ?? "",
                isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }),
                presenting: conflict
            ) { shown in
                Button("Review Changes") { reviewing = shown }
                Button("Cancel", role: .cancel) {}
            } message: { shown in
                Text(shown.message)
            }
            .sheet(item: $reviewing) { reviewed in
                ConflictReview(id: reviewed.id)
            }
            .onValueChange(of: model.locked) { locked in
                if locked { conflict = nil }
            }
    }
}
