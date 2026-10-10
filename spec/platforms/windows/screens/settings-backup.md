---
id: settings-backup
title: Settings ▸ Backup and the export dialogs (Windows)
spec: screens/settings-backup.md
features: [export-archive, import-archive, export-markdown, change-password]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers
  - https://learn.microsoft.com/en-us/windows/apps/develop/files/pickers-save-file
  - https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
---

# Settings ▸ Backup and the export dialogs (Windows)

Archive export and import, Markdown export, and the two File-menu dialogs. Behaviour and copy keys are the spec's [Settings ▸ Backup](../../../screens/settings-backup.md); the steps of each export are the flows [export-archive](../../../flows/export-archive.md) and [export-markdown](../../../flows/export-markdown.md). The shell and patterns are in [settings](settings.md#card-patterns); picker rules are [platform.md, 16](../platform.md#16-files-and-pickers).

**What this page decides about pickers.** The archive is one file ([protocol/archive.md](../../../../protocol/archive.md)), so this page maps the file route: `FileSavePicker` and `FileOpenPicker`. Only the Markdown export, which is many files, uses a folder picker. Everything else on the page is independent of that.

## Controls

Page title: breadcrumb "Settings > Backup".

### Archive group

Header `settings.backup.archive.header`.

| Spec element | Control | Notes |
| --- | --- | --- |
| Export Archive… | An [action card](settings.md#card-patterns), `Header` `common.exportArchive`, icon Export (EDE1), a standard `Button` `common.exportArchive` in its content. `Description`: while the library exists only on this PC (not syncing), the date of the last export ("Last exported {date}") or "Not exported yet" (D22, new copy), so an uninstall that removes the local data is never a surprise. Trailing a small indeterminate `ProgressBar` (about 80 epx) with `AutomationProperties.Name` `settings.backup.preparingArchive`, shown after 0.3 seconds; the card keeps its size | Pressing again while preparing, or while the picker is open, does nothing. The date is a device-only local setting written when an export completes |
| Saved message | After a save, in the Export row's description in place of the last-export line until the next export starts: `messages.export.archiveSaved` (credential in lower case), announced with a notification event (`MostRecent`) when it appears | Every library is encrypted, so it always shows |
| Error line | An `InfoBar` (Error) under the card, `Content` a selectable `TextBlock`; cleared when the next export starts | The messages are the export flow's (`messages.export.archiveFailed`, `messages.export.archiveNoSpace`, `messages.export.archiveSaveFailed`, `messages.save.before.goBack`) |
| Import Archive… | An action card, `Header` `common.importArchive`, icon Import (E8B5), a standard `Button` `common.importArchive` | Opens the picker, then the Import archive task page ([archive-import](archive-import.md)) |
| Footer | A `TextBlock` (Caption) under the group: `settings.backup.archive.footerEncrypted` with the credential in lower case | |
| Change Password pointer | A `HyperlinkButton` under the footer, `settings.backup.archive.changePassword`, opening the [Change Password](change-password.md) dialog | There is no password check before exporting; typing the current password in Change Password is the check, and the dialog's Forgot password? link resets a forgotten one when the journals exist only on this PC |

### Markdown group

Header `settings.backup.markdown.header`.

| Spec element | Control | Notes |
| --- | --- | --- |
| Export as Markdown… | An action card, `Header` `settings.backup.exportMarkdown`, icon Export, a standard `Button` with that label. A small indeterminate `ProgressBar` named `settings.backup.preparingFiles` after 0.3 seconds | Disabled while preparing or without a library |
| Error line | An `InfoBar` (Error), as above | `messages.export.markdownFailed`, `messages.export.markdownNoSpace`, `messages.export.markdownSaveFailed`, `messages.save.before.goBack` |
| Note after a save that left something out | An `InfoBar` (Informational), not closable, `Content` the spec's sentences joined with a space (`settings.backup.markdownNote.imagesNotDownloaded`, `settings.backup.markdownNote.imagesUnreadable`, `settings.backup.markdownNote.itemsUnreadable`, `settings.backup.markdownNote.otherVersions`); cleared when the next export starts | Announced when it opens |
| Footer | `settings.backup.markdown.footer` | |

### File menu dialogs

File ▸ Export archive… and File ▸ Export journals as Markdown… open a `ContentDialog` ([Dialog patterns](settings.md#dialog-patterns)): `Title` `settings.backup.exportArchiveSheet.title` or `settings.backup.exportMarkdownSheet.title`; content the same action card, a progress ring (the dialog is modal, so the app is blocked on it), saved message, error bar, note bar, footer and Change Password pointer as the page; Close button `common.done` (Esc closes a dialog). The dialog stays open while the picker is up and closes when the window locks (nothing is left in the temporary folder: [below](#temporary-files)). The Erase dialog's Export archive… button closes that dialog and opens this one ([settings-erase](settings-erase.md)); it does not nest.

**The Change Password pointer from the dialog.** Choosing it in the File-menu dialog replaces the dialog's content with the Change Password dialog's content (a swap, [Dialog patterns, 1](settings.md#dialog-patterns)); when it closes the export dialog's content returns. From the Backup page it opens the dialog over the page.

## The pickers

| Task | Picker | Details |
| --- | --- | --- |
| Export archive (one file) | `FileSavePicker` of the Windows App SDK (`Microsoft.Windows.Storage.Pickers`, created with the library window's `WindowId`), `SuggestedFileName` `settings.backup.archiveFilename`, one file type choice "My Journal archive" (`.journalarchive`), `SuggestedStartLocation` Documents | The system's own Save button; the picker asks before replacing. It creates an empty file and the app writes into it; if the write fails or is cancelled, the empty or partial file the app created is removed. The suggested name's date is the fixed form `yyyy-MM-dd` in the Gregorian calendar with digits 0 to 9, not the regional format ([platform.md, 31](../platform.md#31-dates-time-zones-and-formats)) |
| Export as Markdown | `FolderPicker`; the app creates `settings.backup.markdownFolderName` inside the chosen folder, adding " (2)", " (3)"… when the name exists and never replacing or merging | The picker's commit button is the Windows-only string of B36 ("Save here"). The file names inside the folder follow the export mapping's Windows-safe rules (platform.md, 16) |
| Import archive (one file) | `FileOpenPicker` filtered to `.journalarchive`, start in Documents | The system's own Open button. A file that is not an archive, or whose manifest and hashes do not match, reaches the import page's own error (`settings.archiveImport.error.damaged`) |

Rules for all of them: the picker is created with the window's `WindowId` (Windows App SDK 1.8 or later; earlier versions use `InitializeWithWindow`), which also works if the app were ever elevated. The app reads and writes only what was picked ([platform.md, 16](../platform.md#16-files-and-pickers)). Names the app proposes (`settings.backup.archiveFilename`, `settings.backup.markdownFolderName`) contain none of the characters Windows forbids in a name (`< > : " / \ | ? *`) or any reserved device name, and do not end in a dot or space; the date in them is why they are fixed text. A picker result is checked for being writable before the work starts; a path that is too long, read-only or on a disconnected drive shows the flow's save-failed message, not a system exception. A cancelled picker is not an error and says nothing.

**Where the export lands.** The picker starts in Documents and the person chooses where the export goes, including a folder that a cloud client such as OneDrive syncs. The app does not warn about that: where an export is saved, and what a sync client then does with it, is the person's decision and risk ([platform.md, 16](../platform.md#16-files-and-pickers)). The footers already say the files are not encrypted.

### Temporary files

The export is prepared in a new folder under the app's temporary folder, deleted when the picker has finished, when the export is cancelled, when the window locks, and at the next launch (matching only its own names). A copy is never left in the Documents or a synced folder. LF line endings and the other file rules are the export mapping's.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Two groups of action cards in the column; footers below each group | Mac Backup tab |
| Small and text size 200% or more | The same; the progress bar sits after the card text | iPhone pushed pane |
| The dialogs | 548 epx wide, scrolling | Mac sheets |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `export-archive` | The button in the action card; File menu | — | Library open; not while one is being prepared or saved |
| `import-archive` | The button in the action card; File menu | — | Unlocked |
| `export-markdown` | The button in the action card; File menu | — | Library open and unlocked; not while preparing |
| `change-password` | The pointer under the archive footer | — | Unlocked |
| `export-sheet-done` | Close button of the File menu dialogs | `Esc` | Always |

Exports ask Windows Hello first for Markdown when App Lock is on (`settings.backup.markdownReason`) through [the authentication gate](settings.md#the-authentication-gate); if it is cancelled nothing happens and nothing is said; a PC without Hello continues. The archive export asks nothing (open-questions D2).

Rules kept from the spec: one export of each kind at a time; leaving the page while preparing cancels the export, while the picker is open it stays; the inactivity timer is held while an export is prepared ([flows/app-lock](../flows/app-lock.md)).

## Copy differences

Sentence case applies ("Export archive…", "Export as Markdown…", "Archive", "Preparing archive…"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.backup.openFailed` | Couldn’t Open Archive | Couldn’t open archive | casing (the title is kept: it names the failure) |
| `settings.backup.markdownReason` | {"default": "Export your journals as files that aren’t encrypted", "mac": …} | The default form | vocabulary (platform.md, 12.3) |
| The last-export line: "Last exported {date}" and "Not exported yet" | none | In [copy-proposals.md](../copy-proposals.md) | new, D22 |
| Where an instruction names a menu path | Settings > Backup | unchanged | none needed |

## Accessibility

- The progress bars are named `settings.backup.preparingArchive` and `settings.backup.preparingFiles`. Errors and notes are announced when their bar opens; the note is read after the error if both exist.
- Focus returns to the action card after a picker closes, an error appears or the dialog closes; the error bar is not a tab stop (its text is selectable by keyboard when focused through the card's description).
- The pickers are the system's and accessible by themselves.
- The progress bar shows only after 0.3 seconds so a quick export causes no announcement.

## Different by design

- **The archive is one file with the Open and Save pickers**: Apple saves it with a document exporter; a Windows picker saves a file the same way. The Markdown export, which is many files, uses a folder picker.
- **A dialog for the File-menu exports.** Apple shows a sheet on the journal window; the Windows dialog is the same size of task and gives the progress, error and note somewhere to show without opening Settings.
- **A last-export line** while the library exists only on this PC, because uninstalling the package removes its local data (D22).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D22 (uninstall and last export), B36 (folder picker strings for Markdown).
