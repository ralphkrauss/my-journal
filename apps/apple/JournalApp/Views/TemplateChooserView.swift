import JournalCore
import SwiftUI

/// Where a reused chooser (the Mac's “Use a Template…” popover) creates the entry, and when it starts afresh.
@MainActor final class TemplateChooserPresentation: ObservableObject {
    /// The journal the new entry goes to, set each time the chooser opens.
    var journalID: UUID?
    /// Changes after the chooser closed, so it opens next time without the previous search or highlight.
    @Published private(set) var generation = 0
    func reset() { generation += 1 }
}

struct TemplateChooserView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var initialJournalID: UUID?
    let anchored: Bool
    /// File ▸ New Entry from Template… outside a journal: the sheet asks which journal, with two or more in use
    /// (template-journal-choice-2026-10-03.md). The "use a template" chooser never does.
    /// Decided when the sheet opens: a failed attempt that moved the destination doesn't take the picker away.
    @State private var choosesJournal: Bool
    @State private var pickedJournalID: UUID?
    /// Closes an AppKit popover, which `dismiss` doesn't reach (the Mac's “Use a Template…”).
    private let closePresentation: (() -> Void)?
    @ObservedObject private var presentation: TemplateChooserPresentation
    init(
        journalID: UUID?, anchored: Bool = false, choosesJournal: Bool = false, close: (() -> Void)? = nil,
        presentation: TemplateChooserPresentation? = nil
    ) {
        _initialJournalID = State(initialValue: journalID)
        self.anchored = anchored
        _choosesJournal = State(initialValue: choosesJournal)
        closePresentation = close
        _presentation = ObservedObject(wrappedValue: presentation ?? TemplateChooserPresentation())
    }
    private var journalID: UUID? { presentation.journalID ?? initialJournalID }
    @State private var selected: UUID?
    @State private var search = ""
    @State private var busy = false
    @State private var error: String?
    private var choices: [TemplateChoice] {
        // A template this version can only read would make an entry that can't be edited.
        let templates = model.templates.filter { $0.document.isEditable }
        var titles: [String: Int] = [:]
        for template in templates { titles[template.displayTitle, default: 0] += 1 }
        return templates.map { template in
            let duplicate = titles[template.displayTitle, default: 0] > 1
            return TemplateChoice(
                id: template.id,
                name: template.displayTitle + (duplicate ? " (\(template.id.uuidString.prefix(8)))" : ""))
        }
    }
    private var filtered: [TemplateChoice] {
        choices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        #if os(iOS)
            if anchored {
                chooser
            } else {
                // A sheet on iPhone, and on iPad in a narrow window or from the File menu: the navigation bar keeps the
                // search field clear of the sheet's grabber and top edge at every size.
                NavigationStack {
                    chooser.navigationTitle("Choose a Template").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { cancelButton } }
                }
            }
        #else
            chooser
        #endif
    }
    /// Whether the Journal row shows: chosen by the command, with two or more journals in use.
    private var showsJournalPicker: Bool { choosesJournal && model.journals.count > 1 }
    private var chooser: some View {
        VStack(spacing: 0) {
            #if os(macOS)
                if showsJournalPicker {
                    journalPicker.padding(.horizontal, 12).frame(height: 40)
                    Divider()
                }
                searchField.frame(height: 44).padding(.horizontal, 8)
                Divider()
                templateList
            #else
                pinningSearchField(to: templateList)
            #endif
            if let error { Text(error).foregroundStyle(.red).padding(12) }
            if busy { ProgressView().padding(8) }
            #if os(macOS)
                if !anchored {
                    // File ▸ New Entry from Template… opens a sheet, which needs a way out; Escape works too.
                    Divider()
                    HStack {
                        Spacer()
                        Button("Cancel", role: .cancel, action: close)
                    }.padding(12)
                }
            #endif
        }
        .disabled(busy)
        #if os(macOS)
            // Escape anywhere else in the sheet or popover, for example after tabbing to Cancel.
            .onExitCommand(perform: close)
        #endif
        .onValueChange(of: search) { _ in selected = nil }
        .onValueChange(of: presentation.generation) { _ in
            search = ""
            selected = nil
            error = nil
            busy = false
        }
        .onValueChange(of: choices) { updated in
            if let selected, !updated.contains(where: { $0.id == selected }) {
                self.selected = nil
                error = "This template is no longer available. Choose another template."
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear {
            if pickedJournalID == nil { pickedJournalID = (model.lastOpenedJournal ?? model.defaultJournal)?.id }
        }
        #if os(macOS)
            .frame(width: 320, height: anchored ? 300 : (showsJournalPicker ? 393 : 352))
        #else
            // The popover's usual height, which shrinks rather than clipping the search field when the keyboard
            // leaves less room.
            .frame(width: anchored ? 320 : nil)
            .frame(idealHeight: anchored ? 360 : nil)
        #endif
    }
    private var searchField: some View {
        TemplateSearchField(text: $search, move: moveSelection, submit: create, cancel: close)
    }
    /// Where the entry goes, before the template is chosen: like Settings ▸ Default Journal, and the Save panel's
    /// "Where:" on the Mac.
    private var journalPicker: some View {
        Picker(selection: $pickedJournalID) {
            ForEach(model.journals) { journal in
                Text(JournalNames.displayName(journal.title)).tag(Optional(journal.id))
            }
            // A journal that went away stays picked until a template is chosen, so a quick Return can't misfile.
            if let picked = pickedJournalID, !model.journals.contains(where: { $0.id == picked }) {
                Text(missingJournalName(picked)).tag(Optional(picked))
            }
        } label: {
            #if os(macOS)
                Text("Journal:").accessibilityLabel("Journal")
            #else
                Text("Journal")
            #endif
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("Template journal")
    }
    private func missingJournalName(_ id: UUID) -> String {
        model.items.first { $0.id == id }.map { JournalNames.displayName($0.title) } ?? "Untitled Journal"
    }
    #if os(iOS)
        /// The search field stays above the list as it scrolls, like a search bar in a navigation bar. Dragging the
        /// list down into the keyboard hides it, to see more templates.
        @ViewBuilder private func pinningSearchField(to results: some View) -> some View {
            let field = VStack(spacing: 4) {
                if showsJournalPicker {
                    LabeledContent {
                        journalPicker.labelsHidden()
                    } label: {
                        Text("Journal")
                    }
                    .padding(.horizontal, 12).frame(minHeight: 44)
                }
                searchField
            }.padding(.horizontal, 8)
            let list = results.scrollDismissesKeyboard(.interactively)
            if #available(iOS 26.0, *) {
                list.safeAreaBar(edge: .top) { field }
            } else {
                list.safeAreaInset(edge: .top, spacing: 0) { field.background(.bar) }
            }
        }
        @ViewBuilder private var cancelButton: some View {
            if #available(iOS 26.0, *) {
                Button(role: .cancel, action: close).disabled(busy)
            } else {
                Button("Cancel", role: .cancel, action: close).disabled(busy)
            }
        }
    #endif
    private var templateList: some View {
        ScrollViewReader { proxy in
            List {
                if filtered.isEmpty {
                    Text(choices.isEmpty ? "No Templates" : "No Results").foregroundStyle(.secondary)
                }
                ForEach(filtered) { choice in
                    Button {
                        selected = choice.id
                        create()
                    } label: {
                        // The system's selected-row colors show which template Return creates.
                        Text(choice.name)
                            .foregroundStyle(selected == choice.id ? Self.selectedText : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).id(choice.id)
                        .accessibilityAddTraits(selected == choice.id ? .isSelected : [])
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(selected == choice.id ? Self.selectedBackground : Color.clear)
                }
            }.listStyle(.plain).onValueChange(of: selected) { id in if let id { proxy.scrollTo(id) } }
                // A reused chooser opens at the top of the list.
                .id(presentation.generation)
        }
    }
    #if os(macOS)
        private static let selectedBackground = Color(nsColor: .selectedContentBackgroundColor)
        private static let selectedText = Color(nsColor: .alternateSelectedControlTextColor)
    #else
        private static let selectedBackground = Color.accentColor
        private static let selectedText = Color.white
    #endif
    /// Escape and Cancel close at once, with or without search text, unless an entry is being created.
    private func close() {
        guard !busy else { return }
        finish()
    }
    private func finish() {
        if let closePresentation {
            closePresentation()
        } else {
            // Writing-time panels close at once, without the presentation's animation.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }
    private func moveSelection(_ direction: Int) {
        guard !filtered.isEmpty else { return }
        let current = filtered.firstIndex { $0.id == selected } ?? (direction > 0 ? -1 : filtered.count)
        selected = filtered[min(filtered.count - 1, max(0, current + direction))].id
    }
    private func create() {
        guard !busy, filtered.contains(where: { $0.id == selected }) else { return }
        var chosen: JournalItem?
        if showsJournalPicker {
            guard let picked = model.journals.first(where: { $0.id == pickedJournalID }) else {
                error =
                    "“\(pickedJournalID.map(missingJournalName) ?? "Untitled Journal")” is no longer available. Choose another journal."
                pickedJournalID = model.defaultJournal?.id
                return
            }
            chosen = picked
        } else {
            guard journalID == model.newEntryJournal?.id, model.journals.contains(where: { $0.id == journalID }) else {
                error = "This journal is no longer available. Close this and choose a journal."
                return
            }
        }
        guard let template = model.templates.first(where: { $0.id == selected }) else {
            error = "This template is no longer available. Choose another template."
            return
        }
        busy = true
        Task {
            // Fills the open untouched entry only when it's in the picked journal.
            await model.newEntry(template: template, in: chosen)
            if let failure = model.error {
                busy = false
                error = failure
            } else {
                // Still busy as it closes: the search field, enabled again, brought its keyboard back, and the sheet
                // rose with it for a moment before closing.
                finish()
            }
        }
    }
}

struct TemplateChoice: Identifiable, Equatable {
    let id: UUID
    let name: String
}
