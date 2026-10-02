# Feedback stabilization — 2026-09-23

Design for the owner's 2026-09-23 feedback on the Mac and iPhone apps. The Mac app is the reference; the iPhone app follows it with stacked navigation. Apple Notes is the interaction model, not a feature list.

## Observed problems (runtime evidence, not source reading)

- **iPhone navigation.** A 60 fps recording of journal → entries → editor → back shows: the Journals toolbar (New Journal, Settings) disappears the instant a push starts, leaving an empty glass capsule during the transition, and reappears only after the pop finishes. The entries screen's journal menu can render an empty capsule. Rows are plain buttons: no tap highlight, and the push waits for an asynchronous save before it starts. Leaving the editor with a pending save swaps the system back button for a custom one, which also disables the edge swipe, and the pop waits for the save.
- **Mac divider.** The detail column's titlebar separator (a hard line at the toolbar's bottom edge) toggles depending on which views AppKit last associated with the split item. It appears after switching entries or toggling source, and disappears after other selections.
- **Mac source button.** The button is a 32×28 AppKit view inside a 37×52 toolbar item. Clicks on the rest of the item reach the title bar: a quick second click zooms the window, and a single click does nothing. The View menu command routes through a path that silently gives up unless the text view is first responder.
- **Markdown source.** Paragraphs edited in the rich view are written with every punctuation character escaped (`Before unchanged\.`, `5\-6 \(maybe\)\!`). Source mode shows this noise and it is stored that way.

## 1. iPhone stacked navigation

Layout is unchanged: Journals → entries → editor, as in Notes.

- Journal rows, collection rows and entry rows are standard `NavigationLink(value:)` rows. The system provides the chevron, the pressed highlight, the push, and the deselection animation that tracks an interactive swipe back. No row keeps a persistent selection.
- Routes carry their destination: `collection(JournalDestination)` and `entry(UUID)`.
- **Push.** When the current draft is already saved (the normal case), the model switches journal/entry synchronously in the same update that pushes the screen. The pushed screen is therefore correct in its first frame. Only when a save is genuinely outstanding does the push wait for it (unchanged safety rule: never navigate away from content that failed to save). A failed save keeps the current screen and shows the existing “Couldn’t save changes” alert with Try Again / Export Entry….
- **Pop.** Always immediate and always the system back button and edge swipe. Leaving the editor does not discard anything: the draft stays in the model and autosave continues. If that save fails, the existing alert appears; opening another entry is refused until it succeeds or is exported.
- **Toolbars.** Each screen declares its own toolbar unconditionally; the navigation stack decides which is visible, so items animate with their screen. No `if` inside a `ToolbarItem` (no empty capsules). Journals: New Journal and Settings (top trailing, unchanged); Search and New Entry / Templates in the bottom bar (unchanged). Entries: journal “…” menu only for a single journal.
- iPad regular width keeps the split view and list selection (unchanged).

## 2. iPhone controls parity (confirm, no new controls)

Editor bottom bar: Formatting (textformat), Insert Image, View Source/View Preview, then Templates… and New Entry. Top: back, Done while editing, and “…” Entry Actions (`ellipsis`, same symbol and contents as the Mac entry menu). No Share, Undo/Redo, checklist, or table buttons. The keyboard accessory has Formatting, Insert Image, View Source. Formatting options live only in the shared Formatting popover or sheet, identical to the Mac.

## 3. Mac window and toolbar

- **No divider.** The window's titlebar separator style is `none`, deterministically for all columns. On macOS 26 this matches the flat glass toolbar; the editor never scrolls beneath the toolbar because the title field sits above it.
- **Detail toolbar, left to right:** [Formatting, Insert Image] · flexible space · [Search field] · [View Source/View Preview, Entry Actions “…”] (plus Sync Status only when there is a sync problem or pending sync). Search and the trailing pair are separate glass groups. The trailing pair always sits at the right edge, where the overflow chevron used to appear.
- **Search** stays an expanded, native search field (placeholder “Search <Journal>” / “Search All Entries”, ⌘F focuses it). Width ideal 220 pt, minimum 120 pt.
- **No overflow chevron.** The detail column minimum width is large enough for every item at the search field's minimum width. When the window is narrower than sidebar + list + detail minimums, the sidebar collapses (standard split view behavior) instead of items overflowing.
- Creation actions (Templates…, New Entry) stay in the entries column in every state (already fixed; retained).
- Settings stays at the bottom of the sidebar (owner's choice on 2026-09-23).
- View menu gains the standard Show/Hide Sidebar command (⌃⌘S) that NavigationSplitView apps normally have.

## 4. View Source / View Preview control

- A standard SwiftUI toolbar button (whole item is the hit target, no AppKit subview, no title-bar fall-through). Label and tooltip: “View Source” (symbol `chevron.left.forwardslash.chevron.right`) in preview, “View Preview” (symbol `doc.richtext`) in source. The View menu item uses the same wording and the same action, with no keyboard shortcut added.
- The action does not depend on keyboard focus. It converts the whole editor, maps the selection (below), scrolls it into view, and returns keyboard focus to the editor so typing continues at the same place.
- Disabled when the entry cannot be edited, and disabled in source mode when the Markdown cannot be shown as a preview (tooltip: “Preview isn’t available for this entry”).

## 5. Selection across source and preview

The caret or selection stays on the same characters after switching, in both directions and repeatedly. Syntax that appears or disappears (`**`, `# `, list markers, `❯`/`>`) is skipped: a caret after “un” in “Before **un**changed” stays after “un”. Selections that include syntax shrink to the content. UTF‑16 offsets are used (emoji safe).

## 6. Formatting in source mode

Every Formatting command works in source mode by editing Markdown syntax; nothing is rendered.

- Inline (Bold `**`, Italic `*`, Strikethrough `~~`, Inline Code `` ` ``, Underline `<u></u>`, Link `[text](url)`): wraps the selection; surrounding spaces stay outside the delimiters; a multi-paragraph selection is wrapped per non-empty line. If the selection is already wrapped by that syntax, the command removes it (toggle). With no selection, it inserts an empty pair and places the caret between.
- Paragraph styles (Heading 1–6, Paragraph, Bulleted/Numbered/Task List, Block Quote) replace the line prefix of every touched line; numbered lists count 1., 2., 3. Applied on a blank line between paragraphs, the prefix goes on its own line with blank lines kept around it, so the neighbors do not merge.
- Inserted blocks (Code Block, Horizontal Rule, Table) always get blank-line separation from existing text; the caret goes inside the code block or first table cell.
- Preview mode behavior is unchanged.

## 7. Markdown output

Escaping is minimal and context aware: only characters that would otherwise change meaning are escaped (`\`, `` ` ``, `*`, `[`, `]`, `<`, `~`, `&` before an entity, `_` at a word boundary, `!` before `[`, `|` in tables, and line-start markers such as `#`, `>`, `-`/`+`/`=` runs, and `1.`). “Before unchanged.” is written as-is. Round trip (write → read) must produce identical text and styles; existing stored Markdown is untouched until edited.

## 8. Copy (formatting popover and Format menu)

Popover: B / I / U / S / Inline Code; Heading 1, Heading 2, Heading 3, Paragraph, More Headings ▸ Heading 4–6; Bulleted List, Numbered List, Task List, Block Quote; Decrease/Increase Indent; Insert ▸ Code Block, Horizontal Rule, Table, Link…, Image…. The code-block escape row changes from “Move After Code Block” to “Exit Code Block”. Format menu uses the same names (“Code” becomes “Inline Code”).

## 9. Touch ID / Apple Watch

No UI change. Unlock uses `deviceOwnerAuthenticationWithBiometricsOrCompanion` on macOS 15+ (Watch-only fallback on 13–14). The button reads “Use Touch ID or Apple Watch” on Mac and “Use Touch ID or Face ID” on iPhone. A real fingerprint/Watch unlock needs the owner's hardware interaction.

## Accessibility

Rows keep combined accessibility labels; NavigationLink rows expose the button trait and chevron natively. Toolbar buttons keep labels/tooltips; the source button's label reflects its action. VoiceOver focus returns to the editor after a mode switch. Reduced motion uses system navigation transitions (no custom animation added). Dynamic Type: no fixed heights added.

## States

Empty/no selection: Mac detail shows “Select an Entry”, toolbar items remain in place and disabled. Save failure: existing alert and inline notice, unchanged. Offline/sync: Sync Status only when pending or failing, unchanged copy.

## Revision 1 — response to independent review

**P1-1 Navigation never waits.** A tap pushes at once; a back swipe pops at once. The model changes selection in the same update when no write is outstanding (the normal case). If a write of the current draft is still running (autosave writes each edit locally; this lasts milliseconds), the pushed screen appears immediately and shows its content as soon as the write finishes — the entries list and editor render only for the route they were pushed for, never another journal's or entry's content. Only an actual save failure stops the change: the pushed screen is popped back and the existing save-failure alert appears (“Couldn’t save changes. Keep Journal open.” with Try Again / Export Entry… / OK — copy unchanged from the reviewed save-failure design, so the alert stays consistent everywhere). While that alert is up, rows can’t be tapped, and the row highlight clears with the pop.

**P1-2 Acceptance matrix.** Verified by an automated runtime test that drives the real editor coordinator (the same code path as the popover, menu and shortcuts) and compares the stored Markdown, plus spot checks in the running Mac and iPhone apps.
- Commands: Bold, Italic, Underline, Strikethrough, Inline Code, Link, Heading 1–6, Paragraph, Bulleted/Numbered/Task List, Block Quote, Toggle Checkmark, Code Block, Horizontal Rule, Table, Image.
- Modes: preview and source; each result is then switched to the other mode and back, and must keep identical Markdown.
- Positions: selection mid-paragraph; caret at paragraph start, end, and on an empty line; inside a list item; inside a block quote; inside a code block; in a table cell (preview).
- Pass: only the targeted lines change; neighbors keep their text, style and blank-line separation; inserted blocks are separated by blank lines; source shows syntax and preview shows rendering.
- Context rules: in preview, inside a code block, inline and paragraph styles are disabled (Exit Code Block and Insert remain); in a table cell, paragraph styles are disabled (existing). In source mode every command edits text literally, including inside code fences, because the user sees exactly what is inserted.

**P2-1 Source-mode coverage.** Heading 4–6 follow §6 paragraph rules. Toggle Checkmark (⇧⌘↩) switches `- [ ]`/`- [x]` on touched lines. Link… wraps the selection as `[selection](address)`, or inserts `[address](address)` with none; the caret goes after the link. Insert Image inserts `![](attachments/…)` on its own line with blank-line separation. Indent controls stay hidden in source mode (Tab types a tab, as in any text editor). ⌘B/⌘I/⌘U, ⇧⌘X, ⌘K and ⌥⌘0–6 work in both modes. Toggles also recognize a selection that includes the delimiters, or a caret inside a wrapped run. In source mode, the popover shows the current line's style and wrapped inline styles as selected, just as in preview.

**P2-2 Source-only entries.** Above the source text, one secondary line: “This entry uses Markdown that can’t be previewed.” View Preview stays disabled (tooltip “Preview isn’t available for this entry”).

**P2-3 Undo.** A mode switch is one undo step: ⌘Z immediately after switching switches back, with the same text and selection. Earlier edits can still be undone after that, because the text is again in the representation they were recorded against. The switch never leaves undo actions pointing at the other representation.

**P2-4 Caret rules.** A caret inside syntax that disappears moves to the nearest visible content on the same side; inside a link or image address it goes after the link text; on a fence or table delimiter line it goes to the start of the following content. The caret's line keeps its vertical position in the window, so the text doesn't jump.

**P2-5 Unlock copy by hardware.** “Use Touch ID”, “Use Face ID”, “Use Optic ID”, “Use Apple Watch”, or “Use Touch ID or Apple Watch”, based on what the device reports. Owner hardware checklist in the handoff: fingerprint success, Cancel, Watch approval, closed lid with the Watch only, and biometric lockout falling back to the PIN.

**P2-6** With no entry selected, Search stays enabled; Formatting, Insert Image, View Source and Entry Actions are disabled.

**P2-7 Overflow.** Sync Status sits left of the search field so the trailing pair never moves. The detail minimum width includes Sync Status. The toolbar is not customizable. Verified at the window's minimum size with the sidebar shown and collapsed.

**P3.** The separator is also verified per column at runtime. The iPhone editor bar drops Templates… (it stays on the entries screen, as on the Mac): Formatting, Insert Image, View Source … New Entry. Entries bottom bar: Search, Templates…, New Entry. System undo gestures remain. View Source/View Preview gets ⌥⌘U. After a switch, VoiceOver announces “Source” or “Preview”. Paragraph shortcuts ⌥⌘0–6 stay. The Mac View menu uses the system `SidebarCommands()`. Escaping also covers leading indentation (four spaces are written as character references, as today) and hard breaks (written as two trailing spaces, as today). Entries already stored with heavy escaping keep it until the paragraph is edited — safe for sync and conflicts. The iPhone sheet keeps its two pull-down menus (More Headings, Insert); they are standard pull-down buttons, not nested submenus.

## Revision 2 — block appearance (owner feedback: “the table isn’t clear; make it like Apple’s native one, and check the other styles”)

Observed today: every table cell draws its own half-point border, so lines double up with gaps between cells; the header row has a grey fill; rows are at least 44 pt tall on the Mac (an iPhone touch size). A block quote shows a “❯” glyph, a horizontal rule is a single “—” character, and a code block's background only covers the characters, giving a ragged edge.

Presentation only — stored Markdown, editing behavior and commands do not change.

- **Table (Notes style).** One continuous grid of hairlines in the system separator color, including the outer edge, square corners, no cell fills. The header row (Markdown's first row) is semibold, with no background. Cell padding: Mac 8 pt horizontal / 6 pt vertical, rows size to their text; iPhone 10 pt / 10 pt with a 44 pt minimum row for touch. Columns share the width equally; below about seven characters per column, the table scrolls sideways within its frame (unchanged). The active cell shows only the caret. Increase Contrast uses the stronger system separator. Table actions stay in the cell's context menu (unchanged).
- **Block quote.** A 3 pt rounded vertical bar in tertiary label color spans the quote's lines; text sits 14 pt after the bar. No glyph.
- **Horizontal rule.** A full-width hairline in the separator color, centred in its line, with normal paragraph spacing.
- **Code block.** Monospaced text on one full-width rounded (6 pt) rectangle in the secondary system fill, with 10 pt inner padding.
- **Inline code.** Monospaced with a subtle rounded fill behind the characters (quaternary system fill).
- **Unchanged:** heading sizes, bullets, numbers, native task checkboxes, link color, bold/italic/underline/strikethrough.

All colors are semantic (light, dark, Increase Contrast). Decorations are drawn behind the text and never intercept clicks or selection. VoiceOver reads the text as today; the quote bar and rule are not separate elements.

## Implementation record — 2026-09-23

Implemented as reviewed (review: `feedback-stabilization-2026-09-23-review.md`), with these review items folded in: the save-failure message names the entry (“Couldn’t save “Title”. Try again, or export the entry to keep a copy.”), the mode switch is named in Edit (“Undo View Source” / “Undo View Preview”), indent controls are disabled rather than hidden in source mode, and the acceptance matrix includes indent/outdent, Exit Code Block, multi-paragraph and list-crossing selections. Revision 2 adds Format ▸ Table (Add Row Below, Add Column After, Delete Row, Delete Column, Delete Table) for the cell being edited.

Not done in this pass, recorded rather than implied: Notes-style row/column handles on tables; VoiceOver cues for entering a quote or code block and for rules; right-to-left mirroring of the quote bar; a side-by-side comparison with Notes in dark mode, Increase Contrast and the largest text size (semantic colors are used throughout, but only light mode at default size was inspected).

Defects found and fixed while testing, beyond the owner's list:
- Markdown written after rich edits escaped almost every punctuation character (`\.`, `\-`, `\(`). Escaping is now context aware; existing entries keep their stored text until a paragraph is edited.
- A table cell claimed ⌘Z for the whole window (key equivalents reach every view), so undo did nothing in any entry containing a table. Only the focused cell handles it now, and the shared undo manager is resolved when used.
- Bold/Italic/Underline across several blocks applied the first run's font to the whole selection (text could change size, and bold toggled against a heading's weight).
- Exit Code Block added two empty paragraphs; inserting a block mid-entry always appended an empty paragraph; an empty code block inserted at the end gained a stray blank line when typed into.
- Source-mode commands that produced no Markdown change fell through to rich-text formatting and applied fonts to the source.
- The iOS title-editing test hosted the title field without the editor environment and crashed the test run.
- iPhone: text typed into a table header cell was saved as `**bold**`, because UIKit drops the block kind from typing attributes. Header cells are now read by row.
- iPhone: once table cells became transparent, UIKit's file placeholder for the image-less table attachment showed behind the grid. The attachment now carries a transparent image.
- iPhone source mode turned `---` into an em dash and straight quotes into curly ones, breaking rules, table separators and code. Source mode turns smart dashes and quotes off; preview follows the system setting (Mac too).
- Every code block was followed by an empty line, because the code's own line break and the block separator were both rendered. The code's break now doubles as the separator; stored text is unchanged (covered by a round-trip test).
- Code backgrounds, rules, tables and images now share one column width, and a code block keeps 6 pt more room above it than text so its background never touches the previous block.

Runtime evidence: the Mac audit build (isolated data) for toolbar layout at the minimum window width and maximized, the divider across mode/entry/collection changes, menu and toolbar source switching without editor focus, source and preview formatting, table insertion, and the all-styles entry; 60 fps simulator recordings of iPhone journal → entries → editor navigation before and after the change. Automated: JournalCore (Markdown round trip including line-start punctuation), Mac unit tests (source formatting matrix, preview formatting, insertion caret, undo beside a table), iOS unit tests, and the MobileParity, FeedbackWorkflow and WritingWorkflow UI tests.

## Revision 3 — owner feedback on toolbars and iPhone writing (2026-09-23, afternoon)

Owner requests, verbatim in substance: the Mac entries-column buttons are clipped by the column divider and a short stray divider appears left of Aa until the entries column is widened; on iPhone a new entry should go to the default journal unless a journal is open (as on the Mac); the iPhone editor “…” menu repeats the toolbar (Formatting, Insert Image, View Source); with a hardware keyboard the toolbar appears twice; New Entry should not be in the editor toolbar, and View Source/View Preview moves to the right; entry-list separators on iPhone start oddly far right. Rule: typing with the on-screen keyboard shows one toolbar directly above the keyboard; with a hardware keyboard the normal bottom toolbar stays and no second one appears.

**Mac entries column.** Cause: at the column's 240 pt minimum, the navigation title plus Templates… and New Entry need more room than the column has, so the toolbar pushes the column's separator item past the real divider (the stray line) and the buttons touch it. The entries column minimum becomes 280 pt (fits “Recently Deleted” with both buttons and a gap) and a fixed toolbar spacer keeps the buttons clear of the divider. The window minimum rises from 810 to 850 pt, the sum of the column minimums. Long custom journal names truncate in the title (to be verified).

**Default journal for New Entry (iPhone, iPad, Mac).** Inside a journal, New Entry and Templates… create there (unchanged). Everywhere else they offer (All Entries, the Journals list on iPhone), they create in the default journal: the oldest journal still in use (the “Default” journal created with the library, or the oldest remaining if it was deleted). No journal picker menu. Move Entry… remains the way to file it elsewhere. If there is no journal, the existing New Journal flow runs first (unchanged).

**iPhone/iPad editor toolbar.** One bottom toolbar: Formatting (Aa) and Insert Image at the leading edge, View Source / View Preview at the trailing edge. No New Entry in the editor (new entries start from the entries list or Journals list). The toolbar is the only formatting surface: the keyboard input accessory is removed from the body and table cells. While the on-screen keyboard is up, the toolbar sits directly above it (SwiftUI keyboard safe area); with a hardware keyboard or a floating iPad keyboard it stays at the bottom. The text view's scrollable area ends above the toolbar so the caret line is never hidden. iPad regular width keeps the compact centred capsule with the same three actions in the same order.

**iPhone “…” menu.** Only entry actions: Image Descriptions… (when the entry has images), the entry commands shared with the Mac “…” menu and the list’s context menu (unchanged), and Sync Status when shown. No Formatting / Insert Image / View Source.

**iPhone entry list.** Row separators start at the row's leading text edge (date/title), not under the journal label.

Accessibility: labels unchanged (“Formatting”, “Insert Image”, “View Source”/“View Preview”); 44 pt targets; VoiceOver order follows the visual order; the toolbar remains reachable with Full Keyboard Access. Reduce Motion: the toolbar moves with the keyboard using the system keyboard animation only.

### Revision 3a — response to review and audit polish

- **Keyboard toolbar (review P1).** Adopted the reviewer's second option: while the body or a table cell is being edited, the system keyboard input accessory is the only toolbar (above the on-screen keyboard, at the bottom with a hardware keyboard, attached to a floating iPad keyboard, following interactive dismissal and rotation natively); the bottom bar hides whenever editing is in progress. The accessory now hosts the same SwiftUI controls as the bottom bar (glass capsule, Formatting and Insert Image leading, View Source/View Preview trailing; compact centred capsule at regular width), so the two look identical and only one is ever visible. The keyboard-frame tracking and its “docked keyboard” heuristic are removed.
- **Default journal (review P2).** Kept “the journal created with the library, else the oldest remaining” for this pass; a Settings ▸ Default Journal choice (as Notes' Default Account / Reminders' Default List) is proposed to the owner rather than added unasked. New Entry from the iPhone Journals list opens the default journal, then the entry, so Back shows where it was filed; from All Entries the entry stays in All Entries with its journal label.
- **States.** New Entry and Templates… are disabled in Recently Deleted (as already in Archived). Read-only entries keep the existing disabled controls.
- **Mac entries column.** Verified at the 280 pt minimum with “Recently Deleted”; see audit report for long journal names.

Audit polish implemented with this revision (all presentation, no behaviour change):
- Entry rows without text no longer reserve an empty preview line.
- Formatting sheet on iPhone: a “Format” title with a Close (xmark) button replaces the floating Done at the bottom; “More Headings” and “Insert” show a chevron so they read as menus (Mac popover too).
- iPhone Settings: Devices uses the outline `laptopcomputer.and.iphone` symbol, matching the other outline icons.
- Mac sidebar shows entry counts as badges, as the iPhone list and the Notes sidebar do.
- Mac menus: File ▸ Journal names an untitled journal “Untitled Journal” instead of a blank item; the unused window-tab commands (Show Tab Bar, Show All Tabs, Merge All Windows, Move Tab to New Window) are gone because the app has one window; Help no longer offers an item that only says help isn't available.
