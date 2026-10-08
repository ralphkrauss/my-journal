---
id: sync-recovery
title: Sync health and recovery (Apple)
spec: flows/sync-recovery.md
features: [sync-health, sync-recovery, sync-item-refusal, sync-network-return, sync-status]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/ServerJoining.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/DevicesView.swift
  - docs/design/sync-health-and-recovery.md
  - docs/design/quiet-sync-and-title-alignment.md
  - docs/design/sync-now-and-done.md
---

# Sync health and recovery (Apple)

How the Apple apps classify a failed sync, hold one state, show it and run the automatic retries. There is no screen of its own: the state appears in [settings-sync](../screens/settings-sync.md), [sync-status](../screens/sync-status.md) and [settings-devices](../screens/settings-devices.md); the connect actions are [reconnect-to-server](reconnect-to-server.md). Spec: [sync-recovery](../../../flows/sync-recovery.md). Sync lifecycle conventions: [platform.md](../platform.md#30-sync-lifecycle-and-background).

## Controls

Where each step of the spec's flow lives:

1. **Detection.** `SyncEngine.synchronize(_:)` (core) reads the server's status first (`checkedStatus()`: not decodable gives `SyncFailure(.notJournalServer)`; protocol above 1 `.appUpdateNeeded`, below 1 `.serverUpdateNeeded`; not initialised `.serverNotSetUp`), refuses a device the server no longer accepts (`lostAccess`: `.accessRemoved` for the same server identity, `.signInNeeded` when this library is unencrypted and the server now is, else `.serverReplaced`), and lets everything else propagate. `ServerClient` turns an HTTP 404 or 405 into `.serverUpdateNeeded`. `AppModel.sync(...)` catches the error and calls `SyncHealth(classifying:)` (`SyncHealth.swift`): a `SyncFailure` keeps its state; a `URLError` becomes `.offline` (codes not connected, data not allowed, roaming off, call in progress), `.certificateInvalid` (secure-connection and certificate codes), `.unavailable` (garbled answers) or `.unreachable`; `ServerRateLimited`, `ServerUnavailable` and cancellation become `.unavailable`; a database error becomes `.localDataUnreadable` or `.localDataUnavailable`; `JournalError.unauthorized` is `.accessRemoved`; unsupported format or newer version is `.appUpdateNeeded`; anything else `.unexpected`. A sync cancelled by leaving the foreground returns early and records nothing.
2. **Holding the state.** `AppModel.recordSyncHealth(_:failure:)` stores `syncHealth` (`SyncHealth?`), sets `encryption.turnedOnElsewhere` for `.signInNeeded`, keeps `syncTiming.retryAfter` from `ServerRateLimited`, `syncTiming.stoppedCheckAt` for states that stop automatic sync, and `syncTiming.failingSince`; non-temporary states also tell `reviewRequests.noteProblem()` (a state the person must act on counts against asking for a rating; offline does not). `syncError` is `health.message(host: connectionHost)` or, with no failure, the report's item-level problem. `syncFailed` records that the sync as a whole failed. A new connection, library or Stop Syncing calls `resetSyncHealth()` through `configureSync()`.
3. **What the person sees.** `SyncHealth.Kind` (`.temporary`, `.needsYou`, `.serverChanged`, `.noAccess`, `.updateOrFix`, `.unexpected`) decides the action in `AppModel.syncStatusAction`: temporary and unexpected give Try Again; needs-you gives Sign In…; server changed gives Set Up Server Again… (not set up) or Connect Again… (replaced); no access gives Connect Again…; update or fix gives Check Again; no state gives Sync Now. The message is in the Settings ▸ Sync footer (`SettingsView.syncSettings`, the Server section's `footer:`), in Sync Status (only when `showsSyncStatus`), and in Settings ▸ Devices when the device list answers unauthorized (`DevicesView.load()` calls `lostAccessHealth()`, which runs a sync to learn the reason and falls back to `.accessRemoved`). `SyncHealth.message(host:)` supplies the text; the Tailscale hint is added when the host ends in `.ts.net`.
4. **The person's action.** `syncNow()` (`Model/SyncSchedule.swift`): one at a time (`syncActivity.syncingNow`), runs `sync(retryingRefused: true)` only if `canSyncNow` (unlocked, library not being replaced, no save failure, an engine exists), holds "Syncing…" for at least half a second, and announces the result. Connect actions go through `perform(_:presentConnection:)`.
5. **Outcome.** A successful sync (`failure == nil`) clears health and `syncError` through `recordSyncHealth(nil, ...)`, sets `syncActivity.synced()` and updates the pending count; a connect action that succeeds ends in `configureSync()`, which starts clean.

**State by state.** The table of states and actions is in the spec; the Apple facts that differ or add:

| Aspect | Apple behaviour |
| --- | --- |
| States that stop automatic sync | `SyncHealth.stopsAutomaticSync`: `.signInNeeded`, `.serverNotSetUp`, `.serverReplaced`, `.accessRemoved` and `.appUpdateNeeded` |
| Update or fix states other than "update My Journal" | the loop continues with `syncDelay(afterFailures: 10)`, 5 minutes |
| `localDataUnreadable` | kind `.unexpected`, backoff retries |
| `localDataUnavailable` (`messages.sync.localDataUnavailable`) | kind `.temporary` (database busy or locked, device locked, disk failing or full): message "Couldn’t sync right now. My Journal will try again.", action Try Again, hidden until the long wait |

**Automatic pace** (`synchronizeAutomatically()` and `nextSyncDelay(afterFailures:)` in `Model/SyncSchedule.swift`). A loop runs while the app is in front or active and unlocked; it wakes once a second and syncs when `Date() >= nextAttempt`. Constants: `syncInterval` 3 seconds; `inactiveSyncInterval` 30 seconds (used when `applicationActive` is false, a Mac window behind others); after a failure `min(300, 3 * 2^failures)` seconds, at least the server's Retry-After; `stoppedCheckInterval` 10 minutes. `.task(id: scenePhase == .background)` in `JournalApp.swift` cancels the loop in the background and restarts it, which syncs at once, on return. States that stop automatic sync are skipped (`waitsForPerson`) until the loop restarts at least ten minutes after the last check. When the server supports waiting (the server capability named sync-wait), `ChangeWatcher` (core, a pure state machine) owns the schedule and a `waitForChange` task replaces polling; the watcher is told about sleep and wake (`NSWorkspace.willSleepNotification`, `didWakeNotification`, Mac only), path changes and the network returning. `NetworkReturn` wraps `NWPathMonitor`: the first satisfied path after an unsatisfied one makes the waiting retry run at once. After each pause in writing (`SyncEngine.writingPause`, 2 seconds, plus a 0.25 second margin) `syncWhenWritingPauses()` syncs (or only refreshes the pending count in a stopped state), `sendWritingAfterLeaving()` syncs when an entry is left, and `sendWriting()` runs on locking, entering the background (`saveAndLock`) and, on the Mac, quitting (`sendWritingBeforeQuitting(within: 3)`, at most three seconds). The project declares no background modes: nothing syncs while the app is suspended.

**Long wait.** `syncWaitedLong(now:)` is `pendingSync && syncFailed` and more than `longSyncWait` (24 hours) since `syncActivity.lastSynced ?? syncTiming.failingSince`; `updateSyncLongWait()` runs after every sync. It only affects `showsSyncStatus`.

**Item-level refusals.** `SyncEngine` keeps `rejectedChanges` and refused images; `report.problem` carries `messages.sync.recordTooLarge`, `messages.sync.recordRefused`, `messages.sync.imageTooLarge` or `messages.sync.imageRefused` with the title cut to 40 characters, a record first (sorted by text), then an image. `sync(retryingRefused: true)` (Sync Now, Try Again, Check Again) sends them again; editing the item does as well. They set `syncError` while `syncFailed` stays false, so the action is Sync Now and Sync Status shows.

**Save failure.** While `model.saveFailure`, `sync()` returns early (`guard ... !saveFailure`), the loop does not count it as a failure, Sync Now is disabled and the Settings footer shows `messages.sync.pausedForSaveFailure` (`save-failure`).

## Layout

The flow has no layout of its own; see the three screen notes. The only device-dependent part is where Sync Status lives: a Mac toolbar item, or a submenu of Entry Actions on iPhone and iPad.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `sync-now` | Settings ▸ Sync button, Sync Status menu (titles Sync Now, Try Again, Check Again) | none | `canSyncNow` and not already syncing |
| `sync-reconnect` | Same places (titles Set Up Server Again…, Connect Again…, Sign In…); Settings ▸ Devices when access was refused | none | not while a sync the person started runs |
| `sync-status` | Sync Status control | none | the state needs the person, or the long wait applies |
| `stop-syncing` | Settings ▸ Sync | none | not while the library is being replaced |
| `try-syncing-again` | Notice of an entry whose journal has not arrived | none | as in [commands.md](../commands.md) |

Placements are in [commands.md](../commands.md). No keyboard shortcut starts a sync.

## Copy differences

None between devices: `SyncHealth.message(host:)` is shared code. Where the source and the catalog differ is listed under Open questions.

## Accessibility

- Announcements come only from `syncNow()`: `JournalAccessibility.announce(syncError ?? (synced ? "Synced" : "Couldn’t sync."))` (`messages.sync.announce.synced`, `messages.sync.announce.failed`). Nothing is announced for automatic syncs, state changes, or a sync that could not run.
- Last Synced and Not on Server Yet are single elements; the "Syncing…" spinner is hidden from VoiceOver ([settings-sync](../screens/settings-sync.md)).
- The connect actions end in an ellipsis; Connect to a Server announces its own errors.

## Differences between iPhone, iPad and Mac

- Lifecycle: iPhone and iPad lock and send writing on entering the background (`applicationEnteredBackground`, `BackgroundActivity.run`, which asks iOS for time to finish) and have no background sync; the Mac keeps syncing in the background at the slower 30-second pace while the app is open but inactive, and sends writing before quitting. Reason: iOS suspends the app, a Mac app keeps running.
- Mac only: sleep and wake notifications feed `ChangeWatcher`.
- Sync Status placement differs ([sync-status](../screens/sync-status.md)).
- Classification, wording, pace constants and actions are shared code and identical.

## Screenshots

None. This flow has no screen of its own and no captured state shows a failure: the captures of [settings-sync](../screens/settings-sync.md) show the healthy and not-connected panes only, and Sync Status (shown only on a failure) is not captured.

## Source files

Core:
- `apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift`: states, kinds, classification, messages.
- `apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift`: status check, lost-access reasons, item-level refusals, writing pause.
- `apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift`: HTTP mapping (404 and 405).
- `apps/apple/Packages/JournalCore/Sources/JournalCore/ChangeWatcher.swift`: waiting for changes instead of polling.

Model:
- `apps/apple/JournalApp/Model/AppModel.swift`: `sync(...)`.
- `apps/apple/JournalApp/Model/SyncHealthOperations.swift`: recording, actions, long wait, `NetworkReturn`, Stop Syncing.
- `apps/apple/JournalApp/Model/SyncSchedule.swift`: pace, backoff, `syncNow()`, `SyncActivity`.
- `apps/apple/JournalApp/Model/ServerJoining.swift`: what a reconnect does.

View:
- `apps/apple/JournalApp/Views/SyncNowRows.swift`, `apps/apple/JournalApp/Views/DevicesView.swift`: where the state is shown.

Design records: [sync-health-and-recovery.md](../../../../docs/design/sync-health-and-recovery.md), [quiet-sync-and-title-alignment.md](../../../../docs/design/quiet-sync-and-title-alignment.md), [sync-now-and-done.md](../../../../docs/design/sync-now-and-done.md).

## Open questions

See [open-questions.md](../../../open-questions.md). Reported with this page, from reading the source:

- `messages.sync.localDataUnreadable` and the temporary `messages.sync.localDataUnavailable` state now match the code and have rows in the spec's states (the unreadable text is the same as `FailureMessage.damagedReading`, `messages.failure.damagedReading`).
- A13 (extended): the spec says one check of a stopped state runs "when the app becomes active"; the loop restarts only when `scenePhase` leaves `.background`, so a Mac whose app is merely deactivated may not re-check until relaunch. Not run.
