import AppKit
import JournalCore
import SwiftUI
import XCTest

@testable import Journal

/// The Mac spec states that open a second library in a window of its own: the welcome screen, the screens for
/// journals that can't be opened, and changes to review. Each library is a copy of the sample library in the app's
/// container, opened by its own model, so the first window and its library stay as they are.
extension SpecMacCapture {
    func libraryStates(_ sample: URL) async throws {
        await state("welcome") { try await welcome(sample) }
        await state("problems") { try await problems(sample) }
        await state("changes to review") { try await changesToReview(sample) }
    }

    /// A window with its own model, as the journal window has.
    private func openWindow(for model: AppModel) async -> NSWindow {
        let content = RootView().environmentObject(model).environmentObject(EditorActions())
            .frame(minWidth: 801, minHeight: 420)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.setFrame(NSRect(x: 40, y: 120, width: 1280, height: 800), display: true)
        window.makeKeyAndOrderFront(nil)
        await model.load()
        window.setFrame(NSRect(x: 40, y: 120, width: 1280, height: 800), display: true)
        return window
    }

    private func copy(of sample: URL) throws -> URL {
        let folder = sample.deletingLastPathComponent().appendingPathComponent("copy-" + UUID().uuidString)
        try FileManager.default.copyItem(at: sample, to: folder)
        return folder
    }

    private func welcome(_ sample: URL) async throws {
        let folder = sample.deletingLastPathComponent().appendingPathComponent("empty-" + UUID().uuidString)
        let model = AppModel(directory: folder)
        let window = await openWindow(for: model)
        try await settle(2)
        try await capture(window, "welcome-default")
        tap(window, at: 640, fromTop: 458)
        try await settle(2)
        try await captureSheet(window, "create-library-password")
        window.close()
    }

    private func problems(_ sample: URL) async throws {
        for (problem, name) in [
            (SpecLibraryFixtures.Problem.settingsUnread, "settings-unread"), (.cantOpen, "cant-open"),
            (.newerVersion, "newer-version"),
        ] {
            let folder = try copy(of: sample)
            let first = AppModel(directory: folder)
            await first.load()
            await first.unlockWithRecovery(try password())
            try? await first.store?.close()
            try SpecLibraryFixtures.damage(problem, in: folder)
            let window = await openWindow(for: AppModel(directory: folder))
            try await settle(2)
            try await capture(window, "unavailable-content-library-\(name)")
            window.close()
        }
    }

    private func changesToReview(_ sample: URL) async throws {
        let folder = try copy(of: sample)
        try await SpecLibraryFixtures.recordConflicts(in: folder, password: try password())
        let model = AppModel(directory: folder)
        let window = await openWindow(for: model)
        await model.unlockWithRecovery(try password())
        let entry = try XCTUnwrap(model.items.first { $0.kind == "entry" && $0.title == "Slow Sunday" })
        await model.select(entry.id)
        window.setFrame(NSRect(x: 40, y: 120, width: 1280, height: 800), display: true)
        try await settle(2)
        try await capture(window, "conflict-review-notice")
        tap(window, at: 1209, fromTop: 80)
        try await settle(3)
        if window.attachedSheet != nil { try await captureSheet(window, "entry-conflict-default") }
        try await closeSheets(of: window)
        window.close()
    }
}
