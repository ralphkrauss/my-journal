---
id: save-entry
title: Saving an entry (Windows)
spec: flows/save-entry.md
features: [autosave]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/applifecycle/applifecycle-single-instance
---

# Saving an entry (Windows)

Writing is saved on this device as it happens, quietly, and is never lost. Steps and rules are the spec's [save-entry](../../../flows/save-entry.md); a save that fails is [save-failure](../../../flows/save-failure.md). Nothing here is shown on screen: this file says when the Windows app saves and what finishes a save first.

## Controls

None while a save works: no spinner, no "Saved" message ([11](../platform.md#11-progress-and-announcements)). The only controls are the failure surfaces ([entry-editor](../screens/entry-editor.md), notices) and the Keep open dialog of [library-window](../screens/library-window.md).

## What triggers and finishes a save

| Moment | Windows mechanism |
| --- | --- |
| Every change to the title or body (typing, dictation, voice typing, formatting, pasting, a checkbox, an image) | The editing control's text-changed events feed the document model, which starts a save to this device at once; changes during a running save are collected and saved right after it. There is no delay and no Save command. Opening an entry, scrolling, selecting or switching views writes nothing; only the editor's changes count |
| While an input method composes | Changes are saved as they arrive, as on the Mac; only the app's own conversions and changes arriving from sync wait for the composition to end |
| Ctrl+S | Finishes the open entry's save now, silently ([7.2](../platform.md#72-additions)); a failed save shows the normal notice. It adds no menu item and shows nothing |
| Leaving the entry: opening another entry or journal, New entry, the entry actions that open a dialog or page (Change date, Move entry, Save as template, Image descriptions, Version history), restoring a version, reviewing a conflict, deleting the open entry, Settings | The action first awaits the save. If the save fails, the action does not happen and the entry stays open with the writing. Pinning does not wait |
| Locking (Lock My Journal, Ctrl+L, Win+L, sleep, user switch, inactivity) | The open entry is saved, then typed content in open pages (Image descriptions), waiting at most 2 seconds; saving continues after locking and a hanging save cannot keep the journals unlocked. A failed save keeps the draft for after unlocking and the lock page explains. Read-only entries are never saved |
| Closing the window, Alt+F4, File ▸ Exit | `AppWindow.Closing` is cancelled until the save finishes, then sync is given up to 3 seconds to send it, then the window closes. If the entry cannot be saved the window stays open and the Keep open dialog shows ([library-window](../screens/library-window.md)) |
| Sign-out, restart or shutdown | The app handles the end-of-session message, holds shutdown back briefly with a shutdown block reason while the save finishes and sync gets up to 3 seconds, then lets it go ([3](../platform.md#3-windows-and-instances), [30](../platform.md#30-sync-lifecycle-and-power)). Windows may still end the process: the save is already on disk after every change |
| The PC sleeps or the process is killed | Nothing is held in memory that was not already written, except writing that failed to save, which the notice makes visible |

Other rules, as the spec: a save never writes an older copy over a newer one stored meanwhile (it becomes a conflict to review); an entry left without typing is never written again; new entries are kept once created, even empty; a cancelled or locked retry keeps the draft.

## Layout at each window width

Not applicable. Saving has no layout; the notices and dialogs it can raise are mapped in [entry-editor](../screens/entry-editor.md) and [library-window](../screens/library-window.md).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `quit`, `close-window` | File ▸ Exit; the Close button | Alt+F4 | Always; waits for the save and may be refused by the Keep open dialog |
| `lock-my-journal` | File menu; Settings ▸ Privacy | Ctrl+L | App Lock is on; saves first |
| `open-settings` | The built-in Settings item; File menu | Ctrl+, | Saves the open entry first |

Ctrl+S is the Windows addition of [7.2](../platform.md#72-additions), not a command id.

## Copy differences

`messages.save.mac.title` becomes "Couldn’t save changes on this PC." (platform.md, 12.3). The Keep open button text `messages.save.mac.keepOpen` stays. `messages.entry.dateChanged`, which says "Close this sheet", becomes "Close this dialog". No other differences.

## Accessibility

- A normal save announces nothing. The Keep open dialog is read by Narrator when it opens (title, then content). The save-failure notice and its Try again button are in [entry-editor](../screens/entry-editor.md).
- Ctrl+S is exposed nowhere because it has no UI; Narrator users lose nothing, since saving is automatic.

## Different by design

- **Close, not Quit.** There is one window, and closing it ends the app, so the same save-first rule serves the Close button, Alt+F4 and Exit ([3](../platform.md#3-windows-and-instances)).
- **Session end.** Windows can end the app at sign-out; a shutdown block reason holds it back for the save, where macOS asks the app to quit.
- **A hidden Ctrl+S** for people who press it by habit.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): A36 (pinning and saving).
