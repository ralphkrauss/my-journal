import JournalCore
import SwiftUI

enum JournalDestination: Hashable {
    case journal(UUID), all, templates, deleted, unavailable

    var isJournal: Bool {
        if case .journal = self { return true }
        return false
    }
}

struct JournalSidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.undoManager) private var undoManager
    var newJournal: () -> Void
    var onNavigate: ((JournalDestination) -> Void)?
    var showsToolbar = true
    /// Stacked (compact) navigation uses standard push rows instead of a persistent selection.
    var stacked = false
    @State private var renaming: JournalItem?
    @State private var name = ""
    @State private var deletionRequest: UUID?
    @State private var takenName: String?
    @State private var retrying: JournalItem?

    /// Edit mode on iPhone and iPad (journal-order.md); the Mac has none, journals are dragged there.
    private var editing: Bool {
        #if os(iOS)
            model.editingJournals
        #else
            false
        #endif
    }
    private var listedJournals: [JournalItem] { model.journals.filter { !model.lists.deleting.contains($0.id) } }

    var body: some View {
        // While editing, the selection stays where it is, and rows can't be chosen.
        List(selection: stacked ? nil : Binding(get: { model.destination }, set: { if !editing { navigate($0) } })) {
            destinationRow("All Entries", symbol: "tray.full", destination: .all)
            Section("Journals") {
                let journals = listedJournals
                ForEach(journals) { journal in
                    journalRow(journal, in: journals)
                }
                // Drag to reorder: with a handle in edit mode, by holding and moving a row otherwise, and on the Mac
                // by dragging a row.
                .onMove(perform: model.canMoveJournals ? { move($0, to: $1, in: journals) } : nil)
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
                        if editing {
                            // A fixed row, dimmed like the others while journals are edited (journal-order.md).
                            Label("Settings", systemImage: "gearshape").foregroundStyle(.secondary).disabled(true)
                        } else {
                            Button {
                                model.settingsPresented = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
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
        #if os(iOS)
            // Only while editing: outside edit mode the list keeps its own, as rows are lifted by holding them.
            .environment(\.editMode, editing ? .constant(.active) : nil)
            // Edit mode ends with the last journal; the model ends it when the journals lock or the library is
            // replaced, but not while a change such as deleting a journal is committed.
            .onValueChange(of: model.journals.isEmpty) { empty in if empty { model.editingJournals = false } }
        #endif
        .onValueChange(of: model.locked) { locked in
            if locked {
                #if os(iOS)
                    model.editingJournals = false
                #endif
                renaming = nil
                takenName = nil
                retrying = nil
            }
        }
        .listStyle(.sidebar)
        #if os(macOS)
            .modifier(SidebarTopEdgeEffectHidden())
            // The sidebar's empty area; New Journal is also in the toolbar and the File menu.
            .contextMenu(forSelectionType: JournalDestination.self) { selection in
                if selection.isEmpty {
                    Button("New Journal…", action: newJournal).disabled(model.writingPausedForEncryption)
                }
            }
        #else
            .navigationTitle("Journals")
            // A large title, as on the iPhone: the sidebar's bar holds New Journal, Edit and the sidebar button.
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if showsToolbar {
                    ToolbarItem {
                        Button(action: newJournal) { Label("New Journal", systemImage: "folder.badge.plus") }
                        .iconHelp("New Journal").disabled(model.writingPausedForEncryption)
                    }
                    JournalEditToolbarItems()
                }
            }
        #endif
        .accessibilityLabel("Journals")
    }
    /// A journal's row: its destination with the journal's context menu, or in edit mode its name, Journal Actions (⋯)
    /// and the system's reorder handle. On iPhone and iPad, VoiceOver also offers Move Up and Move Down.
    @ViewBuilder private func journalRow(_ journal: JournalItem, in journals: [JournalItem]) -> some View {
        let title = JournalNames.displayName(journal.title)
        Group {
            if editing {
                HStack(spacing: stacked ? 12 : 6) {
                    // In the iPad's narrow sidebar the name has the icon's room.
                    editingLabel(title, symbol: stacked ? "book.closed" : nil, destination: .journal(journal.id))
                        .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                    journalActionsControls(journal)
                }
                // The sidebar's selection stays on the collection shown (journal-order.md).
                .tag(JournalDestination.journal(journal.id))
            } else {
                destinationRow(title, symbol: "book.closed", destination: .journal(journal.id))
                    .contextMenu {
                        #if os(macOS)
                            Button("New Journal…", action: newJournal).disabled(model.writingPausedForEncryption)
                            Divider()
                        #endif
                        MenuActionsView(actions: actions(for: journal))
                    }
            }
        }
        #if os(iOS)
            .accessibilityActions {
                if model.canMoveJournals, let index = journals.firstIndex(where: { $0.id == journal.id }) {
                    if index > 0 { Button("Move Up") { move(journal.id, by: -1, in: journals) } }
                    if index + 1 < journals.count { Button("Move Down") { move(journal.id, by: 1, in: journals) } }
                }
            }
        #endif
    }
    /// What replaces a journal row's count and chevron in edit mode: Journal Actions (⋯) and a thin separator before
    /// the system's reorder handle. ⋯ keeps a 44-point-tall target that overhangs the row's own top and bottom margins,
    /// so the row keeps the height it has outside edit mode (journal-order.md).
    private func journalActionsControls(_ journal: JournalItem) -> some View {
        let target: CGFloat = 44
        return HStack(spacing: stacked ? 12 : 6) {
            Menu {
                MenuActionsView(actions: actions(for: journal))
            } label: {
                Image(systemName: "ellipsis.circle").imageScale(.large).foregroundStyle(.tint)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(width: stacked ? target : 32, height: target)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless).fixedSize().accessibilityLabel("Journal Actions")
            .accessibilityIdentifier("Journal Actions " + journal.id.uuidString)
            Divider().frame(width: 1, height: 24).accessibilityHidden(true)
        }
        .frame(height: target)
        .padding(.vertical, -target / 2)
    }
    /// A row's leading part in edit mode: what it shows outside edit mode without the count and chevron at its trailing
    /// end. At accessibility sizes the count is under the name, so it stays and the row keeps its height.
    @ViewBuilder private func editingLabel(
        _ title: String, symbol: String?, destination: JournalDestination, dimmed: Bool = false
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            rowLabel(title, symbol: symbol ?? "", destination: destination, dimmed: dimmed)
        } else if let symbol {
            Label(title, systemImage: symbol)
        } else {
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func actions(for journal: JournalItem) -> [MenuAction] {
        model.journalActions(
            journal,
            rename: {
                name = journal.title
                renaming = journal
            },
            delete: { deletionRequest = journal.id })
    }
    /// A drop at `destination` of the list shown (offsets as `onMove` gives them), as a position among all journals.
    private func move(_ source: IndexSet, to destination: Int, in shown: [JournalItem]) {
        guard let from = source.first, shown.indices.contains(from) else { return }
        let id = shown[from].id
        let others = shown.map(\.id).filter { $0 != id }
        let target = destination > from ? destination - 1 : destination
        place(id, before: others.indices.contains(target) ? others[target] : nil)
    }
    private func move(_ id: UUID, by step: Int, in shown: [JournalItem]) {
        guard let index = shown.firstIndex(where: { $0.id == id }) else { return }
        let others = shown.map(\.id).filter { $0 != id }
        let target = index + step
        guard (0...others.count).contains(target) else { return }
        place(id, before: others.indices.contains(target) ? others[target] : nil)
    }
    /// Moves `id` before the journal `next` (at the end without one) in the whole list, which also has journals being
    /// deleted that the sidebar no longer shows.
    private func place(_ id: UUID, before next: UUID?) {
        let all = model.journals.map(\.id).filter { $0 != id }
        let index = next.flatMap { all.firstIndex(of: $0) } ?? all.count
        Task { await model.moveJournal(id, to: index, undoManager: undoManager) }
    }
    @ViewBuilder private func destinationRow(_ title: String, symbol: String, destination: JournalDestination)
        -> some View
    {
        if editing {
            // Rows that can't be edited are dimmed: no count at the trailing end, no chevron, nothing to choose.
            editingLabel(title, symbol: symbol, destination: destination, dimmed: true).foregroundStyle(.secondary)
                .disabled(true)
                .accessibilityIdentifier(rowIdentifier(destination)).tag(destination)
        } else if stacked {
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
    @ViewBuilder private func rowLabel(
        _ title: String, symbol: String, destination: JournalDestination, dimmed: Bool = false
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(dimmed ? .secondary : .primary).fixedSize(horizontal: false, vertical: true)
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
        _ journal: JournalItem, rename: @escaping @MainActor () -> Void, delete: @escaping @MainActor () -> Void
    ) -> [MenuAction] {
        [
            .command("Rename…", symbol: "pencil", enabled: !writingPausedForEncryption, perform: rename),
            .separator("delete"),
            .command(
                "Delete Journal…", symbol: "trash", enabled: !writingPausedForEncryption, destructive: true,
                perform: delete),
        ]
    }
}

#if os(macOS)
    /// Without the top edge effect, New Journal and Toggle Sidebar follow the window's appearance, as over an AppKit
    /// sidebar. With it, macOS 26 samples the rows beneath and, after a switch to dark, keeps a stale light sample until
    /// the sidebar scrolls: black icons on a dark sidebar (docs/design/mac-window-appkit.md §8). Earlier systems have
    /// no edge effect.
    private struct SidebarTopEdgeEffectHidden: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 26, *) {
                content.scrollEdgeEffectHidden(true, for: .top)
            } else {
                content
            }
        }
    }
#endif
