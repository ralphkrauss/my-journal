---
id: recently-deleted
title: Recently Deleted (list, deleted journal, recovery notice, Delete All)
features: [recently-deleted, restore-entry, restore-journal, delete-permanently, delete-all-deleted, unavailable-journals]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/DeletedJournalView.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/JournalApp/Views/EntryHeaderView.swift
  - apps/apple/JournalApp/Views/PermanentDeletionView.swift
  - apps/apple/JournalApp/Views/DeleteAllPrompt.swift
  - apps/apple/JournalApp/Views/Mac/RecentlyDeletedHeader.swift
  - apps/apple/JournalApp/Model/PermanentDeletionOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreRestoreEntry.swift
  - apps/apple/JournalApp/Model/EntryDeletionOperations.swift
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/recently-deleted-2026-09-30.md
  - docs/design/ios-delete-all-and-settings-2026-10-03.md
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/journal-lifecycle-ui.md
  - docs/design/permanent-deletion.md
  - docs/design/1-1-library-simplifications.md
  - docs/design/1-1-conflicts-and-reconnect.md
---

# Recently Deleted

## Purpose

Holds deleted journals, templates and entries until the person restores them or deletes them permanently. Nothing is removed automatically. Restore is one verb that acts at once; when an entry cannot return to its own journal the label says where it goes.

## Entry points

- The **Recently Deleted** row in [screens/journals](journals.md).

## Content

Title `common.recentlyDeleted`; Mac subtitle `common.itemCount` / `library.window.subtitle.noItems`.

**Mac only, a bar above the list** (the rows scroll under it): `library.recentlyDeleted.footer` in small secondary text, and a small button `library.recentlyDeleted.deleteAll` (Mac variant “Delete All…”), tooltip `library.recentlyDeleted.deleteAll.help`, or `library.recentlyDeleted.deleteAll.helpSearching` while a search is active.

**Sections, in order, each only when it has rows:**

1. **Journals** (`common.journals`): deleted journals by name. Row: the name (`common.untitledJournal` when blank) and under it `library.recentlyDeleted.journalCount` (entries that return when it's restored). Accessibility value `library.entryList.journalValue`.
2. **Templates** (`library.journals.templates`): deleted templates, newest first, entry-style rows with accessibility value `library.entryList.templateValue`.
3. **Entries**: month sections as in [screens/entry-list](entry-list.md); the first month's header is preceded by `library.recentlyDeleted.section.entries`. Includes entries deleted on their own, entries deleted with their journal and entries the app saved next to a permanent deletion ([flows/resolve-conflict](../flows/resolve-conflict.md)).

**iPhone and iPad:** the footer `library.recentlyDeleted.footer` under the last section; the bar button `library.recentlyDeleted.deleteAll` at the top right, shown only when the list has something and no search is active.

## Actions

### Row actions

| Action | Where | Shown when | Result |
| --- | --- | --- | --- |
| Restore (`restore`) | Leading swipe (accent; only when the entry's own journal is in use, or a template), context menu and Entry Actions (uturn arrow), labelled `common.restore`; when the entry can't return to its own journal: `library.recentlyDeleted.restoreTo` (context menu, Entry Actions and the notice only, never a swipe) | the item is editable, has no held conflict and none that still waits, and has a destination (below) | Restores at once, without confirmation and without a sheet ([flows/delete-and-restore](../flows/delete-and-restore.md)) |
| Delete Permanently… (`delete-permanently`) | Context menu and Entry Actions (`library.entryActions.deletePermanently`, trash, destructive, after a separator) | always for entries and templates here | Delete Permanently alert, below |
| Delete (trailing swipe, destructive) | `common.delete` | always | The row leaves at once; then the Delete Permanently alert. Cancel brings the row back |
| Delete or ⌘⌫ (Mac, list focused) | | an entry or template is selected | Delete Permanently alert |
| Image Descriptions…, Version History… | context menu and Entry Actions | as in entry-list | Read-only views |

Pin, Change Date…, Move Entry…, Save as Template… and Delete Entry aren't offered here. To file a restored entry elsewhere, restore it, then use Move Entry….

### Opening an item

- **Entry or template:** opens read-only in the editor with the [recovery notice](#recovery-notice) above the title.
- **Deleted journal:** the editor area shows the journal's page, in this order:
  1. Title: the journal's name (`common.untitledJournal`).
  2. Secondary: `library.recentlyDeleted.journalCount`.
  3. `common.restoredAsRenamed`, only when its name is taken (it returns with a number); it stays directly above the button because it changes the result.
  4. The button `library.recentlyDeleted.restoreJournal` (`restore-journal`), which acts at once, without a sheet; or, for a journal saved by a newer version or one whose change from another device is held, `messages.unavailable.restoreJournalNeedsUpdate` and an Export Archive… control (Settings ▸ Backup, screens/settings-backup).
  5. Secondary text: `library.restoreJournal.explanation`, then `library.restoreJournal.legacy` when entries from an earlier version were deleted with it and must be restored one by one.
  6. `library.entryActions.deletePermanently` (destructive), last.
  All disabled while the library is being replaced. The primary action stays near the top at the largest text sizes, and a screen reader reaches it before the explanation.

**Restore Journal** returns the journal to its place in the order, or the end, with every entry deleted with it, including entries that sync later; entries deleted separately stay in Recently Deleted and restore one by one. On success the journal is shown. Failures, in the general error alert: `messages.save.before.tryAgain` (the open entry couldn't be saved first), `messages.lifecycle.alreadyRestored` (restored elsewhere meanwhile; the journal is shown), `messages.lifecycle.missingJournal`, `messages.lifecycle.unsupportedJournal`, `messages.refresh.journalRestored`.

**Restore (entry)** is decided in one store transaction when it is chosen ([flows/delete-and-restore](../flows/delete-and-restore.md), Restore): the label drawn for it can be out of date, the result never is. Failures, in the general error alert: `messages.save.before.tryAgain`, `messages.restore.destinationGone` (the journal the control named can't be used any more; nothing was restored), `common.entryMovedNotDisplayed`. After a restore that put the entry in a journal other than its own, VoiceOver is told `messages.announce.restoredIn`.

### Delete Permanently (`delete-permanently`)

1. The open entry is saved and the item checked first (unsaved changes, a conflict that still waits or is held, newer format).
2. Alert, title `library.deletePermanently.title` with the item's name (`library.entryList.untitledEntryInAlert`, `library.entryList.untitledTemplate` or `common.untitledJournal` when blank); for a journal with entries `library.deletePermanently.titleWithEntries`. Message: for a journal with entries `library.deletePermanently.journalEntries`, then `library.deletePermanently.retention`. Buttons `common.delete` (destructive) and `common.cancel`.
3. **Delete:** the row (and for a journal its entries' rows) leaves at once with the list's animation; the item is deleted from this device and the deletion syncs. An open item closes; on iPhone its page goes back at once. No message.
4. **Cancel:** nothing changes; a row the swipe removed comes back and VoiceOver focus returns to it.
5. An item saved by a newer version, or held, isn't deleted (`messages.generic.deleteNeedsUpdate`); an entry, template or journal whose conflict still waits to be combined isn't deleted either and shows `messages.lifecycle.combining`. There is no special alert. Failures (general error alert; a removed row comes back): `messages.generic.deleteChanged`, `messages.generic.deleteNeedsUpdate`, `messages.lifecycle.combining`, `messages.save.before.tryAgain`, `messages.refresh.itemDeleted`. An item already gone is ignored quietly.

### Delete All

Feature `delete-all-deleted`; command `delete-all-recently-deleted`.

Available from the bar button (iPhone, iPad), the bar's Delete All… (Mac) and File ▸ Delete All in Recently Deleted… (⇧⌘⌫, Mac). Enabled only while Recently Deleted is shown, has rows, has no search, no Delete All is already running, and the library is open, unlocked and not being replaced.

1. The open entry is saved, then every journal, template and entry listed is checked (journals first). The button is disabled while checking.
2. If something can be deleted, a standard alert:
   - exactly one item (or one journal with its entries): the Delete Permanently alert above;
   - one kind: `library.deleteAll.title.entries`, `library.deleteAll.title.templates` or `library.deleteAll.title.journals`;
   - several kinds: `library.deleteAll.title.items`, message starting `library.deleteAll.includes` with the non-zero counts (`common.entryCount`, `common.journalCount`, `common.templateCount`, joined in the system list format);
   - if some items stay, one sentence: `library.deleteAll.held.newerVersion` or, when the reasons are mixed or an item has a conflict that still waits to be combined, `library.deleteAll.held.other`;
   - always last `library.deletePermanently.retention`;
   - buttons `common.delete` (destructive) and `common.cancel`.
   Entries are counted including a deleted journal's entries, since the list shows them as rows.
3. If nothing can be deleted, no confirmation: a notice `library.deleteAll.nothing.title` with `library.deleteAll.nothing.newerVersion` or `library.deleteAll.nothing.other`, and `common.ok`.
4. **Delete:** every row being deleted leaves at once; rows that stay remain. Items are deleted one by one (journals first, each with its entries), each checked again. Entries deleted with their journal aren't deleted twice. With nothing left, `library.entryList.empty.noDeletedItems` shows and the button disappears.
5. Items that changed between the alert and deleting stay, their rows come back, and a notice says `library.deleteAll.changed.title` / `library.deleteAll.changed.message` (`common.ok`).
6. Stored but not shown: `messages.refresh.itemsDeleted`.

Only what was checked is deleted: items that arrive meanwhile (sync, Undo) stay. A journal that can't be deleted keeps all its entries.

### Recovery notice

Shown above the title of a read-only entry or template opened from Recently Deleted or Unavailable Journals, on a tinted background (at accessibility sizes it takes at most half the height and scrolls).

| Situation | Text | Actions |
| --- | --- | --- |
| Template in Recently Deleted | `library.recoveryNotice.template` | `common.restore` (if editable) |
| Entry in Recently Deleted, its journal in use | `library.recoveryNotice.entry` | `common.restore` |
| Entry in Recently Deleted, its journal in Recently Deleted | `library.recoveryNotice.entry`, then `library.recoveryNotice.journalDeleted` | `library.recentlyDeleted.restoreTo` (the Default Journal) |
| Entry deleted with its journal by an earlier version, journal in use | `library.recoveryNotice.legacy` | `common.restore` |
| Unavailable: the entry's own journal is missing or was deleted permanently, and the entry itself is deleted (its own deletion, a legacy marker, or saved next to a permanent deletion) | `common.journalNotArrived` (library syncs) or `common.journalUnavailableEntrySaved` (no sync) | `library.recentlyDeleted.restoreTo`; with a server also `common.trySyncingAgain` (syncs now, retrying refused items) |
| Unavailable: journal saved by a newer version, or a change to it held | `common.updateToRestoreEntry` | — |
| Any entry, and no journal in use at all | `library.recoveryNotice.createJournalFirst` | — |

Actions are offered only when the entry is editable (not saved by a newer version) and has no held conflict. `{name}` in `library.recentlyDeleted.restoreTo` is the Default Journal (Settings ▸ General, else the oldest journal in use; `common.untitledJournal` when blank). Restoring there makes the entry readable by an agent granted that journal and no longer by a grant on the old one; this is why the label names the journal, and why it is never on a swipe.

## States

- **Empty:** `library.entryList.empty.noDeletedItems`; no Delete All. A deleted journal or template counts as content.
- **Search:** prompt `library.search.deleted`. Journals are filtered by name as it's typed; templates by name or text; entries by title or text. No results: `library.entryList.empty.noResults` with `library.entryList.empty.clearSearch`. Delete All is hidden (iPhone, iPad) or disabled (Mac) while searching.
- **Locked:** prompts close; a swiped row returns; nothing is deleted. Delete All stopped by locking keeps what was already deleted, and the rest comes back, without a message.

## Rules

- Items stay until deleted permanently. There is no automatic removal.
- Deleting permanently can't be undone here; copies may remain in archives, backups and the server's history (the alert says so).
- A deleted pinned entry is listed under its month, not Pinned, and is pinned again when restored, whichever journal it goes to; the journal order doesn't change.
- **Where a restored entry goes**: its own journal when that is in use; otherwise the Default Journal (named in the label); the deleted journal stays deleted and keeps its other entries. See [flows/delete-and-restore](../flows/delete-and-restore.md).
- New Entry from here creates an entry in the Default Journal and shows that journal ([flows/new-entry](../flows/new-entry.md)).

## Accessibility

- Deleted journal rows read name, count and “Journal”; template rows read “Template”.
- The destination is part of the button's own name (“Restore to Personal”), so screen reader and voice control users hear and say it before acting; the announcement confirms it afterwards when the entry did not go home. The notice sentences are read with the notice, one element per paragraph.
- The deleted journal's page keeps its heading, count and text as plain text; Restore Journal comes before the explanation and Delete Permanently… is last. All text wraps and the page scrolls.
- After Cancel on a swiped row, VoiceOver focus returns to it.
- After Delete All empties the list, VoiceOver finds No Deleted Items; no announcement.
- The Delete All button is a plain text button in the default tint (not red), as in Notes and Photos.

## Platform notes (Apple)

- **Mac:** the leading swipe doesn't exist; Restore is in the context menu, Entry Actions and the notice. The explanation and Delete All… are a bar at the top of the list, as in Finder's Trash; File ▸ Delete All in Recently Deleted… (⇧⌘⌫) names what it deletes, since the menu has no list beside it.
- **iPhone and iPad:** the explanation is the last section's footer; Delete All is a bar button.
- **iPhone:** a destructive swipe takes the row away before the alert asks; Cancel brings it back with the list's insertion animation (SwiftUI can't keep a swipe open behind an alert).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
