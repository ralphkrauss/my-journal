# Journal metadata conflict proposal review

Date: 2026-09-20. Independent proposal review against `AGENTS.md`, `screens.md`, and journal-deletion prerequisites. No implementation or rendered UI inspected.

## Outcome

**Request the two refinements below before implementation.** The dedicated metadata summary, deleted-journal access path, captured baseline, stale-choice rejection, absence of Keep Both, transactional history preservation, and owned commit/reconciliation are appropriate. A small metadata comparison is preferable to showing a journal record in an entry editor.

1. **Identify the selected version in the action/confirmation.** The proposal reintroduces generic Keep This Version… / Keep this version? wording despite the approved requirement for device/time-qualified choices. The segmented display helps, but the confirmation must stand alone. Use “Keep Version…” with confirmation identifying “This Device · [modification date/time]” or “Other Device · [modification date/time]”; include the captured recorded ID in secondary details when needed. Do not let switching a segment change an already-open confirmation's target. When the real device name is unavailable, Other Device is honest. A raw UUID need not occupy the primary version header: keep selectable full identification under native Details while showing device label/time prominently.
2. **Provide an active-sheet route for unsupported export.** “Offer a lossless export ... through the existing ArchiveControls route” is underspecified. Define a visible Export Archive… action in the unsupported-conflict sheet, reusing the archive exporter without requiring users to dismiss and hunt in Privacy. If archive export cannot proceed because the current draft failed to save, expose the separate Entry Export recovery path and retain the conflict. Do not imply a one-record entry export preserves the whole journal conflict.

These are small labeling/routing revisions; the main layout does not require redesign. Re-review their concrete wording/action placement before implementation.

## Fidelity and verification notes

Read-only journal Version History is honestly labeled as unfinished restoration work. It preserves inspection/export, but does **not** complete the earlier expectation of directly recovering a selected historical version. Keep that limitation recorded; “Both versions will remain in Version History” is accurate, whereas “you can restore either version here” would not be. Earlier versions should include enough metadata to distinguish lifecycle/default-template choices, including unavailable referenced templates.

An ordinal distinguishes equal timestamps in the history picker; do not substitute server receipt time for edit time. The version selector, content, Cancel, choice, reload/error, and unsupported export must remain reachable with large text and keyboard. Ensure affected-journal settings rows remain reachable even when local and remote versions disagree about deletion, and re-evaluate all remaining conflicts after resolution rather than automatically continuing deletion.

No actual UI or protocol behavior is approved by this proposal review. Tests should establish stale local AND remote baseline rejection, no reparenting/copying children, preservation of both originals, and lock immediately around commit.

## Refinement re-review — 2026-09-20

**Approved for implementation and subsequent actual-UI verification.** The captured device-qualified confirmation with edit date/time resolves version ambiguity, and the primary header no longer depends on a raw identifier. Full recorded identity remains available in Details. Nested Export Archive and separate failed-draft Export Entry provide reachable preservation actions without flattening the journal conflict or clearing failed-save state.

One copy correction is required: “Save or export your entry before exporting the archive” implies that exporting the entry satisfies the archive's flush prerequisite, but the specified behavior correctly keeps saveFailure and retries normal saving. Use “Save your entry before exporting the archive. You can export the entry separately.” This is a wording correction, not a new review gate.

The refinements supersede the old generic Keep This Version wording. No additional proposal revision is required. Actual stale-choice handling, unsupported archive export, nested-sheet lock behavior, journal history preservation, keyboard/VoiceOver, and large text remain to be implemented/verified. Read-only metadata history still does not complete direct history restoration.
