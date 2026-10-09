---
id: settings-sync
title: Settings ▸ Sync
features: [sync-connect, sync-now, sync-status-footer, stop-syncing, sync-recovery, changes-to-review-list, changed-on-two-devices-list, conflict-kept-both, former-mac-server-notice, devices-list, revoke-device, add-device]
sources:
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/DevicesSection.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/KeptNotes.swift
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
  - docs/design/1-1-settings-messages-editor.md
  - docs/design/1-1-conflicts-and-reconnect.md
---

# Settings ▸ Sync

## Purpose

Shows which server this device syncs with and how syncing stands, offers the one action that fits the current state, lists the devices that can sync with the server, and lets the person connect, add a device, remove a device's access, stop syncing, review changes from another device that need a decision (entries and templates), and see what the app settled itself when something changed on two devices.

## Entry points

- Settings ▸ Sync (`screens/settings`).
- Sync Status ▸ Sync Settings… opens Settings directly at this pane (`screens/sync-status`).
- The computer's "Show Connection" notice opens Settings at this pane (`screens/settings`).
- Any text that sends the person here writes the path as “Settings ▸ Sync” (for adding a device, “Settings ▸ Sync ▸ Devices ▸ Add Device”).

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
   | Needs the person (the server now uses encryption or was replaced by an encrypted one) | Reconnect… | `common.reconnect` |
   | Server was reset and waits for a setup code | Reconnect… | `common.reconnect` |
   | Server was restored or replaced and doesn't know this device | Reconnect… | `common.reconnect` |
   | This device's access was removed | Reconnect… | `common.reconnect` |
   | App or server update needed, certificate invalid, address isn't a journal server | Check Again | `messages.sync.action.checkAgain` |

Footer (only one, the first that applies):
1. Connected and an entry couldn't be saved: `messages.sync.pausedForSaveFailure`.
2. The last sync left a message: that message. It is the sync state's message, `messages.sync.<state>` (`messages.sync.offline`, `messages.sync.unreachable` (or `messages.sync.unreachableTailscale` for hosts ending in `.ts.net`), `messages.sync.unavailable`, `messages.sync.signInNeeded`, `messages.sync.serverNotSetUp`, `messages.sync.serverReplaced`, `messages.sync.accessRemoved`, `messages.sync.appUpdateNeeded`, `messages.sync.serverUpdateNeeded`, `messages.sync.certificateInvalid`, `messages.sync.notJournalServer`, `messages.sync.localDataUnreadable`, `messages.sync.unexpected`), or, when every other change synced, the message about a single entry or image the server didn't accept (`messages.sync.*`, owned by `screens/sync-status`).
3. Not connected:
   - Computer that stopped syncing with the server earlier versions ran on it: `settings.sync.footer.formerMacServer`, then on a new line the link `settings.sync.footer.learnMore`.
   - Otherwise: `settings.sync.footer.notConnected`, then on a new line the link `settings.sync.footer.howToSetUp` ("How to Set Up a Server").
4. Connected and the server can't keep pinned entries and journal order:
   - this app is older than the library record on the server: `messages.library.needsUpdate`.

One more line is added below whichever footer shows (or alone), connected or not, while a journal or permanent-deletion change from another device is held because a newer version of My Journal wrote it: `messages.conflict.kept.updateNeeded`. It has no row, no button and no alert.

The action is the only place that reconnects: Reconnect… is never repeated in another section of this pane.

### 2. Changes to Review section (only when an entry or template needs review and My Journal is unlocked)

Above Devices, because it asks for a decision. Header `messages.conflict.settingsSection`. One row per entry or template with changes to review (including one saved by a newer version, which can't be reviewed yet):
- the item's title;
- the date of the local version, in secondary text (date and time);
- a button `common.reviewChanges` ("Review Changes"), accessibility label `common.reviewChangesFor` ("Review Changes for {title}"). It opens the conflict review (`screens/conflict-review`, owned by the conflicts specification) as a sheet.

Journals and permanent deletions are not here: the app settles them itself and lists them in the next section ([flows/resolve-conflict](../flows/resolve-conflict.md)).

### 3. Changed on Two Devices section (only with rows, and My Journal unlocked)

Directly below Changes to Review, or in its place when that section is absent. It tells the person, quietly and afterwards, what the app settled when something changed on two devices. Header `messages.conflict.kept.section`, footer `messages.conflict.kept.footer`. The last row is **Clear List** (`messages.conflict.kept.clear`), a plain button that forgets every note at once, without confirmation (`clear-kept-notes`).

Rows are the 20 most recent notes, newest first. A note expires after 30 days; a journal rename note never expires, because it is the only trail of the name that lost, so only Clear List removes it, and when 20 are reached the oldest other note goes first. A row for an item that no longer exists is removed silently.

| Case | Row |
| --- | --- |
| An entry or template deleted permanently on one device and changed on another | Title: the saved item's title (`library.entryList.untitledEntry` or `library.entryList.untitledTemplate` when blank). Sentence `messages.conflict.kept.deletedAndChanged`. Date and time. The row opens the saved item wherever it is: Recently Deleted, or Unavailable Journals when its journal is gone |
| A journal renamed on two devices | Title: the journal's name (`common.untitledJournal` when blank). Sentence `messages.conflict.kept.journalRenamed` ({name} is the name it has now, {otherName} the one that lost). Date and time. Plain text |
| A journal deleted permanently on one device and changed on another | Title: the journal's name. Sentence `messages.conflict.kept.journalDeleted`. Date and time. Plain text |

**Each row that opens something is one control**: a single row with a disclosure indicator (a button on the Mac), not text with a second button inside it. Its accessibility label is the title, then the sentence, then the date and time; its hint is `messages.conflict.kept.rowHint` ("Opens it."). Activating it opens the item (`open-kept-note`): Settings closes first on iPhone and iPad; on the Mac the library window comes forward and selects it. A row with nothing to open is plain text, read as one element.

Nothing here is an alert, a badge or a sound; it adds nothing to Sync Status and does not count as a problem for the rating request. The section is never shown while locked, and the notes are sealed with the library (a journal's name is not stored in clear text).

### 4. Devices section (connected, and the server accepts this device)

The devices that can sync with the server, as one section with one header, `settings.sync.devices.header` ("Devices"): Add Device…, then one row per device with a trailing Revoke Access…. It is [screens/settings-devices](settings-devices.md).

The section is absent, not dimmed, when the device isn't connected (the Server section offers Connect to a Server…) and when the server doesn't accept this device (a sync state that stops automatic sync: the Server section says why and offers Reconnect…).

### 5. Stop Syncing section (connected only)

- Button `settings.sync.stopSyncing` ("Stop Syncing…"), in a section of its own, last, not styled as destructive (nothing is deleted).

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Connect to a Server… | `connect-to-server` | Always (unlocked) | Opens Connect to a Server (`flows/connect-to-server`) as a sheet over Settings. |
| Sync Now / Try Again | `sync-now` | Not while a sync the person started runs; not while locked, while the journals are being replaced (connecting, importing, encrypting), while a save has failed, or without a working connection. | Syncs once, also resending records and images the server refused before. See Rules. |
| Check Again | `sync-now` | As Sync Now | Syncs once; the state is checked again. |
| Reconnect… | `sync-reconnect` | Not while a sync the person started runs | Opens Reconnect, which goes straight to this server's next step (`flows/reconnect-to-server`). |
| Stop Syncing… | `stop-syncing` | Not while the journals are being replaced | Asks first (below), then `flows/stop-syncing`. |
| Review Changes | `review-changes` | Unlocked | Opens the review for that entry or template. |
| Open a Changed on Two Devices row | `open-kept-note` | Unlocked; the item still exists; the row has something to open | Shows the saved entry or template (see section 3). |
| Clear List | `clear-kept-notes` | Unlocked | Forgets all the notes; nothing else changes. |
| Add Device…, Revoke Access… | `add-device`, `revoke-device` | See [screens/settings-devices](settings-devices.md) | Adds a device; removes a device's access. |
| How to Set Up a Server | `open-setup-guide` | Always | Opens the sync guide (`<repository>/blob/main/docs/guide/sync.md`) in the browser. |
| Learn More (former Mac server) | `open-former-server-guide` | Always | Opens `<repository>/blob/main/docs/guide/sync.md#if-you-used-use-this-mac`. |

### Stop Syncing confirmation

A confirmation (action sheet on phone, dialog on computer), with a visible title:
- Title: `settings.sync.stopSyncing.title` ("Stop syncing with {host}?"), where host is the server's host, with the port when it isn't the default.
- Message: `settings.sync.stopSyncing.message`; when items haven't reached the server, followed by a space and `settings.sync.stopSyncing.messageUnsent` (plural).
- Buttons: `settings.sync.stopSyncing.confirm` ("Stop Syncing"), `common.cancel`.

## States

- **Not connected:** Server section shows Connect to a Server…; footer explains where journals are and links to How to Set Up a Server. No Devices and no Stop Syncing section.
- **Syncing (person started it):** Last Synced shows Syncing… and an indicator; the action button is disabled.
- **Syncing automatically:** nothing changes; normal syncing is quiet.
- **Offline / server unreachable / unavailable:** footer shows the message; button Try Again; automatic retries continue.
- **Needs the person / server changed / no access:** footer shows the message; button Reconnect…; no Devices section; automatic sync has stopped until the person acts. After Reconnect succeeds the Devices section appears and lists the devices without reopening the pane.
- **Update or fix needed:** footer shows the message; Check Again.
- **Save failed:** footer `messages.sync.pausedForSaveFailure`; Sync Now disabled.
- **Locked:** Settings shows only its locked text; the Changes to Review and Changed on Two Devices sections are never shown while locked, and an open review closes when the app locks.
- **Something held:** the footer gains `messages.conflict.kept.updateNeeded`; nothing else changes.
- **Nothing settled:** the Changed on Two Devices section is absent, not an empty list.
- **Former Mac server (computer only):** not connected, with the special footer and Learn More.

## Rules

- **Sync Now** runs one sync at a time; pressing it again while running does nothing. It shows Syncing… for at least half a second, so it reads as done rather than as a flicker. When it ends, VoiceOver hears the footer message if there is one, else `messages.sync.announce.synced` ("Synced") if the Last Synced time moved, else `messages.sync.announce.failed`. A sync that can't run (see enabled) isn't shown as synced and announces nothing.
- **Last Synced** is the last time this device completed a sync with this server, including one that left a single refused entry or image behind. It is stored per library and connection, survives relaunches, and is forgotten when the library connects to another server. It never moves backwards.
- **Not on Server Yet** is read when the pane appears and after every sync.
- The action is chosen from the current state alone; there is exactly one.
- Reconnect… opens Reconnect where the person is: over Settings when pressed here.
- **Stop Syncing** never deletes anything: the journals, unsent changes and the identity they last synced with stay, so connecting to the same server later continues by identity. The device's access on the server is given up when the server still accepts it (best effort).
- The former-Mac-server footer appears only on a computer whose library was connected to the server earlier versions of the Mac app ran on itself; it stays until the library connects to any server.
- Normal syncing is quiet: nothing in this pane changes while automatic sync works.
- Settling a conflict is quiet too: a note appears in section 3 and nothing else happens. The notes are local to this device: they are not synced.

## Accessibility

- Last Synced and Not on Server Yet are each read as one element (label and value together).
- The action button's title says what it does; Connect to a Server… and Reconnect… end with an ellipsis because they open a sheet. Add Device… and Stop Syncing… end with one because they open a sheet or ask first.
- The Devices header is the section's one heading, followed by Add Device… and one row per device.
- Sync Now's result is announced (see Rules).
- Review Changes buttons name their item.
- A Changed on Two Devices row is one element: label (title, sentence, date and time), hint `messages.conflict.kept.rowHint` when it opens something; it wraps at every text size. Clear List is a plain button.

## Platform notes (Apple)

- iPhone and iPad: a pushed pane in the Settings sheet. The Stop Syncing confirmation is an action sheet with a visible title.
- Mac: the Sync tab of the Settings window, which has one height (the smaller of 640 points and the room the screen allows) and scrolls inside it; Connect to a Server and Reconnect open as a sheet on the Settings window, sized to fit inside it. The Stop Syncing confirmation is a dialog.
- The former-Mac-server footer exists only on the Mac (`docs/design/client-only-mac-lists-markdown-2026-10-05.md` §1.2).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
