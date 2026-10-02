# Review: scrolling while typing on iPhone and iPad

Independent design review (2026-10-02) of the first draft of [typing-scroll.md](typing-scroll.md). The reviewer had the
owner's report, the goals (Notes-like typing, earlier fixes kept), the project's direction and the proposal; it read the
code and built nothing. During the review the author corrected one fact: the Format-sheet reveal the draft relied on had
no callers, because the Format panel now replaces the keyboard.

**Verdict: approve with required changes.** The root cause and one shared visible area, with UIKit following the caret
while typing, were accepted as the native direction.

## Findings and outcome

| Finding | Severity | Outcome |
|---|---|---|
| Timed reveals (picture, resize) still run on layout passes and would fight typing right after an insertion or rotation | Must fix | They now use `scrollRectToVisible` against the shared visible area, so they agree with UIKit, and any keystroke ends them |
| Inset timing during the keyboard animation; blank space when the inset shrinks | Must fix | Measured: the inset is set in the layout pass in which SwiftUI shortens the editor, at the start of the keyboard's animation. When it shrinks, the scroll position is clamped to the end of the entry (checked on Finish Editing at the end of a long list) |
| Name every reveal path and its owner, including title → body | Must fix | Listed in the proposal (typing: UIKit; editor's own text changes: one reveal; picture and resize: timed reveal; viewport and inset changes: the header's reveal). Title → body covered by the existing multiline-title Next test |
| Clamp the inset to the real overlap (floating keyboard, Stage Manager, landscape) | Should fix | Controls beside or below the editor cover nothing; at least 88 points of the editor stay visible |
| Spell out the formula against the safe area and SwiftUI's keyboard avoidance | Should fix | Stated; the scroll indicator inset matches |
| Observe controls changes that post no keyboard notification | Should fix | The accessory reports its layout passes |
| Prove UIKit's caret following respects the inset before relying on it | Should fix | Logs on a Release build: on Return UIKit animates to put the caret line 12–35 points above the controls, at the end, in the middle, and in lists (where the editor reveals once and UIKit doesn't scroll again) |
| Remove the temporary instrumentation | Should fix | Removed |
| Settled-position UI checks can't see a cancelled animation; add a device check at 120 Hz | Consider | Added a hosted unit test that records every scroll position while typing at the bottom; it fails with the old reveal (a full-line jump on every Return) and passes with this design. A check on the owner's iPhone is left to the owner, as agents don't use his devices |
| Hardware keyboard, iPad floating keyboard, VoiceOver cases | Consider | Covered by the formula; iPad and rotation suites rerun. Not separately verified on hardware |

Re-review: the revisions tighten the same approach rather than change it, so implementation went ahead; the actual UI
was then inspected in recordings and screenshots.
