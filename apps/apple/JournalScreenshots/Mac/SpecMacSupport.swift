import AppKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// The shared parts of the Mac spec screenshots (design/spec-screenshots/README.md). Like the App Store captures they
/// are hosted in the Mac app, which opens the sample library in its own windows, arranged through the model and the
/// toolbar's own actions, and written as `<page-id>-<state>.png` from the window server's rendering of each window.
@MainActor
class SpecMacCase: XCTestCase {
    var environment: [String: String] { ProcessInfo.processInfo.environment }
    /// The states that failed, written to `failed.txt` beside the captures so the script can report them.
    var failures: [String] = []

    // MARK: - Opening

    func password() throws -> String {
        guard let file = environment["JOURNAL_SCREENSHOT_PASSWORD_FILE"] else {
            throw CaptureError("Run design/spec-screenshots/capture.sh, which seeds the library.")
        }
        return try String(contentsOfFile: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func journalWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(JournalApp.windowID) == true }
            ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    /// The app's model and journal window, with the sample library unlocked.
    func openLibrary() async throws -> (AppModel, NSWindow) {
        let window = try XCTUnwrap(journalWindow(), "The journal window isn't open.")
        let delegate = NSApp.delegate.flatMap { Self.find(ApplicationDelegate.self, in: $0, depth: 0) }
        let model = try XCTUnwrap(delegate?.model ?? Self.find(AppModel.self, in: window.contentView as Any, depth: 0))
        await model.load()
        await model.unlockWithRecovery(try password())
        XCTAssertFalse(model.locked, model.error ?? "")
        window.setFrame(NSRect(x: 40, y: 120, width: 1280, height: 800), display: true)
        return (model, window)
    }

    /// Finds an object of the given type in a view's stored properties.
    static func find<T: AnyObject>(_ type: T.Type, in value: Any, depth: Int) -> T? {
        if let found = value as? T { return found }
        guard depth < 14 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = find(type, in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - Arranging

    func settle(_ seconds: Double = 1.2) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func show(_ title: String, in journal: String, model: AppModel, window: NSWindow) async throws {
        let journalID = try XCTUnwrap(model.journals.first { $0.title == journal }?.id)
        await model.switchJournal(journalID)
        let entry = try XCTUnwrap(model.items.first { $0.kind == "entry" && $0.title == title })
        await model.select(entry.id)
        try await settle()
        window.makeFirstResponder(nil)
        try await settle(0.4)
    }

    func openSettings(_ tab: AppSettingsTab, model: AppModel) async throws -> NSWindow {
        model.settingsTab = tab
        model.settingsPresented = true
        try await settle(2)
        let journal = journalWindow()
        return try XCTUnwrap(
            NSApp.windows.first {
                $0.isVisible && $0 !== journal && $0.styleMask.contains(.titled) && $0.sheetParent == nil
            })
    }

    /// The journal window's toolbar controller, whose configuration holds the menus of the toolbar's ⋯ buttons.
    func toolbarController(of window: NSWindow) throws -> JournalToolbarController {
        try XCTUnwrap(window.toolbar?.delegate as? JournalToolbarController, "The journal window has no toolbar.")
    }

    /// Runs the toolbar menu action with this title (Entry Actions or Journal Actions), as choosing it would.
    func perform(_ title: String, in actions: [MenuAction]) throws {
        let action = try XCTUnwrap(actions.first { $0.title == title }, "No menu action \(title).")
        guard case .command(let run) = action.kind else { throw CaptureError("\(title) is not a command.") }
        run()
    }

    /// The first enabled AppKit control with this title in the window's views.
    func control(_ title: String, in window: NSWindow) -> NSControl? {
        var found: NSControl?
        func visit(_ view: NSView) {
            if found == nil, let control = view as? NSButton, control.isEnabled, !control.isHidden,
                control.title == title
            {
                found = control
            }
            view.subviews.forEach(visit)
        }
        window.contentView.map(visit)
        return found
    }

    /// Clicks the AppKit control with this title, as a click would. SwiftUI's own buttons are drawn without a control,
    /// and the app's accessibility tree isn't built in its own process, so those are clicked by `tap(_:at:fromTop:)`.
    func press(_ title: String, in window: NSWindow) throws {
        guard let found = control(title, in: window) else { throw CaptureError("No \(title) control.") }
        found.performClick(nil)
    }

    /// A click at a place in the window, in points from its top left, queued like one from the mouse so the window
    /// handles it as it would a person's. The places come from the captures themselves: a pane's layout is fixed.
    func tap(_ window: NSWindow, at x: CGFloat, fromTop y: CGFloat) {
        let point = NSPoint(x: x, y: window.frame.height - y)
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: pressure)
            if let event { NSApp.postEvent(event, atStart: false) }
        }
    }

    /// Cancels or closes the sheets of `window` with Escape, which presses the sheet's Cancel button as the keyboard
    /// does, then with Return, which presses its default button (Done), and ends the sheet when neither does.
    func closeSheets(of window: NSWindow) async throws {
        for _ in 0..<4 {
            guard let sheet = window.attachedSheet else { return }
            sheet.makeKeyAndOrderFront(nil)
            for (character, code) in [("\u{1b}", UInt16(53)), ("\r", UInt16(36))] where window.attachedSheet === sheet {
                let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: sheet.windowNumber, context: nil, characters: character,
                    charactersIgnoringModifiers: character, isARepeat: false, keyCode: code)
                _ = event.map { sheet.performKeyEquivalent(with: $0) }
                try await settle(0.8)
            }
            if window.attachedSheet === sheet { window.endSheet(sheet) }
            try await settle(0.5)
        }
        if window.attachedSheet != nil { throw CaptureError("A sheet would not close.") }
    }

    /// The window's views, one per line with their class and any title, label or text, for finding a control.
    func outline(of window: NSWindow) -> String {
        var lines: [String] = []
        func visit(_ view: NSView, _ depth: Int) {
            var detail = String(describing: type(of: view))
            if let button = view as? NSButton { detail += " title=\(button.title)" }
            if let field = view as? NSTextField { detail += " text=\(field.stringValue)" }
            if let label = view.accessibilityLabel() { detail += " label=\(label)" }
            lines.append(String(repeating: " ", count: depth) + detail)
            view.subviews.forEach { visit($0, depth + 1) }
        }
        if let content = window.contentView { visit(content, 0) }
        return lines.joined(separator: "\n")
    }

    /// Runs one state, noting its failure instead of ending the run.
    func state(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            failures.append("\(name): \(error)")
            print("FAILED", name, error)
        }
    }

    func writeFailures() throws {
        guard !failures.isEmpty else { return }
        try failures.joined(separator: "\n").write(
            to: try outputFolder().appendingPathComponent("failed.txt"), atomically: true, encoding: .utf8)
        XCTFail("Some states failed: \(failures.joined(separator: "; "))")
    }

    // MARK: - Capturing

    /// Writes the window as the window server draws it, named `<name>.png`. It never has a sheet: a sheet left open by
    /// an earlier state would put the wrong content, perhaps another machine's servers, into a capture.
    func capture(_ window: NSWindow, _ names: String...) async throws {
        if window.attachedSheet != nil { throw CaptureError("A sheet is open in the capture of \(names).") }
        try await write(window, names)
    }

    /// Writes the window with the sheet that is open, named `<name>.png`.
    func captureSheet(_ window: NSWindow, _ names: String...) async throws {
        if window.attachedSheet == nil { throw CaptureError("No sheet is open for \(names).") }
        try await write(window, names)
    }

    private func write(_ window: NSWindow, _ names: [String]) async throws {
        window.makeKeyAndOrderFront(nil)
        try await settle()
        guard let image = Self.composite(window) else { throw CaptureError("No image for \(names)") }
        // A window hidden from screen capture, as the pairing code is, comes back black; it is not a screenshot.
        if let sheet = window.attachedSheet, let sheetImage = Self.windowImage(sheet), Self.isBlack(sheetImage) {
            let file = try outputFolder().appendingPathComponent("skipped.txt")
            let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let note =
                "\(names.joined(separator: ", ")): the window is hidden from screen capture, so it comes back black.\n"
            try (existing + note).write(to: file, atomically: true, encoding: .utf8)
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CaptureError("No PNG") }
        for name in names { try data.write(to: try outputFolder().appendingPathComponent(name + ".png")) }
    }

    func outputFolder() throws -> URL {
        guard let output = environment["JOURNAL_SCREENSHOT_OUTPUT"] else {
            throw CaptureError("Run design/spec-screenshots/capture.sh, which names the output folder.")
        }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Whether every pixel of the image is black.
    static func isBlack(_ image: CGImage) -> Bool {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        return pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 0 }
    }

    /// The window and the sheets attached to it, each at its place.
    static func composite(_ window: NSWindow) -> CGImage? {
        guard let base = windowImage(window) else { return nil }
        var sheets: [NSWindow] = []
        var next = window.attachedSheet
        while let sheet = next {
            sheets.append(sheet)
            next = sheet.attachedSheet
        }
        guard !sheets.isEmpty else { return base }
        let scale = CGFloat(base.width) / window.frame.width
        guard
            let context = CGContext(
                data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return base }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        for sheet in sheets {
            guard let image = windowImage(sheet) else { continue }
            let rect = CGRect(
                x: (sheet.frame.minX - window.frame.minX) * scale, y: (sheet.frame.minY - window.frame.minY) * scale,
                width: CGFloat(image.width), height: CGFloat(image.height))
            context.draw(image, in: rect)
        }
        return context.makeImage()
    }

    /// `CGWindowListCreateImage` for the app's own window, which needs no screen recording permission. It is looked
    /// up at run time because the macOS 15 SDK no longer declares it.
    static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
            let symbol = dlsym(handle, "CGWindowListCreateImage")
        else { return nil }
        let create = unsafeBitCast(symbol, to: Create.self)
        let includingWindow: UInt32 = 1 << 3
        let options: UInt32 = (1 << 0) | (1 << 3)
        return create(.null, includingWindow, UInt32(window.windowNumber), options)?.takeRetainedValue()
    }
}
