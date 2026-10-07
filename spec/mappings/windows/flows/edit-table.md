---
id: edit-table
title: Edit a table (Windows)
spec: flows/edit-table.md
features: [tables]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/rich-edit-box
  - https://learn.microsoft.com/en-us/windows/apps/design/accessibility/custom-automation-peers
---

# Edit a table (Windows)

Writes in a Markdown (GitHub) table directly in the entry: type in cells, move between them, add and remove rows and columns, and align columns. Steps and rules are the spec's [edit-table](../../../flows/edit-table.md) and TB-1 to TB-7, BI-3, PA-3 of [editing-rules](editing-rules.md).

**This file depends on the editor control spikes** ([entry-editor](../screens/entry-editor.md), The spikes; D30, D33). `RichEditBox` exposes no table editing, so the draft default of D33 (the review's recommendation) is: **if Spike A (`RichEditBox`) wins, tables are preserved, byte-exact, read-only grids that are edited in source view; if Spike B (`WebView2`) wins, tables are edited natively in place.** An overlay grid of cell editors with a shared undo history over a rich edit control is not planned: it is a second editor on top of the first, with the selection, caret and undo problems that causes. A table already in an entry stays intact either way (M-rules, TB-6). The keys, menus, rules and copy below are the same in both cases; only the controls differ.

## Controls

### If Spike A wins: a preserved read-only grid

| Spec element | Windows control | Notes |
| --- | --- | --- |
| The table in the body | A table block holds one reserved empty line of exactly the table's height in the body control, with a read-only grid drawn over it: hairline borders (`DividerStrokeColorDefaultBrush`), columns of equal width of at least 7 × the text size inside a horizontal `ScrollViewer` when they do not fit, header row SemiBold (not the Bold format, TB-5), 12 epx extra after the table | The grid follows the body's scrolling, layout, zoom and window width, and is exposed to Narrator as a table (below). Its text can be selected and copied; copying gives the table's Markdown as plain text (PA-3), built from the model |
| Editing | In source view ([source-view](source-view.md)): the table is its Markdown text and every edit is text. A context-menu item `library.menu.view.viewSource` on the grid moves to source view with the caret in that table | No new strings |
| Insert ▸ Table | Enabled in source view, where it inserts a two-column table skeleton as Markdown text at the caret (a header row, the delimiter row and one empty row); disabled in preview, because an empty read-only grid cannot be filled | A parity gap, recorded in [parity.yaml](../../../parity.yaml) if the owner keeps this default |
| Table structure commands (Add row, Add column, Delete row, Delete column, Delete table, alignment) | Disabled in preview; in source view they are text edits | |

### If Spike B wins (or any control that edits tables itself): native cells

| Spec element | Windows control | Notes |
| --- | --- | --- |
| The table in the body | A native table in the editor, with hairline borders, columns of equal width of at least 7 × the text size inside a horizontal scroller when they do not fit; 12 epx extra after the table | Rows are as tall as their tallest cell |
| Cell being edited | The cell is edited in place with lists, images and paragraph styles disabled; text wraps for display; a cell holds one line, so typed or pasted line breaks become spaces (TB-2) | Typing in a cell is one step in the entry's single history (TB-1, TB-7) |
| Header row | The first row, SemiBold weight (not the Bold format, TB-5) | |
| Cell context menu | A context flyout with the standard text commands as primary commands and, after a separator, a secondary sub-menu `library.menu.format.table` ▸ `library.menu.format.table.addRow`, `library.menu.format.table.addColumn`, an `editor.table.alignment` sub-menu (`editor.table.alignment.left`, `editor.table.alignment.center`, `editor.table.alignment.right`), `library.menu.format.table.deleteRow`, `library.menu.format.table.deleteColumn`, `library.menu.format.table.deleteTable` | The alignment sub-menu follows [commands.md](../commands.md) and open question D7. Opened by right-click, Shift+F10, the Menu key and touch long-press, at the focused cell |
| Format ▸ Table | `MenuFlyoutSubItem` of the Format menu with Add row below, Add column after, a separator, Delete row, Delete column, Delete table | Enabled only while a cell is being edited |

### Steps (native cells)

1. **Insert ▸ Table** adds a table with 2 columns, a header row and one body row, all empty, and the caret goes to the first header cell. A click or touch in any cell of an existing table edits that cell.
2. **Moving.** Tab goes to the next cell (left to right, then the next row); Shift+Tab to the previous cell; Enter to the cell below. Past the last cell the caret leaves the table to the line after it; before the first cell, to just before the table (TB-3, N-15).
3. **Formatting in a cell.** Bold, Italic, Underline, Strikethrough and Inline code (menu, shortcuts, the formatting bar and the mini-toolbar) apply to the cell's selection or typing; paragraph styles and lists are disabled.
4. **Structure.** Add row below inserts an empty row under the cell's row; Add column after inserts an empty column after the cell's column (no alignment); Delete row, Delete column and Delete table remove them; deleting the last row or column removes the table and the caret goes to the line after it; Align left, center and right set the column's alignment (stored in the delimiter row, `:--`, `:-:`, `--:`). After a structure change the caret stays in the same row and column (or the nearest one left).
5. **Undo.** Typing in one cell is one step until anything else changes; each structure change is one step; both share the entry's history, so Ctrl+Z in a cell undoes in the entry (TB-1, TB-7).

### States

- **Read-only entry:** cells can be selected and copied, not edited; no structure menu.
- **Source view:** the table is its Markdown text ([source-view](source-view.md)).
- **Selection and copy.** Select All, a selection across a table and Ctrl+C including a table give other apps its Markdown as plain text (PA-3); the app builds this from the model, because a drawn grid's cells are not part of a rich edit control's selection.

Cell edits keep the other cells' text, alignment marks, escaped pipes and the surrounding source (TB-6): portable model code.

## Layout at each window width

| Width | What differs | Apple equivalent |
| --- | --- | --- |
| Large and medium | Columns share the text column's width, at least 7 × the text size each; more columns than fit scroll sideways inside the table | Mac inline grid |
| Small | Same, with 12 epx margins; the table scrolls sideways more often | iPhone inline grid |
| 200% text size or more | The 7 × size minimum grows with the text, so most tables scroll sideways | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `insert-table` | Format ▸ Insert ▸ Table; the formatting bar's Insert drop-down | none | The entry is editable; with Spike A only in source view |
| `table-add-row`, `table-add-column`, `table-delete-row`, `table-delete-column`, `table-delete-table` | Format ▸ Table; cell context menu | none | A cell is being edited (native cells only) |
| `table-align-left`, `table-align-center`, `table-align-right` | Cell context menu ▸ Table ▸ Alignment | none | A cell is being edited (native cells only) |
| `table-next-cell`, `table-previous-cell` | Tab, Shift+Tab in a cell | Tab, Shift+Tab | A cell is being edited (native cells only) |
| `table-cell-below` | Enter in a cell | Enter | A cell is being edited (native cells only) |

F6 and Shift+F6 leave the table and the editor; Tab never traps (it moves cell to cell and then leaves the table).

## Copy differences

Sentence case on every label: "Add row below", "Add column after", "Delete row", "Delete column", "Delete table", "Align left" ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). No other differences.

## Accessibility

- The table is a container named `editor.table.accessibilityLabel` exposing the grid and table patterns (a custom automation peer on `RichEditBox` for the drawn grid, [custom automation peers](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/custom-automation-peers); Chromium's table roles in Spike B), so Narrator reads row and column positions and headers. Each cell is named `editor.table.cell.header` (row 1) or `editor.table.cell.row`, in row order. This is part of the Narrator walkthrough script, the ship gate of D32.
- Structure changes are announced after they happen (the new row or column count is not in the spec; none is added).
- The grid's colours are system brushes, and the lines remain visible in contrast themes.
- Focus order: body text, then cells in row order, then the text after the table.

## Different by design

- **A preserved read-only grid edited in source view** if Spike A wins (D33), instead of in-place cells; native cells if Spike B wins. Reason: `RichEditBox` has no table API, and an overlay editor with shared undo is a second editor on top of the first.
- **Cell menu** is a context flyout with the Table sub-menu; Windows has no Services or AutoFill items to remove.
- **Alignment is a sub-menu**, as on iPhone and iPad, not five items.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D30 (editor control), D33 (tables in version 1), D31 (undo model), D32 (Narrator).
