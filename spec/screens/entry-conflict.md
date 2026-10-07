---
id: entry-conflict
title: Review Changes (entry or template)
features: [conflict-review-entry]
sources:
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/SettingsView.swift (ConflictNotice, ConflictSettingsSection)
  - apps/apple/JournalApp/Views/PermanentDeletionView.swift (DeletionSheet)
  - apps/apple/JournalApp/Editor/ExternalEdits.swift
  - apps/apple/JournalTests/StaleDraftTests.swift
  - docs/design/entry-conflict-accessibility.md
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - protocol/README.md (sync and conflicts)
---

# Review Changes (entry or template)

## Purpose

When this device and another device both changed the same entry or template, show both versions side by side in turn and let the person keep both or keep one. Nothing is merged and nothing is lost: the other versions remain in Version History.

## Entry points

Where the review is signalled and how it is opened (the notice above the entry, the marked row, Settings ▸ Sync ▸ Changes to Review) is in [conflict-review.md](conflict-review.md) (Entry points). It also opens nested from Move Entry and Version History when a conflict blocks them. The notice's `common.reviewChanges` first saves the open writing and refreshes, then opens this sheet; the notice itself is `messages.conflict.entryNotice`.

This screen covers conflicts where both versions are ordinary, readable entries or templates. Others route elsewhere ([conflict-review.md](conflict-review.md), The Review Changes sheet): a permanent deletion on either side opens the deletion review; a journal opens the journal review; a version this app can't read shows `messages.conflict.updateToReview` with the Export Archive… control. The outcomes are in [flows/resolve-conflict.md](../flows/resolve-conflict.md).

## Content

A sheet titled `common.reviewChanges`. Phone and tablet: navigation bar with `common.cancel` (or `common.done` once resolved) at the leading end; at accessibility text sizes the title is repeated as a heading in the content. Computer: title at the top, scrolling content, divider, then Cancel/Done (Escape); 360–480 pt wide, 400–600 pt tall.

Scrolling content:

1. **Status** (secondary text, when there is one): `messages.conflict.status.updated`, `messages.conflict.status.refreshFailed`, or an error text.
2. **Version** choice: a segmented control labelled `common.version` with `common.thisDevice` and `messages.conflict.version.otherDevice`. At accessibility text sizes: a menu button showing the chosen value with an up-down chevron.
3. The shown version's **title** (title 2 style), its **last change time** (secondary, date and time), and when the two versions differ in place or date, a **placement line** (secondary): `messages.conflict.placement.inJournal`, `messages.conflict.placement.inJournalDated`, `messages.conflict.placement.inRecentlyDeleted`, `messages.conflict.placement.inRecentlyDeletedDated`, `messages.conflict.placement.inTemplates`, `messages.conflict.placement.inTemplatesDated`, `messages.conflict.placement.archivedIn`, `messages.conflict.placement.archivedInDated` or `messages.conflict.placement.dated`.
4. A **read-only preview** of that version, 300 pt tall, with its formatting and images; accessibility hint `messages.conflict.version.hintThisDevice` or `messages.conflict.version.hintOtherDevice`.
5. **Keep Both note** (callout, secondary): `messages.conflict.keepBothNote.entries` or `messages.conflict.keepBothNote.templates`, followed when relevant by `messages.conflict.keepBothOutcome.placeAndDate`, `messages.conflict.keepBothOutcome.place` or `messages.conflict.keepBothOutcome.date`.
6. **`messages.conflict.keepBoth`** (prominent button).
7. **`messages.conflict.keepOne`** (menu): `messages.conflict.keepThisDevice`, `messages.conflict.keepOtherDevice`.
8. While working: progress indicator with `messages.conflict.savingChanges` or `messages.conflict.updatingChanges`.

## Actions

| Action | Enabled | Result |
| --- | --- | --- |
| Switch version | Not busy | Shows the other version; images load for it. |
| Keep Both | Not busy | First saves the open writing (failure: `messages.save.before.resolveEntryConflict`). Keeps both versions as separate entries (or templates), each where it is with its date. The sheet closes and the entry opens as it's now stored. |
| Keep One Version ▸ Keep Version from This Device… / Other Device… | Not busy | Confirmation dialog `messages.conflict.keepOne.title`, message: for the other device's version, what will happen to the entry (`messages.conflict.outcome.entry.*` or `messages.conflict.outcome.template.*`: move, archive, date change) followed by `messages.conflict.keepOne.history`; for this device's version only `messages.conflict.keepOne.history`. Buttons `messages.conflict.keepVersion` and Cancel. Then as Keep Both, keeping only that version. |
| Try Again | After a failed refresh, or after a commit whose reload failed | Refreshes the review, or reloads the resolved entry. |
| Cancel / Done | Not busy | Closes; nothing changes (Cancel) or the result stays (Done). |

## States

| State | What shows |
| --- | --- |
| Reviewing | As in Content. |
| The conflict changed while open (another device sent more) | `messages.conflict.status.updated`; the view returns to This Device, any confirmation closes. VoiceOver focus moves to the status. |
| Refresh failed | `messages.conflict.status.refreshFailed` with `common.tryAgain`. |
| Saved, entry couldn't be reloaded | `messages.conflict.committedNotReloaded` with `common.tryAgain`. |
| Resolved (elsewhere, or no longer a conflict) | `messages.conflict.resolved`; the button is Done. |
| Locked | `messages.conflict.locked` if shown; locking closes the sheet and cancels unfinished work. |
| Library being replaced | The sheet closes. |

## Rules

- A conflict exists when this device saved a change based on a version older than the one the server or another device stored, including typing over a change that arrived but wasn't shown yet (`StaleDraftTests.testAnOpenEntryFollowsOtherDevicesAndTypingOverAnUnseenChangeKeepsBoth`). An entry that arrived from another device while it was open and unchanged here simply updates; it is never a conflict (`StaleDraftTests.testAnEmptyNewEntryWrittenOnAnotherDeviceIsNotOverwrittenWhenLeft`).
- The entry stays editable while it has a conflict; further writing is part of this device's version.
- Each choice keeps a version where it is (its journal or Recently Deleted) with its date; the placement line and outcome sentences say where.
- Resolution is one change; the original versions remain in Version History.
- Only one resolution runs at a time; a resolution never runs automatically after a refresh.

## Accessibility

- The version control reads `common.version` and its value. The preview's hint names the version.
- After a refresh, VoiceOver focus moves to the status line.
- Buttons are standard; the confirmation is a standard dialog (Return/Escape).
- Text wraps at every size; the version control becomes a menu at accessibility sizes.

## Platform notes (Apple)

- Same content on every platform; the sheet frame (`DeletionSheet`) differs as described.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
