# Inherited journal lifecycle proposal review

Date: 2026-09-20. Independent product/interaction and preservation review of `journal-lifecycle-proposal.md`. No protocol implementation or tests inspected; this is not a proof of distributed correctness.

## Outcome

**The parent-inherited visibility model is a reasonable simplification, but its changed recovery interaction needs the refinements below before frontend implementation.** It can preserve the essential user outcome: restore an entire journal without reviving independently deleted entries, or recover one entry while keeping the parent and siblings deleted. Moving the single recovered entry into another journal is a visible change from the formerly approved “restore parent and just this child”; this must be reflected consistently in the UI and docs, not described as the same operation.

Positive properties: one parent tombstone avoids delayed child-cascade messages undoing a restore; child bodies/identities remain intact; independent child deletion remains separate; late offline children receive the current parent's effective location; moving out has explicit ownership semantics. Offline-local counts are honestly qualified, and rejecting changed local confirmation membership/name is appropriate. Effective visibility must be shared by agent/search/editor readers as proposed.

## Required refinements

1. **Keep single-entry recovery possible when no live journal exists.** An existing-live-journal-only Move picker leaves users with only Restore Journal (all children) after deleting their last journal. Specify a native New Journal…/Manage Journals route that creates a destination and returns to the captured recovery entry, or another concrete equivalent. Do not silently create a destination or force whole-journal restoration. Keep the parent deleted and preserve identity/history/images of the recovered child.
2. **Make recovery action labels describe the effect.** A parent-hidden live entry may use Move Entry… and final Move, with brief context that only this entry moves to the chosen journal. An independently deleted entry must say Restore and Move… and final Restore and Move. Restore Journal must explicitly say that all entries except those independently deleted become available, including entries that later sync. No parent-and-single-child wording may remain on this flow. Avoid a single generic Restore button whose effect changes silently by hidden tombstone state.
3. **Define discoverability for unavailable parents.** “Missing parents are unavailable, never assumed live” is safe for access control, but cannot make saved entries disappear from every user-facing recovery path. Specify where a persistently missing/unsupported parent's entries can be found, previewed read-only, and losslessly exported, with the already reviewed conditional sync/update/local-unavailable actions. Temporary partial-sync absence must not be presented as irreversible deletion. Do not broaden agent access to unavailable records.
4. **Define the legacy boundary before enabling the feature.** Compatibility migration or explicit refusal is still a placeholder. Select one and specify the actual UI consequence for existing `deletedWithJournal` records/archives. Refusal must preserve/export content and say why the requested restore cannot proceed; a migration must distinguish independent deletion and repeated cycles without guessing. Changing new writes alone is insufficient if old archives can reintroduce ambiguous markers.

Re-review these user-facing decisions and the chosen compatibility behavior before implementing lifecycle UI. The representation itself can proceed as a candidate for focused protocol/store validation, without claiming the full feature approved.

## Required correctness evidence

Test both parent/child arrival orders; restore before late child arrival; repeated parent cycles; independently deleted child recovery; concurrent move to live and deleted destinations; unresolved parent conflict; no-live-destination recovery; stale local confirmation set; unknown/legacy records; and consistent visibility for every reader. A parent conflict must not silently choose whichever version makes contents visible. Confirm references/history/attachments survive single-child recovery and that a stale retained draft cannot restore old parent membership or tombstone state.

Permanent purge remains separate and incomplete. Inherited visibility is recoverable organization, not erasure from encrypted histories, archives, or backups.

## Refinement re-review — 2026-09-20

**The revised user-facing semantics are approved.** The new choices resolve the four requested interaction/compatibility gaps:

- A nested New Journal sheet returns to the captured entry's recovery picker without moving or selecting automatically. Single-entry recovery remains available when all journals are deleted, while siblings/parent stay deleted.
- Move versus Restore and Move now visibly reflects whether the entry's own tombstone is cleared. Whole-journal restoration is separate and includes later-arriving nonindependently-deleted children. These explicitly replace the former parent-plus-single-child behavior.
- Unavailable Journals gives otherwise hidden entries a read-only, losslessly exportable recovery path with accurate sync/update/local-only guidance. It does not expand editable or agent-visible content.
- Legacy markers are never guessed or bulk-restored. Explicit individual Restore and Move can clear a supported entry's legacy marker/tombstone while preserving its content/history; unsupported content remains exportable and read-only. New writes cannot recreate ambiguous cascade markers. This is a concrete conservative compatibility boundary.

Small copy correction: replace “Restore it to a journal to keep it” with “Choose a journal to restore this entry.” The old phrase implies eventual loss unless the user acts, contradicting indefinite retention. Keep the preceding explanation about the earlier Journal version. No further design round is needed for this correction.

**Gating outcome:** these proposals may guide implementation, but the full deletion/restoration feature must not be exposed until the prerequisite journal-conflict flow is implemented and the shared lifecycle semantics are implemented/tested across normal navigation, search, agents, recovery collections, archives and sync. Parent conflicts must use one explicit, consistent visibility policy; do not choose whichever snapshot happens to reveal content. Real-store/replica evidence is still needed for the previously listed delivery orders, cycles, late entries, independent deletion, legacy archives and unsupported parents. This re-review approves the interaction decisions, not unimplemented distributed correctness.

No UI or protocol implementation was inspected in this re-review. Permanent purge and direct journal-history restoration remain separately unfinished.
