---
id: entry-list
title: Entry list (Windows)
spec: screens/entry-list.md
features: [entry-list, all-entries, unavailable-journals, pin-entry, delete-entry, undo-delete, change-entry-date, move-entry, save-as-template, entry-actions]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/listview-and-gridview
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/swipe
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/collection-commanding
---

# Entry list (Windows)

The list pane of the [library window](library-window.md) for a journal, All Entries and Unavailable Journals. Templates and Recently Deleted reuse it: [templates](templates.md), [recently-deleted](recently-deleted.md). Search is [search](search.md). Behaviour and keys are the spec's [entry-list](../../../screens/entry-list.md).

## Controls

| Spec element | Control | Notes |
| --- | --- | --- |
| List header | Collection name and count, search box, New entry, Journal actions | Specified in [library-window](library-window.md), command bars |
| The list | `ListView`, `SelectionMode` Single, `IsItemClickEnabled` false, items from a `CollectionViewSource` with `IsSourceGrouped` | Selecting an item opens it in the editor (saving the open one first). `ItemsStackPanel` with `AreStickyGroupHeadersEnabled` true. No multi-select |
| Group header: Pinned (`library.entryList.pinned`) | The group header template, `Caption` style, secondary text | Only in a journal and in All Entries, only when something listed is pinned; no icon, no count |
| Group header: a month | Same template; full month and year in the user's language ("October 2026"), newest first | Built with the formatter ([31](../platform.md#31-dates-time-zones-and-formats)); regenerated when the clock, zone or regional format changes and at local midnight |
| Row | A `Grid` data template, every row the same height (68 epx, growing with text size), 12 epx side padding | Three lines below |
| Row line 1 | Date, day and abbreviated month ("6 Oct"), `Caption`, secondary. In All Entries, trailing: the journal name with icon Library (E8F1) (`common.untitledJournal` when blank). Far trailing: icon Error (E783) when the entry has changes to review | Icon-only parts are hidden from the tree; the row's name carries the meaning |
| Row line 2 | Title, `BodyStrong`, one line, trimmed: the title, else the first line of text, else `library.entryList.untitledEntry` | |
| Row line 3 | Preview, `Body`, secondary, one line, whitespace collapsed; `library.entryList.noAdditionalText` when there is none | |
| Separators | None; the `ListViewItem` hover and selection visuals separate rows. No line under a header | Different from the Mac's lines, which exist because Mac lists have no hover state |
| Swipe actions | `SwipeControl` in the item template; trailing Delete (`common.delete`, icon Delete E74D, `Mode` Execute so a full swipe performs it), leading Pin (`library.entryList.swipe.pin`, Pin E718) or Unpin (`library.entryList.swipe.unpin`, Unpin E77A), full swipe performs it | Touch and pen only ([6](../platform.md#6-touch-and-swipe-actions)); every action is also in the context menu and Entry actions |
| Context menu | `MenuFlyout` as the row's `ContextFlyout`; opens at the focused row for Shift+F10 and the Menu key | Items below |
| Empty states | A centred `StackPanel` over the list: secondary `TextBlock` plus, where the spec has an action, a `Button` | [Empty and loading states](#empty-and-loading-states) below |

### Context menu and Entry actions

One list, two presentations ([5](../platform.md#5-context-menus)): the row's `ContextFlyout` and the editor header's Entry actions menu. Each item first saves the open writing; if that fails, nothing happens. Pin and Unpin are the exception: they do not wait for the save and change no content ([save-entry](../flows/save-entry.md), A36). A row action acts on that row, not on the selection.

| Item | Copy | Icon | Shown when |
| --- | --- | --- | --- |
| Pin entry / Unpin entry | `library.entryActions.pin` / `library.entryActions.unpin` | Pin / Unpin | The entry can be pinned |
| Change date… | `library.entryActions.changeDate` | Calendar (E787) | The entry is editable in a journal in use |
| Move entry… | `library.entryActions.moveEntry` | MoveToFolder (E8DE) | Same |
| Save as template… | `library.entryActions.saveAsTemplate` | SaveCopy (EA35) | Same |
| Image descriptions… | `library.entryActions.imageDescriptions` | none | The entry has pictures; enabled when descriptions can be edited |
| Version history… | `common.versionHistoryEllipsis` | History (E81C) | Always |
| separator | | | The entry is editable |
| Delete entry | `library.entryActions.deleteEntry` | Delete (E74D) | The entry is editable in a journal in use. Last, no special colour |

Find in entry is in the Edit menu, not here ([commands.md](../commands.md), `find-in-entry`). Sync status is in the title bar, not here.

### Save as template

`ContentDialog`, title `library.saveTemplate.title`, `TextBox` (`Header` `common.name`, starts with the entry's title, selected), Primary `common.save` (default, disabled while blank), Close `common.cancel`. No message afterwards.

### Pin and Delete

- **Pin or unpin.** No confirmation. The row moves between Pinned and its month; with reduced motion off it uses the list's reposition transition. The open entry stays open and selected and the list scrolls just enough to keep it in view. Narrator is told `messages.announce.pinned` or `messages.announce.unpinned` (notification event) and keyboard focus follows the moved row. Undo and Redo name it `library.entryActions.pinUndo` or `library.entryActions.unpin`.
- **Delete.** No confirmation. The row leaves at once, the entry moves to Recently deleted, and the open entry becomes the next one below (above at the end of the list). Edit ▸ Undo, named `library.entryActions.deleteEntry`, or Ctrl+Z right after, brings it back; the undo step does nothing if the entry has moved meanwhile. If storing fails the row returns and the error dialog explains.

### Empty and loading states

The spec's States, as controls (the empty states of Templates and Recently deleted are in [templates](templates.md) and [recently-deleted](recently-deleted.md)):

| State | Windows |
| --- | --- |
| Empty journal or All Entries | The centred secondary `TextBlock` `library.entryList.empty.noEntries`, and below it a `Button`: `common.newJournalEllipsis` when no journal is in use, otherwise `library.menu.file.newEntry` when a new entry is possible (command `empty-new-entry`) |
| Empty Unavailable journals | `messages.unavailable.empty`, no action |
| Search without results | `library.entryList.empty.noResults` and a `Button` `library.entryList.empty.clearSearch` ([search](search.md)) |
| Loading after unlock | A blank list with no empty state until the journals are read |
| Locked | The list is not shown; the lock page replaces the window ([lock-screen](lock-screen.md)) |
| Library being replaced | Rows stay; actions that change anything are disabled |

The empty text and its button are one group for Narrator; focus is not moved to it.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large | List column 300 to 460 epx (340 default) beside the editor | Mac list column; iPad regular |
| Medium | List column 280 to 420 (300 default); the pane overlay holds the journals | iPad below 1,000 points |
| Small | The list is its own page under the Journals page, with the title bar back button; the open entry is the next page; New entry and search are in the page's header; the header shows the collection name as the page title | iPhone stacked list |
| 200% text size or more | The row's date and journal stack on separate lines and the title wraps (rows grow; they stay equal in height only at normal sizes) | Accessibility text sizes |

The list header's contents are stated once in [library-window](library-window.md); the New entry button keeps its label at every width.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `entry-actions` | Row context menu; editor header More | as in commands.md | An entry is open (header) or a row is targeted |
| `pin-entry-row`, `pin-entry` | Row context menu; swipe; Entry actions; File ▸ Pin entry (open entry) | none (Ctrl+P is Print) | The entry can be pinned: listed in a journal in use, unlocked, library not being replaced; read-only entries and entries with changes to review count; templates and Recently deleted entries do not |
| `change-date` | Context menu; Entry actions | as in commands.md | |
| `move-entry` | Context menu; Entry actions | as in commands.md | |
| `save-as-template` | Context menu; Entry actions | as in commands.md | |
| `image-descriptions` | Context menu; Entry actions | as in commands.md | |
| `entry-version-history` | Context menu; Entry actions | as in commands.md | |
| `delete-entry` | Context menu; Entry actions; trailing swipe | Delete | Focus is in the list, never while typing in the editor |
| `empty-new-entry`, `new-entry`, `new-journal` | Buttons in the empty states | as in commands.md | |
| `clear-search` | Button under No results | Esc in the search box | Search has text |

List keyboard: Up and Down move and open the entry (selection follows focus), Home, End, Page Up and Page Down; type-ahead jumps to the next title starting with the typed text; Enter moves focus to the editor; Delete deletes the selected entry. Ctrl+Backspace is not bound here ([7.1](../platform.md#71-translation-table)). Accelerators on the context menu items are scoped to the list.

## Copy differences

Sentence case on all labels ("Pin entry", "Move entry…", "Save as template…", "Image descriptions…", "Delete entry"; [12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.entryList.empty.noTemplatesHelp` | To create a template, open an entry and choose Save as Template. | To create a template, open an entry and select Save as template. | vocabulary; see B26 |
| `library.entryList.empty.noEntries`, `library.entryList.empty.noResults`, `library.entryList.empty.noDeletedItems` | No Entries, No Results, No Deleted Items | No entries, No results, No deleted items | casing |

## Accessibility

- The `ListView` is named by the collection (its title) and reports position and size, including month groups. Group headers are headings. Each row is one element whose name is date, journal (All Entries only), title and preview; its value is `library.entryList.pinned` for a pinned row so the state is heard when the header is skipped, and `messages.conflict.needsReview` is added for a row with changes to review.
- Swipe actions are the row's accessibility actions too (custom actions `common.delete` and pin or unpin), and the context menu is reachable with the Menu key.
- After Pin or Unpin from a row, focus follows the row to its new place. After Delete, focus goes to the entry that opened next, or to the list when none did.
- Empty-state text is a single element (text and its button in order). "No results" is announced when a search produces it (notification event, `MostRecent`).
- The hover and selection visuals are the system's, so contrast themes need nothing more. The attention icon on a row also has the row's value, so it is never the only signal.

## Different by design

- **Row separators.** Apple draws lines between rows on the Mac. Windows uses the item hover and selection visuals and spacing.
- **Swipe is touch and pen only.** A Mac trackpad swipe does not exist on Windows; Delete, the context menu and Entry actions cover mouse and keyboard.
- **The list header carries the title and count**, replacing the Mac window title and subtitle ([library-window](library-window.md)).
- **No Find in entry in the menu.** The Edit menu has Find, which Windows people look for there.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose), A36 (pinning and saving).
