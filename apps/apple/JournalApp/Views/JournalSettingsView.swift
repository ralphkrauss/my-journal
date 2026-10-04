import JournalCore
import SwiftUI

struct JournalSettingsView: View {
    @EnvironmentObject var model: AppModel
    var journalID: UUID?
    @State private var journalName = ""
    @State private var newNameTaken: String?
    @State private var reviewing: ConflictVersion?
    @State private var lifecycleJournal: JournalItem?
    @State private var history: JournalItem?
    @State private var deletionRequest: UUID?
    private var deletedJournals: [JournalItem] {
        model.items.filter {
            $0.kind == "journal" && $0.deletedAt != nil && (journalID == nil || $0.id == journalID)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        Form {
            ForEach(model.journalRecords.filter { journalID == nil || $0.id == journalID }) { journal in
                Section(journal.title.isEmpty ? "Untitled Journal" : journal.title) {
                    JournalNameField(journal: journal).disabled(hasConflict(journal) || model.replacingVault)
                    Picker(
                        "Default Template",
                        selection: Binding(
                            get: { model.items.first { $0.id == journal.id }?.defaultTemplateID },
                            set: { value in model.changeJournal(journal.id, template: value) })
                    ) {
                        Text("Blank Entry").tag(nil as UUID?)
                        if let id = journal.defaultTemplateID, !model.templates.contains(where: { $0.id == id }) {
                            Text("Unavailable Template").tag(Optional(id)).disabled(true)
                        }
                        ForEach(model.templates) {
                            Text($0.title.isEmpty ? "Untitled Template" : $0.title).tag(Optional($0.id))
                        }
                    }.disabled(
                        hasConflict(journal) || model.replacingVault || !model.offersDefaultTemplateChoice(for: journal)
                    )
                    .accessibilityIdentifier("journal-default-template-\(journal.id.uuidString)")
                    reviewActions(journal)
                    Button("Delete Journal…", role: .destructive) { deletionRequest = journal.id }.foregroundStyle(.red)
                        .disabled(model.replacingVault)
                        .accessibilityLabel("Delete journal \(journal.title)")
                }
            }
            if !deletedJournals.isEmpty {
                Section("Deleted Journals") {
                    ForEach(deletedJournals) { journal in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(journal.title.isEmpty ? "Untitled Journal" : journal.title).font(.headline)
                            reviewActions(journal)
                            Button("Restore Journal…") { lifecycleJournal = journal }.disabled(model.replacingVault)
                                .accessibilityLabel("Restore journal \(journal.title)")
                        }
                    }
                }
            }
            if journalID == nil {
                Section("New Journal") {
                    TextField("Name", text: $journalName).accessibilityIdentifier("New journal name")
                        .onValueChange(of: journalName) { _ in newNameTaken = nil }
                    if let newNameTaken { JournalNameTakenMessage(name: newNameTaken) }
                    Button("Create") {
                        if let taken = model.journalNameTaken(journalName) {
                            newNameTaken = taken
                            return
                        }
                        Task {
                            await model.createJournal(journalName)
                            journalName = ""
                        }
                    }.disabled(
                        journalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.replacingVault)
                }
            }
        }.formStyle(.grouped)
            .sheet(item: $reviewing) { JournalConflictView(conflict: $0) }
            .sheet(item: $lifecycleJournal) {
                JournalLifecycleView(journalID: $0.id, restoring: $0.deletedAt != nil)
            }
            .sheet(item: $history) { JournalHistoryView(journalID: $0.id) }
            .journalDeletionPrompt($deletionRequest)
            .onValueChange(of: model.locked) { locked in
                if locked {
                    reviewing = nil
                    history = nil
                    lifecycleJournal = nil
                }
            }
    }
    private func hasConflict(_ journal: JournalItem) -> Bool { model.conflicts.contains { $0.id == journal.id } }
    @ViewBuilder private func reviewActions(_ journal: JournalItem) -> some View {
        if hasConflict(journal) {
            Text("Changes need review").foregroundStyle(.secondary)
            Button("Review Changes") { reviewing = model.conflicts.first { $0.id == journal.id } }.disabled(
                model.replacingVault)
        }
        if model.journalHistoryIDs.contains(journal.id) {
            Button("Version History…") { history = journal }.disabled(model.replacingVault)
        }
    }
}

/// A journal's name, saved once when editing ends (Return or leaving the field), as the sidebar's Rename does.
private struct JournalNameField: View {
    @EnvironmentObject var model: AppModel
    let journal: JournalItem
    @State private var name: String
    @FocusState private var focused: Bool
    init(journal: JournalItem) {
        self.journal = journal
        _name = State(initialValue: journal.title)
    }
    /// The name of the journal that already has the typed name, after Return (§4.1).
    @State private var taken: String?
    private var savedName: String { model.items.first { $0.id == journal.id }?.title ?? journal.title }
    var body: some View {
        TextField("Name", text: $name).focused($focused).onSubmit { commit(leaving: false) }
            .onValueChange(of: focused) { if !$0 { commit(leaving: true) } }
            .onValueChange(of: savedName) { saved in
                if !focused { name = saved }
            }
            .onValueChange(of: name) { _ in if focused { taken = nil } }
            .onDisappear { commit(leaving: true) }
        if let taken { JournalNameTakenMessage(name: taken) }
    }
    /// Return keeps a taken name in the field with the message below it; leaving the field puts back the saved name.
    private func commit(leaving: Bool) {
        guard name != savedName else {
            taken = nil
            return
        }
        // A name can't be blank; the field returns to the saved name.
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            name = savedName
            return
        }
        if let other = model.journalNameTaken(name, excluding: journal.id) {
            if leaving {
                name = savedName
                taken = nil
            } else {
                taken = other
                focused = true
            }
            return
        }
        taken = nil
        model.changeJournal(journal.id, name: name)
    }
}

/// "A journal named “…” already exists." below a name field, announced when it appears.
struct JournalNameTakenMessage: View {
    let name: String
    var body: some View {
        Text("A journal named “\(name)” already exists.").foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { JournalAccessibility.announce("A journal named “\(name)” already exists.") }
    }
}
