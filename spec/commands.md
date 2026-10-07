# Commands

Every command of My Journal: menu items, toolbar actions, context-menu actions, swipe actions and keyboard shortcuts, where each appears on the Apple platforms, its shortcut and when it is enabled. Each command id is defined once, in the first column of one table (`tools/check-spec.py` checks this and that every command id named elsewhere in the spec exists). Behaviour is in the screen and flow files named in the rows; labels are copy keys from [copy/en.json](copy/en.json).

Shortcut symbols: ⌘ Command, ⌥ Option, ⇧ Shift, ⌃ Control, ↩ Return, ⎋ Escape, ⌫ Delete. “—” means none. “System” means the platform supplies the item; the app doesn't define it. Sheets follow the platform's default and cancel keys (Return for the default button, Escape for Cancel) unless a row says otherwise. Buttons that hand over the journals' key or merge journals use ⌘↩ instead of ↩, so they can't be chosen before reading.

Abbreviations: **Mac** = computer (menu bar, toolbar, context menus). **iPad** = tablet (menu bar and ⌘-hold shortcut list with a hardware keyboard, plus on-screen controls). **iPhone** = phone (on-screen controls; a hardware keyboard reaches only the text view's own shortcuts, marked *text*). “Formatting” = the Formatting surface ([screens/format-sheet](screens/format-sheet.md)). “Bar” = the writing controls (bottom bar while reading, keyboard accessory while writing).

Areas: [Menu bar](#menu-bar), [Toolbars, context menus and swipes](#toolbars-context-menus-and-swipes), [Keyboard in lists, sheets and choosers](#keyboard-in-lists-sheets-and-choosers), [Editor](#editor) and [Settings](#settings).

## Menu bar

On the Mac the menus are My Journal, File, Edit, Format, View, Window, Help. iPad with a hardware keyboard shows File, Edit, Format, View and Help with the same commands (and lists them in the ⌘-hold overlay), except where the iPad column says “—”.

| id | Name (copy key) | Mac menu path and shortcut | iPad shortcut | iPhone and iPad location | Enabled when | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| `about` | system | My Journal ▸ About My Journal | — | — | always | System About panel. |
| `open-settings` | `library.toolbar.settings` (Mac: system) | My Journal ▸ Settings… ⌘, | — | Journals screen top left (iPhone); last sidebar row (iPad) | always (the iPad row is dimmed in journal edit mode) | Opens Settings ([screens/settings](screens/settings.md)). |
| `lock-my-journal` | `common.lockMyJournal` | My Journal ▸ Lock My Journal ⌃⌘L (below Settings…) | — | Settings ▸ Privacy, App Lock section (button) | App Lock is on | Saves, then locks, and closes Settings ([flows/app-lock](flows/app-lock.md)). |
| `quit`, `hide`, `services` | system | My Journal ▸ Services, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q | — | — | always | Quit waits for the open entry to be saved (Keep Open alert if it can't). |
| `new-entry` | `library.menu.file.newEntry` | File ▸ New Entry ⌘N | ⌘N | Bottom bar (Journals screen and every list), icon only | library open, unlocked, not being replaced, a journal in use (File menu); the bar buttons don't need a journal | [flows/new-entry](flows/new-entry.md). Reopens the Mac window if closed. |
| `new-blank-entry` | `library.menu.file.newBlankEntry` | File ▸ New Blank Entry ⇧⌘N | ⇧⌘N | — | as New Entry (File menu) | A new empty entry, ignoring the default template. |
| `new-entry-from-template` | `library.menu.file.newEntryFromTemplate` | File ▸ New Entry from Template… | — | — | as New Entry, and a template exists | Opens the template chooser sheet at once; outside a journal with two or more journals it asks which journal ([screens/template-chooser](screens/template-chooser.md)). |
| `new-journal` | `common.newJournalEllipsis` | File ▸ New Journal… ⌥⌘N | ⌥⌘N | Journals screen top right (iPhone); sidebar bar (iPad); toolbar `library.toolbar.newJournal` | library open and unlocked | New Journal alert ([screens/journals](screens/journals.md)). On the Mac leaves Editor Only. |
| `pin-entry` | `library.entryActions.pin` / `library.entryActions.unpin` | File ▸ Pin Entry / Unpin Entry (own group after New Journal…; no shortcut) | — | Leading swipe, context menu, Entry Actions | the open entry can be pinned (in a journal in use, pinning available) | Pins or unpins the open entry. Undo `library.entryActions.pinUndo`; announced `messages.announce.pinned` / `messages.announce.unpinned`; failure `messages.generic.pinFailed` / `messages.generic.unpinFailed`. |
| `import-archive` | `common.importArchive` | File ▸ Import Archive… | — | Welcome screen; Settings ▸ Backup (button) | unlocked | File picker for an archive, then the import sheet ([flows/import-archive](flows/import-archive.md)). |
| `export-archive` | `common.exportArchive` | File ▸ Export Archive… | — | Settings ▸ Backup (button); the Erase warning | library open, unlocked, no export running | Export Archive sheet ([flows/export-archive](flows/export-archive.md)). |
| `export-markdown` | `library.menu.file.exportMarkdown` (menu); `settings.backup.exportMarkdown` (Settings button) | File ▸ Export Journals as Markdown… | — | Settings ▸ Backup (button) | library open, unlocked, not preparing | Export as Markdown sheet ([flows/export-markdown](flows/export-markdown.md)). The two labels differ ([open-questions](open-questions.md), copy inconsistencies). |
| `delete-all-recently-deleted` | `library.menu.file.deleteAll` (menu); `library.recentlyDeleted.deleteAll` (bar button “Delete All…”) | File ▸ Delete All in Recently Deleted… ⇧⌘⌫ (after a separator) | — | Recently Deleted bar, top right | Recently Deleted shown in the front window, with rows, no search, no Delete All running, unlocked, not being replaced | Delete All ([screens/recently-deleted](screens/recently-deleted.md#delete-all)). |
| `close-window` | system | File ▸ Close ⌘W | — | — | a window is in front | Closes the window after saving the open entry; Keep Open alert if it can't. |
| `undo`, `redo` | system, with action names `library.entryActions.deleteEntry`, `library.entryActions.deleteTemplate`, `library.entryActions.pinUndo`, `library.entryActions.unpin`, `library.journals.undoMove` and the editor's step names `editor.undo.*` | Edit ▸ Undo ‹name› ⌘Z, Redo ‹name› ⇧⌘Z | ⌘Z, ⇧⌘Z; keyboard bar undo and redo | system (shake, three-finger gestures) | something to undo | Undoes Delete Entry/Template, Pin/Unpin Entry, Move Journal and editor changes (rules U-1 to U-8 in [flows/editing-rules](flows/editing-rules.md)). In a table cell ⌘Z and ⇧⌘Z undo the entry. |
| `edit-text` | system | Edit ▸ Cut ⌘X, Copy ⌘C, Paste ⌘V, Paste and Match Style ⌥⇧⌘V, Delete, Select All ⌘A | same | Edit menu; text context menu | text focus | System text commands. Rules PA-1 to PA-15 (Paste and Match Style: PA-10), E-4 and B-9 in [flows/editing-rules](flows/editing-rules.md); a single selected picture: [flows/image-actions](flows/image-actions.md). |
| `paste-and-match-style` | system | Edit ▸ Paste and Match Style ⌥⇧⌘V | Edit menu | Edit menu | text focus | Pastes text without the source's formatting (PA-10 in [flows/editing-rules](flows/editing-rules.md)). |
| `find` | system | Edit ▸ Find ▸ Find… ⌘F (find bar above the entry), Find and Replace… ⇧⌘F, Find Next ⌘G, Find Previous ⇧⌘G, Use Selection for Find ⌘E, Jump to Selection ⌘J | ⌘F, ⇧⌘F (Find and Replace…) | Entry Actions ▸ `library.entryActions.findInEntry` (system find navigator) | the editor has focus | Find in the open entry (V-3 in [flows/editing-rules](flows/editing-rules.md)). Find and Replace… is moved from ⌥⌘F to ⇧⌘F. |
| `search-entries` | `library.menu.edit.searchEntries` | Edit ▸ Search Entries ⌥⌘F (below Find) | ⌥⌘F (iPadOS 17 or later; not offered before) | the list's search field | library open, unlocked | Focuses the list's search ([screens/search](screens/search.md)). |
| `text-editing-system` | system | Edit ▸ Spelling and Grammar, Substitutions, Transformations, Speech, Start Dictation, Emoji & Symbols | — | system keyboard settings | text focus | System. Prose follows these settings; code and source stay literal (SP-1, SP-2). |
| `format-*` | `library.menu.format.*` | Format menu | the same, except Table ▸ (Mac only) | Formatting controls in the editor | the open entry can be edited; see Editor ▸ Format and Table | Each Format command has its own id under [Editor](#editor). The Format menu is disabled while the open item can't be edited. |
| `toggle-sidebar` | system | View ▸ Show Sidebar / Hide Sidebar ⌃⌘S | system | the sidebar button (iPad) | the window has columns | Shows or hides the sidebar; from Editor Only shows every column. |
| `toggle-toolbar` | system | View ▸ Show Toolbar / Hide Toolbar ⌥⌘T | — | — | always | System. |
| `show-editor-only` | `library.menu.view.showEditorOnly` / `library.menu.view.showSidebarAndList`; toolbar toggle `library.toolbar.editorOnly` (help `library.toolbar.editorOnly.help` / `library.toolbar.editorOnly.helpActive`) | View ▸ Show Editor Only / Show Sidebar and List ⇧⌘D | — | — | a library window is in front | Hides or shows the sidebar and list together ([screens/library-window](screens/library-window.md)). |
| `previous-entry` | `library.menu.view.previousEntry` | View ▸ Previous Entry ⌥⌘↑ | — | — | a library window is in front and there is an item above (or nothing is open) | Opens the item above in the list ([screens/library-window](screens/library-window.md)). |
| `next-entry` | `library.menu.view.nextEntry` | View ▸ Next Entry ⌥⌘↓ | — | — | as above, below | Opens the item below in the list. |
| `view-source` | `library.menu.view.viewSource` / `library.menu.view.viewPreview` (the same labels on the Mac toolbar button and the reading bar button) | View ▸ View Source / View Preview ⌥⌘U | ⌥⌘U (View menu) | reading bar; Mac toolbar | the open item can be edited; View Preview also needs a previewable entry (tooltip `common.previewUnavailable` otherwise) | Switches the editor between formatted text and Markdown source ([flows/source-view](flows/source-view.md), S-1 to S-7). |
| `zoom-in` | `library.menu.view.zoomIn` | View ▸ Zoom In ⌘+ (also ⌘=) | ⌘+ (View menu) | — | below 30 points | Editor text one point larger, up to 30 ([screens/entry-editor](screens/entry-editor.md), Rules). |
| `zoom-out` | `library.menu.view.zoomOut` | View ▸ Zoom Out ⌘− | ⌘− (View menu) | — | above 12 points | One point smaller, down to 12. |
| `actual-size` | `library.menu.view.actualSize` | View ▸ Actual Size ⌘0 | ⌘0 (View menu) | — | not at the default size | Back to the default (16 points; the Dynamic Type size on iPad). |
| `enter-full-screen` | system | View ▸ Enter Full Screen ⌃⌘F | — | — | always | System. |
| `window-*` | system | Window ▸ Minimize ⌘M, Zoom, Bring All to Front, the window's name | — | — | always | System. No window tabs. |
| `help-guide` | `library.menu.help.guide` | Help ▸ My Journal Help ⌘? | ⌘? | Settings ▸ About (screens/settings-about) | always | Opens the user guide on the web. |
| `help-support` | `library.menu.help.support` | Help ▸ My Journal Support | — | Settings ▸ About | always | Opens SUPPORT.md on the web. |
| `help-privacy` | `common.privacyPolicy` | Help ▸ Privacy Policy | — | Settings ▸ About | always | Opens PRIVACY.md on the web. |
| `help-source` | `library.menu.help.source` | Help ▸ Source Code on GitHub | — | Settings ▸ About | always | Opens the repository. |
| `help-rate` | `common.rateMyJournal` | Help ▸ Rate My Journal (after a separator) | — | Settings ▸ About | always | Opens the App Store review page. |

## Toolbars, context menus and swipes

Entry actions (the Entry Actions “…” menu in the editor, and an entry's row context menu) each first save the open writing; if that fails, nothing happens. Labels and symbols are specified with the entries list ([screens/entry-list](screens/entry-list.md)).

| id | Name (copy key) | Mac menu path and shortcut | iPad shortcut | iPhone and iPad location | Enabled when | What it does |
| --- | --- | --- | --- | --- | --- | --- |
| `choose-collection` | collection names (`library.journals.*`) | sidebar row; arrow keys in the focused sidebar | — | sidebar row (iPad), Journals screen row (iPhone) | not in edit mode | Shows that collection's list, saving the open entry first. |
| `journal-actions` | `library.toolbar.journalActions` | toolbar menu over the list | — | list bar ⋯ in a journal; ⋯ on a row in edit mode | library open | Menu of the journal actions below (Mac: New Journal… first). |
| `rename-journal` | `library.journalActions.rename` | journal row context menu; Journal Actions | — | journal context menu; Journal Actions | no changes to review | Rename Journal alert. |
| `journal-default-template` | `common.defaultTemplate` | context menu; Journal Actions ▸ submenu | — | same | no changes to review, and a template exists or a stale choice remains | Sets the template New Entry uses in the journal. |
| `merge-journal` | `library.journalActions.mergeInto` | context menu; Journal Actions | — | same | no changes to review, another journal in use | Merge Into… sheet ([screens/merge-journal](screens/merge-journal.md)). |
| `journal-version-history` | `common.versionHistoryEllipsis` | context menu; Journal Actions; deleted journal's detail | — | same | always (detail: when it has versions) | Journal Version History ([screens/journal-history](screens/journal-history.md)). |
| `delete-journal` | `library.journalActions.deleteJournal` | context menu; Journal Actions | — | same | always | Delete Journal alert. |
| `reorder-journal` | `library.journals.undoMove` (Undo name) | drag a journal row in the sidebar | — | drag the handle in edit mode; touch, hold and drag; VoiceOver `library.journals.moveUp` / `library.journals.moveDown` | order readable, unlocked, not being replaced | Moves the journal; announced; undoable. |
| `journals-edit` | `library.toolbar.edit` / `common.done` | — (no edit mode on the Mac) | — | Journals screen and iPad sidebar bar | journals in use, unlocked, not being replaced | Enters or leaves edit mode. |
| `new-journal-context` | `common.newJournalEllipsis` | sidebar context menu (rows and empty area) | — | empty list (no journals) | library open | New Journal alert. |
| `entry-actions` | `library.toolbar.entryActions` | toolbar menu over the editor | — | editor bar ⋯ | an entry or template is open | Menu of the entry actions below. |
| `find-in-entry` | `library.entryActions.findInEntry` | Edit ▸ Find ▸ Find… ⌘F | ⌘F | Entry Actions (first) | an entry is open | The system's find in the entry: the find bar on the Mac, the find navigator on iPhone and iPad. |
| `pin-entry-row` | `library.entryList.swipe.pin` / `library.entryList.swipe.unpin`; menu `library.entryActions.pin` / `.unpin` | context menu; trackpad leading swipe | — | leading swipe (full swipe), context menu, Entry Actions | entry in a journal in use, pins readable, unlocked | Pins or unpins without changing the selection. |
| `new-entry-in` | `library.entryActions.newEntryIn` ▸ journals / `library.entryActions.newEntryFromTemplate` | template context menu; Entry Actions | — | same | a journal in use, no failed save, unlocked, template without changes to review | New entry from that template in the chosen journal. |
| `review-changes` | `common.reviewChanges` | notice above an entry or template with a conflict; Settings ▸ Sync ▸ Changes to Review | same | same | unlocked (the entry has a conflict, for the notice) | Saves the open writing, then opens the conflict review for that item ([screens/conflict-review](screens/conflict-review.md), [screens/entry-conflict](screens/entry-conflict.md)). |
| `change-date` | `library.entryActions.changeDate` | context menu; Entry Actions | — | same | entry editable in a journal in use | Change Date sheet ([screens/change-date](screens/change-date.md)). |
| `move-entry` | `library.entryActions.moveEntry` | context menu; Entry Actions | — | same | same | Move Entry sheet ([screens/move-entry](screens/move-entry.md)). |
| `save-as-template` | `library.entryActions.saveAsTemplate` | context menu; Entry Actions | — | same | same | Save as Template alert ([screens/entry-list](screens/entry-list.md)). |
| `image-descriptions` | `library.entryActions.imageDescriptions` | context menu; Entry Actions | — | same | the item has pictures (shown) and descriptions can be edited (enabled) | [screens/image-description](screens/image-description.md). |
| `entry-version-history` | `common.versionHistoryEllipsis` | context menu; Entry Actions | — | same | always | [screens/version-history](screens/version-history.md). |
| `restore` | `common.restore` (context menu, Entry Actions, leading swipe and notice) | context menu; Entry Actions; notice | — | leading swipe (full swipe), context menu, Entry Actions, notice | in Recently Deleted, journal in use (entries) | Restores without confirmation ([flows/delete-and-restore](flows/delete-and-restore.md)). |
| `restore-with-journal` | `library.recoveryNotice.restoreWithJournal` | recovery notice | — | recovery notice | entry's journal deleted, editable, no review pending | Restore Entry sheet. |
| `restore-and-move` | `library.recoveryNotice.restoreAndMove` | recovery notice | — | recovery notice | item editable (an entry in Recently Deleted or deleted with its journal by an earlier version) | Move Entry in its restoring form ([screens/move-entry](screens/move-entry.md)). |
| `restore-journal` | `library.recentlyDeleted.restoreJournal` | deleted journal's detail | — | same | journal editable, not being replaced | Restore Journal sheet. |
| `try-syncing-again` | `common.trySyncingAgain` | recovery notice; Restore sheet | — | same | journal missing, library syncs | Syncs now, retrying refused items. |
| `delete-permanently` | `library.entryActions.deletePermanently` (context menu, Entry Actions, deleted journal's detail) | context menu; Entry Actions; Delete or ⌘⌫ in the focused list; deleted journal's detail | — | trailing swipe (`common.delete`, removes the row first), context menu, Entry Actions, detail | in Recently Deleted, not being replaced | Delete Permanently alert. |
| `delete-entry` | `library.entryActions.deleteEntry` / `library.entryActions.deleteTemplate`; swipe `common.delete` | context menu; Entry Actions (destructive, last); Delete or ⌘⌫ in the focused list | — | trailing swipe (full swipe), context menu, Entry Actions (destructive, last) | item editable and not deleted (menus: in a journal in use or a template) | Moves it to Recently Deleted at once; Undo brings it back. |
| `clear-search` | `library.entryList.empty.clearSearch` | under No Results | — | under No Results | a search is active | Empties the search. |
| `empty-new-entry` | `library.menu.file.newEntry` | empty journal or All Entries | — | same | New Entry possible | As `new-entry`. |
| `finish-editing` | `common.done` (checkmark) | — | — | editor navigation bar, trailing, while writing | the title, body or a cell has keyboard focus | Ends typing, finishes the save and returns to reading. |
| `sync-status` | `messages.syncStatus.title` | toolbar (only when sync needs the person) | — | Entry Actions ▸ Sync Status | sync needs the person | screens/sync-status. |
| `use-a-template` | `library.templateChooser.useTemplate` (VoiceOver); the link's own text `editor.body.placeholder.templateLink` | link in an empty entry (popover) | — | link in an empty entry (popover on iPad, sheet on iPhone) | the empty entry can be edited and a template exists | Template chooser that fills the entry. |

## Keyboard in lists, sheets and choosers

| Context | Keys |
| --- | --- |
| Mac entries list (focused) | ↑/↓ move the selection and open the entry; Delete or ⌘⌫ delete (or ask to delete permanently in Recently Deleted). |
| Mac sidebar (focused) | ↑/↓ choose a collection. Escape cancels a journal drag. |
| Template chooser | Typing filters; ↑/↓ move the highlight; Return creates; Escape closes (not while an input method is composing). Works on iPad with a keyboard too. |
| Sheets (Mac) | Return = the default button (Move, Merge, Save); Escape = Cancel. The Restore Journal and Restore Entry action has no Return shortcut. |
| Lock screen (Mac) | Return = Unlock with {method}. |
| Create library | Return in Master Password moves to Verify; Return in Verify = Create. |

## Editor

Commands that act on the open entry or template. View, Edit and Entry Actions commands are defined in the sections above (`view-source`, `zoom-in`, `undo`, `find`, `pin-entry`, `change-date`, …). Behaviour is specified in [screens/entry-editor](screens/entry-editor.md), [screens/format-sheet](screens/format-sheet.md) and the rule IDs of [flows/editing-rules](flows/editing-rules.md). The Format, View and Edit menu labels are `library.menu.*`.

**Editable** = the entry or template can be edited ([screens/entry-editor](screens/entry-editor.md), Rules). The whole Format menu is disabled when the open item isn't editable. Format commands act only while the body or a table cell has keyboard focus; from elsewhere they do nothing ([open-questions](open-questions.md), app bugs).

### Format

| id | Label | Mac menu | Mac shortcut | iPad shortcut | iPhone, iPad on screen | Enabled | Rules |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `show-formatting` | `library.toolbar.formatting` | — (toolbar button Formatting; overflow menu item) | — | — | Bar ▸ Formatting (Aa) | Editable | format-sheet |
| `format-bold` | `library.menu.format.bold` | Format ▸ Bold | ⌘B | ⌘B (menu and *text*) | Formatting ▸ **B** | Editable, not in code | F-1, F-2, F-4 |
| `format-italic` | `library.menu.format.italic` | Format ▸ Italic | ⌘I | ⌘I (menu and *text*) | Formatting ▸ *I* | same | F-1, F-4 |
| `format-underline` | `library.menu.format.underline` | Format ▸ Underline | ⌘U | ⌘U (menu and *text*) | Formatting ▸ U̲ | same | F-1, F-4 |
| `format-strikethrough` | `library.menu.format.strikethrough` | Format ▸ Strikethrough | ⇧⌘X | ⇧⌘X (menu and *text*) | Formatting ▸ S̶ | same | F-3, F-4 |
| `format-inline-code` | `library.menu.format.inlineCode` | Format ▸ Inline Code | ⌥⌘C | ⌥⌘C (menu only) | Formatting ▸ `<>` | same | F-3, F-4, F-7 |
| `format-paragraph` | `library.menu.format.paragraph` | Format ▸ Paragraph | ⌥⌘0 | ⌥⌘0 (menu and *text*) | Formatting ▸ Paragraph | Editable; Formatting: not in a cell or code | P-1 to P-6 |
| `format-heading-1` … `format-heading-6` | `library.menu.format.heading` (1–6) | Format ▸ Heading 1 … Heading 6 | ⌥⌘1 … ⌥⌘6 | ⌥⌘1 … ⌥⌘6 (menu and *text*) | Formatting ▸ Heading 1–3; ▸ More Headings ▸ Heading 4–6 | same | P-1 to P-6 |
| `format-bulleted-list` | `library.menu.format.bulletedList` | Format ▸ Bulleted List | ⇧⌘7 | ⇧⌘7 (menu) | Formatting ▸ Bulleted List | same | P-1 to P-6 |
| `format-numbered-list` | `library.menu.format.numberedList` | Format ▸ Numbered List | ⇧⌘9 | ⇧⌘9 (menu) | Formatting ▸ Numbered List | same | P-1 to P-6 |
| `format-checklist` | `library.menu.format.checklist` | Format ▸ Checklist | ⇧⌘L | ⇧⌘L (menu) | Formatting ▸ Checklist | same | P-1 to P-6 |
| `format-mark-checked` | `library.menu.format.markChecked` / `library.menu.format.markUnchecked` | Format ▸ Mark as Checked / Mark as Unchecked | ⇧⌘U | ⇧⌘U (menu); ⇧⌘Return (*text*) | Formatting ▸ Mark as Checked / Unchecked (only with checklist items selected); a checkbox tap (`toggle-checkbox`) | Caret in a checklist item (menu, not in source view) | C-1, C-2 |
| `format-block-quote` | `library.menu.format.blockQuote` | Format ▸ Block Quote | ⌘' | ⌘' (menu) | Formatting ▸ Block Quote | Editable; Formatting: not in a cell or code | P-1 to P-6 |
| `format-increase-indent` | `library.menu.format.increaseIndent` | Format ▸ Increase Indent | ⌘] ; Tab in a list item or code | ⌘] (menu); Tab (*text*) | Formatting ▸ Increase Indent (icon) | Per I-1 to I-3, I-10, I-11, I-15 | I-1 to I-15 |
| `format-decrease-indent` | `library.menu.format.decreaseIndent` | Format ▸ Decrease Indent | ⌘[ ; Shift-Tab in a list item or code | ⌘[ (menu); Shift-Tab (*text*) | Formatting ▸ Decrease Indent (icon) | Per I-4, I-10, I-11, I-15 | I-4 to I-15 |
| `insert-code-block` | `library.menu.format.insert.codeBlock` | Format ▸ Insert ▸ Code Block | — (or type ```` ``` ```` Return) | — | Formatting ▸ Insert ▸ Code Block | Editable | BI-1, BI-2, K-2 |
| `insert-table` | `library.menu.format.insert.table` | Format ▸ Insert ▸ Table | — | — | Formatting ▸ Insert ▸ Table | Editable | BI-1, BI-3 |
| `insert-horizontal-rule` | `library.menu.format.insert.horizontalRule` | Format ▸ Insert ▸ Horizontal Rule | — (or type `---` Return) | — | Formatting ▸ Insert ▸ Horizontal Rule | Editable | BI-1, BI-2, K-2 |
| `insert-link` | `library.menu.format.insert.link` | Format ▸ Insert ▸ Link… | ⌘K | ⌘K (menu and *text*) | Formatting ▸ Insert ▸ Link… | Editable and the body or a cell has focus | `screens/link-editor.md`, L-1 to L-6 |
| `insert-image` | `library.menu.format.insert.image` | Format ▸ Insert ▸ Image… (open panel) | — | — (menu: photo library) | Formatting ▸ Insert ▸ Image… | Editable | `flows/insert-image.md` |
| `exit-code-block` | `editor.format.exitCodeBlock` | — | Down Arrow at the end of a code block's last line | Down Arrow (*text*) | Formatting ▸ Exit Code Block (only in a code block) | Caret in a code block | BI-4 |

Format menu order (Mac, iPad): Bold, Italic, Underline, Strikethrough, Inline Code, —, Paragraph, Heading 1–6, —, Bulleted List, Numbered List, Checklist, Mark as Checked/Unchecked, Block Quote, —, Increase Indent, Decrease Indent, —, Insert ▸ (Code Block, Table, Horizontal Rule, —, Link…, Image…), then on the Mac Table ▸.

### Table

| id | Label | Mac | iPad, iPhone | Enabled | Rules |
| --- | --- | --- | --- | --- | --- |
| `table-add-row` | `library.menu.format.table.addRow` | Format ▸ Table ▸ Add Row Below; cell context menu ▸ Table ▸ | Cell edit menu ▸ Table ▸ | A cell is being edited, editable | TB-4 |
| `table-add-column` | `library.menu.format.table.addColumn` | Format ▸ Table ▸ Add Column After; cell menu | Cell edit menu ▸ Table ▸ | same | TB-4 |
| `table-align-left` / `table-align-center` / `table-align-right` | `editor.table.alignLeft` … (Mac); `editor.table.alignment` ▸ `editor.table.alignment.left` … (iOS) | Cell context menu ▸ Table ▸ Align Left / Align Center / Align Right | Cell edit menu ▸ Table ▸ Alignment ▸ Left / Center / Right | same | TB-4 |
| `table-delete-row` | `library.menu.format.table.deleteRow` | Format ▸ Table ▸ Delete Row; cell menu | Cell edit menu ▸ Table ▸ (destructive) | same | TB-4 |
| `table-delete-column` | `library.menu.format.table.deleteColumn` | Format ▸ Table ▸ Delete Column; cell menu | same (destructive) | same | TB-4 |
| `table-delete-table` | `library.menu.format.table.deleteTable` | Format ▸ Table ▸ Delete Table; cell menu | same (destructive) | same | TB-4 |
| `table-next-cell` / `table-previous-cell` | — | Tab / Shift-Tab in a cell | Tab / Shift-Tab (*text*) | In a cell | TB-3 |
| `table-cell-below` | — | Return in a cell | Return | In a cell | N-15, TB-3 |

### Editor-only controls

| id | Label | Mac | iPad, iPhone | Enabled | Result |
| --- | --- | --- | --- | --- | --- |
| `insert-image-choose-file` | `library.toolbar.insertImage` | Toolbar Insert Image (open panel) | Bar ▸ Insert Image ▸ `editor.insertImage.chooseFile` | Editable | `flows/insert-image.md` |
| `insert-image-photo-library` | `editor.insertImage.photoLibrary` | — | Bar ▸ Insert Image ▸ Photo Library | Editable | same |
| `insert-image-take-photo` | `editor.insertImage.takePhoto` | — | Bar ▸ Insert Image ▸ Take Photo (only with a usable camera) | Editable | same |
| `toggle-checkbox` | item text; value `editor.list.checked` / `editor.list.unchecked` | Click a checkbox | Tap a checkbox | Editable | C-3 |
| `image-copy`, `image-cut`, `image-paste`, `image-share`, `image-save-to-photos`, `image-save-as`, `image-delete` | see `flows/image-actions.md` | Right-click on a picture | Long press on a picture | see flow | IM-5, image-actions |
| `close-formatting` | `editor.format.close` | Escape, or Formatting again | Close button, Aa again, Escape (*text*) | Formatting shown | format-sheet |

### Keys in the text

| Key | Where | Result | Rules |
| --- | --- | --- | --- |
| Return | Item, quote, heading, code, cell, title, `---`/```` ``` ```` line | Continue, split, leave list, new paragraph, new code line, cell below, to body, convert line | N-1 to N-15, T-1, K-2 |
| Backspace (also Option-, Command-Backspace) | Start of an item or quote; straight after a shortcut; across lines | Remove one level; give back typed marker; join lines | B-1 to B-10, K-4 |
| Forward Delete | End of a line | Join lines (B-6); nothing at the end of the last item (E-2) | B-6, E-2 |
| Tab / Shift-Tab | List item, code, cell, paragraph, title | Indent/outdent; tab in code; next/previous cell; tab character; to body (iPhone, iPad title) | I-12, I-15, TB-3, T-1 |
| Down Arrow | End of a code block's last line | Leave the code block | BI-4 |
| Space after a marker | Start of a plain paragraph | Markdown shortcut | K-1 |
| Escape | Formatting shown | Close it | format-sheet |
| ⇧⌘Return | Checklist item (iPhone, iPad *text*) | Mark as Checked / Unchecked | C-1 |

### Notes

- iPad menu-bar commands come from the same command definitions as the Mac's, except Format ▸ Table ▸ and the Mac-only View items.
- No two menu-bar commands share a shortcut (`MenuShortcutTests.testMenuBarShortcutsAreUnique`); ⌘= also triggers Zoom In (`MenuShortcutTests.testZoomInAnswersCommandEqualsWithoutShift`).
- iPhone with a hardware keyboard: whether the iPad menu-bar shortcuts (⇧⌘7, ⇧⌘9, ⇧⌘L, ⌘', ⌘], ⌘[, ⌥⌘C, ⌥⌘U) also work isn't established by any test; only the text view's own shortcuts (*text*) are certain.

## Settings

Every command in Settings and the flows it opens. Commands that live on other surfaces are defined once above and only placed here: `open-settings`, `lock-my-journal` (App Lock section), `import-archive`, `export-archive`, `export-markdown` (Backup), `help-guide`, `review-changes` (Changes to Review). The Settings ▸ About links have their own ids because the Help menu items (`help-privacy`, `help-support`, `help-source`, `help-rate`) are Mac and iPad-keyboard commands with the same destinations.

### Settings structure

| id | Name (copy key) | Mac | iPhone and iPad | Enabled when | What it does |
| --- | --- | --- | --- | --- | --- |
| `settings-open-pane` | `settings.pane.*` | a tab in the Settings window | a row in Settings | always | Shows Writing/General, Sync, Devices, Privacy, Backup or Agent Access. |
| `settings-done` | `common.done` | — | Settings sheet, confirming position | always | Closes Settings. |

### Writing / General

| id | Name (copy key) | Location | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `choose-default-journal` | `settings.general.defaultJournal` | Settings ▸ Writing/General | at least one journal | Sets where New Entry files entries outside a journal. |
| `toggle-format-as-you-type` | `settings.general.formatAsYouType` | Settings ▸ Writing/General | always | Turns Markdown shortcuts at line starts on or off. |

### Sync

| id | Name (copy key) | Location | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `connect-to-server` | `common.connectToServer` | Settings ▸ Sync, Devices, Agent Access (not connected); first-launch screen | unlocked | Opens Connect to a Server (`flows/connect-to-server`). |
| `sync-now` | `messages.sync.action.syncNow` / `common.tryAgain` / `messages.sync.action.checkAgain` | Settings ▸ Sync | connected, unlocked, not replacing the journals, no failed save, no sync the person started running | Syncs once, resending refused items; announces the result. |
| `sync-reconnect` | `messages.sync.action.setUpServerAgain` / `messages.sync.action.connectAgain` / `common.signIn` | Settings ▸ Sync; Settings ▸ Devices (access refused); Settings ▸ Privacy (Sign In…); Settings ▸ Agent Access (no access) | the sync state calls for it | Opens Connect to a Server at this server's next step (`flows/reconnect-to-server`). |
| `stop-syncing` | `settings.sync.stopSyncing` | Settings ▸ Sync | connected, not replacing the journals | Confirmation, then `flows/stop-syncing`. |
| `open-setup-guide` | `settings.sync.footer.howToSetUp` (both footers) | Settings ▸ Sync footer; Set Up Server footer | always | Opens the sync guide. |
| `open-former-server-guide` | `settings.sync.footer.learnMore` | Settings ▸ Sync footer (Mac only) | after the former Mac server stopped | Opens the guide's section for people who used Use This Mac. |

### Connect to a Server

| id | Name (copy key) | Shortcut | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `connect-check-server` | `common.continue`; a nearby server row | ↩ in the address field | address not empty, not checking | Checks the server; goes to the next step. |
| `connect-scan-code` | `settings.connect.scanCode` | — | iPhone/iPad with a supported camera scanner | Opens Scan Code. |
| `scan-cancel` | `common.cancel` | — | always | Closes the scanner. |
| `scan-open-settings` | `common.openSettings` | — | camera access denied | Opens the system's settings for My Journal. |
| `connect-set-up` | `settings.connect.setUp.setUp` / `common.continue` / `common.tryAgain` | ↩ | fields filled, not working | Validates and sets up the server (`flows/connect-to-server` §3–6). |
| `connect-sign-in` | `settings.connect.signIn.signIn` / `common.connect` / `common.tryAgain` | ↩ | credential typed, not working | Signs in with the credential or recovery code. |
| `connect-use-device` | `settings.connect.signIn.useDevice` | — | not working | Pushes Add This Device. |
| `connect-copy-code` | `settings.connect.addThisDevice.copyCode` | — | a pairing code shown | Copies the nine digits. |
| `connect-confirm-check-code` | `common.connect` | ⌘↩ (not ↩) | check code shown, not yet confirmed | Accepts the approval after comparing codes. |
| `connect-new-code` | `settings.connect.addThisDevice.getNewCode` | — | after a pairing failure with nothing received | Withdraws the request and gets a new code. |
| `connect-use-recovery-code` | `settings.connect.addThisDevice.useRecoveryCode` | — | server without encryption, not installing | Pushes Use a Recovery Code. |
| `connect-merge` | `common.merge` | ⌘↩ (not ↩) | not working | Agrees to merge with this server; continues. |
| `connect-retry` | `common.tryAgain` / `settings.connect.scanAgain` | — | after a failure | Tries the same step again, or scans a new code. |
| `connect-cancel` | `common.cancel` | ⎋ | not installing | Stops, withdraws requests, gives up unused access, closes. |
| `connect-done` | `common.done` | ↩ | Server Is Ready | Closes. |
| `show-connection` | `messages.writingPaused.showConnection` | — | Mac, while connecting from Settings | Brings Settings and the sheet forward. |

### Devices

| id | Name (copy key) | Shortcut | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `add-device` | `settings.devices.add`; `settings.connect.ready.addDevice` | — | connected, devices loaded, access not refused | Opens Add Device (`flows/pair-device`). |
| `revoke-device` | `settings.devices.revoke` | — | another device; not busy | Confirmation, then revokes. |
| `devices-try-again` | `common.tryAgain` | — | after a load or revoke error | Retries. |
| `add-device-enter-code` | `settings.addDevice.enterCodeInstead` | — | showing a code | Switches to typing the new device's code. |
| `add-device-look-up` | `common.continue` | ↩ | code typed, not busy | Looks up the code. |
| `add-device-new-code` | `settings.addDevice.showNewCode` | — | session expired | Starts a new session of codes. |
| `add-device-copy-address` | `settings.addDevice.copyAddress` | — | connected through HTTPS | Copies the server address. |
| `add-device-approve` | `settings.addDevice.approve` / `settings.addDevice.add` | ⌘↩ (not ↩) | a request is confirmed, not busy | Authenticates the owner, then sends the key. |
| `add-device-cancel` | `common.cancel` / `settings.addDevice.dontAdd` | ⎋ | not while approving | Declines what waits and closes. |
| `add-device-try-again` | `common.tryAgain` | — | typed code, after an error while waiting | Waits for the new device again. |
| `add-device-done` | `common.done` | — | finished | Closes. |

### Privacy

| id | Name (copy key) | Shortcut | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `turn-on-encryption` | `settings.privacy.encryption.turnOn` | — | journals not encrypted, unlocked, not replacing the journals | Opens Turn On Encryption (`flows/turn-on-encryption`). |
| `encryption-continue` | `common.continue` / `common.tryAgain` | ↩ | not working | Checks space and the server; next step. |
| `encryption-turn-on` | `settings.encryption.turnOn` | ↩ | new password typed twice (and current access password if asked) | Encrypts. |
| `encryption-finish` | `common.tryAgain` | — | unfinished | Finishes after the server switched. |
| `encryption-cancel` | `common.cancel` | ⎋ | before the server is updated | Stops; nothing changes. |
| `encryption-done` | `common.done` | — | encrypted | Closes. |
| `show-encryption-progress` | `messages.writingPaused.showProgress` | — | Mac, while encrypting or unfinished | Opens Settings ▸ Privacy with the sheet. |
| `change-password` | `settings.privacy.changePassword` | — | master-password journals, unlocked | Opens Change Password (`flows/change-password`). |
| `change-password-submit` | `settings.changePassword.change` | ↩ in Confirm | all fields filled, new matches confirm | Changes the password. |
| `change-password-retry` | `common.tryAgain` | — | the server changed, this device didn't save | Saves on this device again. |
| `change-password-cancel` | `common.cancel` | ⎋ | not working; while a local save is pending, only after Try Again failed | Closes without changing anything. |
| `toggle-app-lock` | `settings.privacy.appLock.require` | — | not while asking; on needs authentication available | Authenticates, then turns App Lock on or off (`flows/app-lock`). |
| `set-inactivity-lock` | `settings.privacy.appLock.inactive` | — | Mac, App Lock on | Sets Lock when inactive; longer or Never authenticates first. |
| `unlock-with-device` | `settings.lock.unlockWith` | ↩ (Mac) | locked, not asking | Asks the system to authenticate. |
| `use-credential` | `settings.lock.useCredential` | — | after a failed unlock, journals with a password | Shows the password field. |
| `unlock-with-credential` | `settings.lock.unlock` | ↩ in the field | field not empty | Unlocks with the password or recovery key. |
| `use-device-unlock` | `settings.lock.useMethod` | — | credential form, device key present | Back to device unlock. |
| `copy-recovery-key` | `settings.recoveryKey.copy` | — | early library, key not confirmed | Copies the key (cleared after two minutes). |
| `save-recovery-key` | `settings.recoveryKey.save` | — | early library, key not confirmed | Saves the key as a text file. |
| `confirm-recovery-key` | `common.continue` | — | switch on and last group typed | Confirms and shows the journals. |

### Backup

| id | Name (copy key) | Shortcut | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `password-check` | `settings.passwordCheck.check` | ↩ | password typed | Checks the master password; the export continues. |
| `password-check-not-now` | `settings.passwordCheck.notNow` | ⎋ | not checking | Continues the export without checking. |
| `forgot-password` | `settings.passwordCheck.forgot` | — | after a wrong password; journals only on this device; owner authentication available | `flows/forgot-password`. |
| `set-new-password` | `settings.passwordCheck.setNew.set` | ↩ | both fields match | Sets the new password; the export continues. |
| `set-new-password-cancel` | `common.cancel` | ⎋ | not saving | Back to Check Your Password. |
| `archive-open` | `common.continue` | ↩ in the field | password typed (or none needed), not busy | Opens and previews the archive. |
| `archive-import` | `settings.archiveImport.restore` / `settings.archiveImport.importAsNew` | — | previewed, not busy | Imports. |
| `archive-import-cancel` | `common.cancel` | ⎋ | not importing | Discards and closes. |
| `archive-import-done` | `common.done` | — | imported | Closes. |
| `export-sheet-done` | `common.done` | ⎋ | always | Closes the File-menu export sheet. |

### Erase

| id | Name (copy key) | Location | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `erase-device` | `settings.erase.button` | iPhone/iPad: last section of Settings; Mac: end of General | a library exists and nothing else is changing it | Counts what would be lost; warning (`flows/erase`). |
| `erase-confirm` | `settings.erase.alert.erase` | warning alert (destructive) | — | Authenticates (App Lock on) and erases. |

### Agent Access

| id | Name (copy key) | Shortcut | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `copy-mcp-address` | `common.copy` | — | address shown | Copies the MCP server address. |
| `share-mcp-address` | `common.share` | — | iPhone/iPad, address shown | Share sheet. |
| `open-agent-guide` | `settings.agents.connect.guide` | — | always | Opens the agent guide. |
| `agents-try-again` | `common.tryAgain` | — | server unreachable | Loads again. |
| `review-agent-request` | (the request row) | — | a request waits | Opens Allow Access. |
| `allow-agent` | `settings.allowAgent.allow` | ↩ in the number field | two digits, journals chosen (new agent), under the limit | Allows (`flows/allow-agent`). |
| `decline-agent` | `settings.allowAgent.dontAllow` | ⎋ (Mac) | not allowing | Declines. |
| `open-agent` | (the agent row) | — | agents listed | Opens the agent's detail. |
| `rename-agent` | `common.name` | ↩ saves | access not ended, settings readable | Renames. |
| `change-agent-journals` | `settings.agents.allJournals` / `settings.agents.selectedJournals` and journal switches | — | access not ended, settings readable | Changes the journals (saved after 0.5 s). |
| `change-agent-expiry` | `settings.agentDetail.ends` | — | access not ended, settings readable | Sets when access ends. |
| `revoke-agent` | `common.revokeAccess` / `settings.agentDetail.remove` | — | not working | Revokes (confirmation unless ended). |
| `agent-detail-done` | `common.done` | ↩ (Mac) | not revoking | Closes the Mac detail sheet. |

### About and Help

| id | Name (copy key) | Location | What it does |
| --- | --- | --- | --- |
| `about-privacy-policy` | `common.privacyPolicy` | Settings ▸ About (iPhone/iPad); Help menu as `help-privacy` | Opens PRIVACY.md. |
| `about-support` | `settings.about.support` | Settings ▸ About; Help menu as `help-support` | Opens SUPPORT.md. |
| `about-source-code` | `settings.about.sourceCode` | Settings ▸ About; Help menu as `help-source` | Opens the repository. |
| `about-rate` | `common.rateMyJournal` | Settings ▸ About; Help menu as `help-rate` | Opens the store's review page. |
