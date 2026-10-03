# Checklists: checkboxes, name and indentation — 2026-10-03

Owner request after build 12:

> “The task list is ugly on iOS. It's taking over the weird circles from Notes and I hate them. I want the more conventional checkmarks. In the styling list it should also be called checklist instead of task list. Also the indentation doesn't seem correct (I'm not sure, just double-check it). Use a more conventional Markdown-rendered task list with checkboxes (still using the native Apple look and feel).”

Amends the paragraph style names of [feedback-stabilization-2026-09-23.md](feedback-stabilization-2026-09-23.md) and [owner-decisions-2026-09-25.md](owner-decisions-2026-09-25.md) (Format menu: “Task List ⇧⌘L”), and the “Mark as Complete / Mark as Incomplete” copy approved in [notes-alignment-revision-review.md](notes-alignment-revision-review.md). Storage doesn't change: items are still saved as GitHub task list Markdown, `- [ ] ` and `- [x] `.

## 1. What exists today (measured)

Measured with the real editor (`NativeEditor` in a 402 pt wide window, the iPhone 17 width) on the iOS 26.5 simulator and on the Mac, with a document holding a bulleted, numbered and task item that each wrap, a checked task, and a nested bullet and nested task. Positions are from the text view's leading edge; the text container has 5 pt of padding.

| | Marker or box | Text, first line | Wrapped lines |
| --- | --- | --- | --- |
| iPhone, 17 pt: bullet and numbered | 5 | 27 | 27 |
| iPhone, 17 pt: task | circle image 14–39.7 (25.7 pt), button 5–49 | **49** | 49 |
| iPhone, 17 pt: nested bullet | 22 | 44 | 44 |
| iPhone, 17 pt: nested task | circle 31–56.7 | 66 | 66 |
| iPhone, 53 pt (largest text): bullet | 5 | 27 | 27 |
| iPhone, 53 pt: task | circle still 25.7 pt, 14–39.7 | 49 | 49 |
| Mac, 17 pt: every list, task included | 5 (16 pt checkbox in a 22 pt frame) | 27 | 27 |
| Mac, 17 pt: nested items | 22 | 44 | 44 |

Code: `RichText.attributes(kind:size:)` (list indent 22 pt, iPhone tasks 44 pt, fixed), `RichText.blockAttributes` (nesting: 0.5 em per character of the Markdown prefix, so one level written with two spaces is 17 pt), `InlineTasks.synchronize` (a 44 × 44 pt `UIButton` with `circle` / `checkmark.circle.fill` at its default size on iOS; an `NSButton` checkbox on the Mac).

What's wrong:

1. **The circles.** iOS draws Notes' circles; the Mac already draws a native checkbox. The two platforms disagree, and the owner wants checkboxes.
2. **Checklist text doesn't line up with other lists on iPhone.** It starts at 49 pt, bullets and numbers at 27 pt, so a checklist under a bulleted list is indented 22 pt further for no reason.
3. **Nesting doesn't line up with the parent.** A nested item moves 17 pt (0.5 em per space of Markdown) while the parent's text starts 22 pt in (44 pt for iPhone tasks). A nested bullet sits 5 pt left of its parent's text; a nested task's circle sits 18 pt left of its parent's text, partly under the parent's circle column. Both platforms.
4. **Nothing scales with the text size.** The 22 and 44 pt columns are fixed: at the largest Dynamic Type size (53 pt) the bullet column is narrower than the text's own line height, and the iOS circle stays 25.7 pt beside 53 pt text. On the Mac, Zoom In (up to 30 pt) has the same problem with the 16 pt checkbox.
5. **The name.** “Task List” in the Format panel and the Mac Format menu; the item's VoiceOver labels say “Mark as Complete”, the Mac menu “Mark as Checked”.

## 2. Proposal

### 2.1 The checkbox

- **iPhone and iPad:** a rounded square, drawn with SF Symbols: `square` when unchecked, `checkmark.square.fill` when checked (a filled square with the checkmark cut out). This is the familiar checkbox of Markdown previews and of the Mac's own checkbox, in the system's symbol style.
  - Size: the symbol is configured with the item's paragraph font at the item's size (`UIImage.SymbolConfiguration(font:)`, scale medium; not the first word's font, which may be bold or code), so it is about as tall as the text's capital letters plus a little, and grows and shrinks with Dynamic Type and with Zoom In / Zoom Out.
  - Colour: unchecked is an outline in the secondary label colour (clear, but not as heavy as the text); checked is a square filled with the app's accent colour (the tint) and a white checkmark, as the Mac's checkbox draws it, in light and dark appearance alike (palette rendering, not the cut-out checkmark, which would show dark in dark appearance). Both adapt to Increase Contrast. The Mac's checkbox follows the system accent colour and iOS the app's tint; that difference is the platforms' own and intended. No animation other than the symbol swap; nothing moves.
- **Vertical position, both platforms:** optically centred on the first line's capital letters, so the box sits with the words as a bullet does, not at the top or bottom of the line's spacing. On iOS the symbol sits on the text's baseline by its own baseline (SF Symbols are drawn to sit on the baseline of text of the same font); the Mac's checkbox has no title and so no text baseline, and is centred on the cap height (the baseline minus half the cap height). For a wrapped item the box stays with the first line.
- **Mac:** stays the native `NSButton` checkbox (it already is the conventional checkbox). Its control size follows the text: small below 14 pt, regular up to 20 pt, large above. The large control is the native limit, so after Zoom In to 30 pt the box is smaller than the text; that is accepted rather than drawing a custom checkbox.

### 2.2 Checked items

Checked text stays exactly as it was: no dimming, no strikethrough.

- This is how Markdown is rendered conventionally (GitHub, the Mac editor today) and how Notes shows checked items.
- A journal keeps what was written; a checked line is still part of the entry and should stay as readable as the rest. Dimming would lower its contrast.
- Strikethrough is a real format here (Format ▸ Strikethrough, saved as `~~`). Drawing checked items struck through would make it impossible to tell which lines are struck through on purpose, and copied or exported text wouldn't match what's shown.

The filled accent checkbox is enough to show the state at a glance.

### 2.3 Indentation (all lists, both platforms)

One list column, derived from the text size, for bulleted, numbered and checklist items alike:

- **Column width:** 1.5 em of the item's font, rounded to whole points (26 pt at the iPhone's default 17 pt, 24 pt at the Mac's default 16 pt, 80 pt at the largest Dynamic Type size). The marker — bullet, number or checkbox — sits at the start of the column; the text starts at its end.
- **Wrapped lines** start exactly where the first line's text starts (hanging indent), never under the marker or the box.
- **Nested items** move in by one column per level, so a nested item's bullet, number or checkbox lines up exactly with its parent's text. The level is the number of list levels the item is in (the block's `listIndents.count`, which reading Markdown, Increase Indent and Return already keep), not the length of its Markdown prefix: how many spaces the Markdown uses for a level (two for `- `, three for `1. `, sometimes six under `- [ ] `) no longer changes how far it moves. The rest of the prefix, such as a block quote's `> `, keeps its current 0.5 em per character, so the indent is *quote part + level × column*, for a list inside a quote and a quote inside a list alike.
- **A limit for deep nesting.** The nesting part stops growing at 160 pt: deeper levels stay where the last level that fits is, still with their own hanging indent. At the default size that is six levels (nobody runs into it); at the largest Dynamic Type size, two (the text of a third-level item then starts at 240 pt and keeps 150 pt of an iPhone 17's line, instead of being pushed off it).
- Numbers wider than the column (100. and up at the default size) push only that line's text; its wrapped lines and its nested items keep the column. This is an accepted exception, as today.
- Bulleted and numbered text moves from 22 to 26 pt at the default iPhone size and from 22 to 24 pt on the Mac: a few points, so a checkbox fits the same column as a bullet and every list lines up.

Sketch, iPhone at 17 pt (positions from the text's leading edge):

```
•   Pick up the bread                        0 bullet, text at 26
☐   Call the plumber about the kitchen       0 box, text at 26
    sink before Friday                       wrapped line at 26
    ☑   Ask about the boiler too             nested: box at 26, text at 52
1.  Morning pages                            0 number, text at 26
```

### 2.4 Hit target

- iPhone and iPad: the checkbox's touch area is 44 pt tall, centred on the box, and reaches horizontally from the start of its column (for a nested item, into the parent's column, up to 44 pt wide) to the start of the item's text. It never covers the text, so tapping the first word still places the caret there. Consecutive items are about 33 pt apart at the default size, so where two areas would overlap they are split halfway between the boxes: a tap always toggles the nearer item, never the wrong one. At the default size the area is about 31 pt wide at the top level (the text view has no inset at its leading edge for it to reach into; accepted, since the box itself is the target people aim for) and 44 pt when nested; it grows with the text size. On iPad with a pointer, the area highlights as a button does.
- Mac: the checkbox's own control area: the box plus the rest of its column, up to the text.
- Tapping toggles the item, as one undo step, as today.
- A read-only entry (Version History, conflicts, Recently Deleted) shows the checkboxes as disabled controls, in each platform's own disabled appearance (the Mac's dimmed checkbox; on iOS the accent colour turns grey), and they don't respond.
- Right-to-left paragraphs are out of scope, as for bullets today.

### 2.5 VoiceOver and keyboard

- iOS: each checkbox is a button whose label is the item's text (“Review the day”, or “Empty checklist item” for an item with no text) and whose value is “Checked” or “Unchecked”. VoiceOver reads “Review the day, Unchecked, button”; a double tap toggles it and VoiceOver reads the new value. In a read-only entry it's also marked not enabled (“dimmed”).
- Mac: the native checkbox, labelled with the item's text: “Review the day, unchecked, checkbox”.
- The checkboxes are buttons over the text view, which on iOS is one VoiceOver element. They are now listed after the entry's text (and its tables) in the writing view's VoiceOver order; before this change they weren't listed there at all. As before, only checkboxes on screen exist, so VoiceOver reaches those of the part of the entry that is shown (found during the image actions review, image-actions-ios-2026-10-03.md).
- The keyboard route is unchanged: Format ▸ Mark as Checked / Mark as Unchecked (⇧⌘U) on the Mac and on iPad with a keyboard.

### 2.6 The name: Checklist

User-facing “Task List” becomes **Checklist**, Notes' name for it:

- Format panel (iPhone sheet, iPad and Mac popover): the row **Checklist**, with the `checklist` symbol as today.
- Mac Format menu (also shown in iPad's keyboard shortcut list): **Checklist ⇧⌘L** (Notes uses ⇧⌘L for Checklist too).
- Format panel row on a checklist item: **Mark as Checked** / **Mark as Unchecked** (was Mark as Complete / Mark as Incomplete), the same words as the Mac Format menu and the checkbox's value. For a selection of several items it says Mark as Checked unless every one is checked (the approved rule, unchanged).
- The Checklist row shows its checkmark on checked items too (today only unchecked ones count as the style).
- VoiceOver announcement after typing `[ ] ` or `[x] `: “Checklist” (was “Task list”).
- README feature list: “checklists” (the protocol and the README's format paragraph keep “task lists”, the Markdown term).

Typing `- [ ] `, `[ ] `, `[] ` or `[x] ` still makes a checklist item, and source view still shows the Markdown.

### 2.7 States

There are no loading, empty, offline or error states specific to checklists. An empty checklist item shows its checkbox with the caret beside it. Return on an item with text starts a new unchecked item; Return on an empty item ends the list (or moves it out a level); Backspace at the start of an item's text removes its checkbox and keeps the text (pre-release-ui-2026-09-27.md §4). Copy and paste keep `- [ ]` / `- [x]`. None of this changes.

## 3. Verification plan

- A geometry test (iOS and Mac test targets, the real editor, like `TypingScrollTests`): at the default size and the largest size, bulleted, numbered and checklist text start at the same x; wrapped lines start at their first line's text; a nested item's marker or box starts at its parent's text; a four-level list at the largest size keeps its text on the line; the checkbox (both platforms) is centred on the first line's capital letters and at least as tall as the cap height; on iOS its touch area is clear of the text and no two touch areas intersect.
- Existing tests that find “Task List” or “Mark as Complete” by name are updated, identifiers included; a UI test checks the checkbox's label and value before and after a tap. Existing editor tests for Return, Backspace, toggling, Markdown round trip and copy and paste keep passing.
- Screenshots on the iPhone 17 simulator, light and dark, default and largest text, with nested and wrapped items, checked and unchecked; the Mac at the default size and after Zoom In.

## 4. Review

An independent design review (2026-10-03, given the owner's request, the requirements and this proposal) approved it **with required changes**, all made above:

1. Neighbouring touch areas overlapped (items are 33 pt apart, areas 44 pt tall; the old code had the same flaw): they are now split halfway between boxes, and the test checks that none intersect.
2. Read-only checkboxes were to stay undimmed, which contradicts the Mac's native disabled checkbox and the owner decision that read-only entries show controls disabled: they now use each platform's disabled appearance.
3. Nesting had no limit at large sizes: the nesting part stops at 160 pt, with a four-level test at the largest size.
4. The nesting level was underspecified: it is `listIndents.count`; the formula is quote part + level × column; wide numbers are an accepted exception.
5. The vertical rule was iOS-only: both platforms now centre the box on the capital letters (iOS through the symbol's own baseline), and the Mac is in the geometry test.

Minor findings taken: the checked box uses a white checkmark in both appearances, like the Mac's; the symbol is sized by the paragraph font, not the first run's; the Mac uses the small control at Zoom Out; the narrow top-level touch width, the Mac's large-control limit and right-to-left text are recorded as accepted; the iPad pointer highlight; the UI test checks label and value; test identifiers are renamed with the copy. Not taken: the iOS 17 `.toggleButton` trait (the deployment target is iOS 16, and “button” with a Checked/Unchecked value already reads clearly). Noted for later, not changed here: VoiceOver reading the hidden ☐/☑ marker characters when it reads a whole line of text; this predates the change and is unaffected by it.

The reviewer asked for a re-review only if read-only differed from native disabled controls; it doesn't.

## 5. Implementation check (2026-10-03)

- Measured after the change with the geometry test (`ChecklistGeometryTests`, iOS and Mac): bulleted, numbered and checklist text start together (26 pt at 17 pt on iPhone, 24 pt at 16 pt on the Mac), wrapped lines line up with their text, nested markers and boxes start at their parent's text, four levels at the largest size stop at 160 pt. Two details settled by measurement: the touch area is 44 pt tall or 1.3 em at large sizes, where the box itself is taller than 44 pt; and the symbol, placed on the baseline, sits within a tenth of an em of the cap-height centre.
- The box's font is the paragraph font at the item's size: the hidden ☐ marker is drawn in a fallback font whose cap height differs.
- Screenshots: iPhone 17 simulator, light and dark, default and largest text, nested, wrapped, checked and unchecked, tapping a box; the Mac journal window at 16 pt and 26 pt, light and dark (captured from the app's own window in the Mac test host; the checkboxes show in their inactive-window style there).
