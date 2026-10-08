---
id: recently-deleted
title: Recently Deleted (list, deleted journal, recovery notice, Delete All)
features: [recently-deleted, restore-entry, restore-and-move, restore-journal, delete-permanently, delete-all-deleted, unavailable-journals]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/DeletedJournalView.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/JournalApp/Views/EntryHeaderView.swift
  - apps/apple/JournalApp/Views/PermanentDeletionView.swift
  - apps/apple/JournalApp/Views/DeleteAllPrompt.swift
  - apps/apple/JournalApp/Views/Mac/RecentlyDeletedHeader.swift
  - apps/apple/JournalApp/Model/PermanentDeletionOperations.swift
  - apps/apple/JournalApp/Model/EntryRestorationOperations.swift
  - apps/apple/JournalApp/Model/EntryDeletionOperations.swift
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/recently-deleted-2026-09-30.md
  - docs/design/ios-delete-all-and-settings-2026-10-03.md
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/journal-lifecycle-ui.md
  - docs/design/permanent-deletion.md
---

# Recently Deleted

## Purpose

Holds deleted journals, templates and entries until the person restores them or deletes them permanently. Nothing is removed automatically.

## Entry points

- The **Recently Deleted** row in [screens/journals](journals.md).

## Content

Title `common.recentlyDeleted`; Mac subtitle `common.itemCount` / `library.window.subtitle.noItems`.

**Mac only, a bar above the list** (the rows scroll under it): `library.recentlyDeleted.footer` in small secondary text, and a small button `library.recentlyDeleted.deleteAll` (Mac variant “Delete All…”), tooltip `library.recentlyDeleted.deleteAll.help`, or `library.recentlyDeleted.deleteAll.helpSearching` while a search is active.

**Sections, in order, each only when it has rows:**

1. **Journals** (`common.journals`): deleted journals by name. Row: the name (`common.untitledJournal` when blank) and under it `library.recentlyDeleted.journalCount` (entries that return when it's restored). Accessibility value `library.entryList.journalValue`.
2. **Templates** (`library.journals.templates`): deleted templates, newest first, entry-style rows with accessibility value `library.entryList.templateValue`.
3. **Entries**: month sections as in [screens/entry-list](entry-list.md); the first month's header is preceded by `library.recentlyDeleted.section.entries`. Includes entries deleted on their own and entries deleted with their journal.

**iPhone and iPad:** the footer `library.recentlyDeleted.footer` under the last section; the bar button `library.recentlyDeleted.deleteAll` at the top right, shown only when the list has something and no search is active.

## Actions

### Row actions

| Action | Where | Shown when | Result |
| --- | --- | --- | --- |
| Restore (`restore-entry`) | Leading swipe (accent), context menu and Entry Actions (uturn arrow), all labelled `common.restore` | the entry's journal is in use and the entry wasn't deleted with its journal by an earlier version; or a template | Restores at once, without confirmation ([flows/delete-and-restore](../flows/delete-and-restore.md)) |
| Delete Permanently… (`delete-permanently`) | Context menu and Entry Actions (`library.entryActions.deletePermanently`, trash, destructive, after a separator) | always for entries and templates here | Delete Permanently alert, below |
| Delete (trailing swipe, destructive) | `common.delete` | always | The row leaves at once; then the Delete Permanently alert. Cancel brings the row back |
| Delete or ⌘⌫ (Mac, list focused) | | an entry or template is selected | Delete Permanently alert |
| Image Descriptions…, Version History… | context menu and Entry Actions | as in entry-list | Read-only views |

Pin, Change Date…, Move Entry…, Save as Template… and Delete Entry aren't offered here.

### Opening an item

- **Entry or template:** opens read-only in the editor with the [recovery notice](#recovery-notice) above the title.
- **Deleted journal:** the editor area shows the journal's detail:
  1. Title: the journal's name (`common.untitledJournal`).
  2. Secondary: `library.recentlyDeleted.journalCount`.
  3. `library.recentlyDeleted.restoreJournal`, opening [screens/restore-journal](restore-journal.md); or, for a journal saved by a newer version, `messages.unavailable.restoreJournalNeedsUpdate` and an Export Archive… control (Settings ▸ Backup, screens/settings-backup).
  4. `common.reviewChanges` when the journal has changes to review (screens/conflict-review).
  5. `common.versionHistoryEllipsis` when the journal has saved versions ([screens/journal-history](journal-history.md)).
  6. `library.entryActions.deletePermanently` (destructive).
  All disabled while the library is being replaced.

### Delete Permanently (`delete-permanently`)

1. The open entry is saved and the item checked first (unsaved changes, changes to review, newer format).
2. Alert, title `library.deletePermanently.title` with the item's name (`library.entryList.untitledEntryInAlert`, `library.entryList.untitledTemplate` or `common.untitledJournal` when blank); for a journal with entries `library.deletePermanently.titleWithEntries`. Message: for a journal with entries `library.deletePermanently.journalEntries`, then `library.deletePermanently.retention`. Buttons `common.delete` (destructive) and `common.cancel`.
3. **Delete:** the row (and for a journal its entries' rows) leaves at once with the list's animation; the item is deleted from this device and the deletion syncs. An open item closes; on iPhone its page goes back at once. No message.
4. **Cancel:** nothing changes; a row the swipe removed comes back and VoiceOver focus returns to it.
5. An item with changes to review isn't deleted: a standard alert titled `messages.deleteConflict.title` with the item's name, message `messages.deleteConflict.record`, and buttons `common.reviewChanges` (opens the review) and `common.cancel`. Other failures (general error alert; a removed row comes back): `messages.generic.deleteChanged`, `messages.generic.deleteNeedsUpdate`, `messages.save.before.reviewChanges`, `messages.refresh.itemDeleted`. An item already gone is ignored quietly.

### Delete All

Feature `delete-all-deleted`; command `delete-all-recently-deleted`.

Available from the bar button (iPhone, iPad), the bar's Delete All… (Mac) and File ▸ Delete All in Recently Deleted… (⇧⌘⌫, Mac). Enabled only while Recently Deleted is shown, has rows, has no search, no Delete All is already running, and the library is open, unlocked and not being replaced.

1. The open entry is saved, then every journal, template and entry listed is checked (journals first). The button is disabled while checking.
2. If something can be deleted, a standard alert:
   - exactly one item (or one journal with its entries): the Delete Permanently alert above;
   - one kind: `library.deleteAll.title.entries`, `library.deleteAll.title.templates` or `library.deleteAll.title.journals`;
   - several kinds: `library.deleteAll.title.items`, message starting `library.deleteAll.includes` with the non-zero counts (`common.entryCount`, `common.journalCount`, `common.templateCount`, joined in the system list format);
   - if some items stay, one sentence: `library.deleteAll.held.review`, `library.deleteAll.held.newerVersion` or, for mixed reasons, `library.deleteAll.held.other`;
   - always last `library.deletePermanently.retention`;
   - buttons `common.delete` (destructive) and `common.cancel`.
   Entries are counted including a deleted journal's entries, since the list shows them as rows.
3. If nothing can be deleted, no confirmation: a notice `library.deleteAll.nothing.title` with `library.deleteAll.nothing.review`, `library.deleteAll.nothing.newerVersion` or `library.deleteAll.nothing.other`, and `common.ok`.
4. **Delete:** every row being deleted leaves at once; rows that stay remain. Items are deleted one by one (journals first, each with its entries), each checked again. Entries deleted with their journal aren't deleted twice. With nothing left, `library.entryList.empty.noDeletedItems` shows and the button disappears.
5. Items that changed between the alert and deleting stay, their rows come back, and a notice says `library.deleteAll.changed.title` / `library.deleteAll.changed.message` (`common.ok`).
6. Stored but not shown: `messages.refresh.itemsDeleted`.

Only what was checked is deleted: items that arrive meanwhile (sync, Undo) stay. A journal that can't be deleted keeps all its entries.

### Recovery notice

Shown above the title of a read-only entry or template opened from Recently Deleted or Unavailable Journals, on a tinted background (at accessibility sizes it takes at most half the height and scrolls).

| Situation | Text | Actions |
| --- | --- | --- |
| Template in Recently Deleted | `library.recoveryNotice.template` | `common.restore` (if editable) |
| Entry in Recently Deleted, journal in use | `library.recoveryNotice.entry` | `common.restore`; `library.recoveryNotice.restoreAndMove` |
| Entry in Recently Deleted, journal also deleted (and editable, no changes to review) | `library.recoveryNotice.entry` | `library.recoveryNotice.restoreWithJournal` ([screens/restore-journal](restore-journal.md), Restore Entry); `library.recoveryNotice.restoreAndMove` |
| Entry deleted with its journal by an earlier version | `library.recoveryNotice.legacy` | `library.recoveryNotice.restoreAndMove` |
| Unavailable: journal saved by a newer version | `common.updateToRestoreEntry` | — |
| Unavailable: journal missing, library syncs | `common.journalNotArrived` | `common.trySyncingAgain` (syncs now, retrying refused items); `library.recoveryNotice.restoreAndMove` when an earlier version deleted the entry with its journal |
| Unavailable: journal missing, no sync | `common.journalUnavailableEntrySaved` | `library.recoveryNotice.restoreAndMove` when an earlier version deleted the entry with its journal |
| Unavailable: journal has changes to review | `common.journalNeedsReview` | `common.reviewChanges` |

Actions are offered only when the item is editable (not saved by a newer version). Restore and Move… opens [screens/move-entry](move-entry.md) in its restoring form.

## States

- **Empty:** `library.entryList.empty.noDeletedItems`; no Delete All. A deleted journal or template counts as content.
- **Search:** prompt `library.search.deleted`. Journals are filtered by name as it's typed; templates by name or text; entries by title or text. No results: `library.entryList.empty.noResults` with `library.entryList.empty.clearSearch`. Delete All is hidden (iPhone, iPad) or disabled (Mac) while searching.
- **Locked:** prompts close; a swiped row returns; nothing is deleted. Delete All stopped by locking keeps what was already deleted, and the rest comes back, without a message.

## Rules

- Items stay until deleted permanently. There is no automatic removal.
- Deleting permanently can't be undone here; copies may remain in archives, backups and the server's history (the alert says so).
- A deleted pinned entry is listed under its month, not Pinned, and is pinned again when restored.
- New Entry from here creates an entry in the Default Journal and shows that journal ([flows/new-entry](../flows/new-entry.md)).

## Accessibility

- Deleted journal rows read name, count and “Journal”; template rows read “Template”.
- After Cancel on a swiped row, VoiceOver focus returns to it.
- After Delete All empties the list, VoiceOver finds No Deleted Items; no announcement.
- The Delete All button is a plain text button in the default tint (not red), as in Notes and Photos.

## Platform notes (Apple)

- **Mac:** the explanation and Delete All… are a bar at the top of the list, as in Finder's Trash; File ▸ Delete All in Recently Deleted… (⇧⌘⌫) names what it deletes, since the menu has no list beside it.
- **iPhone and iPad:** the explanation is the last section's footer; Delete All is a bar button.
- **iPhone:** a destructive swipe takes the row away before the alert asks; Cancel brings it back with the list's insertion animation (SwiftUI can't keep a swipe open behind an alert).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
