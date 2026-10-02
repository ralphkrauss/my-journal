import JournalCore
import SwiftUI

/// Last Synced, Not on Server Yet and the sync state's single action in Settings > Sync, on iPhone, iPad and Mac
/// (docs/design/sync-now-and-done.md, docs/design/sync-health-and-recovery.md §4.1). `connect` shows Connect to a
/// Server over Settings for the actions that reconnect.
struct SyncNowRows: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var activity: SyncActivity
    var connect: () -> Void = {}

    var body: some View {
        if activity.syncingNow || activity.lastSynced != nil {
            LabeledContent("Last Synced") {
                if activity.syncingNow {
                    HStack(spacing: 6) {
                        Text("Syncing…")
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                    }
                } else if let date = activity.lastSynced {
                    TimelineView(.everyMinute) { context in
                        Text(SyncActivity.description(of: date, now: context.date))
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
        if activity.pendingItems > 0 {
            LabeledContent("Not on Server Yet", value: Self.items(activity.pendingItems))
                .accessibilityElement(children: .combine)
        }
        let action = model.syncStatusAction
        Button(action.title) { model.perform(action, presentConnection: connect) }
            .disabled(activity.syncingNow || (!action.connects && !model.canSyncNow))
            .task { await model.refreshPendingItems() }
    }

    /// "1 item", "3 items": entries, journals and templates alike (owner decision, 2026-10-01).
    static func items(_ count: Int) -> String { count == 1 ? "1 item" : "\(count) items" }
}

/// Stop Syncing… at the end of Settings > Sync for a server this device doesn't run itself
/// (docs/design/sync-health-and-recovery.md §4.4). Nothing is deleted, so it isn't destructive.
struct StopSyncingSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var activity: SyncActivity
    @State private var confirming = false

    var body: some View {
        Section {
            Button("Stop Syncing…") { confirming = true }.disabled(model.replacingVault)
        }
        .confirmationDialog(
            "Stop syncing with \(model.connectionHost)?", isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Stop Syncing") { model.stopSyncing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }

    private var message: String {
        let stays =
            "Your journals stay on this device. To sync again later, choose Connect to a Server in Settings > Sync."
        let waiting = activity.pendingItems
        guard waiting > 0 else { return stays }
        let items = waiting == 1 ? "1 item that isn’t" : "\(waiting) items that aren’t"
        return stays + " \(items) on the server yet will stay only on this device until then."
    }
}

/// Why Sync Now is unavailable while a save has failed.
enum SyncPauseNotice {
    static let saveFailed = "Syncing is paused until your changes are saved. Choose Try Again in the entry."
}
