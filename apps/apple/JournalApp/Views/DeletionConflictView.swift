import JournalCore
import SwiftUI

struct DeletionConflictView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID
    @State private var confirmation: DeletionConflictConfirmation?
    @State private var images: [UUID: Data] = [:]
    @StateObject private var previewActions = EditorActions()
    @State private var busy = false
    @State private var completed = false
    @State private var unsupported = false
    @State private var reloadJournals = false
    @State private var error: String?
    @State private var deleting = false
    @State private var recoveringCopy: Bool?
    @State private var destination: UUID?
    @State private var creatingJournal = false
    @State private var operation: Task<Void, Never>?
    @ScaledMetric(relativeTo: .body) private var textSize = 17.0
    private var destinations: [JournalItem] {
        model.journals.filter { journal in
            !model.conflicts.contains { $0.id == journal.id }
        }
    }
    private var destinationIDs: [UUID] { destinations.map(\.id) }
    private func ambiguous(_ item: JournalItem) -> Bool {
        destinations.filter { $0.title.localizedCaseInsensitiveCompare(item.title) == .orderedSame }.count > 1
    }

    private func destinationName(_ journal: JournalItem) -> String {
        guard ambiguous(journal) else { return journal.displayTitle }
        let date = journal.date.formatted(date: .abbreviated, time: .standard)
        let name = "\(journal.displayTitle) · \(date)"
        let peers = destinations.filter {
            $0.title.localizedCaseInsensitiveCompare(journal.title) == .orderedSame
                && $0.date.formatted(date: .abbreviated, time: .standard) == date
        }
        guard peers.count > 1 else { return name }
        let identity = journal.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        var length = 8
        while length < identity.count,
            peers.contains(where: {
                $0.id != journal.id
                    && $0.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
                        .hasPrefix(String(identity.prefix(length)))
            })
        { length += 1 }
        return "\(name) · \(identity.prefix(length))"
    }

    var body: some View {
        DeletionSheet(title: "Review Changes", busy: busy, completed: completed) {
            if !model.locked {
                if let confirmation, !completed {
                    review(confirmation)
                }
                if busy { ProgressView("Please Wait…") }
                if let error { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                if !busy, !completed, confirmation == nil {
                    if unsupported {
                        ArchiveExportControls()
                    } else {
                        Button(reloadJournals ? "Reload Journals" : "Review Again") {
                            operation = Task { await prepare() }
                        }
                    }
                }
            }
        }
        .task { await prepare() }
        .onDisappear { operation?.cancel() }
        .onValueChange(of: error) { value in
            if let value, !model.locked { JournalAccessibility.announce(value) }
        }
        .onValueChange(of: model.locked) { locked in
            if locked {
                operation?.cancel()
                confirmation = nil
                images = [:]
                destination = nil
                recoveringCopy = nil
                deleting = false
                creatingJournal = false
                error = nil
                dismiss()
            }
        }
        .onValueChange(of: destinationIDs) { ids in
            if let destination, !ids.contains(destination) { self.destination = nil }
        }
        .sheet(isPresented: $creatingJournal) { RecoveryJournalView() }
        .sheet(isPresented: $deleting) {
            if let confirmation {
                DeletionSheet(title: destructiveTitle(confirmation), busy: busy) {
                    if !model.locked {
                        if let edited = confirmation.edited {
                            Text(edited.displayTitle).font(.title2)
                            if edited.kind == "entry" {
                                Text(edited.date, format: .dateTime).foregroundStyle(.secondary)
                            }
                            Text(
                                edited.kind == "journal"
                                    ? "Removes this edited journal’s name, template setting, and earlier versions from My Journal."
                                    : "Removes this edited version and its earlier versions from My Journal.")
                        } else {
                            event(confirmation.deletion, location: "Deletion to Keep", device: "Unknown Device")
                            Text("Any remaining earlier versions will be removed from My Journal on this device.")
                        }
                        DeletionConsequences()
                        Button("Delete Permanently", role: .destructive) {
                            resolve(confirmation, choice: .keepDeletion)
                        }
                        .disabled(busy)
                        if busy { ProgressView("Deleting…") }
                    }
                }
            }
        }
    }
    @ViewBuilder private func review(_ reviewed: DeletionConflictConfirmation) -> some View {
        let conflict = reviewed.conflict
        event(conflict.local, location: "On This Device", device: "Unknown Device")
        event(conflict.remote, location: "Received Version", device: "Unknown Device")
        if let edited = reviewed.edited {
            if edited.kind != "journal" {
                Text(edited.displayTitle).font(.title2).textSelection(.enabled)
                NativeEditor(
                    document: .constant(edited.document), itemID: edited.id, images: images,
                    fontSize: textSize, editable: false, actions: previewActions
                ) { _ in nil }.frame(minHeight: 260)
            } else {
                JournalMetadataSummary(item: edited)
            }
            if let recoveringCopy {
                destinationChoices(reviewed, asCopy: recoveringCopy)
            } else {
                if edited.kind == "entry" {
                    Button("Keep Entry…") { self.recoveringCopy = false }.disabled(busy)
                    Text("Keeps the edited entry. Earlier versions already deleted aren’t restored.").foregroundStyle(
                        .secondary)
                    Button("Keep Entry as Copy…") { self.recoveringCopy = true }.disabled(busy)
                    Text(
                        "Creates a new entry and keeps the original deleted. Any remaining earlier versions stay available in archive exports."
                    )
                    .foregroundStyle(.secondary)
                } else if edited.kind == "template" {
                    Button("Keep Template") { resolve(reviewed, choice: .keepTemplate) }.disabled(busy)
                    Text("Keeps the edited template. Earlier versions already deleted aren’t restored.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Keep Journal") { resolve(reviewed, choice: .keepJournal) }.disabled(busy)
                    Text("Keeps this journal’s name and template. Deleted entries aren’t restored.").foregroundStyle(
                        .secondary)
                    if let renamed = model.restoredName(of: edited) {
                        Text(
                            "Another journal is named “\(JournalNames.displayName(edited.title))”, so this one will be restored as “\(renamed)”."
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Keep Deletion…", role: .destructive) { deleting = true }.disabled(busy)
                Text(
                    edited.kind == "journal"
                        ? "Removes this edited journal’s name, template setting, and earlier versions from My Journal."
                        : "Removes this edited version and its earlier versions from My Journal."
                ).foregroundStyle(.secondary)
            }
        } else {
            Text("Both versions show this \(Self.noun(reviewed.deletion)) as deleted.")
            Text("Keeping the deletion also removes any remaining earlier versions from My Journal.").foregroundStyle(
                .secondary)
            Button("Keep Deletion…", role: .destructive) { deleting = true }.disabled(busy)
        }
    }
    private func event(_ item: JournalItem, location: String, device: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.isPermanentlyDeleted ? Self.deletedTitle(item) : item.displayTitle)
                .font(.headline)
            Text(location).foregroundStyle(.secondary)
            Text(device).foregroundStyle(.secondary)
            Text(item.permanentlyDeletedAt ?? item.modifiedAt, format: .dateTime).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private func destinationChoices(_ reviewed: DeletionConflictConfirmation, asCopy: Bool) -> some View {
        Text("Choose a Journal").font(.headline)
        ForEach(destinations) { journal in
            Button {
                destination = journal.id
            } label: {
                HStack {
                    Text(destinationName(journal)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if destination == journal.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                }
            }.disabled(busy).accessibilityAddTraits(destination == journal.id ? .isSelected : [])
        }
        Button("New Journal…") { creatingJournal = true }.disabled(busy)
        if let destination, destinationIDs.contains(destination),
            let journal = destinations.first(where: { $0.id == destination })
        {
            Text("Journal: \(destinationName(journal))").foregroundStyle(.secondary)
            Button(asCopy ? "Keep Entry as Copy" : "Keep Entry") {
                resolve(
                    reviewed,
                    choice: asCopy ? .keepEntryAsCopy(journalID: destination) : .keepEntry(journalID: destination))
            }.disabled(busy)
        }
        Button("Back") {
            recoveringCopy = nil
            destination = nil
        }.disabled(busy)
    }
    private func destructiveTitle(_ reviewed: DeletionConflictConfirmation) -> String {
        let kind = Self.noun(reviewed.deletion).capitalized
        return reviewed.edited == nil ? "Keep \(kind) Deleted?" : "Delete Edited \(kind)?"
    }
    /// “journal”, “template” or “entry”.
    static func noun(_ item: JournalItem) -> String {
        ["journal", "template"].contains(item.kind) ? item.kind : "entry"
    }
    /// How a record deleted permanently is named, since its marker has no title.
    static func deletedTitle(_ item: JournalItem) -> String { "Deleted " + noun(item).capitalized }
    private func prepare() async {
        guard !busy, !completed, !model.locked else { return }
        busy = true
        error = nil
        unsupported = false
        reloadJournals = false
        confirmation = nil
        images = [:]
        recoveringCopy = nil
        destination = nil
        defer { busy = false }
        do {
            let reviewed = try await model.prepareDeletionConflict(recordID)
            try await model.refresh()
            guard let store = model.store else { throw JournalError.locked }
            var loaded: [UUID: Data] = [:]
            for id in Set(reviewed.edited?.document.attachmentIDs ?? []) {
                loaded[id] = try? await store.attachment(id)
            }
            try Task.checkCancellation()
            guard !model.locked, model.store === store else { return }
            confirmation = reviewed
            images = loaded
        } catch { handle(error) }
    }
    private func resolve(_ reviewed: DeletionConflictConfirmation, choice: DeletionConflictChoice) {
        guard !busy, !completed, !model.locked else { return }
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                let refreshed = try await model.resolveDeletionConflict(reviewed, choice: choice)
                guard !model.locked else { return }
                completed = true
                deleting = false
                confirmation = nil
                images = [:]
                if refreshed {
                    dismiss()
                } else {
                    error =
                        "Your choice was saved, but My Journal couldn’t update the view. Reopen My Journal to continue."
                }
            } catch { handle(error) }
        }
    }
    private func handle(_ failure: Error) {
        guard !model.locked, !Task.isCancelled, !(failure is CancellationError) else { return }
        deleting = false
        confirmation = nil
        images = [:]
        recoveringCopy = nil
        destination = nil
        switch failure {
        case HistoryRecoveryError.destinationUnavailable, JournalError.conflict:
            reloadJournals = true
            error = "That journal is no longer available. Reload journals and choose another."
        case PermanentDeletionError.changed:
            error = "These changes have been updated. Review them again."
        case PermanentDeletionError.unsupported:
            unsupported = true
            error = "Update My Journal to review these changes. You can export an archive to keep a copy."
        default: error = failure.shown(.saving)
        }
    }
}
