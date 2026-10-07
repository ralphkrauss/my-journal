---
id: source-view
title: View Source and View Preview
features: [source-view, source-only-entry]
sources:
  - apps/apple/JournalApp/Editor/MarkdownEditing.swift
  - apps/apple/JournalApp/Editor/SourceFormatting.swift
  - apps/apple/JournalApp/Editor/MarkdownSelection.swift
  - apps/apple/JournalApp/Editor/ModeSwitchViewport.swift
  - apps/apple/JournalApp/Editor/NativeTableIntegration.swift (applyMarkdownEdit)
  - apps/apple/JournalApp/AppCommands.swift
  - apps/apple/JournalTests/SourceFormattingTests.swift
  - apps/apple/JournalTests/MarkdownEditorTests.swift
  - apps/apple/JournalTests/FormattingRuntimeTests.swift
  - docs/design/markdown-writing-revision.md
  - docs/design/notes-alignment-revision.md
---

# View Source and View Preview

## Purpose

Show and edit the entry's Markdown as plain text, and switch back to the formatted preview, without changing anything by switching.

## Start

- Computer: View ▸ View Source / View Preview (⌥⌘U) and the toolbar button.
- Phone, tablet: the last button of the writing controls (symbol: angle brackets for View Source, a document for View Preview), and View ▸ … ⌥⌘U in the tablet's menu bar. It works while reading too, without bringing up the keyboard.
- Labels: `library.menu.view.viewSource` / `library.menu.view.viewPreview`, the same in the View menu and on the toolbar and reading-bar buttons.

Enabled when the entry is editable. View Preview is disabled, with the help text `common.previewUnavailable`, for an entry whose stored Markdown can only be shown as source (`flows/editing-rules.md` M-12); such an entry always opens in source view with the note `messages.unavailable.markdownSource`.

## Steps

1. **View Source**: the whole entry is replaced by its stored Markdown, in the monospaced system font at the body size, with no styling. Any Formatting panel closes. The caret or selection moves to the same characters; the caret's line stays at the same height in the window (S-2). VoiceOver announces `editor.announce.source`.
2. The person edits the Markdown as text. Every change is saved as typed (the stored Markdown is exactly the text). Spelling and substitutions are off (SP-1).
3. **View Preview**: the Markdown is read and shown as blocks; the caret moves to the same character. VoiceOver announces `editor.announce.preview`. If the Markdown typed can't be shown as preview, the switch doesn't happen and the source stays.
4. Each switch is one undo step (`editor.undo.viewSource` / `editor.undo.viewPreview`); Undo returns to the previous view (S-4).

## Formatting in source view

Every Format command edits syntax; nothing is rendered (`SourceFormatting`, `SourceFormattingTests`):

| Command | Result |
| --- | --- |
| Bold, Italic, Strikethrough, Inline Code, Underline | Wraps the selection in `**…**`, `*…*`, `~~…~~`, `` `…` ``, `<u>…</u>`. Each line of a multi-line selection is wrapped on its own, after its block marker; spaces at the edges stay outside. Applying again removes the delimiters, whether or not they're selected, or with the caret inside. Italic inside bold adds emphasis (`***…***`). With no selection, an empty pair is inserted around the caret; pressing again removes it. |
| Paragraph styles and lists | Replace each touched line's marker (`# `…`###### `, `- `, `1. ` numbered 1, 2, 3 for several lines, `- [ ] `, `> `, none for Paragraph); markers never stack. A Paragraph directly after a list item or quote line gets a blank line so it doesn't continue it. On an empty line, the style starts its own block with blank lines around it as needed. |
| Mark as Checked / Unchecked | From the Formatting surface: toggles `[ ]`/`[x]` on the touched checklist lines, all checked unless all were checked. The Format menu item and its shortcut are unavailable in source view. |
| Insert Code Block | After the current line (never splitting it), with blank lines around it; the caret inside. With lines selected, fences them instead. |
| Insert Horizontal Rule, Table | After the current line, with blank lines around it; the caret after the rule, or in the table's first cell. |
| Insert Link | Replaces the selection with `[text](address)`: the text is Add Link's Text field, or the selection, or the address when both are empty; an address with spaces, brackets or angle brackets is wrapped in `<…>`. The caret goes after it. |
| Insert Image | The image's Markdown on its own line after the current line. |
| Indent, Increase/Decrease Indent, Exit Code Block | Unavailable; Tab types a tab. |
| Markdown as you type | Off. |

On an empty entry in source view, styles and inline commands start the Markdown (`# `, `****`), and typing continues in source (`SourceFormattingTests.testEmptySourceFormattingKeepsMarkdownAndInsertionPoint`).

## Rules

- Source view is per visit: opening an entry shows the preview unless the entry is source-only.
- Switching never changes the stored Markdown (S-1).
- Pasting in source view inserts plain text, or formatted text as Markdown (S-6).
- Images in source view are their Markdown references; switching back shows them at the editor's width (S-7).
- Tables, code blocks and lists survive switching exactly (`TableEditorTests.testNativeTableCellsShareBodyUndoAndSurviveSourceSwitch`, `MarkdownEditorTests.testSourceDeletionAndComplexFormattingDoNotFlattenContent`).

## Accessibility

- The toolbar or bar button's label is the action it performs (View Source or View Preview), and the Mac tooltip says why when preview isn't available.
- Mode changes are announced (high priority on the computer).

## Platform notes (Apple)

- Same behaviour on every platform.

## Open questions

- None.
