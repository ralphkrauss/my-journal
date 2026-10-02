# Retained-draft save failure retry: independent proposal review

## Evidence and outcome

Reviewed `save-failure-retry.md`, the existing save-error alert and macOS warning in `RootView.swift`, `EntryHeaderView.swift`, `AppModel.flush()` and its surrounding session/lock behavior, and the in-progress `SaveFailureUITests` source. No test was rerun and no production code was changed by the reviewer.

The presentation is suitable, but implementation approval is pending the lifecycle revision below.

## Presentation

The existing warning, “Changes haven’t been saved. Keep Journal open.”, explains the local risk plainly. Putting it before native “Try Again” and “Export Entry…” actions provides a sensible recovery order. “Saving…” is an appropriate transient progress label. A shared, leading-aligned vertical component should keep copy and behavior consistent between the platforms without adding normal-save clutter.

Placing the iOS notice first in the scrollable header makes it discoverable after dismissing the alert; retaining the existing macOS location is reasonable for this small addition. Intrinsic wrapping and explicit words make the warning usable without relying on red alone. Preserve individual accessibility elements for the warning, retry, export, and progress; do not combine the whole notice into a single element that hides its buttons. The alert should own the initial announcement, with no repeated focus transfer while writing.

The iOS header remains limited to half the available height, so at the largest text size and with the keyboard open it may require scrolling to reach both actions. That is acceptable if the warning is automatically brought into view and the complete action labels remain reachable through normal scrolling. Verify the initial warning position immediately after alert dismissal, before any test helper scrolls. Then inspect the reachable retry/export controls and retained body separately if they cannot fit together. Do not interpret a helper-revealed screenshot as evidence that the automatic scroll worked.

## Material lifecycle revision required

The proposal validates the session only at task entry before calling `flush()`. Current `flush()` first awaits `mutationTask`, then reads the current store and draft. It later awaits `store.save`, publishes save/error state, and may recursively flush a changed draft. View cancellation does not by itself invalidate these continuations. A retry that started in an old session could consequently read a replacement session's draft after the first wait or publish a stale failure after the save wait.

Specify a scoped retry/save path that captures the vault session, store identity, and retained entry identity. Revalidate after the mutation wait and before saving; validate again before publishing success/error state or continuing with a newer draft generation. Cancellation, lock, vault replacement, or a changed entry must prevent stale publication or a new save in the replacement context. An already committed write to the captured store cannot be undone by cancelling the view, so do not promise rollback. Keep generation-aware saving for edits to the same retained entry.

Do not add blanket cancellation/unlocked guards to every existing `flush()` call: `lock()` deliberately sets `locked = true` before its final flush, and other lifecycle callers may also depend on existing semantics. An opt-in scoped variant or a separate owned retry path can preserve those callers. View cleanup should clear only its own operation state and must not let an older completion clear a newer retry's busy state.

Routing the alert's retry through the same scoped operation would improve consistency, but the existing alert implementation is outside the proposed persistent-notice change; this review does not certify its current unowned task lifecycle.

## Verification boundaries

The isolated SQLite rejection test is useful: it checks the persisted original document while the draft is retained, dismisses the alert, and exercises retry after removing the rejection. Its final assertions check entry identity/count and the exact body text block list, not full final document equality. The synthetic rejection does not establish full-disk or permission-failure behavior. Normal and largest-text dark UI inspection remains required after implementation. Source inspection or screenshot review alone does not establish live VoiceOver or macOS acceptance.

## Revised proposal approval

Read the appended “Review revision” in `save-failure-retry.md`. The opt-in `flush(whileEditing: entryID)` now captures store/session, validates cancellation and selected draft identity before work and after each relevant await, and checks again before publication or recursive saving. The notice also validates its pre-task session/entry capture at task entry. The unscoped path explicitly preserves lock/import cleanup semantics, and the proposal correctly allows a write already accepted by the old store to complete without stale UI publication.

This closes the material proposal finding. The immediate post-alert-dismissal capture requirement also closes the evidence-plan gap. The revised proposal is approved for implementation, subject to verifying the actual scoped guard placement, owned-task cleanup, and rendered normal/largest-text states. This approval does not certify an implementation or the existing alert task lifecycle. The parent reports native reproduction of the missing retry; its evidence has not yet been inspected by the reviewer.

## Initial implementation source review

Inspected the shared `SaveFailureNotice`, revised `EntryHeaderView`, macOS component placement, scoped `AppModel.flush(whileEditing:)`, and extracted `LocalConfiguration` declaration. The scoped flush captures store/session before the mutation wait, validates before work and after that wait, and validates both success and catch continuations after saving. Its synchronous publication/recursion path follows a successful guard without another intervening await. The unscoped default retains prior behavior. The extracted configuration retains the previously inspected field declarations and defaults with internal visibility.

The notice uses the reviewed warning/action/progress copy and disables both actions while its task is retained. Header placement and the nonanimated scroll call follow the proposal. Actual layout and timing remain to be checked in native captures.

One task cleanup correction is required: `defer { operation = nil }` is unconditional, while `cancel()` cancels and immediately clears the handle. If the same view state becomes usable and starts another retry before the cancelled operation unwinds, the old defer can clear the new task handle and re-enable its actions. Give each operation a token, invalidate it on cancellation, check ownership at task entry, and clear the handle in defer only if that operation still owns it.

Also inspected `artifacts/save-failure-before/83A8582A-7A79-4C81-B767-80F1C2E823F5.png`: the complete retained “X”, full warning, export action, and keyboard are visible; no retry action is shown. This confirms the scoped presentation gap. Unchanged disk content and the test failure remain parent-reported; the screenshot alone cannot establish either assertion. No reviewer tests were run.

## Final source review

Re-inspected `SaveFailureNotice` after its operation-token correction. The UUID is installed before task creation and checked at entry. Cancellation invalidates the UUID before cancelling/clearing the handle, and deferred cleanup clears state only while its own UUID still matches. This closes the task-ownership finding. The scoped implementation is approved by source inspection, pending actual UI review.

Read `DraftSaveTests.testCancelledOrLockedRetryKeepsDraftWhileLockCleanupCanSave`. It checks that a pre-cancelled scoped retry returns false and preserves the exact draft, prior error, failure state, and full persisted baseline. A locked scoped retry returns false and preserves the persisted baseline. An unscoped flush while locked succeeds, clears failure, saves the exact retained document, and preserves the draft. The test does not separately reassert draft/error immediately after the locked scoped call, exercise the actual `lock()` method, or inject cancellation/session replacement during an await. These are useful bounded tests of scoped entry guards and the unscoped compatibility contract, not a timing-race acceptance.

The parent reports 59 core tests, 44 macOS tests, and an iOS build passed before the token/test addition. That report does not validate the final additions; no execution log was inspected and no reviewer tests were run.

## Normal-size actual UI review

Inspected all four images in `artifacts/save-failure-normal/manifest.json` and re-read the current native test sequence. The parent reports this run passed; no log or reviewer rerun was used.

- `5D616207-A52D-40A7-B8F5-4E24DE2DE5B5.png`: the alert shows its complete save-failure explanation, Try Again, Export Entry…, and OK. The new persistent warning/actions and retained “X” are visible behind the dimmed modal; the keyboard is not shown.
- `75AC0F66-069E-4E63-B0F2-B9EBF5DF10F1.png`: immediately after dismissal, the full warning and both recovery actions appear first in the header, followed by the complete title and retained “X” with its caret. The keyboard is visible and does not obstruct these elements. The inspected test takes this capture before calling its reveal helper, closing the initial-position evidence gap for this scenario.
- `64A5DEAA-415B-43D2-8F18-1852FE2FEE78.png`: the reachable-retry capture retains the same complete warning/actions, title, body, and keyboard presentation.
- `D3080838-E9A8-43D8-BA09-58866CFEC28C.png`: after retry the warning/actions are gone, while the title and retained “X” with caret remain fully visible above the keyboard.

Normal-size presentation is approved. The test captures success before relaunch, then separately asserts the body after relaunch. Its real-store assertions check the original document unchanged during rejection, and final entry count, identity, and exact body text block list. They do not compare the entire final record or document; do not describe this as full-record equality. No screenshot captures the transient Saving… state, repeated retry failure, or the post-relaunch screen. Largest-text dark review remains pending, along with the previously stated platform/accessibility limits.

## First largest-text dark review and presentation revision

Inspected all four images in `artifacts/save-failure-large/manifest.json`. The parent reports the interaction test passed. The immediate post-dismissal image `154FED56-8E11-483F-8D41-EE2FBD1BDC33.png` exposes a material presentation problem: the half-height header cuts the warning after “saved. Keep”, with both recovery actions outside the visible region. The retained “X” and caret remain clear above the keyboard. In `5B1E1D25-127E-4291-9C98-B79F23FB11AD.png`, the purported reachable retry is cropped behind the navigation area; export, title, and body remain visible. The helper's header frame alone is insufficient to establish full visibility.

`49602303-AD05-4DF9-9A11-BD95CAA0A2F3.png` shows the native alert, but its message ending and OK action are outside the captured content viewport. `E95745E6-6A35-491D-AD81-27507F9BF740.png` shows a clear complete title and retained “X” with caret above the keyboard after success. The initial largest-text failure presentation is not approved despite the reported interaction pass.

Reviewed the parent's revision before implementation: replace the persistent long warning with “Not Saved”, followed by native “Try Again” and “Export Entry…”; retain the full keep-open explanation in the modal. The compact status plainly communicates local save failure in its entry context and gives immediate recovery more room. This revision is approved for implementation with existing lifecycle behavior retained. Keep status and button labels intrinsically wrapping rather than shrinking or truncating to fit.

Record the revised copy in the proposal. Verify the complete status and primary retry immediately after dismissal, before helper scrolling, and capture export fully reachable through header scrolling if necessary. The helper should account for the actual navigation bottom and scroll in either direction to reveal a complete control. Also capture the modal's complete explanation and reachable OK through native scrolling if needed: the short status relies on that initial explanation, and the existing alert image does not show its entirety. A screenshot should not be treated as proof of accessibility focus or announcement behavior. Revised normal/largest actual review remains pending.

## Corrected largest-text primary retry review

Inspected all five images in `artifacts/save-failure-large-final/manifest.json`, current notice copy/wrapping, and the native test's pre-reveal retry assertions. The parent reports a passing run; no reviewer rerun or log inspection occurred.

`2E776D59-1F12-41F0-9852-D812A9A7F773.png` immediately after dismissal and `6D19B2DE-F8B8-47A1-A764-A759BE9F4464.png` at retry both show the complete “Not Saved” status and “Try Again” action below navigation. The retained “X” and caret are clear above the keyboard. The test asserts retry hittability and full vertical bounds below navigation and within the header before helper scrolling. This closes the material primary-recovery presentation issue. The export label is still clipped at the header bottom in both frames; a targeted header reveal/capture is needed to verify the full secondary action remains reachable.

`A2D7F97B-FD1E-4D17-AF54-2C7E4EEAF50A.png` shows the initial alert with its message ending outside the message viewport. `16B6BB1F-D85C-47A4-B870-2053AAEE292C.png` shows the complete OK and Export Entry… actions after the action region scrolls. The message itself still ends at “open and try”; the final “again.” is not visible. The combined evidence establishes readable keep-open guidance and a reachable dismissal, but not a fully visible exact message. This is a separate, explicitly bounded alert-copy evidence limit.

`5F978638-863F-465B-B6E6-AAC2876AC6F6.png` shows the notice removed and the full title and retained “X” with caret above the keyboard after retry. The revised primary retry presentation is approved. Complete secondary-action reachability and final normal-size review remain pending; transient progress, repeated failure, live VoiceOver, and macOS remain outside the inspected evidence.

## Concise alert copy revision approval

Before implementation, reviewed the proposed save-specific error text on both platforms: “Couldn’t save changes. Keep Journal open.” Approved. It preserves the concrete local failure and the action necessary to retain the draft, while the existing “Try Again” button supplies the recovery action. Device wording and repeated retry prose are unnecessary in this context. The native alert title/actions and save lifecycle remain unchanged. Verify the complete revised message in actual largest-text rendering rather than assuming it fits.

The proposed targeted reveal/capture of persistent “Export Entry…” followed by returning to retry is appropriate. Use the visible header intersection below navigation for gestures and full-label bounds, and do not describe visibility inspection as invoking or validating export.

## Final largest-text dark actual review

Inspected all six images in `artifacts/save-failure-large-verified/manifest.json`. The parent reports the route passed; no execution log was inspected and no reviewer test was run.

- `2D20CDE6-592C-4B0D-AC25-D379BD904A9A.png` shows the complete revised alert message, “Couldn’t save changes. Keep Journal open.”, and complete action labels. `9CA36EF5-CB8C-4D8C-A203-CB32DF269EE9.png` shows the complete message and OK action comfortably within the alert after scrolling. The alert-copy evidence gap is closed.
- `4DC14F8A-C02D-4767-BB06-6D1EF75486EE.png` immediately after dismissal and `04247BF7-8B25-4E79-ABC1-6EE5757F342E.png` at retry show complete “Not Saved” and “Try Again” below navigation. The retained “X” and caret remain clear above the keyboard. Export is partially outside the initial header viewport, consistent with the reviewed scrollable design.
- `349718C9-83AE-47AC-B55D-DE072B7FC630.png` shows the complete persistent “Export Entry…” label below navigation after header scrolling, with the complete title and retained “X” below. The primary retry is partially above this viewport, having been fully shown separately. This closes the secondary-action visibility gap without claiming that export was invoked.
- `265354D1-B46A-40A6-A150-8D3715D35B1A.png` shows the notice removed and the complete title and retained “X” with caret above the keyboard after successful retry.

The final largest-text dark presentation is approved for this bounded save-rejection, alert-dismissal, retained-draft retry, and recovery scenario. No scoped visual findings remain for that configuration. Final normal-size evidence for the concise copy is still pending. Previously stated limits on full-record equality, transient progress, repeated failure, timing races, VoiceOver, real storage failures, and live macOS remain in force.

## Final normal-size actual review and closure

Inspected all six images in `artifacts/save-failure-normal-verified/manifest.json`. `1A9A5551-2610-45E2-B2B8-C2938402E48C.png` and `AC293610-94D1-4D47-A386-EAC4BD28D93C.png` show the complete concise alert message and all three actions without truncation. `624496E5-DBD4-4EB7-8625-5637A42CC0C8.png` immediately after dismissal, `2BEC0BE7-5168-4E38-84C1-4F31188830B9.png` at retry, and `730D79A5-4F34-4C0B-B242-53C996D62E9D.png` for export visibility each show the full Not Saved status, both persistent actions, title, and retained “X” with caret above the keyboard. `DB8D2293-FEEF-4293-9874-C9BF9F3E3943.png` shows the notice removed after retry, with title and retained body/caret still clear above the keyboard.

Final normal-size and largest-text dark actual UI are approved. The scoped proposal, source, task-ownership, and actual presentation findings are closed. Export visibility has been verified, not export invocation. The previously recorded evidence limits remain; this approval does not extend to uncaptured progress/repeated-failure states, timing races, VoiceOver, real storage failure types, or live macOS.

The parent reports the final normal native route, 59 core tests, 45 macOS tests, iOS build, and hygiene checks passed. These are parent-reported results; the reviewer did not inspect the logs or rerun them. No production files were changed by the reviewer.
