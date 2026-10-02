# Pre-release interface changes — 2026-09-27

Status: reviewed ([review outcome](#review-outcome)); all twelve items implemented. Items 1–5, 7–9 and 11 as revised by the review; items 6, 10 and 12 as the owner decided on 2026-09-27 ([owner decisions](#owner-decisions-2026-09-27)), which supersede owner-decisions-2026-09-25.md §6 and the §1 alert message.

Scope: twelve owner-approved changes that came out of the pre-release review (UI-1, UI-2, EDT-2, CRY-2, CRY-7, CRY-9, AGT-7, and the open items in [pre-release-fixes-2026-09-27.md](pre-release-fixes-2026-09-27.md)). Each change reuses an existing component, pattern or string where one exists. Apple Notes is the model; the Mac app is the reference and iPhone and iPad match its controls ([owner-decisions-2026-09-25.md](owner-decisions-2026-09-25.md)).

Conventions: “Mac”, “iPhone” and “iPad” describe the three layouts. iPad in a narrow window or at accessibility text sizes uses the iPhone’s stacked layout, as today. Copy is given verbatim, with the app’s curly quotes, apostrophes and ellipsis characters. `<name>`, `<date>` and similar are placeholders; `<date>` is the abbreviated date without a time (for example “27 Sep 2026” or “Sep 27, 2026”, depending on the region). File references are to the tree this record was written against.

## Summary

| # | Change | Platforms | Main files |
| --- | --- | --- | --- |
| 1 | Deleted templates go to Recently Deleted, with Restore, Undo and Delete Permanently | all | RootView, JournalNavigation, AppModel, JournalCore permanent deletion |
| 2 | “New Entry from Template…” sheet gets Cancel, Escape and Return | Mac (and iPad keyboard) | TemplateChooserView, AppCommands |
| 3 | Notice in the Mac window while writing is paused for a server connection | Mac | RootView, AppModel |
| 4 | Backspace at the start of a list, task or quote item removes its formatting | all | editor |
| 5 | iPhone Format sheet fits its content | iPhone | MobileFormattingPresenter |
| 6 | Search Entries becomes ⌥⌘F; Find and Replace… becomes ⇧⌘F | Mac, iPad | AppCommands, FindMenuShortcuts, FindKeyCommands |
| 7 | Footnote after copying the recovery key | all | RootView (RecoveryView) |
| 8 | Devices list says how each device was added | all | DevicesView, ServerClient |
| 9 | The new device confirms the check code before it accepts the pairing | all | ConnectionView |
| 10 | One-time master password check before the first archive export, with “Forgot Password?” | all | ArchiveView, PasswordCheckView, AppModel |
| 11 | Agent connection instructions warn about agents that can run commands | Mac | AgentController, AgentAccessView |
| 12 | Delete Permanently alert says copies may remain | all | PermanentDeletionView |

---

## 1. Deleted templates go to Recently Deleted (UI-1)

### Current behavior

- “Delete Template” (context menu, “…” menu, swipe, and Delete/⌘⌫ in the Mac list) calls the same `deleteSelected` as entries (`Views/RootView.swift:486-493`, `:495-501`, `:502-509`), which sets `deletedAt` (`Model/EntryDeletionOperations.swift:7-31`).
- Undo is registered only for entries (`Views/RootView.swift:516-526`).
- Templates lists only live templates (`Model/JournalNavigation.swift:33-35`, `:50-51`); Recently Deleted lists only entries and journals (`:56-57`, `Views/RootView.swift:276-318`).
- `restore` returns early unless the item is an entry (`Model/AppModel.swift:428-435`).
- JournalCore refuses to delete a template permanently (`PermanentDeletionPlan.prepare`, `JournalCore/PermanentDeletion.swift:41`), and a deletion marker may only have kind `journal` or `entry` (`PermanentDeletion.swift:75-81`, `protocol/permanent-deletion.md:9`).
- Result: a deleted template disappears with no way back, and journals that used it silently start blank entries.

### Design

Templates follow the entry flow exactly, as the owner decided for everything that is deleted (owner-decisions §1).

**Deleting.** “Delete Template” in the context menu and the “…” menu, trailing swipe “Delete”, and Delete or ⌘⌫ while the Templates list has focus on the Mac all move the template to Recently Deleted immediately, without a confirmation. On the Mac and iPad the next template below opens (or the one above, at the end of the list), as for entries. On iPhone the list stays in place (the open template closes and the stack goes back to Templates, as for entries). Edit ▸ Undo Delete Template (⌘Z) restores it.

**Recently Deleted.** The list gains a “Templates” section between the existing “Journals” section and the entries:

```
Recently Deleted
  Journals
    Travel                    3 entries on this device
  Templates
    27 Sep
    Daily Reflection
    What went well today?
  Entries
  September 2026
    …
```

- Template rows use the same row as in Templates (date, title, one preview line; `entryRow`), newest first like the Templates collection and the other Recently Deleted rows, without month headers inside the section.
- Search (“Search Deleted Items”) also matches template names and text.
- One footer: the owner-approved “Items stay here until you delete them permanently.” appears once, under the last section present (Journals, Templates or the last month of entries). The leftover row “Deleted items stay here until you restore or permanently delete them.” is removed; it said the same thing twice.
- The empty state “No Deleted Items” appears only when there are no deleted journals, templates or entries.
- Selecting a deleted template shows it read-only, with the same notice entries have (`EntryRecoveryNotice` style, `.quaternary` background) above the title on Mac, iPhone and iPad:
  - “This template is in Recently Deleted.”
  - Button: “Restore”
- Context and “…” menu for a deleted template: “Version History…” (clock.arrow.circlepath), “Restore” (arrow.uturn.backward), divider, “Delete Permanently…” (trash, destructive). Leading swipe “Restore”, trailing swipe “Delete” (asks with the alert below). Delete and ⌘⌫ in the Mac list open the same alert.

**Restoring.** Restore (menu, swipe, notice or Undo) clears the deletion and shows the template in Templates, selected, just as a restored entry opens in its journal. Nothing else changes.

**Default templates.** A journal keeps its default template setting while the template is in Recently Deleted. Meanwhile New Entry in that journal starts a blank entry (today’s behavior), and the journal’s Default Template submenu (sidebar context menu on the Mac, journal “…” menu on iPhone and iPad) shows the checkmark on “Blank Entry”, because that is what New Entry does. Restoring the template makes it the default again. If the person explicitly chooses “Blank Entry” while the template is in Recently Deleted, the stored default is cleared, so restoring the template later doesn’t bring it back as the default. After Delete Permanently, the journal stays on Blank Entry.

**Delete Permanently.** The existing alert, unchanged in wording:
- Title: “Delete “<template name>” Permanently?” (a template without a name: “Delete “Untitled Template” Permanently?”)
- Message: “You can’t undo this.”
- Buttons: “Delete” (destructive), “Cancel”.

The existing preparation errors apply unchanged (“This has changed since you chose to delete it. Check it and try again.” and so on).

**Templates empty state (related fix).** When the last template is deleted, Templates shows “No Entries” today (`Views/RootView.swift:333-339`). It shows “No Templates” instead, the string the template chooser already uses.

### Accessibility

- VoiceOver reads a deleted template row as one element, like entry rows, with the value “Template” (deleted journal rows already have the value “Journal”, `RootView.swift:290`).
- Section headers “Journals”, “Templates”, “Entries” are headers, as today.
- The notice’s Restore button is a standard button; keyboard focus order on the Mac and iPad: notice text, Restore, then the title.
- Dynamic Type: the notice text wraps; nothing new is fixed-height.

### Model and contract changes this needs

- JournalCore: `PermanentDeletionPlan.prepare` accepts a deleted template (affected records: just the template); a canonical marker may have kind `template`; a transactional `restoreTemplate(_:)` in `Store` that refuses conflicted or permanently deleted templates, as `restoreJournal` does.
- Protocol: `protocol/permanent-deletion.md` (“A canonical marker has kind `journal`, `entry` or `template`”) and the matching sentence in `records.md`. Nothing has shipped yet, so no earlier client depends on the old rule; a pre-release build that meets a template marker keeps it as an unreadable record, which is safe.
- Model: `deletedTemplates`, the Recently Deleted filter, `restore` for templates, Undo registration.

### Verification

- Unit (real store, `JournalTests/DeletionFlowTests`): deleting the open template lists it in Recently Deleted and opens the next template; Restore and Undo bring it back into Templates; a journal whose default template was deleted starts blank entries and uses the template again after Restore.
- JournalCore (`PermanentDeletionMarkerTests`): a deleted template becomes a canonical marker with its history removed; a live template is refused; an incoming template marker is applied like an entry marker.
- iOS UI test (new, iPhone 17): Templates → swipe Delete → Recently Deleted shows the Templates section → Restore → back in Templates → Delete again → Delete Permanently… → alert text → Delete → “No Deleted Items”, then relaunch. Screenshots: Recently Deleted with all three sections (light and dark), the deleted template’s notice, the alert.
- iPad Air 11-inch: screenshot of Recently Deleted and the notice in the three-column layout.
- Mac: Delete key and ⌘⌫ in the Templates list, Edit ▸ Undo Delete Template, the Recently Deleted list and notice (live window screenshot; if a live session isn’t available, an offscreen render, reported as such).

---

## 2. “New Entry from Template…” sheet: Cancel, Escape and Return (UI-2)

### Current behavior

- File ▸ New Entry from Template… presents `TemplateChooserView` as a sheet (`Views/RootView.swift:123-125`, `AppCommands.swift:17-18`). On the Mac that sheet has only a search field and the list; the Close button exists only on iOS (`Views/TemplateChooserView.swift:34-43`). With no templates it shows “No Templates” and there is no way out.
- The toolbar’s “Templates…” opens the same view as a popover, which closes on an outside click or Escape. That stays as it is.

### Design

Mac sheet (menu command only):

```
┌──────────────────────────────┐
│ 🔍 Search Templates          │
├──────────────────────────────┤
│ Daily Reflection             │
│ Gratitude                    │
│ Weekly Reflection            │
│ Workday Log                  │
├──────────────────────────────┤
│                     [Cancel] │
└──────────────────────────────┘
```

- A bottom bar with one button, “Cancel”, at the trailing edge (standard Mac sheet placement), 12 pt margins, below a divider. The list area keeps its current size; the sheet grows by the bar’s height.
- Escape and ⌘. choose Cancel, even while the search field has text. While an input method is composing (Japanese, Chinese and so on), Escape cancels the composition, not the sheet: Escape is handled through the responder chain (the search field’s cancel command), not as a window key equivalent, so the input method sees it first.
- The toolbar popover closes on Escape the same way, at once, even with text in the search field.
- Return creates an entry from the highlighted template (Up and Down move the highlight, as today). With nothing highlighted, Return does nothing. The highlight uses the system’s selected-row appearance (the accent selection color with white text, adapting to Increase Contrast), in the sheet and the popover, so it’s clear what Return will create; the faint tint it replaces was far below 3:1 (UI-17). Clicking a name still creates the entry at once. This is the reviewed rule: “Return activates only a selected live result, typing/highlighting never creates.”
- There is no Create button: the reviewed design has no Create step, and a name click already creates.
- While an entry is being created, Cancel is disabled (the sheet already can’t be dismissed then).
- File ▸ New Entry from Template… is disabled when there are no templates. The toolbar’s “Templates…” stays enabled and its popover says “No Templates”, as today.

iPad (menu command with a hardware keyboard) and iPhone: the sheet already has the Close button (xmark, label “Close”). It also responds to Escape (`.cancelAction`). No visual change.

Copy: “Cancel” (Mac). Existing: “Search Templates”, “No Templates”, “No Results”, “Close”.

### Accessibility

VoiceOver order: search field, template names, Cancel. Cancel is a standard button reachable with Tab under Full Keyboard Access.

### Verification

- Mac: live check of Escape, ⌘., Return with and without a highlighted row, and the disabled menu item with no templates; screenshot of the sheet with templates and with “No Templates”.
- iPhone UI test: open the chooser sheet from the toolbar, press Escape on the simulator’s hardware keyboard (`typeKey(.escape, modifierFlags: [])`), and assert it closed without creating an entry. iPad: the same by the menu command, checked live with a screenshot.

---

## 3. Writing paused while this Mac connects to a server (design-review (a))

### Current behavior

- While a connection is being set up, or a failed pairing keeps a staged copy for Try Again, nothing may change the open library (`Model/AppModel.swift:30-33`). The editor, title and formatting controls are disabled (`JournalNavigation.swift:168-173`), New Entry is disabled (`:41-43`), and even choosing another entry or collection is refused (`:68-74`, `:88-94`).
- The connection sheet explains this after a failed pairing: “Couldn’t finish connecting. Your local journals remain on this device. Try again, or cancel to keep writing.” (`Views/ConnectionView.swift:318-321`).
- On the Mac the sheet usually sits on the Settings window (Settings ▸ Sync, Settings ▸ Devices), so the main window looks normal but ignores typing and clicks, with no explanation.
- On iPhone and iPad the connection sheet is modal over Settings, and the app has a single window, so the editor can’t be reached. No change is needed there.

### Design (Mac only)

A notice at the top of the detail column, above whatever it shows (an entry, a deleted journal, or “Select an Entry”), in the style of the existing conflict notice (`ConflictNotice`: callout text, trailing button, `.quaternary` background, full column width):

```
┌───────────────────────────────────────────────────────────────┐
│ Writing is paused while this Mac connects     [Show Connection]│
│ to your server.                                                │
└───────────────────────────────────────────────────────────────┘
  Title
  Entry text (read-only while paused)
```

- Two states:
  - While connecting (shown after 1 second): “Writing is paused while this Mac connects to your server.”
  - While a failed pairing waits for Try Again (shown at once): “This Mac couldn’t finish connecting to your server. Try again, or cancel to keep writing.” This reuses the sheet’s own wording, so the two windows agree.
- Button in both states: “Show Connection” brings the Settings window with the connection sheet to the front (`openSettings`, which keeps the current tab, so the sheet is never removed).
- Shown while a server connection is being set up on this Mac (Connect, Set Up, Recover Journals, Add This Device) and while a failed pairing waits for Try Again. To avoid a flash during a quick connection, it appears only if the pause lasts longer than 1 second; after a failure it appears at once.
- Not shown during an archive import or a brief entry action (Move, Change Date, Restore): those pauses end on their own within moments and need no action.
- It disappears when the connection finishes (the window then shows the server’s journals) or when the person cancels the connection (writing continues at once). It fades in and out with the default animation; with Reduce Motion it appears and disappears without animation.
- On iPhone and iPad nothing changes.
- At accessibility text sizes the text and button stack vertically, as `ConflictNotice` already does.

### Accessibility

- The text and button are separate elements, text first. No announcement: the person started the connection in the other window, and the sheet already announces its errors.
- The button is reachable with Tab under Full Keyboard Access.

### Verification

- Unit: the model reports “writing paused for a connection” while a staged copy waits and while connecting, and not during an archive import; it clears after Cancel (`discardStagedVault`).
- Mac: a live check with a disposable local server (connect, force the install to fail as the existing pairing tests do), screenshot of the notice over an entry and over “Select an Entry”, and Show Connection bringing Settings forward; confirm the Settings window can’t be closed while the sheet is attached (if it can, closing cancels the connection, which ends the pause, which is also acceptable).

---

## 4. Backspace at the start of a list, task or quote item (EDT-2)

### Current behavior

The caret can no longer sit before or inside the hidden marker (`Editor/HiddenMarkers.swift:47-61`). Backspace at the start of an item’s text deletes the marker’s hidden tab, so the text slides under the bullet or checkbox, and a second Backspace removes the marker (`HiddenMarkers.swift:63-86`: “Deleting within a line’s own marker is left to the text view”; editor fix report, NEEDS OWNER). The saved text is correct either way.

### Design

As in Notes and Pages:

1. **First Backspace** with the caret at the start of a bulleted, numbered, task (checked or not) or block quote item’s text, and no selection:
   - Top-level item: the line becomes a plain paragraph (the same result as Format ▸ Paragraph ⌥⌘0). Its text, inline styles and the caret position stay; a task’s checkbox and checked state go.
   - Nested list item: it moves out one level (the same result as Decrease Indent ⌘[ or Shift-Tab). Repeated Backspaces move it out level by level, then turn it into a paragraph. This matches the reviewed rule for Return on an empty nested item (“outdents once, and at the outer level returns to Body”).
   - Block quote: the line becomes a paragraph. A nested quote (`> >`) steps out one quote level.
   - Innermost first, one level per Backspace: a list item inside a block quote first loses the list, then the quote.
2. **Next Backspace** (now at the start of a paragraph) joins the line with the one before it, as usual.

Details:
- Empty items behave the same way: the empty bullet becomes an empty paragraph, and the next Backspace removes the line.
- Backspace straight after a Markdown shortcut still restores exactly what was typed (“- ” comes back); that rule comes first.
- Option-Delete and ⌘-Delete at the start of an item do the same as Backspace, because they would also delete only the hidden marker.
- A selection, text before the caret, code blocks, tables, headings and source view are unchanged.
- Following items of a numbered list keep their numbers, as they do today after Decrease Indent on the first item.
- Holding Delete: the first press (or first repeat) removes the formatting and the repeats go on deleting as usual, as in Notes. Repeats aren’t swallowed.
- One undo step. Edit ▸ Undo shows “Undo Paragraph” (removed formatting) or “Undo Decrease Indent” (nested item), matching the Format menu’s names. The first ⌘Z brings the item back exactly.

Copy: none visible. VoiceOver announcements: “Paragraph” when the formatting is removed (the string Markdown shortcuts already announce), “Decrease indent” when a nested item moves out.

### Verification

- Unit tests in `JournalTests` (they run on both the Mac and iOS test targets, with the editor harness): for bullet, numbered, task, checked task and quote at top level, Backspace at the start keeps the text, makes a paragraph and saves Markdown without the marker; a nested bullet moves out one level; the second Backspace joins with the line above; Backspace straight after “- ” still restores the typed characters; ⌘Z restores the item. These protect the data path (a wrong range here loses or duplicates text).
- iPhone 17 UI check (screenshot): a task list, Backspace at the start of the second item, the checkbox is gone and the text stays in place.
- Mac: live check with the Delete key, Option-Delete and ⌘Z.

---

## 5. iPhone Format sheet fits its content

### Current behavior

On iPhone the Format sheet opens at the medium detent with a large detent above it (`Views/MobileFormattingPresenter.swift:46-50`). On an iPhone 17 (6.3-inch) it shows the inline row, Heading 1–3, Paragraph, More Headings, Bulleted List and Numbered List; Task List, Block Quote and Insert are below the edge and reachable only by scrolling or dragging the sheet up. Confirmed with the existing `EntryActionsUITests` screenshot “Visual formatting on iPhone” (iPhone 17, iOS 26.5, 27 Sep 2026). iPad uses a 300 × 520 pt popover in regular width, which already fits.

### Design

Keep the reviewed sheet (owner-decisions §10: “standard sheet navigation bar with “Format” title and the system close button”) and its contents, which match the Mac and iPad popover. Change only its height:

- One detent that fits the content: the measured height of the navigation bar plus every row the current selection offers (including the contextual Mark as Complete, indent and Exit Code Block rows). It is measured, not a constant, so smaller iPhones, Dynamic Type and the contextual rows are all handled. On an iPhone 17 at the default text size that is about 620 pt of the 874 pt screen, so every option from Bold to Insert is visible without scrolling.
- If the content is taller than the largest sheet height (larger text sizes, landscape, smaller iPhones), the sheet opens at the largest height and the list scrolls; the scroll indicator flashes once when it appears (iOS 17 and later), so the scrollable content is visible, not hidden.
- With a single detent there is nothing to drag to, so the grabber is hidden. Swiping down and the Close button still close it.
- If the rows change while the sheet is open (for example a text size change), the height is recalculated.
- The selection stays visible: when the sheet appears, the entry scrolls so the caret or selection sits above the sheet, as the text view does for the keyboard, and the entry returns to where it was when the sheet closes. (Inline styles such as Bold keep the sheet open, so the person must see the text they are styling.)
- iPad regular width (popover) and iPad accessibility sizes: unchanged.

Considered and not chosen: a panel like Notes’ format panel on iPhone (paragraph styles as a horizontal row of chips, list styles as a row of icons). It would be shorter and leave more of the text visible, but it would give iPhone different controls from the Mac and iPad popover, which the standing decisions ask to avoid, and would make list styles icon-only. The reviewer may prefer it; if so it needs its own design.

Copy: unchanged (“Format”, “Close” and the row labels).

### Accessibility

VoiceOver order unchanged: Close, then B, I, U, S, Inline Code, the paragraph styles, lists, Insert. Rows keep their 44 pt minimum height and grow with Dynamic Type. Reduce Motion uses the system’s sheet presentation.

### Verification

- iOS UI test (extends `EntryActionsUITests` on iPhone 17): after opening Formatting, “Task List”, “Block Quote” and “Insert” exist and are hittable without any scroll, and Close is hittable; repeated with the caret in a task item (Mark as Complete and the indent row shown). Screenshots light and dark.
- Same test launched at the largest accessibility text size (`-UIPreferredContentSizeCategoryName`): the sheet is at full height, Close is reachable, and scrolling reaches Insert. Screenshot.
- iPad Air 11-inch: screenshot of the unchanged popover.

---

## 6. Search Entries ⌥⌘F; Find and Replace… ⇧⌘F

**Owner: approved** (2026-09-27, supersedes owner-decisions §6). Approved by the review as written; also update the iPad ⌘-hold overlay listing and pre-release-fixes item (e).

### Current behavior

Edit ▸ Search Entries has ⇧⌘F (`AppCommands.swift:29-34`), because the standard Edit ▸ Find ▸ Find and Replace… has ⌥⌘F (owner-decisions §6). The owner has now approved ⌥⌘F for Search Entries.

Notes, checked in `/System/Applications/Notes.app` (its `MainMenu.nib` on this Mac): Edit ▸ Find ▸ Note List Search… ⌥⌘F, Find… ⌘F, Find and Replace… ⇧⌘F, Find Next ⌘G, Find Previous ⇧⌘G, Use Selection for Find ⌘E. Apple’s Notes keyboard-shortcut page lists ⌥⌘F as “Search all notes”.

### Design

Mac and iPad, same as Notes:

| Command | Shortcut |
| --- | --- |
| Edit ▸ Search Entries | ⌥⌘F (was ⇧⌘F) |
| Edit ▸ Find ▸ Find… | ⌘F (unchanged) |
| Edit ▸ Find ▸ Find and Replace… | ⇧⌘F (was ⌥⌘F) |
| Find Next, Find Previous, Use Selection for Find | unchanged |

- Search Entries keeps its name and its place in Edit, below Find (owner-decisions, revision 1). Notes puts its search command at the top of the Find submenu; moving it there isn’t part of this change.
- ⌥⌘F works wherever the focus is, including in the editor, and opens entry search exactly as ⇧⌘F does today (Mac: focuses the toolbar search field; iPad: opens the list’s search, also in stacked layouts).
- Find and Replace… keeps working; Replace is also reachable from the find bar itself.
- If the system’s Find and Replace… shortcut can’t be reassigned reliably on a platform, it is left without a shortcut rather than sharing ⌥⌘F, and this is reported as a deviation.
- Code comments that mention ⇧⌘F are updated (`RootViewAdaptations.swift:18`, `CompactJournalNavigation.swift:68`).

### Verification

- Mac: `MenuShortcutTests` keeps failing on any duplicate shortcut, and additionally checks that Edit ▸ Search Entries is ⌥⌘F and Find and Replace… is ⇧⌘F (this protects against the system menu silently winning).
- iPad UI test with a hardware keyboard (`typeKey("f", modifierFlags: [.command, .option])`) from the editor: the search field is focused and the editor keeps its text; ⌘F in the editor still opens Find in Entry.
- Mac live check of the Edit menu; screenshot.

---

## 7. Footnote after copying the recovery key (CRY-9, design-review regression 7)

### Current behavior

The recovery key screen has “Copy Recovery Key” (`Views/RootView.swift:814-849`, button at `:829`). It appears on Mac, iPhone and iPad for a library protected by a generated recovery key that hasn’t been confirmed yet, which today only libraries from early builds reach (new libraries use a master password or no encryption, `Model/NewVault.swift:17-34`). The copy stays on this device and is removed after 2 minutes (`Model/SensitivePasteboard.swift:10-33`), and nothing says so.

### Design

After “Copy Recovery Key” is chosen, a footnote appears directly below “Save Recovery Key…” and stays for as long as the screen is shown:

- “The copied key is removed from the clipboard after 2 minutes.”

Style: callout, secondary color, like the screen’s existing “Your recovery key is not a backup…” line. Before copying, nothing is shown, so the screen stays as it is for people who save the key to a file. Copying again doesn’t change it.

The sentence must be true. On iPhone and iPad the clipboard item expires by itself. On the Mac a timer clears it, which a quit would skip, so the Mac also clears the copied key when My Journal quits or locks, if nothing else was copied since (the same check the timer makes).

### Accessibility

VoiceOver announces the footnote when it appears (the button gives no other feedback). It follows the Save button in reading order.

### Verification

Screenshot of the screen after copying (Mac and iPhone), by rendering a legacy-key library created in a test fixture. No test: this is copy on one screen.

---

## 8. Devices list: how each device was added

### Current behavior

Each device is its own grouped section with separate rows: the name, “This Device”, “Added <date and time with seconds> · <first 8 characters of its ID>”, and “Revoke Access…” (`Views/DevicesView.swift:24-35`). The revoke dialog title is “Revoke access for <name> (<ID>)?” (`:60-71`). `ServerDevice` has `id`, `name`, `createdAt` and `revoked` (`JournalCore/ServerClient.swift:22-27`). Another fix adds `createdVia` (`setup`, `recovery` or `pairing`, absent for older devices) and `approvedByDeviceId` (the approving device’s ID, or null).

### Design

One calm row per device, then its Revoke button, in the same grouped sections:

```
┌─────────────────────────────────────────────┐
│ Alex’s MacBook Pro                          │
│ This Device                                 │
│ Added during server setup on 27 Sep 2026    │
└─────────────────────────────────────────────┘
┌─────────────────────────────────────────────┐
│ iPhone                                      │
│ Added by Alex’s MacBook Pro on 28 Sep 2026  │
├─────────────────────────────────────────────┤
│ Revoke Access…                              │
└─────────────────────────────────────────────┘
```

- The name, “This Device” (only for this device, unchanged string) and the “Added” line form one row: name in the body style, the other lines secondary. Today they are two or three separate rows.
- The date has no time, and the ID prefix is gone from the row (UI-16).
- “Added” line, by how the device joined:

| `createdVia` | Text |
| --- | --- |
| `pairing`, approving device found in the list (including revoked devices) | “Added by <device name> on <date>” |
| `pairing`, approving device unknown or null | “Added with a pairing code on <date>” |
| `setup` | “Added during server setup on <date>” |
| `recovery`, master password library | “Added with your master password on <date>” |
| `recovery`, recovery key library | “Added with your recovery key on <date>” |
| `recovery`, access password library | “Added with your access password on <date>” |
| `recovery`, server recovery code | “Added with a recovery code on <date>” |
| absent or unknown | “Added on <date>” |

- Duplicates: on iOS 16 and later the app sees generic device names (“iPhone”, “iPad”), so two iPhones, or one iPhone after reinstalling, often look alike. When two or more listed devices would show the same name and the same “Added” sentence, the sentence gets the time: “Added by <device name> on <date> at <time>” (short time), and likewise for every other variant, for example “Added with a pairing code on <date> at <time>”. Only if they would still be identical (same minute) is the short ID appended as a last resort: “… · <first 8 characters of its ID>”. This follows the reviewed rule for duplicate template names (“show a short identifier only when needed”).
  The recovery wording follows this library’s credential, the same distinction `credentialName` makes (Master Password, Recovery Key, Access Password, Recovery Code); each is a full sentence so it can be translated.
- Revoke dialog: title “Revoke access for <name>?” (no ID). Message unchanged: “This stops future sync. Journals already downloaded to that device can’t be erased remotely.” When another listed device has the same name, the message starts with that device’s (disambiguated) “Added” sentence, for example “Added by Alex’s MacBook Pro on 28 Sep 2026 at 14:05. This stops future sync. Journals already downloaded to that device can’t be erased remotely.”
- Loading, error, “Connect Again…”, “Try Again” and “Add Device…” states are unchanged.

### Accessibility

- The device row is one VoiceOver element: “iPhone, Added by Alex’s MacBook Pro on 28 September 2026”.
- The Revoke button’s accessibility label names the device: “Revoke access for iPhone”; when names are duplicated it adds the same disambiguated “Added” sentence.
- Lines wrap at large text sizes; nothing is truncated.

### Verification

- JournalCore test: `ServerDevice` decodes with and without the new fields, and with an unknown `createdVia` value (an older or newer server must never break the Devices list).
- The native pairing UI test (`JournalUITests.testPairDeviceAndDownloadEncryptedEntry`, run with `scripts/test-native-pairing.sh` against a disposable server once the server fields exist): after pairing, Settings ▸ Devices on the new device shows “Added by Fixture Mac on …” for itself and “Added during server setup on …” for the fixture device. Screenshots on iPhone 17 and iPad; Mac Settings ▸ Devices screenshot.

---

## 9. The new device confirms the check code (CRY-2)

### Current behavior

The approving device asks “Does <name> show this code?” with “Approve only if the codes match. <name> will be able to read and sync all your journals.” and Approve (⌘Return) (`Views/DevicesView.swift:155-164`, `:197-205`). The new device shows the check code with “Make sure your other device shows the same code.” but installs the journals as soon as the approval arrives, without asking (`Views/ConnectionView.swift:249-257`, `:274-286`). The grant is already bound to the key behind the displayed code (`JournalCore/Pairing.swift:165-185`); what’s missing is the person’s confirmation on this side.

### Design

Both devices ask. Nothing from the other device is accepted on the new device until the person confirms here, in whichever order the two confirmations happen.

New device, after the other device has entered the pairing code:

```
Connect to a Server
[https://journal.example.ts.net      ]

Check Code
123 456
Connect only if your other device shows the same code.

[Cancel]                                    [Connect]
```

- Replaces “Make sure your other device shows the same code.” with “Connect only if your other device shows the same code.”
- Buttons: “Cancel” (leading) and “Connect” (trailing, prominent). “Connect” is the specific verb: the sheet already uses “Continue” for the address step, and the button connects (“Connecting…”), mirroring “Approve” on the other device. On the Mac, Connect is ⌘Return, not plain Return, like Approve (tooltip “Connect (⌘Return)”, accessibility hint “Press Command-Return to connect.”). Escape chooses Cancel on Mac and iPad keyboards.
- After Connect: Connect disappears and, if the other device hasn’t approved yet, the existing “Waiting for approval on your other device…” progress shows below the code. When the approval is there, “Connecting…” shows, and the sheet closes when the journals are in place, as today.
- If the approval arrives before Connect, nothing is installed and nothing changes on screen; the device waits for Connect.
- **Codes don’t match:** the person chooses Cancel. The pairing request is cancelled, nothing from the other device is used, and the sheet closes with this device unchanged. If the other device had already approved, this device’s new server access is revoked right away (best effort), so it doesn’t stay in the Devices list; if that fails (offline), it can be revoked from the other device, where it shows as “Added by …”. If the other device is still waiting or asking, it reports “This pairing code has expired.” when it next contacts the server (existing behavior; its Cancel also works). The review asks for “Pairing was canceled.” there instead (the string from screens.md revision 2); the server answers 404 for expired and cancelled requests alike, so this needs a server change first (recorded under “Work outside the views”).
- Existing states are unchanged: “This pairing code has expired.” with Get New Code, “Your other device didn’t approve this request.”, “Couldn’t add this device securely. Get a new code and try again.”, and locking cancels the pairing.

VoiceOver announcement when the code appears: “Check code 1 2 3 4 5 6. Connect only if your other device shows the same code.” (replaces “… Make sure your other device shows the same code.”)

iPhone and iPad: the same content and buttons in the connection sheet, in the places the sheet already uses for Cancel and its primary button. The approving device’s copy doesn’t change.

### Accessibility

The code is read digit by digit (existing). Connect is a standard button; VoiceOver users hear the instruction before reaching it. Dynamic Type: the code and text wrap.

### Verification

- Native pairing UI test (disposable server, iPhone 17): the fixture approves first; the app keeps showing the check code and Connect, and after 3 seconds no journal has arrived; after Connect the synced entry appears. A second run cancels after the approval: nothing is installed, the local library is unchanged, and the fixture’s device list shows the new device revoked. Screenshots of the confirm step and of “Waiting for approval on your other device…”.
- Unit: the install can’t start without the confirmation, whichever arrives first.
- After implementation, `SECURITY.md` (“approve only if the codes match”) and `protocol/README.md` (pairing steps) must say that both devices confirm. That is a docs change for the docs owner.

---

## 10. One-time check of the master password (CRY-7)

**Owner: approved in part** (2026-09-27). Implemented: the check before the first archive export and “Forgot Password?”, with the review’s changes and copy. Declined: the one-time check at launch. See [Owner decisions](#owner-decisions-2026-09-27); the text below is the original proposal.

### Current behavior

The master password is typed once, in one field, with no confirmation (a reviewed decision: “No generation button or confirmation field”, notes-alignment-revision). The library is marked confirmed at once (`Model/AppModel.swift:221-223`). This device then opens with its device key, so a mistyped password goes unnoticed until it is needed.

Where the password is already checked: setting up a server from this library (`AppModel.swift:589-596`), Use This Mac as your server (`Views/LocalServerView.swift:155-162`), Recover Journals, unlocking with the password, and Change Password (which needs the current one, `Views/ChangePasswordView.swift:43-50`). So every server-connected library has had its password typed correctly at least once. The unchecked case is a library that only lives on this device and is backed up with Export Archive; an archive is useless if the password is wrong.

### Options considered

- A Settings “Check Password…” action: least intrusive, but it catches nothing unless someone thinks to use it, and it adds a row nobody needs later. Not chosen alone.
- Before the first server connection: already covered by the checks above.
- A prompt some days after the library was created (like iPhone asking for the passcode now and then when Face ID is used): effective, but interrupts writing at a moment unrelated to the password.
- **Chosen: before the first archive export.** That is the moment a backup starts depending on the password, the person is already doing a backup task, and it happens at most until the check succeeds once. It is never forced: “Not Now” continues the export.

### Design

When the person chooses Export Archive… (Settings ▸ Backup, or File ▸ Export Archive…) and this library has a master password that hasn’t been checked, a sheet appears before the archive is prepared:

```
Check Your Password

Enter your master password to make sure it’s the one you saved.
You’ll need it to open this archive.

[Master Password                    ]

[Not Now]                                   [Check]
```

- Title: “Check Your Password”
- Text: “Enter your master password to make sure it’s the one you saved. You’ll need it to open this archive.”
- Field: “Master Password” (secure; password AutoFill offered, which is fine: a saved password that works is what we want to know).
- Buttons: “Not Now” (cancel position; Escape) continues the export without checking, and asks again at the next export. “Check” (default; Return) checks the password against this device’s copy of the password envelope, entirely on this device.
- Correct: the sheet closes and the export continues (“Preparing Archive…”, then the save dialog). It is never asked again for this library.
- Wrong: “That isn’t your master password. Try again.” in red below the field, announced to VoiceOver, field cleared and focused. Nothing else changes.
- After a wrong attempt, and only for a library that isn’t connected to a server, a third button appears below the field: “Set New Password…”. It opens Change Password without the Current Password field:
  - Title: “Set New Password”
  - Text: “Your journals are only on this device, so you can set a new password here. Use it to open archives you make from now on.”
  - Fields: “New Password”, “Confirm New Password”; footer “Use at least 12 characters.”, mismatch “The passwords don’t match.” (existing strings)
  - Buttons: “Cancel”, “Set”
  - After Set, the check counts as done and the export continues.
- The check also counts as done, silently, whenever the app has verified the password another way: setting up or joining a server, Use This Mac, Recover Journals, unlocking with the password, Change Password, and importing an archive into an empty library. Libraries already connected to a server when this ships are treated as checked. Libraries protected by a recovery key, a recovery code, or no encryption are never asked.
- No Settings row is added.

Conflicts and decisions: this keeps the reviewed single password field. “Set New Password…” without the current password is new: for a library that exists only on this device it re-protects the same key with a new password, which someone with the unlocked device could already use to read everything. It needs crypto review and the owner’s approval; without it, a person who can’t reproduce their password has no way forward except creating a new library. If it’s declined, the wrong-password state keeps only “Try Again” and “Not Now”.

### Accessibility

Initial focus in the field. Error announced. Standard Return and Escape handling on Mac and iPad keyboards. At large text sizes the sheet scrolls and its buttons stay in the navigation bar (iPhone and iPad) or the bottom bar (Mac).

### Verification

- Unit (real store and configuration): the check is pending only for an unchecked master-password library; a wrong password leaves it pending; the right one clears it; a server setup clears it; Set New Password re-protects the same key (the old password no longer opens the envelope, the new one does, all entries are intact, an archive made afterwards opens with the new password).
- iOS UI test (iPhone 17): create a password library, Settings ▸ Backup ▸ Export Archive…, wrong password (error shown), right password (save dialog appears), then Export Archive… again goes straight to the save dialog. Screenshots of the sheet, the error and Set New Password.
- Mac: screenshot of the sheet over Settings ▸ Backup and over File ▸ Export Archive….

---

## 11. Agent connection instructions: agents that can run commands (AGT-7)

### Current behavior

The copied instructions end with “Keep this connection file private. Anyone who can use it on this Mac can read these journals while My Journal is unlocked.” (`Model/AgentController.swift:192`). Below “Copy Connection Instructions” the agent detail sheet says “Keep this connection file private.” (`Views/AgentAccessView.swift:206-207`). Neither says that an agent that can run commands or read files can reach every connection on this Mac.

### Design

- Instructions text: after the “Keep this connection file private…” line, add the line “An agent that can run commands or read files on this Mac can use every agent connection on this Mac.”
- Detail sheet, below Copy Connection Instructions: replace “Keep this connection file private.” with “An agent that can run commands or read files on this Mac can use every agent connection on this Mac.” (The advice to keep the file private stays in the copied instructions, where the file is named; the old footnote under a button that copies instructions was confusing, UI-16.)
- Add Access confirmation (the decision point): the risk paragraph becomes “A cloud agent may send this content to its provider. An agent that can run commands or read files on this Mac can use every agent connection on this Mac. Revoking access stops future reads but can’t retract content already read.”
- Copied instructions only (technical readers): after the new line, “To prevent this, don’t let such agents read the agent-connections folder.”

### Verification

Mac screenshot of the agent detail sheet and a check of the copied text. No test (copy only).

---

## 12. Delete Permanently alert

**Owner: note added** (2026-09-27, supersedes the owner-decisions §1 alert message). See [Owner decisions](#owner-decisions-2026-09-27); the text below is the original analysis.

### What happens

- Locally, each affected record is replaced by a content-free marker and its Version History is removed, in one transaction (`JournalCore/StoreDeletion.swift:35-66`). The marker syncs to other connected devices, which remove the item from their lists and history.
- The server keeps every earlier encrypted revision in its change log (`server/src/Journal.Api/Features/SyncEndpoints.cs:122-128`) and in its backups; archives, disconnected devices and earlier library copies keep their copies; image files are kept (`protocol/permanent-deletion.md:3`, `SECURITY.md:28-29`, `:59`).

### The alert

Title “Delete “<name>” Permanently?” (journal with entries: “Delete “<name>” and Its Entries Permanently?”), message “You can’t undo this.” (journal: “Its <n> entries are deleted too. You can’t undo this.”), buttons Delete and Cancel (`Views/PermanentDeletionView.swift:46-60`). The owner chose this plain alert (owner-decisions §1).

Every claim in it is true: the item leaves the app on this and other devices, Restore is gone and there is no Undo. It doesn’t claim that server revisions, backups or archives are erased, and “Permanently” is the term Notes uses for the same action. The retention details are documented in SECURITY.md and the protocol. **No change.** If the owner later wants the retention stated in the alert, the existing sentence “Copies may remain in archives, backups, and server history.” (`DeletionConsequences`) is available.

---

## Conflicts with earlier decisions

- **6** supersedes owner-decisions §6 and its revision (“Search Entries ⇧⌘F; ⌥⌘F is taken by Find and Replace”); Find and Replace… moves to ⇧⌘F as in Notes. Approved by the owner.
- **12** supersedes the §1 alert message, in the owner’s wording. Approved by the owner.
- **1** extends the permanent-deletion contract to templates (protocol change, pre-release).
- **2** adds a button bar to the Mac sheet only; the reviewed popover (“only search and names”) is unchanged.
- **5** keeps the reviewed sheet and its contents; only the height changes.
- **10** keeps the reviewed single password field. The owner approved the export check and “Forgot Password?” and declined the launch trigger.
- **8** removes the device ID from the Devices list (UI-16), keeping it only as the last resort for identical rows.

## Work outside the views

The implementation touches, besides `apps/apple/JournalApp/Views` and `AppCommands.swift`:

- JournalCore: `PermanentDeletion.swift` and `Store.swift` (templates, item 1); `ServerClient.swift` (`ServerDevice` fields, item 8, unless the server fix adds them); tests.
- Model: `AppModel.swift`, `EntryDeletionOperations.swift`, `JournalNavigation.swift`, `PermanentDeletionOperations.swift`, `LocalConfiguration.swift` (password check state), `AgentController.swift` (instructions text).
- Editor: `HiddenMarkers.swift`, `MarkdownShortcutEditing.swift`, `StructuredKeyboard.swift` (item 4).
- Protocol and docs: `protocol/permanent-deletion.md`, `protocol/records.md` (item 1); `SECURITY.md`, `protocol/README.md` (item 9, docs owner); this record and the design index.
- Server (another area): to show “Pairing was canceled.” on the approving device when the new device cancels (item 9), the server must answer a cancelled request differently from an expired one (today both are 404 `pairing_not_found`).
- Owner: the protocol keeps image files after permanent deletion; either delete unreferenced local image files then, or accept it as a documented limitation (review, item 12).

## Verification environment

iPhone 17 simulator (9B3CCED7-1642-421B-8FDD-49D063087377, 6.3-inch, iOS 26.5) and iPad Air 11-inch simulator (828C689A-14CC-4E7E-B160-E71B850F1600); the Mac app built with Apple Development signing and an isolated data folder. Screenshots in light and dark mode, at the default and the largest accessibility text size for iPhone items. Anything that can’t be inspected live is reported as not verified, with what was checked instead.

## Review outcome

Independent design review, 2026-09-27 (design agent that didn't write the proposal; it read the code and documents and parsed Notes’ menu nib, but didn’t run the app). All changes it required for the implemented items are applied above.

| # | Verdict | What changed in this record |
| --- | --- | --- |
| 1 | Approve with changes | Deleted templates sort newest first (not by name); “Untitled Template” in the alert; one footer, the leftover row removed; choosing “Blank Entry” explicitly clears the stored default. |
| 2 | Approve with changes | Escape handled through the responder chain so input methods keep it while composing; the highlight uses the system selected-row appearance; Escape closes the popover and the sheet the same way. |
| 3 | Approve with changes | Two states: “Writing is paused while this Mac connects to your server.” and, after a failed pairing, “This Mac couldn’t finish connecting to your server. Try again, or cancel to keep writing.”; vertical layout at accessibility sizes. |
| 4 | Approve with changes | Ruling: nested items outdent one level. Innermost first (list in a quote loses the list, then the quote; `> >` steps out one level); key repeats aren’t swallowed. |
| 5 | Approve with changes | Ruling: fitted sheet, not a Notes-style panel. The height is measured; the caret or selection scrolls above the sheet and back. |
| 6 | Approve | Held for the owner (decided 2026-09-27, see below). |
| 7 | Approve with changes | The Mac clears the copied key on quit and lock, so the footnote is true. |
| 8 | Approve with changes | Ruling: remove the ID, but disambiguate duplicate names with the time, then the short ID; realistic names in the mockup. |
| 9 | Approve with changes | “Connect” instead of “Continue”; “Connect only if your other device shows the same code.”; tooltip “Connect (⌘Return)”, hint “Press Command-Return to connect.” “Pairing was canceled.” on the approving device needs a server change. |
| 10 | Approve with changes (material) | Held for the owner (decided 2026-09-27, see below) and crypto review. Required: also ask once at launch or unlock, the first time My Journal opens at least one day after the library was created (unchecked master-password library not on a server; before the editor takes focus), with “Enter your master password to make sure it’s the one you saved. You’ll need it to open your journals on a new device or from a backup.”; after Not Now it isn’t shown at launch again. Wrong password: “Wrong password. Try again.” Disable Check and Not Now with a small progress indicator while checking. One trigger point: the Export Archive… button in `ArchiveExportControls`. Instead of “Set New Password…”: a link-style “Forgot Password?” after one wrong attempt, opening “Set New Password” after device owner authentication (reason “set a new password for your journals”), only for libraries not on a server and never from the lock screen, with “Your journals are only on this device, so you can set a new password without the old one. Archives you exported before still need the old password.”, fields “New Password” and “Confirm New Password”, footer “Use at least 12 characters.”, mismatch “The passwords don’t match.”, buttons “Cancel” and “Set Password”. |
| 11 | Approve with changes | The sentence is also added to the Add Access confirmation’s risk paragraph; optional line in the copied instructions added. |
| 12 | Reject “no change” | Held for the owner (decided 2026-09-27, see below). Proposed: keep title, buttons and style; message “Copies may remain in archives, backups, and server history. You can’t undo this.” for a library connected to a server, “Copies may remain in archives and backups. You can’t undo this.” otherwise, each with the “Its 3 entries are deleted too.” prefix for journals with entries. |

The image-file retention question under item 12 is still open for the owner.

## Owner decisions, 2026-09-27

- **6 — match Notes.** Search Entries ⌥⌘F; Edit ▸ Find ▸ Find and Replace… ⇧⌘F, on the Mac and on iPad hardware keyboards. This supersedes owner-decisions-2026-09-25.md §6 and its revision (that record is left as it was). Implementation: `AppCommands` gives Search Entries ⌥⌘F. The system Find menu gives Find and Replace… ⌥⌘F, and SwiftUI then leaves Search Entries without its shortcut, so on the Mac `FindMenuShortcuts` moves the system item to ⇧⌘F as soon as it is added to the menu bar (before the app’s commands) and again if the menu is rebuilt; on iPad `FindKeyCommands` does the same while the menu bar is built. No UI test used the old shortcuts.
- **12 — add the note.** The alert message is “You can’t undo this. Copies may remain in archives, backups, and server history.” For a journal with entries the first sentence stays: “Its 3 entries are deleted too. You can’t undo this. Copies may remain in archives, backups, and server history.” (“Its entry is deleted too.” for one). The same message is used whether or not the library is on a server. This supersedes the owner-decisions-2026-09-25.md §1 message; the title, buttons and style are unchanged.
- **10 — only (a) and (b):**
  - (a) The one-time “Check Your Password” sheet before the first archive export, from the Export Archive… button (Settings ▸ Backup and File ▸ Export Archive…, both through `ArchiveExportControls`). Only for a master-password library that isn’t on a server and hasn’t passed the check. Copy as proposed, with the review’s changes: “Enter your master password to make sure it’s the one you saved. You’ll need it to open this archive.”, field “Master Password”, buttons “Not Now” (Escape; continues the export and asks again next time) and “Check” (Return). While checking, both buttons and the field are disabled and a small progress indicator shows. Wrong: “Wrong password. Try again.”, announced, the field cleared and focused. Right: the sheet closes and the export continues; never asked again. The check also counts as done after Recover Journals, Change Password and importing a password-protected archive into an empty library; a library on a server is never asked.
  - (b) “Forgot Password?” (a borderless button below the error) after one wrong attempt, only for a library that isn’t on a server, and only where the device can authenticate its owner. It asks for device owner authentication (Face ID, Touch ID, or the device passcode or login password; reason “set a new password for your journals”) and then shows “Set New Password” in the same sheet: “Your journals are only on this device, so you can set a new password without the old one. Archives you exported before still need the old password.”, fields “New Password” and “Confirm New Password”, footer “Use at least 12 characters.”, mismatch “The passwords don’t match.”, buttons “Cancel” (back to the check) and “Set Password”. It protects the same vault key with the new password (the journals stay encrypted as they are; nothing is re-encrypted), counts as the check, and the export continues. The model refuses it for a library on a server and unless the device owner authenticated in the last five minutes, once per authentication. Never offered from the lock screen.
  - Declined: the extra one-time check at launch a day after setup.
  - Added during implementation (not reviewed copy): if saving the new password fails, “Couldn’t set a new password. Your current password still works.” On a device without a passcode or biometrics, “Forgot Password?” isn’t shown, because the owner can’t be authenticated.

## Implementation notes, 2026-09-27

Deviations found while inspecting the running app, and how they were resolved:

- **2, iPhone and iPad:** Return in the template search did nothing before something was typed, because the search field only enables its Return key once it has text. It now always creates the highlighted template. The arrow keys needed priority over the search field’s own handling of them. Escape uses the same key commands, but a UI test can’t send Escape to a simulator, so on iOS it is checked by code only; on the Mac the field handles Escape through `cancelOperation`, after an input method has finished composing.
- **5:** The sheet’s height is measured from the sheet’s top to the end of its last row in window coordinates (a named coordinate space doesn’t reach into the sheet’s navigation controller, which made the first build fill the screen). Where the entry was scrolled is remembered before the sheet opens and the keyboard goes away, and restored against that size, so the caret line isn’t left under the keyboard afterwards.
- **6, Mac:** SwiftUI leaves out a command’s shortcut when a system menu item already has it, so the system Find and Replace… item is moved to ⇧⌘F as soon as it is added to the menu bar, before the app’s commands. `MenuShortcutTests` checks ⌥⌘F, ⇧⌘F and ⌘F.
- **6, iPad:** UIKit leaves a command out of the menu bar when its shortcut is taken, and the app’s commands are added before the app can change the system’s. Search Entries is therefore added with ⇧⌘F and the two shortcuts are swapped while the menu bar is built; SwiftUI still recognizes its command by its property list. Checked in the iPad simulator: ⇧⌘F in the entry opens Find and Replace, and ⌥⌘F with the entry closed for editing opens the list search. **Open deviation:** while the entry is being edited, ⌥⌘F still opens Find and Replace in the simulator; the text view’s find interaction answers it before the menu bar, and neither a key command of the text view’s own nor overriding its Find and Replace action changed that. The simulator runs these tests with the on-screen keyboard, so this needs a check on an iPad with a hardware keyboard before it is treated as done.
- **10, iPhone:** “Check Your Password” and “Set New Password” were cut off in the inline title between the two buttons, so the sheet uses a large title on iPhone and iPad. Checked in the iPhone simulator: the sheet, “Wrong password. Try again.” with Forgot Password?, the device owner prompt (“set a new password for your journals”), and the save dialog after the right password. The simulator asks for its passcode, so the Set New Password form was checked as a rendering, and its behavior by unit tests.

