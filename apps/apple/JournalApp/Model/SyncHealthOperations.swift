import Foundation
import JournalCore
import Network

/// The single action a sync state offers in Settings ▸ Sync and Sync Status
/// (docs/design/sync-health-and-recovery.md §2; one Reconnect, docs/design/1-1-conflicts-and-reconnect.md §7).
enum SyncStatusAction: Equatable {
    case syncNow, tryAgain, checkAgain, reconnect

    var title: String {
        switch self {
        case .syncNow: return "Sync Now"
        case .tryAgain: return "Try Again"
        case .checkAgain: return "Check Again"
        case .reconnect: return "Reconnect…"
        }
    }
    /// Opens Reconnect at this device's server instead of syncing.
    var connects: Bool { self == .reconnect }
}

extension AppModel {
    /// The server's host name, which some messages and the Tailscale hint use.
    var connectionHost: String { connection.map { ServerAddress.host($0.address) } ?? "" }

    /// The single action, from the current state alone.
    var syncStatusAction: SyncStatusAction {
        guard let syncHealth else { return .syncNow }
        switch syncHealth.kind {
        case .temporary, .unexpected: return .tryAgain
        case .needsYou, .serverChanged, .noAccess: return .reconnect
        case .updateOrFix: return .checkAgain
        }
    }

    /// The server doesn't accept this device as it is: Reconnect is the way back, and Devices has nothing to list.
    var serverRefusesThisDevice: Bool {
        [.needsYou, .serverChanged, .noAccess].contains(syncHealth?.kind)
    }

    /// The person must act, as opposed to waiting while it syncs by itself.
    var syncNeedsAttention: Bool {
        // Without a failure, a message is about one record or image the server didn't take.
        guard let syncHealth else { return syncError != nil }
        return syncHealth.kind != .temporary
    }

    /// Sync Status shows only when the person must act, or when sync has kept failing while changes waited more
    /// than a day. Syncing normally and retrying by itself stay out of sight, so writing never changes the toolbar
    /// (docs/design/sync-health-and-recovery.md §4.2, as amended on 2026-10-02).
    var showsSyncStatus: Bool {
        connection != nil && (syncNeedsAttention || syncLongWait)
    }

    /// Changes have waited more than about a day while sync fails, measured from the last successful sync, or from
    /// the first failure when there was none (docs/design/sync-health-and-recovery.md §2, Long waits). Waiting alone
    /// isn't enough: at launch, changes from days ago wait only until the first sync.
    func syncWaitedLong(now: Date = Date()) -> Bool {
        guard pendingSync, syncFailed, let since = syncActivity.lastSynced ?? syncTiming.failingSince else {
            return false
        }
        return now.timeIntervalSince(since) > Self.longSyncWait
    }
    static let longSyncWait: TimeInterval = 24 * 60 * 60

    /// Checks the long wait after each sync, which also runs when the app becomes active.
    func updateSyncLongWait(now: Date = Date()) {
        let waited = syncWaitedLong(now: now)
        if syncLongWait != waited { syncLongWait = waited }
    }

    /// Automatic sync waits for the person: retrying can't help in this state.
    var automaticSyncStopped: Bool { syncHealth?.stopsAutomaticSync == true }

    func recordSyncHealth(_ health: SyncHealth?, failure: Error?) {
        if syncHealth != health { syncHealth = health }
        // Reconnect… opens Reconnect, which signs in to this device's server straight away; any other state, or a sync
        // that succeeds, ends that.
        let signIn = health == .signInNeeded
        if encryption.turnedOnElsewhere != signIn { encryption.turnedOnElsewhere = signIn }
        syncTiming.retryAfter = (failure as? ServerRateLimited)?.retryAfter
        if health?.stopsAutomaticSync == true { syncTiming.stoppedCheckAt = Date() }
        if health == nil {
            syncTiming.failingSince = nil
        } else if syncTiming.failingSince == nil {
            syncTiming.failingSince = Date()
        }
    }

    /// The sync state's message, worded for this library (a library without a password names a recovery code).
    func syncMessage(of health: SyncHealth) -> String {
        health.message(host: connectionHost, hasPassword: configuration?.requiresPassword != false)
    }

    /// Sync Settings… in Sync Status: Settings at Sync, where the state is explained and fixed.
    func openSyncSettings() {
        #if os(macOS)
            settingsTab = .sync
        #else
            settingsRequestedTab = .sync
        #endif
        settingsPresented = true
    }

    func resetSyncHealth() {
        if syncHealth != nil { syncHealth = nil }
        if encryption.turnedOnElsewhere { encryption.turnedOnElsewhere = false }
        if syncError != nil { syncError = nil }
        if syncFailed { syncFailed = false }
        syncTiming.stoppedCheckAt = nil
        syncTiming.retryAfter = nil
        syncTiming.failingSince = nil
        if syncLongWait { syncLongWait = false }
    }

    /// Reads how many items wait for the server, for Settings ▸ Sync.
    func refreshPendingItems() async {
        var count = 0
        if let store, connection != nil { count = (try? await store.pendingItemCount()) ?? 0 }
        if syncActivity.pendingItems != count { syncActivity.pendingItems = count }
    }

    /// Runs `action`. Actions that connect call `presentConnection`, which shows Connect to a Server where the
    /// person is: over Settings, or over the journal window.
    func perform(_ action: SyncStatusAction, presentConnection: () -> Void) {
        if action.connects {
            presentConnection()
        } else {
            Task { await syncNow() }
        }
    }

    /// Reconnect goes straight to this device's server: after it was set up again, after access was removed or the
    /// server was restored, or after encryption was turned on elsewhere.
    var reconnectsOnConnect: Bool { encryption.offersSignIn || serverRefusesThisDevice }

    /// The device list was refused as unauthorised: learns why with a sync, which sets the state Settings ▸ Sync
    /// explains. Without an answer the device was removed. Devices then has nothing to show.
    func learnWhyAccessWasRefused() async {
        await sync()
        guard !serverRefusesThisDevice else { return }
        recordSyncHealth(.accessRemoved, failure: nil)
        syncError = syncMessage(of: .accessRemoved)
    }

    /// Stop Syncing… (docs/design/sync-health-and-recovery.md §4.4): this device stops using its server and keeps its
    /// library as it is, including what hasn't been sent and the identity it last synced with, so connecting again
    /// later joins by identity. Its access is given up when the server still accepts it, unless `revoking` is false.
    func stopSyncing(revoking: Bool = true) {
        guard let previous = connection, !replacingVault else { return }
        try? Keychain.remove(configuration?.connectionKeyID ?? keyAccount + "-connection")
        connection = nil
        agentDeclines.cancelAll()
        configureSync()
        syncTiming.afterWriting?.cancel()
        syncActivity.pendingItems = 0
        encryption.turnedOnElsewhere = false
        guard revoking else { return }
        Task {
            try? await ServerClient(address: previous.address, token: previous.token).revoke(previous.deviceID)
        }
    }
}

/// Starts a sync as soon as the network returns, instead of waiting for the backoff to end.
@MainActor final class NetworkReturn {
    private let monitor = NWPathMonitor()
    private var satisfied = true
    /// The network came back since this was last read.
    private(set) var returned = false
    /// The path's status and interfaces as last reported; any change ends a wait for the server's changes.
    private var path: String?
    var onPathChange: (@MainActor () -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            let description = "\(path.status) " + path.availableInterfaces.map(\.name).joined(separator: ",")
            Task { @MainActor in self?.update(available: available, path: description) }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkReturn"))
    }
    deinit { monitor.cancel() }

    func update(available: Bool, path description: String? = nil) {
        if available && !satisfied { returned = true }
        satisfied = available
        if let description {
            if let previous = path, previous != description { onPathChange?() }
            path = description
        }
    }
    /// Whether the network returned since the last call.
    func take() -> Bool {
        defer { returned = false }
        return returned
    }
}
