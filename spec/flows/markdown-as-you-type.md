---
id: markdown-as-you-type
title: Markdown as you type
features: [markdown-as-you-type]
sources:
  - apps/apple/JournalApp/Editor/MarkdownShortcuts.swift
  - apps/apple/JournalApp/Editor/MarkdownShortcutEditing.swift
  - apps/apple/JournalApp/Views/SettingsView.swift (generalSettings)
  - apps/apple/JournalTests/MarkdownShortcutTests.swift
  - docs/design/owner-decisions-2026-09-25.md (§4)
  - docs/design/editor-fixes-2026-10-04.md
---

# Markdown as you type

## Purpose

Let people who know Markdown format while typing, as in Notes, Bear and Google Docs: a marker typed at the start of a line becomes the formatting it stands for, and is easy to take back.

## Start

Typing in the body, in preview (not source view), with **Format Markdown as You Type** on (Settings ▸ General; on by default; specified in `screens/settings-general.md`).

## Steps

1. The person types a marker at the start of a plain paragraph, then a space: `- `, `* `, `+ `, `1. ` (any 1–9 digit number, or `1) `), `[ ] `, `[] `, `[x] `, `> `, or `# ` to `###### `.
2. The space is typed (one undo step), then the line becomes a bulleted list item, a numbered item starting at that number, a checklist item (checked for `[x] `), a block quote or Heading 1–6 (a second undo step). The marker's characters are removed; any text already after the caret on that line becomes the new block's text; the caret is at the start of that text, and typing continues in the new style.
3. VoiceOver announces the new style (`editor.announce.bulletedList`, `editor.announce.numberedList`, `editor.announce.checklist`, `editor.announce.blockQuote`, `editor.announce.heading`).
4. **Taking it back**: Backspace straight after the conversion gives back exactly what was typed, as a plain line (an undo step named `editor.undo.typing`), and that line isn't converted again while typing continues. Undo instead gives back the typed marker and space (first Undo, named after the style), then removes the space (second Undo, `editor.undo.typing`).
5. **Blocks on Return**: Return at the end of a plain line that is exactly `---`, `***` or `___` turns it into a horizontal rule (announced `editor.announce.horizontalRule`, undo step `editor.undo.horizontalRule`); a line that is exactly ` ``` ` optionally followed by a language name turns into an empty code block with the caret inside (announced `editor.announce.codeBlock`, undo step `editor.undo.codeBlock`).

Full rules and tests: `flows/editing-rules.md` K-1 to K-6, N-12.

## When it doesn't apply

- The setting is off: everything stays as typed.
- In source view, a heading, a list item, a quote, a code block or a table cell.
- While an input method composes, and for pasted text (including a pasted space).
- A marker followed by anything other than a space, or a marker in the middle of a line.

## Rules

- A burst of keys typed faster than the screen updates (“- Milk⏎Eggs”) keeps every letter in order, in the right item (N-12).
- The conversion happens within the same key press; nothing is left to convert later.

## Accessibility

- Every conversion is announced, since the change isn't otherwise visible to VoiceOver users.

## Platform notes (Apple)

- Identical on all platforms, with on-screen and hardware keyboards.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
