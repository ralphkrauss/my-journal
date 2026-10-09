---
id: sync-status
title: Sync Status
features: [sync-status, sync-health, sync-item-refusal]
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Views/RootView+Toolbar.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/Mac/RootView+MacWindow.swift
  - apps/apple/JournalApp/Views/Mac/JournalToolbarController.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - docs/design/sync-health-and-recovery.md
  - docs/design/quiet-sync-and-title-alignment.md
  - docs/design/sync-now-and-done.md
---

# Sync Status

## Purpose

A small status control in the journal window that appears only when sync needs the person: it says what is wrong in one sentence, offers the one action that can fix it, and points to Settings ▸ Sync. Normal syncing, and retrying by itself, stay silent.

## Entry points

- **Mac:** a toolbar button in the journal window, in a place kept for it while the library syncs with a server. In a narrow window it is the first item to move into the toolbar's overflow menu, where it is an item with the same submenu.
- **iPhone and iPad:** a submenu at the end of the open entry's More menu (the "…" Entry Actions menu). No toolbar button is ever added or removed.

There is no keyboard shortcut and no menu bar command.

## Content

A menu, in this order:

1. **The state's message**, as non-interactive text: the sync message (`messages.sync.*`, see the table in Rules), or an item-level message (`messages.sync.recordTooLarge`, `messages.sync.recordRefused`, `messages.sync.imageTooLarge`, `messages.sync.imageRefused`). When no message is held, `messages.sync.waiting` (see Open questions).
2. **The state's single action** (one of `messages.sync.action.syncNow`, `common.tryAgain`, `messages.sync.action.checkAgain`, `common.reconnect`).
3. **Sync Settings…** (`messages.syncStatus.settings`).

The control's label, help tag and accessibility label are `messages.syncStatus.title`. Its symbol is always a cloud with an exclamation mark; the plain cloud is never used.

## Actions

| Action | What it does | Afterwards |
| --- | --- | --- |
| Sync Now, Try Again, Check Again | Runs one full sync now (the same as Sync Now in Settings ▸ Sync): it reads the server's status, this device's access and identity first, and resends records and images the server refused before. | Sync Status stays as it is until the sync finishes, then shows or hides by the rule below. VoiceOver announces the result (see Accessibility). |
| Reconnect… | Opens Reconnect over the journal window, at this device's server, and checks it at once. See [flows/sync-recovery.md](../flows/sync-recovery.md) and [flows/reconnect-to-server.md](../flows/reconnect-to-server.md). | When the connection succeeds, the state is cleared and Sync Status hides. |
| Sync Settings… | Opens Settings at Sync. Mac: the Settings window, on its Sync tab. iPhone and iPad: Settings, pushed to Sync. | |

The action is chosen from the current state alone, so it always follows the latest sync.

## States

**When it shows.** Only while this library is connected to a server, and only when one of these holds:

| Situation | Shows | Message | Action |
| --- | --- | --- | --- |
| No server | no | | |
| Syncing normally, with or without changes waiting | no | | |
| Temporary: offline, can't reach, server busy, this device's data busy | no, unless the long wait applies | `messages.sync.offline`, `messages.sync.unreachable` (or `messages.sync.unreachableTailscale` for a `.ts.net` host), `messages.sync.unavailable`, `messages.sync.localDataUnavailable` | `common.tryAgain` |
| Long wait: the last sync failed, changes are waiting, and more than 24 hours passed since Last Synced (or since the first failure when this connection never synced) | yes, in any state | the state's own message | the state's action |
| Needs you (sign-in needed) | yes | `messages.sync.signInNeeded` | `common.reconnect` |
| Server changed: not set up | yes | `messages.sync.serverNotSetUp` | `common.reconnect` |
| Server changed: restored or replaced | yes | `messages.sync.serverReplaced` | `common.reconnect` |
| No access | yes | `messages.sync.accessRemoved` (`messages.sync.accessRemovedNoPassword` for a library without a password) | `common.reconnect` |
| Update or fix needed | yes | `messages.sync.appUpdateNeeded`, `messages.sync.serverUpdateNeeded`, `messages.sync.certificateInvalid`, `messages.sync.notJournalServer` | `messages.sync.action.checkAgain` |
| Unexpected | yes | `messages.sync.unexpected`, or `messages.sync.localDataUnreadable` for this device's own data when it is damaged | `common.tryAgain` |
| One record or image refused, everything else synced | yes | the item-level message | `messages.sync.action.syncNow` |

- **Locked:** not shown. The Mac removes the journal toolbar while locked; iPhone and iPad show the lock screen. Locking also forgets the held message, because a refused item's message names an entry.
- **Busy:** a sync the person started shows no progress here; Settings ▸ Sync shows "Syncing…" next to Last Synced.
- **Save failed:** sync doesn't run, so Sync Status keeps whatever the last sync decided. Settings ▸ Sync says why (`messages.sync.pausedForSaveFailure`).

## Rules

- **Quiet by default.** Writing never makes Sync Status appear. Changes waiting to sync are visible only in Settings ▸ Sync (Not on Server Yet).
- **No flicker.** Whether it shows changes only when a sync finishes. A Try Again that runs keeps it in place until the sync succeeds or the state changes.
- **No layout shift (Mac).** While the library syncs with a server, the toolbar keeps an empty place exactly as wide as the button, between the flexible space after Insert Image and a fixed space before Editor Only. The empty place draws nothing, is not in the keyboard loop or the accessibility tree, has no help tag, and is hidden in the overflow menu. Connecting or Stop Syncing adds or removes the place; a library without a server has no gap.
- **One state at a time, one action.** It never offers an action that can't work in the current state.
- **The same message everywhere.** Settings ▸ Sync ([settings-sync.md](settings-sync.md)) shows the same text as Sync Status, in the Server section's footer (on the Mac, as secondary text below the section). The footer's priority is: `messages.sync.pausedForSaveFailure` while connected and a save has failed; else the sync message; else, when not connected, the not-connected text of Settings ▸ Sync; else `messages.library.needsUpdate`. Temporary states show there even while Sync Status stays hidden.
- **Temporary states stay quiet.** Offline, can't reach and busy are invisible outside Settings ▸ Sync until the long wait. This is by design (owner decision 2026-10-02); other platforms shouldn't “fix” it.
- **Hosts in messages.** Messages say "the server". Only the Tailscale hint depends on the host (a host ending in `.ts.net`).
- **No implementation details.** No message shows status codes, SQL, error domains or the word "request".

## Accessibility

- The control is a menu button labelled "Sync Status" (`messages.syncStatus.title`), opened by click, Space or VoiceOver's activate; the symbol has the same accessibility description.
- The message is the menu's first, non-interactive item, so VoiceOver reads it first.
- **Announcements come only from actions the person started.** After Sync Now, Try Again or Check Again finishes (from here or Settings), VoiceOver announces the held message if there is one, otherwise `messages.sync.announce.synced` after a successful sync, otherwise `messages.sync.announce.failed`. Automatic syncs and state changes in the background are never announced; they are read where they are shown.
- Reduce Motion: on the Mac the button fades in over 0.2 seconds, or appears at once with Reduce Motion. Nothing else moves.
- Increase Contrast and Reduce Transparency need nothing extra: it is a standard toolbar button and menu.
- Full Keyboard Access reaches it on the Mac and iPad like any toolbar or menu item.

## Platform notes (Apple)

- **Mac:** a toolbar button with its own glass, separated from Editor Only's group by a fixed space, with the lowest visibility priority. In the overflow menu its item reads "Sync Status" and opens the same submenu. The message is a disabled menu item on one line.
- **iPhone and iPad:** the "Sync Status" submenu is the last item of the open entry's More menu, after the entry's actions. The More menu is disabled while no entry is open or a deleted journal is shown, so Sync Status is reachable only with an entry open (see Open questions). Connect actions present Connect to a Server as a sheet over the journal window.
- **Windows and Android** should keep the rule (quiet, shown only when the person must act) and put the control where the platform shows a window's or app's status without moving other controls.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
