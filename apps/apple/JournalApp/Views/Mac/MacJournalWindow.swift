#if os(macOS)
    import AppKit
    import SwiftUI

    /// The journal window's columns and toolbar, in AppKit's split view controller and toolbar. `RootView` builds the
    /// columns' SwiftUI contents and the toolbar's configuration on every update.
    struct MacJournalWindow: NSViewControllerRepresentable {
        @Binding var columns: WindowColumns
        let sidebar: AnyView
        let list: AnyView
        let detail: AnyView
        let toolbar: JournalToolbarConfiguration
        let focusEditor: @MainActor () -> Void

        func makeNSViewController(context: Context) -> JournalSplitViewController {
            let controller = JournalSplitViewController(columns: columns)
            updateNSViewController(controller, context: context)
            return controller
        }

        func updateNSViewController(_ controller: JournalSplitViewController, context: Context) {
            let binding = $columns
            controller.columnsChanged = { binding.wrappedValue = $0 }
            controller.focusEditor = focusEditor
            controller.sidebarHost.rootView = sidebar
            controller.listHost.rootView = list
            controller.detailHost.rootView = detail
            if controller.columns != columns {
                // After SwiftUI's update, as the columns' own SwiftUI contents lay out when they change, and with the
                // columns wanted then: the controller may have changed them itself meanwhile and reported it.
                DispatchQueue.main.async {
                    let wanted = binding.wrappedValue
                    if controller.columns != wanted { controller.apply(wanted, animated: true) }
                }
            }
            controller.toolbarController.update(toolbar)
        }

        /// The window's size, whatever the columns' minimums add up to: a window too narrow for the sidebar hides it
        /// rather than overflowing.
        func sizeThatFits(
            _ proposal: ProposedViewSize, nsViewController: JournalSplitViewController, context: Context
        ) -> CGSize? {
            nsViewController.windowSizeProposed()
            return proposal.replacingUnspecifiedDimensions()
        }

        static func dismantleNSViewController(_ controller: JournalSplitViewController, coordinator: ()) {
            if let window = controller.view.window { controller.toolbarController.uninstall(from: window) }
        }
    }
#endif
