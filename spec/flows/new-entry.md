---
id: new-entry
title: New entry (New Entry, then a template if wanted)
features: [new-entry, template-suggestion, default-journal]
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
  - docs/design/1-1-library-simplifications.md
---

# New entry

## Purpose

Starts writing: one New Entry command everywhere, always an empty entry, filed in a predictable journal. A template is used afterwards, from inside the empty entry.

## Entry points

| Command | Where | Shortcut |
| --- | --- | --- |
| New Entry (`new-entry`) | Mac toolbar; iPhone and iPad bottom bars; File menu; empty list action | ⌘N |
| Use a Template (`use-a-template`), after New Entry | the placeholder of the empty entry, and File ▸ Use a Template… on a computer and a tablet with a keyboard ([screens/template-chooser](../screens/template-chooser.md)) | — |

## Steps

1. **Which journal.** The journal whose entries are shown. Anywhere else (All Entries, Templates, Recently Deleted, Unavailable Journals, nothing selected, the iPhone Journals screen) the **Default Journal**: the one chosen in Settings (screens/settings-general), else the oldest journal in use (normally the one created with the library).
2. **No journal in use:** the toolbar and bottom-bar New Entry opens New Journal ([screens/journals](../screens/journals.md)) and, once it's created, starts the entry there. File ▸ New Entry is disabled in this state.
3. The open entry is saved first. If that fails, nothing is created and the error alert explains.
4. **What it contains:** nothing; the entry is empty.
5. **Where it shows:** the list switches to the target journal (closing what was open there), unless All Entries is shown, where the list stays on All Entries with the entry's journal label. The search is cleared. The new entry is dated now, appears at the top of its month, opens, and its title gets keyboard focus. On iPhone the stack becomes [journal, entry], so Back shows where it was filed.
6. Nothing is announced; there's no message.
7. **To start from a template**, choose “use a template” in the empty entry (or File ▸ Use a Template…); the template fills that entry ([screens/template-chooser](../screens/template-chooser.md)).

## States

- **Disabled:** while locked, while the library is being replaced, and (File ▸ New Entry) without a journal in use. The iPhone and iPad button is also disabled while it's already creating.
- **Error:** the general error alert with the error.
- **Interrupted:** choosing another collection or entry while it's being created cancels showing it; an entry already stored stays.

## Rules

- An entry is kept once created, even if left empty (owner decision, 30 September 2026); it never disappears on its own.
- New Entry is predictable: it never depends on a template, a journal setting or what is selected in Templates. (A journal's default template, New Blank Entry and New Entry from Template… of earlier versions are gone; a stored default-template setting from an earlier version is ignored.)
- The empty entry's placeholder offers “use a template” when templates exist; choosing one fills that entry rather than creating another.
- Starting an entry ends the iPhone and iPad Journals edit mode.

## Accessibility

- Focus moves to the new entry's title.

## Platform notes (Apple)

- **Mac:** New Entry is in the toolbar over the editor; ⌘N reopens the journal window if it was closed.
- **iPhone:** New Entry (square and pencil, icon only) in the bottom bar of the Journals screen and of every list. From the Journals screen it opens the Default Journal's list first.
- **iPad:** the same bottom-bar button in the list column, and the File menu commands with a keyboard.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
