# Commands on Windows

Where every command in [commands.md](../../commands.md) appears in the Windows app, its shortcut, its scope and what differs. One row for each command id, in the order of `commands.md`; the checker verifies that every id has exactly one row here. Behaviour is in the screen and flow files; the controls and conventions are in [platform.md](platform.md). Menu bar and command bar structure: [4](platform.md#4-menus-and-toolbars); shortcut rules: [7](platform.md#7-keyboard-shortcuts).

**Placement** says where the command appears: a **menu** (File, Edit, Format, View, Help), a **command bar** (the navigation pane header, the entry list header, the editor header), a **context menu** (entry row, journal row, navigation pane, picture, table cell, text), a **notice** (the action of an `InfoBar`), a **page** or **card** in Settings, a **dialog** button, or **Not offered**, with the reason in the notes. Every command in a command bar or context menu is also in a menu or on a page, and every swipe action is also in a context menu ([6](platform.md#6-touch-and-swipe-actions)).

**Shortcuts** are written as Windows shows them: Ctrl, Alt, Shift, Enter, Esc. The framework shows the shortcut beside each menu item and in each tooltip. “—” means none; "same as Find" and similar phrases are plain text, not shortcuts.

**Scope** says where the shortcut works, so the checker can find collisions:

| Scope | Meaning |
| --- | --- |
| app | Anywhere in the library window. No two app or editor shortcuts may be the same |
| editor | Only while the editor (or a table cell) has focus; may not repeat an app or editor shortcut |
| list | Only in a focused list, the navigation pane or the search box; may repeat across list rows, never an app or editor shortcut |
| dialog | Inside a dialog, a flyout, a task page (Connect, Import archive) or the lock page |
| system | Supplied by Windows; listed for completeness |
| — | No shortcut |

Labels are the copy keys of [copy/en.json](../../copy/en.json); Windows shows them in sentence case with the ellipsis rule in [12](platform.md#12-copy-casing-ellipses-and-vocabulary), so the Apple wording is not repeated here.

Sheets follow the dialog rules in [8](platform.md#8-dialogs): Enter is the default button where Apple's Return is, Esc is Cancel, and where Apple uses ⌘Return the dialog has no default button and Ctrl+Enter chooses the action. The multi-step flows are task pages ([9](platform.md#9-sheets-popovers-and-notices)): they have the same buttons and Ctrl+Enter, but Esc is not Back and Cancel is a button there.

## Menu bar and menus

On Windows the menus are File, Edit, Format, View and Help; the application and Window menus do not exist. The Windows menu structure is in [platform.md](platform.md#4-menus-and-toolbars).

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `about` | system | Help ▸ About My Journal | — | — | Opens Settings ▸ About ([10](platform.md#10-settings)). |
| `open-settings` | `library.toolbar.settings` | The navigation pane's built-in Settings item (gear, last item); File ▸ Settings | `Ctrl+,` | app | No ellipsis: it opens a page. Not available while locked. |
| `lock-my-journal` | `common.lockMyJournal` | File ▸ Lock My Journal; Settings ▸ Privacy ▸ App lock (button) | `Ctrl+L` | app | Enabled while App Lock is on. The editor's own Ctrl+L (align left) is turned off ([7](platform.md#7-keyboard-shortcuts), rule 6). Win+L is the system lock and is unaffected. |
| `quit`, `hide`, `services` | system | `quit`: File ▸ Exit. `hide` and `services`: not offered | `Alt+F4` | system | Alt+F4 closes the window, which ends the app, after the open entry is saved; if it can't be, the Keep Open dialog shows and the window stays ([3](platform.md#3-windows-and-instances)). Windows has no Hide or Services. |
| `new-entry` | `library.menu.file.newEntry` | File ▸ New entry; the New entry button in the entry list header (primary) | `Ctrl+N` | app | Enabled as on Apple. The button works without a journal in use; the menu item needs one. `Ctrl+Shift+N` is not used. |
| `use-a-template` | `library.menu.file.useTemplate`; `library.templateChooser.useTemplate`; `editor.body.placeholder.templateLink` | File ▸ Use a template…; the link in an empty entry's placeholder, opening a flyout | — | app | Template chooser flyout ([9](platform.md#9-sheets-popovers-and-notices)) anchored to the editor; the menu item is dimmed, not hidden, unless the link is shown. |
| `new-journal` | `common.newJournalEllipsis` | File ▸ New journal…; New journal button above the navigation pane items | `Ctrl+Shift+J` | app | A dialog with a name field. Leaves Editor Only first. |
| `pin-entry` | `library.entryActions.pin` / `library.entryActions.unpin` | File ▸ Pin entry / Unpin entry (own group after New journal…) | — | — | No shortcut: Ctrl+P is Print on Windows. |
| `import-archive` | `common.importArchive` | File ▸ Import archive…; first-launch page; Settings ▸ Backup (button) | — | — | Open picker for a `.journalarchive` file (the archive is one file, D29), then the Import archive task page. Dropping an archive file on the window or double-clicking it in Explorer starts the same flow ([19](platform.md#19-single-instance-and-activation)). |
| `export-archive` | `common.exportArchive` | File ▸ Export archive…; Settings ▸ Backup (button) | — | — | Save picker suggesting `settings.backup.archiveFilename` (the archive is one file, D29). No warning about synced folders such as OneDrive: where the file is saved is the person's decision and risk (owner decision, 2026-10-07). |
| `export-markdown` | `library.menu.file.exportMarkdown` (menu); `settings.backup.exportMarkdown` (Settings) | File ▸ Export journals as Markdown…; Settings ▸ Backup (button) | — | — | Folder picker; Windows-safe file names ([16](platform.md#16-files-and-pickers)); no warning about synced folders such as OneDrive (owner decision, 2026-10-07). The two labels differ, as on Apple (see open-questions B). |
| `delete-all-recently-deleted` | `library.menu.file.deleteAll` (menu); `library.recentlyDeleted.deleteAll` (button) | File ▸ Delete all in Recently deleted (after a separator); button in the Recently deleted list header | `Ctrl+Shift+Delete` | app | No ellipsis ([12.2](platform.md#122-ellipsis)); the confirmation dialog follows [8](platform.md#8-dialogs). |
| `close-window` | system | The title bar's Close button; no menu item | `Alt+F4` | system | Same as `quit`: one window. |
| `undo`, `redo` | system, with the action names `library.entryActions.deleteEntry`, `library.entryActions.deleteTemplate`, `library.entryActions.pinUndo`, `library.entryActions.unpin`, `library.journals.undoMove` and `editor.undo.*` | Edit ▸ Undo, Redo (plain, as in Word, Notepad and OneNote, while text has focus); Undo {name}, Redo {name} for the list-level actions (delete entry, unpin, move journal), where nothing in the text says what is undone | `Ctrl+Z`, `Ctrl+Y`, `Ctrl+Shift+Z` | app | Redo is Ctrl+Y on Windows; Ctrl+Shift+Z is accepted and not shown. With text focus the editor's own undo steps apply (rules U-1 to U-8 in [flows/editing-rules](../../flows/editing-rules.md)); the step names `editor.undo.*` are not shown in the menu on Windows and stay as Narrator announcements (D31). |
| `edit-text` | system | Edit ▸ Cut, Copy, Paste, Select all; the text context menu | `Ctrl+X`, `Ctrl+C`, `Ctrl+V`, `Ctrl+A` | editor | No Delete item in the Edit menu: the Delete key does it. Rules PA-1 to PA-15 apply. |
| `paste-and-match-style` | system | Edit ▸ Paste as plain text | `Ctrl+Shift+V` | editor | PA-10 in [flows/editing-rules](../../flows/editing-rules.md). |
| `find` | system | Edit ▸ Find, Find and replace, Find next, Find previous; the find bar above the entry | `Ctrl+F`, `Ctrl+H`, `F3`, `Shift+F3` | editor | The app draws its own find bar; it never covers the first line. Use Selection for Find and Jump to Selection are not offered. Enter and Shift+Enter in the bar step through matches. |
| `search-entries` | `library.menu.edit.searchEntries` | Edit ▸ Search entries; the search box in the entry list header | `Ctrl+E`, `Ctrl+Shift+F` | app | Focuses the list's search box; leaves Editor Only first. |
| `text-editing-system` | system | Windows features: voice typing (Win+H), emoji panel (Win+.), spelling suggestions in the text context menu; no menu items | — | — | Prose follows the system's spelling settings; code and source stay literal (SP-1, SP-2; [25](platform.md#25-text-input-and-spelling)). |
| `format-*` | `library.menu.format.*` | Format menu | — | — | Each Format command has its own row under [Format](#format). The whole menu is disabled while the open item can't be edited. |
| `toggle-sidebar` | system | View ▸ Show navigation pane / Hide navigation pane; the pane button in the title bar | `Ctrl+Shift+B` | app | No Windows standard exists; provisional ([7](platform.md#7-keyboard-shortcuts)). |
| `toggle-toolbar` | system | Not offered | — | — | Windows command bars are not hidden by the person. |
| `show-editor-only` | `library.menu.view.showEditorOnly` / `library.menu.view.showSidebarAndList`; `library.toolbar.editorOnly` | View ▸ Show editor only / Show all panes; **no button in the editor header** | `Ctrl+Shift+D` | app | Not offered at small width. Full screen (F11) and Snap layouts cover the same need on Windows, so the header keeps one icon fewer. Windows labels are proposed in [12.3](platform.md#123-vocabulary). |
| `previous-entry` | `library.menu.view.previousEntry` | View ▸ Previous entry | `Alt+Up` | app | Works while the list is hidden. |
| `next-entry` | `library.menu.view.nextEntry` | View ▸ Next entry | `Alt+Down` | app |  |
| `view-source` | `library.menu.view.viewSource` / `library.menu.view.viewPreview` | View ▸ View source / View preview; no button in the editor header (as in Notepad, the switch is in the View menu) | `Ctrl+Shift+U` | app | Disabled menu item description `common.previewUnavailable`. |
| `zoom-in` | `library.menu.view.zoomIn` | View ▸ Zoom in | `Ctrl+Plus`, `Ctrl+=`, `Ctrl+Numpad +` | app | 12 to 30; Ctrl+mouse wheel and touchpad pinch zoom too. A relative factor on top of the system text size, which the control applies once ([22](platform.md#22-typography)). Main-row and numpad keys are both bound because virtual keys do not follow the printed key on every layout ([7](platform.md#7-keyboard-shortcuts), rule 8). |
| `zoom-out` | `library.menu.view.zoomOut` | View ▸ Zoom out | `Ctrl+Minus`, `Ctrl+Numpad -` | app |  |
| `actual-size` | `library.menu.view.actualSize` | View ▸ Actual size | `Ctrl+0`, `Ctrl+Numpad 0` | app | Back to 16. |
| `enter-full-screen` | system | View ▸ Full screen | `F11` | app | The title bar and menu bar hide and return at the top edge. |
| `window-*` | system | Not offered | — | — | Caption buttons, the taskbar and snap layouts (Win+Z) do this. |
| `help-guide` | `library.menu.help.guide` | Help ▸ My Journal Help; Settings ▸ About | `F1` | app | Opens the user guide on the web. |
| `help-support` | `library.menu.help.support` | Help ▸ My Journal Support; Settings ▸ About | — | — | Opens SUPPORT.md on the web. |
| `help-privacy` | `common.privacyPolicy` | Help ▸ Privacy Policy; Settings ▸ About | — | — | Opens PRIVACY.md on the web. |
| `help-source` | `library.menu.help.source` | Help ▸ Source Code on GitHub; Settings ▸ About | — | — | Opens the repository. |
| `help-rate` | `common.rateMyJournal` | Help ▸ Rate My Journal (after a separator); Settings ▸ About | — | — | Store builds only; opens the Store review page ([28](platform.md#28-rating)). |

## Command bars, context menus and swipes

Entry actions each first save the open writing; if that fails, nothing happens. The Entry actions menu and the entry row's context menu are one list ([5](platform.md#5-context-menus)).

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `choose-collection` | `library.journals.*` | Navigation pane item; ↑ and ↓ in the focused pane | — | — | Saves the open entry first. |
| `journal-actions` | `library.toolbar.journalActions` | Entry list header ▸ More (…) menu | — | — | New journal… first, then Rename… and Delete journal…. |
| `rename-journal` | `library.journalActions.rename` | Journal context menu; Journal actions menu | `F2` | list | F2 renames the focused journal (Microsoft's list). A dialog with a name field. |
| `delete-journal` | `library.journalActions.deleteJournal` | Journal context menu; Journal actions menu | — | — | No Delete-key shortcut for journals (there is no undo, open-questions D1). Confirmation dialog, no ellipsis. |
| `reorder-journal` | `library.journals.undoMove` (undo name); `library.journals.moveUp`, `library.journals.moveDown` | Drag a journal in the navigation pane; Move up and Move down in the journal context menu | `Alt+Shift+Up`, `Alt+Shift+Down` | list | Move up and Move down are the keyboard, Narrator and switch route; the two keys are provisional ([2.1](platform.md#21-controls)). Announced and undoable. |
| `journals-edit` | `library.toolbar.edit` / `common.done` | Not offered | — | — | No edit mode, as on the Mac. |
| `new-journal-context` | `common.newJournalEllipsis` | Navigation pane context menu (rows and empty area); button in the empty state | — | — | As `new-journal`. |
| `entry-actions` | `library.toolbar.entryActions` | Editor header ▸ More (…) menu; the same items in the entry row's context menu | — | — | One command list, two presentations ([5](platform.md#5-context-menus)). |
| `find-in-entry` | `library.entryActions.findInEntry` | Edit ▸ Find; the find bar | same as Find | — | Not repeated in the Entry actions menu: Windows has the Edit menu. |
| `pin-entry-row` | `library.entryList.swipe.pin` / `library.entryList.swipe.unpin`; `library.entryActions.pin` / `library.entryActions.unpin` | Entry row context menu; swipe (touch and pen); Entry actions | — | — | Leading swipe with full swipe. Does not change the selection. |
| `show-other-version` | `messages.conflict.kept.showOther` | The Informational `InfoBar` above the writing of an entry or template that was kept as two versions: its `ActionButton` | — | — | Opens the other version in the library; marks the notice seen. |
| `dismiss-kept-notice` | `common.dismiss` | The same `InfoBar`'s close button (`IsClosable`), named `common.dismiss` for Narrator | — | — | Marks the notice seen; the notice is not shown again. |
| `change-date` | `library.entryActions.changeDate` | Entry row context menu; Entry actions | — | — | Dialog with a `CalendarDatePicker`, date only: the entry keeps its time of day, as the spec says ([31](platform.md#31-dates-time-zones-and-formats)). |
| `move-entry` | `library.entryActions.moveEntry` | Entry row context menu; Entry actions | — | — | Dialog. |
| `save-as-template` | `library.entryActions.saveAsTemplate` | Entry row context menu; Entry actions | — | — | Dialog with a name field. |
| `image-descriptions` | `library.entryActions.imageDescriptions` | Entry row context menu; Entry actions | — | — | Shown only when the item has pictures; a page. |
| `entry-version-history` | `common.versionHistoryEllipsis` | Entry row context menu; Entry actions | — | — | A page. |
| `restore` | `common.restore`; `library.recentlyDeleted.restoreTo` | Entry row context menu; Entry actions; the recovery notice; leading swipe (only `common.restore`, when the entry returns to its own journal) | — | — | Restores at once. The cross-journal label is never on a swipe. |
| `restore-journal` | `library.recentlyDeleted.restoreJournal` | Button on a deleted journal's page, below the count | — | — | Acts at once; no dialog. |
| `try-syncing-again` | `common.trySyncingAgain` | The recovery notice's action; the Restore dialog | — | — |  |
| `delete-permanently` | `library.entryActions.deletePermanently` | Entry row context menu; Entry actions; a deleted journal's page | `Delete`, `Shift+Delete` | list | In Recently deleted both keys ask. No ellipsis. Elsewhere Shift+Delete is not bound. |
| `delete-entry` | `library.entryActions.deleteEntry` / `library.entryActions.deleteTemplate`; `common.delete` (swipe) | Entry row context menu; Entry actions (destructive, last); trailing swipe | `Delete` | list | Moves to Recently deleted at once; Undo brings it back. |
| `clear-search` | `library.entryList.empty.clearSearch` | Button under No results; Esc in the search box | `Esc` | list | Esc clears, then leaves the box. |
| `empty-new-entry` | `library.menu.file.newEntry` | Button in the empty list | — | — | As `new-entry`. |
| `finish-editing` | `common.done` | Not offered | — | — | No Done button: editing is always live, as on the Mac. |
| `sync-status` | `messages.syncStatus.title` | Button with an `InfoBadge` (only when sync needs the person) in the title bar's trailing area at every width (D47); Settings ▸ Sync | — | — | One place at every width, so it is reachable from every page and from Settings. |

## Editor

Commands that act on the open entry or template. Behaviour is in [screens/entry-editor](../../screens/entry-editor.md), [screens/format-sheet](../../screens/format-sheet.md) and the rule ids of [flows/editing-rules](../../flows/editing-rules.md). The editor's own built-in accelerators for alignment, line spacing and font size are turned off ([7](platform.md#7-keyboard-shortcuts), rule 6).

### Format

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `show-formatting` | `library.toolbar.formatting` | Toggle button in the editor header; View ▸ Formatting (a check mark) | — | — | Shows or hides the formatting bar under the editor header; hidden by default, remembered on this device ([format-sheet](screens/format-sheet.md), D20). |
| `format-bold` | `library.menu.format.bold` | Format ▸ Bold; the formatting bar; the selection mini-toolbar | `Ctrl+B` | editor |  |
| `format-italic` | `library.menu.format.italic` | Format ▸ Italic; the formatting bar; the selection mini-toolbar | `Ctrl+I` | editor |  |
| `format-underline` | `library.menu.format.underline` | Format ▸ Underline | `Ctrl+U` | editor |  |
| `format-strikethrough` | `library.menu.format.strikethrough` | Format ▸ Strikethrough | `Ctrl+Shift+X` | editor |  |
| `format-inline-code` | `library.menu.format.inlineCode` | Format ▸ Inline code | `Ctrl+Shift+C` | editor |  |
| `format-paragraph` | `library.menu.format.paragraph` | Format ▸ Paragraph; the style drop-down of the formatting bar | `Ctrl+Shift+0` | editor | Not Ctrl+Alt+0: Windows reports AltGr as Ctrl+Alt and AltGr+digit types characters on many layouts ([7](platform.md#7-keyboard-shortcuts), rule 3; D27). |
| `format-heading-1` … `format-heading-6` | `library.menu.format.heading` (1 to 6) | Format ▸ Heading 1 to Heading 6; the style drop-down of the formatting bar | `Ctrl+Shift+1`, `Ctrl+Shift+2`, `Ctrl+Shift+3`, `Ctrl+Shift+4`, `Ctrl+Shift+5`, `Ctrl+Shift+6` | editor | Word's Ctrl+Alt+1 to 3 are the AltGr chords of the Belgian, French, German and other layouts, so they are not used. |
| `format-bulleted-list` | `library.menu.format.bulletedList` | Format ▸ Bulleted list | `Ctrl+Shift+8` | editor |  |
| `format-numbered-list` | `library.menu.format.numberedList` | Format ▸ Numbered list | `Ctrl+Shift+7` | editor |  |
| `format-checklist` | `library.menu.format.checklist` | Format ▸ Checklist | `Ctrl+Shift+9` | editor |  |
| `format-mark-checked` | `library.menu.format.markChecked` / `library.menu.format.markUnchecked` | Format ▸ Mark as checked / Mark as unchecked | `Ctrl+Shift+Enter` | editor | The same chord as the iPad's text shortcut. |
| `format-block-quote` | `library.menu.format.blockQuote` | Format ▸ Block quote | `Ctrl+Shift+Q` | editor |  |
| `format-increase-indent` | `library.menu.format.increaseIndent` | Format ▸ Increase indent | `Ctrl+M` | editor | Tab in a list item or in code also indents. |
| `format-decrease-indent` | `library.menu.format.decreaseIndent` | Format ▸ Decrease indent | `Ctrl+Shift+M` | editor | Shift+Tab in a list item or in code also outdents. |
| `insert-code-block` | `library.menu.format.insert.codeBlock` | Format ▸ Insert ▸ Code block | — | — | Or type three backticks and Enter (K-2). |
| `insert-table` | `library.menu.format.insert.table` | Format ▸ Insert ▸ Table | — | — |  |
| `insert-horizontal-rule` | `library.menu.format.insert.horizontalRule` | Format ▸ Insert ▸ Horizontal rule | — | — | Or type three hyphens and Enter (K-2). |
| `insert-link` | `library.menu.format.insert.link` / `library.menu.format.insert.editLink` | Format ▸ Insert ▸ Add Link… (Edit Link… with the caret in a link) | `Ctrl+K` | editor | Dialog ([screens/link-editor](../../screens/link-editor.md)). The edit form and the casing of the new labels are not mapped yet (the spec added them after the Apple build 18). |
| `remove-link` | `library.menu.format.insert.removeLink` | Format ▸ Insert ▸ Remove link; the text context menu on a link | — | — | Proposed, not yet reviewed: the Apple apps have it in the Format menu and the context menu. |
| `insert-image` | `library.menu.format.insert.image` | Format ▸ Insert ▸ Image… | — | — | Image file picker starting in Pictures. |
| `exit-code-block` | `editor.format.exitCodeBlock` | The formatting bar's overflow menu (enabled only in a code block) | `Down` | editor | Down Arrow at the end of a code block's last line. |

### Table

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `table-add-row` | `library.menu.format.table.addRow` | Format ▸ Table ▸ Add row below; table cell context menu ▸ Table | — | — |  |
| `table-add-column` | `library.menu.format.table.addColumn` | Format ▸ Table ▸ Add column after; cell context menu ▸ Table | — | — |  |
| `table-align-left` / `table-align-center` / `table-align-right` | `editor.table.alignment` ▸ `editor.table.alignment.left`, `editor.table.alignment.center`, `editor.table.alignment.right` | Cell context menu ▸ Table ▸ Alignment ▸ Left, Center, Right | — | — | A sub-menu keeps the menu short, as on iPhone and iPad (see open-questions D7). |
| `table-delete-row` | `library.menu.format.table.deleteRow` | Format ▸ Table ▸ Delete row; cell context menu | — | — |  |
| `table-delete-column` | `library.menu.format.table.deleteColumn` | Format ▸ Table ▸ Delete column; cell context menu | — | — |  |
| `table-delete-table` | `library.menu.format.table.deleteTable` | Format ▸ Table ▸ Delete table; cell context menu | — | — |  |
| `table-next-cell` / `table-previous-cell` | — | Tab and Shift+Tab in a cell | `Tab`, `Shift+Tab` | editor | TB-3. |
| `table-cell-below` | — | Enter in a cell | `Enter` | editor | N-15, TB-3. |

### Editor-only controls

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `insert-image-choose-file` | `library.toolbar.insertImage` | Insert image button in the editor header | — | — | Same as Format ▸ Insert ▸ Image…. Paste and drag and drop are the other routes ([26](platform.md#26-camera-photos-and-images)). |
| `insert-image-photo-library` | `editor.insertImage.photoLibrary` | Not offered | — | — | Windows has no photo library API. |
| `insert-image-take-photo` | `editor.insertImage.takePhoto` | Not offered | — | — | Not in version 1 (open-questions D24). |
| `toggle-checkbox` | item text; `editor.list.checked` / `editor.list.unchecked` | Click or touch a checkbox; the keyboard route is Mark as checked | — | — | C-3. The box is exposed to Narrator as a toggle. |
| `image-copy`, `image-cut`, `image-paste`, `image-share`, `image-save-to-photos`, `image-save-as`, `image-delete` | see [flows/image-actions](../../flows/image-actions.md) | Context menu on a picture: Cut, Copy, Paste, Share, Save image as…, Image descriptions…, Delete. `image-save-to-photos` is not offered | — | — | Share uses the Windows Share UI ([27](platform.md#27-sharing)). The text shortcuts of `edit-text` work on a selected picture; Delete and Backspace with a picture selected are the editor's ordinary deletion, which removes what IM-5 says (`image-delete` has no chord of its own). |
| `close-formatting` | `editor.format.close` | Not offered: a bar has nothing to close. The Formatting button or View ▸ Formatting hides it | — | — | The text control's selection mini-toolbar closes by itself when the selection changes or Esc is pressed in it. |

## Settings

Settings is a page in the main window ([10](platform.md#10-settings)); sheets opened from it are dialogs over the page.

### Settings structure

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `settings-open-pane` | `settings.pane.*` | A card on the Settings home page opens the pane's page | — | — | General, Sync, Devices, Privacy, Backup, Agent access, in that order. |
| `settings-done` | `common.done` | Not offered | — | — | Settings is a page: Back (Alt+Left), the breadcrumb or the back button leave it. |

### Writing and General

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `choose-default-journal` | `settings.general.defaultJournal` | `ComboBox` in a card | — | — |  |
| `toggle-format-as-you-type` | `settings.general.formatAsYouType` | `ToggleSwitch` in a card | — | — | The footer becomes the card's description. |

### Sync

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `connect-to-server` | `common.connectToServer` | Accent button in the Sync, Devices and Agent access pages when not connected; first-launch page | — | — | Opens the Connect task page. |
| `sync-now` | `messages.sync.action.syncNow` / `common.tryAgain` / `messages.sync.action.checkAgain` | The `ActionButton` of the Sync page's bar when a bar shows, otherwise a button in the server card (never both, D49); the Sync status flyout | — | — | "Syncing…" with a small indeterminate `ProgressBar` (or the text alone) for at least half a second: the page stays usable, so it is not a ring ([11](platform.md#11-progress-and-announcements)). |
| `sync-reconnect` | `common.reconnect` | The state's action in an `InfoBar` or card on the Sync and Agent access pages | — | — |  |
| `stop-syncing` | `settings.sync.stopSyncing` | A card with a Stop syncing button in its own group on the Sync page | — | — | No ellipsis; confirmation dialog with no default button. |
| `open-setup-guide` | `settings.sync.footer.howToSetUp` | Hyperlink in the card description | — | — |  |
| `open-former-server-guide` | `settings.sync.footer.learnMore` | Not offered | — | — | Mac-only state. |
| `open-kept-note` | the row's own sentence; `messages.conflict.kept.rowHint` | A `SettingsCard` row in the Changed on two devices group, clickable as a whole, with a chevron | — | — | One control per row; a row with nothing to open (a journal rename) is plain text. |
| `clear-kept-notes` | `messages.conflict.kept.clear` | Last item of that group, a text button | — | — | No confirmation. |

### Connect to a Server

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `connect-check-server` | `common.continue`; a nearby server row | Task page: primary button; a row in the nearby list | `Enter` | dialog | Enter in the address field. |
| `connect-scan-code` | `settings.connect.scanCode` | Not offered | — | — | Version 1 has no scanner ([29](platform.md#29-qr-codes-and-add-device)). |
| `scan-cancel` | `common.cancel` | Not offered | — | — | No scanner. |
| `scan-open-settings` | `common.openSettings` | Not offered | — | — | No scanner; if one is added, `ms-settings:privacy-webcam`. |
| `connect-set-up` | `settings.connect.setUp.setUp` / `common.continue` / `common.tryAgain` | Task page: primary button | `Enter` | dialog |  |
| `connect-sign-in` | `settings.connect.signIn.signIn` / `common.connect` / `common.tryAgain` | Task page: primary button | `Enter` | dialog |  |
| `connect-use-device` | `settings.connect.signIn.useDevice` | Task page: link button | — | — | Steps to Add This Device on the same page. |
| `connect-copy-code` | `settings.connect.addThisDevice.copyCode` | Task page: Copy button next to the digits | — | — | Copied with the clipboard options in [15](platform.md#15-clipboard). |
| `connect-confirm-check-code` | `common.connect` | Task page: primary button, no default button | `Ctrl+Enter` | dialog | Enter alone does not choose it ([8](platform.md#8-dialogs)). |
| `connect-new-code` | `settings.connect.addThisDevice.getNewCode` | Task page: button | — | — |  |
| `connect-use-recovery-code` | `settings.connect.addThisDevice.useRecoveryCode` | Task page: link button | — | — |  |
| `connect-merge` | `common.merge` | Task page: primary button, no default button | `Ctrl+Enter` | dialog | Enter alone does not choose it. |
| `connect-retry` | `common.tryAgain` / `settings.connect.scanAgain` | Task page: button | — | — | `settings.connect.scanAgain` is not offered (no scanner). |
| `connect-cancel` | `common.cancel` | Task page: Cancel button | — | — | Stops, withdraws requests, gives up unused access, discards a staged copy and returns to where the flow started. Esc is not bound (Esc is not Back). Disabled while the staged copy is being installed; closing the window then waits for that atomic step and discards the copy ([3](platform.md#3-windows-and-instances)). |
| `connect-done` | `common.done` | Task page: Done button, default | `Enter` | dialog | A finished step has one button, labelled Done, which is the default; it returns to where the flow started. |
| `show-connection` | `messages.writingPaused.showConnection` | Not offered | — | — | The task page is modal over the only window. |

### Devices

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `add-device` | `settings.devices.add`; `settings.connect.ready.addDevice` | Button in the Devices page | — | — | Opens the dialog. |
| `revoke-device` | `settings.devices.revoke` | Button in the device's row; confirmation dialog | — | — | Destructive dialog rules ([8](platform.md#8-dialogs)). |
| `devices-try-again` | `common.tryAgain` | Button in the error `InfoBar` | — | — |  |
| `add-device-enter-code` | `settings.addDevice.enterCodeInstead` | Dialog: link button under the QR code | — | — |  |
| `add-device-look-up` | `common.continue` | Dialog: primary button | `Enter` | dialog |  |
| `add-device-new-code` | `settings.addDevice.showNewCode` | Dialog: button | — | — |  |
| `add-device-copy-address` | `settings.addDevice.copyAddress` | Dialog: Copy button | — | — | A plain copy. |
| `add-device-approve` | `settings.addDevice.approve` / `settings.addDevice.add` | Dialog: primary button, no default button | `Ctrl+Enter` | dialog | Asks for Windows Hello first ([13](platform.md#13-device-authentication-and-app-lock)); continues without it when Hello isn't set up. |
| `add-device-cancel` | `common.cancel` / `settings.addDevice.dontAdd` | Dialog: close button | `Esc` | dialog |  |
| `add-device-try-again` | `common.tryAgain` | Dialog: button | — | — |  |
| `add-device-done` | `common.done` | Dialog: close button, default | `Enter`, `Esc` | dialog |  |

### Privacy

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `turn-on-encryption` | `settings.privacy.encryption.turnOn` | Not offered | — | — | Windows has no unencrypted libraries, so Settings ▸ Privacy never shows Encryption Is Off or this button ([screens/encrypt-journals](screens/encrypt-journals.md)). |
| `encrypt-journals` | `library.encrypt.action` / `common.tryAgain` | Not offered | — | — | Windows never shows the Encrypt Your Journals form: it has no unencrypted libraries and never creates one ([flows/encrypt-journals](flows/encrypt-journals.md)). |
| `encrypt-journals-not-now` | `library.encrypt.notNow` | Not offered | — | — | Same reason: there is no form to leave. |
| `encrypt-journals-stop-syncing` | `settings.sync.stopSyncing` | Not offered | — | — | Same reason: no encrypting without a master password on this PC. A server whose recovery format is 3 or 4 is refused instead (`messages.connection.encryptionOff`, [screens/connect-to-server](screens/connect-to-server.md)). |
| `encryption-finish` | `common.tryAgain` | Not offered | — | — | No encryption run exists on Windows. |
| `encryption-cancel` | `common.cancel` | Not offered | — | — | No encryption run exists on Windows. |
| `encryption-done` | `common.done` | Not offered | — | — | No Done step exists on Windows. |
| `change-password` | `settings.privacy.changePassword` (Settings ▸ Privacy); `settings.backup.archive.changePassword` (the pointer under the Export Archive footer) | Button in the Privacy page; link button in the Export Archive card | — | — | Opens the dialog ([flows/change-password](flows/change-password.md)). |
| `change-password-submit` | `settings.changePassword.change` | Dialog: primary button | `Enter` | dialog | Enter in the last field. |
| `change-password-retry` | `common.tryAgain` | Dialog: button | — | — |  |
| `change-password-cancel` | `common.cancel` | Dialog: close button | `Esc` | dialog |  |
| `toggle-app-lock` | `settings.privacy.appLock.require` | `ToggleSwitch` in the header of the App lock `SettingsExpander` | — | — | Windows Hello first. Dimmed with a footer when Hello isn't set up ([13](platform.md#13-device-authentication-and-app-lock)). |
| `set-inactivity-lock` | `settings.privacy.appLock.inactive` | `ComboBox` in the expanded part of the App lock expander | — | — | Offered on Windows as on the Mac; longer or Never asks for Hello first. |
| `unlock-with-device` | `settings.lock.unlockWith` | Lock page: the default button | `Enter` | dialog | Takes focus when the lock page appears; Windows Hello. |
| `use-credential` | `settings.lock.useCredential` | Lock page: link button | — | — |  |
| `unlock-with-credential` | `settings.lock.unlock` | Lock page: primary button | `Enter` | dialog | Enter in the password field. |
| `use-device-unlock` | `settings.lock.useMethod` | Lock page: link button | — | — |  |
| `copy-recovery-key` | `settings.recoveryKey.copy` | Not offered | — | — | No early libraries on Windows (open-questions D11); if one arrives, copy with the clipboard options in [15](platform.md#15-clipboard). |
| `save-recovery-key` | `settings.recoveryKey.save` | Not offered | — | — | As above; a save picker. |
| `confirm-recovery-key` | `common.continue` | Not offered | — | — | As above. |

### Backup

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `forgot-password` | `settings.changePassword.forgot` | Change Password dialog: link button under Current password | — | — | Offered only when Windows Hello is available and the journals exist only on this PC; asks for Windows Hello first (`settings.changePassword.authReason`). |
| `archive-open` | `common.continue` | Task page: primary button | `Enter` | dialog | Enter in the password field. |
| `archive-import` | `settings.archiveImport.restore` / `settings.archiveImport.importAsNew` | Task page: primary button | — | — |  |
| `archive-import-cancel` | `common.cancel` | Task page: Cancel button | — | — | Esc is not bound. |
| `archive-import-done` | `common.done` | Task page: Done button, default | `Enter` | dialog |  |
| `export-sheet-done` | `common.done` | Dialog: close button | `Esc` | dialog |  |

### Erase

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `erase-device` | `settings.erase.button` | Button in the last group of the General page | — | — | No ellipsis; counts what would be lost, then the warning dialog. |
| `erase-confirm` | `settings.erase.alert.erase` | Warning dialog: primary button with no default button when nothing would be lost; the secondary button, with Export archive… as the default, when journals would be lost | — | — | Windows Hello first when App Lock is on. The one exception to "primary is the verb" ([screens/settings-erase](screens/settings-erase.md), D44). |

### Library problem

Not mapped yet. The Apple apps added these commands in build 18 (the library problem screen); the Windows page for the screen is written against the earlier lock-screen note and needs a new mapping, which goes through the design gate ([open-questions.md](../../open-questions.md)).

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `retry-opening` | `common.tryAgain` | Not mapped yet | — | — | Proposed: the primary button of the page that replaces the library. |
| `erase-unopened` | `settings.erase.button` | Not mapped yet | — | — | Proposed: Windows Hello first when App lock is on or can't be known. |
| `open-library-guide` | `library.problem.learnMore` | Not mapped yet | — | — | Proposed: a hyperlink button. |

### Agent Access

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `copy-mcp-address` | `common.copy` | Button in the address card | — | — | A plain copy; announced as copied. |
| `share-mcp-address` | `common.share` | Not offered | — | — | A desktop: Copy only, as on the Mac. |
| `open-agent-guide` | `settings.agents.connect.guide` | Hyperlink in the card description | — | — |  |
| `agents-try-again` | `common.tryAgain` | Button in the error `InfoBar` | — | — |  |
| `review-agent-request` | the request row | Clickable row in the Agent access page | — | — | Opens the Allow access dialog. |
| `allow-agent` | `settings.allowAgent.allow` | Dialog: primary button | `Enter` | dialog | Enter in the number field. |
| `decline-agent` | `settings.allowAgent.dontAllow` | Dialog: close button | `Esc` | dialog |  |
| `open-agent` | the agent row | Clickable row in the Agent access page | — | — | Opens the agent's page (a page, not a dialog). |
| `rename-agent` | `common.name` | Text box on the agent's page | `Enter` | dialog | Saves on Enter or when focus leaves. |
| `change-agent-journals` | `settings.agents.allJournals` / `settings.agents.selectedJournals` | Radio buttons and check boxes on the agent's page | — | — | Saved after half a second, as on Apple. |
| `change-agent-expiry` | `settings.agentDetail.ends` | `ComboBox` or date control on the agent's page | — | — |  |
| `revoke-agent` | `common.revokeAccess` / `settings.agentDetail.remove` | Button on the agent's page; confirmation dialog unless the access has ended | — | — |  |
| `agent-detail-done` | `common.done` | Not offered | — | — | A page: Back leaves it. |

### About and Help

| id | Copy key | Placement | Shortcut | Scope | Notes |
| --- | --- | --- | --- | --- | --- |
| `about-privacy-policy` | `common.privacyPolicy` | Settings ▸ About | — | — | As `help-privacy`. |
| `about-support` | `settings.about.support` | Settings ▸ About | — | — | As `help-support`. |
| `about-source-code` | `settings.about.sourceCode` | Settings ▸ About | — | — | As `help-source`. |
| `about-rate` | `common.rateMyJournal` | Settings ▸ About | — | — | As `help-rate`; Store builds only. |

## Windows additions

Shortcuts and gestures Windows people expect that have no Apple command id.

| Addition | Shortcut | Scope | Notes |
| --- | --- | --- | --- |
| Finish saving the open entry now, silently | `Ctrl+S` | app | A hidden accelerator with no menu item and no message; a failed save shows the usual notice. Windows people press it by habit (open-questions D27). |
| Move between the navigation pane, the list, the formatting bar (when shown) and the editor | `F6`, `Shift+F6` | app | Microsoft's "next UI pane" keys. Always leaves the editor, so Tab can stay a tab. |
| Back (stacked layout, Settings pages, task pages, review, history and Image descriptions pages) | `Alt+Left` | app | Also the mouse back button and the back button. Not in dialogs. A page with unsaved work or a running action asks first. Esc is never Back ([7.2](platform.md#72-additions)). |
| Zoom the editor text | Ctrl+mouse wheel, touchpad pinch | — | Not keys; same range as `zoom-in` and `zoom-out`. |

## Keys in the text

The keys listed under Keys in the text in [commands.md](../../commands.md#keys-in-the-text) keep their behaviour, with Windows key names: Return is Enter, Delete is Backspace, Forward Delete is Delete, and ⇧⌘Return is Ctrl+Shift+Enter. Option-Backspace (delete a word) is Ctrl+Backspace. Command-Backspace (delete to the start of the line) has no standard Windows key and is not offered; the rules B-1 to B-10 apply to Backspace and Ctrl+Backspace. In a list, Ctrl+Backspace is not bound ([7](platform.md#7-keyboard-shortcuts)).
