---
id: settings-sync
title: Settings ▸ Sync (Windows)
spec: screens/settings-sync.md
features: [sync-connect, sync-now, sync-status-footer, stop-syncing, sync-recovery, changes-to-review-list, former-mac-server-notice]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
---

# Settings ▸ Sync (Windows)

The Sync page: which server this PC syncs with, how syncing stands, the one action that fits, Stop syncing and Changes to review. Behaviour, states and copy keys are the spec's [Settings ▸ Sync](../../../screens/settings-sync.md); the shell and patterns are in [settings](settings.md#card-patterns).

## Controls

Page title: breadcrumb "Settings > Sync".

### Status message

Above the first group, at most one `InfoBar`: the first of the spec's footer messages that is a sync message, in the spec's order: `messages.sync.pausedForSaveFailure`, then the sync state's message (`messages.sync.<state>`, or the message about the single entry or image the server did not accept). `IsClosable` false, icon always shown, the state's single action (`messages.sync.action.*`, `common.tryAgain`, `common.reconnect`) as the bar's `ActionButton`; `messages.sync.pausedForSaveFailure` has no action, because it names Try again in the entry. Severity, action and wording per state are the table in [messages](../messages.md) (Sync states): Warning for a state that stops syncing or needs the person (including `messages.sync.pausedForSaveFailure`, `messages.sync.unexpected` and a refused entry or image), Error only for `messages.sync.localDataUnreadable`, Informational for offline, unreachable and unavailable. `messages.sync.waiting` is not shown on this page (the spec shows it in Sync status only).

The bar is created when the page loads and updated in place afterwards, so a background change never speaks; a result of Sync now, Try again or Check again is announced by the notification of [messages](../messages.md) (Narrator notifications), not by the bar. Changes are debounced by half a second. The not-connected footer and the two library notes (`messages.library.needsUpdate`, `messages.library.waitingForServer`) are not bars: they are the description of the server card below, shown when no bar is. The action is in the bar when a bar shows and the state has an action, and in the server card otherwise; never in both (D49).

### Server group

Header `settings.connect.server`.

| State | Control | Notes |
| --- | --- | --- |
| Not connected | A [primary button card](settings.md#card-patterns): `Header` `settings.sync.footer.notConnected`; `Description` a `HyperlinkButton` `settings.sync.footer.howToSetUp` (opens the sync guide in the default browser); accent `Button` `common.connectToServer` | The footer and the link sit with the button they explain. The Mac-only former-server footer (`settings.sync.footer.formerMacServer`, `settings.sync.footer.learnMore`) is never shown |
| Connected: server | `SettingsCard`, `Header` the address as typed (`IsTextSelectionEnabled`, `BodyStrongTextBlockStyle`), `Description` the library note when one applies and no bar shows, trailing the action button when it holds the action | Holds the single action of the spec's table only when no bar shows or the bar's state has none (Sync now, and the disabled Sync now beside `messages.sync.pausedForSaveFailure`); otherwise the bar carries it (D49). Standard `Button`; accent only for Sign in, Set up server again and Connect again |
| Connected: last synced | A value card, `Header` `settings.sync.lastSynced`, value the description | Shown while a sync the person started runs, and once this device has completed a sync with this server. While Sync now runs the value is a small indeterminate `ProgressBar` with `settings.sync.syncing` (or the text alone: the page stays usable, so not a ring, [platform.md, 11](../platform.md#11-progress-and-announcements)); otherwise `settings.sync.lastSynced.justNow`, a relative description, `settings.sync.lastSynced.yesterday` or `settings.sync.lastSynced.date`. A `DispatcherTimer` refreshes it every minute while the page is open and the window is active |
| Connected: not on server yet | A value card, `Header` `settings.sync.notOnServerYet`, value `common.itemCount` | Only when items waiting. Read when the page appears and after every sync |

The action button's title is chosen from the state alone, as in the spec's table: `messages.sync.action.syncNow`, `common.tryAgain`, `common.reconnect`, `messages.sync.action.checkAgain`. The ones that open the Connect task page keep their ellipsis. Windows has no relative-time formatter, so "5 minutes ago" and "2 hours ago" are built by the app (B34); the date forms use `DateTimeFormatter` with the user's regional format ([platform.md, 31](../platform.md#31-dates-time-zones-and-formats)).

### Stop syncing group (connected only)

An [action card](settings.md#card-patterns): `Header` `settings.sync.stopSyncing` as the card's label and a standard `Button` `settings.sync.stopSyncing` in its content, no icon. Not styled as destructive (no red): nothing is deleted. The button opens the confirmation dialog; the card itself is not clickable.

**Confirmation.** `ContentDialog`: `Title` `settings.sync.stopSyncing.title` (a question); content `settings.sync.stopSyncing.message`, then a space and `settings.sync.stopSyncing.messageUnsent` when items are not on the server; Primary `settings.sync.stopSyncing.confirm`; Close `common.cancel`; `DefaultButton` None ([Dialog patterns, 7](settings.md#dialog-patterns)). The steps after it are the stop-syncing flow.

### Changes to review group (only when there are conflicts)

Header `messages.conflict.settingsSection`. One `SettingsCard` per conflict: `Header` the item's title (the spec's deleted-item title for a permanent deletion), `Description` the date and time of the local version or of the deletion, trailing `Button` `common.reviewChanges` with `AutomationProperties.Name` `common.reviewChangesFor`. It opens the conflict review page ([conflict-review](conflict-review.md)), which first saves the open entry. The group never shows while the window is locked, and the review page closes when it locks.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Cards in the column of [settings](settings.md); the status bar full width above the group | Mac Sync tab |
| Small | The action button moves under the address; the status bar wraps; value cards put their value under the label | iPhone pushed pane |
| Text size 200% or more | As small | Accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `connect-to-server` | Primary button card | as in commands.md | Always (the window is unlocked) |
| `sync-now` | The bar's action, or the button in the server card when no bar shows (D49) | as in commands.md | Not while a sync the person started runs; not while the library is being replaced, a save has failed, or without a working connection. Shows "Syncing…" for at least half a second |
| `sync-reconnect` | The bar's action when the state needs it | as in commands.md | Not while a sync the person started runs |
| `stop-syncing` | The button in the Stop syncing card | — | Not while the library is being replaced |
| `review-changes` | Button in each conflict card | — | Always on this page |
| `open-setup-guide` | Hyperlink in the not-connected card | — | Always |
| `open-former-server-guide` | Not offered | — | Mac-only state |

When Sync now ends, Narrator hears the status message if there is one, otherwise `messages.sync.announce.synced` if the last-synced time moved, otherwise `messages.sync.announce.failed`: a notification event with `ImportantMostRecent` processing ([platform.md, 11](../platform.md#11-progress-and-announcements)). A sync that cannot run announces nothing. Windows has no new triggers on this page; the pace and triggers of automatic sync are in [platform.md, 30](../platform.md#30-sync-lifecycle-and-power).

## Copy differences

Sentence case applies ("Last synced", "Not on server yet", "How to set up a server", "Sign in…"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.sync.stopSyncing` | Stop Syncing… | Stop syncing | ellipsis (platform.md, 12.2) |
| `settings.sync.stopSyncing.message` | …choose Connect to a Server in Settings > Sync. | …select Connect to a server in Settings > Sync. | vocabulary (platform.md, 12.3) |
| `settings.sync.footer.formerMacServer`, `settings.sync.footer.learnMore` | the Mac-only footer and link | Not shown | removed (platform.md, 12.3) |
| `messages.sync.pausedForSaveFailure` | …Choose Try Again in the entry. | …Select Try again in the entry. | vocabulary: the same "choose" rule, B26 |
| `messages.sync.localDataUnreadable` | …choose Export Archive in Settings > Backup. | …select Export archive in Settings > Backup. | vocabulary: B26 |
| Relative last-synced strings | none (the platform formats them on Apple) | see B34 | new |

## Accessibility

- The server card is read as one element: "{address}, {action}"; Last synced and Not on server yet are one element each (label and value), as the spec asks.
- The status bar is read when it opens. The action button's name is its label; where it opens a page or dialog its `AutomationProperties.HelpText` says so only through the ellipsis, not extra text.
- The progress bar has the name `settings.sync.syncing`. Review changes buttons name their item.
- While Sync now runs the button is disabled and focus moves to the card (the server card is focusable as a group) so it is not dropped to the page; when the sync ends focus returns to the button. Stop syncing and the Connect page return focus to their opener.
- Contrast themes: the `InfoBar` severities keep their icons; nothing relies on colour.

## Different by design

- **Footer messages are an `InfoBar`.** Apple shows the state's message as the section footer. Windows shows a persistent status bar at the top of the page, the Windows 11 Settings pattern, and puts the one action in it (or beside the server when no bar shows). The text, order and "first that applies" rule are the spec's.
- **No former Mac server notice.** The server earlier Mac versions ran on that computer does not exist on Windows.
- **Stop syncing has no ellipsis**: it only asks for confirmation ([platform.md, 12.2](../platform.md#122-ellipsis)).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose), B34 (relative times), D49 (Sync page message surface).
