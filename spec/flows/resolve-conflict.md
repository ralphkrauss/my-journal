---
id: resolve-conflict
title: Resolve changes to review
features: [conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-journal, conflict-review-deletion, conflict-review-unsupported]
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncReconciliation.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/DeletionConflict.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - apps/apple/JournalApp/Model/PermanentDeletionOperations.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - apps/apple/JournalApp/Views/JournalConflictView.swift
  - apps/apple/JournalApp/Views/DeletionConflictView.swift
  - docs/design/entry-conflict-accessibility.md
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - docs/design/permanent-deletion.md
---

# Resolve changes to review

## Purpose

Conflicting edits are never overwritten silently. Both versions are kept until the person chooses one, both, or the deletion, and both originals stay in Version History. The screens are in [screens/conflict-review.md](../screens/conflict-review.md).

## Entry points

Changes to review appear when:

- **sync receives a version** of an entry, template or journal that this device also changed and hasn't sent yet, or that differs from this device's version when a library joins a server by identity;
- **this device saves over a version that changed meanwhile** (for example a sync arrived between reading and saving): the change that arrived is kept for review instead of being overwritten;
- **one side deleted the record permanently** while the other edited it, or both deleted it with different histories;
- **merging or importing** finds the same record in two different versions.

The person then reaches the review from the entry's notice, the entries list (by opening the marked entry), Settings ▸ Sync ▸ Changes to Review, a journal's settings, a deleted journal, an entry whose journal has changes, or a journal's Version History.

## Steps

### 1. Open the review

1. The open entry's writing is saved first. If that fails, the review doesn't open and the save-failure alert explains (see [flows/save-failure.md](save-failure.md)).
2. The sheet decides its form from the current versions: entry or template, journal, deletion, or unsupported. If the changes are already gone it shows `messages.conflict.resolved`.

### 2a. Entry or template

1. The person compares This Device and Other Device: title, modification date, where each version is (`messages.conflict.placement.*`, only when they differ), and the full text with images.
2. **Keep Both.** The pending save of the open entry finishes first (failure: `messages.save.before.resolveEntryConflict`, nothing changed). Then this device's version stays as the record, and the other device's version becomes a new, separate entry (or template) where that device had it, with its own date. Both are sent.
3. **Keep Version from This Device… / Other Device….** Confirmation `messages.conflict.keepOne.title` with `messages.conflict.keepOne.history`; for Other Device, what happens to the entry here comes first (`messages.conflict.outcome.*`: it moves, is archived, or changes date). Keep Version saves the chosen version as the record; the other is kept only in Version History.
4. **Outcome.** The changes are marked resolved, the journals are read again, the resolved entry opens, and the sheet closes. No success message.

### 2b. Journal

1. The person compares name, default template and location for each version; Other Device's Details shows the recorded device ID.
2. **Keep Version….** Confirmation (`messages.conflict.journal.confirmThisDevice` or `messages.conflict.journal.confirmOtherDevice`, message `messages.conflict.journal.confirmMessage`). The open entry is saved first (failure: `messages.save.before.reviewChanges`). The chosen metadata becomes the journal's; its entries don't move or copy. There is no Keep Both.
3. **Outcome.** `messages.conflict.journal.saved` with Done. The journal's controls are enabled again and its entries leave Unavailable Journals.

### 2c. Deletion

The review is prepared first (`common.pleaseWait`), saving the open entry (failure: `messages.save.before.reviewChanges`).

| Case | Choices | Outcome |
| --- | --- | --- |
| Edited entry against a deletion | Keep Entry… → choose a journal (or New Journal…) → Keep Entry | The edited entry is kept in the chosen journal; earlier versions already deleted aren't restored |
| | Keep Entry as Copy… → choose a journal → Keep Entry as Copy | A new entry with the edited content in the chosen journal; the original stays deleted |
| Edited template against a deletion | Keep Template | The template is kept |
| Edited journal against a deletion | Keep Journal | The journal's name and template are kept (renamed with a number if the name is taken, `common.restoredAsRenamed`); deleted entries aren't restored |
| Any of the above | Keep Deletion… → confirmation → Delete Permanently | The edited version and its earlier versions are removed from this device, and the deletion syncs |
| Both versions are deletions | Keep Deletion… → confirmation → Delete Permanently | Any remaining earlier versions are removed from this device |

On success the sheet closes. The deletion syncs to other connected devices; copies may remain in archives, backups and server history; it can't be undone.

### 2d. Unsupported

A version has content this version of My Journal can't read. The person can only Export Archive… to keep a copy (the archive includes both versions and history) or Cancel. Updating My Journal makes the review possible.

### 3. When something changes meanwhile

| What happened | Entry review | Journal review | Deletion review |
| --- | --- | --- | --- |
| The versions changed while the sheet was open, or the store refused a choice as stale | Reads them again (`messages.conflict.updatingChanges`), then `messages.conflict.status.updated`; This Device shown, choice cleared, focus on the status | `messages.conflict.updatedReviewAgain` with Reload Changes | `messages.conflict.updatedReviewAgain` with Review Again |
| Reading them again failed | `messages.conflict.status.refreshFailed` with Try Again; previews hidden | the error with Reload Changes | the error with Review Again |
| The choice was saved, but showing the result failed | `messages.conflict.committedNotReloaded` with Try Again (reloads only) and Done | `messages.conflict.journal.savedNotDisplayed` with Reload | `messages.conflict.deletion.savedNotDisplayed` |
| Resolved on another device | `messages.conflict.resolved` with Done | the same | the same |
| The chosen journal became unavailable | | | `messages.conflict.deletion.journalUnavailable` with Reload Journals |
| A version became unreadable | the sheet switches to the unsupported form | the journal review's unsupported form | `messages.conflict.deletion.updateToReview` with Export Archive… |
| The app locked | the sheet closes; uncommitted work stops; nothing it showed is kept | the same | the same |
| Any other failure | its message as the status; choices kept for retry | its message with Reload Changes | its message with Review Again |

## Rules

- Both versions are kept until a choice is saved; every choice records both originals in Version History in the same transaction.
- A choice is bound to the versions it was made on. The store rejects it if either changed; the app never replays it.
- Once a choice is committed, cancelling, locking or a failed refresh never undoes or repeats it.
- While a record has changes to review it can be edited and saved on this device, but its changes aren't sent until it is resolved.
- While a journal has changes to review: rename, default template, Merge Into… and Delete are unavailable, its entries are listed in Unavailable Journals, and New Entry from a template with changes to review is refused (`messages.generic.templateNeedsReview`).
- Changes to review count as a problem for the rating request: it isn't shown while any exist.
- Keep Both is offered only for entries and templates.

## Accessibility

- The entry review's status receives VoiceOver focus after an explicit refresh; errors in the journal and deletion reviews are announced.
- No success announcement; the sheet closing and the entry opening are the feedback.
- Confirmation dialogs are standard; Keep Deletion's confirmation marks Delete Permanently as destructive.

## Platform notes (Apple)

- Identical behaviour on iPhone, iPad and Mac; only sheet chrome differs (see the screen file).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
