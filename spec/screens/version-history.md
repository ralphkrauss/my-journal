---
id: version-history
title: Version History (entries and templates)
features: [version-history, restore-version]
sources:
  - apps/apple/JournalApp/Views/VersionHistoryView.swift
  - apps/apple/JournalApp/Views/HistoryMenu.swift
  - apps/apple/JournalApp/Views/RecoveryJournalView.swift
  - apps/apple/JournalApp/Model/HistoryOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/HistoryRecovery.swift
  - apps/apple/JournalTests/HistoryLifecycleTests.swift
  - docs/design/history-recovery.md
  - docs/design/version-checkpoints.md
  - protocol/history-recovery.md
---

# Version History

## Purpose

See earlier versions of an entry or template and copy one back as a new entry or template. The current item and its history are never changed by this screen.

Journal version history (names and default templates) is a different screen, specified with journals.

## Entry points

- Entry Actions ▸ Version History… in the editor, and the row's context menu (`entry-version-history`), for entries and templates, including items in Recently Deleted.

## Content

Sheet. Phone and tablet: navigation bar with title `editor.history.title` and `common.done` (trailing). Computer: title at the top, scrolling content, divider, `common.done` at the leading end of the button row; 360–600 pt wide, 420–620 pt tall. Done is also the Escape action; it's disabled while restoring.

Scrolling content:

1. While loading: progress indicator with `editor.history.loading`.
2. No versions: `editor.history.empty` in secondary text.
3. With versions:
   - **Version** picker (a menu whose label wraps: caption `common.version` above the chosen value): versions newest first, each named by when it was made (abbreviated date and time with seconds); versions whose names would read the same are named `editor.history.versionDuplicate` (numbered 1, 2, … in list order). Without a choice the value reads `editor.history.chooseVersion`.
   - **Preview** of the chosen version: its title (headline), for entries its date, then a read-only editor at least 220 pt tall with its formatting and images. A version in a format this version can't read shows `editor.history.updateToRestore` and the Export Archive… control (specified with backup) instead.
   - For entries: the **Journal** picker (same wrapping menu label: caption `editor.history.journalLabel`, value the journal or `common.chooseJournal`), listing `common.chooseJournal` and every journal in use; journals with the same name are shown as `editor.history.journalDuplicate` (the journal’s creation date and time, then its number among them); a journal without a name is `common.untitledJournal`. Below it `common.newJournalEllipsis`. With no journals: `editor.history.createJournalFirst` and New Journal….
   - The restore button: `editor.history.restoreAsNewEntry` or, for templates, `editor.history.restoreAsNewTemplate`.
4. Error text (secondary, selectable) when there is one.
5. After restoring, if the result couldn't be shown: `editor.history.restored` or `editor.history.restoredTemplate`.
6. Recovery buttons when needed: `editor.history.reload`, `common.reloadJournals`, `common.reviewChanges`.
7. While working: progress indicator with `editor.history.loadingJournals` or `editor.history.restoring`.

## Actions

| Action | Enabled | Result |
| --- | --- | --- |
| Choose a version | Not restoring, not restored | Shows it; its images load. |
| Choose a journal (entries) | Not restoring | Sets the destination. Initially the entry's own journal when it's in use; otherwise none. |
| New Journal… | Not restoring, library not being replaced | Opens `screens/destination-journal.md`. Creating a journal doesn't select it or restore anything. |
| Restore as New Entry / New Template | A readable version is chosen; for entries a journal in use is chosen; not loading, restoring or restored; unlocked | First saves the open entry. Then copies the version as a **new** entry (new identity, the version's title, text, images and date, in the chosen journal) or a new template. On success the sheet closes and the copy opens in the editor (its journal or Templates is shown). |
| Reload History | After a failed load, or when the version is no longer available | Loads the history again. |
| Reload Journals | After the chosen journal became unavailable | Refreshes journals, then asks to choose one: `messages.history.chooseJournal`. |
| Review Changes | The chosen journal has changes to review | Opens the journal or entry conflict review in a nested sheet; if already resolved: `messages.conflict.resolved` with `common.done`. Restoring afterwards needs another explicit Restore. |
| Done | Not restoring | Closes; nothing changes. |

## States

| State | Copy |
| --- | --- |
| Loading | `editor.history.loading` |
| No earlier versions | `editor.history.empty` |
| Load failed | the error text, with Reload History |
| Version in a newer format | `editor.history.updateToRestore` and Export Archive… |
| No journals (entries) | `editor.history.createJournalFirst` |
| Restoring | `editor.history.restoring` (Done and the controls disabled; can't swipe to dismiss) |
| Open entry couldn't be saved first | `messages.save.before.goBack` |
| Version gone | `messages.history.versionUnavailable`, with Reload History |
| Journal gone | `messages.history.chooseJournal` (also when a chosen journal disappears while the sheet is open) |
| Journal has changes to review | `messages.lifecycle.needsReview`, with Review Changes |
| Restored but not shown | `editor.history.restored` / `editor.history.restoredTemplate` (Restore hidden) |
| Locked | The sheet closes; previews are cleared; the work is cancelled. A copy already committed stays. |

## Rules

- Versions listed are this item's earlier versions of the same kind, newest first by when each was made; equal times keep the most recently recorded first (`HistoryLifecycleTests.testVersionPickerListsVersionsNewestFirstAndNumbersOnlyMatchingTimes`).
- Restoring never changes the current item or its history; it always creates a new item. It may copy a version even when the current item is deleted, unavailable or in conflict.
- Only one restore runs at a time.
- A save failure of the open entry stops the restore and keeps the choice of version and journal (`HistoryLifecycleTests.testHistoryRecoverySavesCurrentDraftAndRetainsItOnSaveFailure`).

## Accessibility

- The Version and Journal menus read as their caption and full value. Errors are announced.
- All controls work at the largest text sizes; values wrap rather than truncate.

## Platform notes (Apple)

- Same content everywhere; navigation bar on the phone and tablet, bottom row on the computer.

## Open questions

- None.
