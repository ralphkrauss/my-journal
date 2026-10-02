# Journal deletion/restoration proposal review

Date: 2026-09-20. Independent review of `journal-deletion.md` against `AGENTS.md` and approved `screens.md` revision 2. Proposal review only; no new deletion/restoration implementation inspected or edited.

## Outcome

The recoverable journal tombstone, explicit affected-entry count, last-journal empty state, separate Recently Deleted sections, and narrowly scoped Restore Journal and Entry action fit the native design. Atomic local mutation and retained-draft reconciliation are appropriate. **Request the interaction revisions below before implementation.** They concern meaningful failure recovery and the deletion confirmation, not a new visual system.

Deferring permanent erasure is appropriate for this bounded increment: the existing revision log and backups make an irreversible-erasure promise inaccurate. Record permanent purge as unfinished agreed functionality rather than marking all deletion work complete. No automatic retention deadline should be invented.

## Required revisions

1. **Provide a reachable conflict recovery action for journal metadata.** “Review changes before deleting this journal” is actionable only if users can actually review the affected conflict. Current entry conflict UI does not establish a usable journal-name/default-template conflict review. Specify how the error routes to the conflicting journal or entry and what a journal metadata review shows. If this depends on an unfinished conflict interaction, make that prerequisite explicit; do not strand users on a retry that cannot succeed. Restore has the same need when a parent/child metadata conflict blocks it. Avoid broadening this into a new merge editor: reuse a clear existing review path where it really supports the record type.
2. **Distinguish missing and unsupported parent journals.** “This journal is unavailable. Try syncing again” is not correct for an unsupported format or a local-only vault. Unsupported parent: “Update Journal to restore this entry.” Missing parent with configured sync: explain that the journal has not arrived and offer Try Syncing Again. Missing parent without a server: state that the journal is unavailable and suggest restoring another archive copy only if that supported route can preserve/recover the relationship; otherwise provide accurate preservation copy rather than a nonexistent sync remedy. In every case retain the entry and allow export where lossless export is possible.
3. **Keep confirmation aligned with the actual affected records.** Capture the journal ID, but also ensure the displayed live-entry count describes the delete being committed. If synchronization adds/moves/restores entries after confirmation is shown, revalidate/update the affected set before commit and return for renewed confirmation if the action now includes additional entries the user was not shown. Continue refusing unresolved conflicts atomically. This prevents a confirmation for two entries silently deleting newly arrived work as well.

Re-review these decisions before implementation. The approved layout and ordinary tombstone/restore behavior do not need redesign.

## Native copy and accessibility notes

- Use a standard destructive confirmation with a separate Cancel action and safe default, as proposed. Keep names as content and action labels concise.
- Recently Deleted's “Deleted items stay here until you restore them” is honest for this increment. Show it once as secondary contextual copy, not on every row.
- Deleted journal rows should expose name, item kind, and count to VoiceOver. Distinguish an empty deleted journal from an empty Recently Deleted collection; use “No Deleted Items” when the whole collection is empty.
- On deleting the active/last journal, clear the editable selection only after successful commit; keep New Journal and Recently Deleted reachable so the user can recover without an automatic replacement journal.
- If several selected records block restoration, identify the relevant conflict or unavailable parent without dumping internal IDs or implementation errors. Keep error/recovery controls in the active sheet rather than relying on an underlying global alert.

## Required implementation verification

The proposed focused real-store tests are meaningful. Include deletion count changing while confirmation is open, an independently deleted child, journal deletion split across sync pages, restore after partial remote receipt, lock exactly around commit, failed local save with lossless export, last-journal deletion/relaunch/restore, and unsupported parent/child content. Verify restored entries retain their parent relationship and no later stale draft save resurrects a deleted item.

Inspect native empty/list/detail/confirmation states on iPhone and limited offscreen Mac renders, stating the evidence precisely. Keyboard, VoiceOver, large text, and actual Mac interaction remain separate requirements; an offscreen render cannot establish them.

## Prerequisite-decision re-review — 2026-09-20

**The appended review revisions are accepted. Journal deletion/restoration remains gated on the two explicitly unfinished prerequisites below.** This is not blanket implementation approval.

- The captured live-entry set and atomic membership recheck resolve the stale-count finding. A changed set returns to review with a refreshed count and requires fresh explicit confirmation; it is not silently retried. Refresh the displayed journal name as part of that renewed confirmation if it changed.
- Active-sheet Review Changes now has a defined route and preserves the pending action without automatically resubmitting it. Separating journal metadata review from entry Keep Both avoids silently copying/reparenting a journal's entries. The planned separate metadata proposal still needs its independent review, including unambiguous device/time identity, recoverable original history, and unsupported-content behavior. The generic This Device/Other Device labels in this prerequisite sketch do not supersede the earlier device/time labeling requirement.
- Missing versus unsupported parents now have accurate, distinct copy and real actions. Local-only missing-parent handling preserves/export the entry without falsely promising archive relinking or a sync option. This resolves the earlier misleading-remedy finding.
- Identifying `deletedWithJournal` as insufficient is correct. Distinct deletion cycles and late child tombstones must be represented so a completed restore cannot later be undone or independently deleted entries revived merely by page order. No wall-clock last-write-wins workaround is acceptable.

**Required before implementing this feature:** (1) separately review the concrete native journal metadata conflict flow, and (2) settle and test the deletion/restoration protocol, including partial delivery, separate cycles, and independent deletions. The visual proposal itself does not need broader scope. Permanent purge remains honestly deferred as already described. No new UI or protocol implementation was inspected in this re-review.
