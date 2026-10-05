# Room below the line being typed on the Mac — 2026-10-04

Owner report (Mac, build 14):

> When you are typing and you are hitting the bottom of the screen, it automatically scrolls down, but your typing is always at the bottom. Compare this to Apple Notes, where there is a bit more space below your cursor, which makes it more comfortable to write.

## What happens today

The entry's text view (`NSTextView` in the `NSScrollView` NativeEditor makes) follows the caret itself: after each keystroke it calls `scrollRangeToVisible`, which scrolls only as far as the caret's line needs. Writing at the bottom of a long entry keeps the line being typed against the bottom edge of the editor.

Measured with the real editor at the default 16 pt, build 14:

- `TypingRoomTests` (a 600 × 420 pt window), twelve lines typed with Return at the end of a 40-paragraph entry: the bottom of the caret is **14 pt** above the editor's bottom edge after every line.
- A scratch copy of the app in its own window (1100 × 720 pt): **24 pt**.
- Typing in the middle of the text behaves the same once the line reaches the bottom.
- The editor's own edits for a key don't scroll at all on the Mac: a rule made by Return or a Markdown paste at the bottom of the window can leave the caret's line out of view (measured: 0 and 13 pt from the edge).

**Notes on macOS 26 was not measured.** The only Notes available is the owner's own iCloud library, open on the owner's screen, and measuring would mean creating and typing into a note there. The amount below is a proposal; the owner's side-by-side comparison with Notes is part of acceptance, and the amount is one named constant (`EntryScrollView.typingRoomLines`) so it is cheap to change.

## Proposal

1. **One rule, the platform's own mechanism.** The editor's scroll view gets a bottom content inset (`NSScrollView.contentInsets.bottom`), the room. AppKit treats the area under a content inset as outside the visible area, so the text view's own `scrollRangeToVisible` keeps the caret's line above it. This mirrors the iPhone design (typing-scroll.md): one definition of the visible area, and the text view follows the caret as it always does.
   - `automaticallyAdjustsContentInsets` is turned off, so AppKit can't replace the inset when it lays the scroll view out again (the find bar, the toolbar). The entry's title is above the scroll view on the Mac, so there is no inset of AppKit's own to keep (measured: the automatic insets are zero in the app's window).
2. **How much room: two lines of body text** at the current text size: the layout manager's default line height for the body font, times two. That is **36 pt** at the default 16 pt: in the app's window the caret's bottom ends 44 pt above the editor's edge instead of 24 pt (measured in the scratch copy). It follows View ▸ Zoom In and Zoom Out (larger text, more room). It is never more than a quarter of the editor's height, so in a short window the line being typed stays in the lower part of the editor.
3. **When it is recalculated**: when the text size changes, and when the scroll view is laid out again because the editor's size changed (window resize, a notice appearing above the entry). The inset is written only when it changes by more than half a point. When it shrinks at the end of an entry that is scrolled to its end, the scroll position is moved back so no stale empty space is left.
4. **At the end of the entry**: the room is also scrollable space after the last line, so the end of a long entry can sit above the bottom edge, as the line being typed does. Scrolling to the end shows that space below the last line. Short entries are almost unchanged: one whose text ends within the room of the bottom edge can scroll by those few points.
5. **In the middle of the text**: the same rule. A line typed (or a Return pressed) at the bottom of the window scrolls the text up line by line, keeping the room, with the rest of the entry visible below in that room. Text is drawn under the room as everywhere else; only the scroll position changes.
6. **Return, paste, undo**: the text view reveals the caret after its own typing and its own paste. The editor's own changes for a key don't reach that path on the Mac (Return in a list, checklist, quote or heading, a rule or code block made by Return, a Markdown shortcut, Delete at the start of an item, Down out of a code block, a paste of the journal's own content, a pasted, dropped or inserted picture, undo and redo of the editor's steps), so the editor reveals the caret once after each of them with the same `scrollRangeToVisible`, as iPhone does after its own edits (typing-scroll.md item 3). After a picture it reveals the caret again on the next turn of the run loop, once the picture is laid out, unless the caret moved or the entry scrolled in between; a picture inserted quietly, while the person is elsewhere, never scrolls. It does not after a checkbox click or a menu command applied to a selection, so those never scroll the page.
7. **What doesn't scroll**: clicking a line near the bottom places the caret without scrolling (as today); the first keystroke there then scrolls the line up into place, as the iPhone does. Scrolling with the trackpad or scroll bar is unchanged.
8. **The scroll bar** keeps the editor's full height: the scroller isn't shortened by the room (`scrollerInsets` balance the inset), because nothing covers that area.
9. **Reduce Motion**: no animation is added. The text view's own following of the caret is immediate on the Mac, with or without Reduce Motion.
10. **Other states**: read-only entries (Version History, conflicts, Recently Deleted) use the same editor and get the same scrollable space after the last line. Markdown source view is the same text view. Switching between Source and Preview keeps the caret's line where it was, using the room in its scroll limit (`ModeSwitchViewport`). Tables, pictures and the empty-entry placeholder are unaffected: their positions are in the text.
11. **Accessibility**: VoiceOver, Full Keyboard Access and Increase Contrast are unaffected; larger text (Zoom) gives more room. No copy changes.

## Acceptance

- `TypingRoomTests` (the real NativeEditor in a window): after each line typed with Return at the end of a long entry, at 16 pt and 30 pt, the caret's bottom is at least the room above the editor's bottom edge; the same in the middle of the text at the bottom of the window; after the checklist shortcut, Return in a checklist and after a heading, a rule made by Return, Down out of a code block, a long paste and undo; a shorter window leaves no empty space at the end.
- Find Next reveals matches through the same `scrollRangeToVisible` (NSTextFinder) and isn't tested separately.
- The real app (an Apple Development signed scratch copy): typing at the end of a long entry; the scroll bar reaching the bottom edge.
- **Owner check**: compare the room with Notes on the Mac and choose between two lines (proposed) and three.

## Review

An independent design review (2026-10-04, given the owner's report, the requirements and the first draft) returned **approve with required changes**:

1. *The editor's own edits don't reveal the caret on the Mac* (Return in lists, `convertLineOnReturn`, undo of snapshot steps). Added item 6; measured before the change: a rule made by Return left the caret 13 pt from the edge and a Markdown paste left it out of view.
2. *Turn off `automaticallyAdjustsContentInsets` explicitly.* Item 1.
3. *Say when the room is recalculated, and clamp when it shrinks.* Item 3, with a test.
4. *Mode switching computed its scroll limit without the inset.* Fixed in `ModeSwitchViewport`; no other Mac code derives a scroll limit from the visible rectangle.
5. *Fix references and claims, make the Notes comparison an owner check, one named constant, line height from the font.* Done; "as Notes does" removed from item 7.
6. *Extend the acceptance test* (middle, Zoom, checklist and heading Return, Return conversions, undo, paste, Find, the scroll bar). Done, except Find, which uses the same reveal (noted above); the scroll bar is checked in the real app.

Suggestion taken: two lines instead of three ("a bit more space"), offered to the owner as a choice. The reviewer's notes on drag selection autoscroll, Page Down and the first keystroke after clicking inside the room are checked in the real app where possible.

The reviewer also judged the checklist checkbox fix (native `NSButton`s placed on the clip view's bounds changes, a screen ahead each way, each item keeping its button) sound, on three conditions: don't place checkboxes in the middle of a text edit (done: placement waits for the layout that follows the edit); check VoiceOver with Accessibility Inspector; check that clicking a checkbox leaves focus in the text.

### Re-review

The same reviewer re-reviewed the revision: **approve with two required changes**, with all six earlier ones resolved and no further review needed once these were made:

- *R1. Down out of a code block doesn't reveal the caret on the Mac* (`performStructuralKey`). It does now, and the test covers it.
- *R2. A pasted, dropped or inserted picture doesn't reveal the caret.* It does now, unless the insertion is a quiet one (item 6).

Outcomes of the two checkbox conditions:

- *Focus*: a click on a checkbox now leaves the caret in the text in every case: the checkboxes refuse first responder (`refusesFirstResponder`), which otherwise they accept with Keyboard Navigation on. Format ▸ Mark as Checked / Mark as Unchecked stays the keyboard's way. `ChecklistScrollingTests` clicks a checkbox with real mouse events and checks the text keeps the focus and the caret.
- *VoiceOver*: not heard. The test checks each checkbox's label (its item's words) and state; the screen was locked during this work and this Mac's command line has no Accessibility permission, so neither VoiceOver nor Accessibility Inspector could be used. The checkboxes are the same `NSButton`s as in build 14, now kept on their items while scrolling instead of being given to other items, so what VoiceOver reads is unchanged.

### QA follow-up: the find bar (4 October 2026)

Edit ▸ Find (⌘F) showed the find bar over the entry's first line, and with the editor's own insets nothing could scroll that line into view, so a match in it stayed hidden under the bar (build 14 behaved the same). The editor's scroll view now gives the find bar its own room above the text while it shows, as TextEdit does, and the text returns to the top when it closes. `TypingRoomTests.testTheFindBarDoesntCoverTheFirstLine` covers it; the room below the line being typed is unchanged.

## Owner check (5 October 2026)

The owner tested build 15 on the Mac and found everything good, including the two lines of room below the line being
typed. The value stays at two lines.
