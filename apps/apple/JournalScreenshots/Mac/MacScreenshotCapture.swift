import AppKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// Captures the Mac App Store screenshots from the seeded sample library (docs/app-store/screenshots-plan.md).
/// Hosted in the app, it opens the library in the app's own journal window and Settings window, arranges them as each
/// frame needs and renders the windows at 2x. design/app-store/capture-mac.sh seeds the library and names it with
/// `JOURNAL_DATA_DIR`; `JOURNAL_SCREENSHOT_PASSWORD_FILE` and `JOURNAL_SCREENSHOT_OUTPUT` come from the same script.
@MainActor
final class MacScreenshotCapture: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    func testCaptureMacFrames() async throws {
        let (model, window) = try await openLibrary()
        window.setFrame(NSRect(x: 40, y: 120, width: 1280, height: 800), display: true)
        NSApp.appearance = NSAppearance(named: .aqua)
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        try await capture(window, "01-main-light")

        // Shown on without asking: the capture runs unattended. Not saved.
        model.configuration?.appLock = true
        try await capture(try await openSettings(.privacy, model: model), "02-settings-privacy-light")
        try await capture(try await openSettings(.sync, model: model), "03-settings-sync-light")

        try await show("Offsite ideas", in: "Work", model: model, window: window)
        try await capture(window, "05-main-light")
        model.templateChooserPresented = true
        try await settle(2)
        try await capture(try XCTUnwrap(window.attachedSheet, "No template sheet."), "05-sheet-light")
        model.templateChooserPresented = false
        try await settle()

        NSApp.appearance = NSAppearance(named: .darkAqua)
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        try await capture(window, "04-main-dark")
        // The Agent Access frame needs an agent connected through a sync server, which this capture doesn't run
        // (docs/design/agent-access-simplified.md, section 8).
        try await show("Porto, day two", in: "Travel", model: model, window: window)
        try await capture(window, "06-main-dark")
    }

    // MARK: - Arranging

    private func openLibrary() async throws -> (AppModel, NSWindow) {
        guard let passwordFile = environment["JOURNAL_SCREENSHOT_PASSWORD_FILE"] else {
            throw CaptureError("Run design/app-store/capture-mac.sh, which seeds the library.")
        }
        let window = try XCTUnwrap(journalWindow(), "The journal window isn't open.")
        let delegate = NSApp.delegate.flatMap { Self.find(ApplicationDelegate.self, in: $0, depth: 0) }
        if delegate == nil, let appDelegate = NSApp.delegate { Self.dump(appDelegate, depth: 0) }
        let model = try XCTUnwrap(delegate?.model ?? Self.find(AppModel.self, in: window.contentView as Any, depth: 0))
        await model.load()
        let password = try String(contentsOfFile: passwordFile, encoding: .utf8)
        await model.unlockWithRecovery(password.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(model.locked, model.error ?? "")
        return (model, window)
    }

    private func journalWindow() -> NSWindow? {
        // The WindowGroup's windows are identified by its ID, "journal".
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(JournalApp.windowID) == true }
            ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    private func show(_ title: String, in journal: String, model: AppModel, window: NSWindow) async throws {
        let journalID = try XCTUnwrap(model.journals.first { $0.title == journal }?.id)
        await model.switchJournal(journalID)
        let entry = try XCTUnwrap(model.items.first { $0.kind == "entry" && $0.title == title })
        await model.select(entry.id)
        try await settle()
        // No insertion point in the editor, as after clicking in the list.
        window.makeFirstResponder(nil)
        try await settle(0.5)
    }

    private func openSettings(_ tab: AppSettingsTab, model: AppModel) async throws -> NSWindow {
        model.settingsTab = tab
        model.settingsPresented = true
        try await settle(2)
        let journal = journalWindow()
        return try XCTUnwrap(
            NSApp.windows.first {
                $0.isVisible && $0 !== journal && $0.styleMask.contains(.titled) && $0.sheetParent == nil
            })
    }

    private func settle(_ seconds: Double = 1.5) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Capturing

    /// Writes the window twice: as the window server composes it, and as its views draw themselves, so the script
    /// can use whichever the environment allows.
    private func capture(_ window: NSWindow, _ name: String) async throws {
        window.makeKeyAndOrderFront(nil)
        try await settle()
        let folder = try outputFolder()
        if let image = Self.windowImage(window) {
            try png(image).write(to: folder.appendingPathComponent(name + "-server.png"))
        }
        if let frame = window.contentView?.superview {
            let scale: CGFloat = 2
            let size = frame.bounds.size
            guard
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { throw CaptureError("No bitmap for \(name)") }
            rep.size = size
            frame.cacheDisplay(in: frame.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try data.write(to: folder.appendingPathComponent(name + "-views.png"))
            }
        }
        print("captured", name, window.backingScaleFactor, window.frame)
    }

    private func outputFolder() throws -> URL {
        guard let output = environment["JOURNAL_SCREENSHOT_OUTPUT"] else {
            throw CaptureError("Run design/app-store/capture-mac.sh, which names the output folder.")
        }
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func png(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CaptureError("No PNG") }
        return data
    }

    /// `CGWindowListCreateImage` for the app's own window, which needs no screen recording permission. It is
    /// looked up at run time because the macOS 15 SDK no longer declares it.
    private static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Create = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
            let symbol = dlsym(handle, "CGWindowListCreateImage")
        else { return nil }
        let create = unsafeBitCast(symbol, to: Create.self)
        // Only this window, at its own bounds without the shadow, at the display's full resolution.
        let includingWindow: UInt32 = 1 << 3
        let options: UInt32 = (1 << 0) | (1 << 3)
        return create(.null, includingWindow, UInt32(window.windowNumber), options)?.takeRetainedValue()
    }

    private static func dump(_ value: Any, depth: Int) {
        guard depth < 5 else { return }
        for child in Mirror(reflecting: value).children {
            print(String(repeating: "  ", count: depth), child.label ?? "-", type(of: child.value))
            dump(child.value, depth: depth + 1)
        }
    }

    /// Finds an object of the given type in a view's stored properties, such as the model a SwiftUI hosting view
    /// passes to its content as an environment object.
    private static func find<T: AnyObject>(_ type: T.Type, in value: Any, depth: Int) -> T? {
        if let found = value as? T { return found }
        guard depth < 14 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = find(type, in: child.value, depth: depth + 1) { return found }
        }
        return nil
    }
}

struct CaptureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
