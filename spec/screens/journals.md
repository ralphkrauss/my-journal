---
id: journals
title: Journals (sidebar and Journals screen)
features: [journals-sidebar, new-journal, rename-journal, journal-default-template, merge-journal, delete-journal, reorder-journals, unique-journal-names, all-entries, unavailable-journals]
sources:
  - apps/apple/JournalApp/Views/JournalSidebarView.swift
  - apps/apple/JournalApp/Views/CompactJournalNavigation.swift
  - apps/apple/JournalApp/Views/JournalEditButton.swift
  - apps/apple/JournalApp/Views/JournalMoreMenu.swift
  - apps/apple/JournalApp/Views/JournalNameTakenAlert.swift
  - apps/apple/JournalApp/Views/JournalDeletionPrompt.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/Mac/RootView+MacWindow.swift
  - apps/apple/JournalApp/Model/LibraryOperations.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - apps/apple/JournalApp/Model/JournalEditing.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - docs/design/journal-order.md
  - docs/design/journal-name-uniqueness.md
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/ios-delete-all-and-settings-2026-10-03.md
---

# Journals

## Purpose

The place to choose what the entry list shows (All Entries, one journal, Templates, Recently Deleted, Unavailable Journals) and to manage journals: create, rename, set a default template, merge, delete and reorder.

## Entry points

- Mac and iPad (regular width): the sidebar, always present unless hidden.
- iPhone (and stacked layouts): the root screen, titled `common.journals`.

## Content

A list, in this order:

1. **All Entries** row: tray symbol, `library.journals.allEntries`, and the number of entries in journals in use.
2. **Journals** section (header `common.journals`): one row per journal in use, closed-book symbol, the journal's name (`common.untitledJournal` when blank), and its number of entries. In the person's order ([Rules](#rules)).
3. A second group:
   - **Templates** row: `library.journals.templates`, no count.
   - **Recently Deleted** row: trash symbol, `common.recentlyDeleted`, no count.
   - **Unavailable Journals** row: folder with exclamation mark, `common.unavailableJournals`, no count. Only while some entry belongs to an unavailable journal, or while this collection is shown.
4. **iPad sidebar only:** a last group with a **Settings** row (gear, `library.toolbar.settings`), which opens Settings.

Counts: a bare number at the trailing end; zero shows nothing on the Mac and `0` on iPhone and iPad. At accessibility text sizes the count moves under the name as `common.entryCount`.

The selected collection is highlighted (Mac, iPad). On iPhone each row pushes its collection's list with a chevron.

A journal is **in use** when it isn't in Recently Deleted, isn't saved by a newer version, and has no changes to review. Journals not in use don't appear here; their entries appear in Unavailable Journals.

## Actions

### Choosing a collection

Selecting a row shows that collection's entries (saving the open entry first). The search is cleared and the open entry closes. In a journal, the remembered entry or today's entry opens (see screens/library-window, State restoration).

### New Journal (`new-journal`)

Available from: the toolbar's New Journal (Mac over the sidebar, iPad sidebar bar, iPhone top right), File ▸ New Journal… (⌥⌘N), the Mac sidebar's context menu (on a journal row and on empty space, `common.newJournalEllipsis`), the Mac Journal Actions menu, and the empty list (`common.newJournalEllipsis`, when there are no journals). Enabled while a library is open and unlocked.

1. Alert `library.newJournal.title` with a text field (placeholder `common.name`), `common.cancel` and `common.create`. Create is disabled while the name is blank after trimming spaces.
2. If another journal in use has the name (ignoring case and surrounding spaces): alert `library.nameTaken.title` / `library.nameTaken.message` with `common.ok`, which reopens New Journal with the typed name kept.
3. Otherwise the journal is created with the trimmed name and shown (selected, its empty list). In edit mode on iPhone and iPad it's only added, and edit mode continues.
4. When New Journal was opened by New Entry because there were no journals, the new entry starts in the new journal right after.

On the Mac, New Journal leaves Editor Only first.

### Journal actions (`journal-actions`)

The same catalog everywhere: a journal row's context menu (right-click or Control-click on the Mac; touch and hold on iPhone and iPad), the ⋯ button of a row in edit mode, Journal Actions (⋯) in the list's toolbar while a journal is shown, and on the Mac the toolbar's Journal Actions menu.

| Item | Copy | Symbol | Enabled when | Result |
| --- | --- | --- | --- | --- |
| New Journal… (Mac context menu and Mac Journal Actions only, first, then a separator) | `common.newJournalEllipsis` | folder with plus | library open and unlocked | New Journal, above |
| Rename… | `library.journalActions.rename` | pencil | journal has no changes to review | Rename, below |
| Default Template ▸ | `common.defaultTemplate` | document | no changes to review, and there is a template or the journal still names a template that's gone | Submenu: `common.blankEntry`, then every template by name; the current choice is checked. Choosing saves it at once, without a message. |
| Merge Into… | `library.journalActions.mergeInto` | merge arrows | no changes to review, and another journal is in use | [screens/merge-journal](merge-journal.md) |
| Version History… | `common.versionHistoryEllipsis` | clock | always | The journal's version history ([screens/journal-history](journal-history.md)) |
| — | | | | |
| Delete Journal… | `library.journalActions.deleteJournal` | trash, destructive | always | Delete Journal, below |

On the Mac, the toolbar's Journal Actions menu holds New Journal… alone when no journal is shown.

### Rename (`rename-journal`)

Alert `library.renameJournal.title` with the name field (starts with the current name), `common.cancel` and `library.renameJournal.rename` (disabled while blank). A name another journal in use has shows Name Taken, whose OK reopens Rename with the typed name. The name is saved trimmed; a change of case only is allowed. No confirmation.

### Default Template (`journal-default-template`)

New Entry in this journal starts from the chosen template; Blank Entry means an empty entry. While the chosen template is in Recently Deleted, the journal behaves as Blank Entry, and the choice returns if the template is restored.

### Delete Journal (`delete-journal`)

1. The open entry is saved and the deletion is checked first.
2. Alert `library.deleteJournal.title` (with the journal's name), message `library.deleteJournal.noEntries` or `library.deleteJournal.message` (count of its entries on this device), buttons `common.delete` (destructive) and `common.cancel`.
3. **Delete:** the row leaves the list at once (animated unless Reduce Motion). The journal and its entries move to Recently Deleted, and another journal is shown. Nothing else is said.
4. A journal (or one of its entries) with changes to review isn't deleted: a standard alert titled `messages.deleteConflict.title` with the journal's name, message `messages.deleteConflict.journal`, and buttons `common.reviewChanges` (opens the review) and `common.cancel`. Other failures, in the general error alert: `messages.generic.journalDeleteNeedsUpdate`, `messages.save.before.tryAgain`, `messages.lifecycle.changed`, `messages.refresh.journalDeletedView`. A journal already deleted elsewhere is ignored quietly.

See [flows/delete-and-restore](../flows/delete-and-restore.md) for restoring.

### Reorder (`reorder-journals`)

- **Mac:** drag a journal row up or down within the Journals section; an insertion line shows where it lands. Escape cancels. The selection stays.
- **iPhone and iPad:** **Edit** (`library.toolbar.edit`) turns on edit mode; drag a row's reorder handle. Outside edit mode, touch and hold a row, then move it to drag. With a pointer on iPad, press and drag.
- **VoiceOver (iPhone and iPad):** each journal row has the actions `library.journals.moveUp` (not on the first) and `library.journals.moveDown` (not on the last).
- The new order is saved on drop, shown at once, synced to other devices, and announced: `messages.announce.journalMovedAbove` or `messages.announce.journalMovedBelow`. Undo and Redo (Edit ▸ Undo Move Journal, `library.journals.undoMove`) move it back. If saving fails: error alert `messages.generic.moveJournalFailed` (`messages.library.needsUpdate` when the library record is from a newer version) and the previous order returns.
- All Entries, Templates, Recently Deleted, Unavailable Journals and Settings never move.

### Edit mode (iPhone and iPad)

- **Edit** becomes the system's round checkmark (label `common.done`); choosing it ends edit mode.
- Fixed rows (All Entries, Templates, Recently Deleted, Unavailable Journals, Settings) are dimmed, without count or chevron, and can't be chosen.
- Journal rows keep symbol and name; the count and chevron are replaced by an accent ⋯ button (label `library.toolbar.journalActions`) with the journal actions, a thin separator and the reorder handle. Rows keep their height.
- The collection selection stays where it was; rows can't be chosen.
- New Journal stays available (the new journal is added at the end). Search and New Entry also stay available and end edit mode first. Settings stays available.
- Edit mode ends with Done, when My Journal locks, when the library is replaced, and when the last journal is deleted. Edit is hidden when there are no journals in use, and disabled while locked or while the library is being replaced.

## States

- **No journals:** the Journals section is empty; Edit is hidden. New Entry offers New Journal first.
- **Locked or library being replaced:** reordering, Edit and the VoiceOver move actions are unavailable; open alerts and sheets close on lock.
- **Journal with changes to review:** not listed (it's unavailable); its entries are in Unavailable Journals.
- **Order from a newer version:** pins and order can't be read; journals are listed by name and reordering is unavailable (Settings ▸ Sync explains, screens/settings-sync).

## Rules

- **Order:** once any journal has been moved, journals follow the person's order on every device; new, restored-without-a-position, merged-in and imported journals go at the end; journals from older versions without a position follow the arranged ones by name. Until then journals are sorted by name.
- **Names are unique** among journals in use, ignoring case and surrounding spaces. New Journal and Rename refuse a taken name (Name Taken). Restoring, importing, joining and syncing add a number instead (“Work 2”).
- Names are trimmed; a blank name can't be saved.
- The journal created with the library (“Default”) is an ordinary journal: it can be renamed, moved, merged and deleted.

## Accessibility

- The list's label is `common.journals`.
- Counts are read with the row. At accessibility sizes names wrap and the count moves below the name.
- Move Up / Move Down actions and the move announcement on iPhone and iPad; focus stays on the moved row.
- In edit mode dimmed rows read as dimmed; each journal reads its name, then Journal Actions, then the handle.
- Reduce Motion: rows move without animation.

## Platform notes (Apple)

- **Mac:** no edit mode and no Edit button (owner); reorder by dragging. The sidebar's empty area has a context menu with New Journal…. No Settings row: Settings is in the app menu (⌘,).
- **iPad:** sidebar with large title, New Journal and Edit in its bar, Settings as the last row (owner decision: Settings at the bottom of the sidebar).
- **iPhone:** root screen with Settings at the top left and New Journal and Edit at the top right, as separate buttons; search and New Entry in the bottom bar. Searching replaces the list with results ([screens/search](search.md)).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
