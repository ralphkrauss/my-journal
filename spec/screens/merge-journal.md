---
id: merge-journal
title: Merge Into… (sheet)
features: [merge-journal, unique-journal-names]
sources:
  - apps/apple/JournalApp/Views/MergeJournalView.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/JournalMerging.swift
  - docs/design/journal-name-uniqueness.md
---

# Merge Into…

## Purpose

Moves every entry of one journal into another, then moves the emptied journal to Recently Deleted. Used to combine two journals, for example after syncing gave two journals similar names.

## Entry points

- `library.journalActions.mergeInto` in a journal's actions (enabled when the journal has no changes to review and another journal is in use).

## Content

Title `library.merge.title` (the journal being merged).

1. Header: `library.merge.header`.
2. The other journals in use, in the sidebar order; a checkmark on the chosen one. A journal whose name another destination shares shows `library.merge.created` under its name.
3. Footer:
   - `library.merge.footer.none`, `library.merge.footer.one` or `library.merge.footer.other`, with `{target}` = `library.merge.footer.target` once a journal is chosen, else `library.merge.footer.targetNone`.
   - When the library syncs with a server that has agent access and the journal has entries, what changes for agents (agents with All Journals are never mentioned): `library.merge.agents.unknown` when it couldn't be checked; otherwise `library.merge.agents.gainingOne` / `library.merge.agents.gainingMany` and `library.merge.agents.losingOne` / `library.merge.agents.losingMany`.
   - Error text in red (announced).
   - `common.reviewChanges` after a conflict.
   - Progress `common.merging`.

Buttons: `common.cancel` (`common.done` once the journal is gone) and `common.merge` (hidden once the journal is gone; enabled once a journal is chosen). Mac accessibility hint on Merge: `library.merge.hint`.

## Actions

**Merge:** in one step, every entry of the journal (including entries in Recently Deleted, which keep their deletion) moves to the chosen journal, and the journal moves to Recently Deleted. The sheet closes, VoiceOver announces `library.merge.merged`, and the chosen journal is shown. If the open entry was in the merged journal, it closes. Nothing changes if any entry or either journal has changes to review or was saved by a newer version.

## States

- **Busy:** controls disabled; not dismissable; the app doesn't lock for inactivity meanwhile.
- **Merged journal disappeared:** `messages.generic.journalNamedUnavailable`; only Done remains.
- **Chosen journal disappeared:** the choice clears; `common.journalGone` (before merging) or `library.merge.destinationGone` (while merging).
- **Errors:** `messages.lifecycle.needsReview` (with Review Changes), `messages.merge.newerVersion`, `messages.save.before.mergeJournal`, `library.merge.displayFailed` (then only Done).
- **Locked:** the sheet closes.

## Rules

- The merged journal can be restored from Recently Deleted, but its entries stay in the journal they were merged into.
- Merging doesn't rename anything.

## Accessibility

- The chosen row has the selected trait. Errors and the result are announced.

## Platform notes (Apple)

- **iPhone and iPad:** sheet with Cancel top left and Merge top right.
- **Mac:** sheet with the title on top, Cancel (Escape) and Merge (Return) at the bottom.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
