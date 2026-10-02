import Foundation
import JournalCore
import Network

/// The single action a sync state offers in Settings > Sync and Sync Status
/// (docs/design/sync-health-and-recovery.md §2).
enum SyncStatusAction: Equatable {
    case syncNow, tryAgain, checkAgain, setUpServerAgain, connectAgain, signIn

    var title: String {
        switch self {
        case .syncNow: return "Sync Now"
        case .tryAgain: return "Try Again"
        case .checkAgain: return "Check Again"
        case .setUpServerAgain: return "Set Up Server Again…"
        case .connectAgain: return "Connect Again…"
        case .signIn: return "Sign In…"
        }
    }
    /// Opens Connect to a Server at this device's server instead of syncing.
    var connects: Bool { [.setUpServerAgain, .connectAgain, .signIn].contains(self) }
}

extension AppModel {
    /// The server's host name, which some messages and the Tailscale hint use.
    var connectionHost: String { connection.map { ServerAddress.host($0.address) } ?? "" }

    /// The single action, from the current state alone.
    var syncStatusAction: SyncStatusAction {
        guard let syncHealth else { return .syncNow }
        switch syncHealth.kind {
        case .temporary, .unexpected: return .tryAgain
        case .needsYou: return .signIn
        case .serverChanged: return syncHealth == .serverNotSetUp ? .setUpServerAgain : .connectAgain
        case .noAccess: return .connectAgain
        case .updateOrFix: return .checkAgain
        }
    }

    /// The person must act, as opposed to waiting while it syncs by itself.
    var syncNeedsAttention: Bool {
        // Without a failure, a message is about one record or image the server didn't take.
        guard let syncHealth else { return syncError != nil }
        return syncHealth.kind != .temporary
    }

    /// Sync Status's symbol: the exclamation mark when the person must act or changes have waited a day.
    func syncStatusSymbol(now: Date = Date()) -> String {
        syncNeedsAttention || syncWaitedLong(now: now) ? "exclamationmark.icloud" : "icloud"
    }

    /// Changes have waited more than about a day, measured from the last successful sync: Sync Status then shows
    /// the exclamation mark whatever the state (docs/design/sync-health-and-recovery.md §2, Long waits).
    func syncWaitedLong(now: Date = Date()) -> Bool {
        guard pendingSync, let lastSynced = syncActivity.lastSynced else { return false }
        return now.timeIntervalSince(lastSynced) > Self.longSyncWait
    }
    static let longSyncWait: TimeInterval = 24 * 60 * 60

    /// Automatic sync waits for the person: retrying can't help in this state.
    var automaticSyncStopped: Bool { syncHealth?.stopsAutomaticSync == true }

    func recordSyncHealth(_ health: SyncHealth?, failure: Error?) {
        if syncHealth != health { syncHealth = health }
        // Sign In… opens Connect to a Server, which signs in to this device's server straight away; any other state,
        // or a sync that succeeds, ends that.
        let signIn = health == .signInNeeded
        if encryption.turnedOnElsewhere != signIn { encryption.turnedOnElsewhere = signIn }
        syncTiming.retryAfter = (failure as? ServerRateLimited)?.retryAfter
        if health?.stopsAutomaticSync == true { syncTiming.stoppedCheckAt = Date() }
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
    }

    /// Reads how many items wait for the server, for Settings > Sync.
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

    /// Connect to a Server goes straight to this device's server: setting it up again, signing in again, or
    /// signing in after encryption was turned on elsewhere.
    var reconnectsOnConnect: Bool {
        encryption.offersSignIn || [.needsYou, .serverChanged, .noAccess].contains(syncHealth?.kind)
    }

    /// Why the server refuses this device, for Settings > Devices, which learns it outside a sync.
    func lostAccessHealth() async -> SyncHealth {
        await sync()
        guard let syncHealth, [.needsYou, .serverChanged, .noAccess].contains(syncHealth.kind) else {
            return .accessRemoved
        }
        return syncHealth
    }

    /// Stop Syncing… (docs/design/sync-health-and-recovery.md §4.4): this device stops using its server and keeps its
    /// library as it is, including what hasn't been sent and the identity it last synced with, so connecting again
    /// later joins by identity. Its access is given up when the server still accepts it.
    func stopSyncing() {
        guard let previous = connection, !replacingVault else { return }
        try? Keychain.remove(configuration?.connectionKeyID ?? keyAccount + "-connection")
        connection = nil
        configureSync()
        syncTiming.afterWriting?.cancel()
        syncActivity.pendingItems = 0
        encryption.turnedOnElsewhere = false
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

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.update(available: available) }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkReturn"))
    }
    deinit { monitor.cancel() }

    func update(available: Bool) {
        if available && !satisfied { returned = true }
        satisfied = available
    }
    /// Whether the network returned since the last call.
    func take() -> Bool {
        defer { returned = false }
        return returned
    }
}
