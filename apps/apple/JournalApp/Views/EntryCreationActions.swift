#if os(iOS)
    import JournalCore
    import SwiftUI

    /// New Entry in the iPhone and iPad bars. The Mac's toolbar has its own (JournalToolbarController). Templates are
    /// offered inside the new entry (TemplateSuggestionView).
    struct EntryCreationActions: View {
        @EnvironmentObject private var model: AppModel
        let global: Bool
        let newJournal: () -> Void
        @State private var busy = false
        @State private var operation: Task<Void, Never>?

        var body: some View {
            Button {
                if global {
                    // Outside any collection, open the default journal so Back shows where the entry was filed.
                    if let id = model.defaultJournal?.id { activate(id) } else { newJournal() }
                } else if model.newEntryJournal != nil {
                    start()
                } else {
                    newJournal()
                }
            } label: {
                Label("New Entry", systemImage: "square.and.pencil")
            }
            .iconHelp("New Entry")
            .disabled(busy || !model.isReady || model.locked || model.replacingVault)
            .onDisappear { operation?.cancel() }
        }
        private func start() {
            guard !busy else { return }
            busy = true
            operation = Task { @MainActor in
                defer { busy = false }
                await model.newEntry()
            }
        }
        private func activate(_ id: UUID) {
            guard !busy else { return }
            busy = true
            operation = Task { @MainActor in
                defer { busy = false }
                guard model.journals.contains(where: { $0.id == id }) else { return }
                if model.destination != .journal(id) { await model.switchJournal(id) }
                guard !Task.isCancelled, model.destination == .journal(id), !model.saveFailure else { return }
                await model.newEntry()
            }
        }
    }
#endif
