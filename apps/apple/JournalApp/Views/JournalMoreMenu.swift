import JournalCore
import SwiftUI

struct JournalMoreMenu: View {
    @EnvironmentObject private var model: AppModel
    let journal: JournalItem
    @State private var rename = false
    @State private var name = ""
    @State private var deletionRequest: UUID?
    @State private var history = false
    @State private var takenName: String?
    @State private var merging = false
    var body: some View {
        Menu {
            Button("Rename…", systemImage: "pencil") {
                name = journal.title
                rename = true
            }.disabled(conflicted)
            Menu {
                choice("Blank Entry", id: nil)
                ForEach(model.templates) { choice($0.displayTitle, id: $0.id) }
            } label: {
                Label("Default Template", systemImage: "doc.text")
            }.disabled(conflicted || !model.offersDefaultTemplateChoice(for: journal))
            Button("Merge Into…", systemImage: "arrow.triangle.merge") { merging = true }
                .disabled(conflicted || !model.journals.contains { $0.id != journal.id })
            Button("Version History…", systemImage: "clock.arrow.circlepath") { history = true }
            Divider()
            Button("Delete Journal…", systemImage: "trash", role: .destructive) { deletionRequest = journal.id }
        } label: {
            Label("Journal Actions", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
        .iconHelp("Journal Actions")
        .alert("Rename Journal", isPresented: $rename) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let taken = model.journalNameTaken(name, excluding: journal.id) {
                    afterAlertCloses(model) { takenName = taken }
                } else {
                    model.changeJournal(journal.id, name: name)
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .journalNameTakenAlert($takenName) { afterAlertCloses(model) { rename = true } }
        .journalDeletionPrompt($deletionRequest)
        .sheet(isPresented: $history) { JournalHistoryView(journalID: journal.id) }
        .sheet(isPresented: $merging) { MergeJournalView(sourceID: journal.id) }
        .onValueChange(of: model.locked) { locked in
            if locked {
                rename = false
                takenName = nil
                merging = false
                history = false
            }
        }
    }
    private var conflicted: Bool { model.conflicts.contains { $0.id == journal.id } }
    private func choice(_ title: String, id: UUID?) -> some View {
        Button {
            model.changeJournal(journal.id, template: id)
        } label: {
            if model.defaultTemplateID(of: journal) == id {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
