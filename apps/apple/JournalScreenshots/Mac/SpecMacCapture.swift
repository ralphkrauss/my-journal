import AppKit
import JournalCore
import XCTest

@testable import Journal

/// Captures the Mac screenshots of the spec from the seeded sample library (design/spec-screenshots/README.md). It runs
/// in the Mac app, so every state is reached through the model and the toolbar's own menu actions, and the states that
/// change the library (deleting) come last.
@MainActor
final class SpecMacCapture: SpecMacCase {
    func testCaptureSpecStates() async throws {
        let (model, window) = try await openLibrary()
        NSApp.appearance = NSAppearance(named: .aqua)
        await state("window") { try await windowStates(model, window) }
        await state("entries") { try await entryStates(model, window) }
        await state("sheets") { try await sheetStates(model, window) }
        await state("journals") { try await journalStates(model, window) }
        await state("settings") { try await settingsStates(model) }
        await state("app lock") { try await lockStates(model, window) }
        if environment["JOURNAL_SPEC_SERVER"] != nil { await state("server") { try await syncStates(model) } }
        await state("dark") { try await darkStates(model, window) }
        await state("deleting") { try await deletingStates(model, window) }
        if let sample = environment["JOURNAL_DATA_DIR"] {
            await state("libraries") { try await libraryStates(URL(fileURLWithPath: sample)) }
        }
        try writeFailures()
    }

    // MARK: - The window

    private func windowStates(_ model: AppModel, _ window: NSWindow) async throws {
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        try await capture(window, "library-window-default", "entry-editor-default", "entry-list-default")
        await model.show(.all)
        try await settle()
        try await capture(window, "entry-list-all-entries")
        await model.show(.templates)
        try await settle()
        try await capture(window, "templates-default")
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        let toolbar = try toolbarController(of: window)
        toolbar.configuration.setQuery("walk")
        try await settle(2)
        try await capture(window, "search-default")
        toolbar.configuration.setQuery("")
        try await settle()
    }

    private func entryStates(_ model: AppModel, _ window: NSWindow) async throws {
        try await show("Offsite ideas", in: "Work", model: model, window: window)
        try await capture(window, "entry-editor-table", "edit-table-default")
        try await show("Packing list", in: "Travel", model: model, window: window)
        try await capture(window, "entry-editor-checklist")
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        let toolbar = try toolbarController(of: window)
        toolbar.configuration.toggleSourceMode()
        try await settle(1.5)
        try await capture(window, "source-view-default")
        toolbar.configuration.toggleSourceMode()
        try await settle()
    }

    // MARK: - Sheets

    private func sheetStates(_ model: AppModel, _ window: NSWindow) async throws {
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        for (action, name) in [
            ("Change Date…", "change-date-default"), ("Move Entry…", "move-entry-default"),
            ("Image Descriptions…", "image-description-default"),
        ] {
            let toolbar = try toolbarController(of: window)
            try perform(action, in: toolbar.configuration.entryActions())
            try await settle(2)
            try await captureSheet(window, name)
            try await closeSheets(of: window)
        }
        try await show("Bread, attempt four", in: "Personal", model: model, window: window)
        let toolbar = try toolbarController(of: window)
        try perform("Version History…", in: toolbar.configuration.entryActions())
        try await settle(2)
        try await captureSheet(window, "version-history-default")
        try await closeSheets(of: window)
        model.templateChooserPresented = true
        try await settle(2)
        try await captureSheet(window, "template-chooser-default")
        model.templateChooserPresented = false
        try await settle()
        try await exportSheets(model, window)
    }

    private func exportSheets(_ model: AppModel, _ window: NSWindow) async throws {
        model.markdownExportPresented = true
        try await settle(2)
        try await captureSheet(window, "export-markdown-default")
        model.markdownExportPresented = false
        try await closeSheets(of: window)
        model.archiveExportPresented = true
        try await settle(2)
        try await captureSheet(window, "export-archive-default")
        model.archiveExportPresented = false
        try await closeSheets(of: window)
    }

    // MARK: - Journals

    private func journalStates(_ model: AppModel, _ window: NSWindow) async throws {
        let travel = try XCTUnwrap(model.journals.first { $0.title == "Travel" }?.id)
        await model.switchJournal(travel)
        try await settle()
        model.newJournalRequested = true
        try await settle(2)
        try await captureSheet(window, "journals-new-journal")
        try await closeSheets(of: window)
        let toolbar = try toolbarController(of: window)
        try perform("Delete Journal…", in: toolbar.configuration.journalActions())
        try await settle(2)
        try await captureSheet(window, "journals-delete-confirm")
        try await closeSheets(of: window)
    }

    // MARK: - App Lock

    private func lockStates(_ model: AppModel, _ window: NSWindow) async throws {
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        // Shown on without asking: the capture runs unattended. Not saved.
        model.configuration?.appLock = true
        let privacy = try await openSettings(.privacy, model: model)
        try await capture(privacy, "settings-privacy-app-lock-on")
        tap(privacy, at: 100, fromTop: 193)
        try await settle(2)
        if privacy.attachedSheet != nil { try await captureSheet(privacy, "change-password-default") }
        try await closeSheets(of: privacy)
        model.settingsPresented = false
        try await settle()
        await model.lock()
        try await settle(2)
        try await capture(window, "lock-screen-default")
        await model.unlockWithRecovery(try password())
        model.configuration?.appLock = false
        try await settle()
    }

    // MARK: - Settings

    private func settingsStates(_ model: AppModel) async throws {
        for (tab, name) in [
            (AppSettingsTab.general, "settings-general-default"), (.sync, "settings-sync-default"),
            (.privacy, "settings-privacy-default"), (.backup, "settings-backup-default"),
            (.agents, "settings-agent-access-default"),
        ] {
            let settings = try await openSettings(tab, model: model)
            try await capture(settings, name)
        }
    }

    // MARK: - Dark appearance

    private func darkStates(_ model: AppModel, _ window: NSWindow) async throws {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        try await show("Slow Sunday", in: "Personal", model: model, window: window)
        try await capture(window, "library-window-default-dark", "entry-editor-default-dark")
        try await capture(try await openSettings(.privacy, model: model), "settings-privacy-default-dark")
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    // MARK: - Deleting

    private func deletingStates(_ model: AppModel, _ window: NSWindow) async throws {
        try await show("Rainy walk", in: "Personal", model: model, window: window)
        let toolbar = try toolbarController(of: window)
        try perform("Delete Entry", in: toolbar.configuration.entryActions())
        try await settle(1.5)
        await model.show(.deleted)
        try await settle()
        try await capture(window, "recently-deleted-default")
    }
}
