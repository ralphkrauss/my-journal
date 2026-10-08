---
id: unavailable-content
title: Unavailable and read-only content (Windows)
spec: screens/unavailable-content.md
features: [library-open-failure, read-only-newer-content, unavailable-journals, privacy-cover]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity
---

# Unavailable and read-only content (Windows)

What the Windows app shows when the library cannot open, when content comes from a newer version, when an entry's journal is unavailable, and why the window is not covered when it loses focus. Behaviour, rules and copy keys are the spec's [unavailable-content](../../../screens/unavailable-content.md). Content is never changed or discarded because this version cannot handle it.

## Controls

| Spec element | Control | Notes |
| --- | --- | --- |
| Library cannot open | **Not mapped yet.** This row was written against the earlier spec, where a library that could not open showed the lock page with a note. The spec now has a library problem screen of its own (Try Again, Import archive…, Erase, Learn more; no authentication; never locked), so this row needs a new mapping through the design gate. Until then the Windows app has no design for it (see open-questions.md) | The spec's screen, keys `library.problem.*` and commands `retry-opening`, `erase-unopened`, `open-library-guide`. `messages.library.deviceKeyUnavailable` stays on the lock page and is a first-class path on Windows ([14](../platform.md#14-secure-storage)), now with Import archive… and Erase below the password form (`library.problem.missingKey.caption`) |
| Newer-version entry or template | Opens read-only in the [entry editor](entry-editor.md): `RichEditBox`-class control with `IsReadOnly` true (selectable, copyable, readable by Narrator), title `TextBox` read-only; editing note under the title: `TextBlock`, secondary, `messages.error.unsupportedFormat` | Formatting, Insert image, View source, Entry actions that change the entry, checkbox toggling and the Format menu are disabled; picture menus offer Copy, Share and Save image as only |
| Markdown that can only be shown as source | Opens in source view; View preview disabled with `common.previewUnavailable`; editing note `messages.unavailable.markdownSource` | [flows/source-view](../flows/source-view.md) |
| Newer-version journal | Left out of the pane; its entries are in Unavailable journals with `common.updateToRestoreEntry` on each | [journals](journals.md) |
| Unavailable journals collection | A pane item (icon Folder with an attention dot) after Templates and Recently deleted, present while an entry is unavailable or while it is shown; the entry list titled `common.unavailableJournals`; search prompt `common.searchUnavailableEntries`; empty state `messages.unavailable.empty`; pinned entries are not grouped at the top | [entry-list](entry-list.md) |
| Notice above an unavailable entry's title | `InfoBar`, `Severity` Informational (Warning for a journal that needs review), `IsClosable` false, message and action by reason: missing while syncing, `common.journalNotArrived` with `common.trySyncingAgain`; missing without sync, `common.journalUnavailableEntrySaved` with Restore and move… when an earlier version deleted the entry with its journal (`library.recoveryNotice.restoreAndMove`); newer version, `common.updateToRestoreEntry`, no action; changes to review, `common.journalNeedsReview` with `common.reviewChanges` | The recovery bar of [recently-deleted](recently-deleted.md) is the same control. When the journal arrives or is reviewed, the entry returns to its journal and the list follows it |
| Update messages | `messages.sync.appUpdateNeeded`, `messages.library.needsUpdate`, `messages.import.archiveNeedsUpdate` and the others in the spec's table | Where a message says to update, a Windows-only link "Get updates" beside it opens the Microsoft Store's updates page (D51, B38; [18](../platform.md#18-packaging-distribution-and-updates)); the message's own action, where it has one, is unchanged; the personal-data rules of the lock page are unchanged |
| Privacy cover | Not offered. The Windows app does not cover its window when another window is in front (D28); locking and capture exclusion do the protecting | [platform.md, 20](../platform.md#20-screen-capture-and-window-privacy), [lock-screen](lock-screen.md) |

## Layout at each window width

The notices and the read-only editor use the editor's layout ([entry-editor](entry-editor.md)): at 200% text size the notices stack and a recovery or review `InfoBar` is capped at half the editor's height and scrolls. At small width the notice sits above the title on the entry's page.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `try-syncing-again` | The notice's action | none | The journal is missing and the library syncs; syncs now, also resending refused items |
| `restore-and-move` | The notice's action | none | The entry was deleted with its journal by an earlier version and is editable |
| `review-changes` | The notice's action | none | The journal has changes to review |
| `unlock-with-credential` | Lock page, password field | Enter | The master password or recovery key is entered |
| `export-archive` | Settings ▸ Backup, reached from the deleted journal's page | none | Offered for content this version cannot read; exports it losslessly |

## Copy differences

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `messages.library.cannotOpen` | (quit and reopen text) | "Close My Journal and open it again" | vocabulary (platform.md, 12.3) |
| `messages.library.deviceKeyUnavailable`, `messages.error.newerVersion` | unchanged | unchanged, except any device name becomes "this PC" | vocabulary (platform.md, 12.3) |

Sentence case as in [platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary) ("Unavailable journals", "Search unavailable entries").

## Accessibility

- Notices are `InfoBar`s read when they open, then the title; their buttons are in the tab order and reachable by keyboard only.
- The read-only title is read as "Title" with its text as the value; the body is readable and selectable.
- The lock page announces its note when it changes (a new `InfoBar` instance, because a changed message is not announced, [9.1](../platform.md#91-notices)).
- The window title is "My Journal" in every state ([2](../platform.md#2-app-shell-and-window)).

## Different by design

- **No cover at all.** Apple covers the window when the app is not active, to protect the app switcher's snapshot. Windows has no snapshot, and windows there sit side by side and lose focus all day, so a cover would hide the journal at the moments the person is reading it beside another window ([20](../platform.md#20-screen-capture-and-window-privacy)).
- **Update actions open the Store.** Nothing updates inside the app.
- **Failures show as `InfoBar`s**, not red text, so severity is never colour alone.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D28 (privacy beyond the lock), D30 (editor control), B35 (device key wording).
