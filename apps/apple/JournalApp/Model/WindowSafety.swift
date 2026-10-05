#if os(macOS)
    import AppKit
    import SwiftUI
    import JournalCore
    import UniformTypeIdentifiers

    @MainActor
    final class ApplicationDelegate: NSObject, NSApplicationDelegate {
        weak var model: AppModel?
        private var lockObserver: NSObjectProtocol?
        func applicationWillFinishLaunching(_ notification: Notification) {
            // One journal window: no tab bar or tab commands that could never do anything.
            NSWindow.allowsAutomaticWindowTabbing = false
            // Before the menu bar is built, so Search Entries can have ⌥⌘F.
            FindMenuShortcuts.shared.install()
            ZoomInShortcut.shared.install()
        }
        func applicationDidFinishLaunching(_ notification: Notification) {
            lockObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.model?.lock() }
            }
        }
        func applicationWillTerminate(_ notification: Notification) {
            // A copied recovery key never outlives My Journal on the clipboard.
            SensitivePasteboard.clear()
        }
        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            guard let model else { return .terminateNow }
            Task {
                if await model.flush() {
                    // Writing reaches the server now rather than at the next launch, unless that takes long.
                    await model.sendWritingBeforeQuitting(within: 3)
                    sender.reply(toApplicationShouldTerminate: true)
                } else {
                    model.presentSaveRecovery()
                    sender.reply(toApplicationShouldTerminate: false)
                }
            }
            return .terminateLater
        }
    }
    /// Keeps the journal window open until its writing is saved.
    ///
    /// SwiftUI's own window delegate stays in charge: a proxy handles closing and forwards every other delegate
    /// message to it, so scene teardown, state restoration and full-screen behavior are unaffected.
    struct WindowCloseGuard: NSViewRepresentable {
        let model: AppModel
        func makeNSView(context: Context) -> NSView { WindowObserver(coordinator: context.coordinator) }
        func updateNSView(_ view: NSView, context: Context) {
            // SwiftUI may assign its delegate again; restore the proxy without replacing SwiftUI's delegate.
            context.coordinator.keepInstalled()
        }
        func makeCoordinator() -> Coordinator { Coordinator(model) }

        final class WindowObserver: NSView {
            private let coordinator: Coordinator
            init(coordinator: Coordinator) {
                self.coordinator = coordinator
                super.init(frame: .zero)
            }
            required init?(coder: NSCoder) { nil }
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                if let window { coordinator.attach(to: window) }
            }
        }

        @MainActor final class Coordinator {
            let model: AppModel
            private let proxy: WindowDelegateProxy
            private weak var window: NSWindow?
            init(_ model: AppModel) {
                self.model = model
                proxy = WindowDelegateProxy(model: model)
            }
            func attach(to window: NSWindow) {
                guard self.window !== window else { return }
                self.window = window
                keepInstalled()
                model.journalWindow = window
            }
            func keepInstalled() {
                guard let window, window.delegate !== proxy else { return }
                proxy.original = window.delegate
                window.delegate = proxy
            }
        }
    }

    /// Answers `windowShouldClose` and forwards every other window delegate message to SwiftUI's delegate.
    final class WindowDelegateProxy: NSObject {
        weak var original: NSWindowDelegate?
        /// The journal window's columns. View ▸ Show/Hide Sidebar reaches them from anywhere in the window, also
        /// while the toolbar's search field has keyboard focus.
        weak var splitController: NSSplitViewController?
        let model: AppModel
        private var allowingClose = false
        init(model: AppModel) { self.model = model }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }

    extension WindowDelegateProxy: NSMenuItemValidation {
        @MainActor @objc func toggleSidebar(_ sender: Any?) { splitController?.toggleSidebar(sender) }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            guard menuItem.action == #selector(toggleSidebar(_:)) else {
                // Other actions are SwiftUI's delegate's, which validates them as before.
                return (original as? NSMenuItemValidation)?.validateMenuItem(menuItem) ?? true
            }
            return splitController?.validateUserInterfaceItem(menuItem) ?? false
        }
    }

    extension WindowDelegateProxy: NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            original?.windowWillClose?(notification)
            guard let window = notification.object as? NSWindow else { return }
            if model.journalWindow === window { model.journalWindow = nil }
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if allowingClose { return original?.windowShouldClose?(sender) ?? true }
            Task {
                if await model.flush() {
                    allowingClose = true
                    sender.performClose(nil)
                    allowingClose = false
                } else {
                    model.presentSaveRecovery()
                }
            }
            return false
        }
    }
    extension AppModel {
        func presentSaveRecovery() {
            let alert = NSAlert()
            alert.messageText = "Couldn’t save changes on this Mac."
            alert.informativeText = "Keep this window open and try again, so your changes aren’t lost."
            alert.addButton(withTitle: "Keep Open")
            alert.runModal()
        }
    }
#endif
