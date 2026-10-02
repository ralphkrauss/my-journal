# Owner decisions — 2026-09-25

The owner approved the audit recommendations (W1–W4, K1–K7, C1, C2, C4, C5, C8, S1–S6; later: W5–W7, C3, C6, C7, S7, S8) and added: one Delete flow through Recently Deleted (no Archive), journals the same, a normal confirmation for permanent deletion, no Export Entry, the photo library for Insert Image on iPhone/iPad, and closing an entry that is removed while open. Server items S1–S6 have their own design (`sync-security-2026-09-24.md`). Existing archived entries don't need migration (no data the owner cares about), but nothing may silently disappear.

## 1. Delete, Recently Deleted, Delete Permanently

- **Entries.** “Delete Entry” (menus, ⌘⌫/Delete in the Mac and iPad list) moves the entry to Recently Deleted at once, without confirmation, as in Notes. There is no Archive command, no Archived collection and no “Restore and Unarchive”. An entry that was archived by an earlier build simply shows in its journal again (archive state is ignored, not deleted).
- **Journals.** “Delete Journal…” shows a standard alert: title “Delete “Work”?”, message “Its 3 entries move to Recently Deleted.” (“Its 1 entry …”, or “This journal has no entries.”), buttons **Delete** (destructive) and **Cancel**. The existing checks run before the alert; if the journal has unresolved changes the alert says “This journal has changes that need review.” with **Review Changes** and **Cancel**.
- **Recently Deleted.** Rows keep **Restore** (unchanged flows, including restoring the journal an entry needs). **Delete Permanently…** shows a standard alert: “Delete “Title” Permanently?” / “You can’t undo this.” (journal: “Delete “Work” and Its Entries Permanently?” / “Its 3 entries are deleted too. You can’t undo this.”), buttons **Delete** (destructive) and **Cancel**. Preparation checks run first; failures show the existing error text and, where relevant, **Review Changes**. The large review sheet is removed.
- **Open entry removed.** When the entry in the editor is deleted, permanently deleted, or moved out of the current collection, the editor closes: iPhone pops back to the list; Mac and iPad show “Select an Entry”. The same applies when a sync removes it.

## 2. Remove Export Entry

Export Entry… is removed from the entry menus, the context menu and the save-failure notice. The save-failure notice keeps **Try Again**; the full backup (Settings ▸ Backup ▸ Export Archive…) remains.

## 3. Insert Image (iPhone and iPad)

The Insert Image control becomes a menu with **Photo Library** (system photo picker, no permission prompt), **Take Photo** (camera; hidden on devices without one; first use asks “Take photos to add them to your entries.”) and **Choose File…** (the current Files picker). Same menu in the keyboard toolbar and the bottom bar. Mac is unchanged (standard open panel).

## 4. Markdown as you type (W1)

At the start of a plain paragraph in preview:
- “- ”, “* ” or “+ ” → bulleted list; “1. ” or “1) ” (any number) → numbered list starting at that number; “[ ] ” or “[] ” → task; “[x] ” → checked task; “> ” → block quote; “# ” … “###### ” → Heading 1–6.
- “```” then Return → code block; “---” or “***” then Return → horizontal rule.
The characters are replaced by the formatting in one undo step. **Backspace** directly after a conversion (before typing anything else) or **⌘Z** restores exactly what was typed, and that line is not converted again until it is edited. Never inside code blocks, tables, headings (except changing heading level is not attempted), or source view, and never on paste. A setting **Format Markdown as You Type** (on by default) lives in Settings ▸ General (Mac) / Settings ▸ Writing (iPhone). VoiceOver announces the new style (“Numbered list”).

## 5. Discard untouched new entries (W2)

**Reversed on 30 September 2026:** an entry stays once it's created, even if it's left empty. See [new-entry-template-suggestion.md](new-entry-template-suggestion.md), "Owner decision: new entries are kept".

An entry created with New Entry that still has no title and no text when you open another entry, leave the editor, switch collections, lock, or quit is deleted permanently without a trace (it never goes to Recently Deleted). Entries from templates count as untouched only if the template text is unchanged and the title is empty.

## 6. Find in Entry (W3)

- Mac: Edit ▸ Find (system submenu) — Find… ⌘F opens the find bar in the editor (Find and Replace ⌥⌘F, Find Next ⌘G, Find Previous ⇧⌘G, Use Selection for Find ⌘E). Focusing the journal search field moves to **View ▸ Search Entries ⇧⌘F** (⌥⌘F is taken by Find and Replace).
- iPhone/iPad: “Find in Entry” in the editor “…” menu opens the system find navigator; ⌘F with a hardware keyboard does the same.

## 7. Code stays literal (W4)

Autocapitalization, autocorrection, text replacement and smart quotes/dashes are off while the caret is in a code block, inline code or source view; prose follows the system settings.

## 8. Menus and keyboard (K1–K7)

- **Edit:** the system text commands (Find, Spelling and Grammar, Substitutions, Transformations, Speech) via TextEditingCommands.
- **File:** New Entry ⌘N, New Blank Entry ⇧⌘N, New Entry from Template…, New Journal ⌥⌘N, —, Import Archive…, Export Archive…, —, Close ⌘W. The Journal switcher is removed.
- **Format:** Bold ⌘B, Italic ⌘I, Underline ⌘U, Strikethrough ⇧⌘X, Inline Code ⌥⌘C, —, Paragraph ⌥⌘0, Heading 1–6 ⌥⌘1–6, —, Bulleted List ⇧⌘7, Numbered List ⇧⌘9, Task List ⇧⌘L, Mark as Checked / Mark as Unchecked ⇧⌘U, Block Quote ⌘’, —, Increase Indent ⌘], Decrease Indent ⌘[, —, Insert ▸ (Code Block, Table, Horizontal Rule, Link… ⌘K, Image…), Table ▸ (unchanged).
- **View:** Show/Hide Sidebar, Show/Hide Toolbar, View Source/View Preview ⌥⌘U, Search Entries ⇧⌘F, —, Zoom In ⌘+, Zoom Out ⌘−, Actual Size ⌘0.
- **Entry list:** Delete / ⌘⌫ move the selected entry to Recently Deleted (Mac, iPad).
- **iPad:** the same File, Edit, Format and View commands in the iPadOS menu bar and ⌘-hold overlay.
- **Icons:** context menus and “…” menus show standard symbols: Change Date… (calendar), Move Entry… (folder), Save as Template… (doc.on.doc), Image Descriptions… (text.below.photo), Version History… (clock.arrow.circlepath), Find in Entry (magnifyingglass), Delete Entry (trash), Restore (arrow.uturn.backward), Delete Permanently… (trash.slash), Rename… (pencil), Default Template (doc.text), Delete Journal… (trash).

## 9. Settings (C1, C2, C4, C5)

- **Mac:** a standard Settings window with toolbar tabs and icons — General (gearshape), Sync (arrow.triangle.2.circlepath), Devices (laptopcomputer.and.iphone), Privacy (hand.raised), Backup (externaldrive), Agent Access (person.badge.key). Fixed width, height fits the tab, window title = tab name.
- **iPhone/iPad:** Settings list gains **Writing** and **Backup** rows with the same content.
- **Footers:** explanatory sentences move into section footers (grouped form style).
- **Privacy:** Encryption status; App Lock: when off, “Turn On App Lock…” opens a sheet (Enter PIN, then Confirm PIN, then “Use Touch ID” / “Use Face ID” switch, **Turn On**), when on: “Change PIN…”, the biometric switch, **Turn Off App Lock** (asks for the PIN). Change Password… (password libraries) comes from the sync-security work.
- **Backup:** Export Archive…, Import Archive… with the existing explanation as footer.
- **Name:** user-facing copy says “My Journal” wherever it names the app (“Unlock My Journal to open Settings.”, “Update My Journal to edit this entry.”).

## 10. Smaller polish

- Formatting sheet (iPhone): standard sheet navigation bar with “Format” title and the system close button.
- Remove the unreachable Journals settings pane (C8).

## Accessibility and states

All new menus and buttons have labels; alerts use standard roles so Return/Escape and VoiceOver behave natively; destructive buttons are marked destructive. Locked app: alerts and sheets close; Recently Deleted actions are unavailable while locked. Read-only (newer format) entries show no Delete/format actions that would modify them.

## Revision 1 — response to review (`owner-decisions-2026-09-25-review.md`)

- **Delete keys (P1).** Delete and ⌘⌫ act only while the entries list has focus (Mac: `onDeleteCommand` plus a list-scoped ⌘⌫ key handler); no menu item carries ⌘⌫, so ⌘⌫ in the editor keeps deleting to the start of the line.
- **Removal by sync (P1).** The open entry closes only when it has no unsaved writing (title or text differing from what's stored, a pending save, or a save failure). Otherwise it stays open with the writing intact.
- **After Delete** on Mac/iPad the next entry below (or above, at the end) opens, as in Notes; iPhone returns to the list. **Edit ▸ Undo Delete Entry** restores it. Rows get swipe actions: trailing **Delete** (Recently Deleted: Delete Permanently via the alert), leading **Restore** in Recently Deleted.
- **Recently Deleted** empty state stays “No Deleted Items”; items stay until deleted permanently (no automatic purge was requested), stated in the list footer: “Items stay here until you delete them permanently.”
- **Icons:** Delete Permanently uses `trash`; Save as Template… uses `doc.badge.plus`.
- **App Lock:** PIN is 6 or more digits (existing rule); mismatch: “The PINs don’t match.”; wrong PIN: “Wrong PIN. Try again.”; forgotten PIN: the existing “Forgot PIN?” path (unlock with the master password or recovery) stays; footer: “App Lock hides your journals on this device. It doesn’t change how they’re encrypted.” Mac uses one sheet with PIN and Verify fields.
- **Untouched new entry:** title and text empty after trimming whitespace, no images, date unchanged, template text unchanged. It's removed before it is synced. (Reversed on 30 September 2026; see §5.)
- **Search Entries** lives in Edit (below Find), ⇧⌘F. Zoom In keeps ⌘+. Spell-check underlines are also off in code and source. Mac checkbox label in sentence case: “Format Markdown as you type”. Camera access denied: “Allow camera access in Settings to take photos.” with **Open Settings**. Read-only entries show format controls disabled.

## Implementation record (2026-09-25)

Implemented as reviewed, then inspected on the Mac audit copy and the iPhone simulator. Deviations and fixes found during inspection:

- **Settings window height.** Fitting each tab to its content let sheets (Add Agent Access, agent details, Connect to a Server) become taller than the window. Tabs that present sheets now keep a minimum height of 440 pt; General still fits its content.
- **App Lock sheet (Mac).** A grouped form was taller than the Settings window; the Mac sheet is now a compact layout: title, PIN and Verify fields, a one-line note (“Use at least 6 digits.”, “The PINs don’t match.”, “Wrong PIN. Try again.”), the device-unlock checkbox, the footer sentence, then Cancel and the default button. The wrong-PIN note clears when the PIN is edited. The lock screen uses the same “Wrong PIN. Try again.” and the title “My Journal Is Locked”.
- **App menu.** Lock My Journal sits below Settings…, not above it. Its shortcut is ⌃⌘L; ⇧⌘L stays with Format ▸ Task List (a test now fails on any duplicate menu shortcut).
- **Add Agent Access (Mac).** Buttons are in one row: Back (confirmation step, leading), Cancel, then the default button. The confirmation copy no longer mentions archived entries and states that entries in Recently Deleted aren’t shared.
- **Agent Access pane.** The explanation moved to the section footer (C2).
- **iPhone state restoration.** After launch or unlock, the entry that was open reopens (as in Notes); going back to the list deselects it once saved, so a relaunch returns to the list. Journal switches never push an entry.
- **Agent connector.** The stdio connector waited for 4 KB of input before answering, so a real MCP client (which keeps standard input open) never received a reply. It now answers each request as it arrives; the connector test keeps standard input open like a client.
- **Post-implementation review** (`owner-decisions-2026-09-25-review.md`, final section) accepted all deviations after these changes: Lock My Journal moved to ⌃⌘L; the Mac App Lock sheet uses labelled fields (“Current PIN:”, “New PIN:”, “Verify:”), accepts digits only, announces errors to VoiceOver and returns focus to the PIN after a wrong PIN; the restored iPhone entry opens without animation and only when it is still editable in its journal; a camera restricted by Screen Time or management hides Take Photo, and a denied camera shows “Camera Access Is Off” / “Allow camera access in Settings to take photos.” with Open Settings; the agent confirmation is split into what’s shared and the risks.
- **Camera denied** was missing from the first implementation and was added.
