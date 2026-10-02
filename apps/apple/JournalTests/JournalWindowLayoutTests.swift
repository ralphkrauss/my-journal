#if os(macOS)
    import AppKit
    import SwiftUI
    import XCTest

    @testable import Journal

    /// The journal window's AppKit columns and toolbar: each toolbar section holds its column's items in every layout,
    /// so none ride over another column, and the sidebar button and narrow windows change the columns as in Notes.
    @MainActor
    final class JournalWindowLayoutTests: XCTestCase {
        func testToolbarSectionsFollowTheColumnsInEveryLayout() async throws {
            let host = LayoutWindow(columns: WindowColumns())
            defer { host.close() }
            try await host.waitFor(.all)
            XCTAssertEqual(host.sections.sidebar, ["newJournal", "NSToolbarToggleSidebarItem"])
            XCTAssertEqual(host.sections.list, ["NSToolbarFlexibleSpaceItem", "journalActions"])
            XCTAssertEqual(host.sections.editor.first, "newEntry")
            XCTAssertEqual(host.sections.editor.last, "search", "Search is last, as in Notes")

            // New Journal leaves with the sidebar and returns once it's back.
            host.controller.toggleSidebar(nil)
            try await host.waitFor(.sidebarHidden)
            XCTAssertEqual(host.sections.sidebar, ["NSToolbarToggleSidebarItem"])
            XCTAssertTrue(host.sections.list.contains("journalActions"))
            host.controller.toggleSidebar(nil)
            try await host.waitFor(.all)
            XCTAssertEqual(host.sections.sidebar, ["newJournal", "NSToolbarToggleSidebarItem"])

            // Editor only: the list's items and separator go, and so does the title; the editor's stay.
            host.state.columns.toggleEditorOnly()
            try await host.waitFor(.editorOnly(returnTo: .all))
            XCTAssertEqual(host.sections.sidebar, ["NSToolbarToggleSidebarItem"])
            XCTAssertFalse(host.identifiers.contains("journalActions"))
            XCTAssertFalse(host.identifiers.contains("listSeparator"))
            XCTAssertEqual(host.window.titleVisibility, .hidden)
            XCTAssertTrue(host.identifiers.contains("newEntry"))
        }

        /// Show Sidebar asks for the sidebar: from editor only it shows every column, whatever the mode replaced, while
        /// Show Sidebar and List returns to that layout.
        func testShowSidebarFromEditorOnlyShowsEveryColumn() async throws {
            var columns = WindowColumns()
            columns.toggleSidebar()
            columns.toggleEditorOnly()
            // A window restored in the mode shows it at once, without first showing the columns.
            let host = LayoutWindow(columns: columns)
            defer { host.close() }
            XCTAssertTrue(host.controller.sidebarItem.isCollapsed)
            XCTAssertTrue(host.controller.listItem.isCollapsed)
            try await host.waitFor(.editorOnly(returnTo: .sidebarHidden))

            host.controller.toggleSidebar(nil)
            try await host.waitFor(.all)
            XCTAssertEqual(host.state.columns.layout, .all)

            host.state.columns.toggleSidebar()
            try await host.waitFor(.sidebarHidden)
            host.state.columns.toggleEditorOnly()
            try await host.waitFor(.editorOnly(returnTo: .sidebarHidden))
            host.state.columns.toggleEditorOnly()
            try await host.waitFor(.sidebarHidden)
        }

        /// A window too narrow for every column hides the sidebar, never squeezing the list or the editor, and the
        /// window remembers it.
        func testANarrowWindowHidesTheSidebar() async throws {
            let host = LayoutWindow(columns: WindowColumns())
            defer { host.close() }
            try await host.waitFor(.all)
            host.window.setContentSize(NSSize(width: 820, height: 600))
            try await host.waitFor(.sidebarHidden)
            XCTAssertEqual(host.state.columns.layout, .sidebarHidden)
            XCTAssertGreaterThanOrEqual(host.controller.detailHost.view.frame.width, 439)
        }

        /// Toolbars that share an identifier stay identical across windows; each window changes only its own.
        func testWindowsKeepTheirOwnToolbars() async throws {
            let first = LayoutWindow(columns: WindowColumns())
            defer { first.close() }
            let second = LayoutWindow(columns: WindowColumns())
            defer { second.close() }
            try await first.waitFor(.all)
            try await second.waitFor(.all)
            second.state.columns.toggleEditorOnly()
            try await second.waitFor(.editorOnly(returnTo: .all))
            XCTAssertTrue(first.identifiers.contains("journalActions"))
            XCTAssertTrue(first.identifiers.contains("newJournal"))
            XCTAssertFalse(second.identifiers.contains("journalActions"))
        }
    }

    @MainActor
    private final class LayoutState: ObservableObject {
        @Published var columns: WindowColumns
        init(columns: WindowColumns) { self.columns = columns }
    }

    /// The columns and toolbar with placeholder contents, as the journal window sets them up.
    private struct LayoutView: View {
        @ObservedObject var state: LayoutState

        var body: some View {
            MacJournalWindow(
                columns: $state.columns, sidebar: AnyView(Text("Journals")), list: AnyView(Text("Entries")),
                detail: AnyView(Text("Editor")), toolbar: configuration, focusEditor: {}
            )
            .ignoresSafeArea()
        }

        private var configuration: JournalToolbarConfiguration {
            var configuration = JournalToolbarConfiguration()
            configuration.editorOnly = state.columns.editorOnly
            configuration.toggleEditorOnly = { [state] in state.columns.toggleEditorOnly() }
            return configuration
        }
    }

    @MainActor
    private final class LayoutWindow {
        let state: LayoutState
        let window: NSWindow

        init(columns: WindowColumns) {
            state = LayoutState(columns: columns)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.toolbarStyle = .unified
            let controller = NSHostingController(rootView: LayoutView(state: state))
            controller.sizingOptions = []
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 1100, height: 700))
            window.orderFront(nil)
        }

        func close() { window.close() }

        var controller: JournalSplitViewController {
            guard let controller = Self.controller(in: window.contentView) else {
                preconditionFailure("The window has no journal columns")
            }
            return controller
        }

        var identifiers: [String] { window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [] }

        /// The toolbar's items between its tracking separators.
        var sections: (sidebar: [String], list: [String], editor: [String]) {
            let items = identifiers
            let sidebarEnd = items.firstIndex(of: NSToolbarItem.Identifier.sidebarTrackingSeparator.rawValue)
            guard let sidebarEnd else { return ([], [], items) }
            let listEnd = items.firstIndex(of: "listSeparator") ?? sidebarEnd
            return (
                Array(items[..<sidebarEnd]), Array(items[(sidebarEnd + 1)..<max(listEnd, sidebarEnd + 1)]),
                Array(items[(listEnd + 1)...])
            )
        }

        /// Waits until the columns show `layout` and the toolbar has caught up, once any animation has finished.
        func waitFor(_ layout: WindowColumns.Layout, file: StaticString = #filePath, line: UInt = #line) async throws {
            let deadline = Date().addingTimeInterval(5)
            while !shows(layout), Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertTrue(shows(layout), "\(layout) \(identifiers)", file: file, line: line)
        }

        private func shows(_ layout: WindowColumns.Layout) -> Bool {
            guard let controller = Self.controller(in: window.contentView), controller.columns.layout == layout else {
                return false
            }
            let columnsMatch =
                controller.sidebarItem.isCollapsed == layout.sidebarCollapsed
                && controller.listItem.isCollapsed == layout.listCollapsed
            let toolbarMatches =
                identifiers.contains("newJournal") == !layout.sidebarCollapsed
                && identifiers.contains("journalActions") == !layout.listCollapsed
                && identifiers.contains("listSeparator") == !layout.listCollapsed
            return columnsMatch && toolbarMatches
        }

        private static func controller(in view: NSView?) -> JournalSplitViewController? {
            guard let view else { return nil }
            if let controller = (view as? NSSplitView)?.delegate as? JournalSplitViewController { return controller }
            return view.subviews.lazy.compactMap { controller(in: $0) }.first
        }
    }
#endif
