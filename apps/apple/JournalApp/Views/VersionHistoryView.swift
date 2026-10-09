import JournalCore
import SwiftUI

struct VersionHistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let sourceID: UUID
    let sourceKind: String
    @State private var versions: [JournalItem] = []
    @State private var selected = 0
    @State private var destination: UUID?
    @State private var images: [UUID: Data] = [:]
    @State private var loading = true
    @State private var busy = false
    @State private var completed = false
    @State private var needsReload = false
    @State private var needsDestinationRefresh = false
    @State private var error: String?
    @State private var creatingJournal = false
    @State private var operation: Task<Void, Never>?
    @StateObject private var previewActions = EditorActions()
    @ScaledMetric(relativeTo: .body) private var textSize = 17.0

    private var version: JournalItem? { versions.indices.contains(selected) ? versions[selected] : nil }
    private var restoreTitle: String { sourceKind == "template" ? "Restore as New Template" : "Restore as New Entry" }
    private var destinationIDs: [UUID] { model.journals.map(\.id) }
    private var canRestore: Bool {
        !loading && !busy && !completed && !needsReload && !needsDestinationRefresh && !model.locked
            && !model.replacingVault
            && version?.document.isEditable == true
            && (sourceKind == "template" || destination.map { destinationIDs.contains($0) } == true)
    }
    var body: some View {
        layout
            .interactiveDismissDisabled(busy)
            .task { await load(initial: true) }
            .task(id: selected) { await loadImages() }
            .onDisappear { operation?.cancel() }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    operation?.cancel()
                    versions = []
                    images = [:]
                    error = nil
                    destination = nil
                    creatingJournal = false
                    dismiss()
                }
            }
            .onValueChange(of: destinationIDs) { ids in
                if let destination, !ids.contains(destination) {
                    self.destination = nil
                    error = "Choose an available journal."
                }
            }
            .onValueChange(of: error) { message in
                if let message, !model.locked { JournalAccessibility.announce(message) }
            }
            .sheet(isPresented: $creatingJournal) { RecoveryJournalView() }
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
            }.frame(minWidth: 360, idealWidth: 600, minHeight: 420, idealHeight: 620)
        #endif
    }
    private var closeButton: some View {
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
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
                        HistoryVersionPicker(versions: versions, selected: $selected).disabled(busy || completed)
                        if let version { preview(version) }
                        if !completed && version?.document.isEditable == true {
                            if sourceKind == "entry" { destinationPicker }
                            Button(restoreTitle) { restore() }.disabled(!canRestore)
                        }
                    }
                    if let error { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    if completed {
                        Text(
                            sourceKind == "template"
                                ? "The version was restored. Reopen it from Templates."
                                : "The version was restored. Reopen it from your journal.")
                    } else {
                        recoveryActions
                    }
                    if busy { ProgressView(needsDestinationRefresh ? "Loading Journals…" : "Restoring Version…") }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func preview(_ item: JournalItem) -> some View {
        Text(item.displayTitle).font(.headline)
        if item.kind == "entry" {
            Text(item.date, format: .dateTime.year().month().day()).foregroundStyle(.secondary)
        }
        if item.document.isEditable {
            NativeEditor(
                document: .constant(item.document), itemID: item.id, images: images,
                fontSize: textSize, editable: false, actions: previewActions
            ) { _ in nil }.id(selected).frame(minHeight: 220)
        } else {
            Text("Update My Journal to restore this version.").foregroundStyle(.secondary)
            ArchiveExportControls()
        }
    }
    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            if destinationIDs.isEmpty {
                Text("Create a journal to restore this version.").foregroundStyle(.secondary)
            } else {
                Menu {
                    Picker("Journal", selection: $destination) {
                        Text("Choose a Journal").tag(nil as UUID?)
                        ForEach(model.journals) { journal in
                            Text(destinationName(journal)).tag(Optional(journal.id))
                        }
                    }.pickerStyle(.inline)
                } label: {
                    WrappingMenuLabel(
                        title: "Journal",
                        value: model.journals.first { $0.id == destination }.map(destinationName) ?? "Choose a Journal")
                }.accessibilityIdentifier("history-destination").disabled(busy)

            }
            Button("New Journal…") {
                destination = nil
                creatingJournal = true
            }.disabled(busy || model.replacingVault)
        }
    }
    private func destinationName(_ journal: JournalItem) -> String {
        let duplicates = model.journals.filter { $0.title == journal.title }
        let title = journal.title.isEmpty ? "Untitled Journal" : journal.title
        guard duplicates.count > 1 else { return title }
        let index = duplicates.firstIndex { $0.id == journal.id }.map { $0 + 1 } ?? 1
        return "\(title) · \(journal.date.formatted(date: .abbreviated, time: .shortened)) · \(index)"
    }
    @ViewBuilder private var recoveryActions: some View {
        if !loading && (needsReload || versions.isEmpty && error != nil) {
            Button("Reload History") { operation = Task { await load(initial: false) } }.disabled(busy || loading)
        }
        if needsDestinationRefresh {
            Button("Reload Journals") {
                guard !busy else { return }
                busy = true
                operation = Task {
                    defer { busy = false }
                    await reloadDestinations()
                }
            }.disabled(busy)
        }
    }
    private func load(initial: Bool) async {
        guard !model.locked, !busy, let store = model.store else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let loaded = try await store.history(for: sourceID)
            try Task.checkCancellation()
            guard !model.locked else { return }
            versions = HistoryVersions.newestFirst(loaded.filter { $0.kind == sourceKind })
            selected = 0
            needsReload = false
            if initial, let parent = model.items.first(where: { $0.id == sourceID })?.journalID,
                destinationIDs.contains(parent)
            {
                destination = parent
            }
            await loadImages()
        } catch is CancellationError {} catch {
            if !model.locked { self.error = error.shown(.reading) }
        }
    }
    private func loadImages() async {
        images = [:]
        guard let version, let store = model.store, !model.locked else { return }
        let index = selected
        var loaded: [UUID: Data] = [:]
        for id in Set(version.document.attachmentIDs) {
            loaded[id] = try? await store.attachment(id)
        }
        guard !Task.isCancelled, !model.locked, model.store === store, selected == index, self.version == version else {
            return
        }
        images = loaded
    }
    private func reloadDestinations() async {
        guard !model.locked else { return }
        needsDestinationRefresh = true
        do {
            try await model.refresh()
            try Task.checkCancellation()
            guard !model.locked else { return }
            needsDestinationRefresh = false
            error = "Choose an available journal."
        } catch is CancellationError {} catch {
            if !model.locked { self.error = error.shown(.reading) }
        }
    }
    private func restore() {
        guard canRestore, let version else { return }
        let target = sourceKind == "template" ? nil : destination
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                let refreshed = try await model.restoreHistoricalVersion(version, to: target)
                guard !model.locked else { return }
                completed = true
                if refreshed { dismiss() }
            } catch HistoryRecoveryError.destinationUnavailable {
                destination = nil
                await reloadDestinations()
            } catch JournalLifecycleError.conflict(let id) {
                do { try await model.refresh() } catch {}
                guard !model.locked else { return }
                // Changes from another device are combined at the next sync; what a newer version of the app must read
                // waits for it.
                if model.heldConflictIDs.contains(id) {
                    error = JournalLifecycleError.unsupportedJournal.shown(.saving)
                } else {
                    error = JournalLifecycleError.conflict(id).shown(.saving)
                }
            } catch is CancellationError {} catch {
                guard !model.locked else { return }
                if case HistoryRecoveryError.unavailableVersion = error { needsReload = true }
                self.error = error.shown(.saving)
            }
        }
    }
}
