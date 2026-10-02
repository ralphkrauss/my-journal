# Image descriptions implementation review

Date: 2026-09-20. Independent source review of ImageDescriptionsView, ImageDescriptionOperations, awaitEntryAutosave, RootView integration, and the atomic Store image-description patch against the approved proposal/revisions. No renders or independently executed tests reviewed in this pass.

## Outcome

The main preservation design is implemented correctly in source: an ordered captured image roster is compared within the database write, the latest record receives only description updates, and target plus parent conflict/lifecycle/support checks occur in that transaction. Current body content and attachment references are retained. Missing attachment bytes do not block editing. Waiting for an existing autosave and rejecting an unsettled draft, rather than initiating a whole-record flush of a stale displayed snapshot, is appropriate for this patch.

The native sheet has explicit Cancel/Done, dirty interactive-dismiss protection, per-image accessible field names and current-description previews, confirmed Reload Images, ordinal Copy Descriptions, lock clearing, and owned postcommit reconciliation. Durable-save/display failure disables repeat mutation. **One bounded recovery correction remains before source approval.**

## Finding

**P2 — Do not offer an ineffective Try Again after an existing entry save failure.** `awaitEntryAutosave` awaits the current task and throws while `saveFailure` remains true or draft/items differ. Once the autosave task has ended, ImageDescriptionsView's generic Try Again only calls the same description save again; nothing retries or settles that entry save. Thus a transient entry-save failure leaves a button that can never progress within this sheet, even after the underlying problem clears. Preserve fields and Copy Descriptions, but either provide a safe explicit entry-save recovery that respects current record concurrency, or distinguish this condition and explain that the user must copy descriptions, close the sheet, and resolve the entry save first. Reserve Try Again for failures its action can actually retry. Do not reintroduce an unconditional full-record flush to fix the label.

## Small follow-through items

- The eligibility-change notice is computed text, while only `error` changes are announced. Announce a real transition into unavailability so VoiceOver users learn why Done became disabled. Avoid announcements for the operation's own temporary `replacingVault` state.
- Reload currently displays “Saving Descriptions…” even though it only reloads images. Use a neutral loading label or distinguish reload from save so an explicit discard/reload does not sound like a successful write.
- Invalidation monitoring intentionally skips busy transitions because owned saves temporarily make `canEdit` false. Reconcile true source/selection ineligibility when a reload/save attempt finishes, including reload errors, so returning to eligibility still requires the approved explicit reload and does not revive an old form automatically. Preserve the distinction from the operation's temporary busy guard.

## Required implementation evidence

Run the focused store/model checks for latest-body preservation, repeated attachment per-block metadata, stale roster/description rejection, eligibility conflicts/deletion, and lock after durable commit before reconciliation. Inspect the actual native form, missing preview, dark/large text, explicit reload/copy/error controls, and close/reopen persistence. No claims about native focus or VoiceOver behavior follow from source labels alone; interactive Mac limitations remain in effect.

## Recovery correction re-review — 2026-09-20

**The material recovery finding is resolved; source approved subject to the small consistency condition below and subsequent native verification.** `entrySaveRequired` now gives explicit copy/close/save guidance, preserves local fields and Copy Descriptions, and hides ineffective Try Again/Reload actions. The patch still avoids initiating a stale whole-record flush. Reload uses Loading Images; genuine eligibility loss assigns announced error text and is rechecked after asynchronous work ends, preserving explicit invalidation instead of relying solely on a busy-time observer.

One narrow consistency condition: treat `needsEntrySave` as disabling dirty Done/save as well as hiding Try Again/Reload, or set `invalidated` when reload catches that error. The ordinary save catch already invalidates it, but the reload catch only sets `needsEntrySave`; otherwise an unusual reload failure can leave Done as another ineffective save action. This does not require a further proposal review.

The parent reports a real failed-autosave test using a closed database retains the unsaved draft, newer stored body/title survives the description operation, repeated native round-trip/reopen persists metadata, and the Apple lane passed 28 core tests, 16 native Mac tests, and an iOS build. These are parent-reported results, not an independently rerun suite in this review. Actual editing/relaunch E2E and native render evidence remain pending.

## Done safeguard and limited Mac form review — 2026-09-20

The remaining source consistency condition is resolved: dirty Done and the save function now both gate `needsEntrySave`, including a failure reached from Reload. No source correction from the prior review remains open.

Inspected `artifacts/image-descriptions-mac-previews/C70AB589-4F08-455C-B5CA-A9BA29362209.png`. The isolated native missing-preview form has a legible title/explanation, Image Unavailable state, editable Description field, Copy Descriptions, and conventional separated Cancel/Done controls. No clipping or contradictory missing-image guidance is visible. This supplies limited default-size offscreen Mac layout evidence only; it does not verify focus, VoiceOver, live dismissal, typing, or scrolling. The parent reports the actual simulator synced-image edit/reopen portion passed while its overall suite continues. Final simulator images, completed test results, and the new lock-after-real-commit regression remain pending here.

## Final native visual review — 2026-09-20

**Approved for the reviewed image-description editing/preservation scope.** No concrete additional layout blocker appears in the supplied final states. This approval does not establish the main rich-text editor's inline image announcement behavior.

Inspected actual simulator flow images in `artifacts/image-descriptions-final-ios-previews/`: `E1440C50-19AA-4D51-BD82-107DF1C7C4E1.png` shows a loaded blue PNG, active description field and keyboard, visible Copy Descriptions, and reachable Cancel/Done; `F621E36F-BE93-4F9C-B046-BD7D9F901798.png` shows the retained edited value with the keyboard closed. The single native form stays legible, keeps image context close to the field, and adds no persistent writing-surface controls. The pictured test value combines inserted text with the previous description; this is not evidence of a product transformation or a failed replacement without knowing the test's intended input.

`64C6087C-987B-4092-9D61-B793C7BFD322.png` is a simulator-hosted missing-preview component render with clear placeholder and editing/recovery controls. `55BA6EBA-EC86-4B25-A98A-526B0D7CAAFB.png` is a dark/largest-text component render: explanatory text and missing-image label wrap, while the description field extends below the initial viewport. The native toolbar retains Cancel/Done; ordinary title truncation is visible. This top-of-content render alone does not prove scrolling, typing, or Copy Descriptions reachability at that text size, so it must not be reported as a large-text editing E2E or complete accessibility approval.

Inspected final offscreen Mac component renders `artifacts/image-descriptions-final-mac-previews/4F11C643-F59A-423A-8512-2E017D3E8B8B.png` and `F89A5F8F-F6D7-40ED-B7EF-76E0A3C08583.png`. Light/dark surfaces, missing preview, field, Copy Descriptions, and footer actions remain coherent without clipping. These are component layout evidence, not interactive Mac keyboard/VoiceOver verification.

The parent reports the final iOS run passed three actual E2Es, including synced real-PNG description edit/save/terminate/relaunch, and final Apple checks passed 28 core and 17 native Mac tests, including a real store patch held after commit while lock precedes reconciliation. This reviewer inspected supplied images and source, but did not independently rerun those checks. Form labels and preserved portable/export metadata do not prove that VoiceOver announces those descriptions on inline attachments in the main editor; that remains explicitly unestablished. Multiple-image/error-dialog focus and complete screen-reader traversal likewise remain outside these screenshots' evidence.

## Actual largest-text/dark interaction follow-up — 2026-09-20

Inspected three actual simulator states in `artifacts/image-large-first-previews/`. `E2661E80-133C-4285-9308-5B5E382FB4FB.png` shows the reopened top of the form. `8B7CDA1F-2243-4471-AF8A-85174E45B2F2.png` shows the entire wrapped edited description and Copy Descriptions after scrolling, with Cancel/Done still visible. This closes the previous top-only evidence gap for description/Copy reachability with the keyboard closed. The original-description words surround inserted text, consistent with the parent's account of tapping within the initial value; a contiguous-old-phrase assertion is not an appropriate preservation check for that interaction. Exact edited-versus-reopened equality is the relevant persistence assertion.

**Keyboard-on visual editing still needs one focused check.** `265BDBF3-EE13-4A6C-8724-95D69183DDBC.png` shows the large preview taking substantial space and only the description's first line above the keyboard. The insertion point and inserted text are not visible. The toolbar allows completion, and the parent reports typing/save/relaunch preserved the exact edited value, but automated typing can succeed with the caret obscured. Capture a normal keyboard-open scroll to the active caret and verify continued typing keeps it visible. If ordinary scrolling can expose it, record that evidence; if it cannot or typing repeatedly hides the caret, correct keyboard avoidance/focus scrolling without reducing Dynamic Type. No data-loss or unconditional layout defect is inferred solely from this one scroll position.

The first run is reported to have failed only an overly restrictive assertion that the old phrase remained contiguous after insertion within it; corrected rerun remains pending. Do not call the entire run passing until its final result is available. This evidence improves actual large-text form coverage but does not establish VoiceOver narration of the main editor's inline attachment.
