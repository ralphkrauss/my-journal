---
id: conflict-review
title: Review Changes (conflicts)
features: [conflict-notice, changes-to-review-list, conflict-review-unsupported]
sources:
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/EntryRecoveryNotice.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - docs/design/entry-conflict-accessibility.md
  - docs/design/stale-conflict-recovery.md
  - docs/design/unsupported-conflict-review.md
  - docs/design/1-1-conflicts-and-reconnect.md
---

# Review Changes (conflicts)

## Purpose

When the same entry or template changed on this device and on another one, and the two versions differ, both are kept and the person decides. This file covers where those changes to review are signalled, the list of all of them in Settings ▸ Sync, and how the Review Changes sheet chooses its form: the entry and template form, or the form for a version this app can't read. The entry and template form is in [entry-conflict.md](entry-conflict.md). The steps and outcomes are in [flows/resolve-conflict.md](../flows/resolve-conflict.md).

Journals and permanent deletions have no review: the device settles them itself and lists them under Changed on Two Devices ([settings-sync.md](settings-sync.md), [flows/resolve-conflict.md](../flows/resolve-conflict.md)). A version of a journal this app can't read stays held and is told only by a line in the Sync footer.

## Entry points

| Where | What is shown | Opens |
| --- | --- | --- |
| The open entry or template | Notice above the writing: `messages.conflict.entryNotice` and `common.reviewChanges` | the review for that record (the open writing is saved first) |
| Entries list | An exclamation-mark-in-a-circle symbol on the row, accessibility label `messages.conflict.needsReview` | the entry, by selecting it |
| Settings ▸ Sync | Section `messages.conflict.settingsSection`: one row per entry or template with changes to review, including those saved by a newer version | the review for that row |

Move Entry of an entry with changes to review also offers `common.reviewChanges` when the conflict blocks the move ([move-entry.md](move-entry.md)).

Delete Permanently on an entry or template with changes to review is refused like an item that changed meanwhile ([flows/delete-and-restore.md](../flows/delete-and-restore.md), States); there is no separate alert.

## Content

### Changes to Review (Settings ▸ Sync)

A section titled `messages.conflict.settingsSection`, shown only when the app is unlocked and at least one entry or template has changes to review. It sits beside Changed on Two Devices ([settings-sync.md](settings-sync.md)). Each row, in the store's order:

1. Title: the item's display title (this device's version). Wraps.
2. Secondary text: its date and time.
3. Button `common.reviewChanges`, accessibility label `common.reviewChangesFor`.

### The Review Changes sheet

Title `common.reviewChanges`. A cancel action (`common.cancel`, or `common.done` once completed) closes it; it is disabled, and the sheet can't be dismissed, while a choice is being saved. Content scrolls. Which form shows is decided each time it renders:

| Condition | Form |
| --- | --- |
| The app is locked | `messages.conflict.locked` (the sheet then closes) |
| Both versions are readable | Entry or template review |
| Either version has content from a newer version | Unsupported review |
| The changes no longer exist | `messages.conflict.resolved`, with `common.done` |

**Entry or template review** is specified in [entry-conflict.md](entry-conflict.md): its content, actions, states and copy are there only.

**Unsupported review** (a version from a newer version of My Journal)

`messages.conflict.updateToReview`, then Export Archive… (the archive export control of Settings ▸ Backup, including its one-time password check). Nothing can be resolved; both versions stay.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Review Changes | `review-changes` | unlocked, the library not being replaced | Saves the open entry, then opens the sheet; if the save fails, nothing opens and the save-failure alert shows |
| Entry or template actions | | as [entry-conflict.md](entry-conflict.md) (Actions) | |
| Cancel / Done | | not busy | Closes the sheet; work not yet committed stops, committed work stays |

## States

- **Loading / busy:** progress labels in the entry form; choices dimmed; the sheet can't be dismissed.
- **Resolved elsewhere:** `messages.conflict.resolved` with Done.
- **Locked:** the sheet closes and forgets everything it showed, including previews and images; `messages.conflict.locked` shows if it renders while locked. The Changes to Review section is hidden while locked.
- **Unsupported:** see above.
- **Error:** other failures show their own message in the entry form ([entry-conflict.md](entry-conflict.md), States).

## Rules

- The entry and template form's rules, including its placement lines, are in [entry-conflict.md](entry-conflict.md).
- Both versions are kept until the person chooses; every choice stores both originals in Version History first.
- A choice applies only to the versions shown: if either changed, the store refuses it and the review reads them again. A stale choice is never applied, and a committed one is never applied twice.
- An entry or template with changes to review can still be opened and edited on this device; its writing is saved locally but isn't sent to the server until the changes are reviewed.
- A journal never has changes to review. Rename, Delete Journal and Restore Journal are never dimmed for a conflict; a journal whose conflict is held behaves like one saved by a newer version ([unavailable-content.md](unavailable-content.md)).
- Entries and templates saved by a newer version are listed in Changes to Review but can't be reviewed until My Journal is updated.

## Accessibility

- Each Changes to Review row's title and date read as one element.
- The preview's text follows the body text size.
- Nothing is told by colour alone; the destructive actions are marked destructive.

## Platform notes (Apple)

- **iPhone and iPad:** the sheet has an inline navigation title with Cancel or Done in the cancel position. The entry notice sits above the writing; at accessibility sizes its text stacks above the button.
- **Mac:** the sheet has its title at the top, scrolling content, and a footer with Cancel or Done; minimum about 360 × 400 points. Escape closes the entry and unsupported forms.
- The entry-row symbol is the system's exclamation mark in a circle.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
