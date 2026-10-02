import JournalCore
import SwiftUI

struct EntryConflictReview: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var textSize = 17.0
    let id: UUID
    @State private var showRemote = false
    @State private var confirmation: ResolutionRequest?
    @State private var busy = false
    @State private var committed = false
    @State private var needsRefresh = false
    @State private var refreshGeneration = 0
    @AccessibilityFocusState private var statusFocused: Bool
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @StateObject private var previewActions = EditorActions()
    @StateObject private var imageLoader = DocumentImageLoader()
    private var conflict: ConflictVersion? { model.conflicts.first { $0.id == id } }
    private var previewItem: JournalItem? { committed ? nil : (showRemote ? conflict?.remote : conflict?.local) }
    private var imageRequest: PreviewImageRequest {
        PreviewImageRequest(
            item: previewItem, store: model.store.map(ObjectIdentifier.init),
            enabled: !model.locked && !model.replacingVault && !needsRefresh)
    }
    var body: some View {
        ScrollViewReader { proxy in
            DeletionSheet(title: "Review Changes", busy: busy, completed: committed || conflict == nil) {
                if let status = reviewStatus {
                    Text(status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .id("review-status").accessibilityFocused($statusFocused)
                }
                if committed {
                    if !busy {
                        Text("Changes saved. The entry couldn’t be reloaded.").fixedSize(
                            horizontal: false, vertical: true)
                        Button("Try Again") { reload() }
                    }
                } else if needsRefresh {
                    if !busy { Button("Try Again") { reload() } }
                } else if let conflict, let item = previewItem {
                    versionPicker.disabled(busy)
                    Text(item.displayTitle).font(.title2).fixedSize(horizontal: false, vertical: true)
                    Text(item.modifiedAt, format: .dateTime).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let place = ConflictPlacement.line(for: item, other: otherItem(conflict), journals: journals) {
                        Text(place).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    NativeEditor(
                        document: .constant(item.document), itemID: item.id, images: imageLoader.images,
                        loadingImages: imageLoader.loading, fontSize: textSize, editable: false, actions: previewActions
                    ) { _ in nil }
                    .id(showRemote).frame(height: 300)
                    .accessibilityHint(showRemote ? "Version from Other Device" : "Version from This Device")
                    Text(keepBothNote(conflict)).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Keep Both") { resolve(ResolutionRequest(conflict: conflict, choice: .keepBoth)) }
                        .buttonStyle(.borderedProminent).disabled(busy)
                    Menu("Keep One Version") {
                        Button("Keep Version from This Device…") {
                            confirmation = ResolutionRequest(conflict: conflict, choice: .local)
                        }
                        Button("Keep Version from Other Device…") {
                            confirmation = ResolutionRequest(conflict: conflict, choice: .remote)
                        }
                    }.disabled(busy)
                } else {
                    Text("These changes have been resolved.").fixedSize(horizontal: false, vertical: true)
                        .id("review-status").accessibilityFocused($statusFocused)
                }
                if busy { ProgressView(needsRefresh ? "Updating Changes…" : "Saving Changes…") }
            }
            .onValueChange(of: refreshGeneration) { _ in
                proxy.scrollTo("review-status", anchor: .top)
                statusFocused = true
            }
            .confirmationDialog(
                "Keep this version?",
                isPresented: Binding(
                    get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation
            ) { request in
                Button("Keep Version") { resolve(request) }
            } message: { request in
                Text(keepOneMessage(request))
            }
            .task(id: imageRequest) {
                imageLoader.update(previewItem, store: model.store, enabled: imageRequest.enabled)
                await imageLoader.task?.value
            }
            .onDisappear { cancel() }
            .onValueChange(of: model.locked) {
                if $0 {
                    cancel()
                    dismiss()
                }
            }
            .onValueChange(of: model.replacingVault) {
                if $0 {
                    cancel()
                    dismiss()
                }
            }
            .onValueChange(of: conflict) { value in
                guard !committed else { return }
                confirmation = nil
                showRemote = false
                error = value == nil ? nil : "These changes were updated. Review both versions again."
            }
        }
    }
    /// Every journal, including deleted ones, so a version in Recently Deleted still names its journal.
    private var journals: [JournalItem] { model.items.filter { $0.kind == "journal" } }
    private func otherItem(_ conflict: ConflictVersion) -> JournalItem { showRemote ? conflict.local : conflict.remote }
    private func keepBothNote(_ conflict: ConflictVersion) -> String {
        let note =
            conflict.local.kind == "template"
            ? "Keep Both saves the versions as separate templates."
            : "Keep Both saves the versions as separate entries."
        guard let outcome = ConflictPlacement.keepBothOutcome(conflict.local, conflict.remote) else { return note }
        return note + " " + outcome
    }
    private func keepOneMessage(_ request: ResolutionRequest) -> String {
        let history = "The original versions will remain in Version History."
        // Keeping this device's version leaves the entry as it is here.
        guard request.choice == .remote,
            let outcome = ConflictPlacement.outcome(
                keepingRemote: request.conflict.remote, local: request.conflict.local, journals: journals)
        else { return history }
        return outcome + " " + history
    }
    private var reviewStatus: String? {
        guard !committed else { return nil }
        if needsRefresh { return busy ? nil : "Changes couldn’t be updated." }
        return error
    }
    @ViewBuilder private var versionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                Picker("Version", selection: $showRemote) { versionOptions }
            } label: {
                HStack {
                    Text(showRemote ? "Other Device" : "This Device").fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                }
            }.accessibilityLabel("Version").accessibilityValue(showRemote ? "Other Device" : "This Device")
                .accessibilityIdentifier("conflict-version")
        } else {
            Picker("Version", selection: $showRemote) { versionOptions }.pickerStyle(.segmented)
                .accessibilityIdentifier("conflict-version")
        }
    }
    private var versionOptions: some View {
        Group {
            Text("This Device").tag(false)
            Text("Other Device").tag(true)
        }
    }
    private func valid(_ store: JournalStore, session: UUID) -> Bool {
        !Task.isCancelled && model.store === store && model.vaultSessionID == session
            && !model.locked && !model.replacingVault
    }
    private func resolve(_ request: ResolutionRequest) {
        let session = model.vaultSessionID
        guard !busy, !committed, !needsRefresh, let store = model.store,
            valid(store, session: session), conflict == request.conflict
        else { return }
        busy = true
        error = nil
        operation = Task {
            defer {
                busy = false
                operation = nil
            }
            do {
                guard valid(store, session: session) else { return }
                guard await model.finishPendingSave() else {
                    throw JournalError.server("Your latest changes couldn’t be saved. Try again.")
                }
                guard valid(store, session: session) else { return }
                try await store.resolve(request.conflict, choice: request.choice)
                guard valid(store, session: session) else { return }
                committed = true
                try await refreshAfterCommit(store, session: session)
            } catch JournalError.conflict {
                guard valid(store, session: session), !committed else { return }
                await refreshReview(store, session: session)
            } catch {
                guard valid(store, session: session) else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private func reload() {
        let session = model.vaultSessionID
        guard !busy, committed || needsRefresh, let store = model.store,
            valid(store, session: session)
        else { return }
        busy = true
        operation = Task {
            defer {
                busy = false
                operation = nil
            }
            guard valid(store, session: session) else { return }
            if !committed {
                await refreshReview(store, session: session)
                return
            }
            do { try await refreshAfterCommit(store, session: session) } catch {
                guard valid(store, session: session) else { return }
                self.error = error.localizedDescription
            }
        }
    }
    private func refreshReview(_ store: JournalStore, session: UUID) async {
        guard valid(store, session: session) else { return }
        statusFocused = false
        needsRefresh = true
        confirmation = nil
        showRemote = false
        imageLoader.clear()
        let selected = model.selectedID
        let prior = model.items.first { $0.id == selected }
        do {
            try await model.refresh(forSession: session)
            guard valid(store, session: session) else { return }
            if let prior, model.selectedID == selected, model.draft == prior {
                model.draft = model.items.first { $0.id == selected }
                model.showDraftWhereItIs()
            }
            needsRefresh = false
            error = conflict == nil ? nil : "These changes were updated. Review both versions again."
        } catch {
            guard valid(store, session: session) else { return }
        }
        guard valid(store, session: session) else { return }
        busy = false
        refreshGeneration += 1
    }
    private func refreshAfterCommit(_ store: JournalStore, session: UUID) async throws {
        guard valid(store, session: session) else { return }
        // The entry stays open while the view refreshes. This review belongs to it, so closing the entry first
        // closed the review and stopped the refresh, leaving the list and the entry as they were before.
        try await model.refresh(forSession: session)
        // The review may close as the resolved changes reach the view; the entry still opens as it's now stored.
        guard model.store === store, model.vaultSessionID == session, !model.locked, !model.replacingVault else {
            return
        }
        if model.draft == nil || model.draft?.id == id, let resolved = model.items.first(where: { $0.id == id }) {
            model.selectedID = id
            model.draft = resolved
            model.rememberSelection()
        }
        dismiss()
    }
    private func cancel() {
        operation?.cancel()
        operation = nil
        confirmation = nil
        imageLoader.clear()
    }
}

private struct ResolutionRequest {
    let conflict: ConflictVersion
    let choice: ConflictChoice
}
private struct PreviewImageRequest: Equatable {
    let item: JournalItem?
    let store: ObjectIdentifier?
    let enabled: Bool
}

/// Where a version of an entry in review is, when the two versions differ in it: its journal, Recently Deleted or the
/// archive, and its entry date. Each choice keeps a version where it is, so this is also where it will be kept.
@MainActor enum ConflictPlacement {
    /// "In Home", "In Recently Deleted" or "Archived in Home", with the entry date when the dates differ too; nil when
    /// both versions are in the same place with the same date.
    static func line(for version: JournalItem, other: JournalItem, journals: [JournalItem]) -> String? {
        guard let phrase = phrase(for: version, other: other, journals: journals) else { return nil }
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }
    /// What keeping the other device's version does to this device's entry, for the confirmation; nil when it stays
    /// where it is with the same date.
    static func outcome(keepingRemote remote: JournalItem, local: JournalItem, journals: [JournalItem]) -> String? {
        let noun = remote.kind == "template" ? "template" : "entry"
        let date = remote.date.formatted(date: .abbreviated, time: .omitted)
        let move: String
        if remote.deletedAt != nil {
            move = "move to Recently Deleted"
        } else {
            let name = name(of: remote, journals: journals)
            move = remote.archivedAt == nil ? "move to " + name : "be archived in " + name
        }
        switch (moved(remote, local), redated(remote, local)) {
        case (true, true): return "The \(noun) will \(move), and its date will change to \(date)."
        case (true, false): return "The \(noun) will \(move)."
        case (false, true): return "The \(noun)’s date will change to \(date)."
        case (false, false): return nil
        }
    }
    /// What Keep Both does with the versions' places and dates.
    static func keepBothOutcome(_ local: JournalItem, _ remote: JournalItem) -> String? {
        switch (moved(local, remote), redated(local, remote)) {
        case (true, true): return "Each version keeps its place and date."
        case (true, false): return "Each version stays where it is."
        case (false, true): return "Each version keeps its date."
        case (false, false): return nil
        }
    }
    private static func phrase(for version: JournalItem, other: JournalItem, journals: [JournalItem]) -> String? {
        let date = "dated " + version.date.formatted(date: .abbreviated, time: .omitted)
        switch (moved(version, other), redated(version, other)) {
        case (true, true): return place(of: version, journals: journals) + ", " + date
        case (true, false): return place(of: version, journals: journals)
        case (false, true): return date
        case (false, false): return nil
        }
    }
    private static func moved(_ first: JournalItem, _ second: JournalItem) -> Bool {
        first.journalID != second.journalID || (first.deletedAt == nil) != (second.deletedAt == nil)
            || (first.archivedAt == nil) != (second.archivedAt == nil)
    }
    private static func redated(_ first: JournalItem, _ second: JournalItem) -> Bool {
        !Calendar.current.isDate(first.date, inSameDayAs: second.date)
    }
    private static func place(of version: JournalItem, journals: [JournalItem]) -> String {
        if version.deletedAt != nil { return "in Recently Deleted" }
        let name = name(of: version, journals: journals)
        return version.archivedAt == nil ? "in " + name : "archived in " + name
    }
    private static func name(of version: JournalItem, journals: [JournalItem]) -> String {
        guard version.kind != "template" else { return "Templates" }
        let title = journals.first { $0.id == version.journalID }?.title ?? ""
        return title.isEmpty ? "Untitled Journal" : title
    }
}
