---
id: source-view
title: View source and View preview (Windows)
spec: flows/source-view.md
features: [source-view, source-only-entry]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/rich-edit-box
---

# View source and View preview (Windows)

Shows and edits the entry's Markdown as plain text, and switches back to the formatted preview, without changing anything by switching. Steps and rules are the spec's [source-view](../../../flows/source-view.md) and rules S-1 to S-7, SP-1 of [editing-rules](editing-rules.md).

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Toggle | View ▸ View source or View preview (the label swaps, `library.menu.view.viewSource` in preview, `library.menu.view.viewPreview` in source; icons Code E943 and Preview E8FF on the menu item). **No button in the editor header**: as in Notepad, the switch is in the View menu, and the header is the busiest bar | Disabled when the entry cannot be edited. View preview is also disabled, with `common.previewUnavailable` as its tooltip and `AutomationProperties.HelpText`, for an entry whose Markdown can only be shown as source |
| Source text | The same body control, its content replaced by the stored Markdown in Cascadia Mono at the body size, unstyled, with spell check and text prediction off, the decorations hidden, and the formatting bar's buttons acting on syntax (below) | One control so that undo continues across the switch (S-4). Source-only entries always open here, with the editing note `messages.unavailable.markdownSource` |
| Editing note | As [entry-editor](../screens/entry-editor.md) | |

## Steps on Windows

1. **View source** replaces the whole entry with its stored Markdown. The caret or selection moves to the same characters and the caret's line stays at the same height in the window (S-2); Narrator hears `editor.announce.source`. The Format menu, the formatting bar, Tab and Markdown as you type behave as the spec's table for source view: every format command edits syntax, Increase and Decrease indent and Exit code block are unavailable, Tab types a tab.
2. The person edits the Markdown as text; every change is saved as typed and the stored Markdown is exactly the text. Spelling marks and substitutions are off (SP-1).
3. **View preview** reads the Markdown and shows blocks; the caret moves to the same character; Narrator hears `editor.announce.preview`. If what was typed cannot be shown as a preview, the switch does not happen and the source stays.
4. Each switch is **one undo step** (named `editor.undo.viewSource` or `editor.undo.viewPreview` for announcements; the Edit menu says plain Undo, D31); Ctrl+Z returns to the previous view and text (S-4).

### Formatting in source view

The spec's table is followed unchanged: inline styles wrap or unwrap delimiters (`**`, `*`, `~~`, backticks, `<u>…</u>`), each line of a multi-line selection on its own; paragraph styles replace the line's marker and never stack; Mark as checked is available from the formatting bar's overflow menu only (the Format menu item and its shortcut are not); Insert Code block, Horizontal rule, Table, Link and Image place Markdown after the current line or replace the selection; pasting inserts plain text, or formatted text as Markdown (S-6). This logic is portable code over the source text and is rated App in [editing-rules](editing-rules.md).

Rules, as the spec: source view is per visit (every entry opens in preview unless it is source-only); switching never changes the stored Markdown (S-1); images in source view are their Markdown references and keep following the editor's width on return (S-7); tables, code blocks and lists survive switching exactly.

## Layout at each window width

| Width | What differs | Apple equivalent |
| --- | --- | --- |
| Large and medium | The header button swaps icon and label | Mac toolbar button |
| Small | The button is in the editor page's header or its overflow menu; View ▸ View source is in the title bar's More menu | iPhone reading bar |
| Text size | Source text follows the body size and Zoom, multiplied by the system text size; long lines wrap | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `view-source` | View menu | Ctrl+Shift+U | The entry is editable; View preview also needs Markdown the preview can show |
| `format-bold`, `format-italic`, `format-underline`, `format-strikethrough`, `format-inline-code` | Format menu; the formatting bar | as in commands.md | In source they edit syntax |
| `format-mark-checked` | The formatting bar's overflow menu | none in source | Menu item and shortcut unavailable in source view |

## Copy differences

Sentence case: "View source", "View preview" ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). No other differences.

## Accessibility

- The menu item's name is the action it will perform, so it changes with the mode; when preview is unavailable the disabled item's description says why (`common.previewUnavailable`).
- Mode changes are announced with `ImportantMostRecent` (`editor.announce.source`, `editor.announce.preview`).
- The source text is plain text, read by Narrator character by character in the usual way; the focus stays in the text across the switch.

## Different by design

- **The switch is a View-menu command only**, with no header button, as Notepad's is.
- **Same behaviour as Apple otherwise.** The one difference is mechanical: the same control holds both views so undo continues, and its spell check is switched off for the whole control while in source view, where Apple turns off substitutions and marks.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D30 (editor control), D31 (undo model).
