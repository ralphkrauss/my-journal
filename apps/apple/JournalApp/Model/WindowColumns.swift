#if os(macOS)
    import Foundation

    /// The columns a Mac journal window shows, the layout View ▸ Show Editor Only replaced, and the widths the person
    /// gave the sidebar and the list. Stored per window.
    struct WindowColumns: Equatable {
        enum Plain: String, Equatable {
            case all, sidebarHidden
        }

        enum Layout: Equatable {
            case all, sidebarHidden
            /// Only the editor, remembering the layout to return to.
            case editorOnly(returnTo: Plain)

            var sidebarCollapsed: Bool { self != .all }
            var listCollapsed: Bool {
                if case .editorOnly = self { return true }
                return false
            }
        }

        private(set) var layout = Layout.all
        /// The divider positions the person chose, applied when the window opens.
        var sidebarWidth: Double?
        var listWidth: Double?

        var editorOnly: Bool { layout.listCollapsed }

        /// Show Editor Only, or Show Sidebar and List, which restores the layout the mode replaced.
        mutating func toggleEditorOnly() {
            switch layout {
            case .editorOnly(let plain): layout = Self.layout(plain)
            case .all: layout = .editorOnly(returnTo: .all)
            case .sidebarHidden: layout = .editorOnly(returnTo: .sidebarHidden)
            }
        }

        /// Search and New Journal return to the layout the mode replaced.
        mutating func leaveEditorOnly() {
            guard case .editorOnly(let plain) = layout else { return }
            layout = Self.layout(plain)
        }

        /// View ▸ Show/Hide Sidebar and the sidebar button. From editor only they show every column: the person asked
        /// for the sidebar, and the remembered layout might not show it.
        mutating func toggleSidebar() {
            layout = layout == .all ? .sidebarHidden : .all
        }

        /// The split view collapsed or expanded a column itself, for example the sidebar when the window became too
        /// narrow for it.
        mutating func splitViewShowed(sidebar: Bool, list: Bool) {
            switch (sidebar, list) {
            case (true, _): layout = .all
            case (false, true): layout = .sidebarHidden
            case (false, false): if !editorOnly { layout = .editorOnly(returnTo: .sidebarHidden) }
            }
        }

        private static func layout(_ plain: Plain) -> Layout { plain == .all ? .all : .sidebarHidden }
    }

    extension WindowColumns: RawRepresentable {
        /// For `@SceneStorage`: the layout, the remembered layout and the widths, such as "editorOnly,all,230,300".
        var rawValue: String {
            let names: [String]
            switch layout {
            case .all: names = ["all", "all"]
            case .sidebarHidden: names = ["sidebarHidden", "sidebarHidden"]
            case .editorOnly(let plain): names = ["editorOnly", plain.rawValue]
            }
            let widths = [sidebarWidth, listWidth].map { $0.map { String(Int($0.rounded())) } ?? "" }
            return (names + widths).joined(separator: ",")
        }

        /// Also reads what earlier versions stored: the visible and the remembered `NavigationSplitViewVisibility`,
        /// such as "detailOnly,doubleColumn".
        init?(rawValue: String) {
            let parts = rawValue.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2, let restored = Self.plain(named: parts[1]) else { return nil }
            switch parts[0] {
            case "all": layout = .all
            case "sidebarHidden", "doubleColumn": layout = .sidebarHidden
            case "editorOnly", "detailOnly": layout = .editorOnly(returnTo: restored)
            default: return nil
            }
            if parts.count == 4 {
                sidebarWidth = Double(parts[2])
                listWidth = Double(parts[3])
            }
        }

        private static func plain(named name: String) -> Plain? {
            switch name {
            case "all": return .all
            case "sidebarHidden", "doubleColumn": return .sidebarHidden
            default: return nil
            }
        }
    }
#endif
