# Whole-journal recovery UI proposal review

Date: 2026-09-20. Independent proposal review against `AGENTS.md`, the approved inherited lifecycle protocol, and prior deletion/navigation reviews. No UI implementation or new rendered artifacts inspected.

## Outcome

The consolidated design correctly replaces the old cascade/parent-plus-single-child behavior. Shared trash sections, read-only journal details, accurate offline-local counts, separate individual legacy recovery, active-sheet conflict/export routes, and owned commit reconciliation are appropriate. **Request two interaction revisions before implementation.** Neither changes the lifecycle protocol or expands purge scope.

1. **Use one confirmation surface per operation.** The proposal currently opens a captured review sheet showing name/count/scope, then opens a second native confirmation repeating the same information. That creates unnecessary confirmation steps for both recoverable deletion and restoration. Make the captured native sheet itself the confirmation: Cancel and a specific destructive Delete Journal action, or Cancel and Restore Journal. Preparing the current record/plan can happen in that sheet; after a stale-state error, refreshed information and another explicit press of the action constitute renewed confirmation. If retaining an alert/dialog instead, open it directly after preparation and supply failures/recovery in an appropriate sheet only when needed. Do not require users to confirm the same unchanged scope twice.
2. **Define already-changed lifecycle outcomes, not just stale counts.** Another device may delete the journal while its delete sheet is open, or restore it before local Restore commits. Distinguish these idempotent outcomes from a changed-name/member-set requiring review. Suggested copy: “This journal is already in Recently Deleted.” / Done, or “This journal has already been restored.” / Done with navigation to the available journal after refresh. If the parent is missing, preserve related entries and use the existing unavailable/sync/export handling. Do not leave Try Again in a loop when the requested action has already happened or the record cannot be prepared.

Re-review the revised confirmation and already-applied-state decisions before implementation. The ordinary layout and preservation rules otherwise do not need redesign.

## Copy and accessibility refinements

- On journal rows/details, label a count “1 entry on this device” / “[n] entries on this device” so the visible number is not mistaken for a complete cross-device count. Restore's later-sync scope explanation is correct and should remain in the single confirmation surface.
- Legacy count copy should specify the affected group: “[n] entries from an earlier version of Journal need to be restored individually.” Keep the safe retention explanation; no urgency or purge deadline.
- Recently Deleted search should use No Results/Clear Search when a filter matches nothing, and No Deleted Items only for the actual empty collection. An empty journal still makes the collection nonempty.
- Keep conflicted live journals reachable in Settings even if they are excluded from ordinary live-journal navigation. Review Changes must remain available when Delete/Restore is blocked.
- A read-only journal detail must not inherit editor shortcuts/actions. The proposed disabled entry formatting/export/delete is correct; archive export remains a separate explicit whole-vault action.
- Repeated action labels in rows should have accessible journal context. Preserve focus after refreshed counts/errors without automatically moving focus onto a destructive action. Use standard native Cancel/default keyboard behavior.

## Preservation and verification

The captured ID/plan, atomic recheck, explicit re-preparation, supported-metadata restriction, and no retry after committed refresh failure meet the previously identified data-preservation needs. Whole-journal restoration may reveal entries that arrive later but must not resolve entry conflicts or clear independent/legacy deletion markers. Keep full-reader integration and protocol tests as prerequisites; permanent erasure remains unfinished.

In addition to the listed tests, exercise remote already-deleted/already-restored state while the sheet is open, query-empty versus collection-empty, and a conflicted parent that is still reachable in Settings. The proposed last-journal delete/find/cancel/restore/relaunch simulator flow is meaningful. Inspect the final single confirmation and read-only journal detail, including large text and keyboard/VoiceOver. Offscreen Mac rendering remains limited evidence while the desktop is locked.

## Revision re-review — 2026-09-20

**Approved for implementation and subsequent actual-UI verification.** The revised document removes duplicate confirmation: the captured native sheet is the single review/action surface. Stale plans are cleared, Try Again only refreshes the information, and another explicit action is required. Cancel retains Escape while deletion has no default Return shortcut.

The explicit already-deleted/already-restored outcomes resolve the impossible-retry finding. Already-restored state reconciles navigation; missing-parent guidance preserves/export content without auto-submitting after a later sync. Device-scoped counts, explicit legacy wording, and search-empty precedence address the copy refinements.

No further proposal revision is required. Implement/test the atomic already-applied result as well as refreshed-state detection; do not let a post-commit refresh failure re-enable mutation. The inherited semantics, no automatic independent/legacy restoration, and supported-metadata protections remain authoritative. Actual single-sheet confirmation, trash journal detail, last-journal recovery, large text, keyboard/VoiceOver, and locked-commit behavior still require verification. Permanent purge remains separate unfinished work.
