import JournalCore
import SwiftUI

/// Merge Into…: moves every entry of a journal into another one, then moves the journal to Recently Deleted
/// (docs/design/journal-name-uniqueness.md §5).
struct MergeJournalView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let sourceID: UUID
    @State private var selection: UUID?
    @State private var busy = false
    @State private var error: String?
    @State private var sourceGone = false
    @State private var conflictToReview: UUID?
    @State private var reviewing = false
    @State private var agents: AgentReaders = .none
    @State private var operation: Task<Void, Never>?

    /// Which agents read the journals, as far as this device can tell.
    enum AgentReaders: Equatable {
        /// No server, a server without agent access, or no agents.
        case none
        /// Agents couldn't be checked, or one's settings can't be read.
        case unknown
        case known([LibraryAgent])
    }

    private var source: JournalItem? { model.items.first { $0.id == sourceID } }
    private var sourceName: String { JournalNames.displayName(source?.title ?? "") }
    private var destinations: [JournalItem] { model.journals.filter { $0.id != sourceID } }
    private var destination: JournalItem? { selection.flatMap { id in destinations.first { $0.id == id } } }
    private var entryCount: Int { model.items.filter { $0.kind == "entry" && $0.journalID == sourceID }.count }
    private var canMerge: Bool { !busy && !sourceGone && destination != nil }

    var body: some View {
        layout.interactiveDismissDisabled(busy).keepsUnlockedWhile(busy)
            .sheet(isPresented: $reviewing) {
                if let id = conflictToReview, let conflict = model.conflicts.first(where: { $0.id == id }) {
                    if conflict.local.kind == "journal" {
                        JournalConflictView(conflict: conflict)
                    } else {
                        ConflictReview(id: id)
                    }
                } else {
                    Text("These changes have been resolved.").padding()
                }
            }
            .task { await loadAgents() }
            .onDisappear { operation?.cancel() }
            .onValueChange(of: model.locked) { locked in
                if locked {
                    reviewing = false
                    dismiss()
                }
            }
            .onValueChange(of: source.map(JournalNames.isListed) == true) { listed in
                if !listed, !busy {
                    sourceGone = true
                    showError("“\(sourceName)” is no longer available.")
                }
            }
            .onValueChange(of: destinations.map(\.id)) { ids in
                if let selection, !ids.contains(selection) {
                    self.selection = nil
                    if !busy { showError("That journal is no longer available. Choose another journal.") }
                }
            }
    }

    private var title: String { "Merge “\(sourceName)”" }

    @ViewBuilder private var layout: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                Text(title).font(.headline).padding(.top, 16).padding(.horizontal)
                    .accessibilityAddTraits(.isHeader)
                content
                Divider()
                HStack {
                    Button(sourceGone ? "Done" : "Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction).disabled(busy)
                    Spacer()
                    if !sourceGone {
                        Button("Merge") { merge() }.keyboardShortcut(.defaultAction).disabled(!canMerge)
                            .accessibilityHint("Moves every entry, then moves this journal to Recently Deleted.")
                    }
                }.padding()
            }
            .frame(minWidth: 320, idealWidth: 420, minHeight: 280, idealHeight: 360)
        #else
            NavigationStack {
                content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(sourceGone ? "Done" : "Cancel") { dismiss() }.disabled(busy)
                        }
                        if !sourceGone {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Merge") { merge() }.disabled(!canMerge)
                            }
                        }
                    }
            }
        #endif
    }

    private var content: some View {
        List {
            Section {
                ForEach(destinations) { journal in
                    Button {
                        selection = journal.id
                        error = nil
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(JournalNames.displayName(journal.title))
                                    .fixedSize(horizontal: false, vertical: true)
                                if sharesName(journal) {
                                    Text("Created \(journal.date.formatted(date: .abbreviated, time: .omitted))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if selection == journal.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                            }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || sourceGone)
                    .accessibilityAddTraits(selection == journal.id ? .isSelected : [])
                }
            } header: {
                Text("Choose the journal to merge “\(sourceName)” into.").textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(footer)
                    if let agentSentence { Text(agentSentence) }
                    if let error {
                        Text(error).foregroundStyle(.red).accessibilityIdentifier("Merge error")
                    }
                    if conflictToReview != nil {
                        Button("Review Changes") { reviewing = true }.disabled(busy)
                    }
                    if busy { ProgressView("Merging…") }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        #if os(macOS)
            .listStyle(.inset)
        #endif
    }

    private var footer: String {
        let target = destination.map { "“\(JournalNames.displayName($0.title))”" } ?? "the journal you choose"
        switch entryCount {
        case 0: return "“\(sourceName)” has no entries. It moves to Recently Deleted."
        case 1:
            return "The entry in “\(sourceName)” moves to \(target). “\(sourceName)” then moves to Recently Deleted."
        default:
            return
                "The \(entryCount) entries in “\(sourceName)”, including archived and recently deleted ones, move to \(target). “\(sourceName)” then moves to Recently Deleted."
        }
    }

    /// What merging changes for agents (§5.2). Agents with All Journals read both journals either way.
    private var agentSentence: String? {
        guard let destination, entryCount > 0 else { return nil }
        let name = "“\(JournalNames.displayName(destination.title))”"
        switch agents {
        case .none: return nil
        case .unknown: return "If an agent can read \(name), it will be able to read these entries."
        case .known(let list):
            let selected = list.compactMap(\.settings).filter { !$0.allJournals }
            let gaining = selected.filter {
                $0.journalIDs.contains(destination.id) && !$0.journalIDs.contains(sourceID)
            }
            let losing = selected.filter { $0.journalIDs.contains(sourceID) && !$0.journalIDs.contains(destination.id) }
            var sentences: [String] = []
            if let only = gaining.first, gaining.count == 1 {
                sentences.append("\(only.name) can read \(name), so it will be able to read these entries.")
            } else if gaining.count > 1 {
                sentences.append("\(gaining.count) agents can read \(name), so they’ll be able to read these entries.")
            }
            if let only = losing.first, losing.count == 1 {
                sentences.append("\(only.name) will no longer be able to read these entries.")
            } else if losing.count > 1 {
                sentences.append("\(losing.count) agents will no longer be able to read these entries.")
            }
            return sentences.isEmpty ? nil : sentences.joined(separator: " ")
        }
    }

    /// Only journals with the same name as another destination show when they were created.
    private func sharesName(_ journal: JournalItem) -> Bool {
        destinations.contains { $0.id != journal.id && JournalNames.key($0.title) == JournalNames.key(journal.title) }
    }

    private func loadAgents() async {
        guard model.connection != nil, let publisher = model.agentCopies else { return }
        do {
            let list = try await publisher.list().filter { !$0.hasExpired() }
            guard !Task.isCancelled else { return }
            agents = list.isEmpty ? .none : list.contains { $0.settings == nil } ? .unknown : .known(list)
        } catch AgentCopyError.serverOutdated {
            agents = .none
        } catch {
            agents = .unknown
        }
    }

    private func merge() {
        guard canMerge, let selection else { return }
        busy = true
        error = nil
        conflictToReview = nil
        let name = destination.map { JournalNames.displayName($0.title) } ?? ""
        operation = Task {
            defer { busy = false }
            do {
                let refreshed = try await model.mergeJournal(sourceID, into: selection)
                guard !model.locked, !Task.isCancelled else { return }
                guard refreshed else {
                    showError("The journals were merged, but couldn’t be displayed. Reopen My Journal to try again.")
                    sourceGone = true
                    return
                }
                JournalAccessibility.announce("Merged into “\(name)”.")
                dismiss()
            } catch JournalMergeError.conflict(let id) {
                guard !model.locked else { return }
                conflictToReview = id
                showError(JournalMergeError.conflict(id).localizedDescription)
            } catch JournalMergeError.sourceUnavailable {
                guard !model.locked else { return }
                sourceGone = true
                showError("“\(sourceName)” is no longer available.")
            } catch JournalMergeError.destinationUnavailable {
                guard !model.locked else { return }
                self.selection = nil
                showError("“\(name)” is no longer available. Choose another journal.")
            } catch is CancellationError {} catch {
                guard !model.locked else { return }
                showError(error.shown(.saving))
            }
        }
    }
    private func showError(_ text: String) {
        error = text
        JournalAccessibility.announce(text)
    }
}
