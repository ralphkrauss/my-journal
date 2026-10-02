# Export operation lifetime

## Scope and observed source behavior

The model's entry exporter returns plaintext without checking task cancellation. Entry attachment reads consult the current model store across awaits and only check the final locked Boolean. Archive preparation/inspection also check only final locked/cancelled state. A lock→unlock or store A→B→A transition can therefore make an old operation appear current again. Existing view cancellation helps but does not establish the model boundary itself.

## Proposed behavior

Capture a vault-session generation at the start of entry export, archive export and archive inspection. Advance it synchronously whenever the model becomes locked, begins replacing a vault, or changes store identity. Check cancellation and that captured session after every relevant await and before publishing bytes, an archive URL or an imported preview. Reopening the same store or unlocking must not revive an old operation.

Entry export captures the requested draft, original store and cached image bytes once, then reads missing attachments only from that captured store. The existing unsaved-draft export path remains available without a store if no image read is needed. Later edits need not alter the captured export snapshot; changing the vault session cancels it. No serialization, labels, dialogs, layout or default format changes.

Archive export revalidates after pending save and after archive creation; a stale/cancelled completion removes only its uniquely named generated archive. Archive inspection discards only its restored staging copy if its session is no longer current. Existing source backups remain untouched. The views suppress errors from cancelled/stale operations so locking cannot later produce an irrelevant failure message. Existing lock-driven dismissal and sensitive preview clearing remain.

## Verification

First demonstrate that a pre-cancelled entry export currently returns plaintext, using a focused native model test. Verify that cancellation then fails without plaintext, normal snapshot export preserves the unsaved draft, and captured session validation rejects lock→unlock and store replacement→restore transitions. Native archive/entry success paths already have normal/largest actual evidence; rerun relevant checks after the correction. These tests do not claim physical biometric/Keychain or every timing interleaving.

## Reviewed boundaries

Advance a read-only model session UUID on lock, replacement start and store identity changes. Model checks throw CancellationError for stale sessions so obsolete completion is not a visible error. Each model operation catches underlying failures, revalidates its captured session, then forwards the original failure only if still current. Archive export checks immediately after pending-save completion, before deciding whether a save-failure explanation applies. Core archive export/restore already remove their partial destinations on thrown paths; preserve that ownership and explicitly clean successful-but-stale results.

ArchiveImportView captures the same session before scheduling inspection and carries it through `result.store.lifecycleSnapshot()`. It revalidates before assigning preview/prepared state, disposes the restored copy on failure, and checks session in the outer catch before showing any error. Thus even the additional view-level await cannot publish after a store A→B→A transition. Entry/archive export views similarly capture before scheduling and validate both before publication and in error handling. Task cancellation and session invalidation suppress errors; genuine current failures retain existing copy. Do not modify import commit/reconciliation in this correction.
