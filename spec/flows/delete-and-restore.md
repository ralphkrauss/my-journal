---
id: delete-and-restore
title: Delete, restore and delete permanently
features: [delete-entry, undo-delete, delete-journal, restore-entry, restore-and-move, restore-journal, delete-permanently, delete-all-deleted, recently-deleted]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/JournalDeletionPrompt.swift
  - apps/apple/JournalApp/Views/PermanentDeletionView.swift
  - apps/apple/JournalApp/Views/DeleteAllPrompt.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/JournalApp/Views/DeletedJournalView.swift
  - apps/apple/JournalApp/Model/EntryDeletionOperations.swift
  - apps/apple/JournalApp/Model/EntryRestorationOperations.swift
  - apps/apple/JournalApp/Model/PermanentDeletionOperations.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/recently-deleted-2026-09-30.md
  - docs/design/ios-delete-all-and-settings-2026-10-03.md
  - docs/design/journal-lifecycle-ui.md
  - docs/design/permanent-deletion.md
  - protocol/journal-lifecycle.md
  - protocol/permanent-deletion.md
---

# Delete, restore and delete permanently

## Purpose

One path for everything removed: entries, templates and journals go to Recently Deleted, can be restored from there, and leave only when deleted permanently. There is no Archive.

## Steps

### Delete an entry or template

1. Delete Entry / Delete Template (context menu, Entry Actions), the trailing swipe, or Delete / ⌘⌫ in the focused Mac list.
2. No confirmation. The row leaves at once (one movement; none with Reduce Motion) and the item moves to Recently Deleted. Lists and counts are read again once the movement has finished.
3. If the item was open: Mac and iPad open the next entry below (above at the end); iPhone goes back to the list.
4. Undo: Edit ▸ Undo Delete Entry / Undo Delete Template (⌘Z) restores it; Redo deletes it again.
5. If storing fails, the row comes back with the error.

### Delete a journal

1. Delete Journal… in the journal's actions.
2. The deletion is checked, then the alert `library.deleteJournal.title` with the count of its entries.
3. Delete: the journal's row leaves at once; the journal and its entries (marked as deleted with it) move to Recently Deleted. Entries from other devices join it there when they sync. Another journal is shown.
4. No Undo command.

### Restore

- **Entry whose journal is in use:** Restore (leading swipe, menu, or the notice). It returns to its journal, which is shown with the entry open. Pins come back.
- **Template:** Restore. It returns to Templates, which is shown with the template open.
- **Entry whose journal is also deleted:** the notice's Restore… opens Restore Entry ([screens/restore-journal](../screens/restore-journal.md)), which restores the journal too.
- **Entry into another journal:** Restore and Move… ([screens/move-entry](../screens/move-entry.md)). Only that entry moves.
- **Journal:** Restore Journal… in its detail. Entries deleted with it return (also those that sync later); entries deleted separately stay. If its name is taken it returns with a number. It returns to its former place in the order, or the end.

### Delete permanently

- One item: Delete Permanently… (menu, swipe, Delete key on the Mac, or a deleted journal's detail) → the checked alert → Delete. A journal takes its entries with it.
- Everything: Delete All ([screens/recently-deleted](../screens/recently-deleted.md#delete-all)).
- The deletion syncs to other devices. Copies may remain in archives, backups and the server's history.

## States

- **Locked:** nothing is deleted after locking unless it was already confirmed and stored; swiped rows come back.
- **Changes to review, newer versions:** permanent deletion and journal deletion refuse with the messages listed in the screens; nothing changes.
- **Removed by a sync while open:** the open item closes unless it has unsaved writing.

## Rules

- Deleting never asks for entries and templates; it always asks for journals and for permanent deletion.
- Only Recently Deleted's own actions delete permanently.
- Nothing is ever deleted automatically.

## Accessibility

- Destructive buttons are marked destructive. Alerts are standard alerts.
- After Cancel on a swiped row, VoiceOver focus returns to it.

## Platform notes (Apple)

- See [screens/recently-deleted](../screens/recently-deleted.md) for the Mac bar and iOS bar button differences.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
