---
id: format-sheet
title: Formatting (Windows)
spec: screens/format-sheet.md
features: [format-panel, inline-formatting, paragraph-styles, lists, checklists, list-indentation, block-quotes, code-blocks, horizontal-rules, tables, links, insert-image]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar-flyout
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/toggles
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/rich-edit-box
---

# Formatting (Windows)

Every formatting choice, showing the styles at the selection. Behaviour, rules and copy keys are the spec's [format-sheet](../../../screens/format-sheet.md); the commands act through the rules of [flows/editing-rules](../flows/editing-rules.md) on the [entry editor](entry-editor.md)'s control. The Format menu has every command too ([4.1](../platform.md#41-where-the-menu-bar-sits)) and stays the complete surface.

**Windows does not use a popover for this.** Notepad's formatting update (2025), Word, OneNote and the Mail and Outlook compose windows show formatting as a bar between the menus and the text, with a way to hide it, and select-then-format as a mini-toolbar over the selection; a popover with a column of buttons is Apple's Notes idiom. A flyout costs two clicks for every bold, hides the paragraph styles behind a focus mode that can swallow the first click, and is the most complex surface in the editor. So the Windows surface is two things: a **formatting bar** that can be shown or hidden, and the text control's **selection mini-toolbar**. This is the review's recommendation and the draft default of D20.

## Controls

### The formatting bar

A `CommandBar` under the editor header (row 0 of [entry-editor](entry-editor.md#page-structure)), full pane width, `DefaultLabelPosition` Collapsed (icons with tooltips), `IsDynamicOverflowEnabled` true, `IsOpen` false. It is **hidden by default** (the product asks for no persistent visual clutter around the writing), shown by the Formatting toggle button of the editor header or View ▸ Formatting, and the choice is remembered on this device. Buttons set `AllowFocusOnInteraction` to false, so a click leaves the caret and the selection in the text, and every button acts on the **current** selection of whichever text has focus (the body or a table cell) at the moment of the click. This replaces the focus-handling machinery a flyout needed.

Items, leading to trailing:

| Spec element | Control | Notes |
| --- | --- | --- |
| Paragraph styles | A `DropDownButton` whose label is the current style (`library.menu.format.paragraph` or `library.menu.format.heading` with its level), with a `MenuFlyout` of `RadioMenuFlyoutItem`s in one group: `library.menu.format.paragraph`, then `library.menu.format.heading` for levels 1 to 6; levels 1 to 3 are drawn in their own size and SemiBold, 4 to 6 in the body size | The current style is checked. Replaces the spec's paragraph rows and the More headings sub-menu (`editor.format.moreHeadings` is not shown). Shortcuts are shown in the items |
| Inline row | Five `AppBarToggleButton`s, icon only: Bold (E8DD), Italic (E8DB), Underline (E8DC), Strikethrough (EDE0), Inline code (Code E943). Names `library.menu.format.bold`, `library.menu.format.italic`, `library.menu.format.underline`, `library.menu.format.strikethrough`, `library.menu.format.inlineCode`; tooltip the name plus its shortcut | `IsThreeState` is on so a mixed selection shows the indeterminate visual; a click always sets on or off, never mixed. Narrator hears the toggle state, so `editor.format.state.on`, `editor.format.state.off` and `editor.format.state.mixed` are not used |
| Link | `AppBarButton`, icon Link (E71B), `library.menu.format.insert.link` | Records the selection and opens the [link dialog](link-editor.md); Ctrl+K does the same |
| Lists and quote | Four `AppBarToggleButton`s: `library.menu.format.bulletedList` (BulletedList E8FD), `library.menu.format.numberedList` (a Fluent UI System icon, [23](../platform.md#23-icons)), `library.menu.format.checklist` (CheckList E9D5), `library.menu.format.blockQuote` (LeftDoubleQuote E9B2) | On for the current one (Checklist counts checked and unchecked items) |
| Indent | Two `AppBarButton`s, icon only: `library.menu.format.decreaseIndent`, `library.menu.format.increaseIndent` (Fluent UI System icons) | Each disabled where it does not apply, keeping its name |
| Insert | A `DropDownButton` `library.menu.format.insert` with a `MenuFlyout`: `library.menu.format.insert.codeBlock`, `library.menu.format.insert.horizontalRule`, `library.menu.format.insert.table`, `library.menu.format.insert.link`, `library.menu.format.insert.image` | This order, which differs from the Format menu's, as in the spec |
| Overflow (the secondary commands) | `library.menu.format.markChecked`, or `library.menu.format.markUnchecked` when every selected item is checked; `editor.format.exitCodeBlock` | A bar does not change shape, so Mark as checked is always present here and disabled unless the selection has checklist items; Exit code block is disabled unless the caret is in a code block. Both are in the Format menu and have shortcuts |

Nothing in the bar is a dialog or opens a second surface except the two drop-downs and the Link dialog. As the window narrows the bar's trailing buttons move into its overflow menu; at 225% text size it shows icons and overflow only.

### The selection mini-toolbar

On a selection the text control's own command flyout (`TextCommandBarFlyout`, through `SelectionFlyout` and `ContextFlyout` of `RichEditBox`; it appears the way the system's does, on touch or pen selection and on right-click) is **extended with Bold, Italic and Link** as primary commands beside the standard Cut, Copy and Paste; spelling suggestions stay where the control puts them. The three buttons are the same commands as the bar's, so toggles show their state, and they work whether or not the bar is shown. It is the short mouse and touch path for the commonest formatting; the bar and the Format menu hold the rest. If the editor is a `WebView2` editor (Spike B), the same three commands are an in-page toolbar that follows the selection with the same look. In a code block, the mini-toolbar shows no formatting commands.

### State by place

- **In a table cell:** the paragraph-style drop-down, list and quote buttons and Exit code block are disabled; inline styles apply to the cell.
- **In a code block:** inline styles, paragraph styles, lists and quote are disabled; Exit code block (overflow) is enabled.
- **In source view:** every command edits Markdown syntax ([flows/source-view](../flows/source-view.md)); toggles read the syntax around the selection.
- **Not editable** (read-only entry, locked, library being replaced): the bar stays as it is and every button is disabled; the Formatting button stays enabled so the bar can still be shown or hidden.
- **Another entry opened or the entry removed:** nothing applies; the bar follows the new selection.
- Toggles, checks and the indent buttons follow the selection, refreshed at most once per layout pass.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The bar spans the editor pane under the header; trailing buttons go to overflow as the pane narrows | Mac and iPad popover |
| Small | The bar is on the entry's page under the header, with the same items; most go to overflow, so the selection mini-toolbar and the Format menu (the title bar's More button) are the main routes | iPhone panel |
| 200% text size or more | Icons and overflow only; the bar is as tall as its buttons need and scrolls nothing | Dynamic Type growth |

Buttons are 32 epx for mouse and keyboard and 40 epx when the pointer is touch or pen.

## Commands and shortcuts

Shortcuts and menu placement are in [commands.md](../commands.md) (Editor ▸ Format); the bar adds only its own behaviour.

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `show-formatting` | Toggle button in the editor header; View ▸ Formatting | as in commands.md | The open item can be edited for the buttons; the toggle itself is always enabled |
| `format-bold`, `format-italic`, `format-underline`, `format-strikethrough`, `format-inline-code` | Inline buttons (Bold and Italic also in the mini-toolbar) | as in commands.md | Not in a code block |
| `format-paragraph`, `format-heading-1`, `format-heading-2`, `format-heading-3`, `format-heading-4`, `format-heading-5`, `format-heading-6` | The paragraph-style drop-down | as in commands.md (Ctrl+Shift+0 to 6) | Not in a table cell or code block |
| `format-mark-checked` | Overflow menu | as in commands.md | Only with checklist items selected |
| `format-bulleted-list`, `format-numbered-list`, `format-checklist`, `format-block-quote` | List and quote buttons | as in commands.md | Not in a table cell or code block |
| `format-increase-indent`, `format-decrease-indent` | Indent buttons | as in commands.md | By rules I-1 to I-15 |
| `exit-code-block` | Overflow menu | Down | Caret in a code block |
| `insert-code-block`, `insert-horizontal-rule`, `insert-table`, `insert-link`, `insert-image` | The Insert drop-down; the Link button; Format ▸ Insert | Ctrl+K for the link | The open item can be edited |
| `close-formatting` | Not offered | — | A bar has nothing to close; the Formatting toggle hides it |

Keyboard: F6 and Shift+F6 move between the navigation pane, the list, the bar and the editor; inside the bar the arrow keys move between buttons, Tab leaves the bar, Space or Enter acts. After a command the focus stays where it was in the text when the pointer was used; when the keyboard moved focus into the bar, a command returns focus to the text. Esc is not bound to the bar.

## Copy differences

Sentence case on every label ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Inline code", "Bulleted list", "Numbered list", "Block quote", "Mark as checked", "Decrease indent", "Increase indent", "Exit code block", "Code block", "Horizontal rule". `common.format`, `editor.format.close` and `editor.format.moreHeadings` are not shown on Windows (there is no panel header, no close button and no More headings sub-menu). No other differences, and no new strings: the View menu item uses `library.toolbar.formatting`.

## Accessibility

- The bar is a named toolbar (`library.toolbar.formatting`), so Narrator announces it on entry; the Formatting toggle button has the same name and its toggled state.
- Toggles expose on, off and mixed through the toggle pattern; the current paragraph style is the checked item and the drop-down's name includes it; indent buttons keep their names when disabled.
- Every icon-only button has `AutomationProperties.Name` and a tooltip with the shortcut (`AutomationProperties.AcceleratorKey` too).
- Icons are decorative; toggled states use the accent fill plus a visual state that survives contrast themes (the system highlight pair), never colour alone.
- The bar is reachable by keyboard (F6) and Narrator without a pointer; because its buttons do not take focus on click, the Narrator user in the text hears the result as a notification (`editor.announce.*`), not as a change of focus.
- Rows grow with text size; nothing is truncated.

## Different by design

- **A bar, not a popover.** The Apple popover (a column of toggles in a Mac popover or an iPhone panel in place of the keyboard) is replaced by the Windows pattern: a toggleable bar under the menus and a selection mini-toolbar. One click per bold instead of two, no focus mode, no first click swallowed.
- **Hidden by default, remembered per device**, so writing stays primary and uncluttered; the Format menu and shortcuts are always there.
- **Paragraph styles are one drop-down**, as in Notepad and Word, instead of a column of rows with a More headings sub-menu.
- **Mark as checked and Exit code block live in the overflow menu**, always present but disabled when they do not apply, because a bar does not change shape.
- **No animation work.** The spec says the Apple surface never animates; a bar that is shown or hidden does so with no transition, whatever the system animation setting is.
- **Insert order** differs from the Format menu's, as in the spec; this is kept on purpose.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D20 (formatting bar and mini-toolbar), D30 (editor control).
