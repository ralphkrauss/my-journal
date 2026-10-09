---
id: edit-table
title: Edit a table
features: [tables]
sources:
  - apps/apple/JournalApp/Editor/InlineTables.swift
  - apps/apple/JournalApp/Editor/InlineTableGridIOS.swift
  - apps/apple/JournalApp/Editor/InlineTableGridMac.swift
  - apps/apple/JournalApp/Editor/TableCellFormatting.swift
  - apps/apple/JournalApp/Editor/TablePresentation.swift
  - apps/apple/JournalApp/AppCommands.swift (Format ▸ Table)
  - apps/apple/Packages/JournalCore/Sources/JournalCore/DocumentTable.swift
  - apps/apple/JournalTests/TableEditorTests.swift
  - apps/apple/JournalTests/EditorChangeTests.swift
---

# Edit a table

## Purpose

Write in a Markdown (GitHub) table directly in the entry: type in cells, move between them, add and remove rows and columns, and align columns.

## Start

- Insert ▸ Table (Format menu, Formatting surface, or `|  |  |` Markdown pasted or written in source): a 2-column table with a header row and one body row; the caret goes to the first header cell.
- A click or tap in any cell of an existing table.

## Steps

1. Typing in a cell edits that cell. The header row is drawn semibold. Long text wraps for display only; a cell holds one line, so typed or pasted line breaks become spaces.
2. **Moving**: Tab → next cell (left to right, then the next row); Shift-Tab → previous cell; Return → the cell below. Past the last cell, the caret leaves the table to the line after it; before the first cell, it leaves to just before the table.
3. **Formatting in a cell**: Bold, Italic, Underline, Strikethrough, Inline Code (menu, shortcuts, Formatting surface) apply to the cell's selection or typing by the one rule of `flows/editing-rules.md` F-1; paragraph styles and lists are disabled.
4. **Structure**: one list of commands, in one order, wherever it appears (`commands.md`, Table): Add Row Below (`library.menu.format.table.addRow`), Add Column After (`library.menu.format.table.addColumn`), Alignment (`editor.table.alignment`) ▸ Left, Center, Right (`editor.table.alignment.left`, `editor.table.alignment.center`, `editor.table.alignment.right`), a divider, then Delete Row, Delete Column and Delete Table (`library.menu.format.table.deleteRow`, `library.menu.format.table.deleteColumn`, `library.menu.format.table.deleteTable`; destructive where the platform colours destructive items). The column's current alignment is checked in the Alignment submenu; a column with none shows Left checked.
   - Computer: the cell's context menu has the standard text items, then a separator and `library.menu.format.table` ▸ the list. Format ▸ Table ▸ has the same list, enabled only while a cell is being edited.
   - Tablet: the cell's edit menu (shown on selection or a tap on the caret) has the system's items, then `library.menu.format.table` ▸ the list. Format ▸ Table ▸ in the menu bar has the same list, so a hardware keyboard, Full Keyboard Access, Switch Control and Voice Control have a route that does not need the edit menu; it is enabled only while a cell is being edited.
   - Phone: the cell's edit menu, as on the tablet. There is no menu bar.
5. After a structure change the caret stays in the same row and column (or the nearest one left). Deleting the last row or column, or the table, removes the table and the caret goes to the line after it.
6. Undo: typing in one cell is one step until anything else changes; each structure change is one step; both share the entry's history (⌘Z in a cell undoes in the entry).

Rules and tests: `flows/editing-rules.md` TB-1 to TB-7, BI-3, PA-3.

## States

- Read-only entry: cells can be selected and copied but not edited; no Table menu is built in the cell menu, and Format ▸ Table is disabled.
- Source view: the table is its Markdown text.
- Only cells in view (and a cell being edited) are live text fields; the rest are drawn.

## Rules

- Columns share the editor's text width equally, each at least 7 × the text size wide; when more columns than that fit, the table scrolls sideways inside its frame. Rows are as tall as their tallest cell.
- Column alignment is stored in the Markdown delimiter row (`:--`, `:-:`, `--:`); cells, escaped pipes and the source around the table are kept (TB-6).
- Copying a selection that includes a table gives other apps its Markdown as plain text (PA-3).

## Accessibility

- The table is a container labelled `editor.table.accessibilityLabel`; each cell is an element labelled `editor.table.cell.header` (row 1) or `editor.table.cell.row`, in row order.

## Platform notes (Apple)

- The one list is rendered by each platform's own menu type (a context menu and a menu bar item on the Mac; an edit-menu submenu on iPhone and iPad; the menu bar on iPad). The order, titles, the Alignment submenu and its checkmark are the same.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
