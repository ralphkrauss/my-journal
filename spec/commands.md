# Commands

Every command of My Journal, independent of platform: menu items, toolbar actions, context-menu actions, swipe actions and keyboard shortcuts. Each command id is defined once, in the first column of one table (`tools/check-spec.py` checks this and that every command id named elsewhere in the spec exists). A row gives the id, its name (copy keys from [copy/en.json](copy/en.json)), its scope, when it is enabled and what it does; behaviour is in the screen and flow files named in the rows. **Where each command appears, and its shortcut, belongs to the platform:** every platform folder has a `commands.md` with one row for each id here ([platforms/apple/commands.md](platforms/apple/commands.md), [platforms/windows/commands.md](platforms/windows/commands.md)).

“System” means the platform supplies the item; the app doesn't define it. Dialogs follow the platform's default and cancel keys unless a row says otherwise. Buttons that hand over the journals' key or merge journals are never the default button and have no plain Enter or Return shortcut, so they can't be chosen before reading; each platform gives them a deliberate shortcut.

Form factors: **computer** (a window with a menu bar and toolbar), **tablet** and **phone** (on-screen controls; a tablet may also have a hardware keyboard). “Formatting” = the Formatting surface ([screens/format-sheet](screens/format-sheet.md)).

**Scope** (the Menu bar and Toolbars tables) says what a command acts on: `app` (the app or the library window), `list` (a journal or entry in a list, or the list itself), `entry` (the open entry or template), `text` (the text with focus) and `system` (supplied by the platform).

Areas: [Menu bar](#menu-bar), [Toolbars, context menus and swipes](#toolbars-context-menus-and-swipes), [Editor](#editor) and [Settings](#settings).

## Menu bar

On a computer the menus are the application menu, File, Edit, Format, View, Window and Help; a tablet with a hardware keyboard shows File, Edit, Format, View and Help with the same commands. Each platform's `commands.md` says which commands it places in a menu and where.

| id | Name (copy key) | Scope | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `about` | system | app | always | System About panel. |
| `open-settings` | `library.toolbar.settings` (the system's label where the platform supplies the item) | app | always (dimmed in journal edit mode on a tablet) | Opens Settings ([screens/settings](screens/settings.md)). |
| `lock-my-journal` | `common.lockMyJournal` | app | App Lock is on | Saves, then locks, and closes Settings ([flows/app-lock](flows/app-lock.md)). |
| `quit`, `hide`, `services` | system | system | always | Quit waits for the open entry to be saved (Keep Open alert if it can't). |
| `new-entry` | `library.menu.file.newEntry` | app | library open, unlocked, not being replaced, a journal in use (menu item); the buttons don't need a journal | A new, empty entry in the shown journal, else the Default Journal ([flows/new-entry](flows/new-entry.md)). Reopens the library window if it was closed (computer). |
| `use-a-template` | `library.menu.file.useTemplate` (File menu); `library.templateChooser.useTemplate` (the link, for screen readers); the link’s own text `editor.body.placeholder.templateLink` | app | the open entry can be edited, its body has no text or pictures, and an editable template exists (the menu item is dimmed, not hidden, otherwise) | Opens the template chooser for the open entry; a choice fills that entry ([screens/template-chooser](screens/template-chooser.md)). |
| `new-journal` | `common.newJournalEllipsis` | app | library open and unlocked | New Journal alert ([screens/journals](screens/journals.md)). On a computer leaves Editor Only. |
| `pin-entry` | `library.entryActions.pin` / `library.entryActions.unpin` | entry | the open entry can be pinned (in a journal in use, pinning available) | Pins or unpins the open entry. Undo `library.entryActions.pinUndo`; announced `messages.announce.pinned` / `messages.announce.unpinned`; failure `messages.generic.pinFailed` / `messages.generic.unpinFailed`. |
| `import-archive` | `common.importArchive` | app | unlocked | File picker for an archive, then the import sheet ([flows/import-archive](flows/import-archive.md)). |
| `export-archive` | `common.exportArchive` | app | library open, unlocked, no export running | Export Archive sheet ([flows/export-archive](flows/export-archive.md)). |
| `export-markdown` | `library.menu.file.exportMarkdown` (menu); `settings.backup.exportMarkdown` (Settings button) | app | library open, unlocked, not preparing | Export as Markdown sheet ([flows/export-markdown](flows/export-markdown.md)). The two labels differ ([open-questions](open-questions.md), copy inconsistencies). |
| `delete-all-recently-deleted` | `library.menu.file.deleteAll` (menu); `library.recentlyDeleted.deleteAll` (button “Delete All…”) | app | Recently Deleted shown in the front window, with rows, no search, no Delete All running, unlocked, not being replaced | Delete All ([screens/recently-deleted](screens/recently-deleted.md#delete-all)). |
| `close-window` | system | system | a window is in front | Closes the window after saving the open entry; Keep Open alert if it can't. |
| `undo`, `redo` | system, with action names `library.entryActions.deleteEntry`, `library.entryActions.deleteTemplate`, `library.entryActions.pinUndo`, `library.entryActions.unpin`, `library.journals.undoMove` and the editor's step names `editor.undo.*` | app | something to undo | Undoes Delete Entry/Template, Pin/Unpin Entry, Move Journal and editor changes (rules U-1 to U-8 in [flows/editing-rules](flows/editing-rules.md)). In a table cell, undo and redo act on the entry. |
| `edit-text` | system | text | text focus | System text commands. Rules PA-1 to PA-15 (Paste and Match Style: PA-10), E-4 and B-9 in [flows/editing-rules](flows/editing-rules.md); a single selected picture: [flows/image-actions](flows/image-actions.md). |
| `paste-and-match-style` | system | text | text focus | Pastes text without the source's formatting (PA-10 in [flows/editing-rules](flows/editing-rules.md)). |
| `find` | system | text | the editor has focus | Find in the open entry (V-3 in [flows/editing-rules](flows/editing-rules.md)). |
| `search-entries` | `library.menu.edit.searchEntries` | app | library open, unlocked | Focuses the list's search ([screens/search](screens/search.md)). |
| `text-editing-system` | system | text | text focus | System. Prose follows these settings; code and source stay literal (SP-1, SP-2). |
| `format-*` | `library.menu.format.*` | text | the open entry can be edited; see Editor ▸ Format and Table | Each Format command has its own id under [Editor](#editor). The Format menu is disabled while the open item can't be edited. |
| `toggle-sidebar` | system | app | the window has columns | Shows or hides the sidebar; from Editor Only shows every column. |
| `toggle-toolbar` | system | system | always | System. |
| `show-editor-only` | `library.menu.view.showEditorOnly` / `library.menu.view.showSidebarAndList`; toolbar toggle `library.toolbar.editorOnly` (help `library.toolbar.editorOnly.help` / `library.toolbar.editorOnly.helpActive`) | app | a library window is in front | Hides or shows the sidebar and list together ([screens/library-window](screens/library-window.md)). |
| `previous-entry` | `library.menu.view.previousEntry` | app | a library window is in front and there is an item above (or nothing is open) | Opens the item above in the list ([screens/library-window](screens/library-window.md)). |
| `next-entry` | `library.menu.view.nextEntry` | app | as above, below | Opens the item below in the list. |
| `view-source` | `library.menu.view.viewSource` / `library.menu.view.viewPreview` | entry | the open item can be edited; View Preview also needs a previewable entry (tooltip `common.previewUnavailable` otherwise) | Switches the editor between formatted text and Markdown source ([flows/source-view](flows/source-view.md), S-1 to S-7). |
| `zoom-in` | `library.menu.view.zoomIn` | entry | below 30 points | Editor text one point larger, up to 30 ([screens/entry-editor](screens/entry-editor.md), Rules). |
| `zoom-out` | `library.menu.view.zoomOut` | entry | above 12 points | One point smaller, down to 12. |
| `actual-size` | `library.menu.view.actualSize` | entry | not at the default size | Back to the default (16 points). |
| `enter-full-screen` | system | system | always | System. |
| `window-*` | system | system | always | System. No window tabs. |
| `help-guide` | `library.menu.help.guide` | app | always | Opens the user guide on the web. |
| `help-support` | `library.menu.help.support` | app | always | Opens SUPPORT.md on the web. |
| `help-privacy` | `common.privacyPolicy` | app | always | Opens PRIVACY.md on the web. |
| `help-source` | `library.menu.help.source` | app | always | Opens the repository. |
| `help-rate` | `common.rateMyJournal` | app | always | Opens the store's review page. |

## Toolbars, context menus and swipes

Entry actions (the Entry Actions “…” menu in the editor, and an entry's row context menu) each first save the open writing; if that fails, nothing happens. Labels and symbols are specified with the entries list ([screens/entry-list](screens/entry-list.md)).

| id | Name (copy key) | Scope | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `choose-collection` | collection names (`library.journals.*`) | list | not in edit mode | Shows that collection's list, saving the open entry first. |
| `journal-actions` | `library.toolbar.journalActions` | list | library open | Menu of the journal actions below: Rename… and Delete Journal…, with New Journal… first on a computer. |
| `rename-journal` | `library.journalActions.rename` | list | journal in use | Rename Journal alert. |
| `delete-journal` | `library.journalActions.deleteJournal` | list | always | Delete Journal alert. |
| `reorder-journal` | `library.journals.undoMove` (Undo name) | list | order readable, unlocked, not being replaced | Moves the journal; announced; undoable. |
| `journals-edit` | `library.toolbar.edit` / `common.done` | list | journals in use, unlocked, not being replaced | Enters or leaves edit mode. |
| `new-journal-context` | `common.newJournalEllipsis` | list | library open | New Journal alert. |
| `entry-actions` | `library.toolbar.entryActions` | entry | an entry or template is open | Menu of the entry actions below. |
| `find-in-entry` | `library.entryActions.findInEntry` | text | an entry is open | The system's find in the entry. |
| `pin-entry-row` | `library.entryList.swipe.pin` / `library.entryList.swipe.unpin`; menu `library.entryActions.pin` / `.unpin` | list | entry in a journal in use, pins readable, unlocked | Pins or unpins without changing the selection. |
| `review-changes` | `common.reviewChanges` | entry | unlocked (the entry or template has changes to review: the notice, and the rows of Settings ▸ Sync ▸ Changes to Review) | Saves the open writing, then opens the review of that entry or template ([screens/conflict-review](screens/conflict-review.md), [screens/entry-conflict](screens/entry-conflict.md)). |
| `change-date` | `library.entryActions.changeDate` | entry | entry editable in a journal in use | Change Date sheet ([screens/change-date](screens/change-date.md)). |
| `move-entry` | `library.entryActions.moveEntry` | entry | same | Move Entry sheet ([screens/move-entry](screens/move-entry.md)). |
| `save-as-template` | `library.entryActions.saveAsTemplate` | entry | same | Save as Template alert ([screens/entry-list](screens/entry-list.md)). |
| `image-descriptions` | `library.entryActions.imageDescriptions` | entry | the item has pictures (shown) and descriptions can be edited (enabled) | [screens/image-description](screens/image-description.md). |
| `entry-version-history` | `common.versionHistoryEllipsis` | entry | always | [screens/version-history](screens/version-history.md). |
| `restore` | `common.restore` / `library.recentlyDeleted.restoreTo` (context menu, Entry Actions, notice; leading swipe only as `common.restore`) | list | an entry in Recently Deleted or Unavailable Journals that is editable and has no held conflict, and a destination exists: its own journal in use, else the Default Journal; a template in Recently Deleted that is editable | Restores at once, without a sheet. An entry goes back to its own journal when it is in use, else to the Default Journal, and the label names that journal ([flows/delete-and-restore](flows/delete-and-restore.md), Restore). |
| `restore-journal` | `library.recentlyDeleted.restoreJournal` | list | journal editable, not being replaced | Restores the journal at once, without a sheet ([flows/delete-and-restore](flows/delete-and-restore.md), Restore). |
| `try-syncing-again` | `common.trySyncingAgain` | list | journal missing, library syncs | Syncs now, retrying refused items. |
| `delete-permanently` | `library.entryActions.deletePermanently` (context menu, Entry Actions, deleted journal's detail) | list | in Recently Deleted, not being replaced | Delete Permanently alert. |
| `delete-entry` | `library.entryActions.deleteEntry` / `library.entryActions.deleteTemplate`; swipe `common.delete` | list | item editable and not deleted (menus: in a journal in use or a template) | Moves it to Recently Deleted at once; Undo brings it back. |
| `clear-search` | `library.entryList.empty.clearSearch` | list | a search is active | Empties the search. |
| `empty-new-entry` | `library.menu.file.newEntry` | list | New Entry possible | As `new-entry`. |
| `finish-editing` | `common.done` | text | the title, body or a cell has keyboard focus | Ends typing, finishes the save and returns to reading. |
| `sync-status` | `messages.syncStatus.title` | app | sync needs the person | screens/sync-status. |

## Editor

Commands that act on the open entry or template. View, Edit and Entry Actions commands are defined in the sections above (`view-source`, `zoom-in`, `undo`, `find`, `pin-entry`, `change-date`, …). Behaviour is specified in [screens/entry-editor](screens/entry-editor.md), [screens/format-sheet](screens/format-sheet.md) and the rule IDs of [flows/editing-rules](flows/editing-rules.md). The Format, View and Edit menu labels are `library.menu.*`.

**Editable** = the entry or template can be edited ([screens/entry-editor](screens/entry-editor.md), Rules). The whole Format menu is disabled when the open item isn't editable, and (since build 18) while neither the body nor a table cell has keyboard focus, so a command never looks available and does nothing.

### Format

| id | Label | Enabled | Rules |
| --- | --- | --- | --- |
| `show-formatting` | `library.toolbar.formatting` | Editable | format-sheet |
| `format-bold` | `library.menu.format.bold` | Editable, not in code | F-1, F-2, F-4, F-6 |
| `format-italic` | `library.menu.format.italic` | same | F-1, F-4 |
| `format-underline` | `library.menu.format.underline` | same | F-1, F-4 |
| `format-strikethrough` | `library.menu.format.strikethrough` | same | F-1, F-4 |
| `format-inline-code` | `library.menu.format.inlineCode` | same | F-1, F-4, F-7 |
| `format-paragraph` | `library.menu.format.paragraph` | Editable; Formatting: not in a cell or code | P-1 to P-6 |
| `format-heading-1` … `format-heading-6` | `library.menu.format.heading` (1–6) | same | P-1 to P-6 |
| `format-bulleted-list` | `library.menu.format.bulletedList` | same | P-1 to P-6 |
| `format-numbered-list` | `library.menu.format.numberedList` | same | P-1 to P-6 |
| `format-checklist` | `library.menu.format.checklist` | same | P-1 to P-6 |
| `format-mark-checked` | `library.menu.format.markChecked` / `library.menu.format.markUnchecked` | Caret in a checklist item (menu, not in source view) | C-1, C-2 |
| `format-block-quote` | `library.menu.format.blockQuote` | Editable; Formatting: not in a cell or code | P-1 to P-6 |
| `format-increase-indent` | `library.menu.format.increaseIndent` | Per I-1 to I-3, I-10, I-11, I-15 | I-1 to I-15 |
| `format-decrease-indent` | `library.menu.format.decreaseIndent` | Per I-4, I-10, I-11, I-15 | I-4 to I-15 |
| `insert-code-block` | `library.menu.format.insert.codeBlock` | Editable | BI-1, BI-2, K-2 |
| `insert-table` | `library.menu.format.insert.table` | Editable | BI-1, BI-3 |
| `insert-horizontal-rule` | `library.menu.format.insert.horizontalRule` | Editable | BI-1, BI-2, K-2 |
| `insert-link` | `library.menu.format.insert.link` (Add Link…) / `library.menu.format.insert.editLink` (Edit Link…, while the caret or selection is in one link) | Editable and the body has focus (in a table cell it adds a link but never edits one) | `screens/link-editor.md`, L-1 to L-10 |
| `remove-link` | `library.menu.format.insert.removeLink` | Editable, the body has focus and the caret or selection touches a link (never in a table cell) | `screens/link-editor.md`, L-8 to L-10 |
| `insert-image` | `library.menu.format.insert.image` | Editable | `flows/insert-image.md` |
| `exit-code-block` | `editor.format.exitCodeBlock` | Caret in a code block | BI-4 |

Format menu order (computer, tablet): Bold, Italic, Underline, Strikethrough, Inline Code, —, Paragraph, Heading 1–6, —, Bulleted List, Numbered List, Checklist, Mark as Checked/Unchecked, Block Quote, —, Increase Indent, Decrease Indent, —, Insert ▸ (Code Block, Table, Horizontal Rule, —, Add Link… or Edit Link…, Remove Link, Image…), then Table ▸ (computer and tablet; the phone has no menu bar, so its cell edit menu is the route).

### Table

The table commands are one list in one order on every device: Add Row Below, Add Column After, Alignment ▸ (Left, Center, Right), a divider, Delete Row, Delete Column, Delete Table. The list is the same in the cell menu, in Format ▸ Table (computer and tablet) and in the phone's and tablet's cell edit menu, and is not offered for a read-only entry.

| id | Label | Enabled | Rules |
| --- | --- | --- | --- |
| `table-add-row` | `library.menu.format.table.addRow` | A cell is being edited, editable | TB-4 |
| `table-add-column` | `library.menu.format.table.addColumn` | same | TB-4 |
| `table-align-left` / `table-align-center` / `table-align-right` | `editor.table.alignment` ▸ `editor.table.alignment.left`, `editor.table.alignment.center`, `editor.table.alignment.right` (everywhere; the column's current alignment is checked) | same | TB-4 |
| `table-delete-row` | `library.menu.format.table.deleteRow` | same | TB-4 |
| `table-delete-column` | `library.menu.format.table.deleteColumn` | same | TB-4 |
| `table-delete-table` | `library.menu.format.table.deleteTable` | same | TB-4 |
| `table-next-cell` / `table-previous-cell` | — | In a cell | TB-3 |
| `table-cell-below` | — | In a cell | N-15, TB-3 |

### Editor-only controls

| id | Label | Enabled | Result |
| --- | --- | --- | --- |
| `insert-image-choose-file` | `library.toolbar.insertImage` | Editable | `flows/insert-image.md` |
| `insert-image-photo-library` | `editor.insertImage.photoLibrary` | Editable | same |
| `insert-image-take-photo` | `editor.insertImage.takePhoto` | Editable | same |
| `toggle-checkbox` | item text; value `editor.list.checked` / `editor.list.unchecked` | Editable | C-3 |
| `image-copy`, `image-cut`, `image-paste`, `image-share`, `image-save-to-photos`, `image-save-as`, `image-delete` | see `flows/image-actions.md` | see flow | IM-5, image-actions |
| `close-formatting` | `editor.format.close` | Formatting shown | format-sheet |

### Keys in the text

Key names are the Apple keyboard's (Return, Delete, Option, Command); a platform maps them to its own, as [platforms/windows/commands.md](platforms/windows/commands.md) does. Which of them each device offers is in [platforms/apple/commands.md](platforms/apple/commands.md#keys-in-the-text).

| Key | Where | Result | Rules |
| --- | --- | --- | --- |
| Return | Item, quote, heading, code, cell, title, `---`/```` ``` ```` line | Continue, split, leave list, new paragraph, new code line, cell below, to body, convert line | N-1 to N-15, T-1, K-2 |
| Backspace (also Option-, Command-Backspace) | Start of an item or quote; straight after a shortcut; across lines | Remove one level; give back typed marker; join lines | B-1 to B-10, K-4 |
| Forward Delete | End of a line | Join lines (B-6); nothing at the end of the last item (E-2) | B-6, E-2 |
| Tab / Shift-Tab | List item, code, cell, paragraph, title | Indent/outdent; tab in code; next/previous cell; tab character; to body (from the title on a phone or tablet) | I-12, I-15, TB-3, T-1 |
| Down Arrow | End of a code block's last line | Leave the code block | BI-4 |
| Space after a marker | Start of a plain paragraph | Markdown shortcut | K-1 |
| Escape | Formatting shown | Close it | format-sheet |
| ⇧⌘Return | Checklist item (where the text view has its own shortcut) | Mark as Checked / Unchecked | C-1 |

## Settings

Every command in Settings and the flows it opens. Commands that live on other surfaces are defined once above and only placed here: `open-settings`, `lock-my-journal` (App Lock section), `import-archive`, `export-archive`, `export-markdown` (Backup), `help-guide`, `review-changes` (Changes to Review). The Settings ▸ About links have their own ids because the Help menu items (`help-privacy`, `help-support`, `help-source`, `help-rate`) are menu-bar commands with the same destinations. The commands in the tables below act in Settings or in a flow it opens (scope: Settings and its dialogs).

### Settings structure

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `settings-open-pane` | `settings.pane.*` | always | Shows General, Sync, Privacy, Backup or Agent Access. |
| `settings-done` | `common.done` | always | Closes Settings. |

### General

| id | Name (copy key) | Location | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `choose-default-journal` | `settings.general.defaultJournal` | Settings ▸ General | at least one journal | Sets where New Entry files entries outside a journal. |
| `toggle-format-as-you-type` | `settings.general.formatAsYouType` | Settings ▸ General | always | Turns Markdown shortcuts at line starts on or off. |

### Sync

| id | Name (copy key) | Location | Enabled when | What it does |
| --- | --- | --- | --- | --- |
| `connect-to-server` | `common.connectToServer` | Settings ▸ Sync, Agent Access (not connected); first-launch screen | unlocked | Opens Connect to a Server (`flows/connect-to-server`). |
| `sync-now` | `messages.sync.action.syncNow` / `common.tryAgain` / `messages.sync.action.checkAgain` | Settings ▸ Sync | connected, unlocked, not replacing the journals, no failed save, no sync the person started running | Syncs once, resending refused items; announces the result. |
| `sync-reconnect` | `common.reconnect` | Settings ▸ Sync (the Server section); Sync Status; Settings ▸ Privacy; Settings ▸ Agent Access (no access) | the sync state calls for it | Opens Reconnect at this server's next step (`flows/reconnect-to-server`). |
| `stop-syncing` | `settings.sync.stopSyncing` | Settings ▸ Sync | connected, not replacing the journals | Confirmation, then `flows/stop-syncing`. |
| `open-setup-guide` | `settings.sync.footer.howToSetUp` (both footers) | Settings ▸ Sync footer; Set Up Server footer | always | Opens the sync guide. |
| `open-former-server-guide` | `settings.sync.footer.learnMore` | Settings ▸ Sync footer (computer only) | after the former Mac server stopped | Opens the guide's section for people who used Use This Mac. |
| `open-kept-note` | the row’s own sentence (`messages.conflict.kept.deletedAndChanged`); hint `messages.conflict.kept.rowHint` | Settings ▸ Sync ▸ Changed on Two Devices | unlocked, and the entry or template the row names still exists | Closes Settings (iPhone, iPad) and shows that entry or template where it is; brings the library window forward (Mac). A row with nothing to open is plain text and has no command. |
| `clear-kept-notes` | `messages.conflict.kept.clear` | Settings ▸ Sync ▸ Changed on Two Devices | unlocked | Forgets every note in the list at once, without confirmation. Entries, templates and journals are untouched. |

### Connect to a Server

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `connect-check-server` | `common.continue`; a nearby server row | address not empty, not checking | Checks the server; goes to the next step. |
| `connect-scan-code` | `settings.connect.scanCode` | a supported camera scanner | Opens Scan Code. |
| `scan-cancel` | `common.cancel` | always | Closes the scanner. |
| `scan-open-settings` | `common.openSettings` | camera access denied | Opens the system's settings for My Journal. |
| `connect-set-up` | `settings.connect.setUp.setUp` / `common.continue` / `common.tryAgain` | fields filled, not working | Validates and sets up the server (`flows/connect-to-server` §3–6). |
| `connect-sign-in` | `settings.connect.signIn.signIn` / `common.connect` / `common.tryAgain` | credential typed, not working | Signs in with the credential or recovery code. |
| `connect-use-device` | `settings.connect.signIn.useDevice` | not working | Pushes Add This Device. |
| `connect-copy-code` | `settings.connect.addThisDevice.copyCode` | a pairing code shown | Copies the nine digits. |
| `connect-confirm-check-code` | `common.connect` | check code shown, not yet confirmed | Accepts the approval after comparing codes. |
| `connect-new-code` | `settings.connect.addThisDevice.getNewCode` | after a pairing failure with nothing received | Withdraws the request and gets a new code. |
| `connect-use-recovery-code` | `settings.connect.addThisDevice.useRecoveryCode` | server without encryption, not installing | Pushes Use a Recovery Code. |
| `connect-merge` | `common.merge` | not working | Agrees to merge with this server; continues. |
| `connect-retry` | `common.tryAgain` / `settings.connect.scanAgain` | after a failure | Tries the same step again, or scans a new code. |
| `connect-cancel` | `common.cancel` | not installing | Stops, withdraws requests, gives up unused access, closes. |
| `connect-done` | `common.done` | Server Is Ready | Closes. |
| `show-connection` | `messages.writingPaused.showConnection` | computer, while connecting from Settings | Opens Settings at Sync and brings the sheet forward. |

### Devices (a section of Settings ▸ Sync)

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `add-device` | `settings.devices.add`; `settings.connect.ready.addDevice` | connected, devices loaded, not busy; the Devices section is absent while access is refused | Opens Add Device (`flows/pair-device`). |
| `revoke-device` | `settings.devices.revoke` | another device; not busy | Confirmation, then revokes. |
| `devices-try-again` | `common.tryAgain` | after a load or revoke error | Retries. |
| `add-device-enter-code` | `settings.addDevice.enterCodeInstead` | showing a code | Switches to typing the new device's code. |
| `add-device-look-up` | `common.continue` | code typed, not busy | Looks up the code. |
| `add-device-new-code` | `settings.addDevice.showNewCode` | session expired | Starts a new session of codes. |
| `add-device-copy-address` | `settings.addDevice.copyAddress` | connected through HTTPS | Copies the server address. |
| `add-device-approve` | `settings.addDevice.approve` / `settings.addDevice.add` | a request is confirmed, not busy | Authenticates the owner, then sends the key. |
| `add-device-cancel` | `common.cancel` / `settings.addDevice.dontAdd` | not while approving | Declines what waits and closes. |
| `add-device-try-again` | `common.tryAgain` | typed code, after an error while waiting | Waits for the new device again. |
| `add-device-done` | `common.done` | finished | Closes. |

### Privacy

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `turn-on-encryption` | `settings.privacy.encryption.turnOn` | journals not encrypted, unlocked, not replacing the journals (except to show a run in progress) | Opens the Encrypt Your Journals form as a sheet with Cancel (`screens/encrypt-journals`, `flows/encrypt-journals`). |
| `encrypt-journals` | `library.encrypt.action` / `common.tryAgain` | the check passed; new password typed twice (and current access password if asked); not working | Encrypts. |
| `encrypt-journals-not-now` | `library.encrypt.notNow` | only where the form can't succeed or has failed (`screens/encrypt-journals`, Exits) | Opens the journals as before this version; the form returns at the next launch. |
| `encrypt-journals-stop-syncing` | `settings.sync.stopSyncing` | no access, server too old, access password wrong or limited; also on the unfinished notice | Confirmation, then stops syncing and encrypts locally; on the unfinished notice adopts the encrypted copy (`flows/stop-syncing`). |
| `encryption-finish` | `common.tryAgain` | unfinished | Finishes after the server switched. |
| `encryption-cancel` | `common.cancel` | the working notice, before the server is updated; the form as a sheet, always | Notice: stops the work, nothing changes, shows the plain form again. Sheet: closes it. |
| `encryption-done` | `common.done` | encrypted | Closes the Done sheet. |
| `change-password` | `settings.privacy.changePassword` (Settings ▸ Privacy); `settings.backup.archive.changePassword` (the pointer under the archive footer) | master-password journals, unlocked | Opens Change Password (`flows/change-password`). |
| `change-password-submit` | `settings.changePassword.change` | all fields filled, new matches confirm | Changes the password. |
| `change-password-retry` | `common.tryAgain` | the server changed, this device didn't save | Saves on this device again. |
| `change-password-cancel` | `common.cancel` | not working; while a local save is pending, only after Try Again failed | Closes without changing anything. |
| `forgot-password` | `settings.changePassword.forgot` | in the Change Password sheet: journals only on this device, not being replaced, unlocked, owner authentication available; not working | Authenticates the owner (`settings.changePassword.authReason`), then replaces the Current Password section with the forgot form (`flows/change-password`). |
| `toggle-app-lock` | `settings.privacy.appLock.require` | not while asking; on needs authentication available | Authenticates, then turns App Lock on or off (`flows/app-lock`). |
| `set-inactivity-lock` | `settings.privacy.appLock.inactive` | computer, App Lock on | Sets Lock when inactive; longer or Never authenticates first. |
| `unlock-with-device` | `settings.lock.unlockWith` | locked, not asking | Asks the system to authenticate. |
| `use-credential` | `settings.lock.useCredential` | after a failed unlock, journals with a password | Shows the password field. |
| `unlock-with-credential` | `settings.lock.unlock` | field not empty | Unlocks with the password or recovery key. |
| `use-device-unlock` | `settings.lock.useMethod` | credential form, device key present | Back to device unlock. |
| `copy-recovery-key` | `settings.recoveryKey.copy` | early library, key not confirmed | Copies the key (cleared after two minutes). |
| `save-recovery-key` | `settings.recoveryKey.save` | early library, key not confirmed | Saves the key as a text file. |
| `confirm-recovery-key` | `common.continue` | switch on and last group typed | Confirms and shows the journals. |

### Backup

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `archive-open` | `common.continue` | password typed (or none needed), not busy | Opens and previews the archive. |
| `archive-import` | `settings.archiveImport.restore` / `settings.archiveImport.importAsNew` | previewed, not busy | Imports. |
| `archive-import-cancel` | `common.cancel` | not importing | Discards and closes. |
| `archive-import-done` | `common.done` | imported | Closes. |
| `export-sheet-done` | `common.done` | always | Closes the export sheet opened from the menu. |

### Erase

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `erase-device` | `settings.erase.button` | a library exists and nothing else is changing it | Counts what would be lost; warning (`flows/erase`). |
| `erase-confirm` | `settings.erase.alert.erase` (destructive, in the warning) | — | Authenticates (App Lock on) and erases. |

### Library problem

The commands of the screen that replaces the library when it can't be opened ([screens/unavailable-content](screens/unavailable-content.md)). `import-archive` and `erase-device`'s warning are the same commands as elsewhere; `erase-unopened` is its own command because it reads nothing and has its own warning ([flows/erase](flows/erase.md)).

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `retry-opening` | `common.tryAgain` | the problem is not a newer version; not already trying | Reads the settings and opens the library again from the start. A tap that ends in a problem again counts once towards offering `erase-unopened`. |
| `erase-unopened` | `settings.erase.button` | on the library problem screen: after one failed `retry-opening` (not for a newer version) and while the phone's or tablet's protected data is available; on the lock screen of a missing device key: at once | Authenticates when App Lock is on or can't be known, then the warning `settings.erase.alert.unopened`; Erase removes everything the app stored ([flows/erase](flows/erase.md)). |
| `open-library-guide` | `library.problem.learnMore` | always on the screen | Opens the troubleshooting guide on the web. |

### Agent Access

| id | Name (copy key) | Enabled when | What it does |
| --- | --- | --- | --- |
| `copy-mcp-address` | `common.copy` | address shown | Copies the MCP server address. |
| `share-mcp-address` | `common.share` | phone or tablet, address shown | Share sheet. |
| `open-agent-guide` | `settings.agents.connect.guide` | always | Opens the agent guide. |
| `agents-try-again` | `common.tryAgain` | server unreachable | Loads again. |
| `review-agent-request` | (the request row) | a request waits | Opens Allow Access. |
| `allow-agent` | `settings.allowAgent.allow` | two digits, journals chosen (new agent), under the limit | Allows (`flows/allow-agent`). |
| `decline-agent` | `settings.allowAgent.dontAllow` | not allowing | Declines. |
| `open-agent` | (the agent row) | agents listed | Opens the agent's detail. |
| `rename-agent` | `common.name` | access not ended, settings readable | Renames. |
| `change-agent-journals` | `settings.agents.allJournals` / `settings.agents.selectedJournals` and journal switches | access not ended, settings readable | Changes the journals (saved after 0.5 s). |
| `change-agent-expiry` | `settings.agentDetail.ends` | access not ended, settings readable | Sets when access ends. |
| `revoke-agent` | `common.revokeAccess` / `settings.agentDetail.remove` | not working | Revokes (confirmation unless ended). |
| `agent-detail-done` | `common.done` | not revoking | Closes the agent's detail (a sheet on a computer). |

### About and Help

| id | Name (copy key) | Location | What it does |
| --- | --- | --- | --- |
| `about-privacy-policy` | `common.privacyPolicy` | Settings ▸ About; Help menu as `help-privacy` | Opens PRIVACY.md. |
| `about-support` | `settings.about.support` | Settings ▸ About; Help menu as `help-support` | Opens SUPPORT.md. |
| `about-source-code` | `settings.about.sourceCode` | Settings ▸ About; Help menu as `help-source` | Opens the repository. |
| `about-rate` | `common.rateMyJournal` | Settings ▸ About; Help menu as `help-rate` | Opens the store's review page. |
