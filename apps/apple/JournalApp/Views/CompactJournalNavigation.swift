import JournalCore
import SwiftUI

enum CompactJournalRoute: Hashable {
    case collection(JournalDestination)
    case entry(UUID)
    var isEntry: Bool {
        if case .entry = self { return true }
        return false
    }
}

extension RootView {
    @ViewBuilder func entryLink<Content: View>(_ id: UUID, @ViewBuilder content: () -> Content) -> some View {
        #if os(macOS)
            // The Mac list's selection opens the entry. Its column is in AppKit's split view, outside any navigation
            // container, where a navigation link can't be followed and so is drawn dimmed, as if unavailable.
            content().tag(id as UUID?)
        #else
            if usesStackedNavigation {
                NavigationLink(value: CompactJournalRoute.entry(id), label: content)
            } else {
                NavigationLink(value: id, label: content)
            }
        #endif
    }

    #if os(iOS)
        var compactNavigation: some View {
            NavigationStack(path: Binding(get: { navigationPath }, set: { navigate(to: $0) })) {
                Group {
                    if journalsQuery.isEmpty {
                        JournalSidebarView(newJournal: { newJournal = true }, showsToolbar: false, stacked: true)
                    } else {
                        JournalSearchResults(query: journalsQuery, openEntry: openSearchResult)
                    }
                }
                .modifier(
                    EntrySearch(
                        text: $journalsQuery, isPresented: $journalsSearchPresented, prompt: "Search All Entries")
                )
                .toolbar { compactToolbar }
                .navigationDestination(for: CompactJournalRoute.self) { route in
                    switch route {
                    case .collection(let destination):
                        // Only this collection's entries and actions ever appear here, even while a save finishes.
                        if model.destination == destination {
                            listedSidebar.toolbar { listToolbar }
                        } else {
                            Color.clear.navigationTitle(collectionTitle(destination))
                        }
                    case .entry(let id):
                        Group {
                            if model.draft?.id == id {
                                detail
                            } else {
                                Color.clear
                            }
                        }
                        .toolbar { mainToolbar }
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
            // After launching or unlocking, return to the entry that was open, as Notes does. The lock screen
            // replaces this view, so the request may already be waiting when it appears.
            .onAppear(perform: revealRestoredEntry)
            .onValueChange(of: model.revealsSelection) { _ in revealRestoredEntry() }
        }

        /// Search Entries (⌥⌘F) opens the search of the list on screen. In stacked navigation, an open entry goes back
        /// to its list first, as going back would; beside the editor, a hidden list column is shown.
        func presentSearch() {
            guard usesStackedNavigation else {
                if columnVisibility == .detailOnly { columnVisibility = .doubleColumn }
                searchPresented = true
                return
            }
            guard !navigationPath.isEmpty else {
                journalsSearchPresented = true
                return
            }
            if navigationPath.count > 1 { navigate(to: Array(navigationPath.prefix(1))) }
            searchPresented = true
        }

        private func revealRestoredEntry() {
            guard model.revealsSelection else { return }
            model.revealsSelection = false
            guard let id = model.selectedID, let destination = model.destination else { return }
            // Open straight on the entry, without the list sliding past first.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { navigationPath = [.collection(destination), .entry(id)] }
        }

        @ToolbarContentBuilder private var compactToolbar: some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    newJournal = true
                } label: {
                    Label("New Journal", systemImage: "folder.badge.plus")
                }
                Button {
                    model.settingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            if #available(iOS 26.0, *) { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                EntryCreationActions(
                    global: true,
                    newJournal: {
                        createAfterJournal = true
                        newJournal = true
                    }
                ).labelStyle(.iconOnly)
            }
        }

        /// Pushes and pops happen at once. A pushed route brings the model to it in the same update when the
        /// draft is saved; otherwise the screen waits for the save and is popped again only if the save fails.
        private func navigate(to requested: [CompactJournalRoute]) {
            let previous = navigationPath
            navigationPath = requested
            if requested.count < previous.count, case .entry = previous.last {
                // Once the writing is saved the entry is deselected, so a relaunch returns to the list rather than
                // reopening it. An empty entry stays in the list, like any other.
                Task {
                    guard await model.flush(), !navigationPath.contains(where: \.isEntry) else { return }
                    model.selectImmediately(nil)
                }
            }
            guard requested.count > previous.count, let route = requested.last else { return }
            if requested.count == 1 { journalsQuery = "" }
            if openImmediately(route) { return }
            navigationTask?.cancel()
            navigationTask = Task { @MainActor in
                let opened: Bool
                switch route {
                case .collection(let destination): opened = await model.show(destination)
                case .entry(let id): opened = await model.select(id) && model.selectedID == id
                }
                guard !Task.isCancelled, !opened, navigationPath == requested else { return }
                navigationPath = previous
            }
        }
        private func openImmediately(_ route: CompactJournalRoute) -> Bool {
            switch route {
            case .collection(let destination):
                return model.destination == destination || model.showImmediately(destination)
            case .entry(let id):
                return model.selectedID == id || model.selectImmediately(id)
            }
        }

        private func openSearchResult(_ id: UUID) {
            navigationTask?.cancel()
            navigationTask = Task { @MainActor in
                guard await model.showCollection(all: true), !Task.isCancelled else { return }
                model.query = journalsQuery
                guard await model.select(id), !Task.isCancelled, model.selectedID == id else { return }
                navigationPath = [.collection(.all), .entry(id)]
            }
        }

        func openRegularCollection(_ destination: JournalDestination) {
            navigationTask?.cancel()
            navigationTask = Task { @MainActor in
                guard await model.show(destination), !Task.isCancelled else { return }
                if navigationWidth > 0, navigationWidth < 1_000 { columnVisibility = .doubleColumn }
            }
        }
    #endif
}
