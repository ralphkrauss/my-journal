import SwiftUI

#if os(macOS)
    /// View ▸ Show Editor Only for the window in front, which keeps its own columns.
    struct EditorOnlyCommand {
        let active: Bool
        let toggle: @MainActor () -> Void
    }

    private struct EditorOnlyCommandKey: FocusedValueKey {
        typealias Value = EditorOnlyCommand
    }

    extension FocusedValues {
        var editorOnly: EditorOnlyCommand? {
            get { self[EditorOnlyCommandKey.self] }
            set { self[EditorOnlyCommandKey.self] = newValue }
        }
    }
#endif

extension RootView {
    /// Without the list beside it, the editor shows what the empty list would, such as No Entries and New Entry.
    var showsEmptyListInEditor: Bool {
        #if os(macOS)
            windowColumns.editorOnly && listIsEmpty
        #else
            false
        #endif
    }

    /// Whether the list shows nothing, not even a deleted journal or template. Not while the journals are still
    /// being read after unlocking: the list is blank until they are.
    var listIsEmpty: Bool {
        !model.openingJournals && model.entries.isEmpty
            && (!model.showingTrash
                || (model.filteredDeletedJournals.isEmpty && model.filteredDeletedTemplates.isEmpty))
    }
}

#if os(macOS)
    extension RootView {
        /// Publishes the command to the menu bar, and leaves the mode for what needs the list or the sidebar:
        /// searching, and New Journal, which shows the new journal in the sidebar.
        func editorOnlyBehavior(_ navigation: some View) -> some View {
            navigation
                .focusedSceneValue(
                    \.editorOnly, EditorOnlyCommand(active: windowColumns.editorOnly, toggle: toggleEditorOnly)
                )
                .onValueChange(of: newJournal) { presented in
                    if presented { leaveEditorOnly() }
                }
                .onValueChange(of: editor.searchRequested) { requested in
                    if requested { leaveEditorOnly() }
                }
        }

        /// The split view controller animates the columns, without animation when Reduce Motion is on.
        func toggleEditorOnly() {
            let entering = !windowColumns.editorOnly
            windowColumns.toggleEditorOnly()
            // The list may have had keyboard focus; writing continues in the editor, which stays on screen.
            if entering, !(NSApp.keyWindow?.firstResponder is NSTextView) { editor.perform(.focus) }
        }

        func leaveEditorOnly() {
            guard windowColumns.editorOnly else { return }
            windowColumns.leaveEditorOnly()
        }
    }
#endif
