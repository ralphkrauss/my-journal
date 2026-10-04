# List markers drawn, not stored — 2026-10-03

Owner report after build 12:

> When you start a new checklist item on iPhone, the keyboard doesn't capitalize the first letter as it does in Notes. […] Follow the best practices when implementing text editors like this, and let Apple decide how to handle it.

The owner explicitly does not want a capitalization workaround (toggling `autocapitalizationType`, forcing Shift). The text the keyboard, dictation, predictions, Writing Tools and VoiceOver read must hold only what the person wrote, and the system then behaves as it does everywhere else.

Storage doesn't change: entries are still Markdown, `- `, `1. `, `- [ ] `, `- [x] `, `> `. Only the editor's in-memory text changes. No copy changes.

## 1. Findings

### 1.1 Why the keyboard doesn't capitalize

Every list, checklist and quote line starts with hidden characters in the text storage (`RichText.marker(for:)`): `"•\t"`, `"1.\t"`, `"☐\t"`, `"☑\t"`, `"❯\t"`, drawn clear or at 0.1 pt and tagged `.journalMarker`. `HiddenMarkers` keeps the caret after them. On a new checklist item the keyboard reads `"…Buy milk\n☐\t"` before the caret: not the start of a sentence, so `.sentences` auto-capitalization doesn't apply. Bullets (`•\t`) and quotes (`❯\t`) behave the same; numbered items (`"2.\t"`) capitalize only because of the period. Predictions and dictation see the same context, VoiceOver reads "ballot box", "bullet", "2 period", Find matches "•", and the plain text copied to other apps contains a clear `☐`.

### 1.2 The editor is TextKit 1, everywhere, by construction

- iOS: `JournalWritingView.init` reads `editor.layoutManager` (to turn off non-contiguous layout). That access is what logs “UITextView is switching to TextKit 1 compatibility mode because its layoutManager was accessed”: the text view is created with TextKit 2, then rebuilt as TextKit 1 before it's shown. The Mac's `JournalTextView(frame:)` does the same on first `layoutManager` access (`drawBackground`, checkboxes, tables).
- The switch is not an accident to undo: the whole editor is written against `NSLayoutManager`: quote bars, rules and code backgrounds (`BlockDecorations`), checkbox placement (`InlineTasks`), table grids over their attachments (`InlineTables`), picture anchoring (`ImagePresentation`), the caret height fix (`JournalTextView.caretRect`), the placeholder (`EditorPlaceholder`, deliberately TextKit 1), mode-switch viewport, the Mac picture highlight (`NSTextAttachmentCell`, TextKit 1 only), and the tests that measure layout. An earlier review already records “the app uses TextKit 1 throughout” (image-block-spacing-review.md).

### 1.3 What `NSTextList` does in each TextKit (measured on macOS 26.5, SDK headers for iOS 26.5)

Scratch experiments (an `NSTextView` with `usingTextLayoutManager: false` and `true`, the same content-only list paragraphs, `scratchpad/list-markers/exp/`):

| | TextKit 1 | TextKit 2 |
| --- | --- | --- |
| Draws markers for `NSParagraphStyle.textLists` with no marker text | **No** (no bullets or numbers drawn) | Yes, with its own geometry (text at ≈ 41 pt, not our 24/26 pt column) |
| Text storage, `NSTextInputClient` text, `accessibilityValue` | Content only | Content only |
| Accessibility list attributes (`accessibilityAttributedString`) | None | None |
| Return at the end of the last item | Inserts one `"\n"` | Inserts `"\n\n"` and puts the caret between them: **the new empty item gets a line break of its own** |

Apple's headers state the contract directly: *“NSAttributedString uses two representations for the text list. With TextKit2, the paragraph representing a text list item only contains the content. […] TextKit1 requires the entire resolved text list content including the marker format string.”* (UIKit/AppKit `NSAttributedString.h`; `NSTextList.includesTextListMarkers`, new in iOS 26/macOS 26, is NO by default.)

So:

- **In TextKit 1 the platform convention is the one this editor follows today**: marker strings in the text (TextEdit's `"\t•\t"`). TextKit 1 never draws `NSTextList` markers, and putting `textLists` on marker-less paragraphs is outside its documented contract.
- **“Let Apple decide” is TextKit 2's model**: content-only paragraphs, list structure in paragraph attributes, markers drawn by the layout. Bullets and numbers would be Apple's; checkboxes and quote bars are not `NSTextList` features in either TextKit and stay ours.

The RTF writer (macOS 26) turns either representation into a real RTF list (`{\listtext •}`), and reading RTF now returns content-only lists by default (`PastedRichText` already reads both).

Other facts that shape the design:

- Unchecked items' first lines are 1–3.4 pt taller than every other line at 16, 30 and 53 pt: the hidden `☐` falls back to Apple Symbols, whose descent is larger (`☑`, `•` and digits stay in SF). Toggling a checkbox moves everything below it today.
- Quote text's first line starts 0.5 pt right of its wrapped lines (the hidden `❯` tabs to `quoteIndent + 0.5`).
- AppKit takes typing attributes at the start of a paragraph from that paragraph's first character, and at the end of the text from the last character. iOS drops the block kind from typing attributes (feedback-stabilization-2026-09-23.md); `InsertedText.adopt` restores it from the other characters of the paragraph.

## 2. Options

**A. Move the body editor to TextKit 2** and give bullets and numbers `NSTextList`s. This is Apple's model end to end, but it replaces the editor's layout layer (every item in 1.2), re-derives the checklist geometry through TextKit 2's own list layout (which places text differently), reopens the long-entry scrolling and typing-scroll work TextKit 2 is known to make harder, and spans iOS 16–26 and macOS 14–26 behaviour (lists changed in 26). Weeks of work and the highest regression risk in the app, for bullets and numbers only.

**B. Stay on TextKit 1, with content-only paragraphs** (recommended): list structure in the paragraph's attributes, bullets and numbers drawn by the editor's layout manager, checkboxes stay native controls. This is how Notes, the app the owner compares with, is generally described to store lists and checklists (paragraph attributes, markers drawn by the app), and it is the representation TextKit 2 uses. The keyboard, dictation, predictions, Writing Tools and VoiceOver see only the person's text. Geometry is kept by construction. A later move to TextKit 2 would start from the same representation, though it would still be a large change of its own.

**C. Keep markers, fix capitalization** — excluded by the owner.

Also considered and rejected: holding an empty last item only in typing attributes (it disappears when the entry is shown again, iOS drops the block kind on typing, and deleting the last item's text would leave the previous item's identity and number on the line); a zero-width character for empty items (the keyboard would read it before the caret, which is the bug).

## 3. Design (option B, revised after review)

### 3.1 Representation

- **No characters for list, checklist or quote markers.** A list item's or quote's paragraph holds its text and its line break; nothing else. `.journalMarker` stays only on a rule's `—` (a rule has no text; its character is the rule itself, as U+FFFC is a picture; unchanged).
- **Paragraph attributes carry the structure**, on every character of the paragraph including its line break: `.journalKind`, `.journalBlockID`, `.journalBlockMetadata` and the paragraph style, as today, plus `.journalListNumber` (an Int) on numbered items: the number drawn, fixed when the item is rendered or created, as the `"3.\t"` characters are today. Bullets are drawn from `.journalKind` alone, so there is one source of truth.
- **Indents**: list paragraphs get `firstLineHeadIndent = headIndent = nesting + listColumn(size)` (today: first line at `nesting`, a tab to the column), so checklist, bullet and numbered text and wrapped lines stay exactly where `ChecklistGeometryTests` and checklists-2026-10-03.md put them. A number wider than the column (`100.` and up at the default size) moves only that item's first line in, to the number's width plus a space. Today the tab overflows and the item's text wraps onto a line of its own below the number (measured, TextKit 1, 16 and 17 pt). Numbers up to `99.` are where they are today. *Superseded for numbered lists by section 12: each numbered list's column fits its widest number and a space.* Quotes get `firstLineHeadIndent = headIndent = quoteIndent + nesting`.
- **No `NSTextList` in the editor's text.** TextKit 1 neither draws nor supports marker-less `textLists`, and TextKit 1 `NSTextView` edits marker strings in list paragraphs itself. `NSTextList` is used where it's the contract: text handed to other apps (3.6) and reading pasted text (unchanged).
- **Every list item and quote has its own line break.** Mid-text, that is the line break before the next paragraph. When the text's last paragraph is a list item or quote, the text ends with a line break tagged `.journalOwnEnd`: “this line break ends the last paragraph; no empty paragraph follows it”. TextKit 2's `NSTextView` gives a new last item a line break of its own in the same way (1.3); the tag makes it unambiguous, because “…Eggs⏎” already means “Eggs, then an empty paragraph”, which is how leaving a list at the end works today.
  - Reading (`RichText.document`, `textDocument`): a final line break tagged `.journalOwnEnd` doesn't start an empty block. Rendering a document whose last block is a list item or quote ends it with that line break. `[…, Eggs]`, `[…, Eggs, empty paragraph]` and `[…, empty item]` each render and read back unchanged.
  - Layout: the layout manager gives no extra line fragment after an own end (3.2), so the text is exactly as tall as today and `continuesAtEnd` still measures the real text.
  - The caret can't be after an own end: a caret there (a tap or click below the text, `continueAtEnd`, ⌘↓, → at the end) moves to just before it, so writing continues in the last item, as today. A selection may include it (Select All).
  - The tag lives only on the text's last character. Editor-made edits that end the text (the helper in 3.3) re-establish the rule as a post-condition inside their undo step: if the last paragraph is a list item or quote, the text ends with an own end carrying that paragraph's attributes; otherwise it has none.
  - Selections end before an own end unless they cover the whole text (Select All), so native typing, composition and deletion over a selection can only remove it together with all the text; a native deletion of the own end alone (forward delete at the end of the last item) does nothing. Drops on the Mac land before it. A drop UIKit places at the very end on iOS can still land after it; the tag then sits mid-text, where it means nothing, until the editor's next own edit removes it (accepted).
  - Insertions “at the end” by the editor (a picture, a template, a paste, a drop) go before the own end, and the post-condition then gives the own end to the new last paragraph, or removes it.
  - It is never part of typing attributes.

### 3.2 Drawing

- Bullets and numbers are drawn by a small `NSLayoutManager` subclass (`ListLayoutManager`), after `super` in `drawGlyphs(forGlyphRange:at:)`, for every paragraph whose first glyph is in the range drawn: `"•"` or `"n."`, left-aligned at `lineFragmentPadding + headIndent − listColumn(size)` (the column start, where the marker glyph is today), on the first line's baseline, in the paragraph font at the item's size (`RichText.font(size:)`, never the first word's bold or code font) and the label colour: the font and colour of today's marker characters. They are drawn with the text, so they sit above the Mac's selection highlight as today's glyphs do, follow the layout manager's own invalidation (no stale markers), Dynamic Type, Zoom, Bold Text, Increase Contrast and dark mode.
- The same subclass returns an empty extra line fragment when the text ends with an own end (3.1).
- Both body text views get this layout manager in `JournalTextView`'s own initializer, so the app, the test harness and every test that makes a `JournalTextView` get the same text system. iOS: `init(frame:textContainer:)` without a container builds the TextKit 1 objects itself. Mac: the text view keeps its own text system and replaces its layout manager with this one as it is made (`replaceLayoutManager`), so AppKit still owns the text network as before. This also makes TextKit 1 explicit from the start (3.5).
- Checkboxes: unchanged native controls. `InlineTasks.placement` takes the box's x from the same function the layout manager draws with, and the baseline from the paragraph's first glyph (for an empty item, its line break), instead of from the `☐` glyph. Labels are the line's text (no `dropFirst(2)`).
- Quote bars, rules and code backgrounds: unchanged.
- Right-to-left paragraphs stay out of scope, as for quote bars and checkboxes today: markers are drawn at the leading edge of a left-to-right layout.

### 3.3 Editing behaviour (unchanged for the person unless noted)

| Action | Today | New implementation |
| --- | --- | --- |
| Caret placement, arrows, Home, ⌘← | `HiddenMarkers.caret` steps over markers | Removed for lists and quotes; the caret can sit at an item's start like any line. Kept for rules. Clamp before an own end. |
| Typing attributes | Strip `.journalMarker`, fix invisible styles | Strip `.journalOwnEnd`. At a paragraph start, iOS takes them from the paragraph's own first character, as AppKit already does. On the empty final line after an untagged line break (the line after a list), typing is a plain paragraph on both platforms: today AppKit takes the list item's attributes there. |
| Return in a non-empty item | Intercepted: inserts `"\n" + marker` with `replace` | Intercepted, as today, as one snapshot undo step: the line break, then the rest of the line and its line break as the next item (new identity, next number, `checked` → `task`). At the end of the text the own end stays last, so the new empty item owns it. Return at the very start of an item's text inserts the new empty item above it instead, so the item keeps its identity and checked state (today it unchecked it). |
| Other text with line breaks inserted into an item or quote by the system (dictation, a drop, Writing Tools, `insertText("a\nb")`) | Bullets and numbers became plain paragraphs (marker gone); tasks and quotes kept their kind with a duplicate identity | The text system inserts it, keeping its links and formatting; as the inserted characters are adopted, each new line's characters become the next item of the list (fresh identity, next number, unchecked), or another quote paragraph. Only inserted characters change, so the system's own undo takes it back. A line break at the very end of the inserted text leaves the rest of the item as it was (reading gives it its own identity). |
| Return in an empty item | Intercepted | Intercepted, as today: moves out a level, or leaves the list; at the end the item's own end goes, as the marker does today. Headings: unchanged. |
| Backspace at an item's start | Caret after the marker | Caret at the paragraph start; same one-level removal (`ItemFormattingRemoval`). |
| Joining lines (Backspace at a line start, forward delete, deleting or typing over a selection across lines) | `joiningDeletion` removes the marker with the line break, through `replace` | Through `replace` as one snapshot undo step, as today, whenever an item or quote is involved: the text joined onto a line takes that line's paragraph attributes (kind, identity, metadata, number, paragraph style), so an item's attributes can't resurface later. Only between text paragraphs: never from or into an image, table, rule or code block. When the deletion starts at a line's start and leaves none of that line, nothing is joined: the remaining line keeps its own attributes, as AppKit does. Joins between plain paragraphs, and typing or composing over a selection, stay native. |
| Tab / Shift-Tab, Mark as Checked, checkbox tap, Markdown shortcuts (`- `, `[] `, `1. `, `> `), Format panel styles | Re-render the line, or its text only | One helper re-renders whole paragraphs including their line breaks and applies the own-end post-condition, so the line break always carries its paragraph's attributes. |
| Paste and drop | Rendered fragment; `joinParagraph` removes the first marker | Plain text pasted into a list item or quote is inserted as its lines: the first joins the item, each further line is the next item and the rest of the item follows the last, as typing them does; an empty item, the last one included, stays an item. Formatted text keeps its own blocks as before; a line of it pasted into an item joins the item, which keeps its line break. |
| Copy within the journal (Markdown) | A selection without a line break copies as plain text | Unchanged. A multi-line selection that starts inside an item copies that first line as plain text (today: tasks kept their kind, bullets didn't). |
| Undo | Snapshots for the editor's edits, native for typing | Unchanged. Every change to characters outside the inserted text (splits, continuation, joins, the own end) happens inside the editor's snapshot `replace`, so undo and redo restore it exactly. Native edits only adopt attributes onto the characters they insert, as today, which their own undo removes. |
| Source mode | Markdown | Unchanged; preview↔source selection mapping no longer has marker characters to skip. |

### 3.4 What the keyboard, accessibility and other readers see

- Before the caret on a new item: `"…Buy milk\n"`, a line start, for every list type.
- The keyboard re-reads its context after the editor's own edits: measured in stage 0 (iOS 26.5), the software keyboard shows capitals after the `# ` shortcut and after Return in a heading, both performed with `replace`, and lowercase after the `[] ` shortcut and Return in a checklist, where the marker precedes the caret.
- VoiceOver reads the text without “ballot box”, “bullet” or “2 period” characters, and learns what each line is from accessibility text attributes instead (`ListAccessibility.swift`, added after the owner's decision in section 11). They are part of each list item's and quote's paragraph attributes, so the text views hand them to assistive technologies with the text itself, and the text the keyboard reads is unchanged:
  - Mac: AppKit's list item attributes, made for exactly this: `accessibilityListItemPrefix` (“•”, “3.”, “Checkbox, unchecked”, “Checkbox, checked”) and `accessibilityListItemLevel` (the nesting level). Quotes carry `accessibilityCustomText` [“Quote”]. The item index is left out: it would have to be rewritten on every item above when items are added or removed, and the prefix already carries the number.
  - iPhone and iPad: UIKit has no list attribute; each item carries `accessibilityTextCustom` [“Bullet”], [“3.”], [“Checkbox, unchecked”], [“Checkbox, checked”] or [“Quote”].
  - Checklist items also keep their checkbox buttons (“Buy milk, Unchecked, button”).
- Find no longer matches markers.

### 3.5 TextKit 1, made explicit

Both body text views are created with a TextKit 1 stack from the start (3.2) instead of letting the first `layoutManager` access rebuild them. Same text system as today, without building and discarding a TextKit 2 stack; the “switching to TextKit 1 compatibility mode” message goes away. The title, table cells and placeholder are out of scope.

### 3.6 Text for other apps

Copy and Cut to other apps (iOS `pasteboardItem`, Mac `writeSelection` for `.string`, `.rtf` and `.rtfd`, and Mac drag, which uses `writeSelection`) hand over the selection in TextKit 1's list representation: items whose start is selected begin with `•\t`, `n.\t`, `☐\t` or `☑\t`, in the label colour, inside one shared `NSTextList` per list (disc, decimal, box, check), so Pages, TextEdit and Mail paste real lists and plain text reads as it does today. Quotes carry no marker. Today's RTF had clear, invisible `☐` characters and a 0.1 pt `❯`. The journal's own Markdown type is unchanged.

Dragging selected text from the iOS editor to another app uses UIKit's own drag items, built from the text storage: after the change they carry the text without bullets or numbers. Accepted for now and listed as a known difference: adding a `UITextDragDelegate` also changes drags within the entry, which is a larger change than this one.

### 3.7 States

No loading, empty, offline or error states. An empty entry is unchanged. Read-only entries draw markers and disabled checkboxes as today.

## 4. Visible differences

1. Unchecked checklist items no longer have a 1–3 pt taller first line at some sizes; checking an item no longer moves the text below it.
2. A quote's first line moves 0.5 pt left onto its wrapped lines.
3. Numbers `100.` and up keep their text on the same line (today it wraps below the number).
4. A bullet or number is no longer selectable, findable or spoken as a character. The Mac's selection highlight still runs under it.
5. iOS: dragging list text to another app no longer carries bullets or numbers (3.6).

Everything else must look identical, compared with `checklist-faceid/B-after*` and new captures of quotes and wide numbers.

## 5. Risks

- **Paragraph-attribute consistency** replaces the marker as an item's anchor. Mitigation: one adoption/joining/continuation pass inside the text system's own edit (attributes only), one helper and post-condition for the editor's edits, and the tests in 7.
- **The own end** is a new invariant. Mitigation: exact round-trip tests for every ending, stale-tag and caret tests; if it is ever missing, an item with text still reads correctly.
- **Undo** of splits and joins: all of them are snapshot steps (3.3); tests undo and redo each.
- **Drawing parity**: verified by a pixel comparison of the drawn marker with today's glyph, and screenshots.
- **The keyboard after programmatic edits**: measured in stage 0 (3.4).
- **Native typing undo** is not disturbed: no character is inserted or removed outside an edit the text system or the editor's snapshot undo owns.
- **Older OS versions**: no `NSTextList` in the editor's text; the RTF export uses the TextKit 1 representation every RTF writer reads.

## 6. Staged implementation (each stage builds and passes its tests)

0. **Measure** (done): on a dedicated iOS 26.5 simulator, the keyboard's case after native and editor-made line breaks (3.4); XCUITest shows it as the key labels' case (`B` or `b`).
1. **Explicit TextKit 1 with `ListLayoutManager`** (drawing nothing yet). Editor suites.
2. **Helpers while markers still exist**: paragraph-replacement helper with the own-end post-condition, own-end reading, export for other apps, the copy rule. Behaviour unchanged.
3. **Switch the representation**: render without markers, numbers attribute, indents, own end, drawing, checkbox placement, caret and selection clamp, typing attributes, adoption, splits and joins through `replace`. Update the tests that assert marker characters. Screenshots.
4. **Remove dead code**: list paths of `HiddenMarkers` and `joiningDeletion`, the “marker gone” rule, `newlineAction`'s split path.

## 7. Tests

New:

- **Keyboard context, per list type** (iOS and Mac, real editor, `ListTypingContextTests`): for checklist, bullet, numbered and quote, type the shortcut, a word, Return; the text before the caret ends with `"\n"` (iOS: `UITextInput.text(in:)` and the tokenizer's paragraph boundary), the text is exactly what was typed with line breaks, and the document holds the new empty item.
- **Shift on a fresh item** (iOS UI test): after `[] `, “buy milk”, Return, the software keyboard shows capital letters (`app.keys["B"]` rather than `"b"`), and the same after `- ` and `> `. It's the only test of the actual symptom.
- **Round trips**: render → read is identity for entries ending in a non-empty item, an empty item, a quote, and an item followed by an empty paragraph, for each list kind, nested and in a quote.
- **Own end**: the caret can't land after it; deleting all of the last item's text keeps the item; forward delete at its end keeps it; inserting a picture or table at the end of an entry ending in a list and deleting it again round-trips exactly; on the Mac, typing on the empty line after a list writes a plain paragraph.
- **Continuation and undo**: Return in numbered, checked and nested items (identities, numbers, unchecked), Return at the start of a checked item (it stays checked with its identity); `insertText("a\nb")` into an item; exact undo **and** redo of Return in a checked and a numbered item, Return at the end of the last item, leaving the list, joining a checked item onto a bullet, joining a paragraph onto an item, and forward delete across items.
- **Joining**: an item joined onto the line above stays a paragraph after its head is deleted; forward delete at the end of a code block or before a table doesn't pull the item into them.
- **Composition**: marked text at the start of an empty middle item and of the empty last item keeps the item, its own end and its indent.
- **Copy for other apps**: plain text and RTF of a copied checklist start items with `☐\t`, and RTF read back has the lists (extends `EditorClipboardTests`).
- **Geometry**: `ChecklistGeometryTests` keeps every assertion, reading marker positions from the layout manager's own drawing positions; adds equal first-line heights for checked and unchecked items and a pixel check of a drawn bullet against today's glyph.

Updated: `EditorTests.testListReturnContinues…`, `EditorChangeTests.testArrowKeysStepOverHiddenMarkers` (becomes the caret tests), `EditorContentSafetyTests` marker tests, `MarkdownEditorTests` (find the task by kind), `PreReleaseUITests.testBackspaceAtTheStartOfATaskRemovesTheCheckbox` (checkbox buttons, not `☐` in the value).

Must stay green: TypingScrollTests, EditorClipboardTests, ChecklistGeometryTests, MarkdownEditorTests, MarkdownShortcutTests, ItemFormattingRemovalTests, StructuredSelectionTests, PasteCorpusTests, EditorContentSafetyTests, EditorTests, EditorChangeTests, EditorReadingTests, FormattingRuntimeTests, TemplateInsertionTests, TableEditorTests; the Mac lane; the iOS UI classes WritingWorkflowUITests, EntryBasicsUITests, PreReleaseUITests, PasteUITests, RotationUITests, IPadWritingUITests; all JournalIOSTests once.

Screenshots: every list type, nested and wrapped, numbers ≥ 100, quotes, checked and unchecked, a selection across items on the Mac; light and dark; default and largest text; iPhone 17 and Mac; compared with `B-after*`.

## 8. Open questions for the owner

1. **VoiceOver**: decided, see section 11.
2. **The small visible differences in section 4**: accepted by the owner as improvements.
3. **iOS drag to other apps** loses bullets and numbers (3.6): accepted by the owner as a known gap; Copy and Paste keep them.
4. Moving the editor to TextKit 2 (option A) remains possible later; not proposed now.

## 9. Review

An independent design review (2026-10-03, given the owner's report, the requirements and the first draft) returned **approve with required changes**. Its experiments confirmed the TextKit 1/2 findings, the fallback-font height and AppKit's typing attributes. Required changes and how they were addressed:

1. *Prove the keyboard re-checks capitalization after the editor's programmatic edits; prefer native Return.* Stage 0 measured both paths (3.4); after the re-review Return stays intercepted (see Re-review).
2. *Markers drawn in `drawBackground` disappear under the Mac's selection highlight* (confirmed by the reviewer's render). They are drawn by a layout manager subclass after the glyphs (3.2).
3. *The own end was underspecified*: the extra blank line it adds at the bottom, stale tags when content follows it, typing after a list at the end on the Mac. Now: no extra line fragment, the tag only on the last character with a post-condition for editor edits, and plain typing attributes on the line after a list (3.1, 3.3).
4. *Joining needed exceptions and a direction*: text paragraphs only, never code, tables, pictures or rules; nothing joins when a whole line is deleted from its start (3.3).
5. *System-inserted line breaks* would duplicate identities and numbers: line breaks that reach the text view's change check (Return, dictation, inserted text) continue the list through the editor (3.3); bullets are drawn from the kind, only numbers are stored. Line breaks that never reach it (an input method's composition, an iOS drag-move) keep today's behaviour: the paragraphs share an identity, which reading already de-duplicates.
6. *iOS drag-out* isn't covered by the export: accepted and listed for the owner (3.6, 8).
7. *Copying should not change*: single-line selections stay plain text (3.3).
8. *VoiceOver needs an owner decision*: asked (8); AppKit's list-item attributes are left for that follow-up because VoiceOver's use of them can't be verified here (3.4).
9. *The geometry test must not become a tautology*: positions come from the drawing code, plus a pixel check against today's glyph (7).
10. *Wide numbers* need a stated rule (3.1); visible differences go to the owner (8).

Suggestions taken: typing attributes at a paragraph start on iOS from the paragraph itself; construction inside `JournalTextView`; right-to-left stated as out of scope; the composition, undo, join-exclusion, stale-tag and Mac typing-after-list tests; the Shift test by key case; the `accessibilityValue` assertion dropped. Credit to Notes as a precedent (paragraph attributes, markers drawn by the app) is noted in 2, with “a later TextKit 2 move only changes who draws bullets” toned down.

### Re-review

The revision was re-reviewed (same reviewer, 2026-10-03): **approve with required changes**, with all ten earlier required changes resolved or accepted. Two new required changes, both made above:

- *N1. Native undo doesn't restore attribute fixes made outside the edited range* (measured by the reviewer on the Mac). Stage 0 then showed the keyboard capitalizes after the editor's own `replace`, so native Return was no longer needed: splits, continuation and joins all go through the snapshot `replace` (as `deleteHiddenMarker` does today), native edits only adopt attributes onto the characters they insert, and the tests undo and redo each case.
- *N2. How native edits keep the own end*: selections end before it unless they cover the whole text; a forward delete of it alone does nothing; Mac drops land before it.

Suggestions taken: Return at the start of an item keeps the item's identity and checked state; the layout manager's type is asserted in a test (so a silent TextKit 2 fallback can't hide); pasted blocks keep their own formatting (the rest of the item after a multi-line paste becomes a new item through the editor's own post-condition). Not taken: shipping AppKit's list-item accessibility attributes unverified (left with the owner question).

The reviewer then confirmed both resolved: **approved**. Its minor notes (iOS drops at the very end, composition over a multi-line selection, line breaks that bypass the change check, and stale wording in the first review list) are reflected above.

## 10. Implementation check (2026-10-03)

- Code: `ListLayout.swift` (the `ListLayoutManager` that draws bullets and numbers after the glyphs and drops the extra line fragment after an own end; `JournalTextView` lays out with it from the start on both platforms), `ListEditing.swift` (splitting, continuing, joining, paragraph replacement, the own-end post-condition, typing attributes, text for other apps), and the changes in `RichText`, `HiddenMarkers` (now rules only, plus the caret and selection clamp), `InlineTasks`, `InsertedText`, `MarkdownShortcuts`, `StructuredKeyboard`, `NativeEditor`, `NativeTextView`, `PastedTextInsertion` and `NativeTableIntegration`.
- Backspace at the very start of the text, where the text views do nothing themselves, now reaches the editor (`deleteBackward` on iOS, the command on the Mac), so an item on the first line loses its formatting as items elsewhere do; before, its marker kept the caret one character in.
- Screenshots (iPhone 17 simulator, iOS 26.5): the build 13 “Weekend” entry is pixel-identical to the build 13 captures in light and dark, at the default and the largest text size. Mac (16 and 26 pt, light and dark), rendered from the same editor before and after the change: identical except that unchecked items' first lines are 1 pt (16 pt) and 3 pt (26 pt) shorter, as section 4 expects. Bullets and numbers show above the Mac's selection highlight. A new checklist or bulleted item shows the capital keyboard with capitalized predictions.
- An adversarial QA review of the implementation (an independent agent, reading the code) found eleven problems; all that applied were fixed and each has a test in `ListItemEditingTests`: the caret could end past the text after deleting from a line into the last item (a likely crash); pasting into an empty item made it a plain line, and at the end of the last item added an empty line; several lines pasted at an item's start put a plain line inside the list; Return carried the item's first word's bold, code or link into the next item; multi-line formatted text inserted into an item lost its links (now the system inserts it and only its new lines' characters become items); on iOS, typing at the start of a line after a list took the list's indent; a last item starting with a picture lost its line break; composing over a multi-line selection was intercepted (typing over such a selection is native again); Select All and Delete couldn't remove a lone empty item. Not changed, as before this work: Return in the middle of a numbered list doesn't renumber the items after it; Return in an empty quote line doesn't leave the quote.
- Numbers `98.` and `99.` still touch their text at the default iPhone size (unchanged from build 13: the number fills the column); `100.` and up no longer wrap the text below the number. *Fixed in section 12.*

## 11. Owner decisions and VoiceOver (2026-10-03)

The owner accepted the visible differences of section 4 and the iOS drag gap (3.6), and asked for VoiceOver to keep learning that a line is a list item and which kind, without markers coming back into the text.

- **Approach** (3.4): accessibility text attributes on the item's own text, stored with its paragraph attributes. Measured how each platform's own accessibility hands them on:
  - Mac (macOS 26.5): `NSTextView`'s accessibility server path (`AXAttributedStringForRange`, the request VoiceOver makes) returns the list item and custom attributes that are in the text storage, for TextKit 1 and 2 alike; an override of `accessibilityAttributedString(for:)` alone is *not* used by that path, which is why the attributes are stored rather than added on the fly. Apple's AccessibilityUIExamples sample (`AccessibilityUIExamples/Text/TextAttributesTextView.swift`, developer.apple.com/library/archive/samplecode/AccessibilityUIExamples) returns the same list item attributes, prefix included, from its text view.
  - iOS (26.5 simulator, UIKit's own accessibility implementation loaded in the test process): the text view's accessibility value is the written text only, and both its attributed value and the per-range attributed value VoiceOver reads lines from carry `UIAccessibilityTextAttributeCustom` on every list item and quote line.
- **Expected, not yet heard**: VoiceOver's actual speech. The simulator has no VoiceOver, and the Accessibility Inspector needs an interactive session. How VoiceOver voices custom text attributes on iOS (as it reads a line, or when text attributes are asked for) is VoiceOver's choice; Apple documents the attribute for conveying such context. Until someone listens with VoiceOver on the Mac (⌘F5) and on an iPhone, the announcements are expected rather than confirmed; if iOS VoiceOver turns out not to speak the custom attribute while reading lines, the iPhone and iPad gap remains and needs another approach. The listening check should also judge whether checklist lines, announced in the text and again by their checkbox button, are too noisy.
- **Review**: the independent reviewer approved with two required changes: word the announcements as expected until heard with VoiceOver (done here), and cite the Apple sample (done). Its suggestion to test that every numbered line announces the number it shows, including items made by the shortcut and by Return in the middle of a list, is in the test; the list item index stays out for now.
- **Tests**: `ListItemEditingTests.testListLinesCarryTheirAccessibilityAttributes` (both platforms): each kind of line, nested and typed later, carries its announcement; plain lines carry none; the text read is exactly the written text, as the keyboard reads it.

## 12. Numbered list column (2026-10-04)

QA found that most two-digit numbers touch their text, not only `98.` and `99.`: at every size measured (16, 17, 23, 30 and 53 pt), between 65 and 88 of the numbers 1–99 are wider than the shared list column minus a space. Moving only the first line of each such item in (the rule above for `100.` and up) would leave the text of neighbouring items ragged.

- **Decision: accepted** (coordinator, for the owner, 2026-10-04), because native lists size the number column to the widest number, as TextEdit and Pages do.
- **Rule:** the numbered items at one nesting level, with deeper items between them, form a list. The list's column is the shared list column, or the width of its widest number plus a space, whichever is wider (`RichText.alignNumberedLists`, attribute `.journalListColumn`). Every item of the list uses it, so its numbers keep a space before their text and its text lines up, wrapped lines included. The column is set when an entry is shown and after each of the editor's own edits, so the Return that makes item `10.` widens the whole list at once. Typed text continues in the new column.
- **Visible differences:**
  - Lists numbered 1–9 keep the shared column and still line up with bullets and checklists.
  - A list that reaches `10.` is a few points wider: about 4–5 pt at 16–17 pt, 7 pt at 30 pt and 9 pt at 53 pt (the widest two-digit number plus a space). Its text no longer lines up exactly with a bullet list or checklist next to it.
  - A list that reaches `100.` widens by the width of a three-digit number plus a space, at every item, not only from item 100 on.
  - Items nested under a widened list still start at their nesting (one shared column in per level), so they start a few points left of their parent's text instead of exactly under it.
- **Accessibility and other apps:** unchanged. The number announced and the text copied to other apps don't depend on the column.
- **Tests:** `ChecklistGeometryTests.testNumbersKeepASpaceBeforeTheirTextAndTheListLinesUp` (lists reaching 99, 100 and 101, and Return making `10.`, at the default and the largest size on both platforms). Screenshots at the default and the largest iPhone text size were checked.

