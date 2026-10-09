#if os(macOS)
    import XCTest

    @testable import Journal

    /// View ▸ Show Editor Only: the layout it replaces comes back, and each window keeps its columns across relaunches.
    final class EditorOnlyTests: XCTestCase {
        func testLeavingRestoresTheLayoutTheModeReplacedAndSurvivesRelaunch() throws {
            var columns = WindowColumns()
            columns.toggleSidebar()
            columns.toggleEditorOnly()
            XCTAssertTrue(columns.editorOnly)
            // Each window keeps its mode, the layout to return to and its widths.
            columns.sidebarWidth = 250
            columns.listWidth = 340
            var restored = try XCTUnwrap(WindowColumns(rawValue: columns.rawValue))
            XCTAssertEqual(restored, columns)
            restored.toggleEditorOnly()
            XCTAssertEqual(restored.layout, .sidebarHidden, "The list comes back without the sidebar hidden before")

            var searching = WindowColumns()
            searching.toggleEditorOnly()
            searching.leaveEditorOnly()
            XCTAssertEqual(searching.layout, .all)
            searching.leaveEditorOnly()
            XCTAssertEqual(searching.layout, .all, "Searching outside the mode changes nothing")
        }

        /// Show Sidebar asks for the sidebar: from editor only it shows every column, whatever the mode replaced.
        func testShowingTheSidebarFromEditorOnlyShowsEveryColumn() {
            var columns = WindowColumns()
            columns.toggleSidebar()
            columns.toggleEditorOnly()
            columns.toggleSidebar()
            XCTAssertEqual(columns.layout, .all)
        }
    }
#endif
