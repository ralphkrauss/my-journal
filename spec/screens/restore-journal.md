---
id: restore-journal
title: Restore Journal and Restore Entry (sheet)
features: [restore-journal, restore-entry]
sources:
  - apps/apple/JournalApp/Views/JournalLifecycleView.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - apps/apple/JournalApp/Model/EntryRestorationOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/JournalLifecycle.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/EntryRestoration.swift
  - docs/design/journal-lifecycle-ui.md
  - docs/design/journal-name-uniqueness.md
---

# Restore Journal and Restore Entry

## Purpose

One confirmation sheet that restores a deleted journal with the entries deleted with it, or restores an entry together with its deleted journal.

## Entry points

- **Restore Journal:** `library.recentlyDeleted.restoreJournal` in a deleted journal's detail.
- **Restore Entry:** `library.recoveryNotice.restoreWithJournal` in the notice of an entry whose journal is also in Recently Deleted.

## Content

Sheet title `library.restoreJournal.title` or `library.restoreEntry.title`. A scrolling column:

1. **Restore Entry only:** the entry's title (large), its date (year, month, day, secondary), then `library.restoreEntry.needsJournal`.
2. The journal's name (large; `common.untitledJournal`) and `library.recentlyDeleted.journalCount` (secondary).
3. Explanation: `library.restoreJournal.explanation` or `library.restoreEntry.explanation`.
4. When the journal has entries an earlier version deleted with it: `library.restoreJournal.legacy` (secondary).
5. When another journal in use has the same name: `common.restoredAsRenamed` (the restored journal gets a number).
6. Error text (selectable), when there is one.
7. Progress `common.pleaseWait` while working.
8. The confirming action: `library.restoreJournal.title` (Restore Journal) or `common.restore`, in the accent color, left-aligned. It has no Return shortcut.
9. Recovery actions when they apply: `common.tryAgain`, `library.restoreJournal.reviewEntry`, `common.trySyncingAgain`, `common.reviewChanges`, and an Export Archive… control for content saved by a newer version (screens/settings-backup).

Close button: `common.cancel`, or `common.done` once the action completed. Escape closes on the Mac.

## Actions

1. Opening the sheet saves the open entry and checks the journal (and entry). Until the check succeeds, the confirming action isn't shown.
2. **Restore:** the journal returns to its place in the order (or the end), with every entry deleted with it, including entries that sync later. Entries deleted separately stay in Recently Deleted. For Restore Entry the entry returns too. The sheet closes and the journal is shown (Restore Entry: with the entry open).

## States

- **Busy:** everything disabled, not dismissable by swiping.
- **Missing journal:** `library.restoreJournal.unavailableLocal`, or `common.journalNotArrived` with `common.trySyncingAgain` when the library syncs; and Export Archive….
- **Changes to review:** the store's message `messages.lifecycle.needsReview` with Review Changes. On return from the review, the check runs again. If the changes were resolved meanwhile, the review shows `messages.conflict.resolved` with `common.done`.
- **Already restored** elsewhere: the journal is shown and the sheet says `messages.lifecycle.alreadyRestored` (Done), or `messages.save.before.openRestoredJournal` when the open entry can't be saved. Restore Entry then offers Review Entry (`messages.restore.alreadyRestored`), which shows the entry where it is now.
- **Errors:** `messages.lifecycle.changedContinue` (then Try Again and a new explicit Restore), `messages.save.before.restoreJournal`, `messages.save.before.restoreEntry`, `messages.save.before.reviewEntry`, `messages.lifecycle.unsupportedJournal`, `messages.restore.changed`, `messages.restore.unavailable`, `messages.error.unsupportedFormat`, `messages.lifecycle.missingJournal`, `messages.lifecycle.alreadyDeleted`.
- **Stored but not shown:** `messages.refresh.journalRestored` or `library.restoreEntry.displayFailed`; Cancel becomes Done; restoring isn't offered again.
- **Locked:** the sheet closes and nothing is restored if it hadn't started.

## Rules

- The sheet is the only confirmation. A changed plan never restores automatically: the person presses Restore again.
- Restoring never resolves changes to review.

## Accessibility

- Errors are announced. Counts use singular and plural forms. Names wrap.

## Platform notes (Apple)

- **iPhone and iPad:** a sheet with an inline title and Cancel/Done at the top left.
- **Mac:** a sheet with the title at the top and Cancel/Done at the bottom left (360–460 points wide).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
