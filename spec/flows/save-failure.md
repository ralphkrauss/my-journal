---
id: save-failure
title: Save failure and paused writing
features: [save-failure-recovery, writing-paused-notice]
sources:
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/LockSaving.swift
  - apps/apple/JournalApp/Model/WindowSafety.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Views/EntryHeaderView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/TurnOnEncryptionView.swift
  - docs/design/save-failure-retry.md
  - docs/design/save-failure-retry-review.md
  - docs/design/owner-decisions-2026-09-25.md
---

# Save failure and paused writing

## Purpose

Writing is saved on this device after every edit, quietly. When a save fails, the writing stays on screen and in memory, the person is told once, and a Try Again stays next to the entry until it saves. Nothing that could lose the unsaved writing happens meanwhile. A separate, shorter state pauses writing while the library itself is being replaced.

## Entry points

- Any save of the open entry or template: after each edit, when leaving the entry, before an operation that needs it saved, before locking, and on the Mac before closing the window or quitting.
- The library is replaced or changed as a whole: connecting to a server, turning on encryption, importing an archive, committing an entry action (Move, Change Date, Restore).

## Steps

### Save failure

1. **A save fails.** Writing the open entry to this device's library fails (for example the disk is full or the database can't be written). Read-only entries are never saved, so they never fail.
2. **The person is told.**
   - Unlocked: the generic alert, titled `common.alertTitle`, with `common.saveFailed` ({title} is the entry's title, else its first line, else `library.entryList.untitledEntry`), and the buttons `common.tryAgain` and `common.ok`.
   - Locked (the save after locking failed): the lock screen shows `common.saveFailedLocked`, without the entry's title.
3. **The notice stays.** While saving has failed, the entry shows the save-failure notice: `messages.save.notSaved` in red, then `common.tryAgain`.
   - iPhone and iPad: first in the entry's header, above the title, recovery and conflict notices. Once the alert is dismissed, the header scrolls to it without animation.
   - Mac: below the editor.
4. **The person keeps writing, or tries again.**
   - Typing continues normally; the writing is kept in memory and every edit tries to save again. A failed attempt shows the alert again.
   - Try Again (in the notice or the alert) saves the retained writing now. In the notice, both actions are dimmed and `messages.save.saving` shows with a small spinner while it runs.
5. **Outcome.**
   - Saved: the notice disappears without an announcement, syncing resumes and the writing is sent after the usual pause.
   - Still failing: the alert shows again and the notice stays. Nothing retries by itself.

### While a save has failed

| Area | Behaviour | Copy |
| --- | --- | --- |
| Leaving the entry (another entry, journal or collection, New Entry) | First tries to save; if that fails, stays on the entry and the alert shows again | `common.saveFailed` |
| Back on iPhone (stacked navigation) | The entry's page leaves at once; the entry stays selected with its writing in memory and is deselected only once it saves. Opening another entry tries to save first and stays on the list if that fails | `common.saveFailed` |
| Sync | Doesn't run; Sync Now is dimmed; Settings ▸ Sync's footer explains | `messages.sync.pausedForSaveFailure` |
| Operations that need the entry saved | Refused with a message, nothing else happens | `messages.save.before.*`, `messages.connection.saveBeforeConnecting` |
| Change Date | Save is dimmed | |
| Erase Journals and Settings | Unavailable, as while busy | |
| Template suggestion in a new entry | Hidden | |
| Rating request | Not shown | |
| Locking (Lock My Journal, screen lock, sleep, inactivity) | Saves first for up to 2 seconds, locks, then saves again; the writing stays in memory and the notice returns after unlocking | `common.saveFailedLocked` |
| Mac: closing the journal window, or quitting | Tries to save first; on failure an app-modal alert, the window stays open and quitting is cancelled | `messages.save.mac.title`, `messages.save.mac.message`, `messages.save.mac.keepOpen` |

The "save first" messages, by operation:

| Operation | Key |
| --- | --- |
| Move Entry, Restore and Move… | `common.saveBeforeMoveEntry` |
| Review an entry's restoration | `messages.save.before.reviewEntry` |
| Restore an entry | `messages.save.before.restoreEntry` |
| Restore a template | `messages.save.before.restoreTemplate` |
| Export as Markdown | `messages.save.before.exportMarkdown` |
| Export Archive | `messages.save.before.exportArchive` |
| Import Archive | `messages.save.before.importArchive` |
| Connect to a Server | `messages.connection.saveBeforeConnecting` |
| Resolve a journal or deletion conflict | `messages.save.before.reviewChanges` |
| Resolve an entry conflict | `messages.save.before.resolveEntryConflict` |
| Export Archive from an unsupported journal conflict | `messages.save.before.exportArchiveForConflict` |
| Delete Journal | `messages.save.before.deleteJournal` |
| Restore Journal | `messages.save.before.restoreJournal` |
| Restore Journal that another device already restored | `messages.save.before.openRestoredJournal` |
| Merge Into… | `messages.save.before.mergeJournal` |
| Create a journal from a sheet | `common.saveBeforeCreateJournal` |
| Version History ▸ restore a version | `messages.save.before.restoreVersion` |
| Journal Version History ▸ restore settings | `messages.save.before.restoreJournalSettings` |
| Change Date (save not settled) | `messages.save.before.changeDate` |
| Image Descriptions (save not settled) | `messages.save.before.imageDescriptions` |

### Writing paused while the library is replaced

While the library is being replaced or changed as a whole, the editor is read-only and sync waits. Nothing typed is lost: the open entry is saved before the replacement starts, or the replacement refuses to start.

| Situation | iPhone and iPad | Mac (journal window, above the editor) |
| --- | --- | --- |
| Connecting to a server | Connect to a Server covers the app as a sheet | After 1 second: `messages.writingPaused.connecting` with `messages.writingPaused.showConnection` |
| A failed connection's copy waits for Try Again or Cancel | The sheet stays | `messages.writingPaused.connectionFailed` with `messages.writingPaused.showConnection` |
| Turning on encryption | Turn On Encryption covers the app | `messages.writingPaused.encrypting` with `messages.writingPaused.showProgress` |
| Encryption reached the server but this device couldn't finish | Turn On Encryption reopens over the app with `messages.encryption.unfinished` | `messages.writingPaused.encryptionUnfinished` with `messages.writingPaused.showProgress` |
| Importing an archive, committing an entry action | Brief; no notice | Brief; no notice |
| An archive is opened from Finder or Files meanwhile | Generic alert `messages.writingPaused.updating` | Same |

## Rules

- Every edit is saved locally at once; sync is separate and coalesced.
- The unsaved writing is never discarded by the app: not by navigation, locking, closing the Mac window, quitting the Mac app, or a sync.
- Try Again never runs on its own and never repeats any other action.
- The notice's Try Again belongs to the entry and the library it was started for: it stops when the app locks, the library is replaced, or the notice disappears, and it never saves into a different library or entry.
- An operation already committed when a later step fails is never described as failed (see `messages.refresh.*`).

## Accessibility

- The alert is the announcement; it is a standard alert whose cancel button is `common.ok`. The notice doesn't take focus and isn't announced on each edit.
- "Not Saved" is red and says so in words; colour is never the only signal.
- Notice texts wrap at every text size; the iPhone header keeps the status and Try Again visible above the keyboard at the largest text size.
- Try Again and its dimmed state are reachable with VoiceOver and Full Keyboard Access. `messages.save.saving` is the progress view's label.
- On the Mac, the writing-paused notices stack their text above the button at accessibility text sizes; they fade in and out, without animation under Reduce Motion.

## Platform notes (Apple)

- The notice's place differs: top of the entry's header on iPhone and iPad (the header scrolls with the text, and the bottom of the screen is the keyboard's), below the editor on the Mac.
- Only the Mac guards closing the window and quitting. On iPhone and iPad the system can end the app at any time; a draft that couldn't be saved is then lost (see [open-questions.md](../open-questions.md), D17).
- Only the Mac shows writing-paused notices: on iPhone and iPad the connection and encryption sheets cover the app, so there is nothing to explain behind them.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
