---
id: messages
title: Messages (Windows)
spec: messages.md
features: [sync-health, sync-status, sync-item-refusal, save-failure-recovery, writing-paused-notice, generic-error-alert, conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-journal, conflict-review-deletion, conflict-review-unsupported, library-open-failure, read-only-newer-content, unavailable-journals, privacy-cover, accessibility-announcements]
status: reviewed
---

# Messages (Windows)

Where each message of the spec's [messages](../../messages.md) appears on Windows, with which control, at which severity, and how Narrator hears it. The spec says when a message appears and what the person can do; its copy keys are used unchanged (sentence case and the vocabulary variants of [platform.md, 12](platform.md#12-copy-casing-ellipses-and-vocabulary) apply). This file decides only the surface. [platform.md, 8, 9 and 11](platform.md#8-dialogs) hold the control rules; the pages that own each message have their own mapping: [sync-status](screens/sync-status.md), [sync-recovery](flows/sync-recovery.md), [save-failure](flows/save-failure.md), [conflict-review](screens/conflict-review.md), [unavailable-content](screens/unavailable-content.md).

Microsoft's guidance for choosing the surface, which the rules below apply: an `InfoBar` is for a changed application state that stays until it is resolved or acknowledged, inline and not time-critical; a `ContentDialog` is for confirming an action the person started, for information they must read, and for a state so severe that the app cannot continue; a `Flyout` is for information tied to one control; a field's own error is inline next to the field ([InfoBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar), [Dialogs](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs), checked 2026-10-06). Quiet saving and syncing is a product rule: nothing below shows, sounds or flashes during normal saving or syncing.

## Controls

### From Apple surface to Windows surface

| Apple surface (spec table "How messages reach the person") | Windows surface | Rule |
| --- | --- | --- |
| Settings ▸ Sync footer: the sync message, item refusal, save-paused note, library note | On the Sync page: the message in a non-closable `InfoBar` at the top of the page, with the state's single action as its `ActionButton`; the not-connected text and the two library notes (`messages.library.needsUpdate`, `messages.library.waitingForServer`) as the description of the status card, not as bars. Priority of the spec is kept: `messages.sync.pausedForSaveFailure`, then the sync message, then the not-connected text, then the library notes | The page is the [settings-sync](../../screens/settings-sync.md) page; this file fixes the message, severity and action (D49) |
| Sync Status | A `Flyout` from the button in the title bar's trailing area (every width, D47); [sync-status](screens/sync-status.md) | Only when the person must act or after the long wait |
| Generic alert (`common.alertTitle`, the message, `common.ok`, plus `common.tryAgain` while a save has failed) | A `ContentDialog` through the dialog queue below: no title (`common.alertTitle` is left out, [8.1](platform.md#81-rules) rule 3), content the message, Close `common.ok`; Primary `common.tryAgain` (default button) while a save has failed | One at a time, only from a person-started action or a window-level model error, never while locked or while the first journal is being created |
| Lock screen note | An error `InfoBar` in the lock page ([unavailable-content](screens/unavailable-content.md)) | Opened when the lock page appears or the message changes (a changed message in an open bar is not announced, so a new bar replaces it) |
| Sheet errors (an operation's error inside its own sheet) | An inline `InfoBar`, Severity Error, not closable, in the dialog's or page's content, above the buttons | Never a second dialog; the bar is announced when it opens |
| Notices above the writing (save failure, writing paused, conflict, recovery, unavailable) | `InfoBar`s above the title, in the order of [entry-editor](screens/entry-editor.md) | Not closable; each closes when its state ends |
| Announcements | Narrator notifications, below | Only for results of actions the person started and for errors that appear in an open dialog or page |

### Severity

| Situation | `InfoBar` severity | Why |
| --- | --- | --- |
| A sync state that stops automatic sync or needs the person (sign-in needed, not set up, restored or replaced, access removed, update needed, certificate, not a journal server, unexpected, an item refused) | Warning | A condition that will cause a problem if left; nothing is lost, since the writing is saved on this device |
| This device's own data cannot be read (`messages.sync.localDataUnreadable`), a failed save (`messages.save.notSaved`), an error inside a dialog or page, the lock page's note (except `messages.library.deviceKeyUnavailable`, below) | Error | A problem that has happened |
| `messages.library.deviceKeyUnavailable` on the lock page | Warning | It explains why the password is asked; nothing has failed that the person can fix by retrying |
| Offline, can't reach, server busy, `messages.sync.waiting`, writing paused, recovery and unavailable notices | Informational | Expected or temporary; quiet by design. Recovery notices become Warning when a journal needs review |
| Changes to review (`messages.conflict.entryNotice`) | Warning | The person has a decision to make |
| `messages.sync.pausedForSaveFailure` | Warning | Sync waits for the save; the Error is the save notice itself |

Every bar has its icon and its text states the situation, so severity is never colour alone ([9.1](platform.md#91-notices)). Success is never shown: nothing completes loudly (the spec has no success message).

### The dialog queue

A window can show only one `ContentDialog` at a time and a second one throws ([8.1](platform.md#81-rules)); the Apple app layers alerts over sheets freely. Every dialog of the app, flows and alerts, goes through one queue so that it cannot happen:

1. Requests are shown in the order they were made. A request carries its owner (a flow, or "alert"), and whether a lock drops it.
2. While a flow's dialog or task page is open, errors of that flow show inside it as inline bars. A model error of something else waits until the dialog closes, then shows as the alert. Identical texts that are waiting are shown once.
3. An alert from a person-started action shows at once (after the current dialog). An alert from a model error that arises while the window is not active waits until the window is active again, so a dialog is never shown unseen.
4. An open flyout or menu closes before a dialog opens. Focus returns to the control that opened the dialog, or to the list or editor when that control is gone.
5. Locking hides the open dialog and empties the queue (the lock page shows a held error as its note); erasing does the same ([8.1](platform.md#81-rules) rule 5). The first-journal creation and the lock page never show an alert; their errors are inline.
6. A dialog never opens another dialog: a step inside a flow replaces the content, and a second flow opens when the first has closed.

### Narrator notifications

The announcements of the spec are raised with `AutomationPeer.RaiseNotificationEvent` on the window's peer ([11](platform.md#11-progress-and-announcements)). The text is the copy key; the activity id groups notifications of one kind so that a newer one can replace an older.

| Announcement | Kind | Processing | Activity id |
| --- | --- | --- | --- |
| The held sync message; else `messages.sync.announce.synced`; else `messages.sync.announce.failed` (after Sync now, Try again or Check again, from the Sync page or the Sync status flyout; never for automatic syncs) | ActionCompleted for synced; ActionAborted for the others | ImportantMostRecent | sync-result |
| `messages.announce.pinned`, `messages.announce.unpinned` | ActionCompleted | MostRecent | pin |
| `messages.announce.journalMovedAbove`, `messages.announce.journalMovedBelow` | ActionCompleted | MostRecent | journal-order |
| `messages.encryption.announce.turningOn`, `messages.encryption.announce.updatingServer`, `messages.encryption.announce.done` | Other | ImportantAll, so "You can't stop this now" is never cut | encryption |
| `common.saveFailed` for a failure that began while typing (the Apple alert is not shown, [save-failure](flows/save-failure.md)) | ActionAborted | ImportantMostRecent | save-failure |
| An error in an open dialog or page | None of its own: the inline `InfoBar` opens and announces itself | | |
| Pressing Copy for an address or code | ActionCompleted, the spec's copy confirmation where it has one | MostRecent | copy |

Notices, dialogs and the lock page are not announced separately: Narrator reads a `ContentDialog` when it opens (title, then content) and an `InfoBar` when it opens. A visually hidden live-region `TextBlock` is the fallback where the peer is not reachable. The Sync page's bar is created when the page loads and updated in place afterwards, so a background state change never speaks.

### Sync states

The messages and actions are the spec's table; this adds the Windows severity and where each shows. "Page" is the Sync page's `InfoBar`; "Flyout" is [sync-status](screens/sync-status.md).

| Key | Severity | Page | Flyout |
| --- | --- | --- | --- |
| `messages.sync.offline`, `messages.sync.unreachable`, `messages.sync.unreachableTailscale`, `messages.sync.unavailable` | Informational | Always; action `common.tryAgain` | Only after the long wait |
| `messages.sync.signInNeeded` | Warning | Action `common.reconnect` | Yes |
| `messages.sync.serverNotSetUp` | Warning | Action `common.reconnect` | Yes |
| `messages.sync.serverReplaced`, `messages.sync.accessRemoved`, `messages.sync.accessRemovedNoPassword` | Warning | Action `common.reconnect` | Yes |
| `messages.sync.appUpdateNeeded`, `messages.sync.serverUpdateNeeded`, `messages.sync.certificateInvalid`, `messages.sync.notJournalServer` | Warning | Action `messages.sync.action.checkAgain`; the app-update message adds a "Get updates" link (D51) | Yes |
| `messages.sync.localDataUnreadable` | Error | Action `common.tryAgain` | Yes |
| `messages.sync.unexpected` | Warning | Action `common.tryAgain` | Yes |
| `messages.sync.recordTooLarge`, `messages.sync.recordRefused`, `messages.sync.imageTooLarge`, `messages.sync.imageRefused` | Warning | Action `messages.sync.action.syncNow` | Yes |
| `messages.sync.waiting` | Informational | Not shown on the page (the spec shows it in Sync status only) | Yes |
| `messages.sync.pausedForSaveFailure` | Warning | No action; names Try again in the entry | No |

### Save failures

The failure itself is [save-failure](flows/save-failure.md). The "save first" refusals (`messages.save.before.goBack`, and `messages.save.before.tryAgain` in the alert dialog) are errors of an action the person started, so they show where that action's errors show: inline in its dialog or page (the Export, Import and Restore dialogs show it in their own error bar), or the alert dialog when the action opens nothing (Delete journal, Review changes, and the like). `messages.save.before.goBack` stays inline in its dialog or page; the two texts have Windows wording in [Copy differences](#copy-differences).

### Writing paused

`messages.writingPaused.connecting`, `messages.writingPaused.connectionFailed`, `messages.writingPaused.encrypting` and `messages.writingPaused.encryptionUnfinished` are the Informational `InfoBar` of [entry-editor](screens/entry-editor.md), without an action: Show connection and Show progress are not offered because the flow's dialog is modal over the only window. The bar is what stays visible behind the dialog's overlay. The dialog cannot be left while the work is unfinished ([turn-on-encryption](screens/turn-on-encryption.md), Unfinished, and [connect-to-server](screens/connect-to-server.md)), the Settings page's card reopens it, and an unfinished encryption reopens it at the next launch, so the bar needs no action of its own; after a crash the bar shows without an action until the person opens Settings. `messages.writingPaused.updating` is the alert dialog (an archive was opened while the library is replaced).

### Library cannot be opened, saved but not displayed, other alerts

| Messages | Windows surface |
| --- | --- |
| `messages.library.deviceKeyUnavailable`, `messages.library.cannotOpen`, `messages.error.newerVersion` | The lock page's `InfoBar`: Warning for `messages.library.deviceKeyUnavailable`, Error for the others ([unavailable-content](screens/unavailable-content.md), [lock-screen](screens/lock-screen.md)) |
| `messages.refresh.*`, `common.entryMovedNotDisplayed`, `messages.connection.connectedNotDisplayed` | The alert dialog (Close `common.ok`), or the error bar of the operation's dialog while it is still open. They say what was saved and tell the person to reopen My Journal; nothing is described as failed that was stored |
| `messages.generic.*` | The alert dialog |
| `messages.export.*`, `messages.import.*` | Inline error bar of the export dialog or the Import archive page, or of the Backup page for exports that start there ([export-archive](flows/export-archive.md), [export-markdown](flows/export-markdown.md), [import-archive](flows/import-archive.md)) |
| `messages.image.*` | The error dialog of [insert-image](flows/insert-image.md) (the editor's image-import `InfoBar` is only the progress notice); `messages.image.descriptionsNeedSource` is inline on the Image descriptions page |
| `messages.connection.*`, `messages.pairing.*`, `messages.password.*`, `messages.encryption.*`, `messages.server.*`, `messages.error.*` where they name a field or step | Inline next to the field when they are about one field (wrong password, setup code, address); otherwise the dialog's error bar |
| `messages.entry.*`, `messages.restore.*`, `messages.history.*`, `messages.lifecycle.*`, `messages.merge.*`, `common.journalGone`, `messages.journal.nameTaken` | Inline in the dialog or page that raised them, with the recovery buttons the spec names; `messages.journal.nameTaken` is inline under the name field (the Apple Name Taken alert becomes the field's own error) |

Messages marked unreachable or rare in the spec's notes are mapped like their group but need no design work.

### Unavailable and read-only content, App Lock paused, conflicts

- Unavailable and read-only content and `common.myJournalIsLocked` are in [unavailable-content](screens/unavailable-content.md) and [lock-screen](screens/lock-screen.md). There is no privacy cover on Windows ([platform.md, 20](platform.md#20-screen-capture-and-window-privacy)).
- **App Lock is paused** (Windows Hello not set up, not available or turned off by policy while App Lock is on, D42) is a Warning `InfoBar`, not closable, at the top of the library window on every page while the state lasts; it is not part of the editor's notice order. Text and rules: [flows/app-lock](flows/app-lock.md).
- Every key of the spec's Conflicts section is mapped in [conflict-review](screens/conflict-review.md), [entry-conflict](screens/entry-conflict.md) and [resolve-conflict](flows/resolve-conflict.md).

### Title bar and command bar

Sync state has no title-bar text and no badge on the title bar during normal syncing. The only sync mark in the window chrome is the Sync status button, in the title bar's trailing area at every width, shown only when the person must act ([sync-status](screens/sync-status.md); D47). The window title, the taskbar and the thumbnail never carry a sync or error message, because every process can read them and they must never name content.

## Layout at each window width

- **Bars.** Notices and bars are full width of their column and wrap their text; at 200% text size or more a bar taller than half its pane scrolls inside it ([entry-editor](screens/entry-editor.md)).
- **Dialogs** follow [8.1](platform.md#81-rules), rule 6; the alert dialog is the default width and fills the window width at small width.
- **Flyouts** (Sync status) fill the width at small width ([9](platform.md#9-sheets-popovers-and-notices)).
- The alert queue and the Narrator notifications do not depend on the layout.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `sync-now` | The Sync page and the Sync status flyout, as the bar's or the card's action | none | As the spec's rule: connected, unlocked, not replacing the journals, no failed save, no sync the person started running |
| `sync-reconnect` | The Sync page bar, the Devices page and the Sync status flyout | none | The state calls for it |
| `review-changes` | The conflict notice; the Changes to review list | none | Unlocked |
| `try-syncing-again` | The recovery notice | none | The journal is missing and the library syncs |

Keyboard: a bar's action button is in the tab order after the bar's title; Esc closes the alert dialog (Close `common.ok`); Enter chooses the default button only where the dialog sets one. No message has a shortcut of its own.

## Copy differences

Sentence case applies as in [platform.md, 12](platform.md#12-copy-casing-ellipses-and-vocabulary): for example `messages.save.notSaved` reads "Not saved", `messages.syncStatus.title` "Sync status", `common.myJournalIsLocked` "My Journal is locked", and the action labels "Sync now", "Check again", "Set up server again…", "Connect again…", "Sign in…". Already proposed in platform.md and not repeated: `messages.save.mac.title` (this PC), the `messages.writingPaused.*` Mac wording, `messages.library.cannotOpen`, `messages.image.unavailable`, the "Close this sheet" strings. New here:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `messages.syncStatus.settings` | Sync Settings… | Sync settings | ellipsis (opens a settings page) and casing |
| `messages.sync.pausedForSaveFailure` | … Choose Try Again in the entry. | … Select Try again in the entry. | vocabulary (B26) |
| `messages.sync.localDataUnreadable` | … choose Export Archive in Settings > Backup. | … select Export archive in Settings > Backup. | vocabulary |
| `messages.connection.serverChanged` | … Choose Continue to check it again. | … Select Continue to check it again. | vocabulary |
| `messages.connection.setUpElsewhere` | … Choose it again to sign in. | … Select it again to sign in. | vocabulary |
| `messages.sync.appUpdateNeeded` and the other "Update My Journal" texts | Update My Journal … | Unchanged. Where an action is needed, a link "Get updates" (new Windows-only string) opens the Microsoft Store's updates page | new string (D51, B38) |

## Accessibility

- A bar is announced when it opens; its text and its action button are read in that order; the icon is hidden and the severity is in the words.
- A dialog is read when it opens; focus starts on the first focusable control, or the default button; Esc and the Close button leave without acting.
- Notifications are never the only way to learn a state: everything announced is also visible where it belongs.
- Errors tied to a field are linked to it (`AutomationProperties.DescribedBy` or `LabeledBy`) so Narrator reads the error with the field.
- In the four contrast themes every bar, dialog and flyout uses theme brushes; the severity icons stay visible.
- At 225% text size bars and dialogs reflow and scroll; nothing is truncated.

## Different by design

- **Not every alert is a dialog.** Apple shows one alert style for model errors. On Windows an error tied to a field or a flow is inline, a state that stays is a bar, and only an answer to a person-started action that has no place of its own is a dialog, because a dialog blocks the window and takes keyboard focus.
- **A failed save while typing is not a dialog**, so keystrokes are never swallowed by a dialog that appears under the caret ([save-failure](flows/save-failure.md), D48).
- **The dialog queue.** Apple stacks alerts on sheets; Windows allows one dialog per window, so requests wait their turn and flow errors show inline.
- **The Sync page uses an `InfoBar` with the action inside it**, as Windows Settings does for update and account problems, where Apple has a footer and a row.
- **Update messages offer the Store**, since the app cannot update itself ([18](platform.md#18-packaging-distribution-and-updates)).
- **No success messages and no toasts or notification-area messages in version 1** ([19](platform.md#19-single-instance-and-activation)): the app is quiet when it is closed or in the background.

## Open questions

Recorded in [open-questions.md](../../open-questions.md): D47 (where Sync status lives), D48 (failed save while typing), D49 (Sync page message surface), D51 (update link), B38 (update link wording), B26 (select and choose).
