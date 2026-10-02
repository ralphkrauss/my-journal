# Archive actions at accessibility text sizes — independent review

Reviewed 2026-09-20 against `archive-actions-accessibility.md`, the existing archive design, and both supplied actual full-sheet screenshots. This is preimplementation approval, not verification of the proposed fix.

## Verdict

**Approved for implementation.** A vertical action group at accessibility text sizes is a conventional, bounded adaptation of the existing native controls. Full-width primary action followed by Cancel gives the long action label adequate room and preserves a clear action hierarchy. Keeping the group in the existing ScrollView avoids an oversized fixed footer obscuring content or the keyboard. Retaining the standard horizontal row for normal text sizes is supported by the normal capture.

The large capture `artifacts/archive-ui-large/843DA44F-253C-43E4-A5B6-BCE1196CFE56.png` confirms a real layout defect: Restore Journals breaks inside words and its tall prominent shape extends beyond the visible sheet while Cancel consumes the adjacent width. A passing tap test cannot approve that presentation. The normal capture `artifacts/archive-ui-normal/7D481330-6F25-4D29-8D21-939C5EEF76B6.png` shows a readable long journal name, complete count/explanation copy, and conventional Cancel/Restore Journals placement without clipping.

## Implementation expectations

Use native Button semantics and the existing prominent style, with intrinsic multiline label height and the full available action width. Do not combine the action group into one accessibility element: progress, primary action and Cancel must remain distinct in their visible traversal order. Keep Cancel's cancel role and existing commit disabling, and preserve recovery-key submission/focus behavior. Native macOS retains its existing ordering. The proposal changes no mutation semantics, confirmation, recovery-key copy or import-completion state.

Progress before the primary action is appropriate while busy. Primary remains disabled throughout the operation; Cancel stays available during inspection and unavailable during commit. The visual layout must not introduce a second action or a duplicated keyboard submission path. Both Continue and the longer Import as New Journals label need the same wrapping treatment as Restore Journals.

## Verification still required

Inspect source and actual normal plus dark/largest full-sheet captures after implementation. Confirm complete primary and Cancel frames can be brought into the visible scroll viewport, and inspect the full rendered labels rather than relying on frame containment alone. Retain normal-size ordering and test the existing wrong-key retry/cancel/reopen/restore flow; capture the wrong-key explanation before retry so the actionable failure state is visible. Verify the longest additive label through a representative rendered state as well, even if the existing end-to-end flow restores a new vault.

The parent reports the existing full-sheet interaction test passed before this change; it was not independently rerun or its log inspected in this review. The visible defect remains open until corrected actual UI evidence arrives. VoiceOver source ordering is an implementation requirement, not a claim of executed VoiceOver coverage; interactive Mac behavior remains outside these iOS captures.

## Implementation source review — 2026-09-20

**Approved in source; no design deviation found.** ArchiveImportActions selects a leading VStack at accessibility sizes with progress, full-width primary action, then Cancel. At standard sizes it retains Cancel, spacer, progress and primary in the horizontal row. The primary Text permits intrinsic multiline height without scaling down or a line limit; its accessibility-size frame fills the available width. The controls remain native distinct elements, and Cancel retains its role.

ArchiveImportView supplies the existing three titles and preserves the original enablement rule: primary is disabled while busy or when an unprepared archive has an empty key; Cancel is disabled only while committing. Recovery-key submission/focus and parent interactive-dismiss guards are unchanged. The extracted view remains inside the existing ScrollView. No extra submission path, confirmation or mutation behavior is introduced.

This pass inspected product source only. The parent reports the end-to-end test now exercises the longest additive label and cancellation, and uses bounded frame-derived scrolling; those test changes and their execution have not been independently inspected in this pass. The prior largest-text visual defect remains pending corrected full-sheet evidence, including the complete Restore and additive labels, Cancel access and wrong-key explanation.

## Actual largest-text/dark disposition — 2026-09-20

**Approved for the inspected largest-text/dark full-sheet actions and wrong-key state. The observed action-fragmentation defect is resolved.** Inspected `artifacts/archive-actions-large/A7ECD07C-DF62-42DB-BDA5-ABF8AFC51F7C.png`: Restore Journals is fully readable on two complete lines in the native prominent button. `3B387A31-0A49-435F-99D4-F9B637B5317D.png` and `F0D34C88-423A-464C-992A-4625AA6134C1.png` show the complete Import as New Journals label and reachable Cancel below, with the additive-preservation explanation readable above. `AAA666E5-F1FB-4474-B84A-3109B8F00B0B.png` shows the complete wrong-key explanation plus full Continue and Cancel actions. Offscreen preceding content at a ScrollView boundary is not a clipped control defect.

Read `/tmp/journal-archive-actions-keyboard-large.log`: testArchiveWrongKeyRetryRestoreAndReopen passed in approximately 60.258 seconds; one test, zero failures, TEST SUCCEEDED. Inspected the current test source: the reveal helper requires a hittable element's complete frame inside the viewport and clips that viewport above the full inputView when a keyboard exists. Its bounded drag originates within that visible area. The test reads the wrong-key explanation, retries the recovery key, cancels and reopens, restores, relaunches, visits the additive preview and cancels it. It then decrypts the resulting store and compares complete records, image bytes and lifecycle counts. These source assertions and the inspected pass log support those bounded outcomes; the reviewer did not rerun the test. The parent separately reports only the committed inspection directory survives; no corresponding directory assertion was present in the inspected test source, so that remains parent-reported evidence here.

The earlier stalled wrong-key scroll was attributed by the parent to gestures starting over the keyboard/prediction area. The corrected helper and passing actual flow require no production focus/scroll redesign. This review does not infer general VoiceOver coverage, all import failures, lock-during-import coverage, or interactive Mac behavior. Final normal-size run/captures remain pending at this point.

## Final normal-size disposition — 2026-09-20

**Approved. No outstanding source or visual finding remains in the reviewed archive action/count flow.** Inspected `artifacts/archive-actions-normal/320DAC0C-6FB3-4136-A28D-AF67E776186E.png` and `32A825A4-E134-4BE7-9FC2-382BB6893715.png`: the conventional horizontal Cancel/primary layout is retained, including the complete longer Import as New Journals label. Both captures show the complete long journal name, disjoint counts and preservation explanation without clipping; the additive capture also shows its complete destination-preservation copy.

Read `/tmp/journal-archive-actions-normal.log`: the same actual end-to-end test passed in approximately 38.872 seconds, one test, zero failures, TEST SUCCEEDED. Normal and largest-text/dark final visual evidence is complete for this reviewed flow. Execution logs/images and test source were independently inspected, but tests were not independently rerun. The broader Apple lane remains pending/parent-owned at this review point; the previously stated VoiceOver, interactive Mac and other unexercised failure-state limits remain unchanged.
