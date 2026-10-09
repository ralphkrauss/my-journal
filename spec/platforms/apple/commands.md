# Commands on Apple

Where every command in [commands.md](../../commands.md) appears on iPhone, iPad and the Mac, its shortcut and what differs. One row for each command id, in the order of `commands.md`; the checker verifies that every id has exactly one row here. What a command means, its scope, when it is enabled and what it does are in [commands.md](../../commands.md); this file holds only where the Apple apps place it and how it is invoked. Behaviour is in the screen and flow files named there; labels are copy keys from [copy/en.json](../../copy/en.json).

Shortcut symbols: ⌘ Command, ⌥ Option, ⇧ Shift, ⌃ Control, ↩ Return, ⎋ Escape, ⌫ Delete. “—” means none. “System” means the platform supplies the item; the app doesn't define it. Sheets follow the platform's default and cancel keys (Return for the default button, Escape for Cancel) unless a row says otherwise. Buttons that hand over the journals' key or merge journals use ⌘↩ instead of ↩, so they can't be chosen before reading.

Abbreviations: **Mac** = computer (menu bar, toolbar, context menus). **iPad** = tablet (menu bar and ⌘-hold shortcut list with a hardware keyboard, plus on-screen controls). **iPhone** = phone (on-screen controls; a hardware keyboard reaches only the text view's own shortcuts, marked *text*). “Formatting” = the Formatting surface ([screens/format-sheet](../../screens/format-sheet.md)). “Bar” = the writing controls (bottom bar while reading, keyboard accessory while writing).

Areas: [Menu bar](#menu-bar), [Toolbars, context menus and swipes](#toolbars-context-menus-and-swipes), [Keyboard in lists, sheets and choosers](#keyboard-in-lists-sheets-and-choosers), [Editor](#editor) and [Settings](#settings).

## Menu bar

On the Mac the menus are My Journal, File, Edit, Format, View, Window, Help. iPad with a hardware keyboard shows File, Edit, Format, View and Help with the same commands (and lists them in the ⌘-hold overlay), except where the iPad column says “—”.

| id | Mac placement and shortcut | iPad shortcut | iPhone and iPad placement | Notes |
| --- | --- | --- | --- | --- |
| `about` | My Journal ▸ About My Journal | — | — |  |
| `open-settings` | My Journal ▸ Settings… ⌘, | — | Journals screen top left (iPhone); last sidebar row (iPad) | Mac: the menu item uses the system's label. The iPad row is dimmed in journal edit mode. |
| `lock-my-journal` | My Journal ▸ Lock My Journal ⌃⌘L (below Settings…) | — | Settings ▸ Privacy, App Lock section (button) |  |
| `quit`, `hide`, `services` | My Journal ▸ Services, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q | — | — |  |
| `new-entry` | File ▸ New Entry ⌘N | ⌘N | Bottom bar (Journals screen and every list), icon only | Reopens the Mac window if closed. The bar buttons don't need a journal; the File menu item does. ⇧⌘N, which was New Blank Entry in 1.0, is free. |
| `use-a-template` | File ▸ Use a Template… (sheet, 320 points wide); the link in an empty entry (popover) | — | iPad with a keyboard: File ▸ Use a Template… (sheet; also in the ⌘-hold overlay, with New Entry and New Journal…). The link in an empty entry: popover on iPad in regular width, sheet on iPhone and in compact width | The menu item is dimmed, not hidden, unless the link is shown. The VoiceOver label of the link is `library.templateChooser.useTemplate`. Replaces File ▸ New Entry from Template… of 1.0. |
| `new-journal` | File ▸ New Journal… ⌥⌘N | ⌥⌘N | Journals screen top right (iPhone); sidebar bar (iPad); toolbar `library.toolbar.newJournal` | On the Mac leaves Editor Only. |
| `pin-entry` | File ▸ Pin Entry / Unpin Entry (own group after New Journal…; no shortcut) | — | Leading swipe, context menu, Entry Actions |  |
| `import-archive` | File ▸ Import Archive… | — | Welcome screen; Settings ▸ Backup (button) |  |
| `export-archive` | File ▸ Export Archive… | — | Settings ▸ Backup (button); the Erase warning |  |
| `export-markdown` | File ▸ Export Journals as Markdown… | — | Settings ▸ Backup (button) |  |
| `delete-all-recently-deleted` | File ▸ Delete All in Recently Deleted… ⇧⌘⌫ (after a separator) | — | Recently Deleted bar, top right | The button is “Delete All…” in the Recently Deleted bar. |
| `close-window` | File ▸ Close ⌘W | — | — |  |
| `undo`, `redo` | Edit ▸ Undo ‹name› ⌘Z, Redo ‹name› ⇧⌘Z | ⌘Z, ⇧⌘Z; keyboard bar undo and redo | system (shake, three-finger gestures) | In a table cell ⌘Z and ⇧⌘Z undo the entry. |
| `edit-text` | Edit ▸ Cut ⌘X, Copy ⌘C, Paste ⌘V, Paste and Match Style ⌥⇧⌘V, Delete, Select All ⌘A | same | Edit menu; text context menu |  |
| `paste-and-match-style` | Edit ▸ Paste and Match Style ⌥⇧⌘V | Edit menu | Edit menu |  |
| `find` | Edit ▸ Find ▸ Find… ⌘F (find bar above the entry), Find and Replace… ⇧⌘F, Find Next ⌘G, Find Previous ⇧⌘G, Use Selection for Find ⌘E, Jump to Selection ⌘J | ⌘F, ⇧⌘F (Find and Replace…) | Entry Actions ▸ `library.entryActions.findInEntry` (system find navigator) | Find and Replace… is moved from ⌥⌘F to ⇧⌘F. |
| `search-entries` | Edit ▸ Search Entries ⌥⌘F (below Find) | ⌥⌘F (iPadOS 17 or later; not offered before) | the list's search field |  |
| `text-editing-system` | Edit ▸ Spelling and Grammar, Substitutions, Transformations, Speech, Start Dictation, Emoji & Symbols | — | system keyboard settings |  |
| `format-*` | Format menu | the same, including Table ▸ | Formatting controls in the editor |  |
| `toggle-sidebar` | View ▸ Show Sidebar / Hide Sidebar ⌃⌘S | system | the sidebar button (iPad) |  |
| `toggle-toolbar` | View ▸ Show Toolbar / Hide Toolbar ⌥⌘T | — | — |  |
| `show-editor-only` | View ▸ Show Editor Only / Show Sidebar and List ⇧⌘D | — | — |  |
| `previous-entry` | View ▸ Previous Entry ⌥⌘↑ | — | — |  |
| `next-entry` | View ▸ Next Entry ⌥⌘↓ | — | — |  |
| `view-source` | View ▸ View Source / View Preview ⌥⌘U | ⌥⌘U (View menu) | reading bar; Mac toolbar | The same labels are on the Mac toolbar button and the reading bar button. |
| `zoom-in` | View ▸ Zoom In ⌘+ (also ⌘=) | ⌘+ (View menu) | — |  |
| `zoom-out` | View ▸ Zoom Out ⌘− | ⌘− (View menu) | — |  |
| `actual-size` | View ▸ Actual Size ⌘0 | ⌘0 (View menu) | — | On iPad the default is the Dynamic Type size. |
| `enter-full-screen` | View ▸ Enter Full Screen ⌃⌘F | — | — |  |
| `window-*` | Window ▸ Minimize ⌘M, Zoom, Bring All to Front, the window's name | — | — |  |
| `help-guide` | Help ▸ My Journal Help ⌘? | ⌘? | Settings ▸ About (screens/settings-about) |  |
| `help-support` | Help ▸ My Journal Support | — | Settings ▸ About |  |
| `help-privacy` | Help ▸ Privacy Policy | — | Settings ▸ About |  |
| `help-source` | Help ▸ Source Code on GitHub | — | Settings ▸ About |  |
| `help-rate` | Help ▸ Rate My Journal (after a separator) | — | Settings ▸ About | Opens the App Store review page. |

## Toolbars, context menus and swipes

Entry actions (the Entry Actions “…” menu in the editor, and an entry's row context menu) each first save the open writing; if that fails, nothing happens. Labels and symbols are specified with the entries list ([screens/entry-list](../../screens/entry-list.md)).

| id | Mac placement and shortcut | iPad shortcut | iPhone and iPad placement | Notes |
| --- | --- | --- | --- | --- |
| `choose-collection` | sidebar row; arrow keys in the focused sidebar | — | sidebar row (iPad), Journals screen row (iPhone) |  |
| `journal-actions` | toolbar menu over the list | — | list bar ⋯ in a journal; ⋯ on a row in edit mode | Mac: New Journal… first, then Rename… and Delete Journal…. iPhone and iPad: Rename… and Delete Journal…. |
| `rename-journal` | journal row context menu; Journal Actions | — | journal context menu; Journal Actions |  |
| `delete-journal` | context menu; Journal Actions | — | same |  |
| `reorder-journal` | drag a journal row in the sidebar | — | drag the handle in edit mode; touch, hold and drag; VoiceOver `library.journals.moveUp` / `library.journals.moveDown` |  |
| `journals-edit` | — (no edit mode on the Mac) | — | Journals screen and iPad sidebar bar |  |
| `new-journal-context` | sidebar context menu (rows and empty area) | — | empty list (no journals) |  |
| `entry-actions` | toolbar menu over the editor | — | editor bar ⋯ |  |
| `find-in-entry` | Edit ▸ Find ▸ Find… ⌘F | ⌘F | Entry Actions (first) | The find bar on the Mac, the find navigator on iPhone and iPad. |
| `pin-entry-row` | context menu; trackpad leading swipe | — | leading swipe (full swipe), context menu, Entry Actions |  |
| `review-changes` | notice above an entry or template with changes to review; Settings ▸ Sync ▸ Changes to Review | same | same |  |
| `change-date` | context menu; Entry Actions | — | same |  |
| `move-entry` | context menu; Entry Actions | — | same |  |
| `save-as-template` | context menu; Entry Actions | — | same |  |
| `image-descriptions` | context menu; Entry Actions | — | same |  |
| `entry-version-history` | context menu; Entry Actions | — | same |  |
| `restore` | context menu; Entry Actions; notice | — | leading swipe (full swipe, only when the entry returns to its own journal), context menu, Entry Actions, notice | The label is Restore, or Restore to “{name}” when the entry goes to the Default Journal; the cross-journal form is never on a swipe. |
| `restore-journal` | deleted journal's detail (button below the count) | — | same | Acts at once; no sheet. |
| `try-syncing-again` | recovery notice | — | same |  |
| `delete-permanently` | context menu; Entry Actions; Delete or ⌘⌫ in the focused list; deleted journal's detail | — | trailing swipe (`common.delete`, removes the row first), context menu, Entry Actions, detail |  |
| `delete-entry` | context menu; Entry Actions (destructive, last); Delete or ⌘⌫ in the focused list | — | trailing swipe (full swipe), context menu, Entry Actions (destructive, last) |  |
| `clear-search` | under No Results | — | under No Results |  |
| `empty-new-entry` | empty journal or All Entries | — | same |  |
| `finish-editing` | — | — | editor navigation bar, trailing, while writing | The Done button is a checkmark. |
| `sync-status` | toolbar (only when sync needs the person) | — | Entry Actions ▸ Sync Status |  |

## Keyboard in lists, sheets and choosers

| Context | Keys |
| --- | --- |
| Mac entries list (focused) | ↑/↓ move the selection and open the entry; Delete or ⌘⌫ delete (or ask to delete permanently in Recently Deleted). |
| Mac sidebar (focused) | ↑/↓ choose a collection. Escape cancels a journal drag. |
| Template chooser | Typing filters; ↑/↓ move the highlight; Return creates; Escape closes (not while an input method is composing). Works on iPad with a keyboard too. |
| Sheets (Mac) | Return = the default button (Move, Save); Escape = Cancel. |
| Lock screen (Mac) | Return = Unlock with {method}. |
| Create library | Return in Master Password moves to Verify; Return in Verify = Create. |

## Editor

Behaviour is specified in [screens/entry-editor](../../screens/entry-editor.md), [screens/format-sheet](../../screens/format-sheet.md) and the rule IDs of [flows/editing-rules](../../flows/editing-rules.md). The Format, View and Edit menu labels are `library.menu.*`. The rules each command follows are in the Rules column of [commands.md](../../commands.md#editor).

### Format

| id | Mac menu | Mac shortcut | iPad shortcut | iPhone, iPad on screen |
| --- | --- | --- | --- | --- |
| `show-formatting` | — (toolbar button Formatting; overflow menu item) | — | — | Bar ▸ Formatting (Aa) |
| `format-bold` | Format ▸ Bold | ⌘B | ⌘B (menu and *text*) | Formatting ▸ **B** |
| `format-italic` | Format ▸ Italic | ⌘I | ⌘I (menu and *text*) | Formatting ▸ *I* |
| `format-underline` | Format ▸ Underline | ⌘U | ⌘U (menu and *text*) | Formatting ▸ U̲ |
| `format-strikethrough` | Format ▸ Strikethrough | ⇧⌘X | ⇧⌘X (menu and *text*) | Formatting ▸ S̶ |
| `format-inline-code` | Format ▸ Inline Code | ⌥⌘C | ⌥⌘C (menu only) | Formatting ▸ `<>` |
| `format-paragraph` | Format ▸ Paragraph | ⌥⌘0 | ⌥⌘0 (menu and *text*) | Formatting ▸ Paragraph |
| `format-heading-1` … `format-heading-6` | Format ▸ Heading 1 … Heading 6 | ⌥⌘1 … ⌥⌘6 | ⌥⌘1 … ⌥⌘6 (menu and *text*) | Formatting ▸ Heading 1–3; ▸ More Headings ▸ Heading 4–6 |
| `format-bulleted-list` | Format ▸ Bulleted List | ⇧⌘7 | ⇧⌘7 (menu) | Formatting ▸ Bulleted List |
| `format-numbered-list` | Format ▸ Numbered List | ⇧⌘9 | ⇧⌘9 (menu) | Formatting ▸ Numbered List |
| `format-checklist` | Format ▸ Checklist | ⇧⌘L | ⇧⌘L (menu) | Formatting ▸ Checklist |
| `format-mark-checked` | Format ▸ Mark as Checked / Mark as Unchecked | ⇧⌘U | ⇧⌘U (menu); ⇧⌘Return (*text*) | Formatting ▸ Mark as Checked / Unchecked (only with checklist items selected); a checkbox tap (`toggle-checkbox`) |
| `format-block-quote` | Format ▸ Block Quote | ⌘' | ⌘' (menu) | Formatting ▸ Block Quote |
| `format-increase-indent` | Format ▸ Increase Indent | ⌘] ; Tab in a list item or code | ⌘] (menu); Tab (*text*) | Formatting ▸ Increase Indent (icon) |
| `format-decrease-indent` | Format ▸ Decrease Indent | ⌘[ ; Shift-Tab in a list item or code | ⌘[ (menu); Shift-Tab (*text*) | Formatting ▸ Decrease Indent (icon) |
| `insert-code-block` | Format ▸ Insert ▸ Code Block | — (or type ```` ``` ```` Return) | — | Formatting ▸ Insert ▸ Code Block |
| `insert-table` | Format ▸ Insert ▸ Table | — | — | Formatting ▸ Insert ▸ Table |
| `insert-horizontal-rule` | Format ▸ Insert ▸ Horizontal Rule | — (or type `---` Return) | — | Formatting ▸ Insert ▸ Horizontal Rule |
| `insert-link` | Format ▸ Insert ▸ Add Link…, which reads Edit Link… with the caret or selection in one link; right-click on a link: Edit Link… | ⌘K | ⌘K (menu and *text*) | Formatting ▸ Insert ▸ Add Link… / Edit Link… |
| `remove-link` | Format ▸ Insert ▸ Remove Link (dimmed unless the caret or selection touches a link); right-click on a link: Remove Link | — | — (menu) | Formatting ▸ Insert ▸ Remove Link |
| `insert-image` | Format ▸ Insert ▸ Image… (open panel) | — | — (menu: photo library) | Formatting ▸ Insert ▸ Image… |
| `exit-code-block` | — | Down Arrow at the end of a code block's last line | Down Arrow (*text*) | Formatting ▸ Exit Code Block (only in a code block) |

Format menu order (Mac, iPad): Bold, Italic, Underline, Strikethrough, Inline Code, —, Paragraph, Heading 1–6, —, Bulleted List, Numbered List, Checklist, Mark as Checked/Unchecked, Block Quote, —, Increase Indent, Decrease Indent, —, Insert ▸ (Code Block, Table, Horizontal Rule, —, Add Link… or Edit Link…, Remove Link, Image…), then Table ▸ (Mac and iPad; iPhone has no menu bar).

### Table

| id | Mac | iPad, iPhone |
| --- | --- | --- |
| `table-add-row` | Format ▸ Table ▸ Add Row Below; cell context menu ▸ Table ▸ | iPad: Format ▸ Table ▸ Add Row Below; cell edit menu ▸ Table ▸. iPhone: cell edit menu ▸ Table ▸ |
| `table-add-column` | Format ▸ Table ▸ Add Column After; cell menu | same |
| `table-align-left` / `table-align-center` / `table-align-right` | Format ▸ Table ▸ Alignment ▸ Left / Center / Right (the column's alignment checked); cell context menu ▸ Table ▸ Alignment ▸ | same, and cell edit menu ▸ Table ▸ Alignment ▸ |
| `table-delete-row` | Format ▸ Table ▸ Delete Row; cell menu | same (destructive in the edit menu) |
| `table-delete-column` | Format ▸ Table ▸ Delete Column; cell menu | same (destructive in the edit menu) |
| `table-delete-table` | Format ▸ Table ▸ Delete Table; cell menu | same (destructive in the edit menu) |
| `table-next-cell` / `table-previous-cell` | Tab / Shift-Tab in a cell | Tab / Shift-Tab (*text*) |
| `table-cell-below` | Return in a cell | Return |

### Editor-only controls

| id | Mac | iPad, iPhone |
| --- | --- | --- |
| `insert-image-choose-file` | Toolbar Insert Image (open panel) | Bar ▸ Insert Image ▸ `editor.insertImage.chooseFile` |
| `insert-image-photo-library` | — | Bar ▸ Insert Image ▸ Photo Library |
| `insert-image-take-photo` | — | Bar ▸ Insert Image ▸ Take Photo (only with a usable camera) |
| `toggle-checkbox` | Click a checkbox | Tap a checkbox |
| `image-copy`, `image-cut`, `image-paste`, `image-share`, `image-save-to-photos`, `image-save-as`, `image-delete` | Right-click on a picture | Long press on a picture |
| `close-formatting` | Escape, or Formatting again | Close button, Aa again, Escape (*text*) |

### Keys in the text

The keys, where they act and their results are in [commands.md](../../commands.md#keys-in-the-text). Where the Apple devices differ:

| Key | Where | Device |
| --- | --- | --- |
| Tab / Shift-Tab | To body from the title | iPhone and iPad only |
| ⇧⌘Return | Checklist item: Mark as Checked / Unchecked | iPhone and iPad, *text* (the text view's own shortcut) |

### Notes

- iPad menu-bar commands come from the same command definitions as the Mac's, except the Mac-only View items. Format ▸ Table ▸ is one of them (the same list, from `TableMenu`).
- No two menu-bar commands share a shortcut (`MenuShortcutTests.testMenuBarShortcutsAreUnique`); ⌘= also triggers Zoom In (`MenuShortcutTests.testZoomInAnswersCommandEqualsWithoutShift`).
- iPhone with a hardware keyboard: whether the iPad menu-bar shortcuts (⇧⌘7, ⇧⌘9, ⇧⌘L, ⌘', ⌘], ⌘[, ⌥⌘C, ⌥⌘U) also work isn't established by any test; only the text view's own shortcuts (*text*) are certain.

## Settings

The Settings tables place the commands of [commands.md](../../commands.md#settings). Commands that live on other surfaces are defined once in the sections above and only placed here: `open-settings`, `lock-my-journal` (App Lock section), `import-archive`, `export-archive`, `export-markdown` (Backup), `help-guide`, `review-changes` (Changes to Review). The Settings ▸ About links have their own ids because the Help menu items (`help-privacy`, `help-support`, `help-source`, `help-rate`) are Mac and iPad-keyboard commands with the same destinations.

### Settings structure

| id | Mac | iPhone and iPad | Notes |
| --- | --- | --- | --- |
| `settings-open-pane` | a tab in the Settings window | a row in Settings |  |
| `settings-done` | — | Settings sheet, confirming position |  |

### General

| id | Placement | Shortcut | Notes |
| --- | --- | --- | --- |
| `choose-default-journal` | Settings ▸ General | — |  |
| `toggle-format-as-you-type` | Settings ▸ General | — |  |

### Sync

| id | Placement | Shortcut | Notes |
| --- | --- | --- | --- |
| `connect-to-server` | Settings ▸ Sync, Devices, Agent Access (not connected); first-launch screen | — |  |
| `sync-now` | Settings ▸ Sync | — |  |
| `sync-reconnect` | Settings ▸ Sync (Reconnect…); Sync Status; Settings ▸ Privacy (Reconnect…); Settings ▸ Agent Access (no access) | — |  |
| `stop-syncing` | Settings ▸ Sync | — |  |
| `open-setup-guide` | Settings ▸ Sync footer; Set Up Server footer | — |  |
| `open-former-server-guide` | Settings ▸ Sync footer (Mac only) | — | Mac only (the footer of Settings ▸ Sync). |
| `open-kept-note` | Settings ▸ Sync ▸ Changed on Two Devices: the whole row, with a disclosure indicator (iPhone, iPad); a button (Mac) | — | same | One control per row; a row with nothing to open (a journal rename) is plain text. |
| `clear-kept-notes` | Settings ▸ Sync ▸ Changed on Two Devices: last row, Clear List | — | same | No confirmation. |

### Connect to a Server

| id | Shortcut | Notes |
| --- | --- | --- |
| `connect-check-server` | ↩ in the address field |  |
| `connect-scan-code` | — | iPhone and iPad with a supported camera scanner. |
| `scan-cancel` | — |  |
| `scan-open-settings` | — |  |
| `connect-set-up` | ↩ |  |
| `connect-sign-in` | ↩ |  |
| `connect-use-device` | — |  |
| `connect-copy-code` | — |  |
| `connect-confirm-check-code` | ⌘↩ (not ↩) |  |
| `connect-new-code` | — |  |
| `connect-use-recovery-code` | — |  |
| `connect-merge` | ⌘↩ (not ↩) |  |
| `connect-retry` | — |  |
| `connect-cancel` | ⎋ |  |
| `connect-done` | ↩ |  |
| `show-connection` | — | Mac only. Opens Settings at the Sync tab. |

### Devices

| id | Shortcut | Notes |
| --- | --- | --- |
| `add-device` | — |  |
| `revoke-device` | — |  |
| `devices-try-again` | — |  |
| `add-device-enter-code` | — |  |
| `add-device-look-up` | ↩ |  |
| `add-device-new-code` | — |  |
| `add-device-copy-address` | — |  |
| `add-device-approve` | ⌘↩ (not ↩) |  |
| `add-device-cancel` | ⎋ |  |
| `add-device-try-again` | — |  |
| `add-device-done` | — |  |

### Privacy

| id | Shortcut | Notes |
| --- | --- | --- |
| `turn-on-encryption` | — | Settings ▸ Privacy button; opens the Encrypt Your Journals form as a sheet. |
| `encrypt-journals` | ↩ in Verify (the Mac's default button is Encrypt) | The form's primary button; Try Again after an error. |
| `encrypt-journals-not-now` | — | Plain button under the primary button. |
| `encrypt-journals-stop-syncing` | — | Plain button under the primary button, and on the unfinished notice. |
| `encryption-finish` | — | Try Again on the unfinished notice. |
| `encryption-cancel` | ⎋ | Cancel on the working notice (accessible name “Cancel encryption”) and Cancel of the form as a sheet. |
| `encryption-done` | ↩, ⎋ | Done sheet. |
| `change-password` | — | Also the pointer under the archive footer in Settings ▸ Backup and the Export Archive sheet. |
| `change-password-submit` | ↩ in Confirm |  |
| `change-password-retry` | — |  |
| `change-password-cancel` | ⎋ |  |
| `forgot-password` | — | Borderless button in the Current Password section footer. |
| `toggle-app-lock` | — |  |
| `set-inactivity-lock` | — | Mac only. |
| `unlock-with-device` | ↩ (Mac) | Return on the Mac. |
| `use-credential` | — |  |
| `unlock-with-credential` | ↩ in the field |  |
| `use-device-unlock` | — |  |
| `copy-recovery-key` | — |  |
| `save-recovery-key` | — |  |
| `confirm-recovery-key` | — |  |

### Backup

| id | Shortcut | Notes |
| --- | --- | --- |
| `archive-open` | ↩ in the field |  |
| `archive-import` | — |  |
| `archive-import-cancel` | ⎋ |  |
| `archive-import-done` | — |  |
| `export-sheet-done` | ⎋ | Closes the File-menu export sheet. |

### Erase

| id | Placement | Shortcut | Notes |
| --- | --- | --- | --- |
| `erase-device` | iPhone/iPad: last section of Settings; Mac: end of General | — |  |
| `erase-confirm` | warning alert (destructive) | — |  |

### Library problem

| id | Placement | Shortcut | Notes |
| --- | --- | --- | --- |
| `retry-opening` | Button on the library problem screen (prominent, large; not for a newer version) | Return (default action) | Replaced by a progress indicator while it runs. |
| `erase-unopened` | Plain red button on the library problem screen (after one failed Try Again) and under Import Archive… on the missing-key lock screen | — | On the problem screen, not offered on iPhone and iPad while protected data is unavailable; the lock screen has no such gate. |
| `open-library-guide` | Plain tinted button, last on the library problem screen | Return on the Mac, for a newer version only | The only button for a newer version. |

### Agent Access

| id | Shortcut | Notes |
| --- | --- | --- |
| `copy-mcp-address` | — |  |
| `share-mcp-address` | — | iPhone and iPad only. |
| `open-agent-guide` | — |  |
| `agents-try-again` | — |  |
| `review-agent-request` | — |  |
| `allow-agent` | ↩ in the number field |  |
| `decline-agent` | ⎋ (Mac) | Escape on the Mac. |
| `open-agent` | — |  |
| `rename-agent` | ↩ saves |  |
| `change-agent-journals` | — |  |
| `change-agent-expiry` | — |  |
| `revoke-agent` | — |  |
| `agent-detail-done` | ↩ (Mac) | Closes the Mac detail sheet. |

### About and Help

| id | Placement | Shortcut | Notes |
| --- | --- | --- | --- |
| `about-privacy-policy` | Settings ▸ About (iPhone/iPad); Help menu as `help-privacy` | — |  |
| `about-support` | Settings ▸ About; Help menu as `help-support` | — |  |
| `about-source-code` | Settings ▸ About; Help menu as `help-source` | — |  |
| `about-rate` | Settings ▸ About; Help menu as `help-rate` | — |  |
