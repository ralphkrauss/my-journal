---
id: search
title: Search
features: [search-entries, search-all-entries]
sources:
  - apps/apple/JournalApp/Views/RootView+Toolbar.swift
  - apps/apple/JournalApp/Views/RootViewAdaptations.swift
  - apps/apple/JournalApp/Views/JournalSearchResults.swift
  - apps/apple/JournalApp/Views/CompactJournalNavigation.swift
  - apps/apple/JournalApp/Views/MacJournalSearchField.swift
  - apps/apple/JournalApp/Model/DerivedLists.swift
  - apps/apple/JournalApp/Model/FindKeyCommands.swift
  - apps/apple/JournalApp/Model/FindMenuShortcuts.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/EntrySearch.swift
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/pinned-entries.md
---

# Search

## Purpose

Finds entries (and templates in Templates) by their words. The search filters the list on screen; on the iPhone Journals screen it searches every journal.

## Entry points

- The list's search field: Mac toolbar (at the trailing end); iPhone and iPad bottom bar of the list (system search field).
- **Edit ▸ Search Entries** (⌥⌘F, `search-entries`) on the Mac and on iPad with a keyboard (iPadOS 17 or later).
- iPhone (and stacked layouts) Journals screen: its own search field `library.search.allEntries`.

## Content

**Prompt** (placeholder; on the Mac also its tooltip and accessibility label), by collection:

| Collection | Prompt |
| --- | --- |
| A journal | `library.search.journal` (its name, or “Untitled Journal”) |
| All Entries | `library.search.allEntries` |
| Templates | `library.search.templates` |
| Recently Deleted | `library.search.deleted` |
| Unavailable Journals | `common.searchUnavailableEntries` |
| None | `library.search.journalFallback` |

**Filtered list:** the same list, sections and order, with only the matching rows (pinned matches stay under Pinned, the rest under their months).

**iPhone Journals screen results:** replace the journals list while the field has text; titled `common.journals`. A flat list, newest first, of entries in journals in use (no templates, nothing deleted), each row: date (day, abbreviated month), title (headline, one line), first line of text (secondary), and the journal with a closed-book symbol (`library.entryList.journalValue` if unknown). `library.entryList.empty.noResults` when a search found nothing.

## Actions

- **Typing** filters as results arrive; the list changes only when the results change. Clearing the field shows everything again.
- **Search Entries (⌥⌘F):**
  - Mac: leaves Editor Only if needed and puts focus in the toolbar's search field.
  - iPad: shows a hidden list column if needed and opens its search.
  - Stacked layouts: from an open entry, goes back to its list and opens the list's search; from the Journals screen, opens Search All Entries.
- **Choosing a result on the iPhone Journals screen** opens All Entries with the same search applied and the entry open, so Back leads to the filtered All Entries.
- **Clear Search** (`library.entryList.empty.clearSearch`) under No Results empties the field.
- **Focusing the Mac search field** (click or Tab) leaves Editor Only.

## States

- **No results:** `library.entryList.empty.noResults` with Clear Search (lists); `library.entryList.empty.noResults` alone (iPhone Journals results).
- **Searching while results are computed:** the previous results stay until the new ones are ready.
- **Locked:** the search text is cleared and the index forgotten.

## Rules

- A match is the query found anywhere in the title or text, ignoring case and diacritics (“cafe” finds “Café”). There are no operators, tokens or ranking.
- Recently Deleted also matches deleted journals by name and deleted templates by name or text.
- The search is cleared whenever another collection is chosen, a journal is created or restored, an entry is created, moved or restored, or the library locks.
- Searching or New Entry ends the iPhone and iPad Journals edit mode.
- While searching, Delete All isn't available (“All” could mean the results).

## Accessibility

- The field is the system search field with the prompt as its label.
- Results rows read as one element.

## Platform notes (Apple)

- **Mac:** Search Entries is ⌥⌘F and Edit ▸ Find ▸ Find and Replace… is moved to ⇧⌘F, as in Notes (owner decision 2026-09-27).
- **iPad:** the same shortcuts, swapped from the system's defaults at launch; before iPadOS 17 Search Entries isn't in the menu.
- **iPhone:** the field sits in the bottom bar (iOS 26) and the keyboard opens with it.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
