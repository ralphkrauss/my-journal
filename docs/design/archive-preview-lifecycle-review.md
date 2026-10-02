# Archive preview lifecycle counts — independent design review

Reviewed 2026-09-20 against `archive-preview-lifecycle.md`, `archives.md` revision 2, and current `ArchiveView.swift` / `JournalLifecycle.swift`. This is a proposal/source-context review, not implementation approval or executed accessibility verification.

## Verdict

**Approved with one required, bounded copy refinement before implementation.** The proposed shared lifecycle snapshot and exactly-once classification correctly address misleading archive counts without adding navigation or visual clutter. The existing native scrollable sheet, system styles, wrapping text, and unchanged commit boundary fit the Apple-native requirements. The refinement below does not need another proposal review if adopted as written; a materially different presentation should be re-reviewed.

## Required refinement

**P2 — Identify the live category in the first count.** “N entries” reads as an archive total, particularly immediately above “N in Recently Deleted” and “N in Unavailable”. It therefore leaves the user to infer whether the latter counts are subsets or additional entries. Use **“N entries in journals”** for the first row, retaining **“N in Recently Deleted”** and the conditional **“N in Unavailable”**. Use the singular **“1 entry in journals”** when appropriate. The full first-row string should also be its spoken accessibility text. This makes the three disjoint destinations explicit without adding a redundant explanatory paragraph or technical terminology.

## Accepted semantics and states

The proposed location rules match the normal application's precedence: a missing, unsupported or conflicted parent makes an entry Unavailable even when deletion markers exist; otherwise parent deletion, direct entry deletion and the legacy marker place it in Recently Deleted. Independently conflicted entries remain in the applicable parent location. Counting current entries only, while preserving conflict copies and earlier versions without inflating counts, is appropriate. Retain the first two rows at zero and omit the zero Unavailable row. Untitled Journal is a suitable blank-name fallback.

The conditional sentence “These entries are preserved. You can review them in Unavailable after importing.” is concise and appropriately adjacent to the Unavailable count. Preserve the existing newer-format refusal; this copy must not appear as a completed-import claim or imply that an unsupported additive archive can be installed. Existing additive/new-vault actions and explanations remain necessary and unchanged.

Publishing the prepared archive and complete preview together after successful snapshot loading resolves the current source's early `prepared` assignment hazard. On failed inspection, retain the recovery-key stage and a working Continue retry, discard the owned inspection copy, and avoid exposing a final import action with incomplete counts. Cancellation and lock must also suppress late publication/error presentation and release the owned inspection copy. These are faithful implementation details of the proposal's cancellation/lock requirements, not additional confirmation steps. Preserve keyboard focus on an invalid key and the existing actionable error distinctions.

## Verification boundary

Before final implementation approval, inspect the changed source and actual normal-size plus largest-text/dark native previews, including nonzero values in all three categories and a long journal name. Confirm that the footer actions remain reachable by ordinary scrolling, full counts wrap and remain readable, and failure returns to Continue rather than Restore/Import. The real archive fixture should establish exactly-once classification with inherited/direct/legacy deletion, unavailable-parent precedence, and historical/conflict records excluded from the current-entry total. Source accessibility labels and screenshots alone do not establish a VoiceOver session; offscreen Mac rendering does not establish interactive Mac behavior.

## Implementation source review — 2026-09-20

Reviewed current ArchiveView, ArchiveSummary, ImportLifecycleTests and ArchiveLifecycleTests, plus the model inspection/discard boundary and additive-import refusal copy. **The count implementation and approved copy match the design; one bounded cancellation correction remains before source approval.** No native test run or new rendered evidence was independently inspected in this pass.

ArchiveSummary iterates current entry records once and switches exhaustively on the shared lifecycle location, so history/conflict copies cannot inflate its totals. ArchivePreviewSummary uses the approved singular/plural live-category label, visible zero Recently Deleted count, conditional Unavailable count/explanation, semantic styles and an Untitled Journal fallback. No fixed text height or new custom control was introduced. The real restored-archive test checks inherited, independent and legacy deletion, missing-parent entries and preserved historical/conflict references; subsequent parent restoration checks the expected count transition. The app test checks all three nonzero categories and failed commit/retry preservation. These are meaningful behavioral checks, but reading their source does not establish a passing execution. The supplied fixtures do not themselves exercise unsupported/conflicted-parent precedence; the shared location implementation already applies those rules.

Inspection now retains the restored result locally until lifecycle snapshot loading succeeds, then publishes summary/prepared state without another suspension. A snapshot error or cancellation releases that owned copy; successful new-vault installation is protected from later discard by the persisted ownership check. The additive newer-content refusal remains contextual: “Update Journal to import this archive as new journals. You can still restore it on a device with no journals.” It does not silently remap unsupported content, and the preview is not presented as completed import.

**P2 — Suppress inspection error publication after cancellation or lock.** The outer typed/generic `inspect` catches still assign error/focus state without checking cancellation or lock. This is reachable: `AppModel.inspectArchive` explicitly discards its result and throws `JournalError.locked` when the task is cancelled or the model locks; the view then treats that as a generic file/space failure. A snapshot read may also throw another error after dismissal/cancellation, including after awaited cleanup. Before publishing any inspection error or recovery-key focus, check that the task is not cancelled and the model remains unlocked. Preserve the existing cleanup and genuine active retry errors. This closes the proposal's explicit suppression requirement; it needs no visual redesign.

The test's preview capture builds only the summary and title, omitting the real recovery/import controls and footer. Such renders can establish count/long-text presentation, but cannot establish actual sheet retry behavior or largest-text action reachability. Actual native evidence remains pending, with the same VoiceOver/interactive Mac limitations recorded above.

## Cancellation correction and normal-size component review — 2026-09-20

**The inspection cancellation finding is resolved; the reviewed implementation source is approved.** The outer catch checks task cancellation, model lock and CancellationError before calling synchronous showInspectionError. There is no intervening await before error/focus publication, while snapshot-failure cleanup remains in the inner catch. Genuine active inspection failures retain the existing contextual messages and retry stage.

Inspected normal-size component captures `artifacts/archive-preview-ios/474BA617-4386-4742-A36F-9A1BEFBD01CB.png` and `artifacts/archive-preview-mac/F4206379-27F5-41DA-95DC-2DA9F1D14789.png`. Both show the full title, Personal journal name, all three nonzero disjoint counts, and the complete wrapped preservation explanation. No clipping or layout deviation is visible in these supplied summary states. **Normal-size summary presentation is approved.**

These are summary-component renders, not complete-sheet interaction evidence. They do not establish footer reachability, recovery-key error/Continue retry, long-name layout, VoiceOver, or interactive Mac behavior. No test was independently rerun here. The parent reports the initial dark component capture used a mismatched white UIKit host; that capture is not accepted as dark-appearance evidence. Corrected largest-text/dark render review remains pending.

## Corrected dark/largest-text component disposition — 2026-09-20

**Approved for the visible dark/largest-text summary component.** Inspected `artifacts/archive-preview-corrected-ios/2EB730D3-E7F6-4F3D-A999-154F85C25779.png`: the hosting surface is now black with appropriate light primary and semantic secondary text. Import Archive wraps fully, Personal is legible, and all three category counts are complete without abbreviation or clipped control bounds. The preservation explanation wraps and continues below the ScrollView viewport; this capture does not show its remaining lines or prove a scroll interaction. No new visual defect is raised in the visible component.

Read `/tmp/journal-archive-preview-corrected-ios.log`: `testFailedArchiveCommitKeepsCurrentVaultAndRemovesOnlyItsStaging` passed; one test, zero failures, TEST SUCCEEDED. This is inspected execution evidence for the real archive model failure/retry test, not an independently rerun test or a full import-sheet interaction test. Normal and dark/largest-text component presentation are now reviewed. Complete-sheet footer reachability, active inspection failure/Continue retry, long journal-name presentation, VoiceOver and interactive Mac remain unverified; no broader approval is implied.

## Full-sheet largest-text follow-up — 2026-09-20

The separately reviewed `archive-actions-accessibility-review.md` now records inspected actual largest-text/dark full-sheet evidence and a passing wrong-key retry/cancel/reopen/restore/relaunch test. Complete Restore Journals and Import as New Journals labels, Cancel, the preservation explanation and the wrong-key explanation are visible in the accepted captures. This supersedes the earlier component-only limitation for those specific iOS interactions. It does not establish all error/lock states, VoiceOver or interactive Mac coverage. Final normal-size action evidence remains pending; see the action review for exact images, source assertions and log provenance.

## Final normal full-sheet disposition — 2026-09-20

Final normal restore and additive full-sheet captures and the successful normal end-to-end log have now been independently inspected, as recorded in `archive-actions-accessibility-review.md`. The long journal name, all count categories, complete preservation explanations and horizontal actions are readable without clipping. Together with the accepted largest-text/dark evidence, no source or visual finding remains in the reviewed archive count/action flow. This closes the normal presentation follow-up while retaining the stated VoiceOver, interactive Mac and unexercised-failure-state limits.
