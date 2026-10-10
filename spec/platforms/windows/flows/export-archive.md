---
id: export-archive
title: Export an archive (Windows)
spec: flows/export-archive.md
features: [export-archive, change-password]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.storage.pickers
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
---

# Export an archive (Windows)

Saves everything needed to bring the journals back: entries, journals, templates, Recently deleted, images and earlier versions, encrypted with the journals' password. Steps, errors and rules are the spec's [export-archive](../../../flows/export-archive.md). The archive is one file, the file archive of [protocol/archive.md](../../../../protocol/archive.md), so the picker is a save picker: see [import-archive](import-archive.md), "What an archive is on Windows".

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Entry points | The Backup page's Export archive… button; File ▸ Export archive…; the warning dialog of Erase, which closes first and then starts the export ([erase](../../../flows/erase.md)) | |
| 2. Preparing | The open entry is saved first (`messages.save.before.goBack`); the archive is written to a temporary file in the app's local data, after checking that the volume has the database, the images and 256 MiB free (`messages.export.archiveNoSpace` otherwise), with `System.IO.Compression.ZipArchive` in `Create` mode over a seekable stream and the profile of the protocol (entry times set to 1980-01-01, `journal.sqlite` first, `archive.json` last). After 0.3 seconds a small indeterminate `ProgressBar` with `settings.backup.preparingArchive` shows beside the Export archive button on the Backup page (the page stays usable); for the File menu route a small `ContentDialog` titled `settings.backup.exportArchiveSheet.title` shows a `ProgressRing` and the text (the dialog is modal), with Close `common.done` | The File-menu dialog is the spec's export sheet: it stays open while the picker is up, as the spec says, and the picker is the window's own (a system dialog over the app window, which a `ContentDialog` behind it does not prevent) |
| 3. The picker | A `FileSavePicker` (the Windows App SDK picker with the window's id), started in Documents, `SuggestedFileName` `settings.backup.archiveFilename` with `{date}` in the fixed `yyyy-MM-dd` form of the spec (Gregorian, digits 0 to 9), one file type choice "My Journal archive" (`.journalarchive`). The system's Save button and its own replace prompt are used; nothing is overwritten without that prompt. The picker creates an empty file and the app writes the archive into it; if the write fails or is cancelled the empty or partial file the app created is removed | No Windows-only strings: the system supplies the button |
| Saved | `messages.export.archiveSaved` (the credential in lower case) shows in the Export row of the Backup page, or in the File-menu dialog's Export row, until the next export starts, and is announced with a notification event (`MostRecent`) when it appears | Not an `InfoBar`: it is the row's own status text ([settings-backup](../screens/settings-backup.md)) |
| Cancelled | Nothing; not an error; the temporary file is removed | |
| Saving failed | `messages.export.archiveSaveFailed` in the error bar of the Backup page or of the File-menu dialog | |
| Errors | An Error `InfoBar` under the button on the Backup page, or in the File-menu dialog, selectable text, announced when it opens, cleared when the next export starts: `messages.save.before.goBack`, `messages.export.archiveNoSpace`, `messages.export.archiveFailed`, `messages.export.archiveSaveFailed` | |
| 4. The temporary file | Removed when the picker closes; leftovers from a cancelled picker or a closed window are removed at the next launch, matching only their own names | |

Rules of the spec that Windows keeps: one export at a time (pressing again while preparing or while the picker is open does nothing); locking cancels preparing and removes the temporary file; leaving the Settings page while preparing cancels, while the picker is open the export continues; the archive uses the journals' current password (a file archive is always encrypted); no device authentication is asked, even with App Lock on (D2 in [open-questions.md](../../../open-questions.md)).

### Windows details

- **Where the archive lands.** The person chooses the file's location, including a folder a cloud client such as OneDrive syncs ([16](../platform.md#16-files-and-pickers)). The archive is encrypted and opens only with the master password; the app adds no dialog or note about synced folders, and the risk is the person's (owner decision, 2026-10-07).
- **Long paths.** The only long part of a path is the folder the person picked plus the archive's name; a failure to create or write it is `messages.export.archiveSaveFailed`.
- **Copying the archive afterwards.** Because it is one file, a person can copy, email or upload it as one object, and every platform reads it.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The progress and error are beside and under the Export archive button on the Backup page ([settings-backup](../../../screens/settings-backup.md)); the File-menu dialog is default width | Backup pane; the Mac and iPad File-menu sheet |
| Small | The progress bar and text wrap under the button; the dialog fills the window width | iPhone Backup pane |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `export-archive` | File ▸ Export archive…; Settings ▸ Backup (button) | as in commands.md | Unlocked and no export is running |
| `change-password` | The link button `settings.backup.archive.changePassword` under the footer, on the Backup page and in the File-menu dialog | as in commands.md | Master-password journals (always on Windows), unlocked; it opens the [Change Password](change-password.md) dialog over the page or the File-menu dialog |
| `export-sheet-done` | The File-menu dialog's Close button | Esc | Always |

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Export archive…" (the ellipsis stays: it asks for a destination), "Preparing archive…", "Export archive" for the dialog's title. `settings.backup.archiveFilename` is unchanged on every platform, so exports sort and open the same ([12.1](../platform.md#121-casing)). No new picker strings: the system's Save button is used.

## Accessibility

- The progress indicator is hidden from the tree; its text `settings.backup.preparingArchive` is the label. Errors announce themselves as bars open.
- Focus returns to the Export archive button when preparing ends or the picker closes, and after the File-menu dialog closes to the control that opened it (the File menu's anchor is the window's content).
- Everything works with the keyboard; at 225% text size the text wraps.

## Different by design

- **No device authentication and no password check.** The archive is encrypted and opens only with the password or recovery key, so the archive export asks nothing (D2). A person unsure of their password uses the Change Password… pointer, which opens [Change Password](change-password.md); typing the current password there is the check.
- **A save picker and one file**, because a Windows picker cannot create a directory. Apple saves the same file with its document exporter.
- **The File-menu dialog stays open while the picker is up**, as the Apple sheet does.
- **A progress bar beside the button on the page, a ring only in the modal dialog**, as everywhere on Windows ([11](../platform.md#11-progress-and-announcements)).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D29 (the archive as one file, settled for 1.1).
