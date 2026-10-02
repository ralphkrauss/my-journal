#if os(macOS)
    import AppKit
    import SwiftUI

    /// What the journal window's toolbar shows, and what its items do. Built by `RootView` on every update.
    struct JournalToolbarConfiguration {
        /// What Sync Status shows when the person must act (sync-health-and-recovery.md §4.2).
        struct SyncStatus: Equatable {
            let message: String
            /// The sync state's single action, such as Try Again or Connect Again… (sync-health-and-recovery.md).
            let action: String
        }

        var editorOnly = false
        var canCreateJournal = false
        var canCreateEntry = false
        var canEdit = false
        var entryID: UUID?
        var sourceMode = false
        var previewUnavailable = false
        var hasEntryActions = false
        /// The library syncs with a server, so the toolbar keeps Sync Status's place whether or not it shows.
        var syncs = false
        var syncStatus: SyncStatus?
        var searchPrompt = ""
        var query = ""
        var searchRequested = false

        var newJournal: @MainActor () -> Void = {}
        var newEntry: @MainActor () -> Void = {}
        /// The Formatting popover's contents, created once and reused.
        var formatting: @MainActor (_ close: @escaping () -> Void) -> AnyView = { _ in AnyView(EmptyView()) }
        /// Formatting is about to show; `close` closes it (with `refocus` when the person dismissed it, as Escape does).
        var formattingWillShow: @MainActor (_ close: @escaping (_ refocus: Bool) -> Void) -> Void = { _ in }
        var formattingDidClose: @MainActor () -> Void = {}
        var insertImage: @MainActor () -> Void = {}
        var toggleSourceMode: @MainActor () -> Void = {}
        var toggleEditorOnly: @MainActor () -> Void = {}
        var entryActions: @MainActor () -> [MenuAction] = { [] }
        var journalActions: @MainActor () -> [MenuAction] = { [] }
        var syncAction: @MainActor () -> Void = {}
        var syncSettings: @MainActor () -> Void = {}
        var setQuery: @MainActor (String) -> Void = { _ in }
        /// The person moved keyboard focus to the search field.
        var searchFocused: @MainActor () -> Void = {}
        var searchPresented: @MainActor () -> Void = {}
    }

    /// The journal window's toolbar, with sections that follow the column dividers as in Notes: New Journal and the
    /// sidebar button over the sidebar, the collection's title and Journal Actions over the list, and the editor's
    /// controls with search last over the editor.
    @MainActor
    final class JournalToolbarController: NSObject {
        let toolbar: NSToolbar
        weak var splitView: NSSplitView?
        weak var splitController: NSSplitViewController?
        private(set) var configuration = JournalToolbarConfiguration()
        private var sidebarShown = true
        private var listShown = true
        private var listDividerShown = true
        private weak var window: NSWindow?
        private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
        private let searchField = FocusReportingSearchField()
        private let formattingPopover = ToolbarPopover(
            title: "Formatting", symbol: "textformat", initialFocus: .firstControl)
        private var formattingContent: NSViewController?
        private let entryMenu = MenuActionTarget()
        private let journalMenu = MenuActionTarget()
        private let editorOnlyButton = NSButton()
        private let syncStatusButton = MenuToolbarButton()
        /// Sync Status's place, as wide as its button whether or not that shows, so it appearing or leaving never moves
        /// another item.
        private let syncStatusSlot = NSView()
        private let syncStatusOverflow = NSMenuItem(title: "Sync Status", action: nil, keyEquivalent: "")
        private var searchPending = false
        private var uninstalling = false

        override init() {
            // Toolbars that share an identifier are kept identical across windows; each window has its own columns.
            toolbar = NSToolbar(identifier: "JournalWindow-" + UUID().uuidString)
            super.init()
            toolbar.autosavesConfiguration = false
            toolbar.allowsUserCustomization = false
            toolbar.displayMode = .iconOnly
            toolbar.delegate = self
            searchField.delegate = self
            searchField.sendsSearchStringImmediately = true
            searchField.focused = { [weak self] in self?.configuration.searchFocused() }
            editorOnlyButton.setButtonType(.pushOnPushOff)
            editorOnlyButton.bezelStyle = .toolbar
            editorOnlyButton.image = NSImage(
                systemSymbolName: "rectangle.center.inset.filled", accessibilityDescription: "Editor Only")
            editorOnlyButton.imagePosition = .imageOnly
            editorOnlyButton.setAccessibilityLabel("Editor Only")
            editorOnlyButton.target = self
            editorOnlyButton.action = #selector(toggleEditorOnly)
            configureSyncStatus()
            formattingPopover.button.target = self
            formattingPopover.button.action = #selector(showFormatting)
            formattingPopover.didClose = { [weak self] _ in self?.configuration.formattingDidClose() }
        }

        func install(in window: NSWindow) {
            self.window = window
            if window.toolbar !== toolbar { window.toolbar = toolbar }
            // No line below the toolbar, as in Notes; the split view isn't the window's content controller, whose
            // columns would otherwise decide.
            window.titlebarSeparatorStyle = .none
            applyTitle()
        }

        func uninstall(from window: NSWindow) {
            formattingPopover.close()
            // Removing the toolbar lays out the window, which can take the columns away and ask again before the
            // window lets go of it; removing it twice released it twice.
            guard !uninstalling, window.toolbar === toolbar else { return }
            uninstalling = true
            defer { uninstalling = false }
            window.toolbar = nil
            // Nothing from the journal stays in the title bar or the Window menu while it's locked.
            window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
            window.subtitle = ""
            window.titleVisibility = .visible
            window.titlebarSeparatorStyle = .automatic
        }

        // MARK: State

        func update(_ configuration: JournalToolbarConfiguration) {
            let previous = self.configuration
            self.configuration = configuration
            if previous.entryID != configuration.entryID || !configuration.canEdit {
                formattingPopover.close()
            }
            syncItems()
            updateItems()
            applyTitle()
            if configuration.searchRequested, !searchPending {
                // After the update: presenting search changes the state that asked for it.
                searchPending = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.searchPending = false
                    self.searchItem?.beginSearchInteraction()
                    self.configuration.searchPresented()
                }
            }
        }

        /// The columns whose toolbar items show. The split view controller hides a column's items before the
        /// column collapses and shows them once it has expanded.
        func showColumns(sidebar: Bool, list: Bool, listDivider: Bool? = nil) {
            sidebarShown = sidebar
            listShown = list
            listDividerShown = listDivider ?? list
            syncItems()
            applyTitle()
        }

        private func applyTitle() {
            guard let window else { return }
            // Without the list, the editor section has no title, as in Notes; the Window menu keeps the title.
            let visibility: NSWindow.TitleVisibility = listShown ? .visible : .hidden
            if window.titleVisibility != visibility { window.titleVisibility = visibility }
        }

        private var searchItem: NSSearchToolbarItem? { items[.search] as? NSSearchToolbarItem }

        // MARK: Items

        /// The toolbar's items, leading to trailing, each with a name of its own; the flexible spaces are
        /// otherwise alike.
        private var layout: [(name: String, identifier: NSToolbarItem.Identifier)] {
            var layout: [(name: String, identifier: NSToolbarItem.Identifier)] = []
            if sidebarShown { layout.append(("newJournal", .newJournal)) }
            layout += [("toggleSidebar", .toggleSidebar), ("sidebarSeparator", .sidebarTrackingSeparator)]
            if listShown { layout += [("listSpace", .flexibleSpace), ("journalActions", .journalActions)] }
            // With the list hidden, its separator would stand alone among the editor's items. It stays while the list
            // collapses or expands, so the editor's items follow the divider.
            if listDividerShown { layout.append(("listSeparator", .listSeparator)) }
            layout += [("newEntry", .newEntry), ("leadingSpace", .flexibleSpace)]
            layout += [("formatting", .formatting), ("insertImage", .insertImage), ("trailingSpace", .flexibleSpace)]
            // A space keeps Sync Status apart from Editor Only's group, as a status of its own.
            if configuration.syncs { layout += [("syncStatus", .syncStatus), ("syncSpace", .space)] }
            layout += [("editorOnly", .editorOnly), ("sourceMode", .sourceMode), ("entryActions", .entryActions)]
            layout.append(("search", .search))
            return layout
        }

        var identifiers: [NSToolbarItem.Identifier] { layout.map(\.identifier) }

        /// The names of the toolbar's items, in order. Only the list's flexible space comes and goes, so the flexible
        /// spaces are named from the trailing end.
        private var shownNames: [String] {
            var spaces = ["trailingSpace", "leadingSpace", "listSpace"]
            return toolbar.items.reversed().map { item -> String in
                guard item.itemIdentifier == .flexibleSpace else { return Self.name(of: item.itemIdentifier) }
                return spaces.isEmpty ? "space" : spaces.removeFirst()
            }.reversed()
        }

        private static func name(of identifier: NSToolbarItem.Identifier) -> String {
            switch identifier {
            case .toggleSidebar: return "toggleSidebar"
            case .sidebarTrackingSeparator: return "sidebarSeparator"
            case .space: return "syncSpace"
            default: return identifier.rawValue
            }
        }

        /// Removes the items that leave and inserts those that return, keeping every other item in place.
        private func syncItems() {
            guard !toolbar.items.isEmpty else { return }
            let wanted = layout
            let names = Set(wanted.map(\.name))
            var shown = shownNames
            for index in shown.indices.reversed() where !names.contains(shown[index]) {
                toolbar.removeItem(at: index)
                shown.remove(at: index)
            }
            for (position, item) in wanted.enumerated() where !shown.contains(item.name) {
                let present = Set(shown)
                let index = wanted[..<position].filter { present.contains($0.name) }.count
                toolbar.insertItem(withItemIdentifier: item.identifier, at: index)
                shown = shownNames
            }
        }

        private func updateItems() {
            let configuration = configuration
            items[.newJournal]?.isEnabled = configuration.canCreateJournal
            items[.newEntry]?.isEnabled = configuration.canCreateEntry
            items[.formatting]?.isEnabled = configuration.canEdit
            formattingPopover.button.isEnabled = configuration.canEdit
            items[.insertImage]?.isEnabled = configuration.canEdit
            if let item = items[.sourceMode] {
                let title = configuration.sourceMode ? "View Preview" : "View Source"
                let symbol = configuration.sourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right"
                item.label = title
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                item.toolTip = configuration.previewUnavailable ? "Preview isn’t available for this entry" : title
                item.isEnabled = configuration.canEdit && !configuration.previewUnavailable
            }
            items[.entryActions]?.isEnabled = configuration.hasEntryActions
            editorOnlyButton.state = configuration.editorOnly ? .on : .off
            let editorOnlyHelp = configuration.editorOnly ? "Show Sidebar and List (⇧⌘D)" : "Show Editor Only (⇧⌘D)"
            editorOnlyButton.toolTip = editorOnlyHelp
            items[.editorOnly]?.toolTip = editorOnlyHelp
            showSyncStatus(configuration.syncStatus != nil)
            if searchField.stringValue != configuration.query { searchField.stringValue = configuration.query }
            searchField.placeholderString = configuration.searchPrompt
            searchField.setAccessibilityLabel(configuration.searchPrompt)
            searchField.toolTip = configuration.searchPrompt
        }

        private func button(
            _ identifier: NSToolbarItem.Identifier, _ title: String, symbol: String, action: Selector
        ) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = title
            item.paletteLabel = title
            item.toolTip = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.target = self
            item.action = action
            item.autovalidates = false
            return item
        }

        /// An item whose button the popover knows, so a click on it can be told from a click elsewhere.
        private func popoverItem(
            _ identifier: NSToolbarItem.Identifier, _ title: String, _ popover: ToolbarPopover, action: Selector
        ) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = title
            item.paletteLabel = title
            item.toolTip = title
            item.view = popover.button
            item.autovalidates = false
            let overflow = NSMenuItem(title: title, action: action, keyEquivalent: "")
            overflow.target = self
            item.menuFormRepresentation = overflow
            return item
        }

        private func menu(_ identifier: NSToolbarItem.Identifier, _ title: String, symbol: String) -> NSMenuToolbarItem
        {
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = title
            item.paletteLabel = title
            item.toolTip = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.showsIndicator = false
            item.autovalidates = false
            let menu = NSMenu(title: title)
            menu.autoenablesItems = false
            menu.delegate = self
            item.menu = menu
            return item
        }

        private func makeItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
            switch identifier {
            case .newJournal:
                return button(identifier, "New Journal", symbol: "folder.badge.plus", action: #selector(newJournal))
            case .journalActions:
                return menu(identifier, "Journal Actions", symbol: "ellipsis")
            case .listSeparator:
                guard let splitView else { return nil }
                return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 1)
            case .newEntry:
                return button(identifier, "New Entry", symbol: "square.and.pencil", action: #selector(newEntry))
            case .formatting:
                return popoverItem(identifier, "Formatting", formattingPopover, action: #selector(showFormatting))
            case .insertImage:
                return button(identifier, "Insert Image", symbol: "photo", action: #selector(insertImage))
            case .syncStatus:
                let item = NSToolbarItem(itemIdentifier: identifier)
                item.label = "Sync Status"
                item.paletteLabel = "Sync Status"
                item.view = syncStatusSlot
                // Without a border, an empty place draws no glass; it gets one while the button shows.
                item.isBordered = false
                item.menuFormRepresentation = syncStatusOverflow
                // Gives way first when the window is too narrow for every item.
                item.visibilityPriority = .low
                return item
            case .editorOnly:
                let item = NSToolbarItem(itemIdentifier: identifier)
                item.label = "Editor Only"
                item.paletteLabel = "Editor Only"
                item.view = editorOnlyButton
                return item
            case .sourceMode:
                return button(identifier, "View Source", symbol: "doc.richtext", action: #selector(toggleSourceMode))
            case .entryActions:
                return menu(identifier, "Entry Actions", symbol: "ellipsis")
            case .search:
                let item = NSSearchToolbarItem(itemIdentifier: identifier)
                item.searchField = searchField
                item.preferredWidthForSearchField = 200
                item.label = "Search"
                return item
            default:
                return nil
            }
        }

        // MARK: Actions

        @objc private func newJournal() { configuration.newJournal() }
        @objc private func newEntry() { configuration.newEntry() }
        @objc private func insertImage() { configuration.insertImage() }
        @objc private func toggleSourceMode() { configuration.toggleSourceMode() }
        @objc private func toggleEditorOnly() {
            // The button shows the window's state, which changes with the columns.
            editorOnlyButton.state = configuration.editorOnly ? .on : .off
            configuration.toggleEditorOnly()
        }

        @objc private func showFormatting() {
            guard let item = items[.formatting] else { return }
            formattingPopover.toggle(from: item) {
                let content: NSViewController
                if let formattingContent {
                    content = formattingContent
                } else {
                    let close: () -> Void = { [weak self] in self?.formattingPopover.close(.dismissed) }
                    content = Self.host(configuration.formatting(close))
                    formattingContent = content
                }
                configuration.formattingWillShow { [weak self] refocus in
                    self?.formattingPopover.close(refocus ? .dismissed : .programmatic)
                }
                return content
            }
        }

        /// Popover contents are created once per window and reused, so showing one builds nothing.
        private static func host(_ view: AnyView) -> NSViewController {
            let host = NSHostingController(rootView: view)
            host.sceneBridgingOptions = []
            host.sizingOptions = .preferredContentSize
            return host
        }

        private func configureSyncStatus() {
            let title = "Sync Status"
            syncStatusButton.bezelStyle = .toolbar
            syncStatusButton.setButtonType(.momentaryPushIn)
            syncStatusButton.image = NSImage(
                systemSymbolName: "exclamationmark.icloud", accessibilityDescription: title)
            syncStatusButton.imagePosition = .imageOnly
            syncStatusButton.toolTip = title
            syncStatusButton.setAccessibilityLabel(title)
            syncStatusButton.setAccessibilityRole(.menuButton)
            let menu = NSMenu(title: title)
            menu.autoenablesItems = false
            menu.delegate = self
            syncStatusButton.statusMenu = menu
            let overflow = NSMenu(title: title)
            overflow.autoenablesItems = false
            overflow.delegate = self
            syncStatusOverflow.submenu = overflow
            syncStatusButton.translatesAutoresizingMaskIntoConstraints = false
            syncStatusSlot.addSubview(syncStatusButton)
            NSLayoutConstraint.activate([
                syncStatusButton.leadingAnchor.constraint(equalTo: syncStatusSlot.leadingAnchor),
                syncStatusButton.trailingAnchor.constraint(equalTo: syncStatusSlot.trailingAnchor),
                syncStatusButton.topAnchor.constraint(equalTo: syncStatusSlot.topAnchor),
                syncStatusButton.bottomAnchor.constraint(equalTo: syncStatusSlot.bottomAnchor),
            ])
            syncStatusButton.isHidden = true
            syncStatusOverflow.isHidden = true
        }

        /// Shows or hides Sync Status's button in its place. It fades in, unless Reduce Motion is on.
        private func showSyncStatus(_ shown: Bool) {
            syncStatusOverflow.isHidden = !shown
            if let item = items[.syncStatus], item.isBordered != shown { item.isBordered = shown }
            guard syncStatusButton.isHidden == shown else { return }
            syncStatusButton.isHidden = !shown
            guard shown, syncStatusSlot.window != nil,
                !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            else { return }
            syncStatusButton.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                syncStatusButton.animator().alphaValue = 1
            }
        }

        @objc private func syncAction() { configuration.syncAction() }
        @objc private func syncSettings() { configuration.syncSettings() }
    }

    extension JournalToolbarController: NSToolbarDelegate {
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [
                .newJournal, .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .journalActions,
                .listSeparator, .newEntry, .formatting, .insertImage, .space,
                .syncStatus, .editorOnly,
                .sourceMode, .entryActions, .search,
            ]
        }

        func toolbar(
            _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            let item = makeItem(identifier)
            if let item { items[identifier] = item }
            updateItems()
            return item
        }

        func toolbarWillAddItem(_ notification: Notification) {
            guard let item = notification.userInfo?["item"] as? NSToolbarItem,
                item.itemIdentifier == .toggleSidebar
            else { return }
            // Straight to this window's columns, also while the search field has keyboard focus.
            item.target = splitController
        }
    }

    extension JournalToolbarController: NSMenuDelegate {
        func menuNeedsUpdate(_ menu: NSMenu) {
            if menu === items[.entryActions].flatMap({ ($0 as? NSMenuToolbarItem)?.menu }) {
                entryMenu.fill(menu, with: configuration.entryActions())
            } else if menu === items[.journalActions].flatMap({ ($0 as? NSMenuToolbarItem)?.menu }) {
                journalMenu.fill(menu, with: configuration.journalActions())
            } else if menu === syncStatusButton.statusMenu || menu === syncStatusOverflow.submenu,
                let status = configuration.syncStatus
            {
                menu.removeAllItems()
                let message = NSMenuItem(title: status.message, action: nil, keyEquivalent: "")
                message.isEnabled = false
                menu.addItem(message)
                let retry = NSMenuItem(title: status.action, action: #selector(syncAction), keyEquivalent: "")
                retry.target = self
                menu.addItem(retry)
                let settings = NSMenuItem(title: "Sync Settings…", action: #selector(syncSettings), keyEquivalent: "")
                settings.target = self
                menu.addItem(settings)
            }
        }
    }

    extension JournalToolbarController: NSSearchFieldDelegate {
        func controlTextDidChange(_ notification: Notification) {
            configuration.setQuery(searchField.stringValue)
        }
    }

    /// A toolbar button whose menu opens as the mouse goes down, as a menu toolbar item's does, or when pressed from
    /// the keyboard or with VoiceOver.
    final class MenuToolbarButton: NSButton {
        var statusMenu: NSMenu?

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            showMenu()
        }

        override func performClick(_ sender: Any?) { showMenu() }

        private func showMenu() {
            guard let statusMenu else { return }
            highlight(true)
            defer { highlight(false) }
            let below = NSPoint(x: 0, y: isFlipped ? bounds.maxY + 4 : bounds.minY - 4)
            statusMenu.popUp(positioning: nil, at: below, in: self)
        }
    }

    extension NSToolbarItem.Identifier {
        static let newJournal = Self("newJournal")
        static let journalActions = Self("journalActions")
        static let listSeparator = Self("listSeparator")
        static let newEntry = Self("newEntry")
        static let formatting = Self("formatting")
        static let insertImage = Self("insertImage")
        static let syncStatus = Self("syncStatus")
        static let editorOnly = Self("editorOnly")
        static let sourceMode = Self("sourceMode")
        static let entryActions = Self("entryActions")
        static let search = Self("search")
    }
#endif
