---
id: conflict-review
title: Review Changes (conflicts)
features: [conflict-notice, changes-to-review-list, conflict-review-journal, conflict-review-deletion, conflict-review-unsupported]
sources:
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - apps/apple/JournalApp/Views/JournalConflictView.swift
  - apps/apple/JournalApp/Views/DeletionConflictView.swift
  - apps/apple/JournalApp/Views/PermanentDeletionView.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/JournalSettingsView.swift
  - apps/apple/JournalApp/Views/DeletedJournalView.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/DeletionConflict.swift
  - docs/design/entry-conflict-accessibility.md
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - docs/design/permanent-deletion.md
  - docs/design/unsupported-conflict-review.md
---

# Review Changes (conflicts)

## Purpose

When the same entry, template or journal changed on this device and on another one, both versions are kept and the person decides. This file covers where changes to review are signalled, the list of all of them in Settings ▸ Sync, how the Review Changes sheet chooses its form, and the journal, deletion and unsupported forms. The entry and template form is in [entry-conflict.md](entry-conflict.md). The steps and outcomes are in [flows/resolve-conflict.md](../flows/resolve-conflict.md).

## Entry points

| Where | What is shown | Opens |
| --- | --- | --- |
| The open entry or template | Notice above the writing: `messages.conflict.entryNotice` and `common.reviewChanges` | the review for that record (the open writing is saved first) |
| Entries list | An exclamation-mark-in-a-circle symbol on the row, accessibility label `messages.conflict.needsReview` | the entry, by selecting it |
| Settings ▸ Sync | Section `messages.conflict.settingsSection`: one row per record with changes to review, including journals, templates and permanently deleted records | the review for that row |
| A journal's settings (Journals sheet on iPhone and iPad; journal settings on the Mac) | `messages.conflict.needsReview` and `common.reviewChanges`; the name and default-template controls are dimmed | the journal's review |
| A deleted journal shown from Recently Deleted | `common.reviewChanges` | the journal's review |
| An entry in a journal with changes to review (in Unavailable Journals) | `common.journalNeedsReview` and `common.reviewChanges` | the journal's review |
| A journal's Version History | When the journal has changes to review, the review appears in place of restoring | the journal's review |

The sidebar's journal context menu and the journal's More menu dim Rename…, Default Template and Merge Into… while the journal has changes to review.

## Content

### Changes to Review (Settings ▸ Sync)

A section titled `messages.conflict.settingsSection`, shown only when the app is unlocked and at least one record has changes to review. Each row, in the store's order:

1. Title: the record's display title (this device's version), or for a permanently deleted record `messages.conflict.deletion.deletedTitle.entry` / `.template` / `.journal`. Wraps.
2. Secondary text: its date and time (the deletion time for a permanently deleted record).
3. Button `common.reviewChanges`, accessibility label `common.reviewChangesFor`.

### The Review Changes sheet

Title `common.reviewChanges`. A cancel action (`common.cancel`, or `common.done` once completed) closes it; it is disabled, and the sheet can't be dismissed, while a choice is being saved. Content scrolls. Which form shows is decided each time it renders:

| Condition | Form |
| --- | --- |
| The app is locked | `messages.conflict.locked` (the sheet then closes) |
| Neither version is permanently deleted, both are readable, and it isn't a journal | Entry or template review |
| Either version is permanently deleted | Deletion review |
| Either version has content from a newer version | Unsupported review |
| A journal | Journal review |
| The changes no longer exist | `messages.conflict.resolved`, with `common.done` |

**Entry or template review** is specified in [entry-conflict.md](entry-conflict.md): its content, actions, states and copy are there only. It is the form for conflicts where both versions are ordinary, readable entries or templates.

**Journal review**

1. Version choice (segmented): This Device / Other Device.
2. Heading `common.thisDevice` or `messages.conflict.version.otherDevice`, the version's modification date and time, and for Other Device a disclosure `messages.conflict.journal.details` with the recorded device ID in lower case (selectable; accessibility label `messages.conflict.journal.deviceIDLabel`).
3. Summary, each a caption label over a selectable value: `common.name` (the name, or `common.untitledJournal`), `common.defaultTemplate` (the template's name, `common.blankEntry` or `messages.conflict.journal.value.unavailableTemplate`), `messages.conflict.journal.field.location` (`common.journals` or `common.recentlyDeleted`).
4. `messages.conflict.journal.keepVersion` (prominent). There is no Keep Both for journals.
5. Progress `messages.conflict.journal.loading` or `messages.conflict.savingChanges`.
6. Error, when there is one, as selectable secondary text (accessibility label `messages.conflict.journal.errorLabel`), with `messages.conflict.journal.reloadChanges`, or `messages.conflict.journal.reload` after a saved choice.

Confirmation: title `messages.conflict.journal.confirmThisDevice` or `messages.conflict.journal.confirmOtherDevice`; message `messages.conflict.journal.confirmMessage`; buttons `messages.conflict.keepVersion` and `common.cancel`. After a saved choice: `messages.conflict.journal.saved` with `common.done`.

**Deletion review** (one version deleted permanently, or both)

1. Two version blocks, each read as one element: the title (or `messages.conflict.deletion.deletedTitle.*`), a location line (`common.onThisDevice` / `messages.conflict.deletion.receivedVersion`), a device line (`messages.conflict.deletion.unknownDevice`), and the date and time.
2. When one version is edited:
   - an entry or template shows its title and a read-only preview of it with images; a journal shows the journal summary above;
   - choices, each followed by its explanation in secondary text:
     - entry: `messages.conflict.deletion.keepEntry` (`messages.conflict.deletion.keepEntryExplanation`), `messages.conflict.deletion.keepEntryAsCopy` (`messages.conflict.deletion.keepEntryAsCopyExplanation`);
     - template: `messages.conflict.deletion.keepTemplate` (`messages.conflict.deletion.keepTemplateExplanation`);
     - journal: `messages.conflict.deletion.keepJournal` (`messages.conflict.deletion.keepJournalExplanation`, and `common.restoredAsRenamed` when its name is taken);
     - always: destructive `messages.conflict.deletion.keepDeletion` with `messages.conflict.deletion.keepDeletionExplanation.journal` or `.other`.
   - After Keep Entry… or Keep Entry as Copy…: heading `common.chooseJournal`, a list of journals (journals with changes to review are left out; journals with the same name add their creation date and time, then the shortest distinguishing ID prefix), the chosen one marked with a checkmark and the selected trait, `common.newJournalEllipsis`, then `messages.conflict.deletion.selectedJournal` and `messages.conflict.deletion.confirmKeepEntry` or `messages.conflict.deletion.confirmKeepEntryAsCopy`, and `common.back`.
3. When both versions are deletions: `messages.conflict.deletion.bothDeleted.*`, `messages.conflict.deletion.bothDeletedExplanation` and the destructive `messages.conflict.deletion.keepDeletion`.
4. Progress `common.pleaseWait`; an error as selectable secondary text; after an error, `messages.conflict.deletion.reviewAgain` or `common.reloadJournals`, or Export Archive… when a version can't be read.

Keep Deletion's confirmation is a sheet titled `messages.conflict.deletion.confirmDeleteEdited.*` (an edited version) or `messages.conflict.deletion.confirmKeepDeleted.*` (both deleted). It shows the edited version's title (and an entry's date) with `messages.conflict.deletion.keepDeletionExplanation.*`, or the deletion's block (location `messages.conflict.deletion.deletionToKeep`) with `messages.conflict.deletion.remainingVersionsRemoved`; then `messages.conflict.deletion.consequence.sync`, `.copies` and `.noUndo`; the destructive `messages.conflict.deletion.deletePermanently`; and `messages.conflict.deletion.deleting` while it runs.

**Unsupported review** (a version from a newer version of My Journal)

`messages.conflict.updateToReview`, then Export Archive… (the archive export control of Settings ▸ Backup, including its one-time password check). Nothing can be resolved; both versions stay. The journal review has its own copy of this form (the same text and Export Archive…, followed by `messages.save.before.exportArchiveForConflict` while a save has failed), used only if its versions become unreadable after Reload Changes, because the sheet routes unreadable versions here first.

## Actions

| Action | Enabled | Result |
| --- | --- | --- |
| Review Changes | unlocked, the library not being replaced | Saves the open entry, then opens the sheet; if the save fails, nothing opens and the save-failure alert shows |
| Entry or template actions | as [entry-conflict.md](entry-conflict.md) (Actions) | |
| Keep Version… (journal) | not busy, both versions readable | Confirmation, then saves |
| Keep Entry… / Keep Entry as Copy… | not busy | Shows the journal list |
| Keep Template, Keep Journal | not busy | Saves at once |
| Keep Deletion… | not busy | Destructive confirmation |
| Try Again, Reload, Reload Changes, Review Again, Reload Journals | not busy | Reads the conflict again; never repeats a choice |
| Cancel / Done | not busy | Closes the sheet; work not yet committed stops, committed work stays |

## States

- **Loading / busy:** progress labels above; choices dimmed; the sheet can't be dismissed.
- **Updated meanwhile:** `messages.conflict.updatedReviewAgain` (journal, deletion); the choice is cleared and This Device is shown. The entry form has its own ([entry-conflict.md](entry-conflict.md), States).
- **Saved but not displayed:** `messages.conflict.journal.savedNotDisplayed` or `messages.conflict.deletion.savedNotDisplayed`; the entry form's is in [entry-conflict.md](entry-conflict.md).
- **Resolved elsewhere:** `messages.conflict.resolved` with Done.
- **Locked:** the sheet closes and forgets everything it showed, including previews and images; `messages.conflict.locked` shows if it renders while locked. The Changes to Review section is hidden while locked.
- **Unsupported:** see above.
- **Error:** other failures show their own message (for example `messages.conflict.deletion.journalUnavailable`, `messages.conflict.deletion.updateToReview`).

## Rules

- The entry and template form's rules, including its placement lines, are in [entry-conflict.md](entry-conflict.md).
- Both versions are kept until the person chooses; every choice stores both originals in Version History first.
- A choice applies only to the versions shown: if either changed, the store refuses it and the review reads them again. A stale choice is never applied, and a committed one is never applied twice.
- A record with changes to review can still be opened and edited on this device; its writing is saved locally but isn't sent to the server until the changes are reviewed.
- A journal with changes to review can't be renamed, given a default template, merged or deleted; its entries show in Unavailable Journals until it is reviewed.

## Accessibility

- Errors in the journal and deletion reviews are announced.
- Each deletion-review version block, each journal summary field, and each Changes to Review row's title and date read as one element; the destination checkmark is hidden and the row has the selected trait.
- The preview's text follows the body text size.
- Nothing is told by colour alone; the destructive actions are marked destructive.

## Platform notes (Apple)

- **iPhone and iPad:** the sheet has an inline navigation title with Cancel or Done in the cancel position. The entry notice sits above the writing; at accessibility sizes its text stacks above the button.
- **Mac:** the sheet has its title at the top, scrolling content, and a footer with Cancel or Done; minimum about 360 × 400 points. Escape closes the entry, deletion and unsupported forms; the journal form's Cancel has no Escape shortcut (see Open questions).
- The entry-row symbol is the system's exclamation mark in a circle.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
