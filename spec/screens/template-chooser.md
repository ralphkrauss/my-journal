---
id: template-chooser
title: Template chooser (Choose a Template, Use a Template…)
features: [template-chooser, new-entry-from-template, template-suggestion]
sources:
  - apps/apple/JournalApp/Views/TemplateChooserView.swift
  - apps/apple/JournalApp/Views/TemplateSearchField.swift
  - apps/apple/JournalApp/Views/TemplateSuggestionView.swift
  - apps/apple/JournalApp/Model/TemplateSuggestion.swift
  - apps/apple/JournalApp/Editor/EditorPlaceholder.swift
  - docs/design/new-entry-template-suggestion.md
  - docs/design/template-journal-choice-2026-10-03.md
---

# Template chooser

## Purpose

A quick, keyboard-friendly list of templates to start an entry from, or to fill an empty entry with.

## Entry points

1. **File ▸ New Entry from Template…** (Mac and iPad menu bar; command `new-entry-from-template`). Enabled when New Entry is possible and there is at least one template. Opens as a sheet, at once (no animation).
2. **“use a template”** in an empty entry: the body's placeholder reads “Start writing or [symbol] use a template” (screens/entry-editor), shown when the entry's body has no text or pictures, it can be edited, and an editable template exists. The link opens the chooser: a popover in regular width (iPad, Mac), a sheet in compact width (iPhone; half height, expandable).

## Content

1. **Journal picker** (only for entry point 1, opened outside a journal, with two or more journals in use): label `library.templateChooser.journal` and a menu showing the journal; options are the journals in use in the sidebar order (`common.untitledJournal`). Starts on the journal last opened on this device, else the Default Journal.
2. **Search field**, placeholder `library.search.templates`, focused when the chooser opens. No autocorrection or capitalization.
3. **List of templates** by name, each row at least 44 points tall. Two templates with the same name get `library.templateChooser.duplicateName`. The highlighted row uses the system's selection colors.
   - No templates: `library.entryList.empty.noTemplates`. No match: `library.entryList.empty.noResults`.
4. Error text in red, when there is one.
5. Progress indicator while the entry is created.
6. Close: on iPhone and iPad sheets, the title `library.templateChooser.title` with Cancel at the top left; on the Mac sheet, `common.cancel` at the bottom right. The popovers have no button (Escape or clicking outside closes them). The Mac popover is titled `library.templateChooser.popoverTitle`.

Only templates this version can edit are listed.

## Actions

- **Choose a template:** click or tap a row; or type to filter, move the highlight with Up and Down arrows, and press Return (Return works before anything is typed once a row is highlighted).
  - When the open entry's body is empty (whitespace at most, no pictures) and, with the Journal picker, the entry is in the picked journal: the template **fills that entry** in place (its body; the title is kept), as one change. The title takes focus if it's empty. This is always the case for entry point 2.
  - Otherwise a **new entry** is created from the template in the target journal (the shown journal, or the picked one), opened in that journal with its title focused.
  - The chooser closes.
- **Cancel / Escape:** closes at once, with or without search text, unless an entry is being created. After Escape focus returns where it was.

## States

- **Busy:** everything disabled while creating; not dismissable.
- **Errors (inline):** `library.templateChooser.templateGone` (the highlighted template left), `library.merge.destinationGone` (the picked journal left; the picker then switches to the Default Journal), `library.templateChooser.journalGone` (the journal shown left), or any error from creating the entry.
- **Reopened (Mac popover):** starts afresh: no search text, highlight or error.

## Rules

- The search matches template names, case-insensitively.
- A picked journal that disappears stays picked until a template is chosen, so a quick Return can't misfile the entry.
- A template fills an entry only if its body is still empty when the choice is made, here and in storage; otherwise a new entry is created.

## Accessibility

- The link in the placeholder reads `library.templateChooser.useTemplate`.
- The highlighted row has the selected trait.
- VoiceOver reads the picker as “Journal, ‹name›” on both platforms.
- Keyboard order: picker, search field, list, Cancel.

## Platform notes (Apple)

- **Mac:** File menu sheet 320 points wide (taller with the picker); the link's popover 320 × 300, shown and closed without animation.
- **iPhone:** always a sheet. **iPad:** a popover in regular width, a sheet in compact width or from the File menu; a popover closes rather than turning into a sheet when the window's width changes.

## Open questions

- None.
