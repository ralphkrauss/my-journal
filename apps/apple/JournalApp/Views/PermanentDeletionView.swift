import JournalCore
import SwiftUI

extension View {
    /// Asks with a standard alert before permanently deleting the item whose ID is placed in `request`. Once
    /// Delete is chosen, the item's row leaves its list, as a deleted entry's does, and `leave` is called with its
    /// ID, so an iPhone showing the item can go back to the list at once.
    func permanentDeletionPrompt(_ request: Binding<UUID?>, leave: @escaping (UUID) -> Void = { _ in }) -> some View {
        modifier(PermanentDeletionPrompt(request: request, leave: leave))
    }
}

/// The deletion is checked (unsaved changes, conflicts, newer formats) before the alert appears, so the alert
/// only offers what can actually happen.
private struct PermanentDeletionPrompt: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var request: UUID?
    let leave: (UUID) -> Void
    @State private var confirmation: PermanentDeletionConfirmation?
    @State private var operation: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onValueChange(of: request) { id in
                guard let id else { return }
                request = nil
                operation?.cancel()
                operation = Task { await prepare(id) }
            }
            .alert(
                confirmation.map(title) ?? "",
                isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                presenting: confirmation
            ) { reviewed in
                Button("Delete", role: .destructive) {
                    // The row leaves in this update, with the list's own animation, as a deleted entry's row does.
                    withAnimation(reduceMotion ? nil : .default) { model.removePermanentlyDeletedFromLists(reviewed) }
                    leave(reviewed.plan.recordID)
                    operation = Task { await commit(reviewed) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { reviewed in
                Text(message(reviewed))
            }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    operation?.cancel()
                    confirmation = nil
                }
            }
    }
    private func name(_ plan: PermanentDeletionPlan) -> String {
        guard plan.title.isEmpty else { return plan.title }
        switch plan.kind {
        case "journal": return "Untitled Journal"
        case "template": return "Untitled Template"
        default: return "Untitled Entry"
        }
    }
    private func title(_ reviewed: PermanentDeletionConfirmation) -> String {
        let plan = reviewed.plan
        return plan.kind == "journal" && plan.entryCount > 0
            ? "Delete “\(name(plan))” and Its Entries Permanently?" : "Delete “\(name(plan))” Permanently?"
    }
    /// Deleting here doesn't reach copies kept elsewhere, so the alert says so (owner decision, 2026-09-27).
    private func message(_ reviewed: PermanentDeletionConfirmation) -> String {
        let plan = reviewed.plan
        let retention = "You can’t undo this. Copies may remain in archives, backups, and server history."
        guard plan.kind == "journal", plan.entryCount > 0 else { return retention }
        return plan.entryCount == 1
            ? "Its entry is deleted too. " + retention
            : "Its \(plan.entryCount) entries are deleted too. " + retention
    }
    private func prepare(_ id: UUID) async {
        do {
            let reviewed = try await model.preparePermanentDeletion(id)
            guard !Task.isCancelled, !model.locked else { return }
            confirmation = reviewed
        } catch { report(error) }
    }
    private func commit(_ reviewed: PermanentDeletionConfirmation) async {
        do {
            let refreshed = try await model.permanentlyDeleteListed(reviewed)
            if !refreshed, !model.locked {
                model.error =
                    "The item was deleted, but My Journal couldn’t update the view. Reopen My Journal to continue."
            }
        } catch { report(error) }
    }
    private func report(_ failure: Error) {
        guard !model.locked, !Task.isCancelled, !(failure is CancellationError) else { return }
        switch failure {
        case PermanentDeletionError.missing, PermanentDeletionError.permanentlyDeleted:
            return
        case PermanentDeletionError.changed, PermanentDeletionError.notDeleted:
            model.error = "This has changed since you chose to delete it. Check it and try again."
        case PermanentDeletionError.unsupported:
            model.error = "Update My Journal to delete this."
        case PermanentDeletionError.conflict:
            model.error = "This has changes that need review before it can be deleted."
        default:
            model.error = failure.localizedDescription
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
