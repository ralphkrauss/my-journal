---
id: templates
title: Templates (collection)
features: [templates-collection, new-entry-from-template, save-as-template, delete-entry, undo-delete]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Model/TemplateSuggestion.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - docs/design/template-journal-choice-2026-10-03.md
  - docs/design/no-built-in-templates-2026-10-04.md
---

# Templates

## Purpose

Lists the library's templates so they can be edited, deleted, or used to start an entry in a chosen journal. Templates are edited in the same editor as entries.

## Entry points

- The **Templates** row in [screens/journals](journals.md).

## Content

- Title `library.journals.templates`; on the Mac the subtitle `common.templateCount` / `library.entryList.empty.noTemplates`.
- The same list as [screens/entry-list](entry-list.md), with templates instead of entries: month sections by the template's date, newest first; no Pinned section. Rows show date, title (`library.entryList.untitledEntry` fallback), and preview.

## Actions

Selecting a template opens it in the editor, where it's edited like an entry (screens/entry-editor).

**Context menu and Entry Actions for a template:**

| Item | Copy | Shown when | Enabled when | Result |
| --- | --- | --- | --- | --- |
| New Entry In ▸ (two or more journals in use) | `library.entryActions.newEntryIn`, symbol square and pencil; items: journal names in sidebar order (`common.untitledJournal` for blank), no separators, nothing marked | template editable and not deleted | a journal exists, saving isn't blocked by a failed save, unlocked, not replacing, template has no changes to review | Creates a new entry from the template, as it is now, in the chosen journal |
| New Entry from Template (one journal, or none) | `library.entryActions.newEntryFromTemplate` | same | as above, and exactly one journal | The same, in that journal |
| — | | | | |
| Image Descriptions… | `library.entryActions.imageDescriptions` | the template has pictures | descriptions can be edited | screens/image-description |
| Version History… | `common.versionHistoryEllipsis` | always | always | screens/version-history |
| — | | | | |
| Delete Template | `library.entryActions.deleteTemplate`, destructive | template editable and not deleted | always | Moves it to Recently Deleted at once; Undo Delete Template brings it back |

Swipe: trailing **Delete** (`common.delete`) as Delete Template. No Pin.

**After New Entry In ▸ a journal:** the open template is saved first; a new entry (never a fill of an open empty entry) is created from the template's current text in the chosen journal and opens there with its title focused: the sidebar selects the journal, the list shows it. On iPhone the stack becomes that journal's list and the entry, so Back leads to the journal. No message.

Errors (general error alert): `messages.generic.journalNamedUnavailable` (or `messages.generic.journalUnavailable`), `messages.generic.templateUnavailable`, `messages.generic.templateNeedsReview`.

## States

- **No templates:** centered secondary text `library.entryList.empty.noTemplates` with `library.entryList.empty.noTemplatesHelp` under it (read as one element by VoiceOver). New libraries start here.
- **Search without results:** `library.entryList.empty.noResults` with `library.entryList.empty.clearSearch`.

## Rules

- Making a template: Save as Template… on an entry ([screens/entry-list](entry-list.md)). There is no New Template command.
- New Entry from Template… in the File menu and “use a template” in an empty entry use [screens/template-chooser](template-chooser.md).
- New Entry (⌘N) while Templates is shown creates an entry in the Default Journal with that journal's default template, not the selected template ([flows/new-entry](../flows/new-entry.md)).
- A template saved by a newer version can be read but not used or edited; its New Entry item is hidden.
- Deleted templates appear in Recently Deleted's Templates section.

## Accessibility

As [screens/entry-list](entry-list.md). The submenu reads “New Entry In, menu”.

## Platform notes (Apple)

- Same on all platforms; iOS 26 opens the submenu in place.

## Open questions

- None.
