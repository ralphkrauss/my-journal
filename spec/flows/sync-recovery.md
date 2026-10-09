---
id: sync-recovery
title: Sync health and recovery
features: [sync-health, sync-recovery, sync-item-refusal, sync-network-return, sync-status]
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/ServerJoining.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/DevicesSection.swift
  - docs/design/sync-health-and-recovery.md
  - docs/design/quiet-sync-and-title-alignment.md
  - docs/design/sync-now-and-done.md
---

# Sync health and recovery

## Purpose

Every way sync can fail ends in exactly one state with one message and at most one action. Writing never waits for sync, nothing is ever discarded, and automatic retries stop where retrying can't help. This flow covers each state from detection, through what the person sees and does, to the outcome.

## Entry points

- Automatic sync (see Rules for its pace).
- Sync Now in Settings ▸ Sync, and the action in Sync Status ([screens/sync-status.md](../screens/sync-status.md)) or in Settings ▸ Sync.
- Settings ▸ Sync ▸ Devices, which learns that this device lost access when it loads the device list: it runs a sync, whose state then appears in the Server section.
- Try Syncing Again in the notice of an entry whose journal hasn't arrived ([screens/unavailable-content.md](../screens/unavailable-content.md)).

## Steps

### 1. Detection

A sync reads the server's status first (reused for up to a minute when there is nothing to send), then this device's access and the server's identity, then exchanges records and images. A failure is classified in this order; the first match wins.

| # | What the sync sees | State | Kind |
| --- | --- | --- | --- |
| 1 | The status answer isn't a status (a web page, a 404, an unreadable answer) | not a journal server | Update or fix |
| 2 | The status reports a protocol newer than this app's | update My Journal | Update or fix (stops) |
| 3 | The status reports a protocol older than this app's, or a sync request answers 404 or 405 | server update needed | Update or fix |
| 4 | The status says the server isn't set up | server not set up | Server changed (stops) |
| 5 | This device is refused, and the server's identity is the one this library last synced with, or either has none | access removed | No access (stops) |
| 6 | This device is refused, the identity changed, this library isn't encrypted and the server is | sign-in needed | Needs you (stops) |
| 7 | This device is refused and the identity changed otherwise | restored or replaced | Server changed (stops) |
| 8 | The server's identity changed twice within one sync | busy | Temporary |
| 9 | The server's data was rolled back (it lost revisions or its log changed) | none: everything is compared again and what the server lost is sent back | Syncing normally |
| 10 | No network: not connected, data not allowed, roaming off, a call in progress | offline | Temporary |
| 11 | Certificate or secure-connection error | certificate not valid | Update or fix |
| 12 | Server error (5xx), rate limited (429), or an answer that can't be parsed | busy | Temporary |
| 13 | Any other network error: refused, timed out, host not found, connection lost | can't reach | Temporary |
| 14 | This device's own database is damaged (malformed or not a database, or the store's own validation failed) | this device's data | Unexpected |
| 14b | This device's own database can't be used right now (busy or locked, the device is locked, a failing or full disk) | this device's data, temporary | Temporary |
| 15 | Content or a recovery format from a newer version | update My Journal | Update or fix (stops) |
| 16 | Anything else | unexpected | Unexpected |

Item-level problems are not states: one record too large or refused, or one image refused, is set aside with its own message while everything else syncs (step 4 below). A record whose push fails with a server error three times in a row, while other requests succeed, is refused at item level.

### 2. What the person sees

| State | Message | Action | Sync Status | Automatic sync |
| --- | --- | --- | --- | --- |
| Syncing normally | none | `messages.sync.action.syncNow` | hidden | every 3 s while active |
| Offline | `messages.sync.offline` | `common.tryAgain` | hidden until the long wait | backoff; at once when the network returns |
| Can't reach | `messages.sync.unreachable`, or `messages.sync.unreachableTailscale` for a `.ts.net` host | `common.tryAgain` | hidden until the long wait | backoff; at once when the network returns |
| Busy | `messages.sync.unavailable` | `common.tryAgain` | hidden until the long wait | backoff, at least the server's Retry-After |
| Sign-in needed | `messages.sync.signInNeeded` | `common.reconnect` | shown | stops |
| Not set up | `messages.sync.serverNotSetUp` | `common.reconnect` | shown | stops |
| Restored or replaced | `messages.sync.serverReplaced` | `common.reconnect` | shown | stops |
| Access removed | `messages.sync.accessRemoved`, or `messages.sync.accessRemovedNoPassword` for a library without a password | `common.reconnect` | shown | stops |
| Update My Journal | `messages.sync.appUpdateNeeded` | `messages.sync.action.checkAgain` | shown | stops |
| Server update needed | `messages.sync.serverUpdateNeeded` | `messages.sync.action.checkAgain` | shown | every 5 minutes |
| Certificate not valid | `messages.sync.certificateInvalid` | `messages.sync.action.checkAgain` | shown | every 5 minutes |
| Not a journal server | `messages.sync.notJournalServer` | `messages.sync.action.checkAgain` | shown | every 5 minutes |
| This device's data (damaged) | `messages.sync.localDataUnreadable` | `common.tryAgain` | shown | backoff |
| This device's data (temporary) | `messages.sync.localDataUnavailable` | `common.tryAgain` | hidden until the long wait | backoff |
| Unexpected | `messages.sync.unexpected` | `common.tryAgain` | shown | backoff |
| Item refused (no state) | `messages.sync.recordTooLarge`, `messages.sync.recordRefused`, `messages.sync.imageTooLarge` or `messages.sync.imageRefused` | `messages.sync.action.syncNow` | shown | continues normally |

The message appears in the footer of Settings ▸ Sync's Server section, and in Sync Status when it shows. The action is the last row of that section, after Last Synced and Not on Server Yet. Settings ▸ Sync ▸ Devices has no message or reconnect button of its own: while the server refuses this device, the Devices section is absent and the Server section says why. If the device list is refused before any sync has said so, the device runs a sync to learn why, and without an answer the state is access removed.

### 3. The person's action

**Try Again, Check Again, Sync Now.** Run one full sync now, which also resends refused records and images and anything waiting after a failure. The button is dimmed while it runs and while sync can't run (locked, the library being replaced, a save failed). Settings ▸ Sync shows "Syncing…" next to Last Synced for at least half a second. The outcome is the state the sync ends in; VoiceOver announces it.

**Reconnect…** is specified step by step in [reconnect-to-server.md](reconnect-to-server.md). It opens Reconnect at this device's server and checks it at once; the server's answer decides which step follows, and lineage decides whether the library joins the server by identity or asks to merge. Everything about that flow lives there.

**Sync Settings…** (in Sync Status). Opens Settings at Sync, where the same message and action are shown.

**Stop Syncing…** (Settings ▸ Sync, any state). Ends the connection and keeps the library as it is, including what hasn't been sent; see [stop-syncing.md](stop-syncing.md) and [settings-sync.md](../screens/settings-sync.md). Reconnecting later goes through Connect to a Server, and lineage joins the same library by identity. To follow a server that moved to a new address: Stop Syncing, then connect to the new address.

### 4. Outcome

- A sync that succeeds clears the state: no message, Sync Now, Sync Status hidden, Last Synced updated. A refused item's message stays until it is sent or edited.
- Reconnect, when it succeeds, starts the connection from a clean state: no message, automatic sync running, Last Synced empty until the first sync, which joining runs at once.
- Reconnect cancelled or failed leaves the state as it was. Connect to a Server explains its own failures (`messages.connection.*`).

## Rules

**Automatic sync pace.**

- Syncing normally: every 3 seconds while My Journal is the active app; every 30 seconds while it is open but another app is active; at once when it becomes active again or returns from the background. After each pause in writing, and when leaving an entry, saved writing is sent without waiting. When the server supports waiting for changes, the device waits for them instead of polling.
- After a failure (Temporary and Unexpected): 3 seconds, doubling after each failure in a row, up to 5 minutes; at least the server's Retry-After. When the network comes back the waiting retry runs at once. Returning from the background syncs at once.
- Update or fix needed (except update My Journal): checked every 5 minutes.
- **States that stop automatic sync** (sign-in needed, not set up, restored or replaced, access removed, update My Journal): no automatic sync, no sync after writing pauses or on leaving an entry; a pause in writing only updates Not on Server Yet. One check runs at launch and when the app becomes active, at most every 10 minutes. The state's action, or Sync Now, always runs.
- Sync never runs while locked (saved writing is still sent on locking), while the library is being replaced, or while a save has failed.

**Long wait.** When the last sync failed, changes are waiting, and more than 24 hours passed since Last Synced (or since the first failure, when this connection never synced), Sync Status shows in any state with that state's own message. It's checked after every sync, including automatic retries and the sync when the app becomes active, so changes left from days ago don't flash it at launch.

**Never lose anything.** No state, action, Stop Syncing or reconnection deletes a record, image, waiting change or version. Every waiting change is kept in the library, so nothing depends on the app staying open. A setup code is always needed to claim a server, and a secret or a connected device's approval to rejoin one. Merge Journals appears only when journals will actually be combined, before anything is sent.

**Network and offline.**

- Writing and saving are always local and immediate; being offline only delays sending.
- The device watches the network path. Its return starts a waiting retry at once; any change of path ends a wait for the server's changes.
- A record that times out ends the sync (the next one would wait as long); an image transfer that times out waits on its own, so one slow image doesn't hold up records. A new device downloads images over several syncs, without pausing in between; records never wait for images.
- Connect to a Server's first contact with an address waits up to 20 seconds for the connection to become possible, because the system may first ask for local network permission.
- Offline, can't reach and busy are quiet: no alert, no Sync Status (until the long wait), and they don't count as a problem for the rating request.
- Changes made on two devices follow the same rule: journals and permanent deletions that the device settles itself (Settings ▸ Sync ▸ Changed on Two Devices) are quiet and never count as a problem for the rating request; only an entry or template the person must review does ([flows/resolve-conflict.md](resolve-conflict.md), [flows/rating-request.md](rating-request.md)). A held change adds one line to the Settings ▸ Sync footer (`messages.conflict.kept.updateNeeded`) and doesn't change the sync state.

**Item-level refusals.** A record larger than 4 MB, or one the server refuses, is kept on this device with `messages.sync.recordTooLarge` or `messages.sync.recordRefused` ({title} cut to 40 characters with "…"). It is sent again when it is edited, or with Sync Now or Try Again. An image the server refuses keeps the entries that include it waiting (`messages.sync.imageTooLarge`, `messages.sync.imageRefused`). When several are refused, one message shows: a record's first (sorted by text), then images.

**Other sync-related messages.** `messages.library.needsUpdate` and `messages.library.waitingForServer` explain pins and journal order in the same footer when nothing else is shown. `messages.sync.pausedForSaveFailure` replaces everything while a save has failed ([flows/save-failure.md](save-failure.md)).

## Accessibility

- VoiceOver announcements come only from the result of an action the person started: Sync Now, Try Again, Check Again (the held message, else `messages.sync.announce.synced`, else `messages.sync.announce.failed`), and the guided connect actions (Connect to a Server and Reconnect announce their own errors). Background changes aren't announced.
- Last Synced and Not on Server Yet each read as one element ("Last Synced, Just now"; "Not on Server Yet, 3 items"). The spinner next to "Syncing…" is hidden from VoiceOver.
- Footers wrap at every text size. Actions that open a flow end in "…".

## Platform notes (Apple)

- iPhone, iPad and Mac classify and word every state the same way. The Mac's Settings ▸ Sync shows the message as secondary text below the Server section.
- The Mac app no longer runs a server. A Mac still connected to the removed built-in server stops syncing once and explains it in Settings ▸ Sync (owned by the Settings ▸ Sync screen).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
