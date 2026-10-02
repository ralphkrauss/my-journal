# Entry conflict accessibility review

## Initial proposal review — 2026-09-21

**Layout direction approved; resolve-state details need a short revision before implementation.** Independently reviewed `entry-conflict-accessibility.md`, current EntryConflictReview in SettingsView, the DeletionSheet implementation in PermanentDeletionView, and EntryConflictUITests. No production edits or independently rerun tests occurred.

Reusing the native sheet container, wrapping metadata, semantic preview text, a menu picker at accessibility sizes and vertically arranged actions addresses the current fixed-size and horizontal-layout constraints without adding main-editor clutter. Existing plain copy and quiet completion fit the product. The preview must remain selectable/read-only, with accessible image descriptions and document references intact. Keep the current version visible in the accessibility-size picker label; “Version” is the control's accessible name, not a replacement for its selected value.

### Required revision

**P2 — Distinguish committed resolution from reload failure.** The proposal says failed operations remain in review with all choices available for retry, but resolve can commit before refresh or selection fails. Retrying resolution would act on a conflict that no longer exists and misrepresent what was saved. Specify an explicit committed state: disable/remove version-resolution actions, use “Changes saved. The entry couldn’t be reloaded.” for subsequent reload failure, and offer “Try Again” that only reloads plus “Done”. Equivalent concise copy/behavior is acceptable if it clearly preserves the committed result. An error before commit can retain normal choices and retry resolution. Cancellation/lock must not turn a committed operation into a claim of rollback.

**P2 — Define stale/disappeared conflict and confirmation ownership.** Capture the conflict version together with the Keep One choice shown for confirmation, and prevent a confirmation from applying to a replaced payload. Specify what the user sees if the conflict disappears or changes while review/confirmation is open; do not fall back to an empty sheet. A concise resolved message with Done for an absent conflict, or a changed-version message requiring review of current versions, is preferable to silently applying the old choice to new content. Store preconditions remain essential but do not replace a coherent visible state.

These are limited state additions rather than a redesign. Re-review their concrete copy and transitions before implementation.

### Layout and verification requirements

Give the native preview a concrete bounded height within the outer ScrollView; “minimum 220pt” alone leaves its intended sizing ambiguous. Nested scrolling is acceptable for a document preview when users can scroll the sheet outside the preview to reach explanation/actions and can independently reach the complete preview text/image. Verify that at largest text neither title/date nor preview traps the actions offscreen, and that the menu picker exposes the whole selected version value. Preserve platform Cancel/Escape behavior while idle and prevent duplicate operations while saving. Inline errors must wrap and remain discoverable in the sheet. Label the preview context accessibly so switching versions and navigating to Entry text is intelligible without repeated automatic announcements.

The proposed “Saving Changes…” status belongs only to the active user-triggered operation. Native progress/disabled controls are sufficient; no confirmation on Keep Both or success toast is needed. The Keep One confirmation must remain tied to the explicitly chosen device version even if the preview selection differs, and its Cancel must leave data unchanged.

### Baseline evidence

Inspected `/tmp/journal-entry-conflict-normal.log`: the current normal-size test passes in 37.699 seconds with `TEST SUCCEEDED`. Its real encrypted local fixture seeds a text-only local version and a remote version with an image, switches between versions, cancels/reopens, chooses Keep Both, relaunches, and verifies exactly two entry documents equal to the fixture documents, unchanged image bytes and no remaining conflicts. This is useful persistence/route evidence. The test's remote-preview assertion checks text content, not image pixels; independent screenshot inspection is still needed to establish remote-image visibility. It does not test Keep One, its cancellation, largest layout, failure/commit boundaries, stale replacement, lock, VoiceOver or interactive Mac. No screenshots were inspected in this initial proposal review, and a seeded conflict is not evidence of actual network conflict arrival.

## Committed/stale-state revision review — 2026-09-21

**Approved for implementation.** Read the appended “Review revision: committed and stale states” proposal. The explicit 300-point preview (220-point constrained Mac minimum), wrapping selected-version label, captured conflict plus Keep One choice, and invalidation copy “These changes were updated. Review both versions again.” make the intended behavior concrete. Missing conflicts use the parent's “These changes have been resolved.” route with a nonempty local fallback. The two design P2s above are closed by this revision.

The committed boundary is now explicit: mark success immediately after store.resolve returns; a later reload failure hides resolution choices and displays “Changes saved. The entry couldn’t be reloaded.” with reload-only Try Again and Done. Successful refresh selects the resolved item from refreshed state and dismisses quietly. Precommit failures retain normal retry choices. This clearly distinguishes saved data from failed presentation refresh and avoids resolving the same conflict twice.

Source implementation should preserve two related ownership invariants: parent routing must not unexpectedly remove the committed recovery view before its retry/Done state is available, unless the parent's replacement offers the equivalent completed state; direct draft selection must not discard a different unsaved draft or allow an older save task to overwrite the newly resolved record. Retain the proposed store/conflict preconditions and post-await lock/replacement/cancellation checks. These are implementation correctness checks within the approved proposal, not requests for another visual redesign.

Actual implementation and normal/largest UI inspection remain required. The before-large manifest was read for context, but no additional screenshots were inspected or credited by this revision review.

## Initial implementation source audit — 2026-09-21

**One P2 completed-state copy correction remains; actual UI acceptance is pending.** Inspected the extracted EntryConflictReview, ConflictRouting's retained ordinary-entry route, AppModel.refresh identity checks, finishPendingSave, and the revised EntryConflictUITests. No production changes or test reruns by this reviewer.

The implementation follows the reviewed adaptive layout: semantic body preview size, fixed 300-point native preview, wrapping metadata, accessibility-size version menu with separate accessible value, vertical resolution actions, sheet-owned busy/dismiss behavior, inline precommit errors and read-only document preview. Confirmation carries a captured conflict and choice. Resolve waits for pending save, uses the store's captured-conflict operation, and checks cancellation/store/lock/replacement before publication. Committed state hides resolution controls and offers reload-only recovery. A successful refresh preserves an unrelated draft and only selects the resolved record when no draft remains. Keeping the ordinary entry route mounted after conflict removal addresses the committed task/state lifetime concern; lock and other conflict kinds still route separately.

**P2 — Clear stale-review copy when the conflict disappears.** The conflict onChange handler currently always sets “These changes were updated. Review both versions again.”, including a transition to nil. Because this view now remains mounted, it then shows both “These changes have been resolved.” and the impossible instruction to review both versions again. Clear confirmation/reset selection on either change, but reserve the updated message for a nonnil replacement; nil should clear the error and show the completed message with Done alone. This is a correction to the approved missing-conflict state.

Inspected `/tmp/journal-entry-conflict-normal-fixed.log`: UI test compilation fails because XCUIElement has no `lastMatch` member at the confirmation Cancel selector. No executed native UI results are credited to this log. The revised test source intends to exercise adaptive version selection, outer-scroll reachability, Keep One confirmation cancellation, Keep Both and persisted exact documents/image bytes, but successful execution and actual screenshot review remain outstanding.

### Source correction follow-up

Re-inspected the conflict change handler: nil now clears the error, while nonnil replacement retains the review-again message. The completed-state P2 is closed at source level. The test now obtains the last Cancel through a matching query index, removing the unsupported API usage. The replacement test run is still pending and is not credited here. No other material source/design deviation was identified in this bounded audit; actual normal/largest review remains required.

## Actual normal-size conflict route — 2026-09-21

**Accepted for the inspected normal-size iPhone route.** Read `artifacts/entry-conflict-normal/manifest.json` and directly inspected all seven captures. Remote previews `2A6C7FDE-0A48-4F36-8F3A-D8E7815B8235` and `09973DBF-86DF-4EFB-AB33-9E4EFE8C1880` show the complete remote text and blue image, selected Other Device segment, title/date, full Keep Both explanation and both actions. Local previews `239F9BCA-3296-4D37-8DA8-62F5D2D36535` and `0B6FC502-05F4-4EC9-8289-4CCA53DD178D` show local text with no remote image retained. Cancel and the native sheet title remain visible. No clipping or action collision appears in these states.

Confirmation capture `13C4D450-B5FF-4CBF-AC94-0B35F2BF52B1` shows the native popover, complete Version History explanation and Keep Version action. The system omits a visible confirmation title and separate in-popover Cancel in this rendering; this screenshot alone does not establish an explicit cancel button inside the popover. The test's Cancel interaction returns to the unchanged review (`84AA7806-5D0E-4EBA-ACAF-5AD31EC4F5FC`), where Keep Both is visible and subsequently succeeds. Final capture `C2F162E6-B05F-449C-8307-904C378405FD` shows the local entry after relaunch with no conflict notice; it does not visually show both retained entries simultaneously.

Independently inspected `/tmp/journal-entry-conflict-normal-fixed2.log`: the route passes in 44.650 seconds with `TEST SUCCEEDED`. The reviewed test source verifies version switching, first sheet cancellation/reopening, cancellation after choosing the remote Keep One option, subsequent Keep Both, and after relaunch exactly two stored entries matching the local and remote documents, identical remote image bytes and no unresolved conflicts. These store assertions establish retention beyond the final screenshot. No reviewer rerun occurred.

No material visual finding arose in this normal-size scope. Actual Keep One commit, longest/multiple-image documents, precommit failure, committed reload failure, stale replacement/removal, lock/vault transitions, VoiceOver and interactive Mac remain outside this UI evidence. Largest-text review remains pending. The remote-only ordinary-conflict image visibility gap in the image-loading review is now closed for this normal-size seeded-store route, without claiming real network conflict arrival.

## Actual largest-text dark conflict route — 2026-09-21

**Accepted for the visible states and successful route, with full-preview/action-label evidence still incomplete.** Read `artifacts/entry-conflict-large/manifest.json` and directly inspected all seven captures. Remote `24DFE6AE-8ECE-4124-B123-296786D36283` / `34E891DF-2708-438B-90C6-4AA5F343802B` and local `46235B43-66C8-4647-939F-C24A5AB0E61F` / `B42C9536-00C0-42DC-A482-27B155607023` show complete selected-version labels (“Other Device” / “This Device”), the full accessibility-size Review Changes heading, title, wrapping date and readable selected-version body. Remote images are visibly present; the local version does not retain the remote image. The open version-menu contents are not captured, so their operation is supported by the successful test rather than a visual inventory.

Outer-scroll action capture `154FE295-AE93-45F7-A8B2-FA7BA461E86D` shows the full Keep Both explanation and primary action with native Cancel still available. Confirmation `18926C9D-C9BB-4604-9051-18BA1D87E694` shows all of the Version History explanation and Keep Version button at largest text, with native word hyphenation but no missing text. As at normal size, it does not show a separate in-popover Cancel button; the tested Cancel interaction returns to review. Final `792F309A-8D4D-400A-835D-C24E078E9F1F` shows the local entry after relaunch, not both stored entries simultaneously.

Independently inspected `/tmp/journal-entry-conflict-large-fixed.log`: test passes in 58.582 seconds with `TEST SUCCEEDED`. The reviewed source exercises the accessibility-size picker, scrolling outside the preview to reach resolution actions, Cancel/reopen, Keep One confirmation cancellation, Keep Both and the same exact two-document/image-byte/no-conflict persistence assertions as the normal run. No reviewer rerun occurred. No final Apple lane result is credited here.

Two capture gaps remain: the remote image extends below the initial viewport, and even in the action-state capture the fixed preview does not show the complete image; this run does not demonstrate scrolling within the native preview to its bottom. The second line of “Keep One Version” is also below the captured viewport in the action state, although the test successfully taps the menu. Requested an additional inner-preview bottom capture and an outer-scroll capture showing that action label completely. These are evidence gaps, not demonstrated production clipping defects. Existing precommit/committed-failure, stale/lock, VoiceOver and interactive Mac limits remain.

### Largest remote-preview bottom evidence

Directly inspected `artifacts/entry-conflict-inner-preview/019C2A7E-F0BA-4593-8846-EE0A7EE666A9.png`. The complete blue remote image, including its lower edge, is visible within the scrolled native preview at largest dark text; inner and outer scroll indicators are both visible. The preview is followed by the complete Keep Both explanation. This closes the full-image visibility gap from the prior largest capture set. The lower Keep Both action is partially below this capture, so it supplies no additional full-action evidence.

The author reports this capture came from a run that later failed in a test scroll helper. This review accepts the visible state only and does not label that run passed, infer a product defect from its helper failure, or claim the full updated route succeeded. The complete Keep One Version label capture remains pending.

## Complete largest-text route evidence — 2026-09-21

**Both prior visual evidence gaps are closed; the exercised largest-dark route is accepted.** Read the 11-capture manifest at `artifacts/entry-conflict-large-complete/manifest.json`, the revised sheet-scoped test/helper, and `/tmp/journal-entry-conflict-large-complete6.log`. The complete test passes in 69.171 seconds with `TEST SUCCEEDED`; earlier helper-failed runs are not credited as passing. No reviewer rerun or production edit occurred.

Directly inspected these seven captures from that run:

- `844FA7CA-C5B1-47A8-990A-0C27EAC228E5`: complete two-line Keep One Version label, full Keep Both button and explanation, all below the navigation bar and within the sheet.
- `4AB76E77-54EF-4CE2-B079-B0284698D69D`: complete remote blue image, including lower edge, after scrolling within the native preview; both scroll regions are visible.
- `A83F07CE-4744-4669-A43B-ECBCC45174AF` and `DE57F2F0-7AB1-468C-969E-652F15927AC4`: complete Other Device selector safely below the navigation overlay after returning from the preview, with title/date readable. The first retains the inner preview's prior scroll position until the subsequent version switch; that is consistent with independent scrolling.
- `0A5A0527-9578-4167-B0B7-B5CBE4CCF629`: readable complete confirmation explanation and Keep Version action in the native popover.
- `204DB331-DC88-470E-8095-88B551C15A18`: return to review after confirmation cancellation, with complete explanation and both resolution actions.
- `4C3065A5-23B7-42D3-AFF8-A7943AEC69B9`: local entry after relaunch without a conflict notice.

The helper now scopes preview lookup to the conflict sheet, scrolls visible outer content outside the native preview, excludes the navigation overlay and requires full target bounds before interacting. The passing route therefore supports returning from inner preview scrolling to version selection, reopening after Cancel, reaching the complete Keep One label, cancelling its confirmation and deliberately choosing Keep Both. The same real-store assertions verify exactly two matching documents, identical image bytes and no conflicts after relaunch; the final screenshot alone still shows only the local entry.

No new material visual finding appears. The normal/largest selected-device comparison and seeded remote-image route are accepted within this fixture. Actual Keep One commit, longest/multiple-image content, failure/reload recovery, stale conflict and lock/vault transitions, VoiceOver, live appearance preferences and interactive Mac remain untested here. Apple/hygiene success was reported by the author but not independently inspected in this extension.
