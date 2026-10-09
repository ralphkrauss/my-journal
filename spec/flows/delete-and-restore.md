---
id: delete-and-restore
title: Delete, restore and delete permanently
features: [delete-entry, undo-delete, delete-journal, restore-entry, restore-journal, delete-permanently, delete-all-deleted, recently-deleted]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/JournalDeletionPrompt.swift
  - apps/apple/JournalApp/Views/PermanentDeletionView.swift
  - apps/apple/JournalApp/Views/DeleteAllPrompt.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/JournalApp/Views/DeletedJournalView.swift
  - apps/apple/JournalApp/Model/EntryDeletionOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreRestoreEntry.swift
  - apps/apple/JournalApp/Model/PermanentDeletionOperations.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/recently-deleted-2026-09-30.md
  - docs/design/ios-delete-all-and-settings-2026-10-03.md
  - docs/design/journal-lifecycle-ui.md
  - docs/design/permanent-deletion.md
  - docs/design/1-1-library-simplifications.md
  - docs/design/1-1-conflicts-and-reconnect.md
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

Restore is one verb. It acts at once on entries, templates and journals, with no confirmation, no sheet and no destination picker. The label says where an entry goes: **Restore** (`common.restore`) when it returns to its own journal, **Restore to “{name}”** (`library.recentlyDeleted.restoreTo`) when it can't, and **Restore Journal** (`library.recentlyDeleted.restoreJournal`) on a deleted journal's page.

- **Template:** Restore. It returns to Templates, which is shown with the template open.
- **Journal:** Restore Journal, on the deleted journal's page. Entries deleted with it return (also those that sync later); entries deleted separately stay in Recently Deleted and restore one by one. If its name is taken it returns with a number (`common.restoredAsRenamed` says so on the page before the button is pressed). It returns to its former place in the order, or the end, and is shown.
- **Entry:** Restore, by the rule below. Pin, date, text and images are unchanged, and the pin comes back with the entry; the journal order is not affected.

**Where a restored entry goes.** The same rule on every device:

| Situation of the entry | Restore puts it in |
| --- | --- |
| Its journal is in use | That journal. Label: Restore |
| Its journal is in Recently Deleted | The **Default Journal** (Settings ▸ General, else the oldest journal in use). Label: Restore to “{Default Journal}”. The deleted journal stays deleted and keeps its other entries; restoring the journal is a separate action |
| Deleted with its journal by an earlier version (legacy marker), journal in use | That journal. Label: Restore |
| The entry itself is deleted (its own deletion, a legacy marker, or saved next to a permanent deletion by [the conflict rule](resolve-conflict.md)) and its journal is **missing or was deleted permanently** (it is listed under Unavailable Journals) | The Default Journal. Label: Restore to “{Default Journal}”, in the Unavailable Journals notice and the row's context menu and Entry Actions, never on a swipe. On a syncing library the notice also keeps Try Syncing Again, because a journal that merely hasn't arrived may still come. Move Entry does not apply: it refuses deleted entries |
| Its journal is saved by a newer version, or the journal or the entry has a held conflict | Not offered; the notice says `common.updateToRestoreEntry` |
| The entry itself was saved by a newer version | Not offered |
| No journal is in use at all | Not offered; the notice says `library.recoveryNotice.createJournalFirst` |

An entry that is not deleted but whose journal is missing stays in Unavailable Journals and has nothing to restore.

**Where the control appears.** The leading full swipe (iPhone, iPad) is offered only when the entry's own journal is in use, so a long swipe never files an entry somewhere unexpected. When the destination differs, Restore to “{name}” is in the row's context menu, Entry Actions and the notice button (all devices); the notice adds `library.recoveryNotice.journalDeleted` for a deleted journal.

**The store decides when Restore is chosen.** The label is drawn earlier and can be out of date, so the destination is decided again inside one write transaction (`restoreEntry(_:fallback:)` in the store contract; the app passes as the fallback the journal the control named, and none when the control named the entry's own journal). The store requires the entry itself to be editable and to have no held conflict, uses the entry's own journal when it is in use, supported and without a held conflict (an absent journal, a permanent-deletion marker and a deleted journal all mean "not usable"), else the fallback, which must meet the same conditions. It clears only that entry's own deletion and legacy marker, writes nothing else, and returns the saved entry and the journal it landed in. If neither journal qualifies it restores nothing and reports `messages.restore.destinationGone`: that includes a control that named the entry's own journal (Restore, or the swipe) when that journal is no longer in use at the tap, because the entry is never filed in a journal the control did not name. An entry that is not deleted is returned as it is, archived or not. The app opens the returned journal with the entry (iPhone: the stack becomes [journal, entry]) and, when the entry did not return to its own journal, announces `messages.announce.restoredIn`. If the control named the Default Journal and the entry's own journal came back between drawing it and choosing it, the entry simply goes home and nothing is announced.

**Agent access.** A restored entry follows the grants of the journal it lands in, exactly as a moved entry does. An entry in Recently Deleted is never readable by an agent, so restoring in place changes nothing about who can read it; restoring into the Default Journal makes it readable by a grant on that journal and no longer by one on the old journal. That is why the cross-journal case is named in the control and kept off the swipe.

Errors (the general error alert): `messages.save.before.tryAgain` when the open entry couldn't be saved first; `messages.restore.destinationGone`; for a journal `messages.lifecycle.alreadyRestored`, `messages.lifecycle.missingJournal`, `messages.lifecycle.unsupportedJournal`; stored but not shown `messages.refresh.journalRestored`, `messages.refresh.templateRestored`, `common.entryMovedNotDisplayed`.

### Delete permanently

- One item: Delete Permanently… (menu, swipe, Delete key on the Mac, or a deleted journal's detail) → the checked alert → Delete. A journal takes its entries with it.
- Everything: Delete All ([screens/recently-deleted](../screens/recently-deleted.md#delete-all)).
- The deletion syncs to other devices. Copies may remain in archives, backups and the server's history.

## States

- **Locked:** nothing is deleted after locking unless it was already confirmed and stored; swiped rows come back.
- **Changes to review:** a journal is never refused for changes made on two devices: the device settles them ([flows/resolve-conflict](resolve-conflict.md)). A journal with a change from another device that a newer version wrote, and that stays held, behaves like a journal saved by a newer version and shows the same update messages: Delete Journal `messages.generic.journalDeleteNeedsUpdate`, Delete Permanently `messages.generic.deleteNeedsUpdate`, Restore Journal `messages.unavailable.restoreJournalNeedsUpdate` on its page, and `messages.lifecycle.unsupportedJournal` (“Update My Journal to make changes to this journal.”) wherever a journal operation reports it. An entry or template that still has changes to review isn't deleted permanently (`messages.generic.deleteChanged`, in the general alert). There is no alert with a Review Changes button. A journal whose entries changed while the Delete Journal alert was open shows `messages.lifecycle.changed` in the generic alert.
- **Deleted permanently on one device, changed on another:** the deletion stays final. The changed entry or template is saved separately in Recently Deleted (Unavailable Journals when its journal is gone), where Restore brings it back; a journal stays deleted. Settings ▸ Sync ▸ Changed on Two Devices says so.
- **Newer versions:** permanent deletion and journal deletion refuse with the messages listed in the screens; nothing changes.
- **Removed by a sync while open:** the open item closes unless it has unsaved writing.

## Rules

- Deleting never asks for entries and templates; it always asks for journals and for permanent deletion.
- Only Recently Deleted's own actions delete permanently.
- Restore never asks and never moves an entry across journals without saying where, in the label.
- Nothing is ever deleted automatically.

## Accessibility

- Destructive buttons are marked destructive. Alerts are standard alerts.
- After Cancel on a swiped row, VoiceOver focus returns to it.

## Platform notes (Apple)

- See [screens/recently-deleted](../screens/recently-deleted.md) for the Mac bar and iOS bar button differences.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
