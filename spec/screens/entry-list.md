---
id: entry-list
title: Entry list (a journal, All Entries, Unavailable Journals)
features: [entry-list, all-entries, unavailable-journals, pin-entry, delete-entry, undo-delete, change-entry-date, move-entry, save-as-template, entry-actions]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/CompactJournalNavigation.swift
  - apps/apple/JournalApp/Views/MenuActions.swift
  - apps/apple/JournalApp/Views/MacListSeparators.swift
  - apps/apple/JournalApp/Views/CommandDeleteKey.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/DerivedLists.swift
  - apps/apple/JournalApp/Model/LibraryOperations.swift
  - apps/apple/JournalApp/Model/EntryDeletionOperations.swift
  - apps/apple/JournalApp/Model/EntryActionOperations.swift
  - docs/design/pinned-entries.md
  - docs/design/mac-list-separators-2026-10-04.md
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/ios-delete-all-and-settings-2026-10-03.md
---

# Entry list

## Purpose

Lists the entries of the chosen collection, newest first, grouped by month, with pinned entries on top. It's where entries are opened, pinned, deleted and organized. Templates and Recently Deleted use the same list with differences described in [screens/templates](templates.md) and [screens/recently-deleted](recently-deleted.md).

## Entry points

- Choosing a journal, All Entries or Unavailable Journals in [screens/journals](journals.md).

## Content

**Title:** the collection's name (Mac: window title and subtitle, see screens/library-window; iPhone and iPad: the page or column title).

**Sections, in order:**

1. **Pinned** (header `library.entryList.pinned`), in a journal and in All Entries only, when something listed is pinned. Pinned entries appear only here, never also under their month.
2. **One section per month** of the entry date, header in the person's locale as full month and year (“October 2026”), newest month first.

Within a section, entries are sorted by entry date, newest first (ties by identifier). The headers look the same; the Pinned section has no icon and no count.

**Row** (every row the same height, as in Notes):

1. First line, small secondary text: the entry date as day and abbreviated month (“6 Oct”). In All Entries, at the trailing end, the entry's journal with a closed-book symbol (`common.untitledJournal` when blank). At the far trailing end, an exclamation-circle symbol when the entry has changes to review (accessibility label `messages.conflict.needsReview`).
2. Title, medium weight, one line: the entry's title; if blank, its first line of text; if empty, `library.entryList.untitledEntry`.
3. Preview, secondary text, one line: the start of the text with runs of whitespace collapsed; `library.entryList.noAdditionalText` when there is none.

At accessibility text sizes the date and journal stack on separate lines and the title wraps.

**Mac lines:** lines between rows only; none under a section header, none after a section's last row (mac-list-separators-2026-10-04.md). iPhone and iPad use inset grouped sections.

## Actions

### Opening

- **Mac and iPad (regular):** selecting a row opens the entry in the editor (saving the open one first). One row at a time; there is no multiple selection.
- **iPhone:** tapping a row pushes the entry's page.

### Swipe actions (iPhone, iPad, Mac trackpad)

| Edge | Shown when | Copy | Symbol, tint | Result |
| --- | --- | --- | --- | --- |
| Trailing (full swipe performs it) | The entry is editable and not deleted | `common.delete` | trash, destructive red | `delete-entry`: the row leaves at once; the entry moves to Recently Deleted |
| Leading (full swipe performs it) | The entry can be pinned and isn't | `library.entryList.swipe.pin` | pin, accent | `pin-entry` |
| Leading | The entry is pinned | `library.entryList.swipe.unpin` | pin with slash, accent | `pin-entry` (unpin) |

### Context menu and Entry Actions (`entry-actions`)

Touch and hold (iPhone, iPad), right-click or Control-click (Mac). The same catalog is the editor's Entry Actions menu (⋯) for the open entry. Order:

| Item | Copy | Symbol | Shown when | Enabled when | Result |
| --- | --- | --- | --- | --- | --- |
| Find in Entry (Entry Actions on iPhone and iPad only, then a separator) | `library.entryActions.findInEntry` | magnifying glass | an entry is open | always | The system find bar in the entry (screens/entry-editor) |
| Pin Entry / Unpin Entry | `library.entryActions.pin` / `library.entryActions.unpin` | pin / pin with slash | the entry can be pinned | always | `pin-entry` |
| Change Date… | `library.entryActions.changeDate` | calendar | the entry is editable in a journal in use | always | [screens/change-date](change-date.md) |
| Move Entry… | `library.entryActions.moveEntry` | folder | same | always | [screens/move-entry](move-entry.md) |
| Save as Template… | `library.entryActions.saveAsTemplate` | document with plus | same | always | Save as Template, below |
| Image Descriptions… | `library.entryActions.imageDescriptions` | text below photo | the entry has pictures | descriptions can be edited now | screens/image-description |
| Version History… | `common.versionHistoryEllipsis` | clock | always | always | screens/version-history |
| — | | | the entry is editable | | |
| Delete Entry | `library.entryActions.deleteEntry` | trash, destructive | the entry is editable in a journal in use | always | `delete-entry` |
| Sync Status ▸ (Entry Actions on iPhone and iPad, last, only when sync needs the person) | `messages.syncStatus.title` | | | | screens/sync-status |

Row actions act on that row, not on the selection: an action that needs the entry open (Change Date…, Move Entry…, Save as Template…, Image Descriptions…, Version History…) first saves the open entry and opens this one. Pin and Delete don't change the selection.

Entry Actions is disabled when nothing is open, or a deleted journal is shown.

### Keyboard (Mac)

With the list focused (never while typing in the editor): **Delete** or **⌘⌫** deletes the selected entry (`delete-entry`); in Recently Deleted it asks to delete permanently. Arrow keys move the selection and open the entry.

### Pin Entry (`pin-entry`)

From the leading swipe, the context menu, Entry Actions, or File ▸ Pin Entry (acts on the open entry; no shortcut).

- No confirmation, no message. The row moves into or out of Pinned with the list's animation (none with Reduce Motion). The open entry stays open and selected; the list scrolls just enough to keep it in view.
- VoiceOver announces `messages.announce.pinned` or `messages.announce.unpinned`, and its focus follows the row to its new section.
- Undo and Redo: Edit ▸ Undo Pin Entry / Undo Unpin Entry (`library.entryActions.pinUndo`, `library.entryActions.unpin`).
- A pin belongs to the entry: it's kept through edits, Change Date, Move Entry, deletion (hidden in Recently Deleted) and restoring. Copies (Save as Template, New Entry from Template, Version History copies) aren't pinned. Pins sync.
- Can be pinned: an entry listed in a journal in use, while unlocked and not replacing the library, including read-only entries and entries with changes to review. Not templates, not entries in Recently Deleted or Unavailable Journals.
- Failure: error alert `messages.generic.pinFailed` or `messages.generic.unpinFailed`; `messages.library.needsUpdate` when the library record is from a newer version.

### Delete Entry (`delete-entry`)

- No confirmation, as in Notes. The row leaves the list at once with the list's removal animation (none with Reduce Motion) and the entry moves to Recently Deleted.
- If it was open: Mac and iPad open the entry below it (above it at the end of the list); iPhone goes back to the list.
- Undo (`undo-delete`): Edit ▸ Undo Delete Entry, or ⌘Z right after, brings it back (and Redo deletes it again). The undo step does nothing if the entry has changed place meanwhile.
- If storing the deletion fails, the row comes back and the error alert explains.
- See [flows/delete-and-restore](../flows/delete-and-restore.md).

### Save as Template (`save-as-template`)

Alert `library.saveTemplate.title` with a name field (placeholder `common.name`, starting with the entry's title), `common.cancel` and `common.save` (disabled while blank). Save stores a new template with the trimmed name and the entry's text and formatting; the entry is unchanged and stays open. No message.

## States

- **Empty journal or All Entries:** centered secondary text `library.entryList.empty.noEntries`, and:
  - no journals in use: action `common.newJournalEllipsis` (New Journal);
  - New Entry possible: action `library.menu.file.newEntry`.
- **Empty Unavailable Journals:** `messages.unavailable.empty`, no action.
- **Search without results:** `library.entryList.empty.noResults` with action `library.entryList.empty.clearSearch`.
- **Loading after unlock:** blank, no empty state, until the journals are read.
- **Locked:** the list isn't shown ([screens/lock-screen](lock-screen.md)).
- **Library being replaced:** rows stay visible; actions that change anything are disabled.

## Rules

- Only entries are listed here (no templates). A journal shows its entries; All Entries shows the entries of every journal in use; Unavailable Journals shows entries whose journal is missing, saved by a newer version, or has changes to review.
- Entries in Recently Deleted never appear in these lists.
- Pinned entries come first in a journal and All Entries, also in Previous/Next Entry order and when choosing the next entry after Delete.
- The list keeps showing rows while the library is saved or synced; it changes only when what it shows changes.
- An entry from Unavailable Journals opens read-only with a notice explaining why and offering what can be done ([screens/recently-deleted](recently-deleted.md#recovery-notice)).

## Accessibility

- Each row reads as one element: date, journal (All Entries), title, preview; value `library.entryList.pinned` for a pinned row, so the state is heard even when the header is skipped.
- Section headers are headings.
- Swipe actions are also the row's accessibility actions.
- After Pin or Unpin from a row, VoiceOver focus returns to the moved row.

## Platform notes (Apple)

- **Mac:** plain inset list, selection opens entries; Delete and ⌘⌫ work only while the list has focus, so ⌘⌫ in the editor keeps deleting to the start of the line.
- **iPhone and iPad:** inset grouped list. On iPhone the list is a page with its own bar (Journal Actions in a journal) and a bottom bar with search and New Entry.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
