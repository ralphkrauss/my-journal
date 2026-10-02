import SwiftUI

struct RecoveryJournalView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var entryID: UUID?
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var busy = false
    @State private var created = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Journal").font(.title2.bold())
                TextField("Name", text: $name).focused($nameFocused).disabled(busy || created)
                    .onValueChange(of: name) { _ in if !busy { error = nil } }
                    .onSubmit {
                        if !busy && !created && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            create()
                        }
                    }
                if let error { Text(error).foregroundStyle(.secondary) }
                HStack {
                    Button(created ? "Done" : "Cancel", role: .cancel) { dismiss() }.disabled(busy)
                    Spacer()
                    Button("Create") { create() }.disabled(
                        created || busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24)
        }
        #if os(macOS)
            .frame(minWidth: 320, idealWidth: 420, minHeight: 200, idealHeight: 240)
        #endif
        .interactiveDismissDisabled(busy)
        .onAppear { nameFocused = true }
        .onValueChange(of: error) { text in if let text, !model.locked { JournalAccessibility.announce(text) } }
        .onValueChange(of: model.draft?.id) { id in
            if let entryID, id != entryID {
                operation?.cancel()
                dismiss()
            }
        }
        .onDisappear { operation?.cancel() }
        .onValueChange(of: model.locked) { locked in
            if locked {
                operation?.cancel()
                name = ""
                error = nil
                nameFocused = false
                dismiss()
            }
        }
    }
    private func create() {
        busy = true
        error = nil
        operation = Task {
            defer { busy = false }
            do {
                let refreshed = try await model.createRecoveryJournal(name, entryID: entryID)
                created = true
                if refreshed {
                    dismiss()
                } else {
                    error = "The journal was created, but couldn’t be displayed. Reopen My Journal to try again."
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
