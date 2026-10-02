# Device orientations: independent design review

## Proposal verdict

Approved for implementation as a configuration change. Reviewed `device-orientations.md`, the universal iOS target in `apps/apple/project.yml`, and the current entry/header layout. The source declares device families 1 and 2 without supported-orientation properties. The archive warning is parent-reported; the reviewer did not inspect an archive log or run a build.

Portrait and both landscape orientations on iPhone, with all four on iPad, follow familiar native behavior. Keeping iPad multitasking available is appropriate for a writing app. Standard orientation declarations with SwiftUI/native adaptation introduce no unnecessary controls, copy, or navigation. Add the declarations to the generating project configuration, not only a generated plist, so regeneration preserves them. Preserve the distinction between the general/iPhone key and the iPad-specific key.

No material proposal change is required. Configuration approval does not certify every existing screen in landscape.

## Interaction, accessibility, and preservation criteria

Rotation should resize the current writing surface without replacing the selected entry or resetting editing state. There should be no orientation-based view identity, forced keyboard dismissal, or new persistence path. Continue typing after rotation without an extra editor tap where native focus is retained, then rotate back and verify the complete title/body and selected entry/journal. Check the stored entry identity and content after relaunch; do not rely solely on visible text, which could belong to a new or different entry.

The current iOS header is capped at half the available height, and the body shares the remaining area. Landscape plus an on-screen keyboard is therefore the most useful stress case. Inspect the actual landscape dimensions, caret and active line above the keyboard, reachable title/header content through normal scrolling, and navigation controls clear of side safe areas. Repeat the bounded writing route at an accessibility text size if the normal run leaves uncertainty about usable editing height. Honor system text sizes rather than shrinking text or suppressing the keyboard to make a screenshot fit.

The proposed test can establish rotation during normal editing and persistence across relaunch. Because the app autosaves, that alone does not establish preservation of an unsaved draft under a failed write; use the existing rejection scenario only if making that stronger claim. Do not infer VoiceOver focus/reading order, marked-text/IME preservation, or undo continuity from screenshots or a simple text assertion.

An iPhone rotation run does not establish iPad upside-down orientation or multitasking layout. A representative iPad rotation is useful, but retain the proposal's explicit limit on all iPad window sizes and physical-device behavior. Empty, locked, error, and sheet states receive no new copy or behavior in this change; absence of code changes does not constitute rendered acceptance of those states in each orientation.

## Completion evidence

Inspect the generated/archive plist for the intended orientation arrays and lack of a new full-screen restriction, and confirm the original archive warning is gone. Independently inspect the actual portrait/landscape/returned-portrait captures after implementation. Record test and archive outcomes separately from visual observations, with no broader device/accessibility acceptance claims. No reviewer tests were run and no production files were changed.

## Normal iPhone actual UI and archive review

Inspected both images listed in `artifacts/rotation-screen/manifest.json`, taken with `XCUIScreen.main.screenshot()`. `DCE190AD-C1D5-487B-8D49-6237462C5457.png` shows the full landscape screen: complete “Daily notes” title, complete “Before rotation. After rotation.” body and insertion caret above the keyboard, and navigation controls clear of the screen edges. The writing area is shallow but usable for the captured normal-size line. `A3492692-C9EF-457E-8470-C36DCB2ACF26.png` shows the complete title/body and caret above the keyboard after returning to portrait. No material normal-size visual issue was found. These full-screen images replace the parent's earlier cropped app-only capture as the evidence used for this review.

Read the relevant execution log: `/tmp/journal-rotation-screen.log` records rotation to landscape and back to portrait and a passing `testRotationWhileWritingPreservesEntryAcrossRelaunch` in 22.319 seconds. Inspected test source types in landscape via `app.typeText` without tapping the editor again, checks the combined body/title on return, and checks body text after relaunch. Final real-store assertions verify a single entry with the original entry ID, journal ID, and exact body text block list. This supports normal editing continuity for this route, not full document equality or failed-save draft preservation. No reviewer test was run.

Inspected `/tmp/journal-orientation-archive.log`: the archive succeeded; the supported-orientation warning is absent. The only reported warning is unrelated AppIntents metadata extraction. Read the archived `artifacts/ios-orientation-refresh/Journal-development.xcarchive/Products/Applications/Journal.app/Info.plist`: the general array contains portrait and both landscapes; the iPad array additionally contains upside-down portrait; `UIRequiresFullScreen` is absent. This is an unsigned development archive, not physical-device installation evidence.

Normal iPhone presentation and the orientation declaration/archive outcome are approved. A bounded largest-text rotation follow-up is warranted before closing landscape accessibility layout review: the normal landscape screen already leaves a shallow writing band, while the header can consume half the available height. Reuse the same typing/rotation-return route at the largest text size and inspect the active line/caret above the keyboard and reachable header content. No new product design is requested unless that actual evidence reveals a deviation. This does not request a broad device matrix or establish iPad, VoiceOver, IME, other sheets/states, or physical-device behavior.

## Largest-text finding and short-height proposal review

Inspected both images in `artifacts/rotation-large/manifest.json` and the pass record in `/tmp/journal-rotation-large.log` (22.651 seconds). `9E76A081-AD7E-490A-9488-3EC2FE5A53D1.png` shows a material landscape layout defect: the header viewport slices through the title glyphs, leaving only their upper portion visible. This is vertical clipping across the title, not a horizontally overlong string. The body text and caret are visible immediately above the keyboard with very little clearance. `0E1EACEE-2720-4BDC-82A3-754298E8E2BC.png` shows a complete title and body on return to portrait. A passing preservation test does not establish acceptable title presentation; largest-text landscape is not yet approved.

Re-read `RootView`'s height allocation, `EntryHeaderView`, and the native title view. The title has zero internal text-container inset and uses the system title font; the header adds 28 points above and 12 below its title block within a half-height scroll viewport. Reviewed the appended “Largest-text short-height correction proposal” before product implementation.

The proposed removal of only those decorative title-block vertical insets when available editor height is below 240 points is approved as a minimal first remedy. Basing it on available height, including native keyboard avoidance, is more appropriate than device/orientation branches. Retain horizontal spacing, native text sizing, independent notice padding/actions, the header's scrolling and half-height cap, and editor identity/focus. No new copy or controls are needed. This approval does not authorize hiding warning/recovery/conflict content or changing font size.

Inspect the corrected complete current title line and complete active body line/caret with the largest-text keyboard present, then returned portrait. The threshold and removed padding are a concrete design hypothesis, not proof of sufficient height. If a complete title line still cannot fit, re-review a measured height allocation or natural scrolling design before further UI changes. Arbitrarily long titles need not fit simultaneously, but normal scrolling must allow a complete line to be read. No production file was edited and no test was rerun by the reviewer.

## Spacing-only implementation: remaining glyph clipping

Source inspection confirms the approved change removes only the title block's top/bottom padding below 240 points of available height; horizontal and notice padding, fonts, and half-height allocation remain as reviewed.

Inspected both images in `artifacts/rotation-large-spacing/manifest.json` and the 22.898-second pass in `/tmp/journal-rotation-large-spacing.log`. Landscape `641CE11D-60CE-4898-8819-400F0B947566.png` is substantially improved, but the bottom of the title's “y” descender is still clipped. Compared EXIF-normalized, enlarged crops of this actual screenshot with returned-portrait `E2F798D9-7398-4577-A789-8DB107647EFA.png`: the landscape descender ends at a flat horizontal boundary, while portrait shows its complete rounded lower tip. The full title-line criterion is therefore not met. The body text remains readable, with its caret meeting the keyboard edge and little vertical margin; simply borrowing more body height without checking line metrics could move the clipping problem.

Also inspected both normal-size images in `artifacts/rotation-normal-spacing/manifest.json` and the 22.366-second pass in `/tmp/journal-rotation-normal-spacing.log`. `F348972A-9E4D-4A6E-B681-63E440A125FA.png` shows complete landscape title/body and caret with keyboard clearance; `D2B59192-CC55-44E1-AC9B-D01A90298AB8.png` shows complete title/body on return to portrait (no caret visible in that capture). Normal-size presentation remains approved.

Largest-text landscape remains open. The next proposal should account for a complete title line and a complete body line with native insets/caret clearance, or use a reviewed scrolling arrangement when the sum cannot fit. No additional product modification is approved by this finding alone. No tests were rerun by the reviewer.

## Unified scrolling supersedes the constrained header

The separately reviewed unified-scrolling design now provides the full landscape writing viewport to the native editor and lets the header scroll naturally. Actual `artifacts/unified-rotation-large/8D84231E-E690-47C8-B921-2AE97A7C34D5.png` shows the entire title line and its complete “y” descender after upward scrolling. Companion captures show a readable active body line/caret, Next back to continued writing, and retained title/body on return to portrait. The specific largest-text title clipping finding is closed for this bounded route. See `unified-entry-scrolling-review.md` for the detailed five-image review, source correction/version limits, and remaining integration acceptance. This does not validate the prior fixed-header archive or establish iPad/VoiceOver/IME behavior.
