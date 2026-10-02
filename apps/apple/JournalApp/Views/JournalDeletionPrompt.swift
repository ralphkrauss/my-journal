import JournalCore
import SwiftUI

extension View {
    /// Asks with a standard alert before moving the journal whose ID is placed in `request` to Recently Deleted.
    func journalDeletionPrompt(_ request: Binding<UUID?>) -> some View {
        modifier(JournalDeletionPrompt(request: request))
    }
}

/// The deletion is checked first (unsaved writing, changes to review), so the alert only offers what can happen.
private struct JournalDeletionPrompt: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var request: UUID?
    @State private var plan: JournalDeletionPlan?
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
                plan.map { "Delete “\($0.title.isEmpty ? "Untitled Journal" : $0.title)”?" } ?? "",
                isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } }), presenting: plan
            ) { plan in
                Button("Delete", role: .destructive) {
                    // The journal leaves the sidebar at once, as the alert closes, rather than once it is stored.
                    withAnimation(reduceMotion ? nil : .default) { model.hideInLists(plan.journalID) }
                    operation = Task { await commit(plan) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(
                    plan.entryIDs.isEmpty
                        ? "This journal has no entries."
                        : plan.entryIDs.count == 1
                            ? "Its entry moves to Recently Deleted."
                            : "Its \(plan.entryIDs.count) entries move to Recently Deleted.")
            }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    operation?.cancel()
                    plan = nil
                }
            }
    }
    private func prepare(_ id: UUID) async {
        do {
            let prepared = try await model.prepareJournalDeletion(id)
            guard !Task.isCancelled, !model.locked else { return }
            plan = prepared
        } catch { report(error) }
    }
    private func commit(_ plan: JournalDeletionPlan) async {
        defer { model.showInLists(plan.journalID) }
        do {
            let refreshed = try await model.deleteJournal(plan)
            if !refreshed, !model.locked {
                model.error =
                    "The journal was deleted, but My Journal couldn’t update the view. Reopen My Journal to continue."
            }
        } catch { report(error) }
    }
    private func report(_ failure: Error) {
        guard !model.locked, !Task.isCancelled, !(failure is CancellationError) else { return }
        switch failure {
        case JournalLifecycleError.conflict, JournalLifecycleError.changed:
            model.error = "This journal has changes that need review before it can be deleted."
        case JournalLifecycleError.unsupportedJournal:
            model.error = "Update My Journal to delete this journal."
        case JournalLifecycleError.alreadyDeleted, JournalLifecycleError.missingJournal:
            return
        default:
            model.error = failure.localizedDescription
        }
    }
}
