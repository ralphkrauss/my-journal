# Native writing and onboarding revision — independent design review

Date: 2026-09-21
Proposal: `docs/design/testing-feedback-revision.md`
Disposition: revise before implementation of the affected flows. The native layout and interaction direction is sound; three material specification gaps remain below.

## Scope and evidence

Reviewed current `AGENTS.md`, the proposal, the full user issue list supplied by the parent, the user's Apple Notes screenshot, and existing formatting, connection, archive, Settings, and recovery-copy source. No frontend code was changed and no live Mac actions were performed. This is a proposal review, not actual-UI acceptance or cryptographic/protocol approval.

The proposal covers each reported issue: one chosen password without confirmation, generator support, optional encryption, Default journal, initial title selection, clipped entry snippets, toolbar ownership, explicit template creation, compact formatting and complete row hit areas, two-field links, repeated-click dismissal, removal of the duplicate Mac ellipsis, journal context actions, a single default-template picker with current values, independent Settings access, simpler Settings surfaces, and touch-platform adaptation. The Notes reference supports the compact rows and clear grouping; copying its unsupported text features is unnecessary.

## Material findings

### 1. Specify protection-aware copy throughout recovery, connection, and archives

The proposal changes onboarding and Privacy but leaves the rest of the credential journey implicit. Existing connection/local-server/unlock/archive screens ask for a “Recovery Key”; archive export currently promises “An encrypted copy…” unconditionally. Those become misleading for a new Master Password or an unencrypted library. The old Save Recovery Key action also needs an explicit disposition when a user-chosen password is not retained.

Before implementation, add a compact copy/state matrix for legacy recovery keys, encrypted password libraries, and unencrypted password libraries. Cover unlock fallback, server setup/recovery, archive export/import, incorrect credentials, and unsupported client/server versions. Use the same credential name that the user saw at creation; determine it from the source envelope before asking where possible. If source metadata is not available yet, specify neutral copy until it is. Plaintext archive export must explicitly say the archive is not encrypted. Existing PIN wording must continue distinguishing app unlock from recovery and file protection. Do not retain an action implying the app can retrieve a forgotten master password. Include actionable unsupported-version copy without encouraging creation of a replacement library over existing data.

### 2. Complete single-field password creation guidance and state behavior

A disabled Create button with no specified minimum-length explanation leaves the user guessing. Removing the recovery-key confirmation also removes the existing explanation that credentials alone are not a backup and that losing all recovery access can be permanent. A user-generated or locally generated password needs equally clear, concise guidance before Create; a second password field or extra confirmation screen is not required.

Add visible “Use at least 12 characters.” guidance and concise recovery/backup wording appropriate to the selected protection mode. Specify the initial hidden state, Show/Hide Password labels, Copy Password availability for both generated and typed values, and that reveal/copy/generation do not unexpectedly submit the form. State whether Generate Password is always available rather than “optional”; the user explicitly requested generator support. Generated and manually entered values must remain editable and identical across reveal toggles; disable secret-changing controls during creation. Specify focus and keyboard-safe scrolling, a progress label, and exact actionable creation-error copy. Clear password state on successful creation and cancellation; copying is a deliberate user action, not automatic.

### 3. Make the template chooser and touch layouts concrete enough to implement consistently

“Templates…” opens a chooser, but the proposal does not yet define its title, contents/selection, confirmation or immediate-creation behavior, cancellation, empty state, or a template that disappears while open. These determine whether one click unexpectedly creates an entry and whether the reported creation-menu confusion is actually resolved. Define one native chooser flow with exact labels, Blank Entry always available, creation into the journal captured when the chooser opened, and safe handling when that target/template is no longer available.

The touch section also says “adaptive popover/sheet” without defining which presentation applies. Specify compact iPhone versus regular-width iPad behavior, including iPad multitasking adaptation, formatting dismissal, and entry-list toolbar overflow. Keep New Entry and Templates visibly associated with the entry list, and give every symbol-only action an accessible name. State how journals can be renamed/deleted on touch without requiring a context-menu gesture. This needs a short layout description, not a custom component system.

## Accepted direction and implementation conditions

The three-column Mac structure, bounded list action strip, intrinsic snippet height, removal of the editor ellipsis, title-first creation, native Settings window, and separate Journals management sheet directly address the reported problems. A single native template picker and latest-record updates are appropriate. Keep context actions tied to the clicked journal rather than the selected one. Rename/Delete must remain discoverable by keyboard as well as secondary click.

The formatting density is appropriate for Mac, provided text is not clipped at the proposed row heights. Retain 44-point touch targets, full-row hit testing, system selection states, keyboard access, and accurate mixed-state accessibility. The repeated-click toggle must be checked with the actual pointer resting on the toolbar control; source inspection cannot establish it. Link capture/session validity and inline validation are sound. Explicitly decide how editing the prefilled Text replaces a selection with mixed formatting, so acceptance does not accidentally promise preservation after arbitrary text replacement; preserving existing attributes when only the link changes is already clearly required.

The existing acceptance plan is appropriately behavioral. After the material revisions are recorded, re-review the affected proposal before frontend implementation. Final acceptance requires actual Mac default/narrow layouts and iPhone/iPad evidence, including large text and keyboard-visible forms; proposal approval alone cannot close clipping, focus, hitbox, or Settings-routing issues.

## Amendment re-review — 2026-09-21

Reviewed the added Review amendments against the three findings. Product naming is now **My Journal**; repository publication is outside this design review.

The credential matrix now covers legacy and both password modes, conditional archive copy, and plaintext pairing disclosure. Generation/replacement, deliberate copy, minimum length, recovery guidance, busy state, cancellation, and retaining values after failure are defined. The chooser now has a destination, preview list, initial Blank selection, explicit creation, cancellation, and empty/error behavior. Compact iPhone and regular iPad journal/settings layouts are substantially clearer. These resolve the substantive direction of all three findings.

A short consistency pass is still required to close the proposal gate:

- Replace the original “optional Generate Password” with an always-available action, initially showing a hidden password field. State initial keyboard focus and native scrolling to the active field. Add exact creation-failure copy, for example “Your journal couldn’t be created. Try again.” This error must not imply that partially completed storage can simply be discarded; implementation still needs safe retry.
- The chooser's Cancel/Create controls conflict with the amendment's iPhone “Done/Cancel actions”. Keep Cancel/Create on every platform; Done belongs to management/settings, not creation. Specify exact unavailable-destination and missing-template explanations, keeping the chooser open rather than substituting a different destination/template.
- Include actionable unsupported-version copy, for example “This journal needs a newer version of My Journal. Update the app and try again.” For an incompatible server, say that the server needs an update. Preserve existing data in either case.
- Finish the previously requested formatting adaptation rule: compact width uses a scrolling sheet with Done; regular-width iPad uses an anchored popover, adapting to the sheet in narrow multitasking. Retain selection/session capture across presentation changes.
- Update the app-menu reference to “My Journal > Settings…”.

No redesign is requested. The affected flows are ready after these small contradictions and remaining exact states are recorded and checked. Actual UI acceptance remains outstanding; no implementation or live-device inspection was performed in this re-review.

## Final proposal verdict — 2026-09-21

**Approved for implementation.** Independently reread Final interaction clarifications. The latest text resolves the generator availability, hidden initial password/focus, creation error, unsupported-format stop, chooser Cancel/Create, formatting presentation, and My Journal naming issues. Treat these final clarifications as superseding the earlier “optional” generator, iPhone “Done/Cancel”, and old menu-name wording; consolidating those sentences later would improve readability but is not a design blocker.

No material proposal findings remain. Apply the compact formatting sheet rule when an iPad window becomes compact as well as on iPhone; keep the existing captured-session safeguards through adaptation. Unknown formats and incompatible servers must remain non-destructive, with the stated update guidance. Missing destination/template failures keep the chooser open and do not substitute another journal or template.

This closes the independent pre-implementation design gate for the revised flows. It does not approve cryptographic implementation, claim passing behavioral checks, or replace actual Mac/iPhone/iPad UI acceptance after implementation.

## Actual iPhone review — 2026-09-21

Independently inspected all 11 PNGs and the manifest under `artifacts/feedback-review/iphone-evidence`, plus current `FormattingPopover.swift`, `SettingsView.swift`, the relevant `RootView.swift` routes, and `FormattingState.swift`. No live Mac interactions or test reruns were performed.

### Observed visuals

The formatting captures (`E7543E52…`, `3CCBD285…`) show complete inline controls, paragraph/list rows, Link, and Done without clipping. The rows are clear, but the full-height sheet leaves approximately its lower half empty. A native medium/large detent refinement is approved within the existing scrolling-sheet design: retain large-height expansion, scrolling at large text, and reachable dismissal. It does not require a new custom layout.

The title/body captures show complete wrapped title text and an insertion point above the keyboard; the title/body and toolbar do not overlap. The two captures labeled beginning/end of a long title show the same three-line title, so those names alone do not establish long-content scrolling. The quiet-editor image still has the keyboard visible. The native image picker captures show its empty local-provider state, not successful image insertion. Change Date has readable date and visible Cancel/Save; its large blank region is a density observation, not a blocking clipping defect. The entry context menu is readable and its preview has a properly truncated title and unclipped one-line snippet; this does not establish two-line long-snippet behavior.

### Required corrections or verification

1. **Direct Settings entry point is not implemented as approved.** `RootView.listToolbar` still makes the gear a menu labeled “Journal” containing Settings and Lock Journal. Replace the extra menu step with a directly labeled Settings button as specified; keep Lock in its existing Privacy route or another appropriate existing action location. The screenshot confirms the gear's location, while this behavior is a source finding.
2. **Mixed inline formatting is misrepresented accessibly.** `FormattingState` uses `allSatisfy` booleans, so mixed bold/italic/underline returns false; `FormattingPopover` announces that as “Off”. Preserve a mixed state and announce “Mixed” for a mixed selection, without falsely showing it as wholly on or off. The paragraph state already avoids claiming one style when it differs. This is a source-confirmed deviation, not a VoiceOver observation.
3. **Ensure the entire Done control has a touch target.** Its `minHeight: 44` frame currently wraps the Button rather than the label; unlike the other rows, it lacks a label-sized content shape. Put sizing/hit area inside the label or use native toolbar dismissal. Other formatting rows explicitly size their labels and set rectangular hit shapes. Screenshots cannot establish hit-test bounds.
4. **Touch journal management differs from the reviewed route.** The journal menu offers Manage Journals, but not the specified Manage This Journal route. Either implement the current-journal route with a captured journal identity or explicitly record a narrow design revision to the all-journals form. Rename/default/delete remain available in that form by source inspection; this is a discoverability deviation, not evidence of missing underlying actions.

`SettingsView` now has the intended iOS NavigationStack/list with pushed panes and root-attached Done, without the former nested tab UI. No Settings root/pane or Journals-sheet screenshot is present, so actual root-only Done, Back behavior, keyboard-safe panes, and sheet layout are not yet visually accepted. No iPad or large-text evidence is included in this set.

The parent reports personally verifying Mac second-click formatting dismissal, Text+URL insertion and undo, clean snippets, the native journal template picker's selected value, and independent Command-comma Settings access. These remain parent-reported interaction results, not observations made in this review.

Verdict: the supplied iPhone views are visually readable in the captured conditions, but implementation acceptance remains open for the concrete deviations above and the missing Settings/iPad/large-text evidence. No production code was edited by the reviewer.

## Correction and accessibility/iPad evidence review — 2026-09-21

Independently verified all four earlier source corrections: the gear is now a Settings button; inline formatting preserves On/Off/Mixed and supplies a dash plus accessible value; Done's label owns its minimum 44-point rectangular hit area; Manage This Journal captures a journal record and opens a sheet filtered by its ID. Those four findings are closed at source level. This does not claim direct VoiceOver or touch-coordinate testing.

Inspected these relevant screenshots under `artifacts/feedback-review/accessibility-evidence`: formatting `D3E4ABE4…` and dismissal `C21C2BCC…`, date `7ECBC68A…`, title end `4E776D53…`, body focus `C27B8E3A…`, template title focus `9AC6BF17…`, template answer `6ECD2B61…`, journal/template setting `847FEEB4…`, template cancellation `D722F5CA…`, and entry context menu `1B5DCFF4…`. Dark, very large text remains readable. Formatting wraps Numbered List without cutting the label; Link and Done are fully visible. Date and its Save/Cancel actions are complete. The selected Daily review template is fully visible in the native picker. Title/body/template captures put the active insertion area above the keyboard. Content partly outside the top of a scrolled viewport is not evidence of lost text. The template alert cancellation capture has its Save row partly scrolled away while Cancel is completely exposed; it does not establish both buttons simultaneously visible. No new material clipping finding arises from these captures.

Inspected the original `ipad-evidence` formatting `816B11F7…`, reopened entry `E1FF1769…`, Move Entry `0EE1AA31…`, date `D01C4113…`, and export `C3E34E5D…` captures. Formatting fits in a bounded anchored popover above the keyboard. The reopened entry has an unclipped two-line list snippet and complete editor body. Move/date/export sheets show their labels and principal actions without overlap. These captures visibly retain the already-reported clipped duplicate journal navigation title beside the list toolbar. Current source removes that title on iOS while retaining the selector; updated capture verification remains necessary before describing that visual defect as independently closed.

Independently read pass records: accessibility EntryActions 65.070 seconds and default-template workflow 82.296 seconds; original iPad write/reopen 55.647 seconds; final iPad EntryActions rerun 59.534 seconds. The original iPad EntryActions failure remains in its log; the parent attributes it to the test's unconditional sidebar hide. The final passing rerun is separate from the older screenshots reviewed here.

The parent reported medium/large compact formatting detents, but the source inspected in this review still has a plain sheet and no `presentationDetents` occurrence in JournalApp. Treat the detent refinement as approved but not independently established. The large-text screenshot itself is acceptable at full height. The supplied manifests still contain no Settings root/pane captures, so Settings navigation is source-reviewed and parent-tested, not visually accepted by this reviewer. No live Mac actions or test reruns were performed.

Bounded verdict: previous implementation findings are corrected; reviewed large-text and iPad content surfaces introduce no new material defect beyond the known pre-fix iPad title. Remaining evidence limits are the updated iPad toolbar capture, actual Settings root/panes, and any claimed medium-detent result. Do not describe this as blanket platform or accessibility acceptance.

## Updated iPad Settings and chooser acceptance — 2026-09-21

Independently inspected all four captures in `artifacts/feedback-review/ipad-settings-final`, their manifest, the focused test source, and its passing log `/tmp/journal-feedback-flow-ipad-final.log` (34.621 seconds). No UI code was edited or live Mac action performed.

- Settings root (`72079660…`) shows a clean native navigation list with Sync, Devices, Privacy, Journals, and a single Done action. No nested tab panel remains.
- Privacy (`11C31DCF…`) shows a native Back button, no root Done carried into the pane, complete encryption status, and readable App Lock guidance and controls. Backup continues below the scroll viewport; the capture does not establish its full content.
- Current journal (`E60EF3A4…`) clearly identifies Default, shows its name, one Default Template picker with Blank Entry selected, Delete Journal, and Done. No duplicate picker wrappers or chevrons appear.
- Template chooser (`4A1EC063…`) shows New Entry, destination Default, Cancel/Create, Blank Entry and named template previews, with Workday Log visibly checked. Nothing overlaps or truncates in this regular-width, normal-text capture.

The underlying entry-list toolbar is visible in these captures with complete New Entry, Templates, Settings, and sidebar controls. The stray clipped duplicate navigation title is absent while the Default selector remains. The earlier iPad title-clipping finding is now independently closed visually.

One non-blocking focus observation remains bounded: the Privacy capture shows a keyboard, while the preceding Settings-root capture does not. The focused test taps Privacy but does not tap a PIN field before this capture. The image does not identify the first responder, so it cannot distinguish automatic native form focus from delayed background-editor focus. The keyboard reduces available pane height without covering the displayed controls; this is not evidence that typing edits a background entry. Do not claim first-responder isolation or intentional keyboard presentation from these screenshots alone. The old product-name phrase “unlocks Journal” also remains visible; it is a minor naming inconsistency with My Journal.

The actual regular-width iPad Settings, current-journal, chooser, and toolbar surfaces are accepted within these captured conditions. `RootView.swift` now independently confirms medium/large detents and a visible drag indicator for compact formatting; updated compact screenshots remain a separate pending review. This acceptance does not cover unshown Settings panes, largest-text Settings, VoiceOver, or every iPad multitasking size.

## Updated compact iPhone acceptance — 2026-09-21

Independently inspected the final iPhone manifest and six relevant captures in `artifacts/feedback-review/iphone-final`: formatting `C45C038B…` and dismissal `EA33A4F0…`, Settings root `61B64EF7…`, Privacy `574E4355…`, chooser `F231DCF9…`, and current journal `E4AA2835…`. Independently read `/tmp/journal-feedback-flow-iphone-final.log`: EntryActions passed in 57.975 seconds and FeedbackWorkflow passed in 34.683 seconds.

The formatting sheet now visibly uses the bounded medium presentation with a drag indicator. All inline, paragraph, list, Link, and Done controls fit without clipping, and the underlying writing remains visible. This closes the normal-text excess-empty-area observation. Settings has a native root list with Done; Privacy has Back without a duplicate Done and displays encryption, PIN guidance, and encrypted-backup/master-password copy with natural wrapping. Unlike the earlier iPad capture, this Privacy capture has no keyboard. Current-journal management shows one native template picker, and the chooser shows destination Default, complete previews, Workday Log checked, and Cancel/Create. No new material visual finding appears in these normal-text, light-appearance captures.

Accepted within this compact iPhone evidence. The earlier iPad keyboard observation remains limited to that capture and is not reproduced here. Largest-text behavior after adding detents is reviewed separately; no live actions or test reruns were performed by the reviewer.

## Final large-text detent verification — 2026-09-21

Independently inspected `artifacts/feedback-review/detents-accessibility-final/C8F10FB0-72F7-4CDF-8255-2122D1C32270.png` and `14E90B5E-B8E9-4F64-87F3-8099268EDF7B.png`, matched their manifest names, and read the 66.841-second passing EntryActions result in `/tmp/journal-feedback-detents-accessibility.log`.

At largest text in dark appearance, the initial medium sheet exposes the top formatting rows and a visible drag indicator; lower rows extend beyond that viewport. The subsequent dismissal capture shows the sheet expanded to large, with every formatting label, Link, and Done fully visible. Numbered List wraps as whole words. The lower content is reachable rather than permanently clipped; do not describe all controls as initially visible at the medium height.

Accepted for the supplied normal-text medium and largest-text expanded-sheet paths. This closes the outstanding compact-detent visual check. No material findings remain in the bounded revised iPhone/iPad surfaces reviewed here. Previously recorded limits, including untested VoiceOver, unshown Settings panes/multitasking sizes, and the non-blocking single iPad keyboard observation, remain unchanged. No UI code or live Mac state was changed by the reviewer.

## Mac hit-target correction — 2026-09-21

The parent reports a final live Mac hit-test deviation: clicking the far-right visible Heading/Body row area did nothing, while activating the accessible label worked. This is parent-observed interaction evidence, not a reviewer live observation, and reopens the full-row hit-target finding despite the earlier source review.

The proposed correction—expand each row label with `frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)` before applying its rectangular content shape—is approved under the existing full-row design. Preserve the current row height and selection capture. Actual far-right clicks must be retested for paragraph rows and Link, including successful formatting, dismissal, and unchanged intended selection; source sizing alone cannot close the finding.

Setting `CFBundleName` to My Journal is consistent with the approved product naming and is not a new interaction design. Verify the resulting native app menu after relaunch. No additional design concerns are raised for these scoped corrections; implementation and live verification remain with the parent.


## Primary-agent packaging follow-up — 2026-09-21

After the user-requested resource pause, final Mac and iOS compiled metadata both report My Journal, version0.1.0, and their intended13.0/16.0 target floors. Automatic Xcode plist generation had overridden CFBundleName; the app targets now use explicit XcodeGen plist properties, preserving internal module/executable paths. Final Mac launch visibly shows the My Journal app menu and fresh single-password onboarding; app closed after inspection. This is primary-agent evidence, not an additional independent-review verdict. Full-row pointer acceptance remains inconclusive because coordinate automation misses even visible popover labels; semantic activation works. Explicit row width is compiled, but no physical-pointer success is claimed.
