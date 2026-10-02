# Owner decisions 2026-09-25 review

Independent review of `owner-decisions-2026-09-25.md`. The owner's decisions are taken as given. This review judges only the concrete design, against Notes, Mail, Reminders and Photos on macOS 26 and iOS 26.

**Verdict:** Most of this is well aligned with Apple conventions. The shortcuts largely match Notes: ⇧⌘7/⇧⌘9, ⇧⌘L, ⇧⌘U, ⌘', ⌘[/⌘], ⌘K and ⇧⌘X. Two P1 items block implementation. Both are small to fix.

## P1: Blocks implementation

**P1-1. ⌘⌫ for Delete Entry conflicts with a standard text command.** In any macOS or iPadOS text view, ⌘⌫ deletes to the start of the line. A menu key equivalent is handled before the text view sees the key. If "Delete Entry" carries ⌘⌫ in the menu, pressing it while writing sends the whole entry to Recently Deleted with no confirmation.
*Fix:* Handle Delete and ⌘⌫ only while the entry list has focus: `onDeleteCommand` or a list-scoped key handler on Mac, a list-scoped `UIKeyCommand` on iPad. Give the menu item no key equivalent, or disable it while the editor is first responder. Notes and Mail behave this way. Add this to the runtime checks: type a line, press ⌘⌫, and only the line is deleted.

**P1-2. "Open entry removed … the same applies when a sync removes it" can discard local edits.** If another device deletes or moves an entry while this device has unsaved or unsynced edits to it, closing the editor and applying the removal breaks "never silently discard content or overwrite conflicting edits".
*Fix:* State the rule. The editor closes on a remote removal only when the entry has no local changes that haven't synced. Otherwise, treat it as a conflict:
- keep the entry, with this device's edits;
- keep it in its journal, or restore it from Recently Deleted;
- show the existing changes-need-review notice.

"Permanently deleted elsewhere" follows the same rule: keep the local edits as a restored entry.

## P2: Should fix

- **Select the next entry after delete or move on Mac and iPad.** Showing "Select an Entry" after Delete Entry or Move Entry… breaks the list convention. Notes and Mail select the next item, or the previous one if the removed entry was last, and keep focus in the list. Show "Select an Entry" only when the list becomes empty. On iPhone, popping back is correct.
- **Delete without confirmation needs Undo.** Edit ▸ Undo Delete Entry (⌘Z) should restore the entry to its place, as in Notes. On iPhone, shake to undo and the three-finger gesture should work too. Also list the iPhone and iPad trailing swipe action, Delete (destructive, full swipe allowed), and the Recently Deleted swipes Restore and Delete, so the spec covers every Delete path.
- **Say how long items stay in Recently Deleted.** Notes and Photos state it ("up to 30 days") and show days remaining. Put the rule in the Recently Deleted footer or empty state, for example "Entries are deleted permanently after 30 days." or "Deleted entries stay here until you delete them." Add the empty state "No Deleted Entries".
- **`trash.slash` is the wrong symbol for Delete Permanently.** It means "can't delete" or "no trash". Photos and Files use `trash` for permanent deletion; the alert's copy carries the "permanently". `doc.on.doc` for Save as Template… reads as Copy or Duplicate. Use `doc.badge.plus` or `square.and.arrow.down.on.square`.
- **App Lock is missing a forgotten-PIN path and some copy.**
  - **PIN rules:** say how long a PIN must be and whether it's digits only, for example "Enter a 6-digit PIN."
  - **Mismatch copy:** for example "The PINs don't match. Try again."
  - **Wrong PIN:** say whether attempts are limited or delayed.
  - **Forgotten PIN:** say what happens if it's forgotten, for example "Forgot PIN?" leading to unlocking with the recovery password from the sync-security design. Without that, the owner can lock himself out of his own journal.
  - **Explanatory footer:** add one line saying what App Lock does and doesn't do. The guidance says a short PIN isn't enough protection on its own, so the footer should make clear App Lock doesn't change encryption. For example: "App Lock asks for your PIN or Touch ID when you open My Journal. It doesn't change how your journal is encrypted."
- **Define "untouched" for discarding empty new entries (W2).** Treat whitespace-only title and text as empty. An entry that has an image, a changed date, or a template whose text was edited counts as touched. Discard it before it syncs, so other devices never briefly show an empty entry.

## P3: Minor

- **Journal delete copy.** "Its 3 entries move to Recently Deleted." doesn't say the journal can be restored too. Use "The journal and its 3 entries move to Recently Deleted." (or "…and its 1 entry…"). With no entries: "The journal moves to Recently Deleted."
- **Permanent-delete titles.**
  - Untitled entries: use "Delete This Entry Permanently?" instead of quoting an empty title.
  - A journal with no entries: "Delete "Work" Permanently?"
  - Multiple selection, if the list supports it: "Delete 3 Entries Permanently?"
  - Keep "Delete" and "Cancel" as the buttons, as proposed.
- **Search Entries location.** Notes and Mail put their list search under Edit ▸ Find (Search… / Mailbox Search), not under View. Consider Edit ▸ Find ▸ Search Entries ⇧⌘F. ⇧⌘F doesn't clash with any standard text command.
- **⌥⌘C for Inline Code** is the conventional shortcut for Format ▸ Font ▸ Copy Style. There's no conflict as long as `TextFormattingCommands` isn't added. If it ever is, move Inline Code to Notes' Monostyled shortcut, ⇧⌘M.
- **New Journal.** Notes uses ⇧⌘N for New Folder. Here ⇧⌘N is New Blank Entry and ⌥⌘N is New Journal. That's acceptable, but make sure the menu makes the difference between New Entry and New Blank Entry obvious. For example, show New Entry only when a default template exists, and otherwise let ⌘N create a blank entry.
- **Zoom In.** Bind both ⌘= and ⌘+, as Safari and Notes do. Actual Size ⌘0 and Paragraph ⌥⌘0 don't conflict.
- **Code stays literal (W4).** Also turn off continuous spell checking in code and source, otherwise red underlines appear on identifiers.
- **Markdown as you type.**
  - The Mac checkbox label should be sentence case: "Format Markdown as you type". The iOS toggle keeps title case.
  - Name the undo action after the style, for example "Undo Numbered List".
  - On Mac, put the setting under a "Writing" heading in General, so it matches the iPhone "Writing" row.
- **Camera.** When access is denied or restricted, tapping Take Photo should show "Camera access is off. To take photos, turn on Camera for My Journal in Settings." with Open Settings and Cancel. The usage string is fine.
- **Mac App Lock setup.** Use one sheet with "PIN" and "Verify" fields, as macOS password sheets do, rather than steps in sequence. Sequential steps are right on iPhone. The biometric switch label follows the hardware rules agreed earlier, for example "Use Touch ID or Apple Watch".
- **Settings window.** When switching tabs, change the height without animation under Reduce Motion. Tab icons, fixed width and the window title are correct.
- **Read-only entries.** Show format actions disabled rather than hidden, as agreed earlier, so the toolbar layout doesn't change.
- **Print.** Print ⌘P is a standard File item for document apps (Notes has it). It's optional given the owner removed Export Entry.

## Fine as proposed

- Insert Image menu (Photo Library / Take Photo / Choose File…), matching Mail.
- Find in Entry (Mac Edit ▸ Find with the system shortcuts; iPhone "…" ▸ Find in Entry with the system find navigator).
- The Markdown-as-you-type triggers and Backspace/⌘Z revert.
- The Edit menu through `TextEditingCommands`.
- The Format menu layout.
- The Mac Settings window with toolbar tabs.
- Section footers.
- "My Journal" in copy.
- Formatting sheet with the system close button.
- Removing the Journals settings pane.
- Closing alerts and sheets when the app locks.
- The remaining menu icons.

## Outcome

Implementation can proceed once P1-1 is fixed (⌘⌫ handled in the list only) and P1-2 is stated (a remote removal never closes or discards an entry with local changes). The P2 items should be in the same pass. No re-review is needed unless the Delete or App Lock flows change shape.

## Post-implementation review of deviations (2026-09-25)

Checked against the implementation record and `AppCommands.swift`, `AppLockSheet.swift`, `CompactJournalNavigation.swift` and `ImagePickerPresenter.swift`.

**P1: reject as implemented**
- **⇧⌘L is assigned twice (item 4).** `AppCommands.swift` gives ⇧⌘L to both App ▸ Lock My Journal (line 45) and Format ▸ Task List (line 71, Notes' Checklist shortcut, which the reviewed design assigned). With a PIN set, pressing the Task List shortcut while writing locks the app instead, and the Format item's shortcut doesn't work. *Fix:* keep ⇧⌘L for Task List, as reviewed. Give Lock My Journal ⌃⌘L, which no standard text command or system shortcut uses (⌃⌘Q is the system Lock Screen), or no shortcut at all. Add a check that the Mac menus have no duplicate key equivalents.

**Per-item verdicts**

1. **Settings minimum height of 440 pt: accept.** It's pragmatic, and sheets that are taller than their window look broken on macOS. P3: top-align the content of short tabs so the extra space falls at the bottom, as System Settings panes do. Don't centre it.

2. **Mac App Lock sheet: accept the compact layout, with P2 fixes.**
   - **P2: fields need visible labels.** SecureFields with placeholder-only labels lose them as soon as you type. In "Change PIN", three rows of dots can't be told apart. macOS password sheets (Users & Groups, Change Password) use a label column: "Current PIN:", "New PIN:", "Verify:". Use `Form` with `.formStyle(.columns)`, or `LabeledContent` rows. That stays compact at 360 pt.
   - **P2: VoiceOver doesn't hear errors.** The note changes to "Wrong PIN. Try again." or "The PINs don't match." without being announced. Post an accessibility announcement when either appears. On a wrong PIN, also select the PIN field's contents so the user can retype at once, as macOS password prompts do.
   - **P3: digits only.** Letters are accepted but silently keep the button disabled. Either filter to digits, or change the note to "Use digits only." when a non-digit is typed.
   - Fine: the title, the note wording, the "Unlock with Touch ID" checkbox, the footer, Cancel/Esc and the default button. The iOS Form with Cancel and confirm in the toolbar is correct.

3. **Lock screen copy: accept.** "My Journal Is Locked" is good. "Wrong PIN. Try again." is clear and consistent across the lock screen and the sheet. Optional: Apple more often says "Incorrect", as in "Incorrect PIN. Try again."

4. **App menu order: accept.** About, Settings…, Lock My Journal, Services… is where lock commands usually go. The shortcut must change; see P1.

5. **Add Agent Access buttons and copy: accept.** Back at the leading edge with Cancel and the default button at the trailing edge is the macOS assistant layout. The new copy is accurate, and it rightly drops the archive reference and mentions the cloud provider. P3: split it into two short paragraphs. First, what's shared: "<Name> can read entries in the selected journals while My Journal is open and unlocked. Entries in Recently Deleted aren't shared." Second, the risk: "A cloud agent may send this content to its provider. Revoking access stops future reads but can't retract content already read." That reads more easily at sheet width.

6. **Agent Access footer: accept.** P3: the section header "Agent Access" repeats the tab title. Drop it, or give the header the content of the section, for example "Agents".

7. **iPhone state restoration: accept the behavior. It matches Notes, and the stack is rebuilt as collection → entry so Back is right.**
   - **P2: no visible push animation.** `navigationPath` is set in `onChange(of: revealsSelection)` without turning animation off. After launch or unlock, the list briefly appears and then the editor slides in. Restoration should show the editor directly. Set the path inside a transaction with animations disabled, or before the first frame.
   - **P2: define the fallbacks.** Land on the list, with no error, when the remembered entry has been deleted, moved to Recently Deleted, removed by sync, or is read-only. After restoring, the keyboard shouldn't appear on its own.

8. **Camera access alert: accept for denied, P2 for restricted.**
   - **P2: restricted access.** `isDenied` treats `.restricted` (Screen Time or device management) the same as `.denied`. For a restricted camera, "Open Settings" can't help. Hide Take Photo when access is restricted, or show "Camera use is restricted on this device." with OK only.
   - **P3: alert wording.** A single-sentence alert title is allowed, but Apple more often uses a short title with a message. Suggested title "Camera Access Is Off", message "To take photos, turn on Camera for My Journal in Settings.", buttons Open Settings / Cancel. Either version is acceptable.

**Outcome:** Change the Lock My Journal shortcut before shipping (P1). Fix the App Lock field labels and VoiceOver announcements, the unanimated restoration with its fallbacks, and the restricted-camera case (P2). Everything else is accepted as implemented.
