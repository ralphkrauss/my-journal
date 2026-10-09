---
id: import-archive
title: Import an archive (Windows)
spec: flows/import-archive.md
features: [import-archive]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.storage.pickers
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Import an archive (Windows)

Brings journals back from an archive, safely: nothing changes until the person has seen what is in it and confirmed, and existing journals are never replaced. Steps, errors and rules are the spec's [import-archive](../../../flows/import-archive.md); the task page is [archive-import](../screens/archive-import.md). This file maps how the archive is chosen and handed to the page on Windows.

## What an archive is on Windows

An archive is **one file**, the file archive of [protocol/archive.md](../../../../protocol/archive.md): a ZIP container with `journal.sqlite`, one entry for each image and an `archive.json` that holds the recovery envelope and a sealed manifest of hashes. Windows reads and writes this kind only. The folder that My Journal 1.0 wrote (a directory archive) is an Apple-only legacy: a folder is not an archive here, and the Open picker cannot choose one.

A .NET `ZipArchive` materializes every entry when it is opened and checks neither CRC-32, duplicate names, overlap nor sizes against the manifest, so the reader does the protocol's work itself: it reads the end record first, refuses a central directory above 64 MiB or 300,000 entries before opening a library, asks for the password after the header is read and before anything proportional to the library, streams each listed entry once while hashing it, and inspects the extracted database by structure before it is opened as a library (the rules and limits are in the protocol, and `protocol/conformance/archive/v2/` has cases for each). A file that is not an archive, or does not match, is `settings.archiveImport.error.damaged`; an `archiveVersion` above 2 is `settings.archiveImport.error.newerVersion`; a wrong password is `settings.archiveImport.error.wrongPassword`; a file that cannot be read, or too little room for the staged copy (twice the listed sizes and 256 MiB), is `settings.archiveImport.error.couldntOpen`.

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Choose the archive | A `FileOpenPicker` (the Windows App SDK picker with the window's id, [16](../platform.md#16-files-and-pickers)) filtered to `.journalarchive` ("My Journal archive"), started in Documents; the system's own Open button | The app reads only what the person picked and never browses elsewhere. It checks the container, the manifest and every hash before it shows anything; a file that is not an archive or does not match says `settings.archiveImport.error.damaged` on the task page |
| The picker fails | A `ContentDialog` titled `settings.backup.openFailed`, content the system's message, Close `common.ok` | The error alert of the spec, with its own title kept because it names the failure ([8.1](../platform.md#81-rules)) |
| Opened from the system | Double-clicking a `.journalarchive` file in Explorer starts the import through the file association in the package manifest ("My Journal archive"); dropping the file onto the window does the same, and the drop target's caption is `common.importArchive`. A path given on the command line is handled the same way | The first instance receives the File activation ([platform.md, 19](../platform.md#19-single-instance-and-activation)) |
| Opened while locked | The path (not any content) is held and the import starts after unlocking | Nothing of the archive is read while locked |
| Opened while another flow is open | The window is brought to the front; the import request waits and starts when the flow ends ([messages](../messages.md), the dialog queue) | A modal flow is never interrupted |
| Opened while the library is being replaced | The alert dialog `messages.writingPaused.updating` (Close `common.ok`) instead of the Import archive page | |
| The goes-to-background rule of the spec | Not applicable | A Windows window is not suspended |
| 2–6. The task page | [archive-import](../screens/archive-import.md) | Password step, opening, preview, importing, done |

### Errors while importing

The spec's table, with the Windows surface: all are inline in the import page's error bar; the one the page cannot show (a locked library) is never seen.

| When | Message |
| --- | --- |
| The open entry cannot be saved first | `messages.save.before.goBack` |
| The archive has items from a newer version and journals exist here | `messages.import.archiveNeedsUpdate` |
| Locked meanwhile | The dialog hides and the work is cancelled; `messages.error.locked` is never seen |
| Imported, but the journals cannot be shown | `messages.refresh.imported` in the bar; the import stands |
| Other | The error's own message |

On failure nothing changes: the staged copy and any key written for it are removed.

### Staging

The opened copy is written under the app's local data (not the Documents folder or any synced folder), apart from the library, and removed when the page is cancelled, left or closed by a lock, and at the next launch if the app was ended in between ([17](../platform.md#17-app-data-backups-and-erasing)). It is never placed in the clipboard history or the Recent Items. The commit is one step (the configuration switch); a crash before it leaves the library as it was. While opening or importing, App Lock's inactivity timer does not fire.

## Layout at each window width

Not applicable to the flow; the picker is the system's and the page is mapped in [archive-import](../screens/archive-import.md). The drop target is the whole window at every width.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `import-archive` | File ▸ Import archive…; the welcome page's button; Settings ▸ Backup (button) | as in commands.md | Unlocked, or on the welcome page |
| `archive-open`, `archive-import`, `archive-import-cancel`, `archive-import-done` | The task page | as in [archive-import](../screens/archive-import.md) | As that file |

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Import archive…" (the ellipsis stays: it opens a picker), `settings.backup.openFailed` reads "Couldn’t open archive". No Windows-only picker strings are needed: the system supplies the Open button, and a file that is not an archive uses `settings.archiveImport.error.damaged`.

## Accessibility

- The Windows file picker is the system's and fully accessible. The drop target has no visible target other than the window; Narrator users and keyboard users use the menu or the button, so dropping is never the only way.
- When the page opens from a picker, Narrator reads its heading and content; focus starts on the password box or the first control, as in [archive-import](../screens/archive-import.md).
- A held import is not announced while locked; after unlocking the page opens with its normal announcement.

## Different by design

- **A file picker and a file association for an archive that is one file.** Apple opened the 1.0 folder as one document and opens the 1.1 file the same way; Windows needs a real file for the Open picker, drag and drop of one object and a double-click, and never reads the 1.0 folder.
- **The queue instead of "forgotten in the background".** A request that cannot show yet waits, because a Windows window is not suspended.
- **Dropping is an extra route**, not the only one.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D29 (the archive as one file, settled for 1.1).
