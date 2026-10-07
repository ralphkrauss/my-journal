---
id: library-window
title: Library window (structure, toolbars, windows, restoration)
features: [three-column-layout, stacked-navigation, editor-only, previous-next-entry, text-size, state-restoration, new-entry, search-entries]
sources:
  - apps/apple/JournalApp/JournalApp.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/RootView+Toolbar.swift
  - apps/apple/JournalApp/Views/RootViewAdaptations.swift
  - apps/apple/JournalApp/Views/CompactJournalNavigation.swift
  - apps/apple/JournalApp/Views/EditorOnlyLayout.swift
  - apps/apple/JournalApp/Views/EntryCreationActions.swift
  - apps/apple/JournalApp/Views/Mac/JournalSplitViewController.swift
  - apps/apple/JournalApp/Views/Mac/JournalToolbarController.swift
  - apps/apple/JournalApp/Views/Mac/MacJournalWindow.swift
  - apps/apple/JournalApp/Views/Mac/RootView+MacWindow.swift
  - apps/apple/JournalApp/Model/WindowColumns.swift
  - apps/apple/JournalApp/Model/WindowSafety.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - docs/design/notes-alignment-revision.md
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/quiet-sync-and-title-alignment.md
---

# Library window

## Purpose

The main window once a library is open and unlocked: journals and collections, the entries of the chosen collection, and the open entry. Writing is primary; everything else stays out of the way.

## Entry points

- Launch or unlock with a library (see screens/welcome for the order of launch states).
- On the Mac, any menu command that needs the window reopens it if it was closed (the app keeps running with no window).

## Content

Three parts, in order. Their contents are specified in their own files:

1. **Journals and collections** ([screens/journals](journals.md)): All Entries, the journals, Templates, Recently Deleted, Unavailable Journals (when needed), and on iPad Settings.
2. **Entry list** of the chosen collection ([screens/entry-list](entry-list.md), [screens/templates](templates.md), [screens/recently-deleted](recently-deleted.md)).
3. **Editor** of the open entry or template (screens/entry-editor), or for a deleted journal its detail ([screens/recently-deleted](recently-deleted.md)).

### Arrangement

- **Mac:** three columns side by side, journals in a collapsible sidebar, the entry list, and the editor. Column widths: sidebar 210–320 points (230 by default), list 360–460 (360 by default), editor at least 439. The editor text is at most 760 points wide, centered, with 24-point margins. Window default size 1100 × 720, minimum 801 × 420.
- **iPad, regular width:** the same three columns (sidebar 180–320, ideal 220; list 240–420, ideal 300). Choosing a collection in a window narrower than 1,000 points hides the sidebar, leaving list and editor.
- **iPhone, iPad in compact width, and iPad at accessibility text sizes:** stacked navigation: Journals ▸ collection's entries ▸ entry. Each level is a page with a back button.

### Editor column when nothing is open

- The list has entries: secondary text `library.window.selectEntry`.
- The list is empty: blank (as in Notes). On the Mac with Editor Only, the editor shows what the empty list would (`library.entryList.empty.*` and its action).

### Window title (Mac)

- Title: the collection's name (`library.journals.allEntries`, `library.journals.templates`, `common.recentlyDeleted`, `common.unavailableJournals`, the journal's name or `common.untitledJournal`); `library.app.name` when no collection is chosen.
- Subtitle, as in Notes: the collection's count. Journals, All Entries and Unavailable Journals: `common.entryCount` or `library.entryList.empty.noEntries`. Templates: `common.templateCount` or `library.entryList.empty.noTemplates`. Recently Deleted: `common.itemCount` (journals, templates and entries listed) or `library.window.subtitle.noItems`. Nothing while the library is opening.
- With the list hidden, the title is hidden in the toolbar but kept in the Window menu. While locked, the title is `library.app.name` and the subtitle is empty, so nothing of the journal shows.

## Toolbars

### Mac

One toolbar whose sections follow the column dividers, leading to trailing:

| Over | Item | Copy | Command |
| --- | --- | --- | --- |
| Sidebar | New Journal (folder with plus) | `library.toolbar.newJournal` | `new-journal` |
| Sidebar | System sidebar button | system | `toggle-sidebar` |
| List | Journal Actions menu (⋯): New Journal…, then the shown journal's actions | `library.toolbar.journalActions` | `journal-actions` |
| Editor | New Entry (square and pencil) | `library.menu.file.newEntry` | `new-entry` |
| Editor | Formatting (popover) | `library.toolbar.formatting` | screens/entry-editor |
| Editor | Insert Image | `library.toolbar.insertImage` | screens/entry-editor |
| Editor | Sync Status (only when sync needs the person; its place is kept while the library syncs so nothing moves) | `messages.syncStatus.title` | screens/sync-status |
| Editor | Editor Only (toggle) | `library.toolbar.editorOnly`; tooltip `library.toolbar.editorOnly.help` / `library.toolbar.editorOnly.helpActive` | `show-editor-only` |
| Editor | View Source / View Preview | `library.menu.view.viewSource` / `library.menu.view.viewPreview`; disabled tooltip `common.previewUnavailable` | `view-source` |
| Editor | Entry Actions menu (⋯) | `library.toolbar.entryActions` | `entry-actions` |
| Editor | Search field (200 points) | item label `library.toolbar.search`; placeholder, tooltip and accessibility label = the search prompt ([screens/search](search.md)) | `search-entries` |

The toolbar can't be customized. Items of a column that hides leave with it (New Journal hides with the sidebar; Journal Actions with the list). Sync Status gives way first when the window is too narrow. There is no line under the toolbar.

Enabled states: New Journal while a library is open and unlocked; New Entry also not while the library is being replaced; Formatting, Insert Image, View Source while the open item can be edited (View Source also not when the entry must be edited as Markdown); Entry Actions while an entry or template is open (not a deleted journal).

### iPhone and iPad

- **Journals page (iPhone root, stacked):** top left Settings (gear, `library.toolbar.settings`); top right New Journal (`library.toolbar.newJournal`) and Edit (`library.toolbar.edit`; while editing the system checkmark, labelled `common.done`); bottom bar: search field (`library.search.allEntries`) and New Entry (icon only).
- **iPad sidebar (regular width):** large title `common.journals`; New Journal and Edit in its bar; Settings is the sidebar's last row.
- **Entry list page/column:** in a journal, Journal Actions (⋯, `library.toolbar.journalActions`) at the top right; in Recently Deleted with items and no search, `library.recentlyDeleted.deleteAll` at the top right; bottom bar: the list's search field and New Entry (icon only).
- **Editor page/column:** top right Entry Actions (⋯, `library.toolbar.entryActions`) and, while typing, Done (checkmark, `common.done`), which ends typing and finishes the save. The bottom reading bar (Formatting, Insert Image, View Source) belongs to screens/entry-editor.

## Actions

- **New Entry** (`new-entry`), from any toolbar, menu or empty state: see [flows/new-entry](../flows/new-entry.md). On the iPhone Journals page it opens the Default Journal's list first, then the new entry, so Back shows where the entry was filed.
- **Show Editor Only / Show Sidebar and List** (Mac, `show-editor-only`, ⇧⌘D, View menu and toolbar toggle): hides the sidebar and the list together, leaving only the editor; again restores the layout it replaced (sidebar shown or hidden). Searching (⌥⌘F or focusing the search field) and New Journal leave Editor Only first. Entering it moves keyboard focus to the editor.
- **Show/Hide Sidebar** (`toggle-sidebar`, ⌃⌘S, sidebar button): from Editor Only it shows every column.
- **Previous Entry / Next Entry** (Mac, ⌥⌘↑ / ⌥⌘↓, View menu): opens the item above or below the open one in the list's order (Pinned first; in Recently Deleted journals, then templates, then entries), saving first. With nothing open, Next opens the first item and Previous the last. Works while the list is hidden. Disabled at either end and when the window has no library.
- **Zoom In / Zoom Out / Actual Size** (`zoom-in`, `zoom-out`, `actual-size`): change the editor's text size by one point between 12 and 30 (default 16). On iPhone and iPad the size scales the person's Dynamic Type size by the same ratio. Actual Size is disabled at the default.

## States

- **Loading after unlock:** the list is blank (no empty-state message, which would offer to create something) until the journals have been read.
- **Locked:** the window shows [screens/lock-screen](lock-screen.md); every sheet, popover, menu and prompt the window showed closes (deletion prompts bring back a row a swipe removed).
- **Library being replaced** (connecting, importing, turning on encryption): New Entry, editing and organizing are disabled; on the Mac a notice above the editor explains (screens/sync-status / flows/connect-to-server).
- **Erasing:** every presentation closes and the window returns to screens/welcome.
- **Error:** the general error alert, title `common.alertTitle`, message = the error, `common.ok`; after a failed save also `common.tryAgain` (message `common.saveFailed`). Not shown while locked or while the create-library sheet shows its own error.

## Rules

- **Saving before moving on.** Choosing another collection or entry saves the open entry first. If the save fails, the selection doesn't change and the error alert offers Try Again.
- **An open entry that leaves the shown collection closes** (deleted, permanently deleted, moved, restored elsewhere, made unavailable, here or by a sync): iPhone goes back to the list; Mac and iPad show `library.window.selectEntry`, or the next entry after Delete. Exception: an entry with unsaved writing stays open with its writing intact. An unavailable entry whose journal arrives is followed into that journal instead.
- **A journal that leaves the list** (deleted here or by a sync) is replaced by the remembered journal or the first journal; on iPhone the journal's page goes back to Journals.
- **State restoration.** The last journal and entry are remembered on the device (not synced) whenever they change in a journal or All Entries; never in Templates, Recently Deleted or Unavailable Journals. From All Entries the entry's own journal is remembered, so relaunching opens that journal. At launch and after unlocking: the remembered journal (or the first journal) is shown, and the remembered entry opens if it's still listed; otherwise an entry dated today, if there is one; otherwise nothing.
  - **iPhone:** after launch or unlock the restored entry opens directly, without animation, if it's editable in its journal. Going back from an entry to the list deselects it once saved, so the next launch shows the list.
  - **Mac:** each window remembers its columns (all, sidebar hidden, or Editor Only with the layout to return to) and the widths the person dragged the dividers to.
- **Text size** (Zoom) isn't remembered across launches.
- **Mac window closing and quitting** wait for the open entry to be saved. If it can't be: an alert `messages.save.mac.title` / `messages.save.mac.message` with `messages.save.mac.keepOpen`, and the window stays open (quitting is cancelled). On quit, writing is also sent to the server for up to 3 seconds.
- **Leaving the app (iPhone and iPad):** saving continues in the background and the app locks if App Lock is on ([flows/app-lock](../flows/app-lock.md)). Coming back to the foreground syncs at once.

## Accessibility

- Reduce Motion: column changes and list changes happen without animation.
- Keyboard focus: a column that hides can't keep focus; it moves to the list, or to the editor in Editor Only.
- Toolbar buttons have their names as labels and tooltips.

## Platform notes (Apple)

- **Mac:** one journal window; the app keeps running without it, and menu commands reopen it. No window tabs. Mac columns are an AppKit split view; the sidebar is the first to hide when the window becomes too narrow for all three columns, never the list or editor. A column returning to a narrow window widens the window.
- **iPad:** the system may show more than one window; all windows share the same library, collection and open entry.
- **iPhone:** stacked navigation only. The bottom bar holds search and New Entry, as in Notes.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
