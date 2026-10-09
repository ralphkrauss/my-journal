import Foundation
import StoreKit

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Asks the system for a rating at a natural pause: two seconds after the person leaves an entry they edited, when
/// nothing else is happening and the usage rules allow it (docs/design/about-and-ratings-2026-10-05.md §3).
@MainActor final class ReviewRequests {
    struct Environment {
        var now: () -> Date = Date.init
        var calendar = Calendar.current
        /// The pause before asking; tests make it return at once.
        var pause: () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }
        /// Whether this copy came from the App Store: TestFlight and development builds never ask.
        var installedFromAppStore: () async -> Bool = ReviewRequests.installedFromAppStore
    }

    /// Nil when this process never asks: unit-test hosts and UI-test runs.
    private let store: ReviewUsageStore?
    private let environment: Environment
    /// Whether the screen is clear for the system's prompt; the model answers.
    var momentIsClear: () -> Bool = { false }
    /// The system's request, from the window's environment.
    var present: (() -> Void)?
    /// The entry the person edited since launch or the last unlock.
    private var editedEntry: UUID?
    private var problemThisSession = false
    /// Changes with every edit, selection and interruption; a pending request goes ahead only if it didn't change.
    private var activity = 0
    private(set) var pending: Task<Void, Never>?

    init(store: ReviewUsageStore?, environment: Environment = Environment()) {
        self.store = store
        self.environment = environment
    }

    /// The app's own: preferences, except in test processes.
    static func forApp(hostsTests: Bool) -> ReviewRequests {
        let processEnvironment = ProcessInfo.processInfo.environment
        #if DEBUG
            // A UI-test run that checks the moment starts with usage that meets the rules, kept in memory.
            if processEnvironment["JOURNAL_UI_TEST_REVIEW"] == "eligible" {
                let usage = ReviewUsage(writingDays: 10)
                var environment = Environment()
                environment.installedFromAppStore = { true }
                return ReviewRequests(store: .memory(usage), environment: environment)
            }
        #endif
        let testing = hostsTests || processEnvironment["JOURNAL_UI_TEST_ID"] != nil
        return ReviewRequests(store: testing ? nil : .preferences())
    }

    /// The person changed this entry in the editor.
    func noteEdit(entry id: UUID) {
        editedEntry = id
        interrupt()
    }

    /// The person's edits to this entry were saved: today counts as a writing day.
    func noteSaved(entry id: UUID) {
        guard let store, id == editedEntry else { return }
        let now = environment.now()
        var usage = store.current()
        usage.recordWriting(at: now, calendar: environment.calendar)
        store.usage = usage
    }

    /// An error alert, a failed save or changes to review: no request in this session. A sync problem is not
    /// remembered; Sync Status showing blocks the moment while it lasts (`AppModel.reviewMomentIsClear`).
    func noteProblem() {
        problemThisSession = true
        interrupt()
    }

    /// Anything that makes this not a pause: a new entry, a sheet, locking, leaving the foreground.
    func interrupt() {
        activity += 1
        pending?.cancel()
        pending = nil
    }

    /// Locking ends the session's writing; unlocking is never the moment.
    func noteLocked() {
        editedEntry = nil
        interrupt()
    }

    /// After erasing, as at a first launch.
    func reset() {
        editedEntry = nil
        problemThisSession = false
        interrupt()
    }

    /// The person chose another entry, or went back to the list, from `left`.
    func selectionChanged(leaving left: UUID?) {
        interrupt()
        guard let left, left == editedEntry else { return }
        editedEntry = nil
        let expected = activity
        pending = Task { [weak self] in
            guard let pause = self?.environment.pause else { return }
            do { try await pause() } catch { return }
            await self?.askIfStillPaused(expected)
        }
    }

    private func askIfStillPaused(_ expected: Int) async {
        guard let store, !Task.isCancelled, activity == expected, momentIsClear() else { return }
        let now = environment.now()
        let allowed = ReviewRequestRules.allow(store.usage, problemThisSession: problemThisSession, now: now)
        guard allowed, await environment.installedFromAppStore() else { return }
        guard !Task.isCancelled, activity == expected, momentIsClear(), let present else { return }
        present()
        var usage = store.current()
        usage.lastRequest = now
        store.usage = usage
        pending = nil
    }

    private static func installedFromAppStore() async -> Bool {
        guard case .verified(let transaction) = try? await AppTransaction.shared else { return false }
        return transaction.environment == .production
    }
}

extension AppModel {
    /// Nothing is happening that the system's prompt would interrupt: no operation, sheet, error, problem Sync Status
    /// shows, or new entry, and the window in front has nothing over it and no text input focused.
    var reviewMomentIsClear: Bool {
        guard reviewStateIsClear else { return false }
        #if os(macOS)
            return ReviewMoment.windowIsClear(journalWindow: journalWindow)
        #else
            return ReviewMoment.windowIsClear()
        #endif
    }

    /// The model's side of `reviewMomentIsClear`: what the app is doing and showing, apart from the window.
    var reviewStateIsClear: Bool {
        guard !locked, applicationActive, !unlockState.requestInFront, store != nil, isReady else { return false }
        guard !replacingVault, !erasingLibrary, !connectingToServer, !creatingEntry, deleteAllPhase == .idle else {
            return false
        }
        guard !saveFailure, error == nil, conflicts.isEmpty, !openingJournals, !showsSyncStatus else { return false }
        let presenting =
            settingsPresented || templateChooserPresented || archiveExportPresented
            || markdownExportPresented
            || archiveImportRequested || newJournalRequested
        guard !presenting else { return false }
        // An entry that is still empty is about to be written in.
        if let draft, draft.kind == "entry", draft.title.isEmpty, TemplateSuggestion.hasEmptyBody(draft) {
            return false
        }
        return true
    }
}

/// Whether the window in front shows nothing over the journals and has no text input focused.
@MainActor enum ReviewMoment {
    #if os(macOS)
        static func windowIsClear(journalWindow: NSWindow?) -> Bool {
            guard NSApp.isActive, NSApp.modalWindow == nil, let window = NSApp.keyWindow, window === journalWindow
            else { return false }
            // A menu being tracked, a sheet, or a popover (a child window), or typing in the editor or search field.
            guard RunLoop.current.currentMode != .eventTracking, window.attachedSheet == nil else { return false }
            return window.childWindows?.isEmpty != false && !(window.firstResponder is NSText)
        }
    #else
        static func windowIsClear() -> Bool {
            guard UIApplication.shared.applicationState == .active else { return false }
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            guard let window, window.rootViewController?.presentedViewController == nil else { return false }
            return !FirstResponder.isTextInput
        }
    #endif
}

#if os(iOS)
    /// The current first responder, found with a nil-targeted action as UIKit's responder chain allows.
    @MainActor enum FirstResponder {
        fileprivate static var found: UIResponder?

        static var isTextInput: Bool {
            found = nil
            UIApplication.shared.sendAction(
                #selector(UIResponder.journalReportFirstResponder(_:)), to: nil, from: nil, for: nil)
            defer { found = nil }
            return found is UITextView || found is UITextField
        }
    }

    extension UIResponder {
        @objc fileprivate func journalReportFirstResponder(_ sender: Any?) {
            FirstResponder.found = self
        }
    }
#endif
