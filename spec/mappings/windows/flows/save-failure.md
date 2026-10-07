---
id: save-failure
title: Save failure and paused writing (Windows)
spec: flows/save-failure.md
features: [save-failure-recovery, writing-paused-notice]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-shutdownblockreasoncreate
---

# Save failure and paused writing (Windows)

When saving the open entry fails, the writing stays on screen and in memory, the person is told, and Try again stays next to the entry until it saves. Nothing that could lose the writing happens meanwhile. Steps, the "while a save has failed" table, the "save first" messages and the rules are the spec's [save-failure](../../../flows/save-failure.md); the normal save is [save-entry](save-entry.md). This file decides which Windows surface tells the person what, and what Windows adds at close, sign-out and shutdown.

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| The notice that stays (`messages.save.notSaved` in red, then `common.tryAgain`) | An `InfoBar` above the title, Severity Error, not closable, Title `messages.save.notSaved`, `ActionButton` `common.tryAgain`; while it runs the Title is `messages.save.saving`, an indeterminate `ProgressBar` is in the content and the action is disabled | First of the notices in [entry-editor](../screens/entry-editor.md). It takes no focus and is not read again on each edit. Closes without an announcement when the save succeeds. The same Windows copy is in the title: "Not saved" |
| The alert that tells the person (`common.saveFailed`, buttons `common.tryAgain`, `common.ok`) | A `ContentDialog` from the dialog queue ([messages](../messages.md)): no title, content `common.saveFailed`, Primary `common.tryAgain` as the default button, Close `common.ok` | Shown when the failure is caused by something the person did: Try again, leaving the entry, an operation that needs a saved entry, locking. Closing the window shows the Keep open dialog below instead. See the next row for typing |
| A failure that begins while typing | The notice opens; no dialog. A Narrator notification with the text of `common.saveFailed` is raised ([messages](../messages.md), Narrator notifications) | D48 |
| Lock screen: `common.saveFailedLocked` | The lock page's error `InfoBar` | [unavailable-content](../screens/unavailable-content.md). No entry title |
| Mac only: closing or quitting with an unsaved entry | A `ContentDialog` on window close, Alt+F4 and File ▸ Exit: title `messages.save.mac.title`, content `messages.save.mac.message`, Close `messages.save.mac.keepOpen`; the window stays open | Applies on Windows as the one window: [library-window](../screens/library-window.md). Not offered when there is nothing unsaved |
| Sign-out, restart or shutdown with an unsaved entry | The app sets a shutdown block reason (`ShutdownBlockReasonCreate`) with `messages.save.mac.title` and `messages.save.mac.message`, and removes it as soon as the entry is saved or the window is closed by the person | Windows lets the person choose to continue shutting down anyway; the app never refuses outright and never blocks without a failed save. Normal saves hold shutdown only for the brief save ([3](../platform.md#3-windows-and-instances)) |
| The "save first" refusals (`messages.save.before.*` and the others of the spec's table) | Inline in the dialog or page of the operation, else the alert dialog | [messages](../messages.md), Save failures |
| Writing paused (the library is being replaced) | An Informational `InfoBar` above the title: `messages.writingPaused.connecting` after 1 second, `messages.writingPaused.connectionFailed`, `messages.writingPaused.encrypting`, `messages.writingPaused.encryptionUnfinished`; no action | Show connection and Show progress are not offered: the Connect or Turn on encryption task page is modal over the only window and is the way to leave the state. The editor is read-only meanwhile |
| An archive opened while the library is replaced | The alert dialog with `messages.writingPaused.updating`, Close `common.ok` | |
| Template suggestion hidden, Change date's Save dimmed, Erase unavailable, rating request not shown, sync paused | As the spec's table | The Sync page says why with `messages.sync.pausedForSaveFailure` |

## What stays, what is blocked

All of the spec's table holds on Windows. The Windows mechanisms:

- **Leaving the entry** (another entry, journal or collection, New entry, Settings, a review or history page): the action first awaits the save; if it fails the page does not change, the entry keeps focus with its writing, and the alert dialog shows because the person asked for it.
- **Back in the stacked layout:** as the spec's iPhone row. The entry's page leaves at once, the entry stays selected with its writing in memory, and is deselected only after it saves; opening another entry tries to save first and stays on the list if that fails. The notice is on the entry's page, so a person who went back sees the failure again when the entry reopens, and the list row keeps its selection.
- **Locking** (Ctrl+L, Win+L, sleep, user switch, inactivity): saves for up to 2 seconds, locks, then saves again; the writing stays in memory and the notice returns after unlocking.
- **Closing:** the Keep open dialog above.
- **Sync, Erase, Change date, rating request:** as the spec.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The Error `InfoBar` is the first bar above the title, full width of the editor column. Text wraps, the action stays beside it when there is room | Mac: below the editor; iPad: first in the header |
| Small | The same bar above the title on the entry's page; at 200% text size the text stacks above the button | iPhone header |
| Dialogs | Default width; fill the window at small width | |

On Windows the notice sits above the writing like every other notice ([9.1](../platform.md#91-notices)), not below the editor as on the Mac, because a bar below a scrolling editor is easy to miss and the text column already has a fixed set of notices at the top.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `quit`, `close-window` | File ▸ Exit; the Close button | Alt+F4 | Always; may be refused by the Keep open dialog |
| `lock-my-journal` | File menu; Settings ▸ Privacy | Ctrl+L | App Lock is on; saves first |

The notice's Try again and the alert's Try again are the same action and are not commands of their own. Ctrl+S (a hidden accelerator, [7.2](../platform.md#72-additions)) also finishes the save and, when it fails, shows the normal notice (as for a failure while typing, D48; [7.2](../platform.md#72-additions)), not the alert. Esc in the alert chooses Close; Enter chooses Try again.

## Copy differences

Sentence case: `messages.save.notSaved` is "Not saved"; "Try again". Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `messages.save.mac.title` | Couldn’t save changes on this Mac. | Couldn’t save changes on this PC. | vocabulary (platform.md, 12.3) |
| `messages.save.before.changeDate` | … Close this sheet … | … Close this dialog … | vocabulary (platform.md, 12.3) |
| `messages.save.before.imageDescriptions` | … close this view … | … go back … | vocabulary ([messages](../messages.md)) |

The keys named `messages.save.mac.*` also serve Windows; their Mac-only name is a spec naming question, not a copy change.

## Accessibility

- The notice is reachable by keyboard: Tab from the title reaches Try again after the title row. It is not announced on each edit. When a failure begins, the notification is raised once; a repeat failure while the notice is already open raises nothing new until a person-started action fails, so Narrator is not spoken over while someone types.
- "Not saved" says so in words; the icon and the severity are never the only signal.
- The alert dialog is read when it opens and returns focus to where the person was (the editor, or the control that started the action).
- At 225% text size the notice reflows and Try again stays visible without scrolling; the editor scrolls beneath.
- Contrast themes: the Error bar uses the system's theme brushes and keeps its icon.

## Different by design

- **A failure while typing is not a dialog.** The spec shows the alert after every failed attempt, including attempts made by typing. A modal dialog that opens under the caret takes keyboard focus, so the next characters go to the dialog and the writing is not kept by the editor. On Windows the persistent bar and one Narrator notification tell the person, the dialog is kept for failures caused by a deliberate action, and the writing is kept in memory either way (D48).
- **The notice is above the writing**, not below it.
- **Shutdown block reason** replaces macOS's refusal to quit; Windows decides, the app only says why it should not.
- **No Show connection and Show progress buttons**: the dialog is the only way into those flows.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D48 (failed save while typing), A1 (save failure alert repeats).
