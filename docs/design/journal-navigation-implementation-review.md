# Journal lifecycle navigation implementation review

Date: 2026-09-20. Independent source review of `JournalNavigation`, `JournalOperations`, shared `commitMutation`, recovery notices/new-journal sheet, RootView collections, MoveEntry recovery, and relevant lifecycle/store rules. No implementation edits, independently executed tests, or rendered inspection in this pass. Delete/whole-journal restore methods exist, but their UI is not yet exposed and is not treated as complete.

## Findings

1. **P2 — A parent becoming available does not return the selected entry to its collection.** `refresh()` switches a retained draft into Recently Deleted or Unavailable Journals when its effective location changes, but `.journal` does nothing. If sync supplies the missing parent or resolves its conflict, the selected entry can remain under the Unavailable Journals heading even though it becomes editable and disappears from that collection's list. Reconcile the reverse transition too: preserve the captured entry/content, select its now-live journal, and return the normal collection without stealing editing focus or duplicating the entry. Verify both missing-parent arrival and parent-conflict resolution.
2. **P2 — Post-commit new-journal refresh failure still enables duplicate creation.** `RecoveryJournalView` sets `created = true` and changes Cancel to Done, but leaves Name/Create enabled after reporting that the journal was created but could not be displayed. A retry creates another journal rather than reloading the first. After commit, replace/disable Create and offer only Done/Reload as appropriate; retain the original entry and show the committed destination unselected once refresh succeeds. This is the same durable-outcome rule already applied to move/import.
3. **P2 — Lifecycle failures can surface as opaque implementation errors.** `JournalLifecycleError` is a plain Error enum; move/recovery paths display `localizedDescription` without mapping missing/unsupported/conflicted state into the approved copy/actions. A conflict arriving during commit can therefore produce a generic module/error-code string rather than Review Changes. Map typed failures to the accurate unavailable/update/conflict message and reachable review action, preserving selection/draft. A still-supported destination can remain selected on retry, but never automatically replay a changed operation.
4. **P2 — Missing-parent legacy recovery is narrower than the approved compatibility route.** Unavailable entries receive only update/sync/review plus export, and core `restoreAndMoveEntry` requires a present supported source parent. The lifecycle refinement promised explicit individual recovery for supported legacy-marker entries also discoverable in Unavailable Journals. Record and resolve this boundary explicitly: either implement the reviewed safe individual legacy Restore and Move under a live supported destination, or revise the proposal to say unavailable legacy entries remain export-only until their parent can be recovered. Do not quietly claim the full legacy recovery route is implemented, and do not relax unsupported-record mutation protections as a shortcut.

## Source matches

A shared lifecycle snapshot now drives live journal availability, effective entry collections, and `canEdit`; unsupported/missing/conflicted parents cannot leave children in the ordinary editable timeline. User edits are gated through `canEdit`. Unavailable Journals is reachable from the journal menu, with a dedicated search scope and read-only entry preview/export. Missing-parent copy correctly distinguishes configured sync from local-only storage; parent conflict has a metadata-review route.

Move preserves captured entry identity, exposes Move versus Restore and Move, and keeps nested creation from switching the root draft. Destination creation uses the owned shared mutation path with no automatic destination selection. Shared commit ownership reconciles before lifecycle flush and separates committed work from refresh failures. Legacy-marked entries with an available supported parent remain individually discoverable rather than bulk-restored. Lock closes nested sheets and hides sensitive state.

Minor copy/layout notes: the “Only this entry will move…” explanation is currently shown only for `restoring == true`, while the approved parent-hidden/nonindependently-deleted recovery path also calls for it. `RecoveryJournalView` has no explicit Name focus, error announcement, or scroll container; check its real small-screen/keyboard/large-text behavior and use the established native patterns as needed. These are not grounds to invent extra permanent copy or a new navigation system.

## Outcome and remaining evidence

The integration is materially closer to the approved shared visibility model, but the reverse-navigation, duplicate-create, and typed-error paths need correction before calling this recovery increment complete. The legacy boundary needs an explicit resolution. No rendered/interactive approval is given here. Verify missing-parent arrival, conflict resolution, no-live-destination creation, post-commit refresh failure, legacy recovery, wrong destination, failed save/export, lock around commit, keyboard/VoiceOver, and large text. Whole-journal deletion/restoration and permanent purge remain separately unfinished.

## Source fixes and offscreen Mac previews — 2026-09-20

Independently viewed these **offscreen native Mac renders**, normal-size light appearance:

- `artifacts/journal-recovery-mac-previews/15198EB4-A0E2-49C7-8EA5-6020B8814241.png`: Move Entry with no live destination. The empty-state explanation, New Journal action, Cancel, and disabled Move are clear and fit without clipping.
- `artifacts/journal-recovery-mac-previews/F04D9830-CAE8-4381-9B69-63193A431FEF.png`: isolated local unavailable-parent notice with Export Entry. Copy is concise and the recovery action is visible. This small component render does not show or approve the complete editor/collection layout.

Both pictured states match the reviewed direction. Neither is interactive Mac/VoiceOver evidence.

Re-read the corrections:

1. **Resolved in source:** `reconcileDraftLocation` handles return to a live parent as well as movement into unavailable/trash state; refresh and sync invoke it. The same retained entry is selected under its live parent instead of remaining in an unavailable collection.
2. **Resolved in source:** after successful destination creation with failed refresh, Name/Create remain disabled and Done is available. The sheet cannot invite duplicate creation. It also scrolls, focuses Name, announces unlocked errors, and cancels on captured-entry change.
3. **Resolved in source:** lifecycle errors now have human-readable descriptions; move catches affected-record conflicts, refreshes, and offers an in-sheet Review Changes route to journal or entry review. Actual routing/error recovery remains to be exercised.
4. **Resolved in source for the defined compatibility case:** a supported legacy-marked entry with a missing parent now exposes Restore and Move; the transaction permits that legacy-only missing-parent case while retaining entry/destination conflict checks and unsupported-record protections. Ordinary missing-parent entries are not silently reassigned. Existing unsupported parents continue to require an update.

Move presentation now captures the JournalItem that initiated it, and the single-entry explanation applies to parent-hidden entries as well as independently deleted recovery. The parent reports a native test covering parent arrival returning the same entry and missing-parent legacy recovery; this reviewer did not execute it.

**No demonstrated material blocker remains from this pass's four findings.** Final test results, real nested creation/selection/recovery, failure after commit, large text, keyboard, VoiceOver, and interactive Mac inspection remain separate verification. Whole-journal delete/restore UI is still explicitly unfinished, and these renders do not approve it or permanent purge.

## Final simulator-hosted iOS component inspection — 2026-09-20

Independently viewed:

- `artifacts/journal-recovery-ios-previews/33140EDF-62C0-4E94-9BB9-E658B8520972.png`: native Move Entry recovery component, no live destination, normal-size light appearance. Cancel and disabled Move remain visible in the navigation toolbar. No Other Journals, the creation explanation, New Journal…, and the single-entry scope explanation are legible and unclipped. The state matches the approved recovery design.
- `artifacts/journal-recovery-ios-previews/A4318087-97B1-45F3-899A-13FF226ED421.png`: isolated unavailable-parent notice. The message wraps correctly and Export Entry remains visible. Edge-to-edge positioning belongs to this isolated component render; it is not evidence of the surrounding editor's padding or full collection layout.

**No new material visual finding in these two component states.** These are simulator-hosted native renders, not interactive nested recovery or VoiceOver evidence. The parent reports the final suite passed 13 native iOS tests and two existing E2Es; this reviewer did not execute them, and those results are not described here as proof of untested recovery interactions.

The bounded visual review is complete for these supplied states. Nested New Journal with keyboard, destination selection after creation, Restore and Move, error/retry/export, dark appearance, enlarged text, VoiceOver, and interactive Mac remain separately unverified. Whole-journal deletion/restoration UI and permanent purge are still outside this completed review increment.
