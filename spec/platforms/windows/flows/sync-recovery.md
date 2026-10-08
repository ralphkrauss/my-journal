---
id: sync-recovery
title: Sync health and recovery (Windows)
spec: flows/sync-recovery.md
features: [sync-health, sync-recovery, sync-item-refusal, sync-network-return, sync-status]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.networking.connectivity.networkinformation.networkstatuschanged
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.window.activated
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.system.power.powermanager.systemsuspendstatuschanged
  - https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.systemevents.sessionswitch
---

# Sync health and recovery (Windows)

Every way sync can fail ends in exactly one state with one message and at most one action; writing never waits for sync and nothing is discarded. Detection, the table of states, the person's actions and the rules are the spec's [sync-recovery](../../../flows/sync-recovery.md) and run in the shared sync engine; this file says what starts a sync on Windows, how the paces map onto a desktop window that closes the app, and where each state is shown. The reconnect actions are [reconnect-to-server](reconnect-to-server.md); the control is [sync-status](../screens/sync-status.md); the messages are in [messages](../messages.md).

## Controls

| Spec element | Windows | Notes |
| --- | --- | --- |
| The state's message | The Sync page's `InfoBar` and the Sync status flyout | Severity and actions: [messages](../messages.md), Sync states |
| Sync now, Try again, Check again | The `ActionButton` of the Sync page's bar when a bar shows, otherwise a `Button` in the server card (D49); the flyout's action | "Syncing…" with a small indeterminate `ProgressBar` (or the text alone) beside Last synced, visible at least half a second ([11](../platform.md#11-progress-and-announcements)); the button dims while a sync runs. Nothing is shown in the title bar, the command bar or the taskbar while the library syncs |
| Set up server again…, Connect again…, Sign in… | One `ContentDialog` flow | [reconnect-to-server](reconnect-to-server.md) |
| Stop syncing | A confirmation dialog with no default button | [stop-syncing](stop-syncing.md) |
| Sync status button | Title bar, trailing area, at every width (D47) | [sync-status](../screens/sync-status.md) |
| Item refusals | The same bar and flyout, action Sync now | Messages in [messages](../messages.md) |

## What starts a sync

Windows desktop apps keep running while a window is open and do not run when it is closed ([30](../platform.md#30-sync-lifecycle-and-power)). There is no background-task budget and no state between "active" and "gone": a minimised window is simply inactive. The spec's triggers map as follows.

| Spec trigger | Windows source | Notes |
| --- | --- | --- |
| Active pace: every 3 seconds while My Journal is the active app | The library window is activated: `Window.Activated` with a state other than Deactivated, and the presenter is not minimised | Also true while a dialog or the Windows Security prompt belongs to the window. The Store's rating dialog and Windows Hello are the system's windows; the pace follows the activation state the system reports |
| Open, another app active: every 30 seconds | The window is deactivated or minimised, or the screen is locked (Win+L) without App Lock | Screen locked with App Lock on: sync pauses ([locked](#when-sync-does-not-run)) |
| At once when the app becomes active or returns from the background | The window is activated; the PC resumes from sleep (`PowerManager.SystemSuspendStatusChanged`, or `SystemEvents.PowerModeChanged`); the session is unlocked or reconnected (`SystemEvents.SessionSwitch`, the same session notifications as App Lock, [13](../platform.md#13-device-authentication-and-app-lock)) | Windows activation happens at every Alt+Tab, so the 10-minute limit of the stopped states and the debounce of a sync already running matter more than on a phone |
| At once when the network returns | `NetworkInformation.NetworkStatusChanged` (or the .NET network-change event): the waiting retry runs immediately and any wait for the server's changes ends | A change of network path ends a wait even when it is still online. Metered connections are not treated specially in version 1 |
| After a pause in writing, and when leaving an entry | As the spec, from the document model | Unchanged |
| Up to 3 seconds of sending on quit | On window close and at end of session | The close waits for the save and then up to 3 seconds for sync ([save-entry](save-entry.md)); the window never stays open longer for sync |
| iOS background time | Not applicable | The app is not suspended; at sign-out the app holds shutdown briefly while a save finishes ([3](../platform.md#3-windows-and-instances)) |
| Wait for changes instead of polling, when the server supports it | The same long wait; a closed window ends it | |
| Connect to a Server's first contact waits up to 20 seconds, "because the system may ask for local network permission" | Windows has no such prompt ([32](../platform.md#32-local-network-and-servers)); the engine may keep the allowance, which also covers a VPN or Tailscale client that is still starting | Not a behaviour change; recorded so nobody looks for a prompt |

**When the app is closed nothing syncs.** Changes from other devices arrive the next time the window opens, which the spec's launch check, "at most every 10 minutes" for stopped states and "changes left from days ago don't flash at launch" already allow. The person is not told that sync stops with the window; the saved writing and "Not on server yet" are the truth ([settings-sync](../../../screens/settings-sync.md)). A background task or start-up task would be needed to do better; it is not offered ([30](../platform.md#30-sync-lifecycle-and-power), [19](../platform.md#19-single-instance-and-activation)), and the owner's decision D23 on closing the window decides this.

### When sync does not run

| Condition | Windows signal |
| --- | --- |
| Locked | App Lock's locked state (launch, Ctrl+L, inactivity, Win+L, sleep, user switch); saved writing is still sent as the lock happens |
| The library is being replaced | The connect, encrypt and import flows hold the library |
| A save has failed | The save-failure state ([save-failure](save-failure.md)) |
| A stopped state | Sign-in needed, not set up, restored or replaced, access removed, update My Journal: one check at launch and when the window is activated, at most every 10 minutes; the state's action or Sync now always runs |

### Paces after a failure and the long wait

As the spec: 3 seconds doubling to 5 minutes, at least the server's Retry-After; update-or-fix states every 5 minutes; the long wait of 24 hours is checked after every sync, including the sync when the window becomes active. Timers are ordinary app timers; a sleeping PC does not run them, so the first sync after resume runs at once rather than after the remaining wait.

## Layout at each window width

Not applicable to the sync itself. The bar, flyout and dialog are mapped in [messages](../messages.md), [sync-status](../screens/sync-status.md) and [reconnect-to-server](reconnect-to-server.md).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `sync-now` | Sync page; Sync status flyout | none | Connected, unlocked, not replacing the journals, no failed save, no sync the person started running |
| `sync-reconnect` | Sync page bar; Devices page; Privacy page; Agent Access page; Sync status flyout | none | The state calls for it |
| `stop-syncing` | Sync page | none | Connected, not replacing the journals |
| `try-syncing-again` | The recovery notice of an entry whose journal has not arrived | none | The journal is missing and the library syncs |
| `sync-status` | Title bar, trailing area | none | Sync needs the person |

## Copy differences

Sentence case for the actions and labels ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). The message wording variants are in [messages](../messages.md), Copy differences. The spec's last-synced words ("Just now", "Yesterday at {time}") are built with the formatter of the user's regional settings ([31](../platform.md#31-dates-time-zones-and-formats)).

## Accessibility

- The result of Sync now, Try again and Check again is raised as a Narrator notification: the held message, else `messages.sync.announce.synced`, else `messages.sync.announce.failed`. Automatic syncs and background state changes are never announced; the bar on the Sync page is updated in place so that nothing speaks ([messages](../messages.md), Narrator notifications).
- Last synced and Not on server yet are each one element ("Last synced, Just now"); the progress bar beside "Syncing…" is hidden from the tree.
- The pace and the long wait have no UI. Windows Narrator, magnifier and high-contrast users get the same states as everyone.

## Different by design

- **No background sync and no "background" pace.** Apple apps suspend and return; a Windows window is active, inactive or gone, so the 30-second pace covers every inactive state and closing the window ends sync ([30](../platform.md#30-sync-lifecycle-and-power)).
- **More triggers at activation.** Windows activation fires at every window switch, so a sync is started at activation only when none is running and the stopped-state limit allows it.
- **Resume and unlock are triggers**, because a PC that sleeps overnight holds changes that should go out when the person returns.
- **No local-network allowance** in the first-contact wait is needed, though the engine may keep it.
- **The Mac-only former-server step** (`settings.sync.footer.formerMacServer`) does not exist ([12.3](../platform.md#123-vocabulary)).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D49 (Sync page message surface), D23 (closing the window).
