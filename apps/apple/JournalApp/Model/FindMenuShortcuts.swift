#if os(macOS)
    import AppKit

    /// Notes’ Find shortcuts: Edit ▸ Find ▸ Find and Replace… is ⇧⌘F, which leaves ⌥⌘F for Search Entries (owner
    /// decision, 2026-09-27). The system Find menu gives Find and Replace… ⌥⌘F, and SwiftUI leaves out a shortcut of
    /// its own that is already taken, so the system item changes as soon as it is added, before the app’s commands
    /// are, and again whenever the menu bar is rebuilt or changed.
    @MainActor final class FindMenuShortcuts: NSObject {
        static let shared = FindMenuShortcuts()
        private var installed = false
        /// Changing the item posts a change notification of its own.
        private var applying = false

        func install() {
            guard !installed else { return }
            installed = true
            for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(menuChanged(_:)), name: name, object: nil)
            }
            if let menu = NSApp.mainMenu { apply(to: menu) }
        }

        /// Menus change on the main thread, so the item is changed before the next key press is handled.
        @objc private func menuChanged(_ notification: Notification) {
            guard let menu = notification.object as? NSMenu else { return }
            apply(to: menu)
        }

        func apply(to menu: NSMenu) {
            guard !applying else { return }
            applying = true
            defer { applying = false }
            update(menu)
        }
        private func update(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { update(submenu) }
                guard
                    [
                        #selector(NSTextView.performFindPanelAction(_:)),
                        #selector(NSResponder.performTextFinderAction(_:)),
                    ]
                    .contains(item.action),
                    item.tag == NSTextFinder.Action.showReplaceInterface.rawValue,
                    item.keyEquivalent != "f" || item.keyEquivalentModifierMask != [.command, .shift]
                else { continue }
                item.keyEquivalentModifierMask = [.command, .shift]
                item.keyEquivalent = "f"
            }
        }
    }
#endif
