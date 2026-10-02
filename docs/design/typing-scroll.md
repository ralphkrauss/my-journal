# Scrolling while typing on iPhone and iPad

Owner report on TestFlight build 9 (iPhone 16 Pro, iOS 26): "when I am typing on iphone ios the scroll position is going
completely bananas … type some stuff and enter newlines." Build 10 has the same editor code.

## What happens today

Two mechanisms move the entry while someone types, and they disagree about where the visible area ends:

- `UITextView` follows the caret itself, with its usual animation, as in Notes. It treats the view's bounds minus its
  content insets as visible. The bottom of that area is the top of the keyboard's area, which is about 30 points below
  the top of the writing controls' capsule, so the caret line it reveals sits behind the controls.
- The editor's own reveal (SelectionReveal.swift) keeps the caret line 12 points above the capsule. After every edit it
  runs immediately, again 0.25 and 0.5 seconds later, and on every layout pass of the text view for 0.6 seconds; each
  time it sets the scroll position without animation and may enlarge the bottom content inset.

Measured on an iPhone 17 simulator (Release, software keyboard): every Return starts UIKit's animated scroll and, 4–10
ms later, the editor's reveal cancels it with a jump of 23 points further (the full line at the largest text size).
Every layout pass during the following 0.6 seconds, including each frame of any scroll animation, re-runs the check.
Text-size changes in the header, the keyboard's frame, image layout or the inset enlargement also re-enter it through
the header's own reveal, which uses UIKit's notion of the visible area again. The result is jumpy, non-native movement
that depends on frame timing; on a 120 Hz device the animation advances a few frames before being cancelled.

## Proposal

One definition of the visible area, used by UIKit and the editor alike:

1. While the writing controls show, the part of the entry they cover, plus 12 points of room, is the text view's bottom
   content inset (and its scroll indicator inset). It is measured from the capsule's real frame, so it follows the text
   size, the on-screen keyboard, a hardware keyboard (controls at the bottom of the screen), rotation and iPad layouts.
   - Formula: covered = the editor's bottom edge − (capsule top − 12), in screen coordinates; the inset is covered minus
     the safe area already in the adjusted inset (SwiftUI's keyboard avoidance has already shortened the editor to the
     top of the keyboard's area, so nothing is counted twice).
   - Controls beside the editor (iPad floating keyboard, another window in Stage Manager) or below it cover nothing.
     The inset never leaves less than 88 points of the editor to write in.
   - It is recalculated on the text view's layout passes (SwiftUI resizes the editor at the start of the keyboard's
     animation, with the capsule already at its final frame, so the inset is in place before the keyboard settles), on
     `keyboardDidChangeFrame`, and when the controls' accessory lays out (text size changes). It is written only when
     it differs by more than half a point. Typing never changes it.
   - When the controls go away, the inset returns to zero and the scroll position is clamped to the new end of the
     entry, so no blank space is left.
2. While typing, only `UITextView` follows the caret, exactly as Notes does: it scrolls only when the caret line would
   leave the visible area, with the system's animation. The editor no longer reveals the caret after each keystroke or
   on layout passes while typing. A keystroke ends any pending reveal from (4).
3. When the editor changes the text itself (Return in a list or quote, a Markdown shortcut, paste, undo), the text view
   doesn't follow; the editor reveals the caret once, with `scrollRectToVisible` against the same visible area, animated
   unless Reduce Motion is on.
4. The editor still reveals the caret after events UIKit doesn't follow: an inserted picture (its final size and the
   returning keyboard arrive later; checked for 2 seconds unless the person scrolls or types) and a rotation or window
   resize (0.6 seconds). These use `scrollRectToVisible` against the same visible area, so they agree with UIKit and
   never move the entry when the caret is already visible.
5. The header keeps its single reveal when its height, the width, the editor's height or the inset changes
   (unified-entry-scrolling.md): the title's caret while the title is focused, otherwise the body's. Title → body via
   Next is the body becoming first responder; UIKit reveals the caret against the inset already in place, since the
   keyboard and its controls stay up.
6. The Format panel replaces the keyboard with the controls still above it (menus-and-popovers.md D5), so the same inset
   applies. The unused sheet-era code (`revealSelection`, `restoreRevealedSelection`) is removed.
7. Short entries keep their room below the text through the inset in (1), which replaces the per-keystroke inset
   enlargement.

No layout, control or copy changes. Reduce Motion: UIKit's caret following is system behaviour; the editor's own
reveals are not animated. VoiceOver, Dynamic Type and keyboard navigation are unaffected; at the largest text size the
taller capsule gives a larger inset.

## Acceptance

- A UI test types many lines with Returns into a new entry at the default and largest text size, checks after each line
  that the entry never scrolls back up, and that the line being typed (read from the screen) is visible above the
  writing controls and, once the entry scrolls, no more than three lines above them; the same after Returns in the
  middle of the text. It checks settled positions.
- A hosted unit test (TypingScrollTests) types lines with Returns at the bottom of the real editor and records every
  scroll position: the entry never moves back, never moves more than about half a line between two frames (the text
  view's own animation moves a few points per frame; the old reveal jumped a whole line), and typing never changes
  the bottom inset. It fails with build 10's reveal and passes with this design.
- The picture-insertion check runs in the real editor with its real writing controls (ImageViewportTests), since the
  bare text view used before has no controls to measure.
- Screen recordings and per-keystroke scroll logs before and after, on a Release build.
- Existing checks still pass: caret visible after inserting a picture, largest text size, rotation (iPad template clip),
  title → body with Next, the Format sheet keeping the selection visible.

## Review

Independent review: [typing-scroll-review.md](typing-scroll-review.md). Approved with required changes, which are folded
into the proposal above.
