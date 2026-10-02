import JournalCore
import SwiftUI

/// The toolbars of the journal window: the entry list's controls and the editor's. On the Mac, AppKit's toolbar
/// shows them (JournalToolbarController).
extension RootView {
    var searchPrompt: String { Self.searchPrompt(for: model) }
    /// The search field's placeholder, which is also its tooltip and accessibility label.
    static func searchPrompt(for model: AppModel) -> String {
        if model.showingAllEntries { return "Search All Entries" }
        if model.showingUnavailable { return "Search Unavailable Entries" }
        if model.showingTrash { return "Search Deleted Items" }
        if model.showingTemplates { return "Search Templates" }
        guard let journal = model.selectedJournal else { return "Search Journal" }
        return "Search \(journal.title.isEmpty ? "Untitled Journal" : journal.title)"
    }
    #if os(iOS)
        @ToolbarContentBuilder var listToolbar: some ToolbarContent {
            if case .journal = model.destination, let journal = model.selectedJournal {
                ToolbarItem(placement: .primaryAction) { JournalMoreMenu(journal: journal) }
            }
            if #available(iOS 26.0, *) { DefaultToolbarItem(kind: .search, placement: .bottomBar) }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                creationActions.labelStyle(.iconOnly)
            }
        }
        @ToolbarContentBuilder var mainToolbar: some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                entryMenu
                if editor.editing {
                    Button {
                        editor.finishEditing()
                        Task { _ = await model.finishPendingSave() }
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .accessibilityIdentifier("Finish Editing")
                }
            }
        }
        var insertImageButton: some View {
            InsertImageMenu(editor: editor).disabled(!model.canEdit)
        }
        var sourceModeButton: some View {
            let title = editor.sourceMode ? "View Preview" : "View Source"
            let previewUnavailable = model.draft?.document.requiresMarkdownSource == true
            return Button {
                editor.toggleSourceMode()
            } label: {
                Label(
                    title, systemImage: editor.sourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
            }
            .iconHelp(previewUnavailable ? "Preview isn’t available for this entry" : title)
            .disabled(!model.canEdit || previewUnavailable)
        }
    #endif
    /// Sync Status stays quiet while syncing normally or retrying by itself, and shows while items wait or the
    /// person must act (docs/design/sync-health-and-recovery.md §4.2).
    var showsSyncStatus: Bool {
        model.connection != nil && (model.pendingSync || model.syncNeedsAttention)
    }
    var syncStatusMessage: String { model.syncError ?? "Saved on this device. Waiting to sync." }
    var syncStatusSymbol: String { model.syncStatusSymbol() }
    @ViewBuilder var syncMenu: some View {
        if showsSyncStatus {
            Menu {
                Text(syncStatusMessage)
                let action = model.syncStatusAction
                Button(action.title) {
                    model.perform(action) { model.encryption.signInRequested = true }
                }
                Button("Sync Settings…") { model.openSyncSettings() }
            } label: {
                Label("Sync Status", systemImage: syncStatusSymbol)
            }.iconHelp("Sync Status")
        }
    }
}
