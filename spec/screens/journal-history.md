---
id: journal-history
title: Journal Version History
features: [journal-version-history]
sources:
  - apps/apple/JournalApp/Views/JournalHistoryView.swift
  - apps/apple/JournalApp/Views/JournalSettingsConfirmation.swift
  - apps/apple/JournalApp/Views/HistoryMenu.swift
  - apps/apple/JournalApp/Views/JournalConflictView.swift (JournalMetadataSummary)
  - apps/apple/JournalApp/Views/ArchiveView.swift (ArchiveExportControls)
  - apps/apple/JournalApp/Model/HistoryOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/HistoryRecovery.swift
  - docs/design/history-recovery.md
---

# Journal Version History

## Purpose

See earlier versions of a journal's settings (its name and default template) and put one back. Entries, and whether the journal is in Recently Deleted, never change here. The entry and template form of version history is [version-history.md](version-history.md).

## Entry points

- `journal-version-history`: Version History… (`common.versionHistoryEllipsis`) in a journal's context menu and Journal Actions ([screens/journals](journals.md)).
- A deleted journal's detail in Recently Deleted, when the journal has earlier versions ([screens/recently-deleted](recently-deleted.md)).
- A journal that has changes to review shows the review in place of restoring ([screens/conflict-review](conflict-review.md)).

## Content

Sheet titled `editor.history.title`. Phone and tablet: navigation bar with `common.done` (confirming position). Computer: title at the top, scrolling content, divider, `common.done` at the leading end; 360–460 pt wide, 360–520 pt tall. Done is also the Escape action and is disabled while a restore is being prepared or saved.

Scrolling content, top to bottom:

1. While loading: progress indicator with `editor.history.loading`.
2. No earlier versions and no error: `editor.history.empty` in secondary text.
3. With versions:
   - **Version** picker, a menu whose label wraps (caption `common.version`, value the chosen version, or `editor.history.chooseVersion` when none): versions newest first, each named by when it was made (abbreviated date and time with seconds); versions that would read the same are named `editor.history.versionDuplicate`, numbered 1, 2, … in the order they were recorded. The first version is chosen at the start.
   - **Summary** of the chosen version, each a caption label over a selectable value: `common.name` (the name, or `common.untitledJournal`), `common.defaultTemplate` (the template's name, `common.blankEntry`, or `messages.conflict.journal.value.unavailableTemplate`), `messages.conflict.journal.field.location` (`common.journals` or `common.recentlyDeleted`).
   - A version this app can read: button `library.journalHistory.restoreSettings`.
   - A version from a newer version of My Journal: `editor.history.updateToRestore` and the Export Archive… control (the one in Settings ▸ Backup, including its one-time password check).
4. While preparing: progress indicator with `library.journalHistory.loadingSettings`.
5. An error as secondary selectable text; the result message after restoring.
6. Recovery buttons when needed: `editor.history.reload`, `common.reviewChanges`, and Export Archive….

### Restore Settings (comparison sheet)

A nested sheet titled `library.journalHistory.confirm.title`. Phone and tablet: navigation bar with `common.cancel` (leading) and the confirming button (trailing); at accessibility text sizes the title is repeated as a heading in the content. Computer: title at the top, scrolling content, divider, `common.cancel` and the confirming button; 360–460 pt wide, 420–560 pt tall. The sheet can't be dismissed while restoring.

1. `library.journalHistory.confirm.explanation`.
2. Summary headed `library.journalHistory.confirm.current`: `common.name` and `common.defaultTemplate` of the journal now.
3. Summary headed `common.restore`: the same two fields of the chosen version.
4. When another journal in use has the earlier name: `library.journalHistory.confirm.nameTaken`.
5. While restoring: progress indicator with `library.journalHistory.confirm.restoring`.

A default template's name is its title, or `library.entryList.untitledTemplate`; templates that share a title are named `library.journalHistory.templateDuplicate`; a template that no longer exists is `messages.conflict.journal.value.unavailableTemplate`, numbered with `library.journalHistory.unavailableTemplateNumbered` when the two summaries refer to more than one.

## Actions

| Action | Enabled | Result |
| --- | --- | --- |
| Choose a version | not loading, preparing or saving; not completed | Shows its summary. |
| Restore Settings… | the version can be read; not working; not completed; library not being replaced | Reads the journal as it is now, any change to review and the templates, then opens the comparison. If the journal has changes to review: `messages.lifecycle.needsReview` with Review Changes. If the journal is missing or from a newer version: `library.journalHistory.cantChange` with Export Archive…. |
| Restore (confirming button, `library.journalHistory.confirm.restore`) | not saving; no other journal has the name | Puts back the name and default template. The sheets close when the list refreshed; otherwise `library.journalHistory.restored` shows in the history sheet. |
| Cancel (comparison) | not saving | Closes the comparison; nothing changes. |
| Reload History | after a failed load, or after `messages.history.versionUnavailable` | Reads the versions again. |
| Review Changes | the journal has changes to review | Opens the journal's conflict review in a nested sheet. Restoring afterwards needs a new Restore Settings…. |
| Done | not working | Closes. |

## States

| State | Copy |
| --- | --- |
| Loading | `editor.history.loading` |
| No versions | `editor.history.empty` |
| A version from a newer version | `editor.history.updateToRestore`, Export Archive… |
| Load failed | the error's own text, Reload History |
| The chosen version is no longer there | `messages.history.versionUnavailable`, Reload History |
| Changes to review | `messages.lifecycle.needsReview`, Review Changes |
| Journal missing or unsupported | `library.journalHistory.cantChange`, Export Archive… |
| The journal changed after the comparison opened | `messages.history.journalChanged`; the person opens Restore Settings… again |
| Settings already the same | `messages.history.settingsInUse` (the sheet stays, completed) |
| Restored, list not refreshed | `library.journalHistory.restored` |
| Locked | both sheets close; versions, summaries and errors are forgotten |

Errors are announced to VoiceOver.

## Rules

- Only the journal's name and default template change. Entries, their dates, and whether the journal is in Recently Deleted are untouched.
- The earlier name isn't restored while another journal in use has it; the person renames that journal first (journal names stay unique).
- The comparison shows both sides before anything is saved; a restore is one explicit action.
- A restore applies only to the journal as it was shown: if the journal changed since, the restore is refused and the person reviews again.
- Only one operation runs at a time; locking or closing cancels unfinished work.

## Accessibility

- The Version menu reads as its caption and full value.
- Each summary field reads as one element; each summary heading has the heading trait.
- Errors are announced.

## Platform notes (Apple)

- Done is the Escape action on the Mac; the confirming button of the comparison reads Restore on iPhone and iPad and Restore Settings on the Mac.

## Open questions

- None beyond [open-questions.md](../open-questions.md).
