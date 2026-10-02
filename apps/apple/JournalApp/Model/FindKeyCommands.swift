#if os(iOS)
    import UIKit

    /// Receives the menu bar as it is built on iPad, to give it Notes’ Find shortcuts.
    final class JournalAppDelegate: UIResponder, UIApplicationDelegate {
        override func buildMenu(with builder: UIMenuBuilder) {
            super.buildMenu(with: builder)
            guard builder.system == .main else { return }
            FindKeyCommands.reassign(in: builder)
        }
    }

    /// Notes’ Find shortcuts on an iPad keyboard: Search Entries is ⌥⌘F and Edit ▸ Find ▸ Find and Replace… is ⇧⌘F
    /// (owner decision, 2026-09-27). The system gives Find and Replace… ⌥⌘F, and a command whose shortcut is already
    /// taken is left out of the menu bar, so Search Entries is added with ⇧⌘F and the two shortcuts are swapped here,
    /// once the app’s commands are in place.
    @MainActor enum FindKeyCommands {
        static let searchEntriesTitle = "Search Entries"

        static func reassign(in builder: UIMenuBuilder) {
            guard let edit = builder.menu(for: .edit) else { return }
            builder.replace(menu: .edit, with: reassigned(edit))
        }
        private static func reassigned(_ menu: UIMenu) -> UIMenu {
            menu.replacingChildren(
                menu.children.map { element in
                    if let submenu = element as? UIMenu { return reassigned(submenu) }
                    guard let command = element as? UIKeyCommand, command.input == "f" else { return element }
                    if command.action == #selector(UIResponderStandardEditActions.findAndReplace(_:)) {
                        return copy(command, modifiers: [.command, .shift])
                    }
                    if command.title == searchEntriesTitle, command.modifierFlags == [.command, .shift] {
                        return copy(command, modifiers: [.command, .alternate])
                    }
                    return command
                })
        }
        /// The same command, which the app still recognizes by its action and property list, with other modifiers.
        private static func copy(_ command: UIKeyCommand, modifiers: UIKeyModifierFlags) -> UIKeyCommand {
            guard let action = command.action, let input = command.input else { return command }
            return UIKeyCommand(
                title: command.title, image: command.image, action: action, input: input, modifierFlags: modifiers,
                propertyList: command.propertyList, alternates: command.alternates,
                discoverabilityTitle: command.discoverabilityTitle, attributes: command.attributes, state: command.state
            )
        }
    }
#endif
