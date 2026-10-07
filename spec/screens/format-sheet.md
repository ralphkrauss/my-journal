---
id: format-sheet
title: Formatting (Format panel and popover)
features: [format-panel, inline-formatting, paragraph-styles, lists, checklists, list-indentation, block-quotes, code-blocks, horizontal-rules, tables, links, insert-image]
sources:
  - apps/apple/JournalApp/Views/FormattingPopover.swift
  - apps/apple/JournalApp/Views/MobileFormattingPresenter.swift
  - apps/apple/JournalApp/Views/MacFormattingButton.swift
  - apps/apple/JournalApp/Views/PopoverClickGuard.swift
  - apps/apple/JournalApp/Editor/WritingAccessory.swift
  - apps/apple/JournalApp/Editor/RichText.swift (EditorActions, FormattingSession)
  - apps/apple/JournalApp/Editor/FormattingState.swift
  - apps/apple/JournalApp/Editor/FormattingSessions.swift
  - docs/design/menus-and-popovers.md
  - docs/design/list-indentation-2026-10-04.md
  - docs/design/checklists-2026-10-03.md
  - docs/design/pre-release-ui-2026-09-27.md (§5, superseded in part)
---

# Formatting

## Purpose

One compact surface with every formatting choice, showing the styles at the selection, opened from the Formatting (Aa) button while writing. It feels as instant as a menu: it appears and disappears without animation and never takes the text's selection away.

## Entry points

- Computer: the Formatting toolbar button (symbol: text format, tooltip and label `library.toolbar.formatting`), or its entry in the toolbar's overflow menu.
- Phone and tablet: the Formatting (Aa) button in the writing controls (the keyboard accessory while writing, the bottom bar while reading).

Every command in it is also in the Format menu (computer, tablet) and most have shortcuts (`commands.md#editor`).

## Content

From top to bottom:

1. **Header** (phone panel only): the centred title `common.format` (a heading) and a round close button at the trailing edge (fixed 30 pt glyph in a 44 pt target), accessibility label `editor.format.close`.
2. **Inline row**: five equal toggles, each showing a sample glyph: **B** (bold) `library.menu.format.bold`, *I* `library.menu.format.italic`, U̲ `library.menu.format.underline`, S̶ `library.menu.format.strikethrough`, `<>` in monospace `library.menu.format.inlineCode`. A toggle that is on has an accent-tinted background; a mixed selection adds a small minus sign. Accessibility: the label as listed, value `editor.format.state.on`, `editor.format.state.off` or `editor.format.state.mixed`; tooltip (computer) the label.
3. Divider.
4. **Paragraph styles**, each drawn in its own style, with a checkmark on the current one:
   - `library.menu.format.heading` with level 1 (large bold), 2 and 3, then `library.menu.format.paragraph` (body).
   - Only when the selection has checklist items: `library.menu.format.markChecked`, or `library.menu.format.markUnchecked` when every selected item is checked.
   - `editor.format.moreHeadings` ▸ a menu of `library.menu.format.heading` with levels 4, 5 and 6.
5. Divider.
6. **Lists and quote**, each with a leading symbol: `library.menu.format.bulletedList`, `library.menu.format.numberedList`, `library.menu.format.checklist`, `library.menu.format.blockQuote`; checkmark on the current one (Checklist counts checked and unchecked items).
7. **Indent row**, always present: `library.menu.format.decreaseIndent` and `library.menu.format.increaseIndent`, icon-only buttons side by side, each dimmed where it doesn't apply.
8. Only while the caret is in a code block: `editor.format.exitCodeBlock`.
9. `library.menu.format.insert` ▸ a menu of `library.menu.format.insert.codeBlock`, `library.menu.format.insert.horizontalRule`, `library.menu.format.insert.table`, `library.menu.format.insert.link`, `library.menu.format.insert.image` (this order, which differs from the Format menu’s).

Rows are 44 pt tall on the phone and tablet and 30 pt on the computer; menus show an up-down chevron at the trailing edge. The computer popover is 250 pt wide and as tall as its rows. Disabled rows are dimmed to 30 % and show no hover highlight.

## Actions

| Action | Enabled | Result | Stays open? |
| --- | --- | --- | --- |
| Bold, Italic, Underline, Strikethrough, Inline Code | Not in a code block | Toggles the style on the current selection, or for the next typed text when nothing is selected (`flows/editing-rules.md` F-1 to F-6). | Yes |
| Heading 1–3, Paragraph, Heading 4–6 | Not in a table cell or code block | Restyles every paragraph the selection touches (P-1 to P-6). | No |
| Mark as Checked / Unchecked | Shown only with checklist items selected | C-1, C-2. | No |
| Bulleted List, Numbered List, Checklist, Block Quote | Not in a table cell or code block | P-1 to P-6. | No |
| Decrease Indent, Increase Indent | Per `flows/editing-rules.md` I-1 to I-15 | Moves list items a level, or indents code lines. | Yes |
| Exit Code Block | Caret in a code block | BI-4. | No |
| Insert ▸ Code Block, Horizontal Rule, Table | — | BI-1 to BI-3. | No |
| Insert ▸ Link… | — | Closes, then opens `screens/link-editor.md` for the selection there is now. | No |
| Insert ▸ Image… | — | Closes, then opens the image picker (`flows/insert-image.md`). | No |
| Close (phone), Escape (all), Formatting again | — | Closes; focus and selection stay in the text. | — |

While the surface is open, each command acts on the **current** selection of whichever text has focus (the body or a table cell), at the moment of the command. Typing, moving the selection and menu shortcuts don't void it. Checkmarks, toggles and the indent buttons follow the selection, refreshed at most once per run-loop turn.

## States

- **Not editable** (read-only entry, locked, library being replaced): the Formatting button is disabled; if the entry becomes uneditable while open, the surface closes without refocusing.
- **Another entry opened or the entry removed**: closes and applies nothing.
- **In a table cell**: paragraph styles, lists and More Headings are disabled; inline styles apply to the cell.
- **In a code block**: inline styles, paragraph styles, lists and More Headings are disabled; Exit Code Block appears.
- **In source view**: every command edits Markdown syntax instead (`flows/source-view.md`); the checkmarks and toggles read the syntax around the selection.
- **Rows don't fit** (phone panel at large text sizes or landscape): the rows scroll inside the panel, the scroll indicator flashes once on opening, and each opening starts at the top.

## Rules

- **No animation** on any platform: the surface is on screen in the next frame and gone in the next frame.
- **Computer (popover)**: one popover per window, kept between uses. Opened with the mouse, the text keeps keyboard focus; opened from the keyboard, the overflow menu or with VoiceOver, the popover takes focus on its first control (Bold). A click anywhere outside closes it and that click takes effect normally. A second click on the Formatting button closes it and never reopens it. Escape closes it, also while the text has focus (but not while an input method is composing). Closing with Escape, the button or a closing row returns focus to where it was; a click outside leaves focus where the person clicked.
- **Phone, and the tablet in compact width or at accessibility text sizes (panel)**: the panel replaces the on-screen keyboard as the text's input view. The text keeps focus, its caret or selection stays visible and undimmed, and the writing controls stay above the panel with Aa shown selected. Any input-method composition is committed first. The panel is exactly as tall as the keyboard it replaces (without the accessory bar), so the text doesn't move; without an on-screen keyboard (hardware keyboard, or none shown yet in that orientation) it is as tall as its rows, up to 40 % of the window in portrait and 50 % in landscape. Rotation keeps it open and recomputes its height. Opened while reading, writing starts at the remembered selection with the panel instead of the keyboard. Closing brings the keyboard back with the selection as it is.
- **Tablet in regular width (popover)**: anchored to the Aa that opened it, 300 pt wide, as tall as its rows; the text stays first responder and a tap in the text places the caret and closes the popover. Any selection change not made by a formatting command closes it. A change of width class (Split View, Stage Manager, rotation) closes it and the keyboard returns. A tap on Aa within 0.35 s after a tap outside closed it doesn't reopen it.
- Choosing Link… or Image… records the selection, closes the surface, then opens the link editor or picker.

## Accessibility

- VoiceOver, computer: opened by VoiceOver or Full Keyboard Access, focus goes to Bold (“Bold, off, button”); closing returns focus to the Formatting button.
- VoiceOver, phone: when the panel appears, a screen change moves focus to it (the “Format” heading). Aa has the Selected trait while it's open.
- Toggles expose On/Off/Mixed as values; the current paragraph style has the Selected trait. Indent buttons keep their labels when dimmed (“dimmed”).
- Rows grow with Dynamic Type on the phone and tablet; the close glyph keeps a fixed size.
- Escape closes the panel or popover from a hardware keyboard.

## Platform notes (Apple)

- Computer: AppKit popover from the toolbar item, non-animated, transient.
- Phone: input view in place of the keyboard, as Notes' Format panel.
- Tablet: popover in regular width; panel otherwise.
- The same content view is used everywhere; only the header (phone panel) differs.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
