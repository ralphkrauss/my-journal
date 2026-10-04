# Editor fixes after build 14 — 2026-10-04

Bug fixes for three owner reports. None changes the intended design: each restores what list-markers-2026-10-03.md, checklists-2026-10-03.md and owner-decisions-2026-09-25.md (Markdown as you type) describe. The fourth report, the room below the line being typed on the Mac, is a design change: mac-typing-room-2026-10-04.md.

## 1. A new list item jumped when its first letter was typed (iPhone, and the Mac)

> When I press Enter in an existing checklist, the new checkbox appears, and then when I start typing it jumps up. […] I tested the other lists and they have the same problem.

**Cause.** Since build 14 a list item holds only its text (list-markers-2026-10-03.md), so a new, empty item's only character is its line break. TextKit 1 lays a line break's glyph out below the line's baseline: `location(forGlyphAt:)` returns the line's height plus its line spacing rather than its ascent. The checkbox (`InlineTasks.placement`), the drawn bullet or number (`ListMarkers.marker`) and, on iPhone and iPad, the caret (`JournalTextView.caretRect`) were placed on that position. The first letter gives the line a real glyph, and they all moved up to the real baseline.

Measured with the real editor, before the fix:

| | iPhone 17 pt | iPhone 53 pt | Mac 16 pt | Mac 30 pt |
| --- | --- | --- | --- | --- |
| Checkbox, bullet, number | 7.1 pt | 15.8 pt | 6 pt | 9 pt |
| Caret | 7.1 pt | 15.8 pt | none (AppKit draws its own) | none |

The line itself, its height and the scroll position didn't move. It affected every list kind, in the middle and at the end of an entry, quotes (caret only) and empty plain lines between paragraphs (caret only). A UI test on the iPhone 17 simulator measured the checkbox button moving up as "E" was typed, and a screen recording shows the jump (evidence below).

**Fix.** One function, `ListMarkers.baseline(ofCharacter:glyph:layout:)`, gives a line's baseline: the glyph's own position for text, and for a line whose first character is a line break (or a soft line break), where text in the line break's font sits: its ascent (on the Mac the layout manager's default baseline offset for the font), plus the space a paragraph after a code block leaves above it. The checkbox, the drawn marker and the iOS caret use it.

**Test.** `ListTypingStabilityTests` (iOS and Mac): for checklist, bulleted, numbered and quote items, after Return in the middle and at the end of a list, an empty line between paragraphs, and an emptied item after a code block, at the default and the largest size: the line, the caret, the marker and the checkbox stay where they are when the first character is typed, and the marker sits on that character's baseline. `ListWritingUITests.testANewChecklistItemsCheckboxStaysPutAsItsFirstLetterIsTyped` checks the same on the simulator's software keyboard.

## 2. “- ” didn't start a bulleted list on iPhone

> If I start a new list by using '-' symbols it doesn't automatically get recognized and transformed into the bulleted list, while this functionality does work on the Mac.

**Cause.** Not the hyphen: iOS Smart Punctuation leaves "- " alone (the keyboard sent "-" and then " ", each through `textView(_:shouldChangeTextIn:replacementText:)`, measured with a log on the simulator). The editor scheduled the conversion for the next turn of the run loop as soon as the space was *allowed*. The software keyboard puts the character in, and moves the caret, later, so the conversion often found the caret still before the space and did nothing. Typing quickly had the opposite race: the next letter could arrive before the conversion ran, which then also gave up. Measured on the simulator: the hyphen and space tapped on the keyboard stayed as typed every time; “1. ”, “[] ”, “- ” and “# ” typed with `typeText` failed in some runs and not others. The Mac's text view inserts at once, so it rarely lost the race.

**First fix, replaced.** The first build-15 fix waited until the space was in the text and converted on the next turn of the run loop, adjusting for letters typed in between. That still left the conversion for later: keys the keyboard already had on their way were typed where it had asked to type them, so a fast burst (“- Milk⏎Eggs”) could leave the marker as typed or put letters in the item above (“Milks” and “Egg”), found by another agent's UI test.

**Fix.** The conversion happens within the space's own change. When the space completes a shortcut at the start of a plain line, `textView(_:shouldChangeTextIn:)` types the space itself, converts the line, and returns false, so the text view doesn't type it. These are two undo steps, as before, so ⌘Z first gives back exactly what was typed and Backspace straight after the conversion restores it. Nothing is left for a later turn, so there is no later moment at which the keyboard's next key and the conversion can cross: the next key is asked about, and typed, after the conversion, where the caret then is. The earlier “space arrives late” problem can't come back either, because the editor no longer waits for the keyboard to insert the space: it inserts it. A space typed while an input method is composing, or that completes no shortcut, is left to the text view as before. Return in a list item and joining lines already worked this way. The Mac shares the code and had the same race in the model below (a turn of the run loop after Return left “- ” as typed); it converts the same way now.

The setting that turns shortcuts off, Settings ▸ Writing ▸ Format Markdown as You Type on iPhone and iPad (General ▸ Format Markdown as you type on the Mac), is the same on both and is still respected. Every shortcut the Mac supports works the same way: “- ”, “* ”, “+ ”, “1. ” (or “1) ”), “[] ”, “[ ] ”, “[x] ”, “> ”, “# ” to “###### ”, and “---” or “```” followed by Return.

**Tests.**

- `MarkdownShortcutTests.testABurstOfKeystrokesKeepsEachLetterInItsItem` (iOS and Mac) types “- Milk⏎Eggs” with the run loop turning at every point, at none, and at each single point: between keys, and on iOS between the keyboard asking about a key and typing it where it asked. Each item must be a bulleted item with exactly “Milk” and “Eggs”. With the replaced fix, 13 of the 24 iOS timings failed (the marker left as typed); all pass now.
- `MarkdownShortcutTests.testUndoAfterAShortcutGivesBackWhatWasTyped`: ⌘Z after a shortcut gives back “- ”. The existing test of Backspace after a conversion still passes.
- `ListWritingUITests`: the shortcuts “- ” (one hyphen and space bar tapped key by key), “* ”, “1. ”, “[] ”, “> ” and “# ”, and a list typed in one `typeText` burst, “- Milk⏎Eggs⏎Bread”. Both check the entry's exact Markdown in View Source. A simulator that has seen a hardware keyboard keeps the software keyboard off screen; the test then types the hyphen and space as hardware key presses, which reach the text view the same way.

## 3. Mac checkboxes flickered or disappeared while scrolling

> Checkboxes are glitched. When you scroll them in and out of the viewbox they are flickering or disappearing.

**Cause (build 14).** Checkboxes are native `NSButton`s in the text view, made only for the items on screen (checklists-2026-10-03.md), and placed when the text view laid itself out. Scrolling doesn't lay the text view out, so items scrolled into view had no checkbox until something else did, and the buttons were handed from item to item in screen order whenever they were placed. Measured in a scratch copy of the app (a 120-item checklist, 60 scroll-wheel steps): 890 items in view without a checkbox in total; at the 40th step none of the 19 items in view had one.

**Fix.** The checkboxes are placed again as the scroll view's clip view moves (its bounds-change notification, before the frame is drawn), for the items within a screen above and below the visible area, so items scrolling in already have theirs. An item keeps its button while it stays in that area, and only what changed is set on a button. Placement waits for the layout that follows an edit when the scroll happens in the middle of one. The checkboxes stay native controls rather than drawn ones: VoiceOver, the accent colour, the disabled look and click tracking come with them (the reviewer of mac-typing-room-2026-10-04.md agreed). A click on one no longer takes the focus from the text with Keyboard Navigation on (`refusesFirstResponder`). After the fix the same 60 steps show every checkbox.

iPhone and iPad already place checkboxes on each layout pass, which UIKit runs for every frame of scrolling; the same test passes there.

**Tests.** `ChecklistScrollingTests`: at every scroll position through a 120-item checklist, with no layout or run loop turn in between, every item in view has its checkbox in place (iOS and Mac); on the Mac, checkboxes are labelled and a real click toggles the item while the text keeps the focus and the caret.

## Evidence

Under the session's scratchpad (`b15-editor/`), not in the repository: `ios-before.mp4` and `ios-after.mp4` (simulator recordings of the checklist test), `ios-new-item-frames.png` (frames from both), `frames-before/` and `frames-after/` (Mac scratch app: new item, scrolling, typing at the end, `log.txt`), `typing-end-compare.png`.
