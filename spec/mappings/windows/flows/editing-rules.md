---
id: editing-rules
title: Editing rules (Windows)
spec: flows/editing-rules.md
features: [entry-title, entry-body, inline-formatting, paragraph-styles, lists, checklists, list-indentation, block-quotes, code-blocks, horizontal-rules, tables, links, inert-links, insert-image, image-actions, markdown-as-you-type, source-view, paste-and-drop, copy-to-other-apps, undo-redo, spelling-and-substitutions, autosave]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/rich-edit-box
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.text.richedittextdocument
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.richeditbox.paste
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.richeditbox.textcompositionstarted
  - https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-accelerators
---

# Editing rules (Windows)

Every rule of the spec's [editing-rules](../../../flows/editing-rules.md) becomes a conformance test on every platform. This file says, for Windows, which key or trigger each rule listens to, what the editing control must provide, and which rules look hard on WinUI. It is the companion of the requirement list in [entry-editor](../screens/entry-editor.md) (R1 to R20), which also compares the candidate controls. The rating column assumes Spike A of that file: `RichEditBox` with an app layer and an overlay for what it cannot draw; Spike B (`WebView2`) runs in parallel and, if it wins, the keys and the rules do not change, only the ratings.

**Ratings.** *Native*: the control does it. *App*: ordinary application code over the portable model or the control, no known pitfall. *Care*: application code with a known pitfall that the spike must prove. *Hard*: needs an overlay or a workaround that may not hold; a spike gate. *Blocked*: the control cannot do it; needs another solution or a product decision.

## Controls

The editing control, the title control and the keys; the rules themselves follow in groups.

### How the rules reach the control

- **The rules live in the portable model**, not in the control. A key handler asks the model for the edit, the model returns the changed blocks and the new selection, and the control applies them as one undo step ([entry-editor](../screens/entry-editor.md), Architecture rules).
- **Keys are handled in `PreviewKeyDown`**, before the control, with `Handled` set. Everything the rules bind is handled there; everything else the control does as usual. `DisabledFormattingAccelerators` is All, and the chords with which the control would apply a format the document cannot store (alignment, line spacing, bullets, font size, super and subscript, Ctrl+wheel zoom) are swallowed ([7](../platform.md#7-keyboard-shortcuts), rule 6). Every other chord, such as Ctrl+Backspace, Ctrl+Delete, Ctrl+Left and Right, Ctrl+Home and Ctrl+End, keeps the control's behaviour (D34), and AltGr typing is never touched.
- **Composition.** `TextCompositionStarted` and `TextCompositionEnded` (the control's and the title's) set a flag. While it is set, no rule in K, T-1, N, B, I or X converts, joins or replaces anything; Esc and Enter belong to the input method; changes from elsewhere wait (X-2). `PreviewKeyDown` sees the processing key (virtual key code 229) during composition and must ignore it.
- **Typed characters, not key codes.** A rule that fires on a typed character (the space of K-1) listens to the key that types it, so layouts, dead keys and AltGr work; text that arrives without key events (voice typing, handwriting, the emoji panel, the touch keyboard's text suggestions) is checked in the text-changed handler against the same rule.
- **Synchronous.** Each rule completes inside the key handler. A burst of keystrokes keeps every letter in order and in its own item (N-12).

### Keys on Windows

| Spec key | Windows key | Notes |
| --- | --- | --- |
| Return | Enter (also the numeric keypad Enter) | Shift+Enter and Ctrl+Enter are not in the spec (D34) |
| Delete (backspace) | Backspace | |
| Forward Delete | Delete | |
| Option-Backspace | Ctrl+Backspace | Deletes a word; B-3 applies at an item's start |
| Command-Backspace | not offered | No standard Windows key; the spec's "delete to the start of the line" does not exist on Windows ([commands.md](../commands.md), Keys in the text). Ctrl+Shift+Backspace is unbound |
| Tab, Shift-Tab | Tab, Shift+Tab | Tab is a tab character in a paragraph and in the title never; F6 always leaves the editor |
| ⇧⌘Return (Mark as Checked) | Ctrl+Shift+Enter | |
| ⌘Z, ⇧⌘Z | Ctrl+Z, Ctrl+Y (Ctrl+Shift+Z also) | |
| ⌘K | Ctrl+K | |
| Down Arrow at a code block's end | Down | BI-4 |
| Escape | Esc | Not while an input method composes |
| ⌘] ⌘[ | Ctrl+M, Ctrl+Shift+M | and Tab, Shift+Tab in an item or code |
| Other Windows text keys: Ctrl+Delete, Ctrl+Left and Right, Home, End, Ctrl+Home, Ctrl+End, Page Up and Down, with Shift for selecting | the control's own behaviour | Not in the spec; D34 asks to confirm that the line-boundary rules (B, E, N) apply to them as stated |

### The rules

#### M. Markdown storage and preservation

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| M-1, M-16 | any edit | **Hard** | Byte-exact untouched blocks and stable block identities. The control reports no edit range and gives paragraphs no identity, so the app compares the text and paragraph formats before and after every change (prefix and suffix, then block by block) and maps the difference to blocks. Splitting by Enter assigns a new identity; joining keeps the earlier one. Needs a corpus test |
| M-2 | opening and leaving | Care | Opening, showing and leaving with no change writes nothing: the first text-changed event after loading content is ignored, and loading is not an edit |
| M-3 to M-10, M-13, M-14, M-15 | any edit | App | Portable Markdown reader and writer: marker spelling, line endings, reference definitions, spaces beside marks (`&#32;`), escaping, raw HTML as source text, tables interrupting paragraphs, whole-text equivalence. M-10: an empty item above a nested item stays an item, shown as an empty list paragraph |
| M-11, M-12 | opening an entry | Native | `IsReadOnly` for what this version cannot fully read; source-only entries open in source view. The record is never changed |

#### T. Title

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| T-1 | Enter in the title | Care | Moves focus to the body; while an input method composes, Enter confirms the composition. Tab never types a tab in the title and does not leave it |
| T-2 | Ctrl+V in the title | Native | Line breaks kept, no move to the body, one Undo removes the paste |
| T-3, T-4 | layout | App | Wrapping `TextBox`, zero padding on title and body so the first letters align |
| T-5 | new entry | App | Title focused, text selected |

#### N. Return

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| N-1 to N-4 | Enter in an item | Care | Handle Enter, split the item in the model, apply new identity, number and unchecked state; the new item continues the formatting at the caret. The control's own list continuation must not run as well |
| N-5, N-6 | Enter on an empty item | App | Leave the list, or move out one level, with the caret on it; no extra line at the end of the entry |
| N-7, N-8 | Enter in a quote or heading | App | As specified; Return in the middle of a heading is not specified (open question D6) |
| N-9 | typing on the line after a list | Care | After leaving a list the empty paragraph must not inherit list formatting from the control's carry-over of the previous paragraph's format |
| N-10 | Enter over a selection ending with a line break | Care | The selection of a whole line in the control includes its paragraph mark |
| N-11 | multi-line text inserted in one piece (voice typing, drop, paste) | Care | Further items as Return would make them; the control may already continue the list natively, so the result is normalised against the model |
| N-12 | a typed burst | Care | Synchronous handling, see above |
| N-13 | first character in a new item | Care | Nothing moves when it is typed: an empty item draws its marker at the same place as a filled one (to prove for native list markers) |
| N-14 | Enter in a code block | Care | Inserts a line break inside the one code block, not a new paragraph. A code block is one paragraph with line-break characters |
| N-15 | Enter in a table cell | Blocked | Moves to the cell below; depends on how tables are done (R6, D33) |

#### E. The end of the entry

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| E-1, E-2, E-3, E-4 | caret and Delete at the end | Care | The last item owns its line break: no empty line follows it and the caret cannot go past it. A rich edit story always ends with its final paragraph mark, which fits: the model's last item is that paragraph, and no extra paragraph is added when showing a document that ends in a list. Select All then Delete in an entry whose only line is an empty item removes everything |
| E-5 | touch tap below the text | Care | Continue at the entry's end; never select the last word. A mouse click below the text does this natively |

#### B. Backspace and deletion

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| B-1, B-2, B-3, B-4 | Backspace, Ctrl+Backspace at an item's start | Care | Handled in `PreviewKeyDown` before the control: remove one level of formatting, or move out one level with the items nested under it, innermost first; also at the entry's start and for empty items. One undo step named `editor.undo.paragraph`, `editor.undo.blockQuote` or `editor.undo.decreaseIndent` and the matching announcement |
| B-5 | Backspace elsewhere | Native | |
| B-6 | Backspace, Delete, typing or deleting over a selection across lines | **Hard** | The joined text takes the paragraph of the line where the selection starts. In a rich edit control paragraph formatting lives with the paragraph mark, so a native join gives the merged line the following paragraph's format: the opposite. The app must intercept every joining edit (Backspace, Delete, cut, typing, paste and drop over a selection) and fix the format afterwards in the same undo group |
| B-7, B-10 | joins | Care | Joins never pull an image, table, rule or code block into a line; deleting a rule's line removes the rule whole and none of it is saved in a joined line |
| B-8 | composing over a selection across lines | Care | The input method composes there and the result replaces the selection |
| B-9 | delete across items, then Undo | Care | Brings back every item exactly (identity, kind, checked state): needs the app-owned undo (U-1) |

#### I. Increase and Decrease Indent

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| I-1 to I-11 | Ctrl+M, Ctrl+Shift+M, Tab, Shift+Tab | App | Planning is portable model code. The control's own indent commands are not used: the list level is set from the model's result. Unavailable commands do nothing and the key types no tab in a list item |
| I-3 | maximum depth | App | ⌊160 ÷ round(1.5 × size)⌋ levels, at least 1, in epx (6 at 16 and 17) |
| I-12 | Tab in an item | Care | Handled in `PreviewKeyDown`; in a paragraph Tab types a tab character; where the command is unavailable the key does nothing |
| I-13, I-14 | undo, announcement | Care, App | One undo step named `editor.undo.increaseIndent` or `editor.undo.decreaseIndent` restoring list and selection exactly; the new level announced with `editor.announce.level` |
| I-15 | Tab, Shift+Tab in code | App | Tab (or a tab on every selected line) and removal of one tab or up to four spaces |

#### C. Checklists

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| C-1, C-2 | Ctrl+Shift+Enter; Format menu | App | Acts on every checklist item the selection touches; the command's name follows the caret's item; unavailable outside a checklist item |
| C-3 | click or touch a checkbox | **Hard** | An overlay `CheckBox` toggles its item as one undo step and leaves caret and focus in the text (`IsTabStop` false, `AllowFocusOnInteraction` false). A tap between two boxes toggles the nearer one |
| C-4, C-5 | | App, Care | Nothing else changes; an item that holds only an image keeps it |
| C-6 | scrolling, typing, zoom, resize | **Hard** | Every box in view is in place at every scroll position: positions come from range rectangles and are recomputed on layout, scroll and zoom |

#### G. List layout

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| G-1 to G-3 | layout | Care | Common x for markers and text; list column 1.5 × the size rounded; markers 18 epx in; nested marker under the parent's text; nesting stops moving after 160 epx; set through paragraph indents and tab stops, and checked at 12, 16 and 30 epx |
| G-4 | numbers 10 and over | App | Every numbered item at one level uses the wider column |
| G-5 | marker font | **Hard** | A drawn bullet or number looks like the regular font's, never the first word's bold or code font. Native list markers may follow the first character's format; if so the marker's format must be set separately or drawn by the overlay |
| G-6 | Narrator | **Hard** | Markers are never characters; Narrator learns kind, level, number and state from automation properties ([entry-editor](../screens/entry-editor.md), Accessibility). The control's built-in automation may expose native markers as text or not at all (D32) |
| G-7, G-8, G-9 | composing in an empty item; typing at a line start; arrow keys | Care | Composition keeps the item, its indent and its line break; typing at an item's start is the item's visible text; arrows cross an item's start like any line |

#### F. Inline formatting

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| F-1, F-3 | Ctrl+B, Ctrl+I, Ctrl+U, Ctrl+Shift+X, Ctrl+Shift+C | App | On for the whole selection unless every character that can carry it already has it (the control reports a mixed value as undefined); strikethrough and inline code by the first character; each run keeps its other styles and size |
| F-2 | Bold in a heading | Care | A heading's weight is SemiBold (a weight value), not the Bold effect (a higher weight), so Bold shows Off and is not saved as `**` |
| F-4 | no selection | Native | Changes only what the next typed text gets, through the collapsed selection's character format; it resets when the caret moves, as expected |
| F-5 | in a code block | App | Commands disabled |
| F-6 | the Formatting state | App | On, Off or Mixed from the selection's character format |
| F-7 | typing after inline code | Care | Continues the code; the control's format carry-over at a run boundary is to prove |

#### P. Paragraph styles

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| P-1 to P-3, P-5 | Ctrl+Shift+0 to 6, Ctrl+Shift+7, 8, 9, Ctrl+Shift+Q (never Ctrl+Alt: that is AltGr, [7](../platform.md#7-keyboard-shortcuts), rule 3) | App | Restyle every whole paragraph the selection touches and nothing else; images, tables, code and raw HTML keep their kind; changing to a non-list style removes nesting and number; the caret goes to the end and typing continues in that style |
| P-4 | a list style on an empty line | Care | One identity for the item while it is typed |
| P-6 | in a table cell or code block | App | Unavailable |

#### K. Markdown as you type

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| K-1 | Space after a marker at the start of a plain paragraph | Care | `- `, `* `, `+ `, `n. `, `n) `, `[ ] `, `[] `, `[x] `, `[X] `, `> `, `# ` to `###### ` convert the line, only in preview, only with the setting on, never while composing, never on paste. Handled synchronously in `PreviewKeyDown` for Space; the typed-text check covers text that arrives without keys |
| K-2 | Enter after `---`, `***`, `___` or a code fence line | App | Horizontal rule or empty code block with the caret inside |
| K-3 | Ctrl+Z after a conversion | **Hard** | Two undo steps: the typed space and the conversion. The first Undo gives back the typed marker and space as plain text, the second removes the space. Needs the app to close an undo group after the space and open another for the conversion, or an app-owned stack |
| K-4 | Backspace right after a conversion | **Hard** | Gives back exactly what was typed ("- ") as a plain paragraph, one step named `editor.undo.typing`, not converted again while typing continues |
| K-5, K-6 | | App | Announcements `editor.announce.*`; with the setting off, characters stay |

#### BI. Inserted blocks

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| BI-1, BI-2, BI-4, BI-7 | Format ▸ Insert; Down in a code block | App | After the caret's block, never splitting text; caret placement as specified; exit from a code block |
| BI-3 | Insert ▸ Table | Blocked | A 2 × 2 table with the caret in the first header cell (R6) |
| BI-5, BI-6 | typing in and beside blocks | Care | Typing in a code block keeps one code block; typing on the empty line after an image, table or rule keeps exactly one copy of the block |

#### TB. Tables

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| TB-1 to TB-7 | typing in cells; Tab, Shift+Tab, Enter; cell context menu; Format ▸ Table | **Blocked** | The control has no table editing API. In Spike A tables are preserved, byte-exact, read-only grids edited in source view (D33's draft default); an overlay grid of cell editors over reserved space is not planned (TB-1 shared undo, TB-3 caret leaving the table, selecting across the table and PA-3 copy would all need app code), and Spike B's native cells are the other route. TB-2 (one line per cell), TB-4 (structure edits) and TB-6 (cells, alignment marks, pipes and source kept) are portable model code. See [edit-table](edit-table.md) and D33 |

#### L. Links

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| L-1, L-2, L-4, L-5 | Ctrl+K; the Link dialog | App | Applies to the selection keeping each run's formatting; accepted addresses as in [link-editor](../screens/link-editor.md); link titles kept |
| L-3 | reading Markdown | Care | http, https and mailto shown as links; other destinations shown as plain text and kept unchanged |
| L-6 | typing an address | Care | Nothing is linked automatically: the control's own URL detection, if it has one, is turned off or reversed |

#### S. Source view

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| S-1, S-3, S-5, S-6, S-7 | Ctrl+Shift+U; Format commands in source | App | Stored Markdown exactly; formatting commands edit syntax; images follow the width; pasted formatted text becomes Markdown |
| S-2 | switching | Care | Same character, same selection (also with emoji), the caret's line at the same height in the window |
| S-4 | switching | Care | One undo step named `editor.undo.viewSource` or `editor.undo.viewPreview`; Undo returns to the previous view and text |
| | | | See [source-view](source-view.md) |

#### SP. Spelling and substitutions

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| SP-1 | caret in code, raw HTML, inline code; source view | **Blocked** per range | Spelling marks, text suggestions and autocorrection off there. `IsSpellCheckEnabled` is one switch for the whole control, so in source view the control's spell check is turned off and in code blocks Windows would still mark words (D35). Smart quotes and dashes are not applied by Windows text controls |
| SP-2 | prose | Native | The Windows spell checker follows Settings > Time & language > Typing; there is no in-app spelling menu |

#### PA. Paste, drop and copy

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| PA-1, PA-2, PA-3 | Ctrl+C, Ctrl+X, drag out | Care | The control's copy and cut events are handled: the clipboard gets the entry's own Markdown (a registered format, D36), a plain text form with list markers and a tab ("☐\t", "☑\t", "•\t", "n.\t"), HTML for other apps, and a table's Markdown as plain text; text copied within one paragraph pastes joined to its paragraph |
| PA-4, PA-5, PA-9 | Ctrl+V of formatted text | **Hard** | The `Paste` event is handled before insertion. Other apps' formatted text (HTML, then rich text) becomes the entry's blocks: headings by size, lists, nested lists, checklists, code, tables, bold, italic, underline (not a link's), strikethrough, inline code, web and email links; fonts, sizes, colours and highlights dropped; pasting a page loads nothing it refers to. A portable converter, not the control's own paste |
| PA-6, PA-7, PA-8, PA-15 | Ctrl+V | App | Joining, items from pasted lines, code text in code, pasted pictures landing where the paste was made even if writing continued |
| PA-10 | Ctrl+Shift+V | App | Plain text as written, one paragraph per line; Markdown characters stay characters; lines continue the list they land in |
| PA-11, PA-12 | pictures on the clipboard | App | Text wins over a picture the word processor offers; a picture whose only text is its web address pastes as the picture; image files, bitmaps (including Snipping Tool captures) and pictures inside formatted text are imported first and arrive in place |
| PA-13, PA-14 | drag and drop | Care | Dropped journal content and picture files go where they are dropped (the insertion point from the drop position), in order, never after the last item's own line break; another app gets a copy, only a drop within the entry moves |

#### IM. Images in the text

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| IM-1 to IM-4 | Insert image; paste; drop | Care | An image on a line of its own at the recorded caret; typing beside it keeps exactly one reference; unavailable images keep reference and description; text beside an image survives as its own paragraphs |
| IM-5 | Delete in its menu, Cut, Delete key on a selected picture | App | The picture on its own line goes with its line; at the end of the text the line break before it goes; one undo step named `editor.undo.deleteImage` (Cut: `editor.undo.cut`) |
| IM-6 | an image finishing loading | **Hard** | Replaced in place: visible text, selection, typing style and undo kept, with no scroll jump when the picture is above the viewport |
| IM-7, IM-9 | decoding; late arrival | Care | Decoded at the displayed size and not again when others arrive; images arriving after the person moved on still go where placed and leave caret, focus and scrolling alone |
| IM-8 | spacing | Care | As much room below an image as above |

#### U. Undo and redo

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| U-1 | Ctrl+Z, Ctrl+Y | **Hard** | Every change the editor makes itself is one undo step that restores text, selection and view exactly; Redo repeats it. The control offers undo groups and a limit but no names and no way to inspect the stack (D31): exactness needs an app-owned stack; the names are kept only for Narrator announcements, since the Edit menu says plain Undo and Redo on Windows |
| U-2 | typing | Care | Typing grouped as usual; the editor's own change within one key press is a separate step |
| U-3, U-4, U-5 | | App | 100 steps; opening another entry clears undo; a change from elsewhere clears it; zoom does not |
| U-6 | Ctrl+Z with focus in the list | Care | Ctrl+Z acts on the scope that has focus: the editor's history in the text, the window's history (Pin entry, Delete entry, journal moves) elsewhere. Undoing a window step leaves the entry scrolled where it is |
| U-7, U-8 | after Undo or Redo; several images | Care, App | Visible text and saved entry are the same; one step for several inserted images |

#### X. Changes from elsewhere

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| X-1, X-3, X-4, X-5 | sync | App | Replace the shown text, selection stays where it fits; rebase edits to different blocks from both sides; typing over an unseen change keeps both versions for review; leaving an entry without typing never overwrites the other device's version |
| X-2 | sync while composing | Care | The change waits for `TextCompositionEnded`, then both are kept, block by block |

#### V. Viewing and scrolling while writing

| Rules | Windows trigger | Rating | What is needed |
| --- | --- | --- | --- |
| V-1, V-4 | the touch keyboard | Care | The pane's bottom inset grows by the keyboard's height so the line being typed (and the line after an image is inserted) stays above it |
| V-2 | typing, editor's own edits | Care | Two lines of room below the caret, never more than a quarter of the pane; the control scrolls the caret into view by itself but not with that room |
| V-3 | Ctrl+F | App | The find bar opens above the entry and never covers the first line |
| V-5 | placeholders, appearance changes | Care | Loading and unavailable placeholders stay readable at the largest sizes; appearance changes keep selection and undo; header growth keeps the reading position |

### The hard rules, together

1. **B-6, joins take the first line's paragraph.** Paragraph format lives with the paragraph mark in a rich edit control, so the native join does the opposite. Every joining edit needs interception.
2. **M-1 and M-16, byte-exact blocks and identities.** No change range and no paragraph identity from the control.
3. **U-1, K-3, K-4, B-4, S-4: undo with exact restoration and two-step conversions** (the step names are for announcements). Needs an app-owned undo stack or very careful group handling; the control has neither names nor inspection.
4. **Tables (TB, BI-3, N-15).** Blocked on `RichEditBox`: read-only grids in Spike A (D33), native in Spike B.
5. **C-3 and C-6, checkboxes** in an overlay that never steals focus and never drifts.
6. **G-5 and G-6, marker font and Narrator semantics** for markers the control draws.
7. **SP-1, spelling off in code** (control-wide switch only).
8. **PA-4, converting other apps' formatted text** into blocks (large but portable).
9. **IM-6, images arriving without moving the text** under the reader.

## Layout at each window width

Not applicable. The rules have no layout of their own; the visual consequences (list columns, checkbox positions, typing room) are in [entry-editor](../screens/entry-editor.md).

## Commands and shortcuts

The commands are listed in [commands.md](../commands.md), Editor. The keys the rules use are in the table above.

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `format-increase-indent`, `format-decrease-indent` | Format menu; the formatting bar | Ctrl+M, Ctrl+Shift+M (Tab, Shift+Tab in an item) | By I-1 to I-15 |
| `format-mark-checked` | Format menu | Ctrl+Shift+Enter | The caret is in a checklist item (C-2) |
| `table-next-cell`, `table-previous-cell`, `table-cell-below` | Tab, Shift+Tab, Enter in a cell | as in commands.md | A cell is being edited (TB-3, N-15) |
| `exit-code-block` | The formatting bar's overflow menu; Down at the end of a code block | Down | The caret is in a code block |
| `edit-text`, `paste-and-match-style` | Edit menu; the context menu | Ctrl+X, Ctrl+C, Ctrl+V, Ctrl+A, Ctrl+Shift+V | The PA rules |
| `undo`, `redo` | Edit menu | Ctrl+Z, Ctrl+Y | The U rules |

## Copy differences

The undo step names (`editor.undo.*`) and announcements (`editor.announce.*`) are sentence case on Windows ("Block quote", "Decrease indent"; [platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). `editor.announce.savedToPhotos` is not used. No other differences.

## Accessibility

- Every conversion and structure change is announced by notification event (`editor.announce.*`, `editor.announce.level`), because the change is not otherwise visible to a screen reader ([11](../platform.md#11-progress-and-announcements)): K-5, B-4, I-14, F-2's Bold state, view modes, images added, copied and deleted.
- Markers are never characters, so Narrator, find and copy read only what was written (G-6); the kind, level and number of an item come through automation properties.
- No rule traps the keyboard: F6 and Shift+F6 leave the editor, and Tab types a tab or indents only where the spec says so.

## Different by design

- **Key names and chords** are Windows': Enter, Backspace, Ctrl+Backspace for a word, Ctrl+M for Indent, Ctrl+Shift+Enter for Mark as checked. Command-Backspace has no equivalent.
- **Ctrl+Z scopes** by focus, so the list and the editor each have their history, where the Mac shares one chain ([flows/editing-rules](../../../flows/editing-rules.md), U-6).
- **Spelling in code** may remain active where the control cannot switch it off per range (SP-1).
- **No smart quotes and dashes**: Windows text controls do not substitute them.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D30 (editor control), D31 (undo model), D32 (how Narrator reads the editor), D33 (tables in version 1), D34 (text keys the spec does not define), D35 (spell check in code), D36 (clipboard format).
