# One scrolling writing surface on iOS

## Why allocation cannot fix this case

The measured largest-text landscape screen is 874×402 points. Navigation ends at y78; the predictive keyboard area begins at y194. The available writing surface is116pt. The native title is69.33pt high; the remaining body viewport is56pt after the current60pt header cap. The y descender is cut because the cap is smaller than the title line. Increasing the header alone would clip more of the active body line. Geometry and full-screen captures: artifacts/rotation-measure. Keyboard accessibility frame starts at238 because it excludes44pt of predictions; use the actual full keyboard region for acceptance.

## Proposed layout and interaction

Use a single native scrolling surface for the iOS entry header and rich body, at all text sizes. The title and existing notices appear above the body and scroll naturally out of view while writing. Keep the toolbar, native title/body typography, neutral colors, and familiar editing controls. Do not shrink fonts, hide warnings, or require both title and body to remain simultaneously visible in constrained space. There is no new user-facing copy or control.

Keep the existing UITextView as the scrolling body, selection owner, undo owner and input-method host. Host the SwiftUI header inside that text view's scroll content; its measured height becomes the body text-container top inset. The header's view moves with native scrolling, rather than consuming a permanently reserved external viewport. Keep title and body identity stable through rotation, keyboard changes, content resizing and entry selection. This avoids laying out a complete long body inside an expanding outer SwiftUI scroll view and retains native text virtualization/scrolling behavior.

Retain native title editing above the body. Next focuses the existing body and reveals its current selection. Scrolling upward exposes the complete title and notices; the user can tap the title and edit it. A local save failure scrolls the notice into view after dismissing the alert; Try Again and Export remain reachable even when the keyboard consumes much of the screen. Recovery/conflict/unsupported guidance stays in the same header in document order and must not become a hidden background state.

## Implementation boundaries to review

Use a system SwiftUI hosting content view (UIHostingConfiguration, iOS16+) as a subview of the existing native text view, with explicit model/editor environment. Measure its fitting height at the actual text-container width, update header frame and text-container inset on layout/content changes, and preserve the native selection/typing attributes/undo state. Avoid replacing attributedText merely because the header resizes. Capture a visible body anchor or adjust offset by header-height delta when reading/writing below the header so dynamic header changes do not jump the body. On explicit failure reveal, prioritize the notice rather than compensating the viewport.

Factor the existing header content from its capped independent ScrollView. Prefer stable view identity and callbacks scoped to the current entry. Do not introduce global responders, polling, detached tasks or a new persistence path. The Mac layout stays unchanged.

Accessibility order should follow header/title then body. Preserve each existing accessible control and labels, font scaling and reduced motion. Full text/caret must be readable in the viewport currently being used; normal scrolling may move earlier content off-screen. Header hosting inside an accessible UITextView must be checked for actual accessibility exposure rather than assumed.

## Acceptance

Independent proposal review before implementation. Then native typing before/after rotation, return to portrait, exact stored entry identity/body and relaunch. At largest text, show active line/caret above the full predictive keyboard and deliberately scroll up to show a complete title line, then return to body and continue typing. Inspect normal text too. Re-run the failure-notice retry boundary because its container changes, and the multiline title Next route. Verify selection/undo and image viewport preservation where the header integration touches those behaviors; avoid broad unrelated test reruns. Build a new unsigned device archive only after actual review closes findings.

Do not claim iPad, VoiceOver, IME, all long-title scenarios or physical-device installation from a phone rotation test. These need their own evidence in the full delivery checklist.

## Review

Revised proposal approved before implementation; see [independent review](unified-entry-scrolling-review.md). Implemented with bounded native acceptance and source findings recorded there.

## Review clarifications

A non-accessible native wrapper owns the existing UITextView and projects an explicit accessibility order of hosted header followed by the real text view. The header remains visually inside the scroll content. Preserve native body accessibility editing semantics; verify actual title/notice/button exposure early, before completing the integration. Do not replace the body with a synthetic accessibility element.

Focus/viewport precedence: an explicit failure reveal wins once, after its alert is dismissed, for the current entry/session; it must not repeat on every keystroke. Otherwise an active title keeps its title insertion visible, an active body keeps its own caret visible, and passive reading preserves the visible content anchor. Title focus must not scroll to a stale body selection. Stable header hosting updates must retain title first-responder/selection state and the owned retry operation. Lock/replacement destroys the old view and invalidates any deferred operation.

The empty-body “Start writing…” placeholder moves with the body text-container inset, preserving its existing typography, color, noninteractive behavior and exclusion from accessibility narration. Remove the old fixed RootView overlay on iOS so it cannot overlap the title. The Mac placeholder remains unchanged.

The existing editor has24pt exterior horizontal padding. Inside its hosted header, use4pt title padding to retain the title's28pt screen inset; notices use their normal inset inside the available content width. Review actual notice wrapping. Keep first paragraph's existing8pt top and24pt bottom insets in addition to measured header height. No fixed header-height cap or forced small-height spacing branch remains necessary.

## Conflict notice accessibility correction

The explicit largest-text capture artifacts/unified-final-actions/0240AD07-C434-47EC-94FC-8D3AEB5623FC.png exposes a side-by-side notice that breaks ordinary words across multiple lines. At accessibility Dynamic Type sizes, use a leading-aligned vertical layout with12pt spacing: the complete message “This entry has changes from another device.” followed by the native “Review Changes” button. Each receives the full available width for natural wrapping. Retain normal-size horizontal arrangement, shared scrolling, system fonts/colors and existing action/sheet semantics. Remove the horizontal spacer in the vertical arrangement. No smaller fonts, abbreviated copy or extra controls. Preserve the notice view's state identity while changing layout (AnyLayout).

Inspect the corrected message and complete button at largest text, activate review and retain the existing stale-version preservation check. This is an observed readability correction; no new conflict behavior is proposed. Await independent approval before editing the notice.
