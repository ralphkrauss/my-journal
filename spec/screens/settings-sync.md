---
id: settings-sync
title: Settings ▸ Sync
features: [sync-connect, sync-now, sync-status-footer, stop-syncing, sync-recovery, changes-to-review-list, former-mac-server-notice]
sources:
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/AboutLinks.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/Model/LibraryOperations.swift
  - apps/apple/JournalApp/Model/FormerMacServer.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - docs/design/sync-now-and-done.md
  - docs/design/sync-health-and-recovery.md
  - docs/design/quiet-sync-and-title-alignment.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---

# Settings ▸ Sync

## Purpose

Shows which server this device syncs with and how syncing stands, offers the one action that fits the current state, and lets the person connect, stop syncing, or review changes from another device that need a decision.

## Entry points

- Settings ▸ Sync (`screens/settings`).
- Sync Status ▸ Sync Settings… opens Settings directly at this pane (`screens/sync-status`).

## Content

In order:

### 1. Server section

Header: `settings.connect.server`.

**Not connected:**
- Button `common.connectToServer` ("Connect to a Server…").

**Connected:**
1. The server's address as typed when connecting (for example `https://journal.example.ts.net`), selectable.
2. A **Last Synced** row (label `settings.sync.lastSynced`), shown while a sync the person started is running or once this device has completed a sync with this server:
   - While Sync Now (or Try Again) runs: `settings.sync.syncing` with a small activity indicator.
   - Otherwise the time of the last complete sync, described as:
     - under a minute ago: `settings.sync.lastSynced.justNow`;
     - within a day: the platform's relative time in full words, capitalised to start a sentence (for example "5 minutes ago", "2 hours ago");
     - yesterday: `settings.sync.lastSynced.yesterday` ("Yesterday at {time}");
     - earlier this year: `settings.sync.lastSynced.date` with day and abbreviated month ("12 Sept at 08:03");
     - an earlier year: the same with the year.
   - The description updates every minute while shown.
3. A **Not on Server Yet** row (label `settings.sync.notOnServerYet`, value `common.itemCount`, plural), only when items saved here haven't been accepted by the server. "Items" counts entries, journals and templates alike.
4. One action button whose title depends on the sync state (`sync-now`):

   | Sync state | Button | Copy key |
   | --- | --- | --- |
   | No problem | Sync Now | `messages.sync.action.syncNow` |
   | Temporary (offline, server unreachable, server unavailable) or unexpected | Try Again | `common.tryAgain` |
   | Needs the person (the server now uses encryption or was replaced by an encrypted one) | Sign In… | `common.signIn` |
   | Server was reset and waits for a setup code | Set Up Server Again… | `messages.sync.action.setUpServerAgain` |
   | Server was restored or replaced and doesn't know this device | Connect Again… | `messages.sync.action.connectAgain` |
   | This device's access was removed | Connect Again… | `messages.sync.action.connectAgain` |
   | App or server update needed, certificate invalid, address isn't a journal server | Check Again | `messages.sync.action.checkAgain` |

Footer (only one, the first that applies):
1. Connected and an entry couldn't be saved: `messages.sync.pausedForSaveFailure`.
2. The last sync left a message: that message. It is the sync state's message, `messages.sync.<state>` (`messages.sync.offline`, `messages.sync.unreachable` (or `messages.sync.unreachableTailscale` for hosts ending in `.ts.net`), `messages.sync.unavailable`, `messages.sync.signInNeeded`, `messages.sync.serverNotSetUp`, `messages.sync.serverReplaced`, `messages.sync.accessRemoved`, `messages.sync.appUpdateNeeded`, `messages.sync.serverUpdateNeeded`, `messages.sync.certificateInvalid`, `messages.sync.notJournalServer`, `messages.sync.localDataUnreadable`, `messages.sync.unexpected`), or, when every other change synced, the message about a single entry or image the server didn't accept (`messages.sync.*`, owned by `screens/sync-status`).
3. Not connected:
   - Computer that stopped syncing with the server earlier versions ran on it: `settings.sync.footer.formerMacServer`, then on a new line the link `settings.sync.footer.learnMore`.
   - Otherwise: `settings.sync.footer.notConnected`, then on a new line the link `settings.sync.footer.howToSetUp` ("How to Set Up a Server").
4. Connected and the server can't keep pinned entries and journal order:
   - this app is older than the library record on the server: `messages.library.needsUpdate`;
   - the server is older and doesn't store it yet: `messages.library.waitingForServer`.

### 2. Stop Syncing section (connected only)

- Button `settings.sync.stopSyncing` ("Stop Syncing…"), not styled as destructive (nothing is deleted).

### 3. Changes to Review section (only when there are conflicts and My Journal is unlocked)

Header `messages.conflict.settingsSection`. One row per conflict:
- the item's title (for a permanently deleted item, the deleted-item title the conflict screens use);
- the date of the local version, or of the deletion, in secondary text (date and time);
- a button `common.reviewChanges` ("Review Changes"), accessibility label `common.reviewChangesFor` ("Review Changes for {title}"). It opens the conflict review (`screens/conflict-review`, owned by the conflicts specification) as a sheet.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Connect to a Server… | `connect-to-server` | Always (unlocked) | Opens Connect to a Server (`flows/connect-to-server`) as a sheet over Settings. |
| Sync Now / Try Again | `sync-now` | Not while a sync the person started runs; not while locked, while the journals are being replaced (connecting, importing, encrypting), while a save has failed, or without a working connection. | Syncs once, also resending records and images the server refused before. See Rules. |
| Check Again | `sync-now` | As Sync Now | Syncs once; the state is checked again. |
| Set Up Server Again… / Connect Again… / Sign In… | `sync-reconnect` | Not while a sync the person started runs | Opens Connect to a Server, which goes straight to this server's next step (`flows/reconnect-to-server`). |
| Stop Syncing… | `stop-syncing` | Not while the journals are being replaced | Asks first (below), then `flows/stop-syncing`. |
| Review Changes | `review-changes` | Unlocked | Opens the conflict review for that item. |
| How to Set Up a Server | `open-setup-guide` | Always | Opens the sync guide (`<repository>/blob/main/docs/guide/sync.md`) in the browser. |
| Learn More (former Mac server) | `open-former-server-guide` | Always | Opens `<repository>/blob/main/docs/guide/sync.md#if-you-used-use-this-mac`. |

### Stop Syncing confirmation

A confirmation (action sheet on phone, dialog on computer), with a visible title:
- Title: `settings.sync.stopSyncing.title` ("Stop syncing with {host}?"), where host is the server's host, with the port when it isn't the default.
- Message: `settings.sync.stopSyncing.message`; when items haven't reached the server, followed by a space and `settings.sync.stopSyncing.messageUnsent` (plural).
- Buttons: `settings.sync.stopSyncing.confirm` ("Stop Syncing"), `common.cancel`.

## States

- **Not connected:** Server section shows Connect to a Server…; footer explains where journals are and links to How to Set Up a Server. No Stop Syncing section.
- **Syncing (person started it):** Last Synced shows Syncing… and an indicator; the action button is disabled.
- **Syncing automatically:** nothing changes; normal syncing is quiet.
- **Offline / server unreachable / unavailable:** footer shows the message; button Try Again; automatic retries continue.
- **Needs the person / server changed / no access:** footer shows the message; button Sign In…, Set Up Server Again… or Connect Again…; automatic sync has stopped until the person acts.
- **Update or fix needed:** footer shows the message; Check Again.
- **Save failed:** footer `messages.sync.pausedForSaveFailure`; Sync Now disabled.
- **Locked:** Settings shows only its locked text; the Changes to Review section is never shown while locked, and an open review closes when the app locks.
- **Former Mac server (computer only):** not connected, with the special footer and Learn More.

## Rules

- **Sync Now** runs one sync at a time; pressing it again while running does nothing. It shows Syncing… for at least half a second, so it reads as done rather than as a flicker. When it ends, VoiceOver hears the footer message if there is one, else `messages.sync.announce.synced` ("Synced") if the Last Synced time moved, else `messages.sync.announce.failed`. A sync that can't run (see enabled) isn't shown as synced and announces nothing.
- **Last Synced** is the last time this device completed a sync with this server, including one that left a single refused entry or image behind. It is stored per library and connection, survives relaunches, and is forgotten when the library connects to another server. It never moves backwards.
- **Not on Server Yet** is read when the pane appears and after every sync.
- The action is chosen from the current state alone; there is exactly one.
- Connect actions open Connect to a Server where the person is: over Settings when pressed here.
- **Stop Syncing** never deletes anything: the journals, unsent changes and the identity they last synced with stay, so connecting to the same server later continues by identity. The device's access on the server is given up when the server still accepts it (best effort).
- The former-Mac-server footer appears only on a computer whose library was connected to the server earlier versions of the Mac app ran on itself; it stays until the library connects to any server.
- Normal syncing is quiet: nothing in this pane changes while automatic sync works.

## Accessibility

- Last Synced and Not on Server Yet are each read as one element (label and value together).
- The action button's title says what it does; connect actions end with an ellipsis because they open a sheet.
- Sync Now's result is announced (see Rules).
- Review Changes buttons name their item.

## Platform notes (Apple)

- iPhone and iPad: a pushed pane in the Settings sheet. The Stop Syncing confirmation is an action sheet with a visible title.
- Mac: the Sync tab of the Settings window; Connect to a Server opens as a sheet on the Settings window, sized to fit inside it. The Stop Syncing confirmation is a dialog.
- The former-Mac-server footer exists only on the Mac (`docs/design/client-only-mac-lists-markdown-2026-10-05.md` §1.2).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
