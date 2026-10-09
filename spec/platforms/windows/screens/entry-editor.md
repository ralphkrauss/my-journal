---
id: entry-editor
title: Entry editor (Windows)
spec: screens/entry-editor.md
features: [entry-title, entry-body, autosave, save-failure-recovery, inline-formatting, paragraph-styles, lists, checklists, list-indentation, block-quotes, code-blocks, horizontal-rules, tables, links, inert-links, insert-image, image-actions, image-descriptions, image-placeholders, markdown-as-you-type, source-view, paste-and-drop, copy-to-other-apps, undo-redo, find-in-entry, text-size, spelling-and-substitutions, template-suggestion, entry-actions, change-entry-date, move-entry, pin-entry, save-as-template, delete-entry, version-history, kept-both-notice, read-only-newer-content, source-only-entry, editor-only, writing-controls, writing-paused-notice, previous-next-entry]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/rich-edit-box
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.richeditbox
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.text.richedittextdocument
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.text.itextrange.insertimage
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.disabledformattingaccelerators
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.richeditbox.paste
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.richeditbox.textcompositionstarted
  - https://learn.microsoft.com/en-us/uwp/api/windows.ui.text.markertype
  - https://learn.microsoft.com/en-us/windows/apps/develop/input/custom-text-input
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/microsoft-edge/webview2/
  - https://learn.microsoft.com/en-us/windows/apps/design/input/text-scaling
---

# Entry editor (Windows)

Where an entry or template is written and read: a title and a body of rich text stored as Markdown. This is the most important mapping file for Windows, because the body needs an editing control and the platform's rich text control was not built for this document model. [platform.md, 1 and 34](../platform.md#34-open-questions) list the choice as two spikes run in parallel; this file states what the control must do, how each candidate measures up, and the written pass and fail criteria of [the spikes](#the-spikes). The rule-by-rule list is in [flows/editing-rules](../flows/editing-rules.md). Behaviour, states and copy keys are the spec's [entry-editor](../../../screens/entry-editor.md).

## Controls

### Page structure

The editor pane is a `Grid` of rows, top to bottom. Everything inside the pane is centred in a column of at most 760 epx with 24 epx margins (12 at small width). The formatting bar, when shown, spans the pane under the editor header.

| Row | Spec element | Control | Notes |
| --- | --- | --- | --- |
| 0 | Formatting bar (only while shown) | A `CommandBar` under the editor header | [format-sheet](format-sheet.md). Hidden by default; the Formatting button and View ▸ Formatting show it |
| 1 | Find bar | The app's own find bar, below | Opens above everything in the pane and pushes the rest down; it never covers the first line |
| 2 | Notices above the writing | A vertical `StackPanel` of `InfoBar`s, each only in its state | Order below |
| 3 | Title | A multi-line `TextBox` in the writing style (below) | Placeholder `editor.title.placeholder`; `AutomationProperties.Name` `editor.title.accessibilityLabel` |
| 4 | Editing note | `TextBlock`, `Caption`, secondary | `messages.error.unsupportedFormat` or `messages.unavailable.markdownSource`; only when the entry cannot be edited normally |
| 5 | Image import notice | `InfoBar` Informational with an indeterminate `ProgressBar` in its content and a Stop `Button` | `editor.imageImport.adding` or `editor.imageImport.addingSeveral`, `editor.imageImport.stop`; appears after 0.5 s; appears and leaves without motion when reduced motion is on |
| 6 | Body | The editing control, below | `AutomationProperties.Name` `editor.body.accessibilityLabel`; scrolls on its own, the title and notices stay above it |
| over 6 | Empty-body placeholder | `PlaceholderText` `editor.body.placeholder`, or, when a template can be used, an overlay (below) | |
| over 6 | Decorations | The overlay layer (below) | Checkboxes, quote bars, code fills, rules, tables, find highlights |

The command bar of the editor header (Formatting, Insert image, Entry actions) belongs to the shell: [library-window](library-window.md). Sync status is in the title bar; Show editor only and View source are View-menu commands.

### Notices (the `InfoBar`s of row 2)

All are inline, non-modal and not closable ([9.1](../platform.md#91-notices)); each has its icon, so severity is never colour alone. A changed message is not announced, so a changed state closes the bar and opens a new one, debounced by half a second.

| Order | Notice | Severity | Message | Action |
| --- | --- | --- | --- | --- |
| 1 | Save failure | Error | Title `messages.save.notSaved`; while retrying `messages.save.saving` with an indeterminate `ProgressBar` in the content and the action disabled | `ActionButton` `common.tryAgain` |
| 2 | Writing paused (library being replaced; the entry is read-only meanwhile) | Informational | `messages.writingPaused.connecting` (only after 1 s), `messages.writingPaused.connectionFailed` | None: Show Connection is not offered because the flow's page is modal over the only window. `messages.writingPaused.encrypting` is never shown: Windows runs no encryption |
| 3 | Recovery or unavailable | Informational | [recently-deleted](recently-deleted.md), [unavailable-content](unavailable-content.md) | As those files |
| 4 | Other version kept | Informational, closable | `messages.conflict.kept.notice.entry`, `.entryNewer`, `.template` or `.templateNewer`; a held version shows `messages.conflict.kept.noticeUpdate`; the entry stays editable | `ActionButton` `messages.conflict.kept.showOther`; the close button is `common.dismiss` ([kept-version-notice](kept-version-notice.md)) |

At 200% text size or more, a recovery or notice bar is capped at half the pane's height and scrolls.

### Title

`TextBox`, `TextWrapping` Wrap, `AcceptsReturn` true so that a pasted title keeps its line breaks (T-2), with Enter handled in `PreviewKeyDown` to move focus to the body (and while an input method composes, Enter confirms the composition: `TextCompositionStarted` and `TextCompositionEnded` track it, T-1). `FontSize` 1.75 × the body size, SemiBold. A new entry opens with the title focused and its text selected (T-5); from a template, Enter in the title moves to the template's first empty paragraph.

The writing style applies to the title and the body: no border, no background and no focus underline in every state (the caret and selection are the focus indication), `Padding` zero so that the title's first letter and the body's first letter start at the same x (T-4), selection and caret in the system colours. A read-only entry uses `IsReadOnly`, not `IsEnabled` false, so the text stays focusable, selectable and readable ([Different by design](#different-by-design)).

### The body control

The body is the one control whose choice is not yet made. This section is the requirement list and the comparison that the two spikes run against.

#### What the control must do

Every row is a requirement; the rule ids are in [flows/editing-rules](../flows/editing-rules.md). "Must" rows decide the choice; "should" rows may be met with a documented difference.

| # | Requirement | Level | Source |
| --- | --- | --- | --- |
| R1 | **Markdown round trip.** Markdown the person did not touch keeps its exact bytes; editing one block rewrites only that block; blocks keep identities; a document this version cannot fully read is read-only and byte-exact; Markdown the editor cannot show as blocks opens in source view. The control never holds the Markdown: the portable document model does, and the control is a view of it | Must | M-1 to M-16 |
| R2 | **Lists with drawn markers.** Bulleted, numbered and checklist items; markers are never characters of the text (the keyboard, find, copy and Narrator see only what was written); marker inset 18 epx from the body text, list column 1.5 × the text size rounded; wrapped lines start where the item text starts; nesting up to 6 levels, a nested marker under its parent's text, stops moving in after 160 epx; numbers right: widest-number column widening; marker font is the paragraph's regular font, not the first word's bold or code font | Must | G-1 to G-9, I-3 |
| R3 | **Checklist boxes**: a native-looking check box on the first line of an item, toggled by click or touch as one undo step without moving the caret or taking focus, in place at every scroll position, disabled in read-only entries, exposed to Narrator as a toggle with the item text as its name and the state as its value | Must | C-3 to C-6 |
| R4 | **Indent control.** Tab, Shift+Tab, Ctrl+M and Ctrl+Shift+M act on list items by the app's rules and nothing else; the control's own indentation and list commands are off | Must | I-1 to I-15 |
| R5 | **Inline images.** An image on a line of its own at its natural size scaled to fit, or small inside a line; placeholders (`editor.image.loading`, `editor.image.unavailable`, `editor.image.remote`) replaced in place without moving the visible text or the selection; the description is its alternative text and its Narrator name; decoded at the displayed size; selectable as one unit with a visible selection; context menu on it; one undo step for several | Must | IM-1 to IM-9 |
| R6 | **Tables.** A hairline grid with every cell editable in place; header row semibold; equal column widths of at least 7 × the text size, scrolling sideways when more; Tab, Shift+Tab and Enter move between cells; cell menus; typing in a cell is one undo step in the entry's single history; Narrator reads the grid with row and column | **Must for both spikes** (owner decision, 2026-10-07: tables are fully editable in place, exactly like on the Mac; the read-only grid of D33 is withdrawn). A spike that cannot do it fails | TB-1 to TB-7, BI-3 |
| R7 | **Links.** http, https and mailto shown as links (underlined, link colour); other destinations shown as plain text and kept unchanged; link titles kept; opening a link by Ctrl+click and from the context menu | Must | L-1 to L-6 |
| R8 | **Undo.** At least 100 steps; each editor-made change one step that restores text, selection and view exactly; typing grouped as usual; an IME composition is never split; steps keep their names for Narrator announcements while the Edit menu says plain Undo and Redo on Windows (D31); undo survives view switching and zoom; opening another entry clears it | Must | U-1 to U-8 |
| R9 | **Spell checking** with the Windows spell checker for prose, following the person's Typing settings; **off** inside code blocks, inline code, raw HTML and source view | Must (prose), should (per range) | SP-1, SP-2 |
| R10 | **Input methods.** IME composition through the Text Services Framework for East Asian languages and others; the app can tell when a composition is open and holds back its own edits (Markdown conversion, change from elsewhere, title Enter, chooser Esc); handwriting, voice typing (Win+H), the emoji panel (Win+.) and the touch keyboard work | Must | K, X-2, B-8, G-7 |
| R11 | **Narrator and UI Automation.** The text pattern with caret and selection; headings with levels; list items with kind, level and number; checkboxes as toggles; images with their descriptions; the table as a grid; announcements for style changes; nothing of the entry in the automation tree while locked. **A ship gate**: the Narrator walkthrough script (a list, a checklist, a heading, an image with its description, a table) passes on a real PC, whichever control wins | Must | G-6, [24](../platform.md#24-accessibility) |
| R12 | **Complete keyboard ownership.** Every key the spec binds is handled by the app first; the control's own accelerators for alignment, line spacing, font size, bullets, super and subscript do nothing; no keyboard trap; AltGr (Ctrl+Alt) characters always type, which is why no shortcut uses Ctrl+Alt: headings are Ctrl+Shift+1 to 6 ([7](../platform.md#7-keyboard-shortcuts), rule 3), tested on the US, Belgian AZERTY, German QWERTZ and Polish programmer layouts | Must | [7](../platform.md#7-keyboard-shortcuts) rules 3, 6 and 8 |
| R13 | **Clipboard and drag and drop** owned by the app: copy and cut put the entry's own Markdown, a text list form and the picture's original on the clipboard; paste converts other apps' content to the entry's blocks by the paste rules and never takes fonts or colours; drops land at the point where they are dropped | Must | PA-1 to PA-15 |
| R14 | **Decorations.** Quote bar, code and raw HTML fill, inline code fill, rules, header row, all in theme colours and correct in the four contrast themes; they scroll with the text | Must | Spec, How blocks look |
| R15 | **Size.** Body 16 epx by default, Zoom 12 to 30 as a relative factor on top of the system text size, which is applied once and never twice ([22](../platform.md#22-typography)); line spacing 3 epx and 10 epx after a paragraph; headings 1.4, 1.2, 1.1 and 1.0 × the size, SemiBold | Must | [22](../platform.md#22-typography) |
| R16 | **Source view in the same control**: monospaced, unstyled, exact; switching keeps the caret on the same character and the caret's line at the same height; one undo step per switch | Must | S-1 to S-7 |
| R17 | **Performance.** Typing latency unaffected by a long entry (50,000 characters, 200 pictures); pictures decoded at displayed size; opening an entry does not block the UI | Must | IM-7 |
| R18 | **Find** in the body with highlights of all matches, next and previous, replace and replace all as one undo step | Should | `find` |
| R19 | **Lock.** On lock the control is released: its text, undo history and clipboard hooks are cleared, so nothing is readable by automation or magnifiers | Must | [13](../platform.md#13-device-authentication-and-app-lock) |
| R20 | **Typing room.** Two lines of room below the caret (at most a quarter of the editor's height) after typing and after the editor's own edits; the line being typed stays above the touch keyboard | Should | V-1, V-2 |

#### The candidates

| Requirement | `RichEditBox` plus an app layer | A web editor in `WebView2` | A custom WinUI control |
| --- | --- | --- | --- |
| R1 Markdown model | Adapter: the control gives no per-edit change range and no paragraph identity, so the app diffs the text and paragraph formats after every change and maps it to blocks | Native fit: block-structured editors keep a document tree with node identity and serialise to Markdown | Native fit: the control is a view of the block model, as the Apple app's is |
| R2 Lists | Native lists (bullet, Arabic numbering, nesting, start number, markers drawn) are a good match; marker inset, column width and marker font are properties to prove | Native, styled with CSS | Own layout: all of it is written |
| R3 Checkboxes | No: `MarkerType` has no checkbox. Overlay `CheckBox` elements positioned from range rectangles, synchronised with scrolling | Native in the editor schema | Own drawing and hit-testing |
| R4 Indent | Adapter: handled in `PreviewKeyDown`, applied through the paragraph format | Native | Own |
| R5 Images | `InsertImage` places an image object in the text with alternative text; sizes, placeholders and selection visuals to prove | Native | Own |
| R6 Tables | **Blocked**: no table API is exposed to the control's users. The overlay editor (cells over reserved space, with the undo and selection problems that causes) has no plan yet: the owner's decision of 2026-10-07 withdraws D33's read-only grid, so for this candidate editing tables in place needs a design the spike must prove, or the candidate fails R6 | Native with a table module | Own |
| R7 Links | Adapter: link property on ranges | Native | Own |
| R8 Undo | Control has grouping (`BeginUndoGroup`, `EndUndoGroup`), `UndoLimit`, `Undo`, `Redo`, `CanUndo` and `CanRedo`, but no step names and no inspection. Exact snapshots and cross-block exactness (overlay check boxes) need an app-owned undo stack (D31); the names are only for announcements | Editor's history module with names | Own |
| R9 Spelling | Native, **control-wide only**: one `IsSpellCheckEnabled` switch for the whole control (D35) | Per element (`spellcheck` attribute) | Own use of the Windows spell checker API; per range is easy |
| R10 IME | Native; composition events `TextCompositionStarted`, `TextCompositionChanged` and `TextCompositionEnded` exist | Native in Chromium; the XAML shell needs the same events forwarded | Needs the core text API (`CoreTextEditContext`) and a lot of care; the common source of bugs |
| R11 Narrator | Native text pattern; drawn markers and overlay check boxes are not in it, so a derived automation peer (a `RichEditBox` subclass supplying a `RichEditBoxAutomationPeer`) is budgeted in the spike and the gate is the walkthrough script | Chromium's accessibility tree, already good for lists, check boxes, headings, tables and images, with a web-document feel in Narrator and an extra process | Own text provider: full control, full cost |
| R12 Keys | `DisabledFormattingAccelerators` covers only Ctrl+B, Ctrl+I and Ctrl+U; everything else is a `PreviewKeyDown` deny-list | Keys go to the web page first; XAML accelerators need forwarding | Own: nothing is bound by default |
| R13 Clipboard | Native events: `Paste` fires before insertion and can be handled; copy and cut events can be handled; drag and drop events exist | Web clipboard events, with the browser's rich paste to override | Own |
| R14 Decorations | Overlay layer using range rectangles | CSS | Own drawing |
| R15 Size | Native: character size, paragraph spacing | CSS; must mirror text scaling and contrast themes | Own |
| R16 Source view | Same control, text replaced in one undo group, spell check off | A second mode of the editor or a code editor | Own |
| R17 Performance | Good for prose; many overlays and images need testing | Good | Depends on virtualised layout |
| R18 Find | Range search is native (`FindText`); highlights are overlays | Page search or editor decorations | Own |
| R19 Lock | Clear document and history, unload control | Destroy the `WebView2`; the process goes away | Dispose |
| R20 Typing room | Via the control's scroll viewer and `ScrollIntoView`; touch keyboard inset by the app | Native with scroll margin | Own |
| Other | Microsoft's own control, no new dependency, text feels like Windows | A second runtime and a bundled JavaScript editor with its dependency tree (needs a documented reason, a lockfile and a supply-chain review), keyboard and focus handoff between two UI stacks, theme and text size mirrored by hand | Months of work, the highest accessibility and IME risk |

#### The spikes

**Run Spike A and Spike B in parallel, time-boxed (two to three weeks each), against one shared scorecard. Do not defer B until A fails.** By this file's own candidates table, `RichEditBox` is rated Blocked for tables and not under the app's control for Narrator before any code is written, and the architecture it needs (the control never holds the Markdown, the app diffs text and paragraph formats after every change, an app-owned undo stack, overlay check boxes, find highlights and code fills positioned from range rectangles) is a second editor built on a first. Text can change without key events (an input method, voice typing, handwriting, autocorrect, touch suggestions, drag and drop, the control's own spelling replacements), and each of those paths must be reconciled with the model: that is the likeliest source of silent corruption in the product. Microsoft's own precedents are mixed (Notepad keeps a native edit control; the new Outlook and Loop use web editors), so "native" does not require `RichEditBox`.

- **Spike A:** `RichEditBox` plus an overlay layer, behind `IEditorSurface` (set blocks, apply an edit, read selection, caret rectangle, range rectangles, composition state, events), with a custom automation peer.
- **Spike B:** a `WebView2` block editor with a document tree that has node identity and serialises to Markdown, with its dependencies pinned in a lockfile and reviewed for supply-chain risk (a documented reason, [AGENTS.md](../../../../AGENTS.md)); keyboard and focus hand-off between the two UI stacks, and theme, contrast and text size mirrored from the system.
- **Spike C** (a custom WinUI control) stays on paper and is scoped only if both fail.
- The portable document model and the editing rules stay outside the control, so the outcome changes only the surface. `IEditorSurface` is kept for that reason.

**The scorecard** (the same corpus and devices for both): Narrator on a real PC with the walkthrough script; a Japanese input method; 200% display scale and 225% text size; a 50,000-character entry with 200 pictures; the Markdown fidelity corpus; AltGr typing on the US, Belgian AZERTY, German QWERTZ and Polish programmer layouts; the four contrast themes.

**Pass criteria** (each is pass or fail, with the measurement written down):

| Requirement | Pass |
| --- | --- |
| R1 | Open every entry of the Markdown fidelity corpus, make one edit in each block kind, and every other block stays byte-identical (the spec's M rules as tests) |
| R2 | Lists with 6 nesting levels, numbering after Enter, indent and outdent, correct at 12, 16 and 30 epx, with the marker in the regular font after a bold first word |
| R3 | 200 check boxes stay aligned while scrolling, typing, zooming and resizing at 200% display scale; a click toggles as one undo step without moving the caret |
| R5 | 100 pictures: placeholders replaced in place with the caret and scroll position unchanged |
| R8 | Undo and redo of 100 mixed edits restore text, selection and view exactly |
| R10 | Composing in an empty list item, in a heading, and across a change arriving from sync, with a Japanese input method; voice typing, the emoji panel and handwriting insert text |
| R11 | The Narrator walkthrough script passes on a real PC: a list item with its kind and level, a checklist item with its state, a heading with its level, an image with its description, and an editable table read by row and column (both spikes; no read-only grid) |
| R12 | Every chord of [commands](../commands.md) fires its command once in the editor; AltGr characters type on all four layouts; F6 and Shift+F6 leave the editor |
| R15 | Body and heading sizes are correct at 100% and 225% text size (scaled once) and at Zoom 12, 16 and 30 |
| R17 | Typing latency in the 50,000-character entry is not noticeably worse than in an empty one; opening it does not block the UI |
| R6 | Both spikes: a table is edited in place and passes TB-1 to TB-7 including shared undo (owner decision, 2026-10-07) |

**Abandonment criteria, written now:** a spike is dropped if it fails R1 on any byte of the corpus, R3 (Spike A), R10 or R11, or if it cannot be made to leave the editor with F6 and release its content on lock (R19). Both spikes are dropped if they fail R6 (owner decision, 2026-10-07: tables must be editable in place). Spike B is also dropped if its dependency tree cannot be pinned and reviewed, or if theme, contrast and text size cannot follow the system. If both pass, the owner chooses with the scores in hand (the extra runtime and a JavaScript editor in a native app need the owner's agreement, D30); if only one passes, it is the choice; if neither does, Spike C is scoped.

#### Architecture rules for any control

These hold whichever control wins, so the other editor pages can be written now.

- The document model, the Markdown reader and writer and the editing rules (every N, B, I, C, K, BI, TB, L and PA rule) are portable code shared with the other native clients and tested once with the conformance cases of the spec. The control only reports key presses, composition state and selection, and applies the edit the rules return as one undo step.
- The rules run **synchronously in the key handler**: a burst of keystrokes ("- Milk", Enter, "Eggs" at any speed) keeps every letter in order and in its own item (N-12), so no conversion is deferred to a later event.
- Edits the app makes go through one method that opens an undo group, applies the change, restores the selection and closes the group.
- No control event may write Markdown while an input method composes; changes from elsewhere wait for the end of the composition ([flows/editing-rules](../flows/editing-rules.md), X).
- The control is released on lock and on leaving the entry; nothing about its content outlives it.

### Blocks, as drawn

Sizes are relative to the body size *s* (default 16 epx). The spec's table ([How blocks look](../../../screens/entry-editor.md#how-blocks-look)) is followed row by row; where Windows has a different way, it is here.

| Block | Windows realisation on the preferred control | Check in the spike |
| --- | --- | --- |
| Paragraph | Character size *s*; paragraph spacing 10 epx after; extra line spacing 3 epx through the paragraph's line spacing rule | The 3 epx extra matches the Apple measure at 12, 16 and 30 |
| Headings 1 to 3, and 4 to 6 | SemiBold weight (a font weight, not the Bold effect) at 1.4, 1.2, 1.1 and 1.0 × *s*. Because the heading's weight is its style, Bold shows Off in a heading (F-2) | Weight 600 and Bold (700) are told apart by the app |
| Bulleted, numbered, checklist item | Native list formatting for bullets and numbers; for checklist items a list-less paragraph with the same left indent and an overlay box. Marker inset 18 epx, text column 1.5 × *s* rounded, level step one column | Marker font, tab stop and numbered column widening |
| Checkbox | The standard WinUI `CheckBox` template drawn small (below 14), regular (to 20) and large (above) in an overlay, unchecked as outline, checked with accent fill; touch target 40 × 40 epx from the column start; not dimmed or struck through when checked; disabled look in read-only entries | Alignment with the first line's capitals |
| Block quote | Left indent of 18 epx; a 3 epx rounded bar in `TextFillColorTertiaryBrush`, drawn in the overlay at the height of the quote's lines | Bar follows wrapping and zoom |
| Code block and raw HTML block | Cascadia Mono at *s*; paragraph shading in `ControlFillColorSecondaryBrush`-class brush with 10 epx side padding and 6 epx above and below drawn as a rounded (6 epx) overlay rectangle; 12 epx extra after | If the overlay cannot follow edits cleanly, a square character background is the allowed fallback |
| Inline code | Cascadia Mono; character background in the same brush | |
| Horizontal rule | A hairline in `DividerStrokeColorDefaultBrush` across the text width on a line of its own, drawn in the overlay over an empty reserved line | |
| Table | See R6. Cells are edited in place in either spike (owner decision, 2026-10-07): a hairline grid, header row SemiBold, cell text wrapping, columns at least 7 × *s*, sideways scrolling, 12 epx after; an existing table stays byte-exact | Byte-exactness of every table in the corpus |
| Image on its own line | `InsertImage` at natural size (from its resolution, otherwise 96 dpi) scaled to fit the text width, as much room below as above | IM-8 |
| Small image, remote image | At most 120 × 80 epx; a remote image shows `editor.image.remote` and is never downloaded | |
| Image not loaded | A placeholder line in secondary text: `editor.image.loading`, `editor.image.unavailable` or `editor.image.remote` | Replaced in place (IM-6) |
| Link | Underlined, `HyperlinkForegroundBrush`-class colour for http, https and mailto; plain text otherwise | Inert links keep their Markdown |
| Selected picture | The control's object selection, tinted and outlined in the selection colour | Visible in contrast themes |

### Empty-body placeholder and the template link

When no template can be used: the control's `PlaceholderText` `editor.body.placeholder`. When one can (the item is an entry, it can be edited, an editable template exists, the body has no characters and no images, whatever the title), `PlaceholderText` is empty and an overlay `TextBlock` shows `editor.body.placeholder.templatePrefix` followed by a template icon (TwoPage E89A) and a `HyperlinkButton` `editor.body.placeholder.templateLink`, laid out exactly where typed text would begin. The text part is not hit-testable (clicks reach the body); the link opens the [template chooser](template-chooser.md) anchored to it; File ▸ Use a template… opens it too, anchored to the writing area, and is enabled exactly when the link is shown. It disappears with the first character and returns when the body is empty again. Narrator reads the link as `library.templateChooser.useTemplate`.

### Find bar

The app draws its own find bar (Windows has no system one): a `Grid` with a find `TextBox`, previous and next `AppBarButton`s (icons Up E74A and Down E74B), the match position, a close button (Cancel E711), and, for Ctrl+H, a second row with a replace `TextBox` and Replace and Replace all buttons. Enter and Shift+Enter in the box step through matches; F3 and Shift+F3 step from the editor; Esc closes the bar and returns focus to the text. Matches are found with range search and highlighted with overlay rectangles (never with character formats, which would be saved or undone). It searches the body and table cells. Replace is one undo step per use; Replace all is one step. The strings are new Windows copy (B31).

## Layout at each window width

| Width (epx) | Editor pane | Apple equivalent |
| --- | --- | --- |
| Large | At least 439 wide; the text column is at most 760, centred, with 24 margins; notices span the column | Mac detail column |
| Medium | At least 360 wide; same column, 24 margins | iPad regular width |
| Small | The entry is its own page; margins 12; the header command bar shows Formatting, Insert image and Entry actions; the formatting bar, when shown, scrolls its overflow and the selection mini-toolbar is the quick route | iPhone entry page without the floating capsule |
| 200% text size or more | One layout narrower; notices stack vertically with their buttons below the text; the system text scale is applied once by the control, and the Zoom commands are a relative factor on top ([22](../platform.md#22-typography)) | Accessibility text sizes |

- **Touch keyboard.** When the touch keyboard shows, the editor pane's bottom inset grows by the covered height (from the input pane's occluded rectangle) so that the line being typed stays visible above it (V-1). With a hardware keyboard nothing changes.
- **Typing room.** In the large and medium layouts two lines of room are kept below the line being typed, never more than a quarter of the pane's height, also after the editor's own edits (Enter in a list, shortcuts, paste, undo) (V-2).
- **Zoom.** Ctrl+Plus, Ctrl+Minus, Ctrl+0, Ctrl+mouse wheel and touchpad pinch change the body size by 1 epx between 12 and 30; the control's own wheel zoom is turned off and the app handles the wheel. Zoom keeps selection and undo.

## Commands and shortcuts

Placement and shortcuts are in [commands.md](../commands.md) (Editor). The page adds:

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `show-formatting` | Toggle button in the editor header; View ▸ Formatting | as in commands.md | The open item can be edited; the bar stays but its buttons are disabled if the entry becomes uneditable |
| `insert-image-choose-file` | Insert image button; Format ▸ Insert ▸ Image… | as in commands.md | Entry editable |
| `insert-link` | Format ▸ Insert ▸ Link… | Ctrl+K | The body or a cell has focus; [link-editor](link-editor.md) |
| `toggle-checkbox` | Click or touch a checkbox; Mark as checked is the keyboard route | none | Entry editable; one undo step, caret stays |
| `view-source` | View menu | Ctrl+Shift+U | [source-view](../flows/source-view.md) |
| `entry-actions` | Editor header More | as in commands.md | An entry or template is open |
| `find`, `find-in-entry` | Edit menu; the find bar | Ctrl+F, Ctrl+H, F3, Shift+F3 | An entry or template is open, including read-only ones |
| `use-a-template` | The placeholder link | none | The template suggestion is shown |
| `show-other-version`, `dismiss-kept-notice` | The other-version notice | none | The notice is shown |
| `format-*` | Format menu; the formatting bar; the selection mini-toolbar | as in commands.md | [format-sheet](format-sheet.md) |

- Tab in the body types a tab character in a paragraph and acts as Indent in a list item or code ([flows/editing-rules](../flows/editing-rules.md), I-12); F6 and Shift+F6 always leave the editor.
- The control's own accelerators for alignment, line spacing, bullets, font size, super and subscript, and its own Ctrl+wheel zoom are turned off ([7](../platform.md#7-keyboard-shortcuts), rule 6): `DisabledFormattingAccelerators` is set to All and `PreviewKeyDown` swallows the chords with which the control would apply such a format; other chords (Ctrl+Backspace, Ctrl+arrows, Ctrl+Home and the like) keep the control's behaviour (D34), and AltGr character input is never touched.
- Delete in the editor deletes text; it never deletes the entry (the list owns that key).

## Copy differences

Sentence case on all labels ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)); notice, menu and dialog titles follow it. Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `messages.writingPaused.connecting`, `messages.writingPaused.connectionFailed` | … this Mac … | … this PC … | vocabulary (platform.md, 12.3) |
| `messages.writingPaused.showConnection` | Show Connection | not shown | removed (the flow's page is modal) |
| `editor.imageDescriptions.intro` | … people using VoiceOver. | … people using Narrator. | vocabulary; see B28 |
| `editor.imageImport.cause.unavailable` | They may still be downloading from iCloud. Try again later. | They may still be downloading. Try again later. | vocabulary (platform.md, 12.3) |
| New Windows-only keys for the find bar (proposed names: editor, find group) | none | Find in entry, Replace, Previous match, Next match, Replace, Replace all, "{current} of {total}", No matches, Close find | new strings; see B31 |

## Accessibility

- **Names.** Title: `editor.title.accessibilityLabel`. Body: `editor.body.accessibilityLabel`. The placeholder link: `library.templateChooser.useTemplate`.
- **Structure for Narrator** (requirement R11, the model for any control): a heading carries its level; a list item carries its kind and nesting level through its text attributes, never through characters: "Bullet", `editor.list.number` (the number it shows, also after a move), `editor.list.checkboxUnchecked` or `editor.list.checkboxChecked`, `editor.list.quote`; an empty checklist item reads `editor.list.emptyChecklistItem`. A checkbox is a toggle named by its item's text with the value `editor.list.checked` or `editor.list.unchecked`. A picture is read as its description, or `editor.image.accessibilityLabel`; when not shown, the status (`editor.image.loadingAccessibility`, `editor.image.unavailableAccessibility`, `editor.image.remoteAccessibility`) first. The table is a grid named `editor.table.accessibilityLabel`, each cell `editor.table.cell.header` or `editor.table.cell.row`. Whether the control lets the app set these is the ship gate of D32: a derived automation peer on `RichEditBox` (Spike A) or Chromium's accessibility tree (Spike B), proved by the walkthrough script on a real PC.
- **Checkboxes are not tab stops**, as on the Mac: Tab stays a tab or an indent; Mark as checked (Ctrl+Shift+Enter) is the keyboard route, and Narrator users reach a box through its list item and the toggle pattern.
- **Announcements** by notification event: style changes from shortcuts and Backspace (`editor.announce.*`), the new indentation level (`editor.announce.level`), view mode (`editor.announce.source`, `editor.announce.preview`), images added, copied and deleted (`editor.announce.imageAdded`, `editor.announce.imagesAdded`, `editor.announce.copied`, `editor.announce.imageDeleted`). Saving announces nothing. `ImportantMostRecent` for results, `MostRecent` for routine ones ([11](../platform.md#11-progress-and-announcements)). `editor.announce.savedToPhotos` is not used.
- **Focus.** Opening an entry from the list keeps focus in the list until Enter or F6; a new entry focuses its title. The formatting bar's buttons do not take keyboard focus when clicked, so the text keeps its caret and selection; F6 moves to the bar and on to the editor. After Undo or Redo the text and the saved entry are the same.
- **Contrast and text size.** Checkboxes, quote bars, code fills, rules, table lines and find highlights use system colours in contrast themes and never rest on colour alone. At 225% text size the notices stack, the body size scales once, and nothing is truncated.
- **Languages.** The entry's `Language` is set for Narrator; spell checking follows the Windows language list.

## Different by design

- **Notices are `InfoBar`s**, inline above the title, not tinted bands. The save-failure notice is the first one, above the title, because a notice below a scrolling body can be off screen; the Mac puts it below the body.
- **No Done, no floating writing controls, no reading and writing states.** Windows has no on-screen-keyboard accessory model; the header command bar carries Formatting and Insert image for every input method. Touch keyboards are handled by the inset above.
- **Formatting is a toggleable bar under the editor header, plus the text control's selection mini-toolbar**, not a popover or a panel in place of the keyboard ([format-sheet](format-sheet.md)): the Windows pattern of Notepad, Word, OneNote and Mail.
- **View source and Show editor only are View-menu commands**, not header buttons, so the busiest bar has two icons fewer.
- **Read-only entries use `IsReadOnly`** for the title, so the text stays selectable and Narrator can read it, instead of a disabled field with disabled contrast.
- **Links** open with Ctrl+click or the context menu (Open link, Copy link); a plain click places the caret. Typed addresses are never linked automatically (L-6).
- **Find bar** is the app's own, with Replace (Ctrl+H), because Windows has no system find bar.
- **Spelling is the Windows checker's.** There is no Substitutions or Writing Tools equivalent; code and source stay literal where the control allows (D35).
- **Block visuals** use Windows brushes and Cascadia Mono; corner radii of the code fill are a target, with square fills allowed if the overlay cannot follow edits.
- **Undo is app-owned** if the spike confirms it (D31), but the Edit menu says plain Undo and Redo, as Word, Notepad and OneNote do; the step names such as `editor.undo.typing` are used for Narrator announcements only.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D20 (formatting bar), D30 (editor control and the parallel spikes), D31 (undo model), D32 (how Narrator reads the editor, a ship gate), D33 (tables in version 1), D34 (text keys the spec does not define), D35 (spell check in code), D36 (clipboard format), D37 (find and replace), B31 (find bar strings), B28 (Apple names in sentences).
