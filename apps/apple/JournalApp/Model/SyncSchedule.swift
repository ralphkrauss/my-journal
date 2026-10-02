import CryptoKit
import Foundation
import JournalCore

/// When synchronizations run apart from the regular pace.
@MainActor final class SyncTiming {
    /// The synchronization that sends writing once it paused.
    var afterWriting: Task<Void, Never>?
    /// Images the last synchronization left to download; the next one follows without the usual wait.
    var imagesToDownload = 0
    /// How long a server that limited requests asked to wait.
    var retryAfter: TimeInterval?
    /// When a state in which automatic sync stops was last checked; becoming active checks again after a while.
    var stoppedCheckAt: Date?
    /// The network came back: a waiting retry runs at once.
    lazy var networkReturn = NetworkReturn()
}

extension AppModel {
    /// The usual time between automatic syncs while My Journal is the active app, in seconds.
    static let syncInterval: TimeInterval = 3
    /// The time between automatic syncs while My Journal is open but another app is active, such as a Mac window
    /// behind others. Becoming active syncs at once.
    static let inactiveSyncInterval: TimeInterval = 30

    /// The wait before the next automatic sync: the usual interval, doubling after each failure in a row up to five
    /// minutes, so an unreachable server isn't asked every few seconds.
    static func syncDelay(afterFailures failures: Int) -> TimeInterval {
        min(300, syncInterval * pow(2, Double(min(failures, 10))))
    }

    /// How often a state in which automatic sync stops is checked again when the app becomes active.
    static let stoppedCheckInterval: TimeInterval = 10 * 60

    /// Syncs automatically while the app is open and unlocked; the caller cancels this while the app is in the
    /// background and starts it again when the app becomes active. A successful sync, including one the person
    /// starts, unlocking and the network returning end the wait, and so does the app becoming active while syncing
    /// normally. In states where retrying can't help it doesn't sync, except once when the app becomes active, at most
    /// every `stoppedCheckInterval` (docs/design/sync-health-and-recovery.md §2).
    func synchronizeAutomatically() async {
        var failures = 0
        var nextAttempt = Date.distantPast
        var wasLocked = false
        var wasActive = applicationActive
        if automaticSyncStopped, let checked = syncTiming.stoppedCheckAt,
            Date().timeIntervalSince(checked) >= Self.stoppedCheckInterval
        {
            syncTiming.stoppedCheckAt = nil
        }
        while !Task.isCancelled {
            if locked {
                wasLocked = true
            } else {
                // A sync that succeeded meanwhile, such as Sync Now, ends the wait; so does the network returning.
                let networkReturned = syncTiming.networkReturn.take()
                if wasLocked || (failures > 0 && !syncFailed) || networkReturned {
                    wasLocked = false
                    failures = 0
                    nextAttempt = .distantPast
                }
                // Returning to My Journal shows what changed elsewhere meanwhile at once.
                if applicationActive && !wasActive && failures == 0 { nextAttempt = .distantPast }
                wasActive = applicationActive
                // While a save or library change is pending, sync() does nothing; that isn't a failed attempt.
                if Date() >= nextAttempt, !replacingVault, !saveFailure, !waitsForPerson {
                    // A record or image that can't sync sets syncError while the rest succeeds; that isn't a failure.
                    failures = await sync(waitingForWritingPause: true) ? 0 : failures + 1
                    nextAttempt = Date().addingTimeInterval(nextSyncDelay(afterFailures: failures))
                }
            }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        }
    }

    /// Automatic sync waits for the person, unless this state wasn't checked since the app became active.
    private var waitsForPerson: Bool { automaticSyncStopped && syncTiming.stoppedCheckAt != nil }

    /// The wait before the next automatic sync. A new device downloads its images over several synchronizations
    /// without pausing; another app being active slows the usual pace; a server or certificate that needs fixing is
    /// checked every five minutes; a server that limited requests is given the time it asked for.
    func nextSyncDelay(afterFailures failures: Int) -> TimeInterval {
        if failures == 0 && syncTiming.imagesToDownload > 0 { return 0 }
        var delay = Self.syncDelay(afterFailures: failures)
        // Only the usual pace slows; retries after a failure keep their own waits.
        if failures == 0 && !applicationActive { delay = Self.inactiveSyncInterval }
        if syncHealth?.kind == .updateOrFix { delay = Self.syncDelay(afterFailures: 10) }
        if let retryAfter = syncTiming.retryAfter { delay = max(delay, retryAfter) }
        return delay
    }
}

extension AppModel {
    /// Sends writing to the server once it has paused (`SyncEngine.writingPause`), rather than every few seconds
    /// while it continues. Saving on this device stays immediate.
    func syncWhenWritingPauses() {
        guard syncEngine != nil else { return }
        syncTiming.afterWriting?.cancel()
        syncTiming.afterWriting = Task {
            try? await Task.sleep(nanoseconds: UInt64((SyncEngine.writingPause + 0.25) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Retrying can't help in this state: only the count of what waits changes.
            if automaticSyncStopped {
                await refreshPendingItems()
            } else {
                await sync()
            }
        }
    }

    /// Sends the writing of an entry that was just left, without waiting for the pause.
    func sendWritingAfterLeaving() {
        guard syncEngine != nil, pendingSync else { return }
        Task {
            _ = await finishPendingSave()
            await sendWriting()
        }
    }

    /// Sends saved writing now: when leaving an entry, locking, going to the background or quitting. The journals
    /// may already be locked; nothing is shown then.
    func sendWriting() async {
        guard !replacingVault, !saveFailure, !automaticSyncStopped, let syncEngine else { return }
        syncTiming.afterWriting?.cancel()
        if !locked {
            await sync()
        } else {
            _ = try? await syncEngine.synchronize()
        }
    }

    /// Sends saved writing while quitting, for at most `seconds`: quitting never waits longer on the network.
    func sendWritingBeforeQuitting(within seconds: Double) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.sendWriting() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
    }
}

/// When this device last synchronized completely with its server, and whether a sync the person started runs, for
/// Settings > Sync (docs/design/sync-now-and-done.md). Kept apart from AppModel, so the time every automatic sync
/// records redraws only what shows it. The time is stored per library and connection, written at most once a minute
/// and when the app leaves the screen, and forgotten when the library connects to another server.
@MainActor final class SyncActivity: ObservableObject {
    @Published private(set) var lastSynced: Date?
    @Published fileprivate(set) var syncingNow = false
    /// Entries, journals and templates saved here that the server hasn't accepted yet.
    @Published var pendingItems = 0
    private let defaults: UserDefaults
    private let storageKey: String
    private var connectionKey: String?
    private var storedAt: Date?

    init(directory: URL, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storageKey = "lastSynced-" + Self.digest(directory.standardizedFileURL.path)
    }

    /// Follows the library's connection: the time stored for it, or none for another server.
    func connectionChanged(_ connection: SyncConnection?) {
        let key = connection.map { Self.digest($0.address + "\n" + $0.deviceID.uuidString) }
        guard key != connectionKey else { return }
        connectionKey = key
        storedAt = nil
        let stored = defaults.dictionary(forKey: storageKey)
        if let key, stored?["connection"] as? String == key, let date = stored?["date"] as? Date {
            lastSynced = date
        } else {
            lastSynced = nil
            defaults.removeObject(forKey: storageKey)
        }
    }

    /// A synchronization completed, including one that left a refused entry or image behind.
    func synced(at date: Date = Date()) {
        lastSynced = date
        if storedAt.map({ date.timeIntervalSince($0) >= 60 }) ?? true { persist() }
    }

    func persist() {
        guard let connectionKey, let lastSynced, storedAt != lastSynced else { return }
        defaults.set(["connection": connectionKey, "date": lastSynced], forKey: storageKey)
        storedAt = lastSynced
    }

    /// "Just now", a relative time within a day, then the date and time: "Yesterday at 21:14", "12 Sept at 08:03".
    static func description(of date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if elapsed < 24 * 60 * 60 {
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            formatter.formattingContext = .beginningOfSentence
            return formatter.localizedString(for: date, relativeTo: now)
        }
        let time = date.formatted(date: .omitted, time: .shortened)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday at \(time)"
        }
        let day =
            calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(day) at \(time)"
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppModel {
    /// Whether a sync can run now; otherwise `sync()` returns without syncing.
    var canSyncNow: Bool { !locked && !replacingVault && !saveFailure && syncEngine != nil }

    /// Sync Now and Try Again: one at a time, shown as "Syncing…" for at least half a second so it reads as done
    /// rather than as a flicker, then announced to VoiceOver. A sync that can't run isn't shown as synced.
    func syncNow() async {
        guard !syncActivity.syncingNow else { return }
        syncActivity.syncingNow = true
        let started = Date()
        let ran = canSyncNow
        let before = syncActivity.lastSynced
        let succeeded = ran ? await sync(retryingRefused: true) : false
        let synced = succeeded && syncActivity.lastSynced != before
        let remaining = 0.5 - Date().timeIntervalSince(started)
        if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        syncActivity.syncingNow = false
        guard ran else { return }
        JournalAccessibility.announce(syncError ?? (synced ? "Synced" : "Couldn’t sync."))
    }

}
