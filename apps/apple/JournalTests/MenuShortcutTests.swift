#if os(macOS)
    import AppKit
    import XCTest

    @MainActor
    final class MenuShortcutTests: XCTestCase {
        /// Two commands with one shortcut make one of them unreachable, and can run the wrong one (such as locking
        /// the app instead of starting a task list).
        func testMenuBarShortcutsAreUnique() throws {
            let menu = try XCTUnwrap(NSApp.mainMenu)
            var owners: [String: String] = [:]
            var duplicates: [String] = []
            func visit(_ menu: NSMenu, path: String) {
                // SwiftUI fills menus when they open; update so every command is present.
                menu.update()
                for item in menu.items {
                    let title = path + " ▸ " + item.title
                    // Services come from other apps and the person's settings, and appear once the system has
                    // loaded them; they aren't the app's shortcuts.
                    if let submenu = item.submenu, submenu !== NSApp.servicesMenu { visit(submenu, path: title) }
                    guard !item.keyEquivalent.isEmpty, !item.isAlternate else { continue }
                    let flags = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
                    let key = "\(flags.rawValue)-\(item.keyEquivalent.lowercased())"
                    if let owner = owners[key] {
                        duplicates.append("\(owner) and \(title)")
                    } else {
                        owners[key] = title
                    }
                }
            }
            visit(menu, path: "")
            XCTAssertNotNil(owners.values.first { $0.hasSuffix("▸ Task List") }, "The Format menu must be checked.")
            XCTAssertEqual(duplicates, [])
            // As in Notes. The system Find menu would otherwise keep Find and Replace… on ⌥⌘F and win over it.
            let command = NSEvent.ModifierFlags.command.rawValue
            let option = command | NSEvent.ModifierFlags.option.rawValue
            let shift = command | NSEvent.ModifierFlags.shift.rawValue
            XCTAssertEqual(owners["\(option)-f"], " ▸ Edit ▸ Search Entries")
            XCTAssertEqual(owners["\(shift)-f"], " ▸ Edit ▸ Find ▸ Find and Replace…")
            XCTAssertEqual(owners["\(command)-f"], " ▸ Edit ▸ Find ▸ Find…")
            // Show Editor Only as in Bear; Previous and Next Entry leave ⌘↑ and ⌘↓ to text navigation.
            XCTAssertEqual(owners["\(shift)-d"], " ▸ View ▸ Show Editor Only")
            // AppKit's up and down arrow key equivalents.
            XCTAssertEqual(owners["\(option)-\u{F700}"], " ▸ View ▸ Previous Entry")
            XCTAssertEqual(owners["\(option)-\u{F701}"], " ▸ View ▸ Next Entry")
        }

        /// Zoom In shows ⌘+, but on the =/+ key it must also work without Shift, as Zoom Out does with ⌘-.
        func testZoomInAnswersCommandEqualsWithoutShift() throws {
            let menu = try XCTUnwrap(NSApp.mainMenu)
            let zoomIn = try XCTUnwrap(Self.item(titled: "Zoom In", in: menu))
            XCTAssertEqual(zoomIn.keyEquivalent, "+", "The menu shows ⌘+.")
            let commandEquals = try XCTUnwrap(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: .command,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, characters: "=",
                    charactersIgnoringModifiers: "=", isARepeat: false, keyCode: 24))
            let zoomInID = ObjectIdentifier(zoomIn)
            let sent = expectation(forNotification: NSMenu.didSendActionNotification, object: nil) { notification in
                (notification.userInfo?["MenuItem"] as AnyObject?).map(ObjectIdentifier.init) == zoomInID
            }
            // As the app receives the key press, through its event monitors.
            NSApp.sendEvent(commandEquals)
            wait(for: [sent], timeout: 2)
        }

        private static func item(titled title: String, in menu: NSMenu) -> NSMenuItem? {
            // SwiftUI fills menus when they open; update so every command is present.
            menu.update()
            for item in menu.items {
                if item.title == title { return item }
                if let submenu = item.submenu, submenu !== NSApp.servicesMenu,
                    let found = Self.item(titled: title, in: submenu)
                {
                    return found
                }
            }
            return nil
        }
    }
#endif
