# Image description keyboard proposal review

Date: 2026-09-20. Independent preimplementation review of `image-description-keyboard.md` and actual largest-text/dark screenshot `artifacts/image-keyboard-final-previews/F505B681-98EA-4969-BCE1-31AEF81FC17D.png`.

## Outcome

**Approved for implementation as a bounded native correction, subject to actual caret-visibility verification.** The supplied screenshot confirms that the active field is mostly behind the keyboard and the insertion point is not visible, despite the reported successful continued typing and exact persistence. This is an unresolved visual editing problem; passing the persistence test alone is insufficient.

A native vertical TextField with `lineLimit(1...3)` is a reasonable first correction. A semantic visible-line range respects the system text size while allowing the native control to scroll longer content internally. It does not justify a character limit, lossy ellipsis in stored text, or smaller fonts. Keep image context, the outer scroll view, native toolbar actions, and all existing draft/save/recovery semantics.

Three lines are a hypothesis, not a guarantee: at accessibility sizes, even a bounded field can sit mostly below the keyboard if the outer form does not position it appropriately. Verify both layers cooperate: the outer form exposes the focused field, and internal scrolling follows the caret as text exceeds its visible range. Earlier lines must remain reachable for editing as well as later lines. Nested scrolling is acceptable when native behavior makes this practical; if it remains difficult, reassess focused-field placement or a conventional native editing layout rather than suppressing the accessibility setting.

## Required evidence

Use an actual keyboard-open largest-text/dark run with content longer than three lines. Capture the insertion point and newly typed text visibly above the keyboard after continued input, then move within the longer value to demonstrate it remains editable. Save and compare the exact entire value after relaunch. Inspect the field at normal text size and ensure Copy Descriptions still contains the complete string, including portions outside the visible line range. Verify the Mac build and its bounded-field layout; offscreen Mac evidence does not establish interactive keyboard behavior.

Do not mark the defect resolved if a screenshot merely shows the first line with the caret hidden or if automated typing succeeds invisibly. The proposal correctly calls for another layout assessment if this native line range is insufficient. No additional design revision is needed before trying the stated change, and no user-facing copy change is required.

## Focused-field placement revision review — 2026-09-20

**Approved for implementation and actual keyboard verification.** Inspected `artifacts/image-bounded-previews/60EAB87B-F40F-4C2B-98BD-013546834AED.png`: the line-range change shifts the internally visible text but leaves the field itself mostly behind the keyboard. The original visual editing defect remains; the parent-reported persistence/build passes do not close it.

The appended Focused-field placement revision addresses the missing outer-scroll step directly. On deliberate focus, scrolling the specific field's stable block ID below the navigation bar is a conventional way to give its native internal scroll area useful space. No auto-focus, forced selection, repeated keystroke scroll, timer, or font reduction is needed. Keep later user scrolling under user control, clear focus on lock, and respect reduced motion if adding animation; an unanimated focus scroll is acceptable.

Use the field itself as the scroll target, not the enclosing image section, so the preview does not consume the recovered editing space. Confirm the final settled keyboard layout still exposes the field: a focus callback before keyboard layout settles is not automatically proof that placement remains correct. Also preserve the field's accessible image ordinal when its visual preview moves above the viewport. Existing explicit reload/cancel/data-preservation rules remain unchanged.

Verify continued input beyond three lines with a visible caret and typed text above the keyboard, then exact full-value relaunch preservation. Inspect normal text-size placement as well. No additional proposal revision is required to implement this bounded focus behavior; if the resulting capture still hides the insertion point, do not report the defect resolved.

## Settled keyboard placement revision review — 2026-09-20

**Approved for bounded implementation and visual recheck.** The actual focus-only image `artifacts/image-focus-previews/6BBD54C6-61BA-431A-AF16-2525B4D6B867.png` shows improvement, including part of the caret, but the current edited line is still partly covered by the software keyboard. The visual defect is not resolved.

Responding once to iOS keyboardDidShow by positioning the still-focused field is a reasonable native event-based timing correction. Retaining focus-transition positioning supports hardware keyboards and Mac; avoiding delays, recurring timers, and keystroke scrolling respects user control. Scope the event handling to this visible unlocked sheet and an image ID still in its current roster, and do not recreate focus or selection in response to an event. Prefer no animation; any optional animation must respect reduced motion.

The event name alone does not guarantee the SwiftUI scroll geometry has the necessary keyboard inset or scroll extent. Verify the final field and full edited line are above the keyboard after continued input, not merely that a second scroll request runs. If the event-based attempt still cannot move the field far enough, investigate actual keyboard-safe-area layout and available scroll extent rather than adding progressively longer delays or more notifications. No further design revision is needed before this bounded attempt; exact value preservation, native Copy, and lock clearing remain mandatory.

## Settled-event actual result — 2026-09-20

Inspected `artifacts/image-settled-previews/595DF8C8-6A65-41AE-8BD3-5AC611996658.png`: the active line remains partially covered, essentially matching the prior focus-only state. The keyboardDidShow attempt did not resolve the defect. The parent reports removing that ineffective event handler and retaining the line range/focus behavior while investigating actual scroll geometry. **Keyboard visibility remains open.** Passing persistence checks must not be reported as a visual fix. The proposed native Form alternative is reviewed separately in `image-description-native-form-review.md`.

## Corrected outer-scroll evidence and causal correction — 2026-09-20

**Limited keyboard-visibility approval: no native Form change is needed on this evidence.** Inspected actual screenshot `artifacts/image-outer-scroll-previews/7475429B-FA2D-4081-A405-914B4CB0BE62.png`: the full current three-line field range, newly inserted “today,” and insertion caret are clearly above the software keyboard. Copy Descriptions is also visible above it, and native Cancel/Done remain available. This is materially stronger evidence than successful invisible automated typing.

Read `artifacts/image-outer-scroll-previews/A97F2F4F-427C-4738-B5B8-004A7F2BADA1.txt`: the focused field is y174.3 with height187.3 (ending361.6), while the complete inputView begins at y539; the keyboard-key element begins at y583. This agrees with the visual clearance. The prior gesture used y553, derived from keyboard-key bounds, and started inside the prediction surface. The corrected gesture starts above the actual inputView and outside the nested field, scrolling the outer content. Therefore earlier captures demonstrated occlusion at those positions but did not establish that ordinary outer scrolling could not expose the caret. The native line-range/focus implementation supports visible editing after a correctly targeted scroll; the keyboardDidShow handler remains unnecessary and removed.

The parent reports continued typing and exact full-value preservation after relaunch for this run. The screenshot and hierarchy were independently inspected here, but the test was not independently rerun. Record this as resolution of the demonstrated caret-reachability concern with normal scrolling, not proof of automatic caret placement in every initial focus state. A meaningful whole-field-above-inputView assertion, normal-size check, and earlier-text edit/cancel verification are still pending. Full VoiceOver, hardware keyboard, and interactive Mac behavior retain their limits. The approved but unimplemented native Form proposal can remain an alternative rather than required work.

## Final focused verification — 2026-09-20

**Approved for the bounded normal-size and largest-text software-keyboard editing flow. No further product layout change is requested.** Inspected `artifacts/image-keyboard-verified-normal-previews/636680F4-6CF6-4B10-B8A5-F920AD28E399.png` and `E05C60B0-8EF9-4BC1-A792-934AB0D125D2.png`: continued input and editing earlier text both show the active caret/line above the keyboard, with native completion/cancel controls available. At largest text in dark mode, `artifacts/image-keyboard-verified-large-previews/87945F0B-9477-4907-A7ED-445C3D0511D6.png` shows the complete current field range and caret safely above the input surface after outer scrolling. `C2EC7336-C1CB-49EE-9388-5A2D93CDC3F3.png` shows the earlier-line edit and caret clearly visible; lower inactive lines extend behind the keyboard at this different scroll position, so this particular screenshot does not establish whole-field clearance, nor is whole-field clearance necessary to read that active earlier line.

The parent reports both final actual focused tests passed: full field bottom is asserted above the entire inputView after continued typing, the exact value survives terminate/relaunch, and an earlier-text edit followed by Cancel leaves the previously saved value unchanged on reopening. These reported assertions plus inspected active-caret screenshots close the pending normal-size/earlier-text verification within the tested scenario. This reviewer did not independently execute those tests. Product source did not change in this final verification turn; the Form alternative remains unimplemented and unnecessary for this finding.

Copy Descriptions button reachability is established in the relevant images; its whole-string construction was source-reviewed earlier. Actual clipboard contents were not exercised here and must not be described as verified. Screen-reader narration, main-editor inline attachment VoiceOver behavior, hardware keyboards, interactive Mac, and automatic caret positioning in every initial focus state remain outside this approval. Native outer scrolling remains part of the supported largest-text interaction.
