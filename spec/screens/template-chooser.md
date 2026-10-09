---
id: template-chooser
title: Template chooser (Choose a Template, Use a Template…)
features: [template-chooser, template-suggestion]
sources:
  - apps/apple/JournalApp/Views/TemplateChooserView.swift
  - apps/apple/JournalApp/Views/TemplateSearchField.swift
  - apps/apple/JournalApp/Views/TemplateSuggestionView.swift
  - apps/apple/JournalApp/Model/TemplateSuggestion.swift
  - apps/apple/JournalApp/Editor/EditorPlaceholder.swift
  - apps/apple/JournalApp/AppCommands.swift
  - docs/design/new-entry-template-suggestion.md
  - docs/design/template-journal-choice-2026-10-03.md
  - docs/design/1-1-library-simplifications.md
---

# Template chooser

## Purpose

A quick, keyboard-friendly list of templates that fills the empty entry that is open. It is the one way to start from a template: New Entry gives a blank entry, and the chooser is opened from inside it. The chooser never creates an entry.

## Entry points

1. **“use a template”** in an empty entry: the body's placeholder reads “Start writing or [symbol] use a template” (screens/entry-editor), shown when the entry's body has no text or pictures, it can be edited, and an editable template exists. The link opens the chooser: a popover in regular width (iPad, Mac), a sheet in compact width (iPhone; half height, expandable).
2. **File ▸ Use a Template…** (Mac and iPad menu bar, also in the iPad ⌘-hold overlay; command `use-a-template`). Enabled exactly when the link is shown; dimmed, not hidden, otherwise. Opens as a sheet, at once (no animation). It exists so the action has a menu route for keyboard, Voice Control and screen reader users; iPhone has no menu bar and uses the link.

## Content

1. **Search field**, placeholder `library.search.templates`, focused when the chooser opens. No autocorrection or capitalization.
2. **List of templates** by name, each row at least 44 points tall. Two templates with the same name get `library.templateChooser.duplicateName`. The highlighted row uses the system's selection colors.
   - No templates: `library.entryList.empty.noTemplates`. No match: `library.entryList.empty.noResults`.
3. Close: on iPhone and iPad sheets, the title `library.templateChooser.title` with Cancel at the top left; on the Mac sheet, `common.cancel` at the bottom right. The popovers have no button (Escape or clicking outside closes them). The Mac popover is titled `library.templateChooser.popoverTitle`.

Only templates this version can edit are listed.

## Actions

- **Choose a template:** click or tap a row; or type to filter, move the highlight with Up and Down arrows, and press Return (Return works before anything is typed once a row is highlighted).
  - The template **fills the open entry** in place: its body, with formatting and images; the title is kept. It is one change, undone with one Undo ([flows/editing-rules](../flows/editing-rules.md)). The title takes focus if it's empty. The chooser closes.
  - If the entry's body is no longer empty (text typed or synced in meanwhile), nothing changes: the chooser closes and the general error alert shows `library.templateChooser.entryChanged`. Choosing again would fail the same way, so the list is not kept open.
  - If the entry itself was closed or deleted meanwhile, the chooser just closes.
- **Cancel / Escape:** closes at once, with or without search text. After Escape focus returns where it was.

## States

- **Errors (inline):** `library.templateChooser.templateGone` (the highlighted template left, or the last template was deleted: the list shows `library.entryList.empty.noTemplates`).
- **Reopened (Mac popover):** starts afresh: no search text, highlight or error.
- **Not offered:** with no template, or an entry that can't be edited or has text, the link isn't shown and the menu item is dimmed.

## Rules

- The search matches template names, case-insensitively.
- A template fills an entry only if its body is still empty when the choice is made, here and in storage. Nothing is ever created implicitly: there is no journal to pick, no "journal is gone" state and no rule about where a new entry would go, because the entry already has its journal.
- The chooser is the same list with the same keyboard behaviour in all its containers.

## Accessibility

- The link in the placeholder reads `library.templateChooser.useTemplate`; the menu item reads `library.menu.file.useTemplate`.
- The highlighted row has the selected trait.
- Keyboard order: search field, list, Cancel.
- `library.templateChooser.entryChanged` is shown in the general error alert (read like any alert); focus returns to the entry.

## Platform notes (Apple)

- **Mac:** File menu sheet 320 × 352 points; the link's popover 320 × 300, shown and closed without animation.
- **iPhone:** always a sheet (no menu bar). **iPad:** a popover in regular width, a sheet in compact width or from the File menu; a popover closes rather than turning into a sheet when the window's width changes.

## Open questions

- None.
