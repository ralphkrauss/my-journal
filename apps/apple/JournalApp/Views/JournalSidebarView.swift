import JournalCore
import SwiftUI

enum JournalDestination: Hashable {
    case journal(UUID), all, templates, deleted, unavailable
}

struct JournalSidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var newJournal: () -> Void
    var onNavigate: ((JournalDestination) -> Void)?
    var showsToolbar = true
    /// Stacked (compact) navigation uses standard push rows instead of a persistent selection.
    var stacked = false
    @State private var renaming: JournalItem?
    @State private var name = ""
    @State private var deletionRequest: UUID?
    @State private var history: JournalItem?
    @State private var takenName: String?
    @State private var retrying: JournalItem?
    @State private var merging: JournalItem?

    var body: some View {
        List(selection: stacked ? nil : Binding(get: { model.destination }, set: { navigate($0) })) {
            destinationRow("All Entries", symbol: "tray.full", destination: .all)
            Section("Journals") {
                ForEach(model.journals.filter { !model.lists.deleting.contains($0.id) }) { journal in
                    destinationRow(
                        journal.title.isEmpty ? "Untitled Journal" : journal.title, symbol: "book.closed",
                        destination: .journal(journal.id)
                    )
                    .contextMenu {
                        #if os(macOS)
                            Button("New Journal…", action: newJournal)
                            Divider()
                        #endif
                        MenuActionsView(
                            actions: model.journalActions(
                                journal,
                                rename: {
                                    name = journal.title
                                    renaming = journal
                                },
                                merge: { merging = journal },
                                history: { history = journal },
                                delete: { deletionRequest = journal.id }))
                    }
                }
            }
            Section {
                destinationRow("Templates", symbol: "doc.on.doc", destination: .templates)
                destinationRow("Recently Deleted", symbol: "trash", destination: .deleted)
                if model.showingUnavailable || hasUnavailableEntries {
                    destinationRow("Unavailable Journals", symbol: "exclamationmark.folder", destination: .unavailable)
                }
            }
            #if os(iOS)
                if showsToolbar {
                    Section {
                        Button {
                            model.settingsPresented = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
            #endif

        }
        .alert("Rename Journal", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let journal = renaming {
                    if let taken = model.journalNameTaken(name, excluding: journal.id) {
                        afterAlertCloses(model) {
                            retrying = journal
                            takenName = taken
                        }
                    } else {
                        model.changeJournal(journal.id, name: name)
                    }
                }
                renaming = nil
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .journalNameTakenAlert($takenName) {
            let journal = retrying
            retrying = nil
            afterAlertCloses(model) { renaming = journal }
        }
        .journalDeletionPrompt($deletionRequest)
        .sheet(item: $history) { JournalHistoryView(journalID: $0.id) }
        .sheet(item: $merging) { MergeJournalView(sourceID: $0.id) }
        .onValueChange(of: model.locked) { locked in
            if locked {
                renaming = nil
                takenName = nil
                retrying = nil
                merging = nil
                history = nil
            }
        }
        .listStyle(.sidebar)
        #if os(macOS)
            // The sidebar's empty area; New Journal is also in the toolbar and the File menu.
            .contextMenu(forSelectionType: JournalDestination.self) { selection in
                if selection.isEmpty { Button("New Journal…", action: newJournal) }
            }
        #else
            .navigationTitle("Journals")
            .toolbar {
                if showsToolbar {
                    ToolbarItemGroup {
                        Button(action: newJournal) { Label("New Journal", systemImage: "folder.badge.plus") }
                        .iconHelp("New Journal")
                    }
                }
            }
        #endif
        .accessibilityLabel("Journals")
    }
    @ViewBuilder private func destinationRow(_ title: String, symbol: String, destination: JournalDestination)
        -> some View
    {
        if stacked {
            NavigationLink(value: CompactJournalRoute.collection(destination)) {
                rowLabel(title, symbol: symbol, destination: destination)
            }.accessibilityIdentifier(rowIdentifier(destination))
        } else if onNavigate != nil {
            Button {
                navigate(destination)
            } label: {
                rowLabel(title, symbol: symbol, destination: destination).contentShape(Rectangle())
            }.buttonStyle(.plain).tag(destination).accessibilityIdentifier(rowIdentifier(destination))
        } else {
            // Entry counts as in the iPhone list and the Notes sidebar; zero shows no badge.
            Label(title, systemImage: symbol).badge(count(destination) ?? 0).tag(destination)
        }
    }
    @ViewBuilder private func rowLabel(_ title: String, symbol: String, destination: JournalDestination)
        -> some View
    {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if let count = count(destination) {
                    Text(count == 1 ? "1 entry" : "\(count.formatted()) entries")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Label(title, systemImage: symbol).foregroundStyle(.primary)
                Spacer()
                if let count = count(destination) { Text(count.formatted()).foregroundStyle(.secondary) }
            }
        }
    }
    private func rowIdentifier(_ destination: JournalDestination) -> String {
        if case .journal(let id) = destination { return "Journal row " + id.uuidString }
        return String(describing: destination)
    }
    private func count(_ destination: JournalDestination) -> Int? { model.entryCount(in: destination) }
    private var hasUnavailableEntries: Bool { model.hasUnavailableEntries }
    private func navigate(_ destination: JournalDestination?) {
        guard let destination else { return }
        if let onNavigate {
            onNavigate(destination)
            return
        }
        Task { await model.show(destination) }
    }
}

extension AppModel {
    /// A journal's actions, in its sidebar row's context menu and the Mac toolbar's Journal Actions menu.
    func journalActions(
        _ journal: JournalItem, rename: @escaping @MainActor () -> Void, merge: @escaping @MainActor () -> Void,
        history: @escaping @MainActor () -> Void, delete: @escaping @MainActor () -> Void
    ) -> [MenuAction] {
        let conflicted = conflicts.contains { $0.id == journal.id }
        let current = defaultTemplateID(of: journal)
        let choices =
            [
                MenuAction.command("Blank Entry", id: "blank", checked: current == nil) {
                    self.changeJournal(journal.id, template: nil)
                }
            ]
            + templates.map { template in
                MenuAction.command(template.displayTitle, id: template.id.uuidString, checked: current == template.id) {
                    self.changeJournal(journal.id, template: template.id)
                }
            }
        return [
            .command("Rename…", symbol: "pencil", enabled: !conflicted, perform: rename),
            .submenu("Default Template", symbol: "doc.text", enabled: !conflicted, choices),
            .command(
                "Merge Into…", symbol: "arrow.triangle.merge",
                enabled: !conflicted && journals.contains { $0.id != journal.id }, perform: merge),
            .command("Version History…", symbol: "clock.arrow.circlepath", perform: history),
            .separator("delete"),
            .command("Delete Journal…", symbol: "trash", destructive: true, perform: delete),
        ]
    }
}
