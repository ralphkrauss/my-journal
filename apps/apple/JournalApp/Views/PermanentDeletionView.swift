import JournalCore
import SwiftUI

extension View {
    /// Asks with a standard alert before permanently deleting the item `request` names. Once Delete is chosen, the
    /// item's row leaves its list, as a deleted entry's does, and `leave` is called with its ID, so an iPhone showing
    /// the item can go back to the list at once. A row a destructive swipe already took out of the list comes back
    /// whenever the item isn't deleted, and `returned` is called with its ID.
    func permanentDeletionPrompt(
        _ request: Binding<PermanentDeletionRequest?>, leave: @escaping (UUID) -> Void = { _ in },
        returned: @escaping (UUID) -> Void = { _ in }
    ) -> some View {
        modifier(PermanentDeletionPrompt(request: request, leave: leave, returned: returned))
    }
}

/// An item to delete permanently.
struct PermanentDeletionRequest: Equatable {
    let id: UUID
    /// Whether a destructive swipe already took the item's row out of its list, as a swipe expects
    /// (docs/design/ios-delete-all-and-settings-2026-10-03.md §1).
    var rowRemoved = false
}

/// The deletion is checked (unsaved changes, conflicts, newer formats) before the alert appears, so the alert
/// only offers what can actually happen.
private struct PermanentDeletionPrompt: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var request: PermanentDeletionRequest?
    let leave: (UUID) -> Void
    let returned: (UUID) -> Void
    @State private var confirmation: PermanentDeletionConfirmation?
    @State private var operation: Task<Void, Never>?
    /// The row a swipe took out of the list for the item being asked about.
    @State private var removedRow: UUID?
    @State private var conflict: DeletionConflict?

    func body(content: Content) -> some View {
        content
            .onValueChange(of: request) { requested in
                guard let requested else { return }
                request = nil
                operation?.cancel()
                // A second swipe before the first one's alert appeared: the first row comes back.
                if let previous = removedRow { returnRow(previous) }
                if requested.rowRemoved { removedRow = requested.id }
                operation = Task { await prepare(requested.id) }
            }
            .alert(
                confirmation.map { PermanentDeletionCopy.title($0.plan) } ?? "",
                isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                presenting: confirmation
            ) { reviewed in
                Button("Delete", role: .destructive) {
                    // The row leaves in this update, with the list's own animation, as a deleted entry's row does,
                    // unless the swipe already took it; the deletion now brings it back if it isn't stored.
                    withAnimation(reduceMotion ? nil : .default) { model.removePermanentlyDeletedFromLists(reviewed) }
                    if removedRow == reviewed.plan.recordID { removedRow = nil }
                    leave(reviewed.plan.recordID)
                    operation = Task { await commit(reviewed) }
                }
                Button("Cancel", role: .cancel) { returnRow(reviewed.plan.recordID) }
            } message: { reviewed in
                Text(PermanentDeletionCopy.message(reviewed.plan))
            }
            .deletionConflictAlert($conflict)
            .onValueChange(of: model.locked) { locked in
                if locked {
                    operation?.cancel()
                    confirmation = nil
                    if let removedRow { returnRow(removedRow) }
                }
            }
    }
    /// Lists a row a swipe took out again, as the item stays.
    private func returnRow(_ id: UUID) {
        guard removedRow == id else { return }
        removedRow = nil
        withAnimation(reduceMotion ? nil : .default) { model.showInLists(id) }
        returned(id)
    }
    private func prepare(_ id: UUID) async {
        do {
            let reviewed = try await model.preparePermanentDeletion(id)
            guard !Task.isCancelled, !model.locked else { return }
            confirmation = reviewed
        } catch {
            guard !Task.isCancelled else { return }
            returnRow(id)
            let listed = model.items.first { $0.id == id }
            report(error, kind: listed?.kind ?? "entry", title: listed?.title ?? "")
        }
    }
    private func commit(_ reviewed: PermanentDeletionConfirmation) async {
        do {
            let refreshed = try await model.permanentlyDeleteListed(
                reviewed, settle: reduceMotion ? .zero : .listRemoval)
            if !refreshed, !model.locked {
                model.error =
                    "The item was deleted, but My Journal couldn’t update the view. Reopen My Journal to continue."
            }
        } catch { report(error, kind: reviewed.plan.kind, title: reviewed.plan.title) }
    }
    private func report(_ failure: Error, kind: String, title: String) {
        guard !model.locked, !Task.isCancelled, !(failure is CancellationError) else { return }
        switch failure {
        case PermanentDeletionError.missing, PermanentDeletionError.permanentlyDeleted:
            return
        case PermanentDeletionError.changed, PermanentDeletionError.notDeleted:
            model.error = "This has changed since you chose to delete it. Check it and try again."
        case PermanentDeletionError.unsupported:
            model.error = "Update My Journal to delete this."
        case PermanentDeletionError.conflict(let recordID):
            conflict = DeletionConflict(
                id: recordID, title: DeletionConflict.alertTitle(kind: kind, title: title),
                message: "This has changes that need review before it can be deleted.")
        default:
            model.report(failure, .saving)
        }
    }
}

/// The wording of the Delete Permanently alert.
enum PermanentDeletionCopy {
    /// Deleting here doesn't reach copies kept elsewhere, so the alert says so (owner decision, 2026-09-27).
    static let retention = "You can’t undo this. Copies may remain in archives, backups, and server history."
    static func title(_ plan: PermanentDeletionPlan) -> String {
        title(kind: plan.kind, title: plan.title, entryCount: plan.entryCount)
    }
    static func message(_ plan: PermanentDeletionPlan) -> String {
        message(kind: plan.kind, entryCount: plan.entryCount)
    }
    static func title(kind: String, title: String, entryCount: Int) -> String {
        let name = name(kind: kind, title: title)
        return kind == "journal" && entryCount > 0
            ? "Delete “\(name)” and Its Entries Permanently?" : "Delete “\(name)” Permanently?"
    }
    /// The journal's entries, when it has any, then `retention`; `held` goes between them.
    static func message(kind: String, entryCount: Int, held: String? = nil) -> String {
        var sentences: [String] = []
        if kind == "journal", entryCount > 0 {
            sentences.append(
                entryCount == 1 ? "Its entry is deleted too." : "Its \(entryCount) entries are deleted too.")
        }
        if let held { sentences.append(held) }
        sentences.append(retention)
        return sentences.joined(separator: " ")
    }
    private static func name(kind: String, title: String) -> String {
        guard title.isEmpty else { return title }
        switch kind {
        case "journal": return "Untitled Journal"
        case "template": return "Untitled Template"
        default: return "Untitled Entry"
        }
    }
}

struct DeletionConsequences: View {
    var body: some View {
        Text("This deletion will sync to your other connected devices.")
        Text("Copies may remain in archives, backups, and server history.")
        Text("You can’t undo this.")
    }
}

struct DeletionSheet<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    let title: String
    let busy: Bool
    var completed = false
    @ViewBuilder var content: Content
    private var closeButton: some View {
        Button(completed ? "Done" : "Cancel", role: .cancel) { dismiss() }
            .keyboardShortcut(.cancelAction).disabled(busy)
    }
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                #if os(iOS)
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(title).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                #endif
                content
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
                    scrollContent.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { closeButton } }
                }
            #else
                VStack(spacing: 0) {
                    Text(title).font(.title2.bold()).padding(.top, 24)
                    scrollContent
                    Divider()
                    HStack {
                        closeButton
                        Spacer()
                    }.padding()
                }.frame(minWidth: 360, idealWidth: 480, minHeight: 400, idealHeight: 600)
            #endif
        }.interactiveDismissDisabled(busy)
    }
}
