#if os(macOS)
    import JournalCore
    import SwiftUI

    /// The Mac journal window: AppKit's split view and toolbar around the SwiftUI columns.
    extension RootView {
        /// Type-erased: on macOS 26.3, resolving the full generic type of these modifiers inside RootView's body
        /// crashed in the Swift runtime (with `navigationSubtitle`).
        var macJournalWindow: AnyView {
            AnyView(macJournalColumns)
        }

        private var macJournalColumns: some View {
            MacJournalWindow(
                columns: $windowColumns,
                sidebar: AnyView(
                    JournalSidebarView(newJournal: { model.newJournalRequested = true })
                        .environmentObject(model).environmentObject(editor)),
                list: AnyView(listedSidebar.environmentObject(model).environmentObject(editor)),
                detail: AnyView(detail.environmentObject(model).environmentObject(editor)),
                toolbar: toolbarConfiguration,
                focusEditor: { editor.perform(.focus) }
            )
            // Under the titlebar, so the sidebar is full height and the toolbar's sections meet the dividers.
            .ignoresSafeArea()
            // The window's two-line title over the list, as in Notes. SwiftUI owns the window's title and subtitle
            // and would show its own, empty subtitle instead of one set on the window.
            .navigationTitle(Text(model.destination.map(collectionTitle) ?? "My Journal"))
            .navigationSubtitle(Text(collectionSubtitle))
        }

        private var toolbarConfiguration: JournalToolbarConfiguration {
            var configuration = JournalToolbarConfiguration()
            configuration.editorOnly = windowColumns.editorOnly
            configuration.canCreateJournal = model.isReady && !model.locked
            let creating = model.isReady && !model.locked && !model.replacingVault
            configuration.canCreateEntry = creating
            configuration.canEdit = model.canEdit
            configuration.entryID = model.selectedID
            configuration.sourceMode = editor.sourceMode
            configuration.previewUnavailable = model.draft?.document.requiresMarkdownSource == true
            configuration.hasEntryActions = model.draft.map { $0.kind != "journal" } ?? false
            if showsSyncStatus {
                configuration.syncStatus = .init(
                    message: syncStatusMessage, failing: syncStatusSymbol == "exclamationmark.icloud",
                    action: model.syncStatusAction.title)
            }
            configuration.searchPrompt = searchPrompt
            configuration.query = model.query
            configuration.searchRequested = editor.searchRequested
            configuration.newJournal = { model.newJournalRequested = true }
            configuration.newEntry = newEntryFromToolbar
            configuration.formatting = { close in
                AnyView(FormattingPopover(editor: editor, session: editor.formatting, close: close))
            }
            configuration.formattingWillShow = { close in
                editor.beginFormattingPresentation()
                editor.closeFormatting = close
            }
            configuration.formattingDidClose = { editor.finishPresentation(refocus: false) }
            configuration.insertImage = { editor.insertImage(from: .files) }
            configuration.toggleSourceMode = { editor.toggleSourceMode() }
            configuration.toggleEditorOnly = toggleEditorOnly
            configuration.entryActions = {
                guard let draft = model.draft, draft.kind != "journal" else { return [] }
                return entryActionCatalog(draft)
            }
            configuration.journalActions = journalActionCatalog
            configuration.syncAction = {
                model.perform(model.syncStatusAction) { model.encryption.signInRequested = true }
            }
            configuration.syncSettings = { model.openSyncSettings() }
            configuration.setQuery = { model.query = $0 }
            configuration.searchFocused = leaveEditorOnly
            configuration.searchPresented = { editor.searchRequested = false }
            return configuration
        }

        /// New Entry in the open journal; without a journal, New Journal first and then the entry.
        private func newEntryFromToolbar() {
            guard model.newEntryJournal != nil else {
                createAfterJournal = true
                model.newJournalRequested = true
                return
            }
            Task { await model.newEntry() }
        }

        /// The collection's count below its title, as in Notes. Nothing while the library is opening.
        private var collectionSubtitle: String {
            guard model.isReady, let destination = model.destination else { return "" }
            switch destination {
            case .all, .journal:
                return Self.count(
                    model.entryCount(in: destination) ?? 0, one: "entry", many: "entries", none: "No Entries")
            case .templates:
                return Self.count(model.templates.count, one: "template", many: "templates", none: "No Templates")
            case .deleted:
                let snapshot = model.lifecycle
                let items = model.items.filter { item in
                    switch item.kind {
                    case "entry": return snapshot.location(of: item) == .recentlyDeleted
                    case "template": return model.isRecentlyDeleted(item)
                    default: return false
                    }
                }.count
                return Self.count(
                    items + model.deletedJournals.count, one: "item", many: "items", none: "No Items")
            case .unavailable:
                let snapshot = model.lifecycle
                let entries = model.items.filter { item in
                    guard item.kind == "entry", case .unavailable = snapshot.location(of: item) else { return false }
                    return true
                }.count
                return Self.count(entries, one: "entry", many: "entries", none: "No Entries")
            }
        }

        private static func count(_ count: Int, one: String, many: String, none: String) -> String {
            switch count {
            case 0: return none
            case 1: return "1 " + one
            default: return count.formatted() + " " + many
            }
        }

        /// Journal Actions in the list's toolbar section: New Journal…, and for a journal the actions of its row.
        private func journalActionCatalog() -> [MenuAction] {
            var actions: [MenuAction] = [
                .command("New Journal…", symbol: "folder.badge.plus", enabled: model.isReady && !model.locked) {
                    model.newJournalRequested = true
                }
            ]
            if case .journal = model.destination, let journal = model.selectedJournal {
                actions.append(.separator("journal"))
                actions += model.journalActions(
                    journal,
                    rename: {
                        journalRenameText = journal.title
                        journalToRename = journal
                    },
                    merge: { journalToMerge = journal },
                    history: { journalHistory = journal },
                    delete: { journalDeletionRequest = journal.id })
            }
            return actions
        }

        /// The alerts and sheets of Journal Actions.
        var journalActionPresentation: JournalActionPresentation {
            JournalActionPresentation(
                renaming: $journalToRename, name: $journalRenameText, deletionRequest: $journalDeletionRequest,
                history: $journalHistory, merging: $journalToMerge)
        }
    }

    struct JournalActionPresentation: ViewModifier {
        @EnvironmentObject var model: AppModel
        @Binding var renaming: JournalItem?
        @Binding var name: String
        @Binding var deletionRequest: UUID?
        @Binding var history: JournalItem?
        @Binding var merging: JournalItem?
        @State private var takenName: String?
        @State private var retrying: JournalItem?

        func body(content: Content) -> some View {
            content
                .alert(
                    "Rename Journal", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
                ) {
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
        }
    }
#endif
