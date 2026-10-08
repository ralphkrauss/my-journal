---
id: export-markdown
title: Export journals as Markdown (Windows)
spec: flows/export-markdown.md
features: [export-markdown]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.storage.pickers
  - https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
  - https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
---

# Export journals as Markdown (Windows)

Saves every journal as Markdown files, with their images, in a folder other apps can open. It is not a backup and cannot be imported. Steps, errors, the note after saving and the rules are the spec's [export-markdown](../../../flows/export-markdown.md); the folder's format, including how names are made safe, is the shared contract [protocol/markdown-export.md](../../../../protocol/markdown-export.md).

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Entry points | The Backup page's Export as Markdown… button (`settings.backup.exportMarkdown`); File ▸ Export journals as Markdown… (`library.menu.file.exportMarkdown`); for the File route a small `ContentDialog` titled `settings.backup.exportMarkdownSheet.title`, as in [export-archive](export-archive.md) | |
| 2. Owner check when App Lock is on | Windows Hello through `UserConsentVerifierInterop.RequestVerificationForWindowAsync` with the window's handle ([13](../platform.md#13-device-authentication-and-app-lock)); the message is `settings.backup.markdownReason` for encrypted journals or `settings.backup.markdownReasonUnencrypted` otherwise, in the default (capitalised) form, because Windows shows it as a sentence | Cancelled or failed: nothing happens and nothing is said. The Windows Security prompt is not a `ContentDialog`; a lock cancels it. Not asked when App Lock is off |
| 3. Preparing | The open entry is saved first (`messages.save.before.exportMarkdown`); the files are written to a temporary folder in the app's local data, never in Documents or any synced folder. After 0.3 seconds a small indeterminate `ProgressBar` with `settings.backup.preparingFiles` shows beside the button (a `ProgressRing` in the File-route dialog, which is modal) | |
| 4. The folder | A `FolderPicker` (the Windows App SDK picker with the window's id), started in Documents; the person picks where the export goes and the app creates the folder named `settings.backup.markdownFolderName` (`{date}` in the fixed `yyyy-MM-dd` form) inside it. If that name exists there, " (2)", " (3)"… is added, as Explorer does; an existing folder is never written into or replaced | The picker's commit button is a Windows-only string (B36); the spec's save dialog suggests the folder's name, which a folder picker cannot. Any folder the person can pick is accepted, including one a cloud client such as OneDrive syncs; the app does not warn about that (owner decision, 2026-10-07) |
| Saved | If something was left out, an Informational `InfoBar` under the button (or in the dialog) with the spec's sentences, in order, each only when it applies, joined with a space: `settings.backup.markdownNote.imagesNotDownloaded`, `settings.backup.markdownNote.imagesUnreadable`, `settings.backup.markdownNote.itemsUnreadable`, `settings.backup.markdownNote.otherVersions` (all plural). Announced when it opens | Not closable until the next export or leaving the page |
| Cancelled | Nothing; the temporary folder is removed | |
| Errors | An Error `InfoBar` in the same place, selectable, announced: `messages.save.before.exportMarkdown`, `messages.export.markdownNoSpace`, `messages.export.markdownFailed`, `messages.export.markdownSaveFailed` | The File-route dialog stays open while the picker is up, so a save failure shows in its own bar |
| 5. The temporary folder | Removed when the picker closes; leftovers are removed at the next launch, matching only their own names | |

Rules of the spec kept: one Markdown export at a time; locking cancels; the files are not encrypted whatever the journals are, and the Backup page's footer says so for encrypted journals.

### Windows file names

The protocol makes every folder and file name safe on all systems, and its steps already cover what Windows forbids ([16](../platform.md#16-files-and-pickers)): `< > : " / \ | ? *` and control characters become `-`; leading dots, and trailing dots and spaces, are trimmed; a name whose first part is a device name (`CON`, `PRN`, `AUX`, `NUL`, `COM1` to `COM9` and the superscript forms, `LPT1` to `LPT9`, in any case) gets a `-` before the first dot; names are at most 60 characters and 120 bytes; names that differ only by case or Unicode form are numbered, which is right for NTFS, where names are case-insensitive. The Windows mapping adds no second naming rule: the same library gives the same folder names on every platform. What Windows adds is checking:

- **The app writes with the long-path form** of each path. A path the file system or an antivirus product still refuses is a save failure, `messages.export.markdownSaveFailed`; the shortest picked folder plus the 27-character folder name, a journal folder, `attachments` and a file name can pass 260 characters, and the OneDrive client has its own, shorter limit.
- **Tests** that belong to the shared export code and run on Windows: each forbidden character; each device name with and without an extension and in upper and lower case; trailing dot and trailing space; a name of 60 characters made of multi-byte characters; two titles that differ only by case; and a full export written under a path longer than 260 characters.
- **No warning about synced folders.** Documents is often redirected to OneDrive, which then uploads the files as they are written. The footer already says the files are not encrypted; the app adds no dialog or note about OneDrive or any other synced folder, and the risk is the person's (owner decision, 2026-10-07).

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Progress and bars are beside and under the button on the Backup page ([settings-backup](../../../screens/settings-backup.md)) | Backup pane; the File-menu sheet |
| Small | The progress bar and text wrap under the button; bars fill the width | iPhone |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `export-markdown` | File ▸ Export journals as Markdown…; Settings ▸ Backup (button) | as in commands.md | Unlocked and no export is running |
| `export-sheet-done` | The File-route dialog's Close button | Esc | Always |

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Export as Markdown…", "Export journals as Markdown…", "Preparing files…"; "Markdown" keeps its capital. The reasons use the default capitalised form ([12.3](../platform.md#123-vocabulary)), not the Mac's lower-case variant. `settings.backup.markdownFolderName` is unchanged on every platform. The picker's commit button is a new string (B36).

## Accessibility

- The progress bar is hidden from the tree; its text is the label. Errors and the note are bars that announce themselves when they open, so nothing is spoken twice.
- The Windows Security prompt is read by Narrator itself; the app adds nothing.
- Focus returns to the Export as Markdown button when the picker closes. Everything works with the keyboard, and the bars wrap at 225% text size.

## Different by design

- **A folder picker creating a named folder inside**, where the Apple save dialog suggests the folder's name.
- **Windows Hello** takes the place of the device passcode prompt.
- **Long-path writing and file-system tests** for Windows' length and naming limits; the names themselves do not change.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B36 (picker strings).
