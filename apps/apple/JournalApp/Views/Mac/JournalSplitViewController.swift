#if os(macOS)
    import AppKit
    import SwiftUI

    /// The journal window's columns: journals in the sidebar, entries in the list and the editor, in AppKit's split
    /// view as in Notes. The columns' contents stay SwiftUI. It also owns the window's toolbar, whose sections follow
    /// the columns' dividers.
    @MainActor
    final class JournalSplitViewController: NSSplitViewController {
        static let sidebarWidths = (minimum: 210.0, preferred: 230.0, maximum: 320.0)
        /// Room for the list's toolbar section. With the sidebar hidden, it holds the window and sidebar buttons, the
        /// collection's title and Journal Actions, and AppKit needs about 355 points for them: any narrower and the
        /// section, and every item after it, would move past the divider. One minimum for both layouts keeps the
        /// list's width when the sidebar hides.
        static let listWidths = (minimum: 360.0, preferred: 360.0, maximum: 460.0)
        /// Room for every editor item with Sync Status and a collapsed search field, so none overflow (440 with the
        /// divider). With the list beside it, the window's 801-point minimum.
        static let detailMinimum = 439.0

        let sidebarHost = NSHostingController(rootView: AnyView(EmptyView()))
        let listHost = NSHostingController(rootView: AnyView(EmptyView()))
        let detailHost = NSHostingController(rootView: AnyView(EmptyView()))
        let sidebarItem: NSSplitViewItem
        let listItem: NSSplitViewItem
        let detailItem: NSSplitViewItem
        let toolbarController = JournalToolbarController()

        /// The columns shown, or being animated to.
        private(set) var columns: WindowColumns
        /// Reports changes the person made here (the sidebar button, a divider) or the split view made itself.
        var columnsChanged: (WindowColumns) -> Void = { _ in }
        /// Gives the editor keyboard focus when the column that had it hides.
        var focusEditor: () -> Void = {}

        /// The column change being applied, whose collapses aren't reported back as the person's.
        private var transition: Int?
        private var transitionCount = 0
        private var observations: [NSKeyValueObservation] = []
        private var widthsApplied = false
        private var widthSave: DispatchWorkItem?

        init(columns: WindowColumns) {
            self.columns = columns
            for host in [sidebarHost, listHost, detailHost] {
                // The columns never set the window's title or toolbar; the toolbar controller does.
                host.sceneBridgingOptions = []
                host.sizingOptions = []
            }
            sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
            listItem = NSSplitViewItem(contentListWithViewController: listHost)
            detailItem = NSSplitViewItem(viewController: detailHost)
            super.init(nibName: nil, bundle: nil)
            configureItems()
            // Restored before the window shows the columns, so it never flashes another layout.
            sidebarItem.isCollapsed = columns.layout.sidebarCollapsed
            listItem.isCollapsed = columns.layout.listCollapsed
            for item in [sidebarItem, listItem, detailItem] { addSplitViewItem(item) }
            toolbarController.showColumns(sidebar: !sidebarItem.isCollapsed, list: !listItem.isCollapsed)
            observeCollapses()
        }

        required init?(coder: NSCoder) { nil }

        private func configureItems() {
            sidebarItem.minimumThickness = Self.sidebarWidths.minimum
            sidebarItem.maximumThickness = Self.sidebarWidths.maximum
            // The sidebar is the first to give way when the window narrows (windowSizeProposed). AppKit's own collapse
            // also fired while SwiftUI first sized the columns, hiding the sidebar of a window that had room for it.
            sidebarItem.canCollapse = true
            sidebarItem.canCollapseFromWindowResize = false
            sidebarItem.holdingPriority = NSLayoutConstraint.Priority(270)
            listItem.minimumThickness = Self.listWidths.minimum
            listItem.maximumThickness = Self.listWidths.maximum
            // Collapsed only for editor only: dividers and window resizes stop at its minimum.
            listItem.canCollapse = true
            listItem.canCollapseFromWindowResize = false
            listItem.holdingPriority = NSLayoutConstraint.Priority(260)
            detailItem.minimumThickness = Self.detailMinimum
            detailItem.canCollapse = false
            // Resizing the window goes to the editor first.
            detailItem.holdingPriority = NSLayoutConstraint.Priority(250)
            for item in [sidebarItem, listItem, detailItem] { item.titlebarSeparatorStyle = .none }
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            toolbarController.splitView = splitView
            NotificationCenter.default.addObserver(
                self, selector: #selector(dividerMoved), name: NSSplitView.didResizeSubviewsNotification,
                object: splitView)
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            guard splitView.bounds.width > 0 else { return }
            if !widthsApplied {
                widthsApplied = true
                applyWidths()
            }
        }

        /// The width the shown columns need at their minimums.
        private func minimumWidth(sidebar: Bool) -> Double {
            var width = Self.detailMinimum
            if !listItem.isCollapsed { width += Self.listWidths.minimum + splitView.dividerThickness }
            if sidebar { width += Self.sidebarWidths.minimum + splitView.dividerThickness }
            return width
        }

        /// SwiftUI is laying out the window. A window too narrow for every column hides the sidebar, as in Notes,
        /// never the list or the editor: the split view would otherwise keep every minimum and overflow the window.
        func windowSizeProposed() {
            // After the layout in progress, from the window's actual width: SwiftUI also proposes sizes to learn the
            // columns' minimum and ideal sizes.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.widthsApplied, !self.sidebarItem.isCollapsed, self.transition == nil,
                    let window = self.view.window, window.isVisible, let width = window.contentView?.bounds.width,
                    width < self.minimumWidth(sidebar: true)
                else { return }
                self.sidebarItem.isCollapsed = true
            }
        }

        /// A column returning to a window too narrow for it widens the window, as AppKit does for a sidebar.
        private func widenWindow(for layout: WindowColumns.Layout) {
            guard let window = view.window, !window.styleMask.contains(.fullScreen) else { return }
            var needed = Self.detailMinimum
            if !layout.listCollapsed { needed += Self.listWidths.minimum + splitView.dividerThickness }
            if !layout.sidebarCollapsed { needed += Self.sidebarWidths.minimum + splitView.dividerThickness }
            let missing = needed - splitView.bounds.width
            guard missing > 0 else { return }
            var frame = window.frame
            frame.size.width += missing
            if let screen = window.screen?.visibleFrame, frame.maxX > screen.maxX {
                frame.origin.x = max(screen.minX, screen.maxX - frame.width)
            }
            window.setFrame(frame, display: true, animate: false)
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            guard let window = view.window else { return }
            toolbarController.install(in: window)
            (window.delegate as? WindowDelegateProxy)?.splitController = self
        }

        override func viewWillDisappear() {
            super.viewWillDisappear()
            guard let window = view.window else { return }
            toolbarController.uninstall(from: window)
        }

        // MARK: Layout

        /// Shows `target`'s columns, animated unless Reduce Motion is on.
        func apply(_ target: WindowColumns, animated: Bool) {
            let layout = target.layout
            let previous = columns.layout
            columns = target
            guard layout != previous else { return }
            moveFocus(before: layout)
            widenWindow(for: layout)
            // Toolbar items of a column that hides leave before it does; those of a column that returns come back
            // once it's in place, so none ride over another column or pass through the overflow menu.
            toolbarController.showColumns(
                sidebar: !previous.sidebarCollapsed && !layout.sidebarCollapsed,
                list: !previous.listCollapsed && !layout.listCollapsed,
                listDivider: !previous.listCollapsed || !layout.listCollapsed)
            transitionCount += 1
            let current = transitionCount
            transition = current
            guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                sidebarItem.isCollapsed = layout.sidebarCollapsed
                listItem.isCollapsed = layout.listCollapsed
                finishTransition(current)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.allowsImplicitAnimation = true
                if sidebarItem.isCollapsed != layout.sidebarCollapsed {
                    sidebarItem.animator().isCollapsed = layout.sidebarCollapsed
                }
                if listItem.isCollapsed != layout.listCollapsed {
                    listItem.animator().isCollapsed = layout.listCollapsed
                }
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.finishTransition(current) }
            }
            // AppKit doesn't report the end of an animation that doesn't run, for example while the screen is locked.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.finishTransition(current) }
        }

        private func finishTransition(_ finished: Int) {
            guard transition == finished else { return }
            transition = nil
            // Where the animation left the columns, if it didn't finish.
            sidebarItem.isCollapsed = columns.layout.sidebarCollapsed
            listItem.isCollapsed = columns.layout.listCollapsed
            toolbarController.showColumns(sidebar: !sidebarItem.isCollapsed, list: !listItem.isCollapsed)
        }

        /// View ▸ Show/Hide Sidebar, ⌃⌘S and the sidebar button, through the same path as every other column
        /// change, so Reduce Motion applies. From editor only they show every column.
        override func toggleSidebar(_ sender: Any?) {
            var updated = columns
            updated.toggleSidebar()
            columnsChanged(updated)
            apply(updated, animated: true)
        }

        /// Only editor only collapses the list; dragging its divider stops at the list's minimum width.
        override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            if subview === listHost.view, transition == nil { return false }
            return super.splitView(splitView, canCollapseSubview: subview)
        }

        private func observeCollapses() {
            observations = [sidebarItem, listItem].map { item in
                item.observe(\.isCollapsed, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.splitViewCollapsed() }
                }
            }
        }

        /// The split view collapsed or expanded a column itself: the window became too narrow for the sidebar, or
        /// the person dragged its divider.
        private func splitViewCollapsed() {
            guard transition == nil else { return }
            var updated = columns
            updated.splitViewShowed(sidebar: !sidebarItem.isCollapsed, list: !listItem.isCollapsed)
            toolbarController.showColumns(sidebar: !sidebarItem.isCollapsed, list: !listItem.isCollapsed)
            guard updated != columns else { return }
            columns = updated
            columnsChanged(updated)
        }

        /// A column that hides can't keep keyboard focus: it moves to the list, or to the editor in editor only.
        private func moveFocus(before layout: WindowColumns.Layout) {
            guard let window = view.window, let responder = window.firstResponder as? NSView else { return }
            let inSidebar = responder.isDescendant(of: sidebarHost.view)
            let inList = responder.isDescendant(of: listHost.view)
            if layout.listCollapsed, inSidebar || inList {
                window.makeFirstResponder(nil)
                focusEditor()
            } else if layout.sidebarCollapsed, inSidebar {
                window.makeFirstResponder(Self.firstTable(in: listHost.view))
            }
        }

        private static func firstTable(in view: NSView) -> NSView? {
            if view is NSTableView { return view }
            return view.subviews.lazy.compactMap { firstTable(in: $0) }.first
        }

        // MARK: Widths

        private func applyWidths() {
            let sidebar = columns.sidebarWidth ?? Self.sidebarWidths.preferred
            let list = columns.listWidth ?? Self.listWidths.preferred
            if !sidebarItem.isCollapsed { splitView.setPosition(sidebar, ofDividerAt: 0) }
            if !listItem.isCollapsed {
                let start = sidebarItem.isCollapsed ? 0 : sidebarHost.view.frame.maxX + splitView.dividerThickness
                splitView.setPosition(start + list, ofDividerAt: 1)
            }
        }

        /// Keeps the widths the person drags the dividers to, not those a window resize or a column change gives.
        @objc private func dividerMoved() {
            guard widthsApplied, transition == nil, NSApp.currentEvent?.type == .leftMouseDragged,
                view.window?.inLiveResize == false
            else { return }
            widthSave?.cancel()
            let save = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.saveWidths() }
            }
            widthSave = save
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: save)
        }

        private func saveWidths() {
            var updated = columns
            if !sidebarItem.isCollapsed { updated.sidebarWidth = sidebarHost.view.frame.width }
            if !listItem.isCollapsed { updated.listWidth = listHost.view.frame.width }
            guard updated != columns else { return }
            columns = updated
            columnsChanged(updated)
        }
    }
#endif
