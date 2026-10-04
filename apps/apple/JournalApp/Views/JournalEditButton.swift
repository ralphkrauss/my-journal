#if os(iOS)
    import SwiftUI

    /// Edit and Done for the Journals list on iPhone and iPad, after New Journal as its own button, as in Notes'
    /// Folders (journal-order.md). Hidden while there's no journal in use.
    struct JournalEditToolbarItems: ToolbarContent {
        @EnvironmentObject private var model: AppModel
        var placement: ToolbarItemPlacement = .automatic

        var body: some ToolbarContent {
            if !model.journals.isEmpty {
                if #available(iOS 26.0, *) { ToolbarSpacer(.fixed, placement: placement) }
                ToolbarItem(placement: placement) { JournalEditButton() }
            }
        }
    }

    struct JournalEditButton: View {
        @EnvironmentObject private var model: AppModel

        var body: some View {
            if model.editingJournals {
                if #available(iOS 26.0, *) {
                    // The system's round checkmark, read as "Done".
                    Button(role: .confirm) { setEditing(false) }
                } else {
                    Button {
                        setEditing(false)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                }
            } else {
                Button("Edit") { setEditing(true) }.disabled(!model.isReady || model.locked || model.replacingVault)
            }
        }
        private func setEditing(_ editing: Bool) {
            withAnimation(AppModel.listAnimation) { model.editingJournals = editing }
        }
    }
#endif
