import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// The menu bar on the Mac and the iPad (and the ⌘ shortcut overlay there), laid out as in Notes.
struct JournalCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: EditorActions
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        /// The window in front with a library open.
        @FocusedValue(\.editorOnly) private var editorOnly
        @FocusedValue(\.deleteAll) private var deleteAll
    #endif

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") { inJournalWindow { Task { await model.newEntry() } } }.keyboardShortcut("n")
                .disabled(!model.canCreateEntry)
            Button("New Journal…") { inJournalWindow { model.newJournalRequested = true } }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!model.isReady || model.locked)
            // The same chooser as the link in an empty entry, so it is available exactly when that link is shown.
            Button("Use a Template…") {
                // The chooser appears at once, without the sheet's animation, as the formatting controls do.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                inJournalWindow { withTransaction(transaction) { model.templateChooserPresented = true } }
            }
            .disabled(!model.canUseTemplate)
            Divider()
            // Acts on the selected entry; no shortcut, as in Notes (pinned-entries.md).
            let pinnable = model.selectedPinnable
            Button(pinnable.map(model.isPinned) == true ? "Unpin Entry" : "Pin Entry") {
                guard let pinnable else { return }
                Task {
                    await model.setPinned(!model.isPinned(pinnable), entryID: pinnable.id, undoManager: undoManager)
                }
            }.disabled(pinnable == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("Import Archive…") { inJournalWindow { model.archiveImportRequested = true } }
                .disabled(!model.canImportArchive)
            Button("Export Archive…") { inJournalWindow { model.archiveExportPresented = true } }
                .disabled(!model.isReady || model.locked)
            Button("Export Journals as Markdown…") { inJournalWindow { model.markdownExportPresented = true } }
                .disabled(!model.isReady || model.locked)
        }
        #if os(macOS)
            CommandGroup(after: .importExport) {
                Divider()
                // Names what it deletes: unlike the toolbar button, it has no list beside it. ⇧⌘⌫ as Finder's Empty
                // Trash… and Mail's Erase Deleted Items.
                Button("Delete All in Recently Deleted…") { deleteAll?.request() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .disabled(deleteAll == nil || !model.canDeleteAll)
            }
        #endif
        TextEditingCommands()
        CommandGroup(after: .textEditing) {
            if Self.canPresentSearch {
                Button("Search Entries") { inJournalWindow { editor.searchRequested = true } }
                    .keyboardShortcut("f", modifiers: Self.searchEntriesModifiers)
                    .disabled(!model.isReady || model.locked)
            }
        }
        CommandMenu("Format") { formatMenu }
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            #if os(macOS)
                editorOnlyCommands
                Divider()
            #endif
            Button(editor.sourceMode ? "View Preview" : "View Source") { editor.toggleSourceMode() }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(!model.canEdit || model.draft?.document.requiresMarkdownSource == true)
            Divider()
            Button("Zoom In") { model.textSize = min(30, model.textSize + 1) }.keyboardShortcut("+")
            Button("Zoom Out") { model.textSize = max(12, model.textSize - 1) }.keyboardShortcut("-")
            Button("Actual Size") { model.textSize = AppModel.defaultTextSize }.keyboardShortcut("0")
                .disabled(model.textSize == AppModel.defaultTextSize)
        }
        // There is no help book: the user guide and the project's pages are on the web (AboutLinks.swift).
        CommandGroup(replacing: .help) { HelpMenuItems() }
        #if os(macOS)
            CommandGroup(before: .systemServices) {
                Button("Lock My Journal") { Task { await model.lock() } }
                    .keyboardShortcut("l", modifiers: [.command, .control]).disabled(!model.appLockOn)
            }
        #endif
    }

    #if os(macOS)
        /// Focused writing, and moving through the list without showing it. ⌘↑ and ⌘↓ stay text navigation.
        @ViewBuilder private var editorOnlyCommands: some View {
            Button(editorOnly?.active == true ? "Show Sidebar and List" : "Show Editor Only") { editorOnly?.toggle() }
                .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(editorOnly == nil)
            Divider()
            Button("Previous Entry") { Task { await model.selectListed(.previous) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(editorOnly == nil || model.listedID(.previous) == nil)
            Button("Next Entry") { Task { await model.selectListed(.next) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(editorOnly == nil || model.listedID(.next) == nil)
        }
    #endif

    /// ⌥⌘F as in Notes, with Find and Replace… on ⇧⌘F (FindMenuShortcuts on the Mac). On iPad the system’s Find and
    /// Replace… still has ⌥⌘F when these commands are added, so Search Entries starts with ⇧⌘F and FindKeyCommands
    /// swaps the two.
    private static var searchEntriesModifiers: EventModifiers {
        #if os(iOS)
            [.command, .shift]
        #else
            [.command, .option]
        #endif
    }

    /// On iPad, presenting the search field from a command needs iOS 17; before that the command isn't offered.
    private static var canPresentSearch: Bool {
        #if os(iOS)
            if #available(iOS 17, *) { return true }
            return false
        #else
            return true
        #endif
    }

    /// The journal window's undo manager, so Edit ▸ Undo Pin Entry follows a menu command too.
    private var undoManager: UndoManager? {
        #if os(macOS)
            model.journalWindow?.undoManager
        #else
            model.windowUndoManager
        #endif
    }

    /// These commands act in the journal window. On the Mac the app keeps running after it's closed, so the window
    /// opens again first rather than the command acting where nothing shows it.
    private func inJournalWindow(_ action: () -> Void) {
        #if os(macOS)
            if !model.hasJournalWindow { openWindow(id: JournalApp.windowID) }
        #endif
        action()
    }

    @ViewBuilder private var formatMenu: some View {
        Group {
            Button("Bold") { editor.perform(.bold) }.keyboardShortcut("b")
            Button("Italic") { editor.perform(.italic) }.keyboardShortcut("i")
            Button("Underline") { editor.perform(.underline) }.keyboardShortcut("u")
            Button("Strikethrough") { editor.perform(.strikethrough) }.keyboardShortcut(
                "x", modifiers: [.command, .shift])
            Button("Inline Code") { editor.perform(.code) }.keyboardShortcut("c", modifiers: [.command, .option])
            Divider()
            Button("Paragraph") { editor.perform(.paragraph("paragraph")) }
                .keyboardShortcut("0", modifiers: [.command, .option])
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") {
                    editor.perform(.paragraph(level == 1 ? "heading" : level == 2 ? "subheading" : "heading\(level)"))
                }.keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: [.command, .option])
            }
            Divider()
            Button("Bulleted List") { editor.perform(.paragraph("bullet")) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Numbered List") { editor.perform(.paragraph("numbered")) }
                .keyboardShortcut("9", modifiers: [.command, .shift])
            Button("Checklist") { editor.perform(.paragraph("task")) }.keyboardShortcut(
                "l", modifiers: [.command, .shift])
            Button(editor.caretTaskChecked == true ? "Mark as Unchecked" : "Mark as Checked") {
                editor.perform(.toggleTask)
            }.keyboardShortcut("u", modifiers: [.command, .shift]).disabled(editor.caretTaskChecked == nil)
            Button("Block Quote") { editor.perform(.paragraph("quote")) }.keyboardShortcut("'")
            Divider()
            Button("Increase Indent") { editor.perform(.indent) }.keyboardShortcut("]")
                .disabled(!editor.caretIndentation.increase)
            Button("Decrease Indent") { editor.perform(.outdent) }.keyboardShortcut("[")
                .disabled(!editor.caretIndentation.decrease)
            Divider()
            Menu("Insert") {
                Button("Code Block") { editor.perform(.insert("```\n\n```\n")) }
                Button("Table") { editor.perform(.insert("|  |  |\n| --- | --- |\n|  |  |\n")) }
                Button("Horizontal Rule") { editor.perform(.insert("---\n")) }
                Divider()
                // ⌘K adds or edits, as in Notes and Pages: it reads Edit Link… with the caret in a link.
                Button(editor.caretLink.edit ? "Edit Link…" : "Add Link…") { editor.openLinkFromKeyboard() }
                    .keyboardShortcut("k")
                Button("Remove Link") { editor.perform(.removeLink(nil)) }.disabled(!editor.caretLink.remove)
                Button("Image…") {
                    #if os(macOS)
                        editor.insertImage(from: .files)
                    #else
                        editor.insertImage(from: .photos)
                    #endif
                }
            }
        }.disabled(!model.canEdit || !(editor.editing || editor.editingTable))
        Menu("Table") {
            TableMenuContent(alignment: editor.tableAlignment) { editor.tableAction?($0) }
        }.disabled(!model.canEdit || !editor.editingTable)
    }
}

#if os(macOS)
    /// View ▸ Zoom In shows ⌘+, as in Safari and Notes, and also answers ⌘= on the same key without Shift, as Zoom
    /// Out answers ⌘- and Actual Size ⌘0. SwiftUI has no hidden menu items, so the key press is given to the menu as
    /// ⌘+.
    @MainActor final class ZoomInShortcut {
        static let shared = ZoomInShortcut()
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: Self.menuEvent(for:))
        }

        /// ⌘= as ⌘+, which Zoom In's key equivalent matches; any other event unchanged.
        nonisolated static func menuEvent(for event: NSEvent) -> NSEvent {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard event.type == .keyDown, modifiers == .command, event.charactersIgnoringModifiers == "=" else {
                return event
            }
            return NSEvent.keyEvent(
                with: .keyDown, location: event.locationInWindow, modifierFlags: event.modifierFlags,
                timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil, characters: "+",
                charactersIgnoringModifiers: "+", isARepeat: event.isARepeat, keyCode: event.keyCode) ?? event
        }
    }
#endif
