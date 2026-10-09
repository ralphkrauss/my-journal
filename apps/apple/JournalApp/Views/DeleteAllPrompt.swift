import JournalCore
import SwiftUI

extension View {
    /// Delete All in Recently Deleted: checks everything there, asks with a standard alert that says what will be
    /// deleted and what stays, then deletes it (docs/design/ios-delete-all-and-settings-2026-10-03.md §2, §4).
    /// Setting `requested` starts the check when Delete All can start (`AppModel.canDeleteAll`) and is reset at once;
    /// `AppModel.deleteAllPhase` follows it from there.
    func deleteAllPrompt(_ requested: Binding<Bool>) -> some View {
        modifier(DeleteAllPrompt(requested: requested))
    }
}

private struct DeleteAllPrompt: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var requested: Bool
    @State private var review: DeleteAllReview?
    @State private var notice: DeletionNotice?
    @State private var operation: Task<Void, Never>?
    /// This window started the Delete All under way, so it ends it if it closes first.
    @State private var started = false

    func body(content: Content) -> some View {
        content
            .onValueChange(of: requested) { requested in
                guard requested else { return }
                self.requested = false
                guard model.beginDeleteAll() else { return }
                started = true
                operation = Task { await check() }
            }
            .alert(
                review.map { DeleteAllCopy($0.summary).title } ?? "",
                isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }),
                presenting: review
            ) { reviewed in
                Button("Delete", role: .destructive) {
                    model.deleteAllPhase = .deleting
                    withAnimation(reduceMotion ? nil : .default) { model.removeFromLists(reviewed) }
                    operation = Task { await delete(reviewed) }
                }
                Button("Cancel", role: .cancel) { end() }
            } message: { reviewed in
                Text(DeleteAllCopy(reviewed.summary).message)
            }
            .alert(
                notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
                presenting: notice
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { shown in
                Text(shown.message)
            }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    operation?.cancel()
                    review = nil
                    notice = nil
                    end()
                }
            }
            .onDisappear {
                guard started, model.deleteAllPhase != .deleting else { return }
                operation?.cancel()
                end()
            }
    }
    private func end() {
        guard started else { return }
        started = false
        model.endDeleteAll()
    }
    private func check() async {
        do {
            let checked = try await model.reviewDeleteAll()
            guard !Task.isCancelled, !model.locked else {
                end()
                return
            }
            if !checked.items.isEmpty {
                review = checked
                model.deleteAllPhase = .confirming
                return
            }
            if !checked.held.isEmpty { notice = DeleteAllCopy.nothingDeletable(checked.held.map(\.reason)) }
        } catch { report(error) }
        end()
    }
    private func delete(_ reviewed: DeleteAllReview) async {
        // The deletion ends Delete All itself, also when locking stops it part way.
        started = false
        do {
            let batch = try await model.permanentlyDeleteAll(reviewed, settle: reduceMotion ? .zero : .listRemoval)
            guard !model.locked else { return }
            if !batch.refreshed {
                model.error =
                    "The items were deleted, but My Journal couldn’t update the view. Reopen My Journal to continue."
            } else if !batch.failedRows.isEmpty {
                notice = DeleteAllCopy.changedMeanwhile(batch.failedRows.count)
            }
        } catch { report(error) }
    }
    private func report(_ failure: Error) {
        guard !model.locked, !Task.isCancelled, !(failure is CancellationError) else { return }
        model.report(failure, .saving)
    }
}

/// An alert that only informs.
struct DeletionNotice: Equatable {
    let title: String
    let message: String
}

/// What Delete All's alert counts: the items it deletes and why others stay.
struct DeleteAllSummary: Equatable {
    var journals = 0
    var templates = 0
    /// Entries deleted, on their own or with their journal.
    var entries = 0
    var held: [DeletionHold] = []
    /// The one item deleted, when there is only one: its kind, title and entries.
    var single: (kind: String, title: String, entryCount: Int)?
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.journals == rhs.journals && lhs.templates == rhs.templates && lhs.entries == rhs.entries
            && lhs.held == rhs.held && lhs.single?.kind == rhs.single?.kind && lhs.single?.title == rhs.single?.title
            && lhs.single?.entryCount == rhs.single?.entryCount
    }
}

extension DeleteAllReview {
    var summary: DeleteAllSummary {
        let plan = items.count == 1 ? items.first?.confirmation.plan : nil
        return DeleteAllSummary(
            journals: journals, templates: templates, entries: entries, held: held.map(\.reason),
            single: plan.map { ($0.kind, $0.title, $0.entryCount) })
    }
}

/// The wording of Delete All's alerts (docs/design/ios-delete-all-and-settings-2026-10-03.md §2).
struct DeleteAllCopy {
    let title: String
    let message: String

    init(_ summary: DeleteAllSummary) {
        let held = Self.heldSentence(summary.held)
        if let single = summary.single {
            title = PermanentDeletionCopy.title(kind: single.kind, title: single.title, entryCount: single.entryCount)
            message = PermanentDeletionCopy.message(kind: single.kind, entryCount: single.entryCount, held: held)
            return
        }
        let kinds = [
            (summary.journals, "Journal", "Journals"), (summary.templates, "Template", "Templates"),
            (summary.entries, "Entry", "Entries"),
        ].filter { $0.0 > 0 }
        var sentences: [String] = []
        if kinds.count == 1, let only = kinds.first {
            title = "Delete \(only.0) \(only.0 == 1 ? only.1 : only.2) Permanently?"
        } else {
            title = "Delete \(kinds.reduce(0) { $0 + $1.0 }) Items Permanently?"
            let counted = kinds.map { "\($0.0) \(($0.0 == 1 ? $0.1 : $0.2).lowercased())" }
            sentences.append("Includes \(ListFormatter.localizedString(byJoining: counted)).")
        }
        if let held { sentences.append(held) }
        sentences.append(PermanentDeletionCopy.retention)
        message = sentences.joined(separator: " ")
    }

    /// Why items stay, before “You can’t undo this.”
    static func heldSentence(_ held: [DeletionHold]) -> String? {
        guard let first = held.first else { return nil }
        let one = held.count == 1
        let items = one ? "1 item" : "\(held.count) items"
        let reason: String
        switch held.allSatisfy({ $0 == first }) ? first : .other {
        case .review: reason = one ? "has changes that need review" : "have changes that need review"
        case .newerVersion:
            return one
                ? "1 item was saved by a newer version and stays in Recently Deleted. Update My Journal to delete it."
                : "\(held.count) items were saved by a newer version and stay in Recently Deleted. Update My Journal to delete them."
        case .other: reason = "can’t be deleted yet"
        }
        return "\(items) \(reason) and will stay in Recently Deleted."
    }

    /// When nothing in Recently Deleted can be deleted, there is nothing to confirm.
    static func nothingDeletable(_ held: [DeletionHold]) -> DeletionNotice {
        let one = held.count == 1
        let message: String
        switch held.allSatisfy({ $0 == held.first }) ? held.first ?? .other : .other {
        case .review:
            message =
                one
                ? "This has changes that need review before it can be deleted."
                : "These items have changes that need review before they can be deleted."
        case .newerVersion:
            message = one ? "Update My Journal to delete this." : "Update My Journal to delete these items."
        case .other: message = one ? "This can’t be deleted yet." : "These items can’t be deleted yet."
        }
        return DeletionNotice(title: one ? "Item Can’t Be Deleted" : "Items Can’t Be Deleted", message: message)
    }

    /// Items that changed between the alert and deleting stay.
    static func changedMeanwhile(_ count: Int) -> DeletionNotice {
        count == 1
            ? DeletionNotice(
                title: "1 Item Couldn’t Be Deleted",
                message: "It changed since you chose to delete it. It’s still in Recently Deleted.")
            : DeletionNotice(
                title: "\(count) Items Couldn’t Be Deleted",
                message: "They changed since you chose to delete them. They’re still in Recently Deleted.")
    }
}
