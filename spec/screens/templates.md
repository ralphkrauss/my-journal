---
id: templates
title: Templates (collection)
features: [templates-collection, save-as-template, delete-entry, undo-delete]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Model/TemplateSuggestion.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - docs/design/template-journal-choice-2026-10-03.md
  - docs/design/no-built-in-templates-2026-10-04.md
  - docs/design/1-1-library-simplifications.md
---

# Templates

## Purpose

Lists the library's templates so they can be edited, described and deleted. Templates are edited in the same editor as entries. A template is used from inside an empty entry ([screens/template-chooser](template-chooser.md)), never from this list.

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
| Image Descriptions… | `library.entryActions.imageDescriptions` | the template has pictures | descriptions can be edited | screens/image-description |
| Version History… | `common.versionHistoryEllipsis` | always | always | screens/version-history |
| — | | | | |
| Delete Template | `library.entryActions.deleteTemplate`, destructive | template editable and not deleted | always | Moves it to Recently Deleted at once; Undo Delete Template brings it back |

Swipe: trailing **Delete** (`common.delete`) as Delete Template. No Pin.

## States

- **No templates:** centered secondary text `library.entryList.empty.noTemplates` with `library.entryList.empty.noTemplatesHelp` under it (read as one element by VoiceOver). New libraries start here.
- **Search without results:** `library.entryList.empty.noResults` with `library.entryList.empty.clearSearch`.

## Rules

- Making a template: Save as Template… on an entry ([screens/entry-list](entry-list.md)). There is no New Template command.
- “use a template” in an empty entry, and File ▸ Use a Template…, use [screens/template-chooser](template-chooser.md). There is no way to start an entry from a template in this list.
- New Entry (⌘N) while Templates is shown creates an empty entry in the Default Journal ([flows/new-entry](../flows/new-entry.md)).
- A template saved by a newer version can be read but not used or edited; the chooser doesn't list it.
- Deleted templates appear in Recently Deleted's Templates section.

## Accessibility

As [screens/entry-list](entry-list.md).

## Platform notes (Apple)

- Same on all platforms.

## Open questions

- None.
