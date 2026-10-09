import JournalCore
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var editor: EditorActions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.undoManager) private var undoManager
    @State var navigationPath: [CompactJournalRoute] = []
    @State var navigationTask: Task<Void, Never>?
    @State var journalsQuery = ""
    @State var navigationWidth: CGFloat = 0
    #if os(macOS)
        /// Each window's columns, including View ▸ Show Editor Only.
        @SceneStorage("windowColumns") var windowColumns = WindowColumns()
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        /// Journal Actions in the toolbar, which work as the journal row's context menu does.
        @State var journalToRename: JournalItem?
        @State var journalRenameText = ""
        @State var journalDeletionRequest: UUID?
    #else
        @State var columnVisibility = NavigationSplitViewVisibility.all
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #endif
    @State var newJournal = false
    @State var createAfterJournal = false
    @State private var journalName = ""
    @State private var journalNameTaken: String?
    @State private var templateName = ""
    @State private var saveTemplate = false
    @State private var importImage = false
    @State private var imageInsertion: ImageInsertionSession?
    @State private var imageImportTask: Task<Void, Never>?
    @State private var creatingLibrary = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var connect = false
    @State private var history: JournalItem?
    @State private var imageDescriptionsEntry: JournalItem?
    @State private var entryToMove: JournalItem?
    @State private var entryToDate: JournalItem?
    @State private var permanentDeletionRequest: PermanentDeletionRequest?
    /// Delete All in Recently Deleted: its toolbar button and, on the Mac, File ▸ Delete All in Recently Deleted….
    @State var deleteAllRequested = false
    /// A row in Recently Deleted that came back after its deletion was cancelled, for VoiceOver to return to.
    @AccessibilityFocusState private var returnedRow: UUID?
    @State private var rowActionTask: Task<Void, Never>?
    /// Deletions are stored one after another, each without cancelling the last.
    @State private var deletionTask: Task<Void, Never>?
    @State private var archiveToImport: URL?
    /// An archive opened before the journals could be shown: while the library opened, as when opening the archive
    /// launched the app, or while it was locked. It opens once they are shown; a cancelled or failed unlock keeps it
    /// waiting for the next one, until the person leaves the app.
    @State private var pendingArchive: URL?
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @State var searchPresented = false
        @State var journalsSearchPresented = false
    #endif
    @ScaledMetric(relativeTo: .body) private var preferredTextSize = 17.0

    var usesStackedNavigation: Bool {
        #if os(macOS)
            false
        #else
            horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
        #endif
    }

    /// The deletion prompts stay across locking, so a row a swipe took out of the list comes back when locking closes
    /// the alert.
    var body: some View {
        deletionPrompts(window)
    }

    private var window: some View {
        Group {
            if !model.loaded {
                ProgressView("Opening Journal…")
            } else if model.locked {
                UnlockView()
            } else if model.showsLibraryProblem, let problem = model.shownLibraryProblem {
                LibraryProblemView(problem: problem)
            } else if model.store == nil {
                welcome
            } else if let key = model.recoveryKey {
                RecoveryView(key: key)
            } else {
                mainNavigation
            }
        }
        .alert(
            "My Journal",
            isPresented: Binding(
                get: { model.alertText != nil && !model.locked && !creatingLibrary },
                set: { if !$0 { model.dismissAlert() } })
        ) {
            if model.saveFailure {
                Button("Try Again") { Task { _ = await model.flush(announcing: .always) } }
            }
            Button("OK", role: .cancel) { model.dismissAlert() }
        } message: {
            Text(model.alertText ?? "")
        }
        .alert("New Journal", isPresented: $newJournal) {
            TextField("Name", text: $journalName)
            Button("Cancel", role: .cancel) {
                createAfterJournal = false
                journalName = ""
            }
            Button("Create") {
                if let taken = model.journalNameTaken(journalName) {
                    afterAlertCloses(model) { journalNameTaken = taken }
                    return
                }
                Task {
                    await model.createJournal(journalName)
                    if createAfterJournal, model.error == nil { await model.newEntry() }
                    createAfterJournal = false
                    journalName = ""
                }
            }.disabled(journalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .journalNameTakenAlert($journalNameTaken) { afterAlertCloses(model) { newJournal = true } }
        .alert("Save as Template", isPresented: $saveTemplate) {
            TextField("Name", text: $templateName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await model.saveTemplate(name: templateName) } }
                .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onValueChange(of: model.newJournalRequested) { _ in presentRequestedNewJournal() }
        // The menu may have asked while no window was open; this window answers it when it appears.
        .onAppear(perform: presentRequestedNewJournal)
        .onAppear { model.windowUndoManager = undoManager }
        .fileImporter(isPresented: $model.archiveImportRequested, allowedContentTypes: [.journalArchive]) { result in
            // A choice made as the app locked, or while the journals are being replaced, isn't imported.
            guard !model.lockBlocksImport, !model.replacingVault, case .success(let url) = result else { return }
            archiveToImport = url
        }
        .sheet(isPresented: $model.archiveExportPresented) { ArchiveExportSheet() }
        .sheet(isPresented: $model.markdownExportPresented) { MarkdownExportSheet() }
        .onValueChange(of: editor.requestImage) { requested in
            guard requested else { return }
            editor.requestImage = false
            cancelImageImport()
            imageInsertion = ImageInsertionSession(model: model, actions: editor)
            importImage = imageInsertion != nil
        }
        #if os(iOS)
            .background(MobileFormattingPresenter(editor: editor))
        #endif
        .sheet(isPresented: $editor.requestLink) { LinkEditorView().environmentObject(editor) }
        .sheet(isPresented: $creatingLibrary) { CreateJournalView() }
        .sheet(isPresented: $model.templateChooserPresented) {
            // File ▸ Use a Template…: the same chooser as the link in the empty entry, for the entry open now.
            TemplateChooserView(entryID: model.draft?.id)
        }
        .background {
            if let session = imageInsertion {
                ImagePickerPresenter(
                    session: session, source: editor.imageSource, isPresented: $importImage, receive: importImageResult
                )
                .id(ObjectIdentifier(session))
            }
        }
        .onValueChange(of: model.locked) { locked in
            // The open panel would otherwise stay over the lock screen.
            if locked { closePresentations() }
        }
        // As the app locks: a sheet over the journals would stay over the screen that says they can't be opened.
        .onValueChange(of: model.showsLibraryProblem) { if $0 { closePresentations() } }
        // Erasing this device's journals closes what every window shows of them (erase-device-2026-10-04.md).
        .onValueChange(of: model.erasingLibrary) { erasing in
            if erasing { closePresentations() }
        }
        #if os(iOS)
            .onValueChange(of: editor.searchRequested) { requested in
                guard requested else { return }
                editor.searchRequested = false
                presentSearch()
            }
            // A layout change to stacked navigation shows the model's collection and entry, not stale routes.
            .onValueChange(of: usesStackedNavigation) { _ in rebuildNavigationPath() }
            .onValueChange(of: model.destination) { followModelDestination(to: $0) }
        #endif
        .onValueChange(of: model.selectedID) { _ in
            #if os(iOS)
                editor.entryVisitEnded()
            #endif
            cancelImageImport(leaving: true)
            editor.sourceMode = model.draft?.document.requiresMarkdownSource ?? false
            if model.titleFocus != nil || !usesStackedNavigation, let id = model.selectedID,
                let destination = model.destination
            {
                navigationPath = [.collection(destination), .entry(id)]
            } else if usesStackedNavigation, case .entry(let open) = navigationPath.last, open != model.selectedID {
                // The open entry was deleted, moved or removed by a sync: go back to the list, not an empty page.
                // Another entry chosen in its place (a restored copy, an undone deletion) is shown instead.
                navigationPath.removeLast()
                if let id = model.selectedID { navigationPath.append(.entry(id)) }
            }
            editor.requestLink = false
            editor.endFormatting()
        }
        .onOpenURL { url in
            guard url.isFileURL, url.pathExtension.lowercased() == "journalarchive" else { return }
            pendingArchive = url
            openPendingArchive()
        }
        .onValueChange(of: model.loaded) { _ in openPendingArchive() }
        .onValueChange(of: model.locked) { _ in openPendingArchive() }
        .onValueChange(of: model.libraryProblem) { _ in openPendingArchive() }
        .onValueChange(of: model.committingMutation) { _ in openPendingArchive() }
        // Someone who gave up unlocking isn't shown the archive hours later.
        .onValueChange(of: scenePhase) { if $0 == .background { pendingArchive = nil } }
        .sheet(isPresented: Binding(get: { archiveToImport != nil }, set: { if !$0 { archiveToImport = nil } })) {
            if let archiveToImport { ArchiveImportView(source: archiveToImport) }
        }
        .sheet(item: $imageDescriptionsEntry) { ImageDescriptionsView(entry: $0) }
        .sheet(item: $entryToDate) { EntryDateView(entry: $0) }
        .onDisappear {
            rowActionTask?.cancel()
            navigationTask?.cancel()
            cancelImageImport()
        }
        .sheet(item: $entryToMove) { entry in MoveEntryView(entryID: entry.id) }
        .sheet(item: $history) { VersionHistoryView(sourceID: $0.id, sourceKind: $0.kind) }
        .sheet(isPresented: $connect) { ConnectionView() }
        #if os(macOS)
            .background(SettingsPresenter(requested: $model.settingsPresented))
            .modifier(journalActionPresentation)
        #else
            .sheet(isPresented: $model.settingsPresented) { SettingsView() }
        #endif
    }
    /// Closes every sheet, panel and prompt the window shows, when the app locks or its journals are erased.
    private func closePresentations() {
        model.archiveImportRequested = false
        archiveToImport = nil
        history = nil
        entryToMove = nil
        entryToDate = nil
        rowActionTask?.cancel()
        imageDescriptionsEntry = nil
        connect = false
        model.settingsPresented = false
        model.templateChooserPresented = false
        newJournal = false
        journalNameTaken = nil

        saveTemplate = false
        cancelImageImport()
        editor.requestLink = false
        editor.endFormatting()
    }
    /// Delete Permanently for one item, and Delete All in Recently Deleted.
    private func deletionPrompts(_ content: some View) -> some View {
        content
            .permanentDeletionPrompt(
                $permanentDeletionRequest, leave: leaveDeletedEntry, returned: { id in Task { returnedRow = id } }
            )
            .deleteAllPrompt($deleteAllRequested)
    }
    /// Opens a waiting archive once the journals are shown, as after unlocking, and after a change being stored. While
    /// connecting or turning on encryption replaces the journals, it can't be imported, and the person is told so.
    private func openPendingArchive() {
        guard let url = pendingArchive, model.loaded, !model.committingMutation, !model.retryingOpen else { return }
        // Journals a newer version wrote, and settings that couldn't be read, are never imported over. Locked: it
        // waits for the unlock (the lock screen of a missing device key offers the import itself).
        guard model.refusesImport || !model.lockBlocksImport else { return }
        pendingArchive = nil
        guard !model.refusesImport else { return }
        guard !model.replacingVault else {
            model.error = "My Journal is updating your journals. Try again when it’s finished."
            return
        }
        archiveToImport = url
    }
    @ViewBuilder private var mainNavigation: some View {
        #if os(macOS)
            editorOnlyBehavior(macJournalWindow)
                .focusedSceneValue(\.deleteAll, DeleteAllCommand { deleteAllRequested = true })
        #else
            if usesStackedNavigation {
                compactNavigation
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    JournalSidebarView(newJournal: { newJournal = true }, onNavigate: openRegularCollection)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                } content: {
                    listedSidebar.navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
                        .toolbar { listToolbar }
                } detail: {
                    detail.toolbar { if model.draft != nil { mainToolbar } }
                }.navigationSplitViewStyle(.balanced)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.onAppear { navigationWidth = geometry.size.width }
                                .onValueChange(of: geometry.size.width) { navigationWidth = $0 }
                        }
                    }
            }
        #endif
    }
    private var welcome: some View {
        // Scrolls at the largest text sizes, as the lock screen does.
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "book.closed").font(.system(size: 48, weight: .light)).foregroundStyle(
                        .secondary
                    )
                    .accessibilityHidden(true)
                    Text("My Journal").font(.largeTitle.bold())
                    Text("Write on this device. You can set up sync later.").foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Start a Journal") { creatingLibrary = true }.buttonStyle(.borderedProminent).controlSize(
                        .large)
                    Button("Connect to a Server…") { connect = true }.buttonStyle(.plain).foregroundStyle(.tint)
                    // The window already has a file importer, and iOS presents only one per view hierarchy.
                    Button("Import Archive…") { model.archiveImportRequested = true }
                }.padding(40).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }
        }
    }
    var sidebar: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(selection: listSelection) {
                    if model.showingTrash {
                        if !model.filteredDeletedJournals.isEmpty {
                            Section {
                                ForEach(model.filteredDeletedJournals) { journal in
                                    entryLink(journal.id) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(journal.title.isEmpty ? "Untitled Journal" : journal.title)
                                            Text(
                                                model.restorableEntryCount(journal.id) == 1
                                                    ? "1 entry on this device"
                                                    : "\(model.restorableEntryCount(journal.id)) entries on this device"
                                            )
                                            .font(.callout).foregroundStyle(.secondary)
                                        }.accessibilityElement(children: .combine)
                                            .accessibilityValue("Journal")
                                    }
                                    .entriesRowSeparator(
                                        lastInSection: journal.id == model.filteredDeletedJournals.last?.id)
                                }
                            } header: {
                                Text("Journals").entriesHeaderSeparatorHidden()
                            } footer: {
                                if model.filteredDeletedTemplates.isEmpty && groupedEntries.isEmpty { trashFooter }
                            }
                        }
                        if !model.filteredDeletedTemplates.isEmpty {
                            Section {
                                ForEach(model.filteredDeletedTemplates) { template in
                                    entryRow(template, value: "Template")
                                        .entriesRowSeparator(
                                            lastInSection: template.id == model.filteredDeletedTemplates.last?.id)
                                }
                            } header: {
                                Text("Templates").entriesHeaderSeparatorHidden()
                            } footer: {
                                if groupedEntries.isEmpty { trashFooter }
                            }
                        }
                        ForEach(groupedEntries, id: \.0) { month, entries in
                            Section {
                                monthRows(entries)
                            } header: {
                                VStack(alignment: .leading, spacing: 8) {
                                    if month == groupedEntries.first?.0 { Text("Entries") }
                                    Text(month)
                                }
                                .entriesHeaderSeparatorHidden()
                            } footer: {
                                if month == groupedEntries.last?.0 { trashFooter }
                            }
                        }
                    } else {
                        // The Pinned section comes first, styled like the months (pinned-entries.md).
                        ForEach(groupedEntries, id: \.0) { month, entries in
                            Section {
                                monthRows(entries)
                            } header: {
                                Text(month).entriesHeaderSeparatorHidden()
                            }
                        }
                    }
                }
                #if os(macOS)
                    .listStyle(.inset)
                #else
                    .listStyle(.insetGrouped)
                #endif
                // The open entry stays in view when it moves into or out of Pinned.
                .onValueChange(of: model.selectedID.map(model.library.pinned.contains)) { _ in
                    guard let id = model.selectedID else { return }
                    withAnimation(AppModel.listAnimation) { proxy.scrollTo(id) }
                }
            }
            #if os(macOS)
                // Delete and ⌘⌫ act only while the list has focus, never while typing in the editor.
                .onDeleteCommand(perform: deleteSelectedFromList)
                .modifier(CommandDeleteKey(action: deleteSelectedFromList))
                .recentlyDeletedHeader(shown: model.showingTrash) { deleteAllRequested = true }
            #endif
            .overlay { if listIsEmpty { emptyListState } }
            #if os(iOS)
                .modifier(EntrySearch(text: $model.query, isPresented: $searchPresented, prompt: searchPrompt))
            #endif
        }
        .navigationTitle(model.destination.map(collectionTitle) ?? "Journal")
    }
    private var listSelection: Binding<UUID?>? {
        guard !usesStackedNavigation else { return nil }
        return Binding(
            // A deleted row leaves the list and the selection in the same update.
            get: { model.selectedID.flatMap { model.lists.deleting.contains($0) ? nil : $0 } },
            set: { id in Task { await model.select(id) } })
    }
    /// What an empty list shows, and the editor when the list is hidden.
    var emptyListState: some View {
        VStack(spacing: 10) {
            if model.query.isEmpty && model.showingTemplates {
                noTemplates
            } else {
                Text(
                    model.query.isEmpty
                        ? (model.showingTrash
                            ? "No Deleted Items"
                            : model.showingUnavailable ? "No Unavailable Entries" : "No Entries") : "No Results"
                ).foregroundStyle(.secondary)
            }
            if model.query.isEmpty && !model.showingTrash && !model.showingTemplates && !model.showingUnavailable {
                if model.journals.isEmpty {
                    Button("New Journal…") {
                        journalName = ""
                        newJournal = true
                    }
                } else if model.canCreateEntry {
                    // The same command as ⌘N, so an empty journal offers the next step.
                    Button("New Entry") { Task { await model.newEntry() } }
                }
            } else if !model.query.isEmpty {
                Button("Clear Search") { model.query = "" }
            }
        }
    }
    /// A new library has no templates, so the empty Templates list says how to make one
    /// (no-built-in-templates-2026-10-04.md). VoiceOver reads both lines as one element.
    private var noTemplates: some View {
        VStack(spacing: 4) {
            Text("No Templates")
            // The command's name stays on one line.
            Text("To create a template, open an entry and choose Save\u{00A0}as\u{00A0}Template.").font(.callout)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
    private func presentRequestedNewJournal() {
        guard model.newJournalRequested else { return }
        model.newJournalRequested = false
        journalName = ""
        newJournal = true
    }
    func collectionTitle(_ destination: JournalDestination) -> String {
        switch destination {
        case .all: return "All Entries"
        case .templates: return "Templates"
        case .deleted: return "Recently Deleted"
        case .unavailable: return "Unavailable Journals"
        case .journal(let id):
            let title = model.journals.first { $0.id == id }?.title ?? ""
            return title.isEmpty ? "Untitled Journal" : title
        }
    }
    /// On the Mac, the sentence is in the header with Delete All… instead (RecentlyDeletedHeader.swift).
    @ViewBuilder private var trashFooter: some View {
        #if os(iOS)
            Text("Items stay here until you delete them permanently.")
        #endif
    }
    private func entryRow(_ entry: JournalItem, value: String? = nil) -> some View {
        entryLink(entry.id) {
            VStack(alignment: .leading, spacing: 5) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.date, format: .dateTime.day().month(.abbreviated))
                            entryConflictIndicator(entry)
                        }
                        if model.showingAllEntries {
                            Text(journalName(for: entry)).fixedSize(horizontal: false, vertical: true)
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(entry.date, format: .dateTime.day().month(.abbreviated)).font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.showingAllEntries {
                            Label(journalName(for: entry), systemImage: "book.closed").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        entryConflictIndicator(entry)
                    }
                }
                Text(entry.displayTitle).font(.body.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                let preview = model.listPreview(of: entry)
                // As in Notes, rows keep one height; an entry without text says so.
                Text(preview.isEmpty ? "No additional text" : preview).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize(horizontal: false, vertical: true)
            }.fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4).accessibilityElement(children: .combine)
                // A pinned row says so, even when its section header is skipped.
                .accessibilityValue(value ?? (model.showsPinnedSection && model.isPinned(entry) ? "Pinned" : ""))
                // Separators start at the row's text, not at the journal label's text.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                .accessibilityFocused($returnedRow, equals: entry.id)
        }.contextMenu { entryActions(entry) }
            .swipeActions(edge: .trailing) { swipeActions(entry) }
            .swipeActions(edge: .leading) {
                if model.isRecentlyDeleted(entry), model.restoreOffer(for: entry)?.returnsToOwnJournal == true {
                    // Only into the entry's own journal: a full swipe never files an entry somewhere unexpected.
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore(entry) }.tint(.accentColor)
                } else if model.canPin(entry) {
                    let pinned = model.isPinned(entry)
                    Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
                        setPinned(!pinned, entry.id)
                    }.tint(.accentColor)
                }
            }
    }
    @ViewBuilder private func entryConflictIndicator(_ entry: JournalItem) -> some View {
        if model.conflicts.contains(where: { $0.id == entry.id }) {
            Image(systemName: "exclamationmark.circle").accessibilityLabel("Changes need review")
        }
    }
    private func entryActions(_ entry: JournalItem) -> some View {
        MenuActionsView(actions: entryActionCatalog(entry))
    }
    /// An entry's actions, in its row's context menu and the Entry Actions menu.
    func entryActionCatalog(_ entry: JournalItem) -> [MenuAction] {
        let editable = model.offersDelete(entry)
        var actions: [MenuAction] = []
        // First in the entry's group, as Pin Note is in Notes.
        if entry.kind == "entry", model.canPin(entry) {
            let pinned = model.isPinned(entry)
            actions.append(
                .command(pinned ? "Unpin Entry" : "Pin Entry", symbol: pinned ? "pin.slash" : "pin") {
                    setPinned(!pinned, entry.id)
                })
        }
        if editable, entry.kind == "entry" {
            actions.append(
                .command("Change Date…", symbol: "calendar") {
                    performRowAction(entry.id) { entryToDate = model.draft }
                })
            actions.append(
                .command("Move Entry…", symbol: "folder") {
                    performRowAction(entry.id) { entryToMove = model.draft }
                })
            actions.append(
                .command("Save as Template…", symbol: "doc.badge.plus") {
                    performRowAction(entry.id) {
                        templateName = model.draft?.title ?? ""
                        saveTemplate = true
                    }
                })
        }
        if !entry.document.imageBlocks.isEmpty {
            actions.append(
                .command(
                    "Image Descriptions…", symbol: "text.below.photo",
                    enabled: model.offersImageDescriptions(for: entry)
                ) {
                    performRowAction(entry.id) { imageDescriptionsEntry = model.draft }
                })
        }
        actions.append(
            .command("Version History…", symbol: "clock.arrow.circlepath") {
                performRowAction(entry.id) { history = model.draft }
            })
        if model.isRecentlyDeleted(entry) {
            if let offer = model.restoreOffer(for: entry) {
                actions.append(.command(offer.title, symbol: "arrow.uturn.backward") { restore(entry) })
            }
            actions.append(.separator("restore"))
            actions.append(
                .command("Delete Permanently…", symbol: "trash", destructive: true) {
                    permanentDeletionRequest = .init(id: entry.id)
                })
        } else if entry.kind == "entry", let offer = model.restoreOffer(for: entry) {
            // An entry deleted by itself whose journal is gone, in Unavailable Journals: never on a swipe.
            actions.append(.command(offer.title, symbol: "arrow.uturn.backward") { restore(entry) })
        }
        if editable {
            actions.append(.separator("delete"))
            actions.append(
                .command(
                    entry.kind == "template" ? "Delete Template" : "Delete Entry", symbol: "trash", destructive: true
                ) {
                    delete(entry.id)
                })
        }
        return actions
    }
    @ViewBuilder private func swipeActions(_ entry: JournalItem) -> some View {
        if model.isRecentlyDeleted(entry) {
            Button("Delete", systemImage: "trash", role: .destructive) { swipePermanentDeletion(entry.id) }
        } else if model.offersDelete(entry) {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(entry.id) }
        }
    }
    private func deleteSelectedFromList() {
        guard let entry = model.draft, entry.kind != "journal" else { return }
        if model.isRecentlyDeleted(entry) {
            permanentDeletionRequest = .init(id: entry.id)
        } else if model.canEdit {
            delete(entry.id)
        }
    }
    /// A destructive swipe takes its row away at once, in one movement, as in a journal's list; the alert then asks,
    /// and the row comes back unless the item is deleted (docs/design/ios-delete-all-and-settings-2026-10-03.md §1).
    private func swipePermanentDeletion(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .default) { model.hideInLists(id) }
        permanentDeletionRequest = .init(id: id, rowRemoved: true)
    }
    /// Restores at once. On the iPhone the stack becomes the journal and the entry the restore opens.
    private func restore(_ entry: JournalItem) {
        rowActionTask?.cancel()
        rowActionTask = Task {
            let restored = await model.restore(entry)
            #if os(iOS)
                if restored, usesStackedNavigation, entry.kind == "entry", model.draft?.id == entry.id {
                    model.revealsSelection = true
                }
            #endif
        }
    }
    /// Moves the entry or template to Recently Deleted at once, as in Notes; Edit ▸ Undo Delete Entry (or Undo
    /// Delete Template) brings it back. Its row leaves the list in the same update, as a swipe action expects.
    func delete(_ id: UUID) {
        let selectingNext = !usesStackedNavigation
        let removal = withAnimation(reduceMotion ? nil : .default) {
            model.removeFromLists(id, selectingNext: selectingNext)
        }
        guard let removal else { return }
        leaveDeletedEntry(id)
        let previous = deletionTask
        deletionTask = Task {
            await previous?.value
            guard let deleted = await model.deleteListed(removal, settle: reduceMotion ? .zero : .listRemoval) else {
                return
            }
            model.registerDeletionUndo(deleted, selectingNext: selectingNext, in: undoManager)
        }
    }
    /// On iPhone, a deleted entry's page goes back to the list while it still shows the entry.
    private func leaveDeletedEntry(_ id: UUID) {
        if usesStackedNavigation, navigationPath.last == .entry(id) { navigationPath.removeLast() }
    }
    private func journalName(for entry: JournalItem) -> String {
        let title = model.journals.first { $0.id == entry.journalID }?.title ?? ""
        return title.isEmpty ? "Untitled Journal" : title
    }
    /// Pins or unpins without changing the selection. VoiceOver focus follows the row to its new section once the list
    /// has updated, since the row's view is made again there.
    private func setPinned(_ pinned: Bool, _ id: UUID) {
        rowActionTask?.cancel()
        // The next row action cancels only the focus change: a pin made in quick succession with it still happens.
        let pinning = Task { await model.setPinned(pinned, entryID: id, undoManager: undoManager) }
        rowActionTask = Task {
            _ = await pinning.value
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            returnedRow = id
        }
    }
    private func performRowAction(_ id: UUID, action: @escaping @MainActor () async -> Void) {
        rowActionTask?.cancel()
        rowActionTask = Task {
            guard await model.selectEntryForAction(id) else { return }
            await action()
        }
    }
    private var groupedEntries: [(String, [JournalItem])] { model.entryGroups }
    /// The list of entries, built again only when what it shows changed. Everything else the model publishes, such as
    /// a sync or a save, leaves it as it is: comparing a list of thousands of rows took tens of milliseconds each time.
    var listedSidebar: some View {
        #if os(iOS)
            let searching = searchPresented
        #else
            let searching = false
        #endif
        return Isolated(
            key: model.listKey(
                accessibilitySize: dynamicTypeSize.isAccessibilitySize, stacked: usesStackedNavigation,
                searchPresented: searching)
        ) { sidebar }.equatable()
    }
    /// A section's rows; on the Mac the last one has no line below it.
    private func monthRows(_ entries: [JournalItem]) -> some View {
        ForEach(entries) { entry in
            listedRow(entry).entriesRowSeparator(lastInSection: entry.id == entries.last?.id)
        }
    }
    /// An entry's row, built again only when what it shows changed.
    private func listedRow(_ entry: JournalItem) -> some View {
        Isolated(key: model.rowKey(entry, accessibilitySize: dynamicTypeSize.isAccessibilitySize)) {
            entryRow(entry)
        }.equatable()
    }
    private func entryEditor(_ item: JournalItem) -> NativeEditor {
        var native = NativeEditor(
            document: binding(\.document, default: item.document, itemID: item.id), itemID: item.id,
            images: model.imageData,
            loadingImages: model.imageLoader.loading, initialInsertion: model.initialInsertion,
            fontSize: editorSize, editable: model.canEdit, actions: editor
        ) { [generation = model.imageInsertionGeneration] data in
            guard model.imageInsertionGeneration == generation else { return nil }
            return await model.addImage(data)
        }
        if model.templateSuggestion(for: item).isShown {
            native.suggestion = AnyView(TemplateSuggestionView().environmentObject(model))
        }
        #if os(iOS)
            var configured = native
            configured.header = AnyView(
                EntryHeaderView(item: item, title: binding(\.title, default: item.title, itemID: item.id))
                    .environmentObject(model).environmentObject(editor))
            configured.revealSaveFailure = model.saveFailure && model.error == nil
            configured.imageActions = imageActions(for: item)
            return configured
        #else
            native.imageActions = imageActions(for: item)
            return native
        #endif
    }
    /// The actions on the entry's pictures: on iPhone and iPad Copy, Share, Save to Photos, Image Descriptions and
    /// Delete; on the Mac Cut, Copy, Paste, Share, Save Image As, Image Descriptions and Delete.
    private func imageActions(for item: JournalItem) -> ImageActionSupport {
        let store = model.store
        let original: @MainActor (UUID) async -> Data? = { id in
            guard let store else { return nil }
            return try? await store.attachment(id)
        }
        var describe: (@MainActor () -> Void)?
        if model.canDescribeImages(in: item.id) {
            describe = { imageDescriptionsEntry = model.draft }
        }
        return ImageActionSupport(original: original, report: { model.error = $0 }, describe: describe)
    }
    @ViewBuilder var detail: some View {
        #if os(macOS)
            VStack(spacing: 0) {
                ConnectionPauseNotice()
                detailContent
            }
        #else
            detailContent
        #endif
    }
    @ViewBuilder private var detailContent: some View {
        if let item = model.draft, item.kind == "journal" {
            DeletedJournalView(journal: item, leave: leaveDeletedEntry)
        } else if let item = model.draft {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    #if os(macOS)
                        if item.kind == "entry"
                            ? !model.lifecycle.location(of: item).isInLiveJournal
                            : model.isRecentlyDeleted(item)
                        {
                            recoveryNotice(item, availableHeight: geometry.size.height)
                        }
                        if model.conflicts.contains(where: { $0.id == item.id }) {
                            ConflictNotice(id: item.id)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            EntryTitleEditor(
                                text: binding(\.title, default: item.title, itemID: item.id),
                                initialFocus: model.titleFocus?.itemID == item.id ? model.titleFocus : nil,
                                submit: { editor.perform(.focus) }
                            ).id(item.id).disabled(!model.canEdit)
                            EntryEditingNote(document: item.document)
                        }
                        // The title's first letter where the body's starts.
                        .padding(.horizontal, Self.editorMargin + EntryTextInset.text)
                        .padding(.top, 28).padding(.bottom, 12)
                    #else
                        // Above the writing rather than in it, so it stays in view however far the entry is
                        // scrolled, as on the Mac.
                        if model.conflicts.contains(where: { $0.id == item.id }) {
                            ConflictNotice(id: item.id)
                        }
                    #endif
                    if let session = imageInsertion {
                        ImageImportNotice(session: session) { cancelImageImport() }
                    }
                    entryEditor(item).padding(.horizontal, Self.editorMargin)
                    #if os(macOS)
                        if model.saveFailure {
                            SaveFailureNotice(entryID: item.id).padding()
                        }
                    #endif
                }
                .frame(maxWidth: 760).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
            #if os(iOS)
                .safeAreaInset(edge: .bottom) {
                    // While typing, the keyboard's accessory shows these same controls instead.
                    if !editor.editing && !editor.editingTable {
                        ReadingBar(fitsContents: !usesStackedNavigation) {
                            mobileFormattingButton
                            insertImageButton
                            if usesStackedNavigation { Spacer(minLength: 16) }
                            sourceModeButton
                        }
                    }
                }
            #endif
        } else {
            // Blank while the list is empty, as in Notes: there is nothing to select. Without the list beside it,
            // the editor offers what the empty list would.
            // Always a view that fills the column, even when blank, so the column's width is still measured.
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).overlay {
                if !model.entries.isEmpty {
                    Text("Select an Entry").foregroundStyle(.secondary)
                } else if showsEmptyListInEditor {
                    emptyListState
                }
            }
        }
    }
    @ViewBuilder private func recoveryNotice(_ item: JournalItem, availableHeight: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .vertical) {
                EntryRecoveryNotice(entry: item).fixedSize(horizontal: false, vertical: true).padding()
                ScrollView {
                    EntryRecoveryNotice(entry: item).fixedSize(horizontal: false, vertical: true).padding()
                }.accessibilityIdentifier("Entry recovery notice")
            }.frame(maxHeight: availableHeight / 2).clipped().background(.quaternary)
        } else {
            EntryRecoveryNotice(entry: item).padding().background(.quaternary)
        }
    }
    /// The space beside the editor in the detail column.
    static let editorMargin: CGFloat = 24
    private var editorSize: CGFloat {
        #if os(macOS)
            model.textSize
        #else
            // Zoom In and Zoom Out scale the Dynamic Type size.
            preferredTextSize * model.textSize / AppModel.defaultTextSize
        #endif
    }
    private func binding<T>(_ path: WritableKeyPath<JournalItem, T>, default value: T, itemID: UUID? = nil) -> Binding<
        T
    > {
        Binding(
            get: {
                // An editor leaving the screen, such as a deleted entry's page going back, keeps showing its entry.
                guard let draft = model.draft, itemID == nil || draft.id == itemID else { return value }
                return draft[keyPath: path]
            },
            set: { newValue in
                guard var item = model.draft, itemID == nil || item.id == itemID else { return }
                item[keyPath: path] = newValue
                model.updateDraft(item)
            })
    }
    #if os(iOS)
        var creationActions: some View {
            EntryCreationActions(
                global: false,
                newJournal: {
                    createAfterJournal = true
                    newJournal = true
                })
        }
    #endif
    private func importImageResult(_ session: ImageInsertionSession, result: Result<[ImageLoad], Error>) {
        guard imageInsertion === session, session.isCurrent(in: model) else { return }
        imageImportTask = Task {
            defer {
                if imageInsertion === session {
                    imageInsertion = nil
                    imageImportTask = nil
                }
            }
            do {
                await session.insert(try result.get(), into: model)
            } catch {
                guard session.isCurrent(in: model), (error as? CocoaError)?.code != .userCancelled else { return }
                model.error = error.shown(.saving)
            }
        }
    }
    /// `leaving`: the person left the entry, which the import then mentions if it hadn't finished.
    private func cancelImageImport(leaving: Bool = false) {
        imageImportTask?.cancel()
        imageImportTask = nil
        if leaving { imageInsertion?.leave() } else { imageInsertion?.cancel() }
        imageInsertion = nil
        importImage = false
    }
    private var mobileFormattingButton: some View {
        FormattingButton(session: editor.formatting) {
            #if os(iOS)
                editor.toggleFormatting?(editor.formattingToolbarAnchor)
            #endif
        }.disabled(!model.canEdit)
            #if os(iOS)
                .background(FormattingButtonAnchor(editor: editor))
            #endif
    }
    var entryMenu: some View {
        Menu {
            #if os(iOS)
                Button("Find in Entry", systemImage: "magnifyingglass") { editor.findInEntry?() }
                Divider()
            #endif
            if let draft = model.draft, draft.kind != "journal" { entryActions(draft) }
            #if os(iOS)
                syncMenu
            #endif
        } label: {
            Label("Entry Actions", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
        .iconHelp("Entry Actions").disabled(model.draft == nil || model.draft?.kind == "journal")
    }

}
