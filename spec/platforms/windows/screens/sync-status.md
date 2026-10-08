---
id: sync-status
title: Sync status (Windows)
spec: screens/sync-status.md
features: [sync-status, sync-health, sync-item-refusal]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/flyouts
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobadge
---

# Sync status (Windows)

A small status control that appears only when sync needs the person: it says what is wrong in one sentence, offers the one action that can fix it, and points to the Sync settings. Normal syncing and retrying by itself stay silent. Behaviour, the table of states and the rules are the spec's [sync-status](../../../screens/sync-status.md); the states, their paces and their actions are [sync-recovery](../flows/sync-recovery.md); the messages' severity and the Sync page's bar are in [messages](../messages.md).

## Controls

| Spec element | Control | Notes |
| --- | --- | --- |
| The control | A subtle icon `Button` in the title bar's trailing area, between the drag region and the caption buttons ([library-window](library-window.md)), icon SyncError (EA6A), tooltip and `AutomationProperties.Name` `messages.syncStatus.title`, with an attention-dot `InfoBadge` over the icon | The spec's symbol is always the cloud with an exclamation mark: SyncError. The dot is Windows' "needs attention" mark and adds no meaning the icon and name do not have. It sits in the title bar at every width (D47), so it is reachable from every page and from Settings and never goes into an overflow menu |
| Shown only when it applies | `Visibility` follows the spec's table: connected, unlocked, and the state is one that shows (needs the person, an item refused, or the long wait) | Whether it shows changes only when a sync finishes, so it never flickers. A Try again that runs keeps it in place |
| Nothing moves when it appears | The button takes the end of the drag region, so no other control shifts when it appears or goes. There is no reserved empty place | The old reserved gap was needed only in the editor header's command bar |
| The menu | A `Flyout` (not a `MenuFlyout`), `Placement` BottomEdgeAlignedRight, 320 epx wide, content a `StackPanel` | A disabled menu item cannot take keyboard focus or be reached by Narrator, so the message cannot be a disabled item as on the Mac. In the flyout it is ordinary text that Narrator reads first |
| 1. The state's message | `TextBlock`, `Body`, wrapping, `IsTextSelectionEnabled` true: the `messages.sync.*` text, or an item-level message, or `messages.sync.waiting` when none is held | The same text as the Sync page's bar |
| 2. The state's single action | One `Button`, accent style: `messages.sync.action.syncNow`, `common.tryAgain`, `messages.sync.action.checkAgain`, `messages.sync.action.setUpServerAgain`, `messages.sync.action.connectAgain` or `common.signIn`, by state | The one primary action of the surface. The connect actions close the flyout, then open the Connect task page ([reconnect-to-server](../flows/reconnect-to-server.md)). After Sync now, Try again and Check again the flyout closes and focus returns to the button |
| 3. Sync settings | `HyperlinkButton` `messages.syncStatus.settings`, last | Opens the Settings page at Sync ([10](../platform.md#10-settings)); saves the open entry first |
| Update messages | For `messages.sync.appUpdateNeeded`, a second `HyperlinkButton` "Get updates" under the action | New Windows-only string; opens the Microsoft Store's updates page (D51, B38) |
| Busy | A sync the person started shows no progress here; the Sync page shows "Syncing…" | As the spec |
| Locked | The button is not shown; locking forgets the held message | The lock page replaces the window ([13](../platform.md#13-device-authentication-and-app-lock)) |
| Save failed | Sync does not run; the button keeps what the last sync decided; the Sync page says why | `messages.sync.pausedForSaveFailure` is not in this flyout |

The states table, "when it shows", the long wait (more than 24 hours with changes waiting), and "temporary states stay quiet" are the spec's and are not repeated.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The button sits in the title bar's trailing area, icon only with a tooltip. The flyout is anchored below it | Mac toolbar button |
| Small | The same place; the flyout fills the width. The title bar holds the pane or back button, the name, the More button and this button | iPhone: a submenu of the entry's More menu, reachable only with an entry open (a gap the spec lists as an open question) |
| 200% text size or more | The flyout grows and scrolls; the button keeps its icon only | |

The title bar at every width is the draft default of D47 (the review's recommendation): one place, nothing depends on the layout.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `sync-status` | The title bar button; Settings ▸ Sync | none: the spec has no shortcut, and Windows adds none | Sync needs the person (the spec's table) |
| `sync-now` | The flyout's action | none | The spec's rule: not locked, not replacing the journals, no failed save, no sync the person started running |
| `sync-reconnect` | The flyout's action | none | The state calls for it |

Keyboard: Tab reaches the button in the title bar, after the menu bar; Enter or Space opens the flyout; focus starts on the action button; Esc closes the flyout and returns focus to the button. The flyout is not in the menu bar, as in the spec.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): `messages.syncStatus.title` is "Sync status", and the actions "Sync now", "Check again", "Try again", "Sign in…". Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `messages.syncStatus.settings` | Sync Settings… | Sync settings | ellipsis and casing |
| (new) | none | Get updates | new Windows-only string, for the app-update message (D51, B38) |

## Accessibility

- The button's name is `messages.syncStatus.title`; its tooltip repeats it. The `InfoBadge` is hidden from the tree. Narrator reads "Sync status, button".
- The flyout is read when it opens: the message first, then the action. Focus starts on the action.
- No announcement when the button appears or disappears: sync is quiet, and the spec announces only results of actions the person started ([messages](../messages.md), Narrator notifications). After Sync now, Try again or Check again the result is raised as a notification.
- In contrast themes the icon and badge use theme colours; the dot is also a shape, not only a colour. Reduced motion: the button appears at once.

## Different by design

- **A flyout, not a menu.** The Mac shows a menu whose first item is a disabled line of text. A menu item that is disabled is skipped by keyboard and Narrator on Windows, so the message would be unreadable; a flyout reads it.
- **The accent action button** is the one primary action of the surface; the Mac's menu has no emphasis.
- **Title bar at every width** so the control is reachable on every page, where iPhone only reaches it with an entry open and the Mac has it in the editor toolbar.
- **A "Get updates" link** where the message says to update, since Store builds update through the Microsoft Store.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D47 (where Sync status lives), D51 (update link), B38 (update link wording).
