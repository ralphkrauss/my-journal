# Review: Feedback stabilization, 2026-09-23

Independent design review of `feedback-stabilization-2026-09-23.md`, checked against the owner's 13 feedback items and the project guidance.

## P1: Blocks implementation

**P1-1. iPhone push can still wait on a save. This conflicts with `NavigationLink(value:)` and can bring back the lag (item 1).**
§1 says the push waits whenever "a save is genuinely outstanding". That will happen often: someone types, taps Back, and taps another entry within the autosave debounce. A value-based `NavigationLink` pushes at once, so holding the push means intercepting the path. That brings back the delayed, flickering highlight the owner reported. "Opening another entry is refused" also has no defined UI or copy.
*Recommendation:* Never block navigation on an in-flight save. Keep pending drafts in the model per entry and write them on a serial queue, so opening entry B never waits for entry A's write. Block only after a save has actually failed. In that case, show the existing alert and name the entry: "Couldn't Save "<Title>"" with Try Again / Export Entry… / Cancel. State that tapping a row while that alert is pending does nothing, and that the row highlight clears. Remove the "push waits" clause.

**P1-2. Item 11 (runtime-test every style inside existing content) has no plan.**
§6 says "Preview mode behavior is unchanged", but the owner asked for every style to be verified in both modes. The proposal has no acceptance criteria.
*Recommendation:* Add an acceptance matrix before implementation, and check each row in the running app by diffing the stored Markdown:
- Commands: every Formatting and Insert command.
- Modes: preview and source.
- Positions: mid-paragraph selection, caret at start, end, and on an empty line, inside a list item, a block quote, a code block, and a table cell.
- Pass means only the intended lines change, surrounding blocks don't merge, insertions have clean blank-line separation, source shows syntax, and preview shows rendering.

Also define which commands are disabled in which context. For example, paragraph styles are disabled in a table cell, and inline styles and headings are disabled inside a code block. Unspecified contexts are where the "unintended change" bugs come from.

## P2: Should change

**P2-1. Source-mode coverage is incomplete (item 3).** §6 doesn't cover Decrease/Increase Indent, Heading 4–6, Insert Image, Link… (what the dialog does with and without a selection, and where the caret lands), or toggling a task item's checkbox. It also doesn't say whether ⌘B, ⌘I, ⌘U and the other shortcuts work in source mode. Specify each. For toggles, accept selections with or without the delimiters, and with the caret inside a wrapped run. Say whether the Format menu shows checkmarks for the current line's style in source mode. It should, to match preview.

**P2-2. A disabled "View Preview" leaves the user stuck with no actionable explanation.** A tooltip on a disabled toolbar item is easy to miss, and the copy doesn't say why. Keep the button disabled, but add a quiet inline note at the top of the source view that names the cause, for example: "Preview isn't available because this entry contains Markdown the editor can't show without changing it." If the unsupported construct can be located, offer "Show" to select it.

**P2-3. Undo across a mode switch is undefined (item 12 and data safety).** Converting the whole editor can clear the undo stack, or make ⌘Z revert the entire conversion. State the intended behavior. Recommended: the switch itself isn't an undoable edit, and text edits made before the switch can still be undone after it, or at minimum the switch doesn't corrupt the stack.

**P2-4. Selection-mapping edge cases (§5).** Define where the caret goes when it's inside syntax that disappears: a link URL or image path, a code fence line, table pipes, or between `*` and `**`. Suggested rule: go to the nearest content boundary on the same side, and after the link text for URLs. When switching, keep the caret's line at the same vertical position in the viewport rather than just scrolling it into view, so the text doesn't jump.

**P2-5. Unlock button copy should reflect the hardware that's present (item 8).** "Use Touch ID or Face ID" is never right on an iPhone, because a device has one or the other. On a Mac without a Touch ID sensor, or without a paired Watch, "Use Touch ID or Apple Watch" is also wrong. Use `biometryType` and whether a companion is available: "Use Face ID", "Use Touch ID", "Use Apple Watch", or "Use Touch ID or Apple Watch". Add a short checklist for the owner to run on hardware: success, Cancel, biometric lockout falling back to password, Watch approval, and a closed lid with only the Watch.

**P2-6. "Toolbar items remain in place and disabled" must not include Search.** With no entry selected, Search stays enabled. Formatting, Insert Image, View Source and Entry Actions are disabled.

**P2-7. The no-overflow guarantee has gaps (item 7).**
- The detail minimum width must include Sync Status when it's shown.
- Say where Sync Status goes. Recommended: left of the search field, so the trailing pair never moves.
- Define the window's minimum width when the sidebar is already collapsed, and check it in a half-screen tile on a 13-inch display.
- If the toolbar is customizable, either disable customization or state that the added space is accounted for. Otherwise `>>` can come back.

## P3: Minor

- **Divider (item 4).** `titlebarSeparatorStyle` on an `NSSplitViewItem` overrides the window's setting. Set `.none` on each item too, or confirm at runtime that none override it. Check that the entries list and sidebar still get the system scroll-edge effect under the toolbar. With Increase Contrast on, prefer whatever the system does over forcing no separator.
- **iPhone editor bar.** Templates… on the editor's bottom bar isn't on the Mac editor, where Templates… lives in the entries column. To match the Mac, keep New Entry at the trailing end, as Notes does, and leave Templates… on the entries screen. Also spell out the entries screen's bottom bar.
- **Removing Undo/Redo buttons.** Make sure system undo still works: shake to undo, three-finger gestures, and the keyboard undo key.
- **Conditional "…" on entries.** Put the condition around the `ToolbarItem`, not inside it. The text already implies this, but make it explicit.
- **Source toggle shortcut.** Consider ⌥⌘U, which Safari uses for Show Page Source. A frequent mode switch with no shortcut is unusual on the Mac.
- **"Preview" naming.** The rich mode is the main editing mode, so "Preview" suggests it's read-only. This is acceptable because it's the owner's own vocabulary. Keep "View Source" and "View Preview" consistent everywhere, including the VoiceOver label.
- **VoiceOver.** When focus moves to the editor after a switch, also announce the new mode ("Source" or "Preview") so the change is audible. Give B/I/U/S the labels Bold, Italic, Underline and Strikethrough.
- **Popover structure.** Avoid nested submenus (More Headings ▸, Insert ▸) in the iPhone sheet. Use pull-down `Menu` buttons or grouped rows instead. Nested menus are fine in the Mac Format menu.
- **Keyboard shortcuts.** Say whether the renamed paragraph styles keep their existing shortcuts. Put Link… on ⌘K.
- **Menu copy.** "Exit Code Block", "Inline Code", "Heading 1–6", "Paragraph", "Task List", "Block Quote" and "Horizontal Rule" are good, consistent Markdown naming. "Increase Indent" and "Decrease Indent" are acceptable.
- **Escaping (§7).** Also cover `1)` ordered-list markers, 4 or more leading spaces (indented code), and hard line breaks from trailing spaces or a backslash. Entries already stored with noisy escapes will still show them in source mode until they're edited. That's acceptable and conflict-safe, but say so.
- **Search placeholder.** "Search <Journal>" truncates when the journal name is long. That's acceptable. Keep ⌘F.
- **Show/Hide Sidebar.** Use the system `SidebarCommands()` so the command isn't duplicated.

## Fine as proposed

Standard `NavigationLink` rows with system highlight and deselection (item 1). The system back button and edge swipe. Toolbars declared per screen (no empty capsules). Removing Share, checklist, table and undo/redo (item 2). The expanded search field (item 5). Creation actions staying in the entries column (item 6). The trailing View Source / "…" group in place of the overflow chevron (item 7). A SwiftUI toolbar button that doesn't depend on focus (item 9). The Markdown style names (item 10). Mapping by UTF-16 offset (item 12). Settings at the bottom of the sidebar (item 13, the owner's choice; make sure ⌘, still opens it).

## Outcome

Implementation can proceed after P1-1 is fixed (never block navigation on an in-flight save; a defined failure UI naming the entry) and P1-2 is added (a style × mode × position acceptance matrix, plus per-context disabled rules). P2-1 to P2-7 should go into the same revision. The P1-1 navigation change needs a short re-review. The rest doesn't.

## Re-review: Revision 1

**P1-1 (navigation): resolved.** Push and pop happen at once. The pushed screen shows only its own route's content. Only an actual failure stops the change. Two items remain:
- **P2: Alert copy.** "Couldn't save changes. Keep Journal open." reads like an instruction, and "Journal" could mean the app or one of the user's journals. It also still doesn't name the entry, which matters now that the alert can appear on a screen other than the editor. Suggested: title "Couldn't Save "<Entry Title>"", message "Keep My Journal open until the entry is saved or exported." Buttons: Try Again / Export Entry… / OK. Applying this everywhere keeps the alerts consistent.
- **P3: Blank editor while the write finishes.** Don't let the pushed editor take focus or accept typing until its content has loaded, so nothing typed during those milliseconds gets replaced.

**P1-2 (acceptance matrix): resolved.** The commands, modes, positions, round trip, pass criteria and context rules are adequate. One item remains:
- **P2: Add missing cases.** Add Decrease/Increase Indent (preview) and Exit Code Block as commands. Add a multi-paragraph selection and a selection that crosses a list/paragraph boundary as positions. These are the likeliest places for unintended changes.

**Other changes (brief check):**
- **P2-3 Undo: P2, a departure from convention.** Making the mode switch an undo step means ⌘Z after switching flips the view instead of undoing the last text edit. Mac apps don't normally make view changes undoable. If no better approach is possible, keep it, but name the action in the Edit menu ("Undo View Source" / "Undo View Preview") so the behavior is visible.
- **P3: Indent in source mode.** Disable the indent controls instead of hiding them, so the popover layout doesn't shift between modes.
- **P2-1, P2-2, P2-4 to P2-7, and the P3 items: fine as revised.**

**Outcome:** Implementation can proceed. Fold in the alert copy, the matrix additions and the undo menu naming. No further re-review is needed.

## Revision 2 review: block appearance

This revision is right: one continuous hairline grid, no fills, compact Mac rows, a quote bar instead of a glyph, a real rule line, full-width code blocks, and semantic colors. It fixes what the owner found unclear. There are no P1 findings.

**P2**
- **Table actions need a visible, keyboard-reachable path.** Notes makes its tables clear by showing small row and column handles on the active cell's row and column. Clicking a handle selects the row or column and opens its actions. Here the actions live only in a context menu that is hidden by default and hard to reach from the keyboard. Add handles like Notes does, shown only while the caret is in the table. Also add Format ▸ Table ▸ Add Row Above/Below, Add Column Before/After, Delete Row, and Delete Column, so the actions work from the menu bar, the keyboard and VoiceOver.
- **VoiceOver loses structure.** "Reads the text as today" means tables, quotes, rules and code blocks are indistinguishable from plain paragraphs. At minimum:
  - Table cells should announce their row and column, with the header's text as context. Use native table accessibility if the text system provides it.
  - Quotes should announce "Quote" and code blocks "Code" when VoiceOver enters them.
  - The rule should be read as "Separator".

  These don't need to be separate focusable elements, but they need spoken announcements.
- **"Check the other styles" needs runtime evidence, not "unchanged".** The owner asked for a check. Before sign-off, add a side-by-side screenshot pass against Notes on Mac and iPhone:
  - Styles: headings, lists, task checkboxes, links, inline images, quote, code, table and rule.
  - Appearances: light, dark, and Increase Contrast.
  - Text size: the largest Dynamic Type size on iPhone.

  Record any deviations.

**P3**
- **Nesting and direction.** Specify how a quote nested in a quote looks (one bar per level) and how quotes and code look inside list items. Draw bars on the leading edge so they flip for right-to-left text.
- **Rule and table editing.** The rule should select and delete as one unit, with the caret moving past it cleanly. Tab and Shift-Tab should move between table cells as in Notes. Confirm both at runtime, even though editing behavior is out of scope.
- **Long code lines.** State that they wrap, as in Notes, rather than scrolling.
- **Inline code fill.** Quaternary fill is nearly invisible in light mode. Check it on screen and use tertiary fill if it disappears. The monospaced font carries the meaning either way.
- **iPhone table row height.** The 44 pt minimum is fine. It sits close to the natural height at 10 pt padding, and rows grow with Dynamic Type.
- **Header row.** Notes has no header row, but Markdown requires one, so a semibold first row with no fill is the right native-looking compromise.

**Outcome:** Implementation can proceed after adding the table handles and the Format ▸ Table menu, the VoiceOver announcements, and the recorded appearance pass against Notes. No further re-review is needed.

## Revision 3 review

**Verdict:** The direction is right and matches what the owner asked for. It can proceed after one P1 item about how the keyboard bar is built and the P2 fixes below. No re-review is needed unless the approach to the keyboard bar changes.

**P1**
- **Replacing the input accessory with a bar driven by the keyboard safe area is sound only if it behaves like the system bar. Specify that and prove it at runtime.** Notes gets "one bar above the keyboard, one bar with a hardware keyboard" from UIKit, because its editing bar is the keyboard accessory. With a hardware keyboard, iOS docks the accessory at the bottom of the screen. The duplicate the owner saw comes from also keeping a bottom bar, not from having an accessory. A bar placed by the SwiftUI keyboard safe area gets show/hide right, but it can lag or jump in the cases that matter:
  - Interactive swipe-down dismissal: the bar must follow the finger frame by frame.
  - Undocked and split iPad keyboards, the floating keyboard, and the Stage Manager keyboard.
  - The iPad hardware-keyboard shortcut bar and dictation.
  - Rotation while typing.
  - Reduce Motion: no custom animation, and no jump.

  Recommendation: keep one set of toolbar items and present it once. Either (a) the proposed bar, attached with `UIKeyboardLayoutGuide` (`followsUndockedKeyboard`) and verified in every case above, or (b) the system input accessory while the editor is focused, with the bottom bar hidden while the text view is first responder. Option (b) handles hardware and floating keyboards natively. Whichever you pick, add these cases to the runtime checks before sign-off.

**P2**
- **Default journal: make the rule a visible setting, not an inferred one.** "The oldest journal still in use" is deterministic, but users can't see it. A renamed "Default" journal, an archived journal, or a journal restored from Recently Deleted all make "in use" and "oldest" ambiguous. Apple's pattern is a Settings choice with no picker at creation time: Notes' Default Account and Reminders' Default List. Recommendation:
  - Add Settings ▸ Default Journal, initially the journal created with the library.
  - If that journal is deleted or archived, fall back to the oldest remaining active journal, and update the setting visibly.
  - No picker at creation time; Move Entry… stays, as proposed.
- **Show where the new entry went.** New Entry from the iPhone Journals list should push the default journal and then the editor, so Back lands on the list the entry was filed in (Notes does this). New Entry from All Entries should show the journal label on the new row, as other rows already do.
- **States missing from the spec:**
  - **Recently Deleted:** New Entry and Templates… are disabled, as Notes disables Compose there. That also means the Mac width fit shouldn't be measured against "Recently Deleted". Measure against a normal journal title and let long names truncate.
  - **Read-only entries** (a deleted entry, an entry that can't be edited, a source-only entry): Formatting and Insert Image are disabled, not hidden, and View Source follows the §4 rules. The keyboard doesn't appear.
  - **Locked:** locking dismisses the keyboard and the bar, and nothing shows above the lock screen. Unlocking returns to the editor without bringing the keyboard back.
  - **No journals:** New Entry opening the New Journal flow is acceptable, but that sheet then needs one line of context, for example the footer "New entries are saved in this journal." Or show a "No Journals" empty state with a New Journal button instead.
- **Hardware keyboards need the commands without the bar.** On iPad and on iPhone with a keyboard, ⌘N (New Entry, now that the button has left the editor), ⌘B, ⌘I, ⌘U, ⌘K, ⌥⌘U and the heading shortcuts must work. On iPadOS 26 they should also appear in the menu bar's Format and View menus, grouped as on the Mac. With Full Keyboard Access, the bar must be reachable in visual order (Aa, Insert Image, View Source).

**P3**
- **Editor scrolling.** Let the text scroll under the glass bar with the system scroll-edge effect, and use a bottom content inset so the caret line stays visible. Clipping the scroll area above the bar looks less native on iOS 26.
- **Mac entries column.** Check the 280 pt minimum with a larger sidebar icon size (the Mac setting that enlarges sidebar rows and text) and in longer localizations. The fixed spacer is fine.
- **Separators.** Aligning them to the leading text with `listRowSeparatorLeading` is right. Check at the largest Dynamic Type sizes, where row layouts change.
- **"…" menu.** Fine: entry actions only.
- **Removing New Entry from the editor.** Fine, as the owner asked.
- **iPad capsule.** Fine.

## Revision 3a re-review

**Verdict:** The Revision 3 P1 is resolved by design. Nothing blocks. The P2 items below are runtime checks and one small fix, to confirm during the implementation inspection.

**Keyboard toolbar: resolved.** Using the system input accessory as the only toolbar while editing, and hiding the bottom bar, is the approach Notes uses. It gets hardware, floating, undocked and interactive-dismissal behavior from UIKit instead of heuristics. Removing the keyboard-frame tracking is the right call.

**P2: verify at runtime (checked against `Editor/WritingAccessory.swift`)**
- **Background with a hardware keyboard.** `UIInputView(inputViewStyle: .default)` can draw a keyboard-style translucent strip behind the hosted glass capsule. With a hardware keyboard that strip sits at the bottom of the screen, so the "identical to the bottom bar" claim needs checking. If a strip shows, use a plain `UIView` accessory, or confirm the style draws nothing on iOS 26.
- **Home indicator.** With a hardware keyboard, the accessory is placed at the bottom edge. The hosting view is pinned to `bottomAnchor`, not `safeAreaLayoutGuide.bottomAnchor`, so the capsule may crowd the home indicator. Pin it to the safe area, or confirm the system insets it.
- **Handoff when editing ends.** On interactive swipe-down, and on Done, the accessory leaves with the keyboard and the bottom bar returns. Confirm the handoff shows neither both bars nor a gap. With Reduce Motion, the bottom bar should appear without its own animation.
- **Dynamic Type.** At accessibility sizes, confirm the self-sizing accessory grows. The initial frame is fixed at 56 pt, and the intrinsic size must win.

**Default journal:** Deferring the Settings choice to the owner is acceptable. Journals list → default journal → entry, and the journal label under All Entries, answer the "where did it go" concern. One edge case (P3): `liveJournals` leaves out conflicted journals. During a sync conflict on the default journal, new entries silently go into the next-oldest journal, then go back to the original once the conflict clears. Either disable New Entry under All Entries while the default journal is in conflict, or keep filing into it. A visible Default Journal setting would also settle this.

**States:** Fine: New Entry is disabled in Recently Deleted and Archived, and the existing read-only handling stays.

**Audit polish**
- **"Format" title with an xmark Close button:** correct. It matches Notes' iOS 26 Format sheet. P3: use the system close button (`Button(role: .close)` in a toolbar) instead of a hand-drawn xmark, so it gets the standard glass circle.
- **Chevrons on More Headings / Insert (P3).** On iOS, a trailing `chevron.right` on a row means "push a screen". Rows that open a pull-down menu use `chevron.up.chevron.down`, or no chevron. On the Mac popover a right chevron is acceptable because it reads like a submenu arrow. Consider the up/down chevron on iOS.
- **Entry rows without text (P3, convention mismatch).** Notes keeps every row the same height and shows "No additional text" in secondary color. Collapsing the line makes list rows uneven. Prefer Notes' behavior unless the owner asked for this.
- **Mac sidebar counts:** correct. `.badge` gives the trailing secondary count that Notes shows, and zero shows none.
- **"Untitled Journal":** good.
- **Removing window-tab commands:** fine for a single-window app. Do it with `NSWindow.allowsAutomaticWindowTabbing = false` rather than editing menus.
- **Removing the Help item that only says help isn't available:** fine. The system Help menu with its search field remains.
- **Devices symbol:** fine.
- **Mac entries column at 280 pt:** acceptable, pending the long-name check in the audit report.

**Outcome:** Implementation can proceed. Resolve the four P2 runtime checks during the UI inspection. The P3 items are optional polish.
