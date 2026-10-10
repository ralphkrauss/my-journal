import Foundation
import JournalCore
import SwiftUI
import os

/// Why the journals on this device can't be opened (docs/design/build-18-fixes-2026-10-06.md §2.1). Only a newer
/// version is told apart from the rest: the person's choices are the same, and a permanent fault can't reliably be told
/// from a temporary one.
enum LibraryProblem: Equatable {
    /// `configuration.json` exists but doesn't read or decode.
    case settingsUnread
    /// The library the configuration names doesn't open, or its first read fails.
    case cantOpen
    /// The journals, or the format they use, were saved by a newer version of My Journal.
    case newerVersion
    /// The library needs a password and its device key is gone: the lock screen, with the credential field.
    case needsKey
    /// The library on this device isn't encrypted: version 1.0 made it when asked to work without encryption. This
    /// version never opens, changes or syncs one, so its files stay as they are until the person erases them.
    case notEncrypted

    /// Try Again re-reads the settings and opens the library again.
    var offersTryAgain: Bool { self == .cantOpen || self == .settingsUnread }
    /// Import Archive… verifies the archive before it replaces the library that can't be opened.
    var offersImport: Bool { self == .cantOpen || self == .needsKey }
    /// Erase Journals and Settings… is the one way out of an unreadable library or settings.
    var allowsErase: Bool { self != .newerVersion }
    /// Erase waits for one failed Try Again, so it is offered at once where there is no Try Again.
    var erasesAfterFailedRetry: Bool { offersTryAgain }
    /// Whether the problem is shown by the problem screen. The missing key keeps the lock screen.
    var hasOwnScreen: Bool { self != .needsKey }
}

/// What refuses a change while the journals can't be opened (docs/design/build-18-fixes-2026-10-06.md §2.1, rule 1).
struct LibraryNotOpenError: Error, LocalizedError {
    var errorDescription: String? { "Your journals need to open before this can be done." }
}

/// The first read of the journals failed, and the library was closed and the problem shown. Callers that would
/// otherwise show an alert for the failure have nothing more to say.
struct LibraryOpenHandled: Error {}

/// A configuration that names a library whose database is missing opens nothing, and nothing is created for it.
struct LibraryDatabaseMissing: Error {}

extension AppModel {
    /// `messages.library.deviceKeyUnavailable`: names the credential the lock screen asks for, which is the library's
    /// own (`LocalConfiguration.credentialName`): the master password, or the recovery key of an early library.
    static func missingDeviceKeyMessage(credentialName: String?) -> String {
        "Your device key is unavailable. Use your \(credentialName?.lowercased() ?? "password") to unlock your journals."
    }

    var missingDeviceKeyMessage: String {
        Self.missingDeviceKeyMessage(credentialName: configuration?.credentialName)
    }

    /// A problem state is never locked: it has no store to unlock. The missing key is the exception, which is the lock
    /// screen with its credential field.
    var showsLibraryProblem: Bool {
        guard let problem = libraryProblem ?? (retryingOpen ? lastLibraryProblem : nil) else { return false }
        return problem.hasOwnScreen
    }

    /// The problem the screen describes, also while Try Again runs.
    var shownLibraryProblem: LibraryProblem? { libraryProblem ?? (retryingOpen ? lastLibraryProblem : nil) }

    /// File ▸ Import Archive… and opened archive files. With a library open, whenever the app isn't locked; without
    /// one, unless importing would overwrite settings that couldn't be read or replace journals a newer version
    /// wrote, which updating opens.
    var canImportArchive: Bool {
        guard store == nil, let problem = libraryProblem else {
            return !locked
        }
        return problem.offersImport && !retryingOpen
    }

    /// Journals a newer version wrote, settings that couldn't be read and journals that aren't encrypted are never
    /// imported over.
    var refusesImport: Bool { libraryProblem.map { !$0.offersImport } ?? false }

    /// Whether the lock screen is in the way of importing: not for the missing key, whose lock screen offers it.
    var lockBlocksImport: Bool { locked && libraryProblem != .needsKey }

    func setLibraryProblem(_ problem: LibraryProblem?) {
        if let problem { lastLibraryProblem = problem }
        libraryProblem = problem
    }

    /// Runs the opening again from the start (File reading included): clears the problem and loads. A tap that ends
    /// in a problem again counts once, so Erase is offered after one failed Try Again; the automatic retry and a tap
    /// while the iPhone's protected data isn't available never count.
    func retryOpening(tapped: Bool = true) async {
        guard let problem = libraryProblem, problem.offersTryAgain, !retryingOpen else { return }
        let counts = tapped && protectedDataAvailable
        retryingOpen = true
        defer { retryingOpen = false }
        // A library closed by a failed read must be closed before it is opened again.
        await libraryClosing?.value
        setLibraryProblem(nil)
        await openSavedLibrary()
        if counts, libraryProblem != nil { failedRetries += 1 }
    }

    /// Protected data became available (iPhone and iPad, after the first unlock): a launch before it, or while the
    /// device was locked, failed for a reason that ends by itself. If the library opens now with App Lock on, the
    /// person lands on the lock screen, never on the journals.
    func protectedDataBecameAvailable() async {
        protectedDataAvailable = true
        await retryOpening(tapped: false)
    }

    /// The first read failed, or opening did: nothing of the library stays open, nothing keeps running for it and the
    /// problem is shown. A problem state never has a live store.
    func close(becoming problem: LibraryProblem) async {
        let failed = store
        setLibraryProblem(problem)
        connection = nil
        store = nil
        masterKey = nil
        configureSync()
        locked = false
        error = nil
        openingJournals = false
        unlockState.problem = false
        unlockState.promptPending = false
        guard let failed else { return }
        // The next try waits for this, so it can never overlap a handle on the same file.
        let closing = Task {
            do { try await failed.close() } catch {
                Logger(subsystem: "org.privatejournal", category: "library").error("A library couldn’t be closed.")
            }
        }
        libraryClosing = closing
        await closing.value
    }

    /// Opening failed, or the first read did: a newer version shows its own screen, everything else one screen.
    func failOpening(_ failure: Error) async {
        let kind = LocalDataFailure(classifying: failure)
        let problem: LibraryProblem
        if failure as? JournalError == .notEncrypted {
            problem = .notEncrypted
        } else {
            problem = kind == .needsUpdate ? .newerVersion : .cantOpen
        }
        let failed = failure as NSError
        Logger(subsystem: "org.privatejournal", category: "library").error(
            "The journals couldn’t be opened: \(failed.domain, privacy: .private), \(failed.code, privacy: .private).")
        await close(becoming: problem)
    }

    /// The missing key's lock screen: only the recovery credential, an archive or Erase can go on.
    func lockForMissingDeviceKey() {
        masterKey = nil
        locked = true
        error = missingDeviceKeyMessage
        setLibraryProblem(.needsKey)
    }

    /// Whether the state needs the device owner before something is removed: App Lock is on, or the settings can't be
    /// read, so whether it is on can't be known.
    var removalNeedsAuthentication: Bool { appLockOn || libraryProblem == .settingsUnread }

    /// Connecting, pairing and starting a journal replace the library, so they refuse while it can't be opened: the
    /// refusal fails early with good copy, and `persistConfiguration` is the backstop behind it.
    func requireJournalsOpen() throws {
        guard libraryProblem == nil, !retryingOpen else { throw LibraryNotOpenError() }
    }

    /// Reports a failure the way every action does, except one that was already shown as a problem screen. A save
    /// that is needed first stays typed until the alert is drawn, which then chooses its words and its Try Again
    /// button together (`showsSaveRequiredAlert`).
    func report(_ failure: Error, _ operation: FailureMessage.Operation) {
        guard !(failure is LibraryOpenHandled) else { return }
        if case JournalError.saveRequired = failure {
            // The failed save that made the operation stop has just shown its own text; this one replaces it, as the
            // old sentence did. Saved again in the meantime: there is nothing to say, and nothing is kept.
            saveRequiredAlert = saveFailure ? .saveRequired : nil
            error = nil
            return
        }
        error = failure.shown(operation)
    }

    /// The alert for an operation that needed the open entry saved first, while saving still fails. Once a retry
    /// has saved the entry there is nothing to tell (`saveFailure` clears `saveRequiredAlert`).
    var showsSaveRequiredAlert: Bool { saveRequiredAlert != nil && saveFailure }

    /// What the app's alert says, or nil when it has nothing to say. The words for an unsaved entry are chosen here,
    /// together with the alert's Try Again button, which shows while `saveFailure` holds.
    var alertText: String? {
        error ?? (showsSaveRequiredAlert ? FailureMessage.saveRequiredWithTryAgain : nil)
    }

    func dismissAlert() {
        error = nil
        saveRequiredAlert = nil
    }
}
