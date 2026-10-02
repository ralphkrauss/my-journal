import JournalCore
import SwiftUI

struct JournalHistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let journalID: UUID
    @State private var versions: [JournalItem] = []
    @State private var selected = 0
    @State private var loading = true
    @State private var preparing = false
    @State private var busy = false
    @State private var completed = false
    @State private var needsReload = false
    @State private var unavailable = false
    @State private var error: String?
    @State private var result: String?
    @State private var comparison: JournalSettingsComparison?
    @State private var conflict: ConflictVersion?
    @State private var reviewing = false
    @State private var operation: Task<Void, Never>?
    private var working: Bool { loading || preparing || busy }
    private var version: JournalItem? { versions.indices.contains(selected) ? versions[selected] : nil }
    var body: some View {
        layout
            .interactiveDismissDisabled(preparing || busy)
            .task { await load() }
            .onDisappear { operation?.cancel() }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    operation?.cancel()
                    versions = []
                    comparison = nil
                    conflict = nil
                    reviewing = false
                    error = nil
                    result = nil
                    dismiss()
                }
            }
            .onValueChange(of: error) { message in
                if let message, !model.locked { JournalAccessibility.announce(message) }
            }
            .sheet(item: $comparison) { snapshot in
                JournalSettingsConfirmation(
                    comparison: snapshot, busy: $busy, takenName: model.restoringNameTaken(snapshot)
                ) { restore(snapshot) }
            }
            .sheet(isPresented: $reviewing) {
                if let conflict { JournalConflictView(conflict: conflict) }
            }
    }
    @ViewBuilder private var layout: some View {
        #if os(iOS)
            NavigationStack {
                content.navigationTitle("Version History").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { closeButton } }
            }
        #else
            VStack(spacing: 0) {
                Text("Version History").font(.title2.bold()).padding(.top, 24)
                content
                Divider()
                HStack {
                    closeButton
                    Spacer()
                }.padding()
            }.frame(minWidth: 360, idealWidth: 460, minHeight: 360, idealHeight: 520)
        #endif
    }
    private var closeButton: some View {
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(preparing || busy)
    }
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !model.locked {
                    if loading {
                        ProgressView("Loading History…")
                    } else if versions.isEmpty {
                        if error == nil { Text("No Earlier Versions").foregroundStyle(.secondary) }
                    } else {
                        HistoryVersionPicker(versions: versions, selected: $selected)
                            .disabled(working || completed || comparison != nil)
                        if let version { JournalMetadataSummary(item: version) }
                        if !completed {
                            if version?.document.isEditable == true {
                                Button("Restore Settings…") { prepare() }
                                    .disabled(working || needsReload || model.replacingVault)
                            } else {
                                Text("Update My Journal to restore this version.").foregroundStyle(.secondary)
                                ArchiveExportControls()
                            }
                        }
                    }
                    if preparing { ProgressView("Loading Settings…") }
                    if let error { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let result { Text(result) }
                    if !completed { recoveryActions }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var recoveryActions: some View {
        if needsReload {
            Button("Reload History") { operation = Task { await load() } }.disabled(working)
        }
        if conflict != nil {
            Button("Review Changes") { reviewing = true }.disabled(working)
        }
        if unavailable { ArchiveExportControls() }
    }
    private func load() async {
        guard !model.locked, !preparing, !busy, let store = model.store else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let loaded = try await store.history(for: journalID)
            try Task.checkCancellation()
            guard !model.locked else { return }
            versions = HistoryVersions.newestFirst(loaded.filter { $0.kind == "journal" })
            selected = 0
            needsReload = false
        } catch is CancellationError {} catch {
            if !model.locked {
                needsReload = true
                self.error = error.localizedDescription
            }
        }
    }
    private func prepare() {
        guard !working, !completed, !model.locked, !model.replacingVault, let version, let store = model.store else {
            return
        }
        preparing = true
        error = nil
        unavailable = false
        conflict = nil
        operation = Task {
            defer { preparing = false }
            do {
                let current = try await store.item(journalID)
                let latestConflict = try await store.conflicts().first { $0.id == journalID }
                let templates = try await store.items().filter { $0.kind == "template" && $0.deletedAt == nil }
                try Task.checkCancellation()
                guard !model.locked, !model.replacingVault else { return }
                if let latestConflict {
                    conflict = latestConflict
                    error = "These changes need review before you can continue."
                } else if let current, current.kind == "journal", current.document.isEditable {
                    comparison = JournalSettingsComparison(
                        current: current, historical: version, templates: templates)
                } else {
                    unavailable = true
                    error = "This journal can’t be changed here. You can export your journals."
                }
            } catch is CancellationError {} catch {
                if !model.locked { self.error = error.localizedDescription }
            }
        }
    }
    private func restore(_ snapshot: JournalSettingsComparison) {
        guard !working, !completed, !model.locked, !model.replacingVault else { return }
        busy = true
        error = nil
        operation = Task {
            defer {
                busy = false
                comparison = nil
            }
            do {
                let refreshed = try await model.restoreHistoricalJournalSettings(
                    snapshot.historical, expectedJournal: snapshot.current)
                guard !model.locked else { return }
                completed = true
                result = "The settings were restored. Reopen your journal to see them."
                if refreshed { dismiss() }
            } catch HistoryRecoveryError.settingsAlreadyApplied {
                if !model.locked {
                    completed = true
                    result = "These settings are already in use."
                }
            } catch JournalLifecycleError.conflict {
                await loadConflict()
            } catch JournalLifecycleError.missingJournal, JournalLifecycleError.unsupportedJournal {
                guard !model.locked else { return }
                unavailable = true
                error = "This journal can’t be changed here. You can export your journals."
            } catch is CancellationError {} catch {
                guard !model.locked else { return }
                if case HistoryRecoveryError.unavailableVersion = error { needsReload = true }
                self.error = error.localizedDescription
            }
        }
    }
    private func loadConflict() async {
        do {
            let latest = try await model.store?.conflicts().first { $0.id == journalID }
            try Task.checkCancellation()
            guard !model.locked, !model.replacingVault else { return }
            conflict = latest
            error = "These changes need review before you can continue."
        } catch is CancellationError {} catch {
            if !model.locked { self.error = error.localizedDescription }
        }
    }

}
