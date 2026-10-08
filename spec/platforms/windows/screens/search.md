---
id: search
title: Search (Windows)
spec: screens/search.md
features: [search-entries, search-all-entries]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/auto-suggest-box
---

# Search (Windows)

Filters the entry list on screen. Behaviour, matching rules and copy keys are the spec's [search](../../../screens/search.md); the box lives in the list header of the [library window](library-window.md).

## Controls

| Spec element | Control | Notes |
| --- | --- | --- |
| Search field | `AutoSuggestBox`, `QueryIcon` Find, no suggestion list (`ItemsSource` empty, `UpdateTextOnSelect` false), `TextChanged` filters the list as the person types, `AutomationProperties.Name` and `PlaceholderText` both the prompt; 200 epx wide at large width, filling the header at medium and small | In the list header, left of New entry |
| Prompt by collection | A journal: `library.search.journal` ({name}, or `common.untitledJournal`); All Entries: `library.search.allEntries`; Templates: `library.search.templates`; Recently deleted: `library.search.deleted`; Unavailable journals: `common.searchUnavailableEntries`; none: `library.search.journalFallback` | The tooltip repeats the prompt. The Mac's `library.toolbar.search` label is the access name of the collapsed icon button |
| Filtered list | The same `ListView`, groups and order with only the matching rows; pinned matches stay under Pinned | The list changes only when results change; the previous results stay until the new ones are ready |
| No results | Centred `library.entryList.empty.noResults` and a `Button` `library.entryList.empty.clearSearch` (lists) | |
| Clear | The `AutoSuggestBox` clear button (X) empties the field | |
| Locked | The text is cleared and the index forgotten | |
| iPhone Journals-screen search | Not offered: the stacked Journals page has no search box | Different by design |

Matching: the query anywhere in the title or text, ignoring case and diacritics; no operators, tokens or ranking. Recently deleted also matches deleted journals by name and deleted templates by name or text. Search is cleared when another collection is chosen, a journal is created or restored, an entry is created, moved or restored, or the library locks. While searching, Delete all is disabled.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large | The box is 200 epx in the list header | Mac toolbar field |
| Medium | The box is a Search icon button when the list is narrower than 340 epx (the default medium list width is 300), and expands in place when pressed or when Ctrl+E is used ([library-window](library-window.md)); wider lists show the 200 epx box as at large width | iPad bottom bar field |
| Small | On the entry list page the box sits under the page title and fills the width. The Journals page has none: searching all entries means opening All Entries first | iPhone list page; the Journals screen's own "Search All Entries" field is not offered |
| 200% text size or more | The box becomes a Search icon button that expands to a full-width box when pressed | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `search-entries` | Edit menu; the box | Ctrl+E, Ctrl+Shift+F | A library is open and unlocked. Leaves Show editor only and shows a hidden list first, then focuses the box |
| `clear-search` | Button under No results; Esc in the box | Esc | The box has text |

- In the stacked (small) layout, Ctrl+E on an open entry goes back to its list and focuses the box; on the Journals page, which has no search of its own, it opens All Entries and focuses the box (the spec's stacked-layout rule, with the Journals page's own field not offered).
- Esc clears the text, a second Esc leaves the box and returns focus to the list.
- Down arrow moves focus from the box to the first row; Enter does the same. Focusing the box by click or Tab leaves Show editor only.
- Ctrl+F is Find in the open entry, not search ([commands.md](../commands.md), `find`).

## Copy differences

Sentence case on the prompts ("Search all entries", "Search templates", "Search deleted items", "Search unavailable entries", "Search journal"; [platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). No other differences.

## Accessibility

- The box is a Search landmark named by the prompt; `AutomationProperties.AcceleratorKey` carries Ctrl+E. Results are announced as a count: after results settle, a notification event with `common.entryCount` for the filtered rows, `MostRecent`, so typing does not queue announcements; "No results" is announced the same way.
- Result rows read as one element, as in [entry-list](entry-list.md).
- The clear button has the name `library.entryList.empty.clearSearch`.
- The box works with the touch keyboard (`InputScope` Search) and voice typing.

## Different by design

- **Place.** The Mac puts the field at the far end of the editor toolbar; iPhone and iPad put it in the list's bottom bar. Windows puts it in the list header because it filters that list.
- **No all-journal search from the Journals page.** Windows has no stacked Journals-screen search; the three-column layout has All Entries one click away.
- **Shortcuts.** Ctrl+E (and Ctrl+Shift+F) replace Option+Command+F; Find and replace is Ctrl+H ([7.1](../platform.md#71-translation-table)).

## Open questions

None.
