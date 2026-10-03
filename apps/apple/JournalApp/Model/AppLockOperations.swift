import JournalCore
import SwiftUI
import os

/// How turning App Lock on or off from Settings ended.
enum AppLockChange: Equatable {
    case saved
    /// The request was cancelled, or the app locked meanwhile. Nothing changed and nothing needs saying.
    case cancelled
    /// The device can't authenticate its owner now, for example without a passcode. Nothing changed.
    case unavailable
    /// The change couldn't be saved; App Lock stays as it was.
    case notSaved
}

/// Why App Lock turned itself off, said once in an alert.
enum AppLockTurnedOff: Equatable {
    /// The device no longer has a passcode or login password.
    case passcodeRemoved
    /// This device used an App Lock PIN, and has no passcode to use instead.
    case pinRetired
}

/// Where unlocking with the device's authentication stands (docs/design/app-lock-system-auth.md).
struct DeviceUnlockState {
    /// Counts locks, so that a success answering an earlier lock is never applied.
    var lockCount = 0
    /// The system's request is showing.
    var authenticating = false
    /// The system's request made the app inactive, and the app has been neither active nor in the background since.
    /// Face ID's panel keeps the app inactive for about a second after a success; the answer needn't wait for it.
    var inactiveForRequest = false
    /// The system's request is in front of the app, or its panel is still closing: nothing covers the window.
    var requestInFront: Bool { authenticating || inactiveForRequest }
    /// The system is asked without a tap once the app is active: at launch, and on iPhone and iPad after the app
    /// returns from the background.
    var promptPending = false
    /// A success that arrived while the app wasn't active, applied when it is if no lock happened meanwhile.
    var pendingSuccess: (lockCount: Int, sessionID: UUID)?
    /// Unlocking failed or couldn't be asked: the lock screen says so and offers the recovery credential.
    var problem = false
    /// What the device last reported, for naming the method.
    var availability: DeviceOwnerAvailability?
    /// App Lock turned itself off; the alert says why once.
    var turnedOff: AppLockTurnedOff?
}

extension DeviceOwnerAvailability {
    /// The method to name, with the passcode or login password when the device can't say.
    var method: DeviceUnlockMethod {
        if case .available(let method) = self { return method }
        #if os(macOS)
            return .loginPassword
        #else
            return .passcode
        #endif
    }
}

extension AppModel {
    var appLockOn: Bool { configuration?.appLock == true }

    /// The system's reason text: shown as is on iOS, and after "My Journal is trying to" on the Mac.
    static func authenticationReason(_ reason: String) -> String {
        #if os(macOS)
            return reason.prefix(1).lowercased() + reason.dropFirst()
        #else
            return reason
        #endif
    }

    /// Reads again what the device can authenticate with, for Settings and the lock screen.
    func refreshDeviceOwnerAvailability() {
        let availability = deviceOwner.availability()
        if unlockState.availability != availability { unlockState.availability = availability }
    }

    /// Turns App Lock on or off once the device owner has authenticated.
    func setAppLock(_ on: Bool) async -> AppLockChange {
        guard !locked, configuration != nil, !unlockState.authenticating else { return .cancelled }
        guard appLockOn != on else { return .saved }
        refreshDeviceOwnerAvailability()
        if on {
            guard case .available = unlockState.availability else { return .unavailable }
        }
        let lockCount = unlockState.lockCount
        unlockState.authenticating = true
        let outcome = await deviceOwner.authenticate(
            reason: Self.authenticationReason(on ? "Turn on App Lock" : "Turn off App Lock"))
        unlockState.authenticating = false
        guard !locked, lockCount == unlockState.lockCount, appLockOn != on else { return .cancelled }
        switch outcome {
        case .success:
            break
        case .noPasscode where !on:
            // Only the device owner can remove the passcode, and without it there is nothing to ask.
            break
        case .noPasscode:
            return .unavailable
        case .cancelled, .failed:
            return .cancelled
        }
        return saveAppLock { configuration in
            configuration.appLock = on ? true : nil
            configuration.pinRetiredNotice = nil
        }
            ? .saved : .notSaved
    }

    /// Applies an App Lock change only once it's saved: after a failed save the previous setting stays in force,
    /// so Settings never shows App Lock differently from how the next launch will open.
    private func saveAppLock(_ change: (inout LocalConfiguration) -> Void) -> Bool {
        guard var next = configuration else { return false }
        let previous = configuration
        change(&next)
        configuration = next
        do {
            try persistConfiguration()
            return true
        } catch {
            configuration = previous
            return false
        }
    }

    /// Moves a device that used an App Lock PIN to the device's own authentication, and removes the PIN's verifier
    /// and attempt count. Nothing was ever encrypted with the PIN, so nothing else changes. A failed save leaves
    /// App Lock on in memory, and the next launch moves it again.
    func retireAppLockPIN() {
        guard let current = configuration else { return }
        let hadPIN = current.pinHash != nil
        guard
            hadPIN || current.pinSalt != nil || current.useBiometrics != nil || current.failedUnlocks != nil
                || current.unlockRetryAfter != nil
        else { return }
        configuration?.pinSalt = nil
        configuration?.pinHash = nil
        configuration?.useBiometrics = nil
        configuration?.failedUnlocks = nil
        configuration?.unlockRetryAfter = nil
        if hadPIN && current.appLock == nil {
            configuration?.appLock = true
            configuration?.pinRetiredNotice = true
        }
        do { try persistConfiguration() } catch {
            Logger(subsystem: "org.privatejournal", category: "app-lock").error("Could not save the App Lock change.")
        }
    }
}

extension AppModel {
    func lock() async {
        // Writing in the open entry and in open sheets is saved first, for a moment at most (LockSaving.swift).
        if appLockOn && !locked {
            await saveBeforeLocking()
            // Another lock finished meanwhile and saved for itself.
            guard !locked else { return }
        }
        guard lockImmediately() else { return }
        await saveWhileLocked()
    }
    /// After locking: saves writing that isn't stored yet. An unchanged or read-only entry is left as it is.
    func saveWhileLocked() async {
        _ = await flush()
        await sendWriting()
    }
    func storeForUnlock() -> JournalStore? {
        guard locked, !Task.isCancelled, !replacingVault else { return nil }
        guard masterKey != nil else {
            error = "Your device key is unavailable. Use your recovery key to unlock your journals."
            return nil
        }
        guard let store else {
            if error == nil { error = "Your journals couldn’t be opened. Quit and reopen My Journal." }
            return nil
        }
        return store
    }
    /// Reads the journals the lock had cleared. Until they're read, the list shows no empty state, which would
    /// offer to create a journal or an entry.
    func readJournalsAfterUnlocking() async throws {
        let session = vaultSessionID
        openingJournals = true
        // A lock meanwhile clears it; a later unlock then reads for itself.
        defer { if vaultSessionID == session { openingJournals = false } }
        try await refresh()
        await retryUnsavedImageDescriptions()
    }
    func canFinishUnlock(_ store: JournalStore, sessionID: UUID) -> Bool {
        !Task.isCancelled && !replacingVault && masterKey != nil
            && self.store === store && vaultSessionID == sessionID
    }

    /// The lock screen's prompt without a tap, once per lock and only while the app is active.
    func promptToUnlockIfPending() async {
        guard unlockState.promptPending, applicationActive, locked, appLockOn, masterKey != nil else { return }
        unlockState.promptPending = false
        await unlockWithDevice()
    }

    /// The app is no longer active. On iPhone and iPad, when the system's request made it so, its answer is still
    /// applied at once. The Mac waits: a window stays visible behind the app the person may have switched to.
    func applicationResignedActive() {
        applicationActive = false
        #if os(iOS)
            if unlockState.authenticating { unlockState.inactiveForRequest = true }
        #endif
    }

    /// The app entered the background on iPhone or iPad: it locks, and asks for Face ID once it is in front again.
    /// When the device itself locks, iOS ends the app's active state and moves it to the background within the
    /// same moment, before the resign-active notification above has been handled. Without marking the app inactive
    /// here, the lock screen appearing in the background would ask for Face ID over the iPhone's own Lock Screen.
    func applicationEnteredBackground() {
        applicationActive = false
        lockImmediately(prompting: true)
    }

    /// The app became active: applies a success that arrived meanwhile, or asks as the lock screen appears.
    func applicationBecameActive() async {
        applicationActive = true
        if unlockState.inactiveForRequest {
            unlockState.inactiveForRequest = false
            #if os(iOS)
                // Unlocked behind the closing panel, which had VoiceOver's focus: it moves to the journals now.
                if !locked { JournalAccessibility.screenChanged() }
            #endif
        }
        // A passcode set or Face ID allowed meanwhile changes what the lock screen and Settings offer.
        if configuration != nil { refreshDeviceOwnerAvailability() }
        if let pending = unlockState.pendingSuccess {
            unlockState.pendingSuccess = nil
            if pending.lockCount == unlockState.lockCount, let store = storeForUnlock() {
                await finishDeviceUnlock(store, sessionID: pending.sessionID)
            }
            return
        }
        await promptToUnlockIfPending()
    }

    /// Unlocks with Face ID, Touch ID or Optic ID, or the device passcode or Mac login password.
    func unlockWithDevice() async {
        guard locked, appLockOn, !unlockState.authenticating, let store = storeForUnlock() else { return }
        let sessionID = vaultSessionID
        let lockCount = unlockState.lockCount
        refreshDeviceOwnerAvailability()
        switch unlockState.availability {
        case .noPasscode:
            await turnOffWithoutPasscode(store, sessionID: sessionID)
            return
        case .unavailable, nil:
            unlockState.problem = true
            return
        case .available:
            break
        }
        unlockState.authenticating = true
        unlockState.problem = false
        let outcome = await deviceOwner.authenticate(reason: Self.authenticationReason("Unlock your journals"))
        unlockState.authenticating = false
        // A lock while the system was asking answers nothing: the request belonged to the earlier lock.
        guard locked, appLockOn, lockCount == unlockState.lockCount else { return }
        switch outcome {
        case .success:
            // Inactive only because of the request (Face ID's panel is closing): the journals appear behind it.
            if applicationActive || unlockState.inactiveForRequest {
                await finishDeviceUnlock(store, sessionID: sessionID)
            } else {
                unlockState.pendingSuccess = (lockCount, sessionID)
            }
        case .cancelled:
            break
        case .noPasscode:
            await turnOffWithoutPasscode(store, sessionID: sessionID)
        case .failed:
            unlockState.problem = true
        }
    }

    private func finishDeviceUnlock(_ store: JournalStore, sessionID: UUID) async {
        guard locked, applicationActive || unlockState.inactiveForRequest, canFinishUnlock(store, sessionID: sessionID)
        else { return }
        var authenticated = false
        do {
            authenticated = true
            locked = false
            error = nil
            unlockState.problem = false
            clearRetiredPINNotice()
            try await readJournalsAfterUnlocking()
            guard !locked, canFinishUnlock(store, sessionID: sessionID) else { return }
            if draft == nil { selectInitialEntry(reveal: true) }
        } catch {
            guard locked || authenticated, canFinishUnlock(store, sessionID: sessionID) else { return }
            self.error = error.localizedDescription
        }
    }

    /// Only the device owner can remove the passcode (or a Mac's login password), so App Lock turns off and says so
    /// rather than locking the journals away. Checked once, while the app is active.
    private func turnOffWithoutPasscode(_ store: JournalStore, sessionID: UUID) async {
        guard applicationActive else {
            unlockState.promptPending = true
            return
        }
        let reason: AppLockTurnedOff = configuration?.pinRetiredNotice == true ? .pinRetired : .passcodeRemoved
        configuration?.appLock = nil
        configuration?.pinRetiredNotice = nil
        do { try persistConfiguration() } catch {
            // Open for now; the next launch finds the same and turns App Lock off again.
            Logger(subsystem: "org.privatejournal", category: "app-lock").error("Could not save the App Lock change.")
        }
        unlockState.turnedOff = reason
        await finishDeviceUnlock(store, sessionID: sessionID)
    }

    func clearRetiredPINNotice() {
        guard configuration?.pinRetiredNotice == true else { return }
        configuration?.pinRetiredNotice = nil
        do { try persistConfiguration() } catch {
            // Shown once more at the next lock; nothing else depends on it.
            Logger(subsystem: "org.privatejournal", category: "app-lock").error("Could not save the App Lock change.")
        }
    }
}
