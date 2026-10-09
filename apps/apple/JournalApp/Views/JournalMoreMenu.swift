import JournalCore
import SwiftUI

struct JournalMoreMenu: View {
    @EnvironmentObject private var model: AppModel
    let journal: JournalItem
    @State private var rename = false
    @State private var name = ""
    @State private var deletionRequest: UUID?
    @State private var takenName: String?
    var body: some View {
        Menu {
            Button("Rename…", systemImage: "pencil") {
                name = journal.title
                rename = true
            }
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
        .onValueChange(of: model.locked) { locked in
            if locked {
                rename = false
                takenName = nil
            }
        }
    }
}
