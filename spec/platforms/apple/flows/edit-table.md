---
id: edit-table
title: Edit a table (Apple)
spec: flows/edit-table.md
features: [tables]
devices: [iphone, ipad, mac]
status: verified
sources:
  - apps/apple/JournalApp/Editor/InlineTables.swift
  - apps/apple/JournalApp/Editor/InlineTableGridIOS.swift
  - apps/apple/JournalApp/Editor/InlineTableGridMac.swift
  - apps/apple/JournalApp/Editor/TableCellFormatting.swift
  - apps/apple/JournalApp/Editor/TablePresentation.swift
  - apps/apple/JournalApp/Editor/TableMenu.swift
  - apps/apple/JournalApp/Editor/InlineStyles.swift
  - apps/apple/JournalApp/Editor/NativeTableIntegration.swift
  - apps/apple/JournalApp/Editor/DocumentUndo.swift
  - apps/apple/JournalApp/Editor/JournalWritingView.swift
  - apps/apple/JournalApp/AppCommands.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/DocumentTable.swift
  - apps/apple/JournalTests/TableEditorTests.swift
screenshots:
  - screenshots/iphone/edit-table-default.png
  - screenshots/ipad/edit-table-default.png
  - screenshots/mac/edit-table-default.png
---

# Edit a table (Apple)

How the spec's [Edit a table](../../../flows/edit-table.md) is built. The text rules are in [editing-rules.md](editing-rules.md) (TB-1 to TB-7, BI-3, PA-3). The screen it happens in is [entry-editor.md](../screens/entry-editor.md).

## Controls

A table is not drawn by the entry's text view. The entry's `NSTextView` (Mac) or `UITextView` (iPhone, iPad), `JournalTextView`, holds one attachment character per table, sized to the table (`TablePresentation.render`). Over that character a grid view is placed, and every cell is its own small text view inside the grid. `InlineTables` (one per editor) owns the grids and moves them as the text lays out; the model is the entry's `JournalDocument`, whose table block is a `DocumentTable` (JournalCore).

| Element | Mac | iPhone and iPad |
| --- | --- | --- |
| Grid | `InlineTableGrid`, an `NSScrollView` with `hasHorizontalScroller` and `autohidesScrollers`; added as a subview of the entry's text view | `InlineTableGrid`, a `UIScrollView` with `isDirectionalLockEnabled` and no vertical indicator; added to the `JournalWritingView` container, beside the text view (not inside it), and positioned from the text view's coordinates |
| Cell | `TableCellTextView`, an `NSTextView` subclass (`isRichText`, `allowsUndo = false`, own container with zero line padding) | `TableCellTextView`, a `UITextView` subclass (`isScrollEnabled = false`, `adjustsFontForContentSizeCategory`, `undoManager` returns nil) |
| Grid lines | `TableCanvas` (`NSView`) draws one hairline grid in `separatorColor` behind the cells | `TableCanvas` (`UIView`) draws the same in `UIColor.separator` |
| Header row | Semibold by paragraph kind `tableHeader`; the stored runs are not bold (`TablePresentation.runs(_:header:)`) | Same. UIKit drops the block kind from typing attributes, so the row decides, not the typed text |
| Cell padding | 8 by 6 points, no minimum row height | 10 by 10 points, rows at least 44 points tall (touch size) |
| Structure menu | Appended to the cell's context menu (`menu(for:)`): the standard text items, a separator, then an `NSMenu` titled Table, built from `TableMenu.groups` (`menu(_:)`); none when the entry is read-only | Added by `textView(_:editMenuForTextIn:suggestedActions:)`: the system's suggested actions plus one `UIMenu` titled Table, built from `TableMenu.groups` (an inline `UIMenu` per group, so a divider sits before the Delete items); none when the entry is read-only |
| Format ▸ Table | `Menu("Table")` in `AppCommands.swift` with `TableMenuContent` (a SwiftUI rendering of `TableMenu.groups`), disabled unless the entry can be edited and a table cell has focus | The same `Menu`, from the same definition, in the iPad menu bar (the `#if os(macOS)` is gone and `EditorActions.tableAction` is wired on iOS too, `InlineTableGrid.applyToActiveCell`). iPhone has no menu bar, so its cell edit menu is the route |
| Writing controls while a cell has focus | Format popover and toolbar, as for the text | The same writing controls (its own `WritingAccessory` as the cell's `inputAccessoryView`) and the same Format panel as the text (the cell's `inputView` is `formattingInputView`) |

The structure commands are one definition, `TableMenu.groups(alignment:)` (`TableMenu.swift`): Add Row Below, Add Column After, an Alignment submenu (Left, Center, Right, with the column's current alignment checked; a column with none shows Left), a divider, then Delete Row, Delete Column and Delete Table (marked destructive). Titles are the text of `library.menu.format.table.addRow`, `library.menu.format.table.addColumn`, `editor.table.alignment` with `editor.table.alignment.left`, `editor.table.alignment.center` and `editor.table.alignment.right`, then `library.menu.format.table.deleteRow`, `library.menu.format.table.deleteColumn` and `library.menu.format.table.deleteTable`; the submenu's title is `library.menu.format.table`. Small adapters render it: an `NSMenu` (separator between the groups, a submenu item, `NSMenuItem.state` for the checkmark; the Mac does not colour destructive items), a `UIMenu` (inline groups, `UIAction.state`, `.destructive`) and a SwiftUI `Menu` (`TableMenuContent`: `Divider`, a `Toggle` per alignment for the checkmark, `Button` with `.destructive`). `EditorActions.tableAlignment` carries the focused cell's column alignment to the menu bar; the grid publishes it when the selection moves, after a structure change, and clears it when the cell loses focus.

All structure changes go through `DocumentTable.apply(_:row:column:)` (JournalCore), then `InlineTableGrid.changed` hands the new block to `InlineTables.commit`, which replaces the table's attachment in the text as one undo step. The returned flag says whether a table is left: if not, the table is removed and the caret leaves forward.

Cells show only what is in view. `InlineTables.synchronize` creates a grid for a table only if it is in the visible rect or a cell of it has focus, and a grid creates cell views only for cells in its viewport or with focus (`refreshCells`); the rest is the canvas lines and the attachment. A porter needs the same lazy scheme only for long tables.

Moving between cells (`InlineTableGrid.move`, the same code on both platforms apart from the key hook):

- Mac: `textView(_:doCommandBy:)` handles `insertTab` (next), `insertBacktab` (previous) and `insertNewline` (the cell below, which is the next index plus the column count).
- iPhone and iPad: `UIKeyCommand` for Tab and Shift-Tab (`TableCellTextView.keyCommands`), and `shouldChangeTextIn` turns a typed `"\n"` or `"\t"` into a move. A software keyboard has Return but no Tab, so there is no key for the next cell; tapping a cell is the way.
- Both: moving before the first or past the last cell calls `exit`, which puts the caret before the table (`range.location`) or on the line after it, and gives the focus back to the text view. An input method's marked text is committed first (`unmarkText`), and Tab, Return and the undo keys do nothing while it is composing.

Line breaks: `shouldChangeTextIn` replaces a typed or pasted line break by a space on both platforms (TB-2).

Formatting in a cell: the Format menu and panel call `InlineTableGrid.formatCell` first (`NativeEditor.Coordinator.perform`, `formattingSession`). Bold, Italic, Underline, Strikethrough and Inline Code use the same code as the body (`MarkdownEditing.typingCommand` for the next typed text, `MarkdownEditing.edit` over a selection, both through `InlineStyles`, the one rule of F-1); Link reuses `LinkInsertion`. Paragraph styles and focus are swallowed (return true) so they do nothing. The Format panel disables its paragraph section when `FormattingState.paragraph == "tableCell"` (`selectedCellStyle`). Edit Link and Remove Link are ignored in a cell.

States: with `canEdit` false, `InlineTableGrid.editable` is false and `cell.isEditable` is set to it, so cells can be selected and copied. Neither grid builds a structure menu then (`menu(_:)` and `editMenuForTextIn` return nil / the system's items only), `applyToActiveCell` does nothing, and the commit is skipped (`InlineTables.commit` returns unless `editable`). Source view shows the Markdown text with no grid (the attachment is not made).

Undo: both cell types hand the undo manager to the entry (`sharedUndo`). The cell's own manager is off (`allowsUndo = false` on the Mac, `undoManager` nil on iOS). ⌘Z and ⇧⌘Z are caught by `performKeyEquivalent` (Mac) and `UIKeyCommand` (iOS) and call the entry's `undo()` or `redo()`. Typing in a cell registers one step through `CellTypingUndo` (`DocumentUndo.swift`) that is replaced on each key until another change happens.

## Layout

- Width: the table attachment is as wide as the text view minus 20 points (`InlineTables.synchronize`, `max(40, host.bounds.width - 20)`). Columns share that width equally, each at least 7 times the text size (`TablePresentation.layout`). If the columns need more, the grid scrolls sideways inside its frame: `UIScrollView` with direction lock on iPhone and iPad, `NSScrollView` with an auto-hiding horizontal scroller on the Mac. On iPhone the capture shows this: three columns do not fit, the third is cut at the right edge.
- Row height: the tallest cell, wrapping long text, at least `minimumRowHeight` (44 on iPhone and iPad, none on the Mac).
- Text size: on the Mac `model.textSize` (View ▸ Zoom In, Zoom Out); on iPhone and iPad the Dynamic Type size scaled by the same zoom (`editorSize` in `RootView.swift`). Larger sizes make the rows taller and the minimum column wider, so more tables scroll sideways.
- iPad: the same grid at the width of the detail column. Stage Manager or Slide Over widths only change that width.
- Keyboard on iPhone and iPad: while a cell has focus the writing controls sit above the keyboard (`WritingAccessory`), and the cell is scrolled into view (`reveal`, `scrollRectToVisible`). The editor's bottom bar is hidden while a cell is being edited (the bar shows only when neither the text nor a cell is being edited).

## Commands and shortcuts

Placement and shortcuts are as in [commands.md](../commands.md); the Table rows are in its Table section.

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `insert-table` | Format ▸ Insert ▸ Table; Formatting surface; inserts `\|  \|  \|` with a delimiter row and one body row, then `InlineTables.focus` puts the caret in the first header cell | none | The entry is editable and the text has focus or a cell has it |
| `table-add-row` | Mac: Format ▸ Table, cell context menu. iPad: Format ▸ Table, cell edit menu ▸ Table. iPhone: cell edit menu ▸ Table | none | A cell has focus and the entry can be edited (the menu bar: the editor reports a table cell as focused) |
| `table-add-column` | as `table-add-row` | none | as above |
| `table-align-left` | Every place the list appears, as Table ▸ Alignment ▸ Left (checked when it is the column's alignment) | none | as above |
| `table-align-center` | as `table-align-left` | none | as above |
| `table-align-right` | as `table-align-left` | none | as above |
| `table-delete-row` | as `table-add-row` | none | as above |
| `table-delete-column` | as `table-add-row` | none | as above |
| `table-delete-table` | as `table-add-row` | none | as above |
| `table-next-cell` | In a cell | Tab | Always while a cell has focus; not while an input method composes |
| `table-previous-cell` | In a cell | Shift-Tab | as above |
| `table-cell-below` | In a cell | Return | as above |
| `undo` | Entry's history | ⌘Z | Cell focused and not composing |
| `redo` | Entry's history | ⇧⌘Z | as above |

Notes: the list and its order are the same in all three places (`TableMenu`); the inline format commands (`format-bold`, `format-italic`, `format-underline`, `format-strikethrough`, `format-inline-code`) work in a cell through the Format menu and its shortcuts (menu bar on the Mac and iPad) and through the Formatting surface. The cell does not register the text view's own key commands (`KeyboardFormatting`), so whether those keys reach a cell on an iPhone with a hardware keyboard is not verified. `format-paragraph`, the list commands and the heading commands do nothing in a cell. On the Mac, Tab and Return are `NSTextViewDelegate` commands, so Option-Tab or an input method may still behave as the text system decides.

## Copy differences

None. The Mac and iPhone/iPad menus use different subsets of the same keys (see Controls). The source writes the strings as literal English with no string catalog; every title equals the text of the key named above, and so do the cell labels of Accessibility.

## Accessibility

- Cells are accessibility elements in row order. Label: `editor.table.cell.header` ("Header, column n") for row 1, `editor.table.cell.row` ("Row r, column n") for the others; the row number counts the header as 1. The labels are set on every layout in `refreshCells`.
- iPhone and iPad: the grid itself is not an accessibility element (`isAccessibilityElement = false`), but its `accessibilityElements` are the cells, and its label is set to `editor.table.accessibilityLabel`. `JournalWritingView.updateAccessibility` lists the grids after the entry's text view, sorted by vertical position, then the checkboxes and pictures. So VoiceOver reaches a table after the whole text, not at its place in the text. Whether VoiceOver announces the grid's label is not verified.
- Mac: the scroll view carries `editor.table.accessibilityLabel`, and `canvas.setAccessibilityChildren` lists the cells in row order.
- Only cells in view exist as elements. Scrolling the grid or the entry creates and removes them.
- Increase Contrast and Reduce Transparency: the grid lines use the system separator colour, so the system setting applies; nothing else is drawn.
- Full Keyboard Access and hardware keyboards: Tab, Shift-Tab and Return work as above on iPad; the structure commands have no keyboard shortcut, so with a keyboard they are reached from Format ▸ Table in the menu bar (Mac and iPad), which has the same list as the cell menus.
- No announcement is made for a structure change; the caret stays in the same row and column (or the nearest one left), and focus moves to that cell.

## Differences between iPhone, iPad and Mac

- Grid host: iPhone and iPad put the grid beside the text view (in `JournalWritingView`), the Mac inside it. Either way the grid is placed from the text view's layout and moved on every layout change (`layoutChanged` calls `synchronizeTables`). The source does not say why the hosts differ; a port that draws text and cells in one scrolling surface does not need either arrangement.
- Format ▸ Table is in the Mac and iPad menu bars; iPhone has no menu bar and uses the cell's edit menu. The list, its order, the Alignment submenu and its checkmark are the same everywhere. The Mac does not colour the Delete items; iPhone and iPad mark them destructive.
- Row padding and minimum height are larger on iPhone and iPad for touch targets.
- Tab for the next cell needs a hardware keyboard on iPhone and iPad.

## Screenshots

| Device | Capture | State |
| --- | --- | --- |
| iPhone | ![Table in an entry on iPhone](../screenshots/iphone/edit-table-default.png) | An entry with a three-column table. The caret is not in a cell. The third column runs past the right edge and scrolls sideways. The bottom bar shows Formatting, Insert Image and View Source |
| iPad | ![Table in an entry on iPad](../screenshots/ipad/edit-table-default.png) | The same table in the detail column of the three-column layout. All columns fit, the last row wraps in its third cell |
| Mac | ![Table in an entry on Mac](../screenshots/mac/edit-table-default.png) | The same table in the Mac window. Compact rows, a semibold header, and the toolbar above the editor |

Captures show the table at rest; the structure menus are system menus and were not captured.

## Source files

View:

- `apps/apple/JournalApp/Editor/InlineTableGridMac.swift`, `InlineTableGridIOS.swift`: the grid, cells, key handling, structure menus and canvas for each platform.
- `apps/apple/JournalApp/Editor/InlineTables.swift`: creates, places and removes grids; replaces the table in the text on a change; moves the caret out of the table.
- `apps/apple/JournalApp/Editor/TablePresentation.swift`: column and row layout, padding, header style, the attachment.
- `apps/apple/JournalApp/Editor/TableCellFormatting.swift`: formatting commands inside a cell.
- `apps/apple/JournalApp/Editor/TableMenu.swift`: the one list of table commands, and its SwiftUI rendering for Format ▸ Table.
- `apps/apple/JournalApp/Editor/InlineStyles.swift`: the inline style rule shared with the entry's text.
- `apps/apple/JournalApp/AppCommands.swift`: Format ▸ Insert ▸ Table and Format ▸ Table (Mac, iPad).

Model:

- `apps/apple/JournalApp/Editor/NativeTableIntegration.swift`: wires `tableAction` for the menu bar (Mac, iPad) and `InlineTables` to the editor.
- `apps/apple/JournalApp/Editor/DocumentUndo.swift`: `CellTypingUndo`, the one-step typing undo.

Core:

- `apps/apple/Packages/JournalCore/Sources/JournalCore/DocumentTable.swift`: `DocumentTable`, `TableStructureAction` and `apply`, which implement TB-4.

Tests: `apps/apple/JournalTests/TableEditorTests.swift`.

## Open questions

None open. A43 (the Table items of the edit menus offered while the entry is read-only) is fixed: no menu is built for a read-only entry.
