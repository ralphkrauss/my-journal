---
id: journals
title: Journals (Windows)
spec: screens/journals.md
features: [journals-sidebar, new-journal, rename-journal, delete-journal, reorder-journals, unique-journal-names, all-entries, unavailable-journals]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/navigationview
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobadge
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/listview-and-gridview
---

# Journals (Windows)

The navigation pane of the [library window](library-window.md). Behaviour and copy keys are those of the spec's [journals](../../../screens/journals.md); the pane's place in the shell and its widths are in library-window.

## Controls

The pane is the `NavigationView` of the library window ([platform.md, 2.1](../platform.md#21-controls)), `IsBackButtonVisible` Collapsed, `OpenPaneLength` 240. All entries and the journals are a `ListView` in the pane's custom content; Templates, Recently deleted and Unavailable journals are `NavigationViewItem`s below it; Settings is the built-in Settings item (`IsSettingsVisible` true, handled in `ItemInvoked` so the open entry is saved first). `NavigationView` is meant for a few top-level sections, and a person's own list of journals is data that grows, is reordered and has counts, so it is a `ListView` (as Mail's folders and OneNote's notebooks are lists, not navigation items). The two controls share one selection, the current collection, held in the model: choosing in one clears the other. `SelectionFollowsFocus` is Enabled on both (the arrow keys choose a collection, as on the Mac sidebar; each choice saves the open entry first). If the two do not coexist cleanly in the spike, the pane becomes one sectioned `ListView` or `TreeView` in a `SplitView` with a Settings button of our own, and nothing below changes.

| Spec element | Control | Notes |
| --- | --- | --- |
| All Entries row | `ListViewItem`, icon List (EA37), content `library.journals.allEntries`, and the number of entries in journals in use as plain secondary text at the trailing edge | First item |
| Journals section header | `ListViewHeaderItem`, `common.journals` | Heading for Narrator |
| One row per journal in use | `ListViewItem`, icon Library (E8F1), content the name (`common.untitledJournal` when blank), and its entry count as plain secondary text at the trailing edge. Bound to an observable list in the person's order | Zero shows no count. The row's `ContextFlyout` is the journal context menu below |
| Second group (below the journals, after a `NavigationViewItemSeparator`) | `NavigationViewItem`: Templates (`library.journals.templates`, icon TwoPage E89A, no count); Recently deleted (`common.recentlyDeleted`, icon Delete E74D, no count); Unavailable journals (`common.unavailableJournals`, icon Folder E8B7 with an attention-dot `InfoBadge`), the last present only while some entry belongs to an unavailable journal or while it is shown | The pane's `MenuItems` change at run time; removing the selected row selects the remembered journal or the first one |
| Settings row (iPad sidebar) | The built-in Settings item (gear, `library.toolbar.settings`, last item, pinned) | Opens the Settings page |
| New journal | `AppBarButton` above the items, `library.toolbar.newJournal` | [library-window](library-window.md), command bars. Also the empty state's button |
| Count placement | A `TextBlock` in `CaptionTextBlockStyle` with `TextFillColorSecondaryBrush`, at the trailing end of the row | A count is not a notification: `InfoBadge` is a notification affordance in Fluent 2 (Mail shows its folder counts as plain text). The only badge in the pane is the attention dot on Unavailable journals; see D38 |
| Edit mode (iPhone, iPad) | Not offered | Different by design |

The selected row uses the standard selection indicator. The selected collection stays selected while a dialog is open.

### Journal context menu and Journal actions

One `MenuFlyout` built from one command list, shown as the row's `ContextFlyout` (right-click, Shift+F10, the Menu key, touch long-press) and as the More button's flyout in the list header ([library-window](library-window.md)). The journal's actions are Rename… and Delete journal… only, with New journal… first; the spec's table gives the order and enabled rules. Windows adds Move up and Move down to the pane's menu (below). A journal has no Version history, Merge into…, Default template or Review changes item, and Rename and Delete journal are never dimmed for a conflict:

| Item | Copy | Icon | Notes |
| --- | --- | --- | --- |
| New journal… (first, then a separator; in the pane's context menu on rows and on the empty area, and in the More menu) | `common.newJournalEllipsis` | NewFolder | |
| Rename… | `library.journalActions.rename` | Rename (E8AC) | F2 on the focused row does the same. A `ContentDialog`: title `library.renameJournal.title`, `TextBox` (`Header` `common.name`, starts with the current name, selected), Primary `library.renameJournal.rename` (default button, disabled while blank), Close `common.cancel` |
| Move up, Move down | `library.journals.moveUp`, `library.journals.moveDown` | Up (E74A), Down (E74B) | The keyboard, Narrator and switch route to reordering. Not on the first and the last. Pane context menu only |
| separator | | | |
| Delete journal | `library.journalActions.deleteJournal` | Delete (E74D) | No ellipsis ([12.2](../platform.md#122-ellipsis)); it asks before acting |

Rename and New journal use one dialog shape: a single-line `TextBox`, `InputScope` Default, no autocorrection, Enter chooses the default button.

### New journal

`ContentDialog`, title `library.newJournal.title`, `TextBox` with `Header` `common.name` (focused), Primary `common.create` (default button, disabled while blank after trimming), Close `common.cancel`. A taken name does not open a second dialog: the dialog stays open and shows the field's own error under the name field (an error glyph and `messages.journal.nameTaken`, also the field's `AutomationProperties.HelpText` and announced once focus is back in the field), the typed name kept and selected, and Create stays enabled so a different name can be tried at once ([8.1, rule 8](../platform.md#81-rules), field errors as in [settings](settings.md#dialog-patterns)). This replaces the spec's Name Taken alert (`library.nameTaken.title`, `library.nameTaken.message`), whose OK reopens the dialog; the outcome is identical, and those two keys are not shown on Windows.

### Delete journal

`ContentDialog`, title `library.deleteJournal.title` (a question), content `library.deleteJournal.noEntries` or `library.deleteJournal.message`, Primary `common.delete`, Close `common.cancel`, no default button ([8.1, rule 3](../platform.md#81-rules)). On Delete the row leaves at once (no animation when reduced motion is on) and another journal is shown. Failures show the general error dialog.

### Reordering

- **Drag.** A journal row can be dragged within the Journals section (`CanReorderItems` and `AllowDrop` on the `ListView`); an insertion line shows where it lands; Esc cancels; the selection stays. The fixed rows (All entries and the second group) never move and are not drop targets.
- **Keyboard.** Move up and Move down (`reorder-journal`), and Alt+Shift+Up and Alt+Shift+Down on the focused row. Focus stays on the moved row.
- **After a move.** The new order is saved on drop, synced, and announced with `messages.announce.journalMovedAbove` or `messages.announce.journalMovedBelow` (notification event, `MostRecent`, [messages](../messages.md)). Edit ▸ Undo and Redo name it `library.journals.undoMove`. A failed save shows the general error dialog and the previous order returns.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large | The pane is open, 240 epx, between the title bar and the window's bottom edge; the first item is All Entries | Mac sidebar; iPad regular width |
| Medium | The pane is an overlay opened with the title bar's pane button (Minimal mode, [2.2](../platform.md#22-layout-by-window-width)); it closes after a choice; Esc and a click outside close it | iPad below 1,000 points |
| Small | The pane is not used. The first page is a `ListView` of the same items in the same order (All Entries, header, journals, second group, Settings last), each with its count and a chevron-less row; choosing one navigates to the entry list page. New journal is the page's command bar button; search is not on this page (see [search](search.md)) | iPhone root screen |
| 200% text size or more | One layout narrower; counts stay at the trailing end and names wrap | iPhone count under the name |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `choose-collection` | A pane item; Up and Down, Home and End in the focused pane | as in commands.md | Saves the open entry first; clears the search; closes the open entry |
| `new-journal`, `new-journal-context` | Button above the items; File menu; pane context menu (rows and empty area); the empty list's button | as in commands.md | A library is open and unlocked |
| `journal-actions` | Journal row context menu; list header More button | as in commands.md | |
| `rename-journal` | Context menu; Journal actions | F2 | The journal is in use |
| `delete-journal` | Context menu; Journal actions | none (no Delete key for journals) | Always |
| `reorder-journal` | Drag; Move up, Move down | Alt+Shift+Up, Alt+Shift+Down | Not while locked or while the library is being replaced; not offered for fixed rows |
| `journals-edit` | Not offered | | No edit mode, as on the Mac |

- Esc in the pane overlay closes it; Esc during a drag cancels it.
- Dialogs close when the library locks and anything they had removed comes back ([8.1, rule 5](../platform.md#81-rules)).

## Copy differences

Sentence case on every label ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "All entries", "Recently deleted", "Unavailable journals", "Delete journal". Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.journalActions.deleteJournal` | Delete Journal… | Delete journal | ellipsis (platform.md, 12.2) |
| `library.nameTaken.title`, `library.nameTaken.message` | Name Taken; …Choose a different name. | Not shown | removed: the field's own error shows `messages.journal.nameTaken` (B30) |

## Accessibility

- The pane's `AutomationProperties.Name` is `common.journals` and it is a Navigation landmark. Each item is read with its name, then its count (the count text is part of the row's name), for example "Work, 12, selected". The Unavailable journals attention dot is hidden from the tree because the name already says what it is.
- Section headers are headings.
- Move up and Move down are the accessible reordering route; focus stays on the moved row and the move is announced. Dragging is not the only way ([6](../platform.md#6-touch-and-swipe-actions)).
- Dialogs: focus starts in the name field; on close it returns to the row or button that opened them, or to the list when that row is gone.
- High contrast: selection uses the system highlight pair; the attention dots use system colours.

## Different by design

- **No Edit mode and no reorder handles** (iPhone and iPad). Windows has no list editing mode; drag and the Move up and Move down items replace it.
- **Name taken shows inline, under the name field.** Apple opens an alert after the New journal alert. A `ContentDialog` cannot open another dialog, and an error tied to one field belongs next to it ([8.1](../platform.md#81-rules)).
- **Settings is the built-in Settings item** on every Windows layout, not only on iPad ([10](../platform.md#10-settings)).
- **Journals are a `ListView`, not `NavigationViewItem`s**, because they are user data with counts and reordering ([platform.md, 2.1](../platform.md#21-controls)).
- **Counts are plain secondary text, zero shows nothing**, as on the Mac; iPhone's `0` is not shown. Badges are for attention only.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D38 (counts in the navigation pane), B26 (select and choose), B30 (strings never shown).
