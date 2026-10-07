---
id: export-archive
title: Export an archive (Windows)
spec: flows/export-archive.md
features: [export-archive, password-check]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.storage.pickers
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
---

# Export an archive (Windows)

Saves everything needed to bring the journals back: entries, journals, templates, Recently deleted, images and earlier versions, encrypted with the journals' password when they are encrypted. Steps, errors and rules are the spec's [export-archive](../../../flows/export-archive.md). The archive is one file on Windows (the draft default of D29, from the review), so the picker is a save picker: see [import-archive](import-archive.md), "What an archive is on Windows".

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Entry points | The Backup page's Export archive… button; File ▸ Export archive…; the warning dialog of Erase, which closes first and then starts the export ([erase](../../../flows/erase.md)) | |
| 2. One-time password check | The Check your password dialog ([password-check](../../../screens/password-check.md)) over the page; Windows does not open a second dialog: the check closes, then the picker opens | Only for master-password journals not on a server whose password has not been confirmed. Right password or Not now continues; wrong shows `settings.passwordCheck.wrong` inline in that dialog |
| 3. Preparing | The open entry is saved first (`messages.save.before.exportArchive`); the package is written to a temporary folder in the app's local data. After 0.3 seconds a small indeterminate `ProgressBar` with `settings.backup.preparingArchive` shows beside the Export archive button on the Backup page (the page stays usable); for the File menu route a small `ContentDialog` titled `settings.backup.exportArchiveSheet.title` shows a `ProgressRing` and the text (the dialog is modal), with Close `common.done` | The File-menu dialog is the spec's export sheet: it stays open while the picker is up, as the spec says, and the picker is the window's own (a system dialog over the app window, which a `ContentDialog` behind it does not prevent) |
| 4. The picker | A `FileSavePicker` (the Windows App SDK picker with the window's id), started in Documents, `SuggestedFileName` `settings.backup.archiveFilename` with `{date}` in the fixed `yyyy-MM-dd` form of the spec (Gregorian, digits 0 to 9), one file type choice "My Journal archive" (`.journalarchive`). The system's Save button and its own replace prompt are used; nothing is overwritten without that prompt. The picker creates an empty file and the app writes the archive into it; if the write fails or is cancelled the empty or partial file the app created is removed | No Windows-only strings: the system supplies the button |
| Before writing (D46) | When the library is not encrypted and the chosen file is inside a OneDrive folder, the app asks first with the short dialog of [settings-backup](../screens/settings-backup.md): Choose another folder (reopens the picker, removing the empty file), Export here, or Cancel | An encrypted archive is safe in OneDrive and is not asked about |
| Saved | Done; nothing is announced | |
| Cancelled | Nothing; not an error; the temporary package is removed | |
| Saving failed | `messages.export.archiveSaveFailed` in the error bar of the Backup page or of the File-menu dialog | |
| Errors | An Error `InfoBar` under the button on the Backup page, or in the File-menu dialog, selectable text, announced when it opens, cleared when the next export starts: `messages.save.before.exportArchive`, `messages.export.archiveNoSpace`, `messages.export.archiveFailed`, `messages.export.archiveSaveFailed` | |
| 5. The temporary package | Removed when the picker closes; leftovers from a cancelled picker or a closed window are removed at the next launch, matching only their own names | |

Rules of the spec that Windows keeps: one export at a time (pressing again while preparing or while the picker is open does nothing); locking cancels preparing and removes the temporary package; leaving the Settings page while preparing cancels, while the picker is open the export continues; the archive uses the journals' current password and an unencrypted library gives a readable archive (the footer says so); no device authentication is asked, even with App Lock on (D2 in [open-questions.md](../../../open-questions.md)).

### Windows details

- **Where the archive lands.** Documents is often redirected to OneDrive ([16](../platform.md#16-files-and-pickers)). An encrypted archive is safe there; an archive of an unencrypted library is readable, which the existing footer already says, and the sync client uploads at once, so the app asks before writing (D46, above).
- **Long paths.** The only long part of a path is the folder the person picked plus the archive's name; a failure to create or write it is `messages.export.archiveSaveFailed`.
- **Copying the archive afterwards.** Because it is one file, a person can copy, email or upload it as one object, and every platform reads it (D29).

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The progress and error are beside and under the Export archive button on the Backup page ([settings-backup](../../../screens/settings-backup.md)); the File-menu dialog is default width | Backup pane; the Mac and iPad File-menu sheet |
| Small | The progress bar and text wrap under the button; the dialog fills the window width | iPhone Backup pane |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `export-archive` | File ▸ Export archive…; Settings ▸ Backup (button) | as in commands.md | Unlocked and no export is running |
| `password-check`, `password-check-not-now`, `forgot-password`, `set-new-password`, `set-new-password-cancel` | The check dialog | as in commands.md | As the spec |
| `export-sheet-done` | The File-menu dialog's Close button | Esc | Always |

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Export archive…" (the ellipsis stays: it asks for a destination), "Preparing archive…", "Export archive" for the dialog's title. `settings.backup.archiveFilename` is unchanged on every platform, so exports sort and open the same ([12.1](../platform.md#121-casing)). No new picker strings: the system's Save button is used. The OneDrive question is new (B37, D46).

## Accessibility

- The progress indicator is hidden from the tree; its text `settings.backup.preparingArchive` is the label. Errors announce themselves as bars open.
- Focus returns to the Export archive button when preparing ends or the picker closes, and after the File-menu dialog closes to the control that opened it (the File menu's anchor is the window's content).
- Everything works with the keyboard; at 225% text size the text wraps.

## Different by design

- **A save picker and one file**, because a Windows picker cannot create a directory package (D29, the review's recommendation; needs a protocol change).
- **The File-menu dialog stays open while the picker is up**, as the Apple sheet does.
- **A progress bar beside the button on the page, a ring only in the modal dialog**, as everywhere on Windows ([11](../platform.md#11-progress-and-announcements)).
- **A OneDrive question before an unencrypted export is written** (D46).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D29 (the archive as one file), D46 (OneDrive question), B37 (OneDrive wording).
