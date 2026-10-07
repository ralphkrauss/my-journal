---
id: new-entry
title: New entry (New Entry, New Blank Entry, from a template)
features: [new-entry, new-blank-entry, new-entry-from-template, template-suggestion, journal-default-template, default-journal]
sources:
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/TemplateSuggestion.swift
  - apps/apple/JournalApp/Views/EntryCreationActions.swift
  - apps/apple/JournalApp/Views/Mac/RootView+MacWindow.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/AppCommands.swift
  - docs/design/default-journal.md
  - docs/design/new-entry-template-suggestion.md
  - docs/design/template-journal-choice-2026-10-03.md
---

# New entry

## Purpose

Starts writing: one New Entry command everywhere, filed in a predictable journal, optionally from a template.

## Entry points

| Command | Where | Shortcut |
| --- | --- | --- |
| New Entry (`new-entry`) | Mac toolbar; iPhone and iPad bottom bars; File menu; empty list action | ⌘N |
| New Blank Entry (`new-blank-entry`) | File menu (Mac, iPad) | ⇧⌘N |
| New Entry from Template… (`new-entry-from-template`) | File menu (Mac, iPad) | — |
| New Entry In ▸ / New Entry from Template | a template's context menu or Entry Actions ([screens/templates](../screens/templates.md)) | — |
| use a template | the placeholder of an empty entry ([screens/template-chooser](../screens/template-chooser.md)) | — |

## Steps

1. **Which journal.** The journal whose entries are shown. Anywhere else (All Entries, Templates, Recently Deleted, Unavailable Journals, nothing selected, the iPhone Journals screen) the **Default Journal**: the one chosen in Settings (screens/settings-general), else the oldest journal in use (normally the one created with the library).
2. **No journal in use:** the toolbar and bottom-bar New Entry opens New Journal ([screens/journals](../screens/journals.md)) and, once it's created, starts the entry there. File ▸ New Entry is disabled in this state.
3. The open entry is saved first. If that fails, nothing is created and the error alert explains.
4. **What it contains:**
   - New Entry: the journal's Default Template's text and formatting, or an empty entry when it has none (or its template is in Recently Deleted).
   - New Blank Entry: always empty.
   - From a template: that template's current text.
5. **Where it shows:** the list switches to the target journal (closing what was open there), unless All Entries is shown, where the list stays on All Entries with the entry's journal label. The search is cleared. The new entry is dated now, appears at the top of its month, opens, and its title gets keyboard focus. On iPhone the stack becomes [journal, entry], so Back shows where it was filed.
6. Nothing is announced; there's no message.

## States

- **Disabled:** while locked, while the library is being replaced, and (File ▸ New Entry, New Blank Entry, New Entry from Template…) without a journal in use. New Entry from Template… also needs a template. The iPhone and iPad button is also disabled while it's already creating.
- **Error:** the general error alert with the error.
- **Interrupted:** choosing another collection or entry while it's being created cancels showing it; an entry already stored stays.

## Rules

- An entry is kept once created, even if left empty (owner decision, 30 September 2026); it never disappears on its own.
- The empty entry's placeholder offers “use a template” when templates exist; choosing one fills that entry rather than creating another.
- New Entry with a template selected in Templates still uses the Default Journal's default template, not the selected one; New Entry In ▸ is the way to use a selected template.
- Starting an entry ends the iPhone and iPad Journals edit mode.

## Accessibility

- Focus moves to the new entry's title.

## Platform notes (Apple)

- **Mac:** New Entry is in the toolbar over the editor; ⌘N reopens the journal window if it was closed.
- **iPhone:** New Entry (square and pencil, icon only) in the bottom bar of the Journals screen and of every list. From the Journals screen it opens the Default Journal's list first.
- **iPad:** the same bottom-bar button in the list column, and the File menu commands with a keyboard.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
