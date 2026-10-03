import Combine
import SwiftUI

extension AppModel {
    /// The person used My Journal in a way that may not come from the keyboard or pointer, such as Dictation, Voice
    /// Control or VoiceOver editing the entry or choosing another (docs/design/mac-inactivity-lock-2026-10-03.md).
    func noteUse() {
        #if os(macOS)
            inactivityLock?.noteUse()
        #endif
    }
}

#if os(macOS)
    import AppKit
    import os

    /// The clock an inactivity lock measures with and its one scheduled wake-up. Tests use their own.
    @MainActor
    protocol InactivityClock: AnyObject {
        var now: ContinuousClock.Instant { get }
        /// Calls `action` once at `deadline`, unless the returned value is cancelled or released first.
        func wake(at deadline: ContinuousClock.Instant, _ action: @escaping @MainActor @Sendable () -> Void)
            -> AnyCancellable
    }

    /// The continuous clock, which keeps counting while the Mac sleeps.
    @MainActor
    final class SystemInactivityClock: InactivityClock {
        var now: ContinuousClock.Instant { .now }
        func wake(at deadline: ContinuousClock.Instant, _ action: @escaping @MainActor @Sendable () -> Void)
            -> AnyCancellable
        {
            let task = Task { @MainActor in
                // Tolerance lets the system combine wake-ups; any input after the deadline locks anyway.
                try? await Task.sleep(until: deadline, tolerance: .seconds(5), clock: .continuous)
                guard !Task.isCancelled else { return }
                action()
            }
            return AnyCancellable { task.cancel() }
        }
    }

    /// Locks App Lock's journals once My Journal hasn't been used for the chosen time, and when the Mac sleeps or
    /// switches to another user (docs/design/mac-inactivity-lock-2026-10-03.md).
    ///
    /// Input only records its time. One wake-up waits for the deadline and, if there was input meanwhile, waits once
    /// more for the new one, so nothing runs per event and nothing polls.
    @MainActor
    final class InactivityLock {
        static let defaultMinutes = 30
        /// The choices in Settings, in minutes; 0 is Never.
        static let choices = [5, 15, 30, 60, 0]

        private weak var model: AppModel?
        private let clock: InactivityClock
        private let intervalOverride: Duration?
        /// The time without use after which it locks, while it may lock: App Lock on, unlocked, and not Never.
        private(set) var interval: Duration?
        private var lastUse: ContinuousClock.Instant
        /// An action the person started is in progress in the model, such as connecting or importing.
        private var modelBusy = false
        /// Sheets running an action, such as adding a device, hold the time too.
        private var holders: Set<UUID> = []
        private var wakeUp: AnyCancellable?
        /// Saving and locking after the deadline. Input meanwhile is discarded.
        private(set) var locking: Task<Void, Never>?
        private var subscriptions: Set<AnyCancellable> = []
        private var monitor: Any?
        private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

        init(
            model: AppModel, clock: InactivityClock = SystemInactivityClock(),
            intervalOverride: Duration? = InactivityLock.testInterval
        ) {
            self.model = model
            self.clock = clock
            self.intervalOverride = intervalOverride
            lastUse = clock.now
        }

        /// Debug builds only: a short interval for checking the real app, from the launch environment.
        static var testInterval: Duration? {
            #if DEBUG
                let value = ProcessInfo.processInfo.environment["JOURNAL_UI_TEST_INACTIVITY_LOCK_SECONDS"]
                if let seconds = value.flatMap(Double.init), seconds > 0 { return .seconds(seconds) }
            #endif
            return nil
        }

        /// The interval for a stored choice: nil is the default, 0 is Never.
        static func interval(minutes: Int?, override: Duration?) -> Duration? {
            let minutes = minutes ?? defaultMinutes
            guard minutes > 0 else { return nil }
            return override ?? .seconds(minutes * 60)
        }

        /// Pointer movement counts only while My Journal is the active app: passing over its window while working
        /// in another app isn't use.
        nonisolated static func counts(_ type: NSEvent.EventType, applicationActive: Bool) -> Bool {
            type == .mouseMoved ? applicationActive : true
        }

        private static let watchedEvents: NSEvent.EventTypeMask = [
            .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged,
            .rightMouseDragged, .otherMouseDragged, .mouseMoved, .scrollWheel, .magnify, .rotate, .swipe,
            .smartMagnify,
        ]

        /// Follows App Lock, the lock, the setting and actions in progress, and watches the system.
        func start() {
            guard let model, subscriptions.isEmpty else { return }
            // Published values arrive before the properties change, so only the values passed are read.
            let busy = Publishers.CombineLatest4(
                model.$vaultReplacement, model.$committingMutation, model.$connectingToServer,
                model.$joinPhase.map { $0 != nil }
            ).map { $0 || $1 || $2 || $3 }
            model.$locked.combineLatest(model.$configuration, busy.removeDuplicates())
                .sink { [weak self] locked, configuration, busy in
                    self?.follow(locked: locked, configuration: configuration, busy: busy)
                }
                .store(in: &subscriptions)
            observeSystem()
        }

        func stop() {
            subscriptions.removeAll()
            for observer in observers { observer.center.removeObserver(observer.token) }
            observers = []
            interval = nil
            updateMonitor()
            wakeUp = nil
        }

        /// Records use. After the deadline it locks instead, and returns false: that input is discarded, so it never
        /// acts on the journals.
        @discardableResult func noteUse() -> Bool {
            guard interval != nil else { return true }
            guard locking == nil else { return false }
            if overdue {
                startLocking()
                return false
            }
            lastUse = clock.now
            return true
        }

        /// Locks if the deadline passed while the wake-up couldn't run, such as during sleep or App Nap.
        func checkDeadline() {
            if locking == nil && overdue { startLocking() }
        }

        /// While `held`, an action the person started is in progress for `holder`; the time starts again when the
        /// last one ends.
        func hold(_ held: Bool, by holder: UUID) {
            let wasHeld = self.held
            if held {
                holders.insert(holder)
            } else {
                holders.remove(holder)
            }
            guard wasHeld != self.held else { return }
            if !self.held { lastUse = clock.now }
            schedule()
        }

        private var held: Bool { modelBusy || !holders.isEmpty }

        private var overdue: Bool {
            guard let interval, !held else { return false }
            return clock.now - lastUse >= interval
        }

        private func follow(locked: Bool, configuration: LocalConfiguration?, busy: Bool) {
            let next =
                locked || configuration?.appLock != true
                ? nil : Self.interval(minutes: configuration?.inactivityLockMinutes, override: intervalOverride)
            let wasHeld = held
            modelBusy = busy
            if next != interval {
                // Arming, and a changed setting, count from now.
                interval = next
                lastUse = clock.now
                updateMonitor()
            } else if wasHeld != held {
                if !held { lastUse = clock.now }
            } else {
                return
            }
            schedule()
        }

        private func schedule() {
            wakeUp = nil
            guard let interval, !held, locking == nil else { return }
            wakeUp = clock.wake(at: lastUse + interval) { [weak self] in self?.deadlineReached() }
        }

        private func deadlineReached() {
            wakeUp = nil
            if overdue {
                startLocking()
            } else {
                schedule()
            }
        }

        /// Locks as Lock My Journal does, which saves what's open first, for a moment at most. Input meanwhile is
        /// discarded.
        private func startLocking() {
            guard locking == nil, let model else { return }
            wakeUp = nil
            locking = Task { [weak self] in
                await model.lock()
                guard let self else { return }
                self.locking = nil
                // Still unlocked only if App Lock changed meanwhile; the time counts afresh.
                self.lastUse = self.clock.now
                self.schedule()
            }
        }

        /// The person stepped away: the Mac sleeps, or another user takes over. Locks whatever the setting, saving
        /// first like every lock.
        private func lockNow() {
            guard let model, model.appLockOn, !model.locked else { return }
            startLocking()
        }

        private func updateMonitor() {
            if interval != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: Self.watchedEvents) { [weak self] event in
                    let type = event.type
                    let keep = MainActor.assumeIsolated {
                        guard let self, Self.counts(type, applicationActive: NSApp.isActive) else { return true }
                        return self.noteUse()
                    }
                    return keep ? event : nil
                }
            } else if interval == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func observeSystem() {
            let workspace = NSWorkspace.shared.notificationCenter
            let center = NotificationCenter.default
            observe(workspace, NSWorkspace.willSleepNotification) { $0.lockNow() }
            observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.lockNow() }
            observe(workspace, NSWorkspace.didWakeNotification) { $0.checkDeadline() }
            observe(center, NSApplication.didBecomeActiveNotification) { $0.checkDeadline() }
            observe(center, NSWindow.didChangeOcclusionStateNotification) { $0.checkDeadline() }
            observe(center, NSMenu.didBeginTrackingNotification) { lock in
                if NSApp.isActive { lock.noteUse() }
            }
        }

        private func observe(
            _ center: NotificationCenter, _ name: Notification.Name,
            _ action: @escaping @MainActor @Sendable (InactivityLock) -> Void
        ) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { action(self) }
                }
            }
            observers.append((center, token))
        }
    }

    extension AppModel {
        /// Lock when inactive, in minutes; 0 is Never.
        var inactivityLockMinutes: Int { configuration?.inactivityLockMinutes ?? InactivityLock.defaultMinutes }

        /// Starts locking after inactivity, once, in the app (not in the process that hosts unit tests).
        func startInactivityLock() {
            guard inactivityLock == nil else { return }
            let lock = InactivityLock(model: self)
            inactivityLock = lock
            lock.start()
        }

        /// Changes Lock when inactive. A longer time or Never weakens App Lock, so the device owner authenticates
        /// first, as for turning it off; a shorter time doesn't ask.
        func setInactivityLock(minutes: Int) async -> AppLockChange {
            guard !locked, appLockOn, !unlockState.authenticating else { return .cancelled }
            let current = inactivityLockMinutes
            guard minutes != current else { return .saved }
            let weakens = minutes <= 0 || (current > 0 && minutes > current)
            if weakens {
                guard await authenticateToWeakenLock() else { return .cancelled }
                guard !locked, appLockOn, inactivityLockMinutes == current else { return .cancelled }
            }
            guard let previous = configuration else { return .notSaved }
            configuration?.inactivityLockMinutes = minutes == InactivityLock.defaultMinutes ? nil : minutes
            do {
                try persistConfiguration()
                return .saved
            } catch {
                configuration = previous
                Logger(subsystem: "org.privatejournal", category: "app-lock").error(
                    "Could not save Lock when inactive.")
                return .notSaved
            }
        }

        private func authenticateToWeakenLock() async -> Bool {
            refreshDeviceOwnerAvailability()
            // Only the device owner can remove the login password, and without it there is nothing to ask.
            if unlockState.availability == .noPasscode { return true }
            let lockCount = unlockState.lockCount
            unlockState.authenticating = true
            let outcome = await deviceOwner.authenticate(
                reason: Self.authenticationReason("Change App Lock settings"))
            unlockState.authenticating = false
            guard lockCount == unlockState.lockCount else { return false }
            return outcome == .success || outcome == .noPasscode
        }
    }
#endif
