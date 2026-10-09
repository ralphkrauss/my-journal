---
id: save-entry
title: Saving an entry
features: [autosave]
sources:
  - apps/apple/JournalApp/Model/AppModel.swift (updateDraft, flush, finishPendingSave)
  - apps/apple/JournalApp/Model/JournalEditing.swift (writeDraft)
  - apps/apple/JournalApp/Model/JournalNavigation.swift (select, switchJournal, canEdit)
  - apps/apple/JournalApp/Model/LockSaving.swift
  - apps/apple/JournalApp/Model/WindowSafety.swift
  - apps/apple/JournalApp/Views/RootView.swift (error alert)
  - apps/apple/JournalTests/DraftSaveTests.swift
  - apps/apple/JournalTests/StaleDraftTests.swift
  - apps/apple/JournalTests/LockSavingTests.swift
  - docs/design/mac-inactivity-lock-2026-10-03.md
  - docs/design/sync-now-and-done.md
---

# Saving an entry

## Purpose

Writing is saved on this device as it happens, quietly, and is never lost: not when leaving the entry, locking, quitting, or when a save fails. This file covers saving that works and the points where a save is finished first; what happens when a save fails (the alert, the notice, Try Again, what is blocked meanwhile) is in [save-failure.md](save-failure.md).

## Normal saving

1. Every change to the title or body (typing, dictation, formatting, pasting, a checkbox, an image) updates the open entry and starts a save to this device at once. There is no delay and no Save command. While a save runs, further changes are collected and saved right after it, until nothing is left.
2. Nothing is shown while saving, or after: no “Saved” message, no spinner.
3. Once saved, sync is asked to send the change when writing pauses (specified with sync).
4. Only the editor's changes count as edits. Opening an entry, scrolling, selecting or switching views writes nothing.
5. A read-only entry (newer format, in Recently Deleted, journal unavailable) is never saved, and locking doesn't save it (`StaleDraftTests.testLockingSavesOnlyUnsavedWritingAndLeavesReadOnlyEntriesAlone`).
6. A save never writes an older copy over a newer one stored meanwhile (from another device); both versions are kept instead: this device’s stays the entry and the stored one becomes a separate entry ([flows/resolve-conflict.md](resolve-conflict.md)).

## Before anything leaves the entry

Every action that leaves or acts on the open entry first finishes its save: opening another entry or journal, New Entry, Done (phone, tablet), the Entry Actions that open a sheet (Change Date, Move Entry, Save as Template, Image Descriptions, Version History), restoring a version, deleting the open entry, locking and quitting. Pinning doesn't wait for the save; it doesn't change the entry's content. If the save fails, the action doesn't happen and the entry stays open with the writing intact; the operations that need a saved entry say so, with `messages.save.before.goBack` in a sheet or pane and `messages.save.before.tryAgain` in the generic alert ([save-failure.md](save-failure.md)).

## When saving fails

The action doesn't happen, the entry stays open with its writing, and the failure is shown and retried as described in [save-failure.md](save-failure.md).

## Locking

- Before any lock the person or the system starts (Lock My Journal, the screen locking, sleep, inactivity), the open entry is saved, then typed content in open sheets (Image Descriptions), waiting at most 2 seconds; saving continues after locking. A hanging save can't keep the journals unlocked (`LockSavingTests.testHangingSaveDoesntHoldTheLock`).
- If the save fails while locking, the draft is kept for after unlocking and the lock screen explains ([save-failure.md](save-failure.md)).
- Image descriptions that couldn't be saved before locking are kept in memory and saved after unlocking (`LockSavingTests.testDescriptionsKeptByALockAreSavedAfterUnlocking`).

## Closing the window and quitting (computer)

- Quitting saves the open entry first and then gives sync up to 3 seconds to send it.
- If the entry can't be saved, quitting (or closing the journal window) is cancelled and the window stays open with the writing ([save-failure.md](save-failure.md)).

## Rules

- A cancelled or locked retry keeps the draft, and the lock's own save can still save it (`DraftSaveTests.testCancelledOrLockedRetryKeepsDraftWhileLockCleanupCanSave`).
- An entry left without typing is never written again, even if another device changed it meanwhile (`StaleDraftTests.testAnEmptyNewEntryWrittenOnAnotherDeviceIsNotOverwrittenWhenLeft`).
- New entries are kept once created, even when left empty (`new-entry-template-suggestion.md`, owner decision 2026-09-30).

## Accessibility

- Nothing is announced or shown for a normal save. Accessibility of the save-failure alert and notice is in [save-failure.md](save-failure.md).

## Platform notes (Apple)

- Quitting and closing the window finish the save first on the Mac, and wait up to 3 seconds for sync; on iPhone and iPad the system can end the app at any time.

## Open questions

- None.
