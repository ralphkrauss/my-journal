import JournalCore
import SwiftUI

private enum EntryRecoveryIssue { case unavailable, unsupported, review }

struct JournalLifecycleView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let journalID: UUID
    var restoringEntryID: UUID?
    @State private var journal: JournalItem?
    @State private var entryPlan: EntryRestorationPlan?
    @State private var entryIssue: EntryRecoveryIssue?
    @State private var busy = false
    @State private var prepared = false
    @State private var loaded = false
    @State private var completed = false
    @State private var error: String?
    @State private var conflictID: UUID?
    @State private var reviewing = false
    @State private var operation: Task<Void, Never>?
    private var title: String {
        restoringEntryID != nil ? "Restore Entry" : "Restore Journal"
    }
    private var actionTitle: String {
        guard restoringEntryID != nil else { return title }
        return "Restore"
    }
    private var name: String {
        let value = journal?.title ?? ""
        return value.isEmpty ? "Untitled Journal" : value
    }
    private var eligibleCount: Int {
        entryPlan?.entryCount ?? model.restorableEntryCount(journalID)
    }
    private var countText: String {
        eligibleCount == 1 ? "1 entry on this device" : "\(eligibleCount) entries on this device"
    }
    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
                    content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { closeButton } }
                }
            #else
                VStack(spacing: 0) {
                    Text(title).font(.title2.bold()).padding(.top, 24)
                    content
                    Divider()
                    HStack {
                        closeButton
                        Spacer()
                    }.padding()
                }.frame(minWidth: 360, idealWidth: 460, minHeight: 360, idealHeight: 500)
            #endif
        }
        .interactiveDismissDisabled(busy)
        .task { await prepare() }
        .onDisappear { operation?.cancel() }
        .onValueChange(of: error) { value in
            if let value, !model.locked { JournalAccessibility.announce(value) }
        }
        .onValueChange(of: model.locked) { locked in
            if locked {
                operation?.cancel()
                journal = nil
                entryPlan = nil
                reviewing = false
                dismiss()
            }
        }
        .sheet(
            isPresented: $reviewing,
            onDismiss: {
                prepared = false
                entryPlan = nil
            }
        ) {
            if let conflict = model.conflicts.first(where: { $0.id == conflictID }) {
                if conflict.local.kind == "journal" {
                    JournalConflictView(conflict: conflict)
                } else {
                    ConflictReview(id: conflict.id)
                }
            } else {
                VStack(spacing: 16) {
                    Text("These changes have been resolved.")
                    Button("Done") { reviewing = false }
                }.padding()
            }
        }
    }
    private var closeButton: some View {
        Button(completed ? "Done" : "Cancel", role: .cancel) { dismiss() }
            .keyboardShortcut(.cancelAction).disabled(busy)
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.locked {
                    if let entry = entryPlan?.entry {
                        Text(entry.displayTitle).font(.title2).fixedSize(horizontal: false, vertical: true)
                        Text(entry.date, format: .dateTime.year().month().day()).foregroundStyle(.secondary)
                        Text("To restore this entry, its journal must also be restored.")
                    }
                    if journal != nil {
                        Text(name).font(.title2).fixedSize(horizontal: false, vertical: true)
                        Text(countText).foregroundStyle(.secondary)
                    }
                    if restoringEntryID == nil || entryPlan != nil { restorationExplanation }
                    if let error { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    if busy { ProgressView("Please Wait…") }
                    if !completed {
                        if prepared {
                            Button(action: commit) {
                                Text(actionTitle).multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.foregroundStyle(Color.accentColor).disabled(busy)
                                .accessibilityIdentifier("confirm-journal-lifecycle")
                        } else if entryIssue == nil, !busy,
                            !loaded || restoringEntryID != nil || journal?.document.isEditable == true
                        {
                            Button("Try Again") { operation = Task { await prepare() } }
                        }
                        entryFailureActions
                        if conflictID != nil { Button("Review Changes") { reviewing = true }.disabled(busy) }
                        if journal?.document.isEditable == false { ArchiveExportControls() }
                        if restoringEntryID == nil, loaded, journal == nil, !busy {
                            Text(
                                model.connection == nil
                                    ? "The journal is unavailable. Your entries are still saved."
                                    : "This journal hasn’t arrived on this device.")
                            if model.connection != nil {
                                Button("Try Syncing Again") {
                                    syncAndPrepare()
                                }
                            }
                            ArchiveExportControls()
                        }
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var entryFailureActions: some View {
        if let entryIssue {
            if entryIssue == .review {
                Button("Review Entry") { reviewEntry() }.disabled(busy)
            }
            if entryIssue == .unavailable && model.connection != nil {
                Button("Try Syncing Again") {
                    syncAndPrepare()
                }.disabled(busy)
            }
            ArchiveExportControls()
        }
    }
    private func syncAndPrepare() {
        guard !busy, !model.locked else { return }
        busy = true
        operation = Task {
            await model.sync()
            guard !Task.isCancelled, !model.locked else {
                busy = false
                return
            }
            busy = false
            await prepare()
        }
    }
    private func reviewEntry() {
        guard let restoringEntryID, !busy else { return }
        busy = true
        operation = Task {
            defer { busy = false }
            do {
                try await model.reviewRestoredEntry(restoringEntryID)
                guard !model.locked, !Task.isCancelled else { return }
                dismiss()
            } catch { await handle(error) }
        }
    }
    @ViewBuilder private var restorationExplanation: some View {
        Text(
            restoringEntryID == nil
                ? "Entries deleted with this journal will return, including entries that sync later. Entries you deleted separately will stay in Recently Deleted."
                : "Entries deleted with this journal will return, including entries that sync later. Other entries you deleted separately will stay in Recently Deleted."
        )
        let legacy = entryPlan?.legacyEntryCount ?? model.legacyEntryCount(journalID)
        if legacy > 0 {
            Text(
                legacy == 1
                    ? "1 entry from an earlier version of My Journal needs to be restored individually."
                    : "\(legacy) entries from an earlier version of My Journal need to be restored individually."
            )
            .foregroundStyle(.secondary)
        }
        if let journal, let renamed = model.restoredName(of: journal) {
            Text(
                "Another journal is named “\(JournalNames.displayName(journal.title))”, so this one will be restored as “\(renamed)”."
            )
        }
    }
    private func prepare() async {
        guard !busy, !model.locked, !Task.isCancelled else { return }
        busy = true
        prepared = false
        entryPlan = nil
        entryIssue = nil
        journal = nil
        error = nil
        loaded = false
        conflictID = nil
        defer { busy = false }
        do {
            if let restoringEntryID {
                let captured = try await model.prepareEntryRestoration(restoringEntryID, journalID: journalID)
                try Task.checkCancellation()
                guard !model.locked else { return }
                entryPlan = captured
                journal = captured.journal
                loaded = true
                prepared = true
                return
            }
            try await model.refresh()
            try Task.checkCancellation()
            guard !model.locked else { return }
            loaded = true
            journal = model.items.first { $0.id == journalID && $0.kind == "journal" }
            guard let journal else { return }
            guard journal.document.isEditable else { throw JournalLifecycleError.unsupportedJournal }
            if model.conflicts.contains(where: { $0.id == journalID }) {
                throw JournalLifecycleError.conflict(journalID)
            }
            if journal.deletedAt == nil { throw JournalLifecycleError.alreadyRestored }
            try Task.checkCancellation()
            guard !model.locked else { return }
            prepared = true
        } catch { await handle(error) }
    }
    private func commit() {
        guard prepared, !busy, let journal else { return }
        let capturedEntryPlan = entryPlan
        busy = true
        operation = Task {
            defer { busy = false }
            do {
                let refreshed: Bool
                if let capturedEntryPlan {
                    refreshed = try await model.restoreEntryAndJournal(capturedEntryPlan)
                } else if restoringEntryID != nil {
                    return
                } else {
                    refreshed = try await model.restoreJournal(journalID, expectedTitle: journal.title)
                }
                guard !model.locked, !Task.isCancelled else { return }
                completed = true
                prepared = false
                if refreshed {
                    dismiss()
                } else if capturedEntryPlan != nil {
                    error =
                        "The entry and journal were restored, but My Journal couldn’t update the view. Reopen My Journal to continue."
                } else {
                    error = "The journal was restored, but couldn’t be displayed. Reopen My Journal to try again."
                }
            } catch { await handle(error) }
        }
    }
    private func handle(_ failure: Error) async {
        guard !model.locked, !Task.isCancelled, !(failure is CancellationError) else { return }
        prepared = false
        entryPlan = nil
        if restoringEntryID != nil {
            journal = nil
            loaded = true
            switch failure {
            case EntryRestorationError.unavailable: entryIssue = .unavailable
            case EntryRestorationError.alreadyRestored: entryIssue = .review
            case JournalError.unsupportedFormat: entryIssue = .unsupported
            default: break
            }
        }
        if case JournalLifecycleError.conflict(let id) = failure {
            conflictID = id
            do { try await model.refresh() } catch {}
        }
        if case JournalLifecycleError.missingJournal = failure {
            journal = nil
            loaded = true
        }
        if case JournalLifecycleError.alreadyRestored = failure {
            completed = true
            do {
                try await model.refresh()
                await model.switchJournal(journalID)
                if model.saveFailure {
                    error = JournalError.saveRequired.shown(.saving)
                    return
                }
            } catch {
                self.error = "The journal was restored, but couldn’t be displayed. Reopen My Journal to try again."
                return
            }
        }
        guard !model.locked, !Task.isCancelled else { return }
        if case JournalLifecycleError.changed = failure {
            error = "This journal has changed. Review it again before continuing."
        } else {
            error = failure.shown(.saving)
        }
    }
}
