# List indentation — 2026-10-04

Status: current, built 2026-10-04 (reviewed: approve with required changes, all addressed; implementation check in section 6).

## Request

Owner, after build 14: “On iOS adding and removing horizontal indentation doesn't seem to work. And the buttons to do this appear and disappear depending on whether you are on a new line after text or not. I don't understand how this works. I haven't tested this on Mac.”

## 1. What happens today

Rules in the code:

- The Format panel (iPhone, iPad, Mac popover) shows Decrease Indent and Increase Indent only when `FormattingState.canIndent` is true: the selection touches a bulleted, numbered or checklist item or a code block (`FormattingState.swift`, `FormattingPopover.swift`). Elsewhere the row isn't there.
- Format ▸ Increase Indent (⌘]) and Decrease Indent (⌘[) are always enabled on the Mac and iPad menu bar. Tab and Shift-Tab do the same in lists (`StructuredKeyboard`).
- Increase Indent adds one level to every selected item, with no other rule. Decrease Indent removes one; at the top level it turns the item into a plain paragraph.

Measured with the real editor (`EditorHarness`, the Mac build of the shared editor code; the iOS run waits for a free simulator):

| # | Case | Result |
| --- | --- | --- |
| 1 | Caret on the empty line after a list (Return twice to leave it) | The panel reports the line as a **bulleted item**: Bulleted List is checked and the indent buttons appear. Tapping them does nothing (the edit finds no item on that line). On a plain line after a paragraph they don't appear. This is the “appear and disappear” the owner saw, and one way they “don't work”. Cause: the caret's line is read from the character before it, the list's last line break. |
| 2 | Increase Indent on the **first item** of a list | The editor draws it indented, but the Markdown written is `  - one`, which reads back as a top-level item. Reopening the entry, or another device, shows it unindented again. |
| 3 | Increase Indent twice on an item | The editor draws two levels; the Markdown (`    - three` under a top-level item) reads back as one. |
| 4 | Increase or Decrease Indent on an item **with nested items** | The nested items stay where they are: after indenting “b”, its child “c” becomes b's sibling; after outdenting “b”, “c” is two levels deeper than “b”, which Markdown reads back as one. |
| 5 | Increase Indent on item 2 of `1. 2. 3.` | The nested item keeps the number 2 and the next item keeps 3. Read back, the outer list is numbered 1, 2. The nested list starting at 2 can't follow its parent's text in Markdown, so a blank line is written between them (the list becomes “loose”). The nesting width is taken from the item's own number (`10. `) rather than its parent's, which doesn't nest under `1.`–`9.` items once renumbered. |
| 6 | Plain paragraphs | No indent: Markdown has no indented paragraph (four spaces make a code block). Tab inserts a tab character, as before. |

So the operation works for the simple case (item 2 of a bulleted list, indented once) on both platforms, but every other case either does nothing or changes only what is drawn and is undone silently when the entry is read again. That is the “doesn't seem to work” the owner reported, and it's the same on the Mac.

## 2. Design

### 2.1 What can be indented

Indentation applies to list items only (bulleted, numbered, checklist), and keeps the meaning it has in Markdown, so what the editor draws is exactly what is saved and what other devices show.

- **Increase Indent** makes the selected items children of the item above them. It's possible when the first selected item has an item at its own level above it in the same list, whatever that item's kind (a numbered item can nest under a bullet; bulleted and checklist items are one list). Not possible on a list's first item, or on an item whose parent is the item directly above it. Notes lets a list's first item be indented; Markdown can't keep that, so it isn't offered.
- **Maximum depth**: an item can't go deeper than the editor can draw at the current text size (`RichText.nestingIndent` stops moving lines in after as many list columns as fit in 160 pt: 6 levels at the default sizes, 2 at the largest accessibility size). Increase Indent is unavailable when any line it would move is already there, so every enabled Increase Indent visibly moves the text. Accepted limitation: someone writing at the largest sizes can build fewer levels than on another device; deeper items written elsewhere are kept as they are and can be decreased.
- **Decrease Indent** moves the selected nested items out one level. Not possible at the top level of a list, including a list in a quote (it never takes an item out of its quote): there it now does nothing; before, it turned the item into a plain paragraph. Leaving a list stays as in Notes: Backspace at the start of the item, Return in an empty item, or a paragraph style in the Format panel.
- **The whole subtree moves**: the items nested under a moved item move with it, in both directions.
- **Items after a moved item keep their level**, and so may get a new parent: after Decrease Indent on “b” in `a > [b, c]`, “c” is b's child. Its Markdown indentation is recomputed from its new parent's marker.
- **Numbered lists are renumbered** as Markdown reads them, only in the list where something moved: an item that starts a nested list, or whose parent changed and is now first, is 1; an item that joins an existing list (indented under an item that already has numbered children, or moved out after a numbered item) continues that list's numbering; the items after it follow. A list's first number is otherwise kept (a list starting at 5). A nested list starting at 1 is written tight, without the blank line the old `2.` start needed.
- The nesting written to Markdown is the parent item's marker width (2 for `- `, 3 for `1. `, 4 for `10. `), as CommonMark requires and as the reader already records it. In a quote, nesting stays inside the quote (spaces after the `> `).
- **Other content inside a list item** (a paragraph, quote, code block, table or picture nested in an item, which only comes from Markdown written elsewhere): when the list holds any, both commands are unavailable in that list, rather than risking detaching that content from its item or turning it into a code block.
- **Selections**: all selected items move together with their subtrees, when they belong to one list; other selected lines (paragraphs, headings) are left as they are. Increase Indent follows the first selected item's rule; Decrease Indent moves out every selected item that is nested and leaves top-level items where they are. When the selection covers items of more than one list, both are unavailable.
- **Code blocks**: unchanged. Increase Indent inserts a tab (or indents the selected lines); Decrease Indent removes one from the selected lines, and its availability comes from the same code, so they can't disagree.
- **Plain paragraphs, headings, quotes, tables, images**: both commands unavailable. Markdown can't represent an indented paragraph, so none is invented.
- **Source view**: both unavailable; the Markdown is edited as text.
- **VoiceOver**: after Increase or Decrease Indent the new level is announced, “Level 2” (“Level 1” at the top level), because the text doesn't change and on iPhone and iPad the item's own accessibility text has no level.

### 2.2 Format panel and popover

Always show the row with Decrease Indent and Increase Indent, in its current place under Block Quote, and disable the buttons that don't apply instead of removing the row. This is what Notes does with its indent buttons, it stops the panel's height and rows from shifting as the caret moves, and a dimmed control says “not here” where a missing one leaves the person wondering where it went.

```
  ┌────────────────────────────────┐
  │ Format                       ⓧ │   (iPhone panel title)
  │  B   I   U   S   <>            │
  │ ────────────────────────────── │
  │ Heading 1                      │
  │ …                              │
  │ ≡ Bulleted List              ✓ │
  │ ≡ Numbered List                │
  │ ☑ Checklist                    │
  │ ❝ Block Quote                  │
  │      ⇤            ⇥            │  ← always present; each button enabled per 2.1
  │ Insert                       ⌃⌄│
  └────────────────────────────────┘
```

- On a plain line both buttons are dimmed. On a top-level list's first item both are dimmed (nothing to nest under, nothing to move out of); on its second item Increase is enabled and Decrease dimmed; on a nested item Decrease is enabled, and Increase is enabled unless the item is already one level below the item above it or at the maximum depth.
- The state follows the caret while the panel is open, as the checkmarks do today.
- The panel no longer closes after Decrease or Increase Indent, so an item can be moved several levels in a row, as the B/I/U toggles already work. (Today each tap closes the panel.)
- **Accessibility**: the buttons keep their labels (“Decrease Indent”, “Increase Indent”); a disabled button is announced “dimmed” by VoiceOver and skipped by Full Keyboard Access, as for every disabled SwiftUI button. Help tags on the Mac stay. Their size doesn't change with state.
- **Line kind on the empty last line**: the line after a list (or any untagged final line break) is read as what typing there makes: a plain paragraph, or the style chosen for it while it is empty. Bulleted List is no longer checked there. The same correction applies to Format ▸ Mark as Checked.

### 2.3 Mac and iPad menu bar, keyboard

- Format ▸ Increase Indent (⌘]) and Decrease Indent (⌘[) are enabled by the same rules as the buttons (one shared check), and disabled while the editor doesn't have the caret in an applicable line.
- **Tab and Shift-Tab in a list item** do what the menu items do. When the command isn't available there (Tab on a list's first item or at the maximum depth, Shift-Tab at the top level) the key changes nothing and doesn't insert a tab character into the item; the Mac beeps, as AppKit does for a command that can't apply. Elsewhere Tab is unchanged (a tab character in paragraphs and code).
- **Backspace at the start of a nested item** already moves it out one level; its nested items now move with it, through the same operation.

### 2.4 Undo

Each Increase or Decrease Indent is one undo step (“Increase Indent”, “Decrease Indent” in Edit ▸ Undo on the Mac), covering the moved items, their nested items and renumbered items, through the editor's snapshot `replace`; undo restores the selection too.

### 2.5 Copy

Existing labels: “Decrease Indent”, “Increase Indent”. New VoiceOver announcement: “Level 2” (the item's level after the change).

### 2.6 States

No loading, offline or error states. Read-only entries (Recently Deleted, conflicts) have no Format panel, and the menu items are disabled there as other formatting commands are.

## 3. Tests

- **The owner's journey first** (both platforms, the real editor): type an item, Return, then Increase Indent on the new empty item, at the very end of the entry (its own line break) and in the middle; the shared availability check agrees, and the empty item isn't mistaken for the empty line after a list.
- **Rules and Markdown round trip**: indent and outdent of a bulleted, numbered, checklist and checked item; mixed kinds (a numbered item under a bullet); the first item can't be indented and Tab there leaves the text unchanged; the maximum depth at the default size; subtrees move in both directions; a sibling after an outdented item becomes its child with recomputed indentation; numbering (a new nested list starts at 1 and is written tight, joining an existing nested list continues it, later items follow); a list in a quote stays in the quote, and Decrease is unavailable at its top level; a list with other nested content and a selection across two lists are unavailable; each result's Markdown read back gives the structure the editor shows; Decrease at the top level does nothing.
- **Undo and redo** of an indent and an outdent with nested items restore the exact Markdown and the selection.
- **Availability**: the shared check matches what the operation does for each case above, including the empty line after a list (both unavailable, not a bulleted item).
- **Format panel**: the existing `FormattingRuntimeTests` indent/outdent through the panel's path, now without closing.
- iOS UI test: on the iPhone, open Format on a list's second item; Decrease Indent is dimmed; tap Increase Indent: the panel stays open, the item is nested, Increase Indent is now dimmed and Decrease Indent enabled; tap Decrease Indent and the item is back at the top level. On the empty line after the list both buttons are dimmed and Bulleted List isn't checked.

## 4. Owner-visible changes

0. Indentation applies to list items only: Markdown has no indented paragraph, so on plain text both buttons are dimmed. Notes can indent body text; this app can't without changing what is saved. (For the owner to confirm.)
1. The indent row is always in the Format panel; buttons dim where they don't apply.
2. Indenting works only where Markdown can keep it: not on a list's first item, at most one level below the item above.
3. Nested items move with their parent; numbered lists renumber.
4. Decrease Indent / Shift-Tab on a top-level item does nothing (it used to turn the item into a paragraph).
5. The panel stays open after an indent button.

## 5. Review

An independent design review (2026-10-04, given the owner's report, the coordinator's direction and the first draft) returned **approve with required changes**; it confirmed the diagnosis in section 1 and the always-shown, dimmed row. Required changes and how they were addressed:

1. *Other nested content must move with its item or it can be detached or become a code block.* Lists holding such content (only possible from Markdown written elsewhere) make both commands unavailable (2.1), rather than moving multi-line blocks.
2. *Siblings after a moved item get a new parent*: specified, with recomputed indentation and numbering (2.1), and tested.
3. *Mixed kinds and joining a nested list*: nesting is allowed under the item above at the same level whatever its kind; bulleted and checklist items are one list; joining continues the numbering (2.1).
4. *Lists in quotes*: nesting stays inside the quote; Decrease is unavailable at the quote list's top level (2.1); tested.
5. *Selections across lists*: unavailable; other selected lines are left alone (2.1).
6. *VoiceOver gets no feedback*: the new level is announced, “Level 2” (2.1, 2.5).
7. *Test the owner's journey first*: Return then indent on the new empty item, at the end and in the middle (3).

Suggestions taken: scope stated for the owner (4.0); the departure from Notes on first items (2.1); the text-size limit recorded as accepted (2.1); renumbering only the affected list, tight nested lists (2.1); a beep for Tab and Shift-Tab with nothing to do on the Mac (2.3); undo restores the selection (2.4); code-block availability from the same code as the operation (2.1). The caret stays where it was while the iPhone panel is open, as today.

## 6. Implementation check (2026-10-04)

- Code: `ListIndentation.swift` (reading the list around the selection, the rules, renumbering and Markdown indentation, one `paragraphReplacement` for the changed lines), routed from `StructuredKeyboard.edit` for Tab, Shift-Tab, the menu and the panel; `FormattingState` (availability, the line kind after a list); `FormattingPopover` (row always shown, buttons stay open); `AppCommands` (menu items enabled by `EditorActions.caretIndentation`, kept current in `updateCaretState`); `HiddenMarkers` (Backspace at a nested item's start moves its subtree); `RichText.visibleNestingLevels`; JournalCore `DocumentBlock.listMarkerWidth`.
- Found while checking the panel: the Format panel's custom row style didn't dim disabled rows at all (the style rows in a code block looked enabled too). Rows now draw their own disabled state, at 30% opacity and without the hover highlight.
- Availability is read on each selection change, for the menus: about 0.5 ms in a 50-item list and 3 ms in a 300-item list in a Debug build on the Mac; only when the caret is in a list.
- Tests: `ListIndentationTests` (10 cases, Mac and iOS), `StructuredSelectionTests` (the multi-item test now indents items 2–3, since the first can't be), `ListIndentationUITests` (iPhone 17).
- Screenshots: the Mac popover for a list's second item, a nested item and a paragraph (light and dark), the iPhone panel with the item nested and on the line after the list.
- Seen while testing, not changed here: typing `- Milk⏎Eggs` in one burst through XCUITest (much faster than a person) sometimes leaves `- ` unconverted or puts a later letter in the item above (“Milks / Egg”, “M / Eggs / ilk”), with this change's code switched off as well. The Markdown shortcut's own edit seems to land after keystrokes that were already queued. Reported to the build-15 editor work; the UI test types at a person's pace.
