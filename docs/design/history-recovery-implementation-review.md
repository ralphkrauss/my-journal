# Version-history recovery implementation review

Date: 2026-09-20. Independent source review of the entry/template portion: VersionHistoryView, HistoryOperations, captured RootView history presentation, optional-source RecoveryJournalView/createRecoveryJournal, and atomic store-copy context. Journal metadata history UI is not implemented/reviewed in this pass. No renders or independently executed tests were supplied for this pass.

## Outcome

The main entry/template preservation path follows the approved design. Root captures source ID/kind; Restore captures the selected full historical record before awaiting work; the store revalidates membership and destination in its write, creates a new identity, clears tombstones, preserves historical date/content/references, and retains template kind. The picker index is only view selection, not the immutable commit identity. Current editor saving happens before mutation; failure retains the sheet/version/destination, exposes current-draft Export Entry, and another Restore actually retries the final save. Owned canonical-copy reconciliation precedes lifecycle flushing, while committed refresh failure leaves Done without repeat restoration.

Loading/read-error/empty states are distinct. Unsupported versions offer active-sheet Archive export. Source changes do not retarget the sheet. Nested New Journal with no entry ID no longer inherits current-source edit eligibility and leaves destination selection explicit. Conflict review remains nested, previews are read-only, and lock clears history/image state and nested presentations. **One bounded destination-state correction remains before source approval.**

## Finding

**P2 — Reconcile unavailable/conflicted destinations into the active picker/recovery state.** An atomic `HistoryRecoveryError.destinationUnavailable` currently reaches the generic catch without clearing the selected destination or refreshing live choices. If the store has a deleted/unsupported destination that the model has not loaded, the sheet continues to present it as selected and eligible, alongside “Choose an available journal”; repeated Restore retries the same rejected journal. Clear that rejected selection and refresh current destination eligibility, retaining the historical version. If refresh fails, show a meaningful retry for refreshing choices rather than silently re-enabling the rejected target.

Also handle a selected destination becoming conflicted during a normal model refresh: `onChange(destinationIDs)` currently clears it and only says “Choose an available journal.” Capture the departing selected ID and expose Review Changes when it is in `model.conflicts`, matching the approved conflict route. Returning from review must still require explicit destination choice/restore; do not auto-copy. This is a UI-state correction; the atomic store validation correctly prevents invalid restoration already.

## Small follow-through refinements

- Give the Mac Done button Escape behavior consistent with the other native history/recovery sheets.
- Consider displaying the historical entry date separately from the saved-version timestamp, so retaining an older journal date is understandable before Restore as New Entry. Do not relabel modifiedAt as the entry date.
- Empty journal titles should use the existing Untitled Journal fallback in the destination picker. Duplicate-title context should remain deterministic across refreshes where possible.
- Attachment loading appropriately guards selected index plus complete version equality after awaiting bytes. Actual large-text preview and missing-image behavior still need inspection: the shared native rich-text renderer's iOS missing-image placeholder has its own fixed bitmap size, and source-level read-only flags alone do not prove readable or accessible preview content.

## Evidence still required

Inspect normal and largest-text history preview, destination picker, no-destination/New Journal, unsupported/read-error and restore-result states. Focused native evidence should exercise failed current-save retention, source-switch capture, committed copy followed by lock, and no duplicate copy after refresh failure; actual preview/restore/relaunch should verify the new identity and retained old version/content. Store tests reported elsewhere are not independently executed in this review. Journal settings restoration requires its own completed source/UI review, and inline image VoiceOver behavior remains unestablished.

## Entry/template destination correction re-review — 2026-09-20

**The destination-state finding is resolved; entry/template source approved for native verification.** Atomic destination rejection clears the selection and refreshes live choices while retaining the selected historical record. `needsDestinationRefresh` prevents another restore until refresh succeeds; failures retain a meaningful Reload Journals action. That action owns `busy`, disables repeat restore/dismissal, and checks cancellation/lock before clearing the retry gate. No refreshing path automatically reselects a rejected journal or creates a copy.

Normal destination-list removal now checks the departing journal's conflict identity and exposes Review Changes. Returning still requires deliberate journal selection and Restore. Mac Done has Escape, empty journal names use Untitled Journal, and the preview includes the historical entry date separately from the version-save picker. These address the earlier small refinements.

One nonblocking copy correction should accompany final native verification: `busy` is also used by Reload Journals, so the unconditional “Restoring Version…” progress currently mislabels that read as a restore. Use “Loading Journals…” for that operation (or separate the progress phase). Preserve error/selection state if the refresh is cancelled; the present retry gate already does so. No additional mutation or confirmation behavior is needed.

This pass inspected source only, including lock/cancellation and retry gating; it did not execute tests or inspect renders. Final native history preview/restore/reopen and failure-state evidence remain pending. Journal metadata history UI remains outside this entry/template approval.

## Journal settings implementation source review — 2026-09-20

Reviewed JournalHistoryView, JournalSettingsConfirmation/Comparison, and the restoreJournalSettings atomic checks. No new render or executed test evidence inspected. The captured historical/current records and frozen template labels form an immutable comparison. Same-named/missing references are disambiguated without raw IDs; native Current/Restore sections combine field labels/values for accessibility. The explanation correctly excludes lifecycle, and loading versus committing progress is distinct. Parent-owned busy state disables both parent and confirmation dismissal/actions. Stale-current and unavailable-version failures discard the old comparison; reopening reads a fresh current snapshot, while history membership failure requires Reload History. Already-matching and committed-refresh-failed outcomes prevent repeated mutation.

**Two bounded source corrections remain before metadata UI approval:**

1. **P2 — Guard post-await conflict assignment against lock/cancellation.** In `restore`'s conflict catch, `conflict = try await model.store?.conflicts().first(...)` assigns a full journal conflict payload after awaiting without checking cancellation or lock. If lock cleared state during that read, the continuation can repopulate sensitive conflict state; the following lock guard only suppresses the error text. Load into a local value, check cancellation/unlocked state, then assign. Apply the same rule to any other newly added post-await metadata payload assignment. The approved lock behavior is to clear retained historical/current/conflict values, not merely stop presenting them.

2. **P2 — Route atomic missing/unsupported current-parent rejection directly to unavailable/export state.** If a journal disappears or becomes unsupported after confirmation, the store throws missingJournal/unsupportedJournal; the generic catch closes comparison but only sets localized error. It does not set `unavailable`, so the promised active-sheet archive recovery is absent until the user retries Restore Settings and preparation rediscovers the state. Handle these typed outcomes immediately with the approved unavailable explanation and Archive export, retaining history and requiring fresh preparation before a future restore. Store checks already protect against an invalid patch; this correction makes the first rejection actionable and faithful to the approved design.

The atomic metadata patch checks full expected current equality, history membership and target conflict/support, preserves the previous current version, and only changes name/default reference plus modified time. These source checks do not substitute for the pending test evidence on immutable outbox bytes/history and lock-after-commit reconciliation. Entry/template approval above is unchanged. Final native comparisons, long/duplicate template labels, errors, largest-text actions and actual recovery flows remain pending.

## Journal settings correction re-review — 2026-09-20

**Both metadata source findings are resolved; journal settings source is approved for native verification.** The conflict-rejection path now reads into a local value, checks task cancellation and unlocked/nonreplacement state, then assigns the payload. It cannot repopulate the cleared conflict state through that previously identified post-await continuation. Typed missing/unsupported-current-parent failures immediately enter the approved unavailable explanation plus active-sheet Archive export, without requiring another failed preparation.

Comparison preparation also obtains current template records from the store before freezing display labels, rather than relying on a potentially older model template list. The captured label strings stay stable afterwards; the current journal's complete snapshot is still revalidated atomically at commit. No prior source finding remains open in the reviewed entry/template or settings portions.

This is source disposition only. The compiling/running native suite, actual captured comparisons/previews, largest-text action access, lock/refresh-failure test results and interaction evidence remain pending. No new execution or rendered-state evidence was inferred in this re-review.

## Initial loaded simulator visual evidence — 2026-09-20

Inspected `artifacts/history-settings-query-previews/4644C1D2-1FB4-4455-A218-EC3DC1A23CA9.png`: loaded entry history shows a legible version/save-time picker, historical title and entry date, read-only earlier text, destination, New Journal and Restore as New Entry. The current source journal is visibly selected; native controls remain uncluttered. The simple text-only preview does not establish historical rich-text/image accessibility or larger-content scrolling.

Inspected `3F055A28-5183-4A6A-B071-8E4B3E8D48E5.png` in the same directory: Current and Restore name/default-template values, including Unavailable Template, read clearly and the lifecycle-scope explanation is visible. Its navigation title truncates at normal size because the trailing Restore Settings repeats it; the separately recorded preimplementation review approves shortening only that iOS action to Restore. Corrected capture remains pending.

The parent reports this test stopped on a query that targeted background-sheet text instead of the visible combined accessibility comparison field. This review inspected screenshots only; no complete restoration/pass outcome is claimed from this interrupted run. Scoped-query rerun and actual large-text action evidence remain pending.

## Corrected comparison and post-restore Settings evidence — 2026-09-20

Inspected `artifacts/history-settings-normal-previews/193400F2-8B00-4F19-B202-7DA25B5686A6.png`: the shorter iOS Restore action now leaves the full Restore Settings title readable at normal size; the comparison and lifecycle-scope copy remain clear. That visual refinement is accepted.

`817D06B5-965B-4937-9CCA-20B55A2CB5A7.png` shows restored Earlier Work in Settings but an empty Default Template picker value. The parent reports the normal actual E2E passed and the missing reference is correctly preserved. This screenshot nevertheless reveals a presentation gap; the separately approved missing-reference option repair should make it Unavailable Template without replacing its ID. Corrected picker capture and largest-text evidence remain pending. The parent-reported E2E pass was not independently rerun here.

## Largest-text rich-history visual finding — 2026-09-20

The supplied actual largest-text/dark rich-history capture `artifacts/history-settings-large-previews/8D3F161D-E2D5-48ED-86B6-951CD389E7EA.png` displays preserved earlier text and a loaded blue image, but the selected version and journal picker values are vertically clipped. The separately reviewed native wrapping-menu label repair is approved; final visual disposition remains pending that correction. `D120280D-BDB8-462B-8501-C970C146EDDD.png` shows readable scrolled Current/Restore settings values and the reachable native Restore action; compact title truncation will be supplemented by the approved accessibility-size content heading. These screenshots do not establish inline-image VoiceOver behavior. The parent reports the rich-fixture flow passed, but that does not negate the visible control-clipping defect.

## Wrapping controls and missing-reference source follow-up — 2026-09-20

**The bounded reviewed changes match the proposal in source.** HistoryMenuLabel gives the selected value intrinsic multiline height, uses a caption field label, hides the decorative chevron, makes the complete label area a target, and exposes a single named/value accessibility element. HistoryVersionPicker and the destination menu retain native inline Picker contents with tagged choices. Entry/template busy/completed guards and metadata working/comparison guards remain at their call sites. No mutation or selection policy change was introduced by this presentation extraction.

The iOS confirmation now adds a full Restore Settings heading only for accessibility Dynamic Type sizes, within the scrollable content, while keeping the native toolbar/actions. JournalSettingsView includes a disabled Unavailable Template option tagged with the exact preserved missing reference, retains its picker-level conflict/replacement guards, and uses Untitled Template for unnamed available options. Displaying that option does not itself invoke the selection setter. Reload Journals progress now correctly says Loading Journals while its refresh gate is active.

No new source finding is raised. Actual full-value wrapping, open native-menu choice/checkmark behavior, complete accessibility exposure at the Menu level, and visible missing-template selection still need the forthcoming native run/captures. Source labels alone are not VoiceOver execution evidence; the Apple lane currently running is not counted as passed in this review.

## Wrapped largest-text history evidence — 2026-09-20

Inspected final supplied images in `artifacts/history-settings-wrapped-large-previews/`: `7398C963-98E9-4BD8-85F5-B73E1A1FF481.png` shows the complete selected version timestamp/ordinal without vertical clipping; `8D7D12A1-4472-4899-BA20-F62F3DEBB822.png` shows the complete Current Work destination and reachable Restore as New Entry; `C0BE4E57-028D-4723-8CCD-8458CAB3349E.png` shows full native version-menu choices and the selected checkmark. The observed history control-clipping finding is resolved in these states. `12ECF1A9-BA4F-4ADC-807E-AB18CD1F1833.png` shows the full accessibility-size Restore Settings content heading with native Cancel/Restore available; scope text continues through the ordinary scroll boundary.

Read `/tmp/journal-history-settings-wrapping-large.log`: it reports one test executed with zero failures and TEST SUCCEEDED. The reviewer inspected the execution log and images, but did not independently rerun the test. This is actual largest-text rich-fixture evidence, not a VoiceOver session.

One bounded display follow-up remains: `A61F97CF-0CA8-445D-8CF2-D9516CC10E4F.png` shows the Settings Default Template selection abbreviated despite its preserved ID. The separately approved wrapping-label reuse, semantic secondary caption color, and leading multiline alignment address this visible issue. Await corrected Settings and final normal-size evidence; no persistence or immutable-history finding is inferred from the current truncation.

## Final largest-text presentation disposition — 2026-09-20

**Approved for the inspected largest-text/dark history-recovery and restored-settings states. No observed clipping follow-up remains open.** In `artifacts/history-settings-polished-large-previews/BB40E60A-196E-48E2-9D3D-D9FEE163023B.png`, Unavailable Template is fully visible through native wrapping/hyphenation rather than abbreviated. `93E57F95-EE2B-4FFD-9ABC-6E44097FA35E.png` shows the complete selected version with readable semantic secondary caption and leading multiline alignment. Inspected source confirms the shared WrappingMenuLabel keeps the field-name/full-value accessibility contract and Settings retains the exact-ID Picker binding, disabled missing-current option and existing mutation guards.

Additional inspected final images: `30AE4F31-2223-4161-B1D8-ED445B41C859.png` shows full destination and reachable Restore as New Entry; `5D4E2814-A638-44D3-97AB-3933BB8FB22E.png` shows native destination choices with Current Work checked; `535FBFC7-BCDA-4BCB-9C65-9C59D20E84D2.png` shows readable Current/Restore comparison fields and persistent toolbar actions while scrolling. Content beyond a viewport boundary is not treated as clipping of an individual control.

Read `/tmp/journal-history-settings-polished-large.log`: one actual test passed with zero failures and TEST SUCCEEDED. This reviewer inspected the log and images, not an independently repeated execution. The parent reports final Apple checks passed 31 core tests, 20 native Mac tests, an iOS build and hygiene checks; those counts remain parent-reported here. Final normal-size run is pending at this review point. This approval is bounded to the captured successful recovery/settings presentation and previously reviewed source. It does not claim all history failure states, template UI recovery, VoiceOver narration, or interactive Mac coverage were exercised by this one flow.

## Final normal-size presentation disposition — 2026-09-20

**Approved for the inspected normal-size history-recovery and restored-settings states. No outstanding source or visual finding remains in the reviewed successful entry-history/settings flow; successful normal-size and largest-text evidence is complete.** In `artifacts/history-settings-polished-normal-previews/DF9AEA7E-E279-44F1-9DBB-94DF40811F30.png`, restored Earlier Work and the complete Unavailable Template selection are legible with the native chevron and no clipping. `CBA67840-5C73-49A4-AEA5-3D879B7FAD65.png` shows the complete version timestamp/ordinal, Earlier reflection title, historical date, bold earlier text and loaded blue image, plus Current Work, New Journal… and Restore as New Entry. `751AEFDB-05F4-490A-80DE-DD16ABB10B8D.png` shows the complete Restore Settings navigation title with Cancel/Restore, clear Current versus Restore values, and the explanation that entries and Recently Deleted remain unchanged.

Read `/tmp/journal-history-settings-polished-normal.log`: one test executed with zero failures in approximately 61.435 seconds and TEST SUCCEEDED. The reviewer inspected the images and execution log; the test was not independently rerun. Together with the preceding largest-text disposition, this closes the remaining successful-flow presentation verification note. It does not establish all error states or template recovery UI flows, VoiceOver narration, or interactive Mac behavior. The locked Mac desktop and unestablished main-editor inline-image VoiceOver narration remain coverage limitations, not claims of completed verification.
