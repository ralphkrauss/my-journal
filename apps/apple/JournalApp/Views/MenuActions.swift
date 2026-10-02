import SwiftUI

/// A menu's commands, described once and shown both as a SwiftUI menu (context menus) and as an AppKit menu (Mac
/// toolbar menus), so the two always offer the same actions.
struct MenuAction: Identifiable {
    enum Kind {
        case command(@MainActor () -> Void)
        case submenu([MenuAction])
        case separator
    }

    let id: String
    let title: String
    let symbol: String?
    var enabled = true
    var destructive = false
    var checked = false
    let kind: Kind

    static func command(
        _ title: String, id: String? = nil, symbol: String? = nil, enabled: Bool = true, destructive: Bool = false,
        checked: Bool = false, perform: @escaping @MainActor () -> Void
    ) -> MenuAction {
        MenuAction(
            id: id ?? title, title: title, symbol: symbol, enabled: enabled, destructive: destructive, checked: checked,
            kind: .command(perform))
    }

    static func submenu(_ title: String, symbol: String?, enabled: Bool = true, _ items: [MenuAction]) -> MenuAction {
        MenuAction(id: title, title: title, symbol: symbol, enabled: enabled, kind: .submenu(items))
    }

    static func separator(_ id: String) -> MenuAction {
        MenuAction(id: "separator " + id, title: "", symbol: nil, kind: .separator)
    }
}

/// Menu actions as SwiftUI buttons, dividers and submenus.
struct MenuActionsView: View {
    let actions: [MenuAction]

    var body: some View {
        ForEach(actions) { action in
            switch action.kind {
            case .separator:
                Divider()
            case .command(let perform):
                Button(role: action.destructive ? .destructive : nil, action: perform) { label(action) }
                    .disabled(!action.enabled)
            case .submenu(let items):
                Menu {
                    MenuActionsView(actions: items)
                } label: {
                    label(action)
                }.disabled(!action.enabled)
            }
        }
    }

    @ViewBuilder private func label(_ action: MenuAction) -> some View {
        if action.checked {
            Label(action.title, systemImage: "checkmark")
        } else if let symbol = action.symbol {
            Label(action.title, systemImage: symbol)
        } else {
            Text(action.title)
        }
    }
}

#if os(macOS)
    import AppKit

    /// Menu actions as an AppKit menu, for toolbar menus.
    @MainActor
    final class MenuActionTarget: NSObject {
        private var handlers: [@MainActor () -> Void] = []

        func fill(_ menu: NSMenu, with actions: [MenuAction]) {
            handlers.removeAll()
            menu.removeAllItems()
            add(actions, to: menu)
        }

        private func add(_ actions: [MenuAction], to menu: NSMenu) {
            for action in actions {
                switch action.kind {
                case .separator:
                    menu.addItem(.separator())
                case .command(let perform):
                    let item = NSMenuItem(title: action.title, action: #selector(run(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = handlers.count
                    handlers.append(perform)
                    configure(item, action)
                    menu.addItem(item)
                case .submenu(let items):
                    let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
                    let submenu = NSMenu(title: action.title)
                    submenu.autoenablesItems = false
                    add(items, to: submenu)
                    item.submenu = submenu
                    configure(item, action)
                    menu.addItem(item)
                }
            }
        }

        private func configure(_ item: NSMenuItem, _ action: MenuAction) {
            item.isEnabled = action.enabled
            item.state = action.checked ? .on : .off
            if let symbol = action.symbol, !action.checked {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
        }

        @objc private func run(_ sender: NSMenuItem) {
            guard handlers.indices.contains(sender.tag) else { return }
            handlers[sender.tag]()
        }
    }
#endif
