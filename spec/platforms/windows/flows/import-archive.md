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

The spec says an archive is **one file**, and the protocol carries it as a **directory package** named `….journalarchive` (an `archive.json`, a `journal.sqlite` and an `attachments` folder, in [protocol/archive.md](../../../../protocol/archive.md)). Apple's file system treats such a package as one document. Windows does not: Explorer shows a folder, a folder cannot be chosen with a file picker, a save picker cannot create one, and a file type association applies to files. A folder is also easy to copy partly, to sync half-way through OneDrive and to break with path-length limits, and nothing stops a half-copied folder from looking valid. **The draft default of D29 (the review's recommendation) is a protocol change: one file on every platform**, a ZIP container (or an equivalent single-file package) with the manifest, a content hash and the same checks. This mapping follows that default and says what it needs; the protocol change is the owner's decision because the protocol is shared by every platform.

**Fallback if the owner declines.** The folder route: `FolderPicker` in both directions, no file association, a dropped folder starts the import, and a completeness check before the preview: the manifest lists every file with its hash and the import verifies all of them, so a half-copied folder cannot look valid; a folder that fails gets `settings.archiveImport.error.damaged`, or the Windows-only string of B36 when it is not an archive at all.

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Choose the archive | A `FileOpenPicker` (the Windows App SDK picker with the window's id, [16](../platform.md#16-files-and-pickers)) filtered to `.journalarchive` ("My Journal archive"), started in Documents; the system's own Open button | The app reads only what the person picked and never browses elsewhere. It checks the manifest and the content hash before it shows anything; a file that is not an archive or does not match says `settings.archiveImport.error.damaged` on the task page |
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

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Import archive…" (the ellipsis stays: it opens a picker), `settings.backup.openFailed` reads "Couldn’t open archive". No Windows-only picker strings are needed on the file route: the system supplies the Open button, and a file that is not an archive uses `settings.archiveImport.error.damaged`. (The folder fallback needs "Select archive" and "This folder isn’t a My Journal archive.", B36.)

## Accessibility

- The Windows file picker is the system's and fully accessible. The drop target has no visible target other than the window; Narrator users and keyboard users use the menu or the button, so dropping is never the only way.
- When the page opens from a picker, Narrator reads its heading and content; focus starts on the password box or the first control, as in [archive-import](../screens/archive-import.md).
- A held import is not announced while locked; after unlocking the page opens with its normal announcement.

## Different by design

- **A file picker and a file association for an archive that is one file** (D29, the review's recommendation, which needs a protocol change). Apple opens a directory package as one document; Windows needs a real file for the Open picker, drag and drop of one object and a double-click.
- **The queue instead of "forgotten in the background".** A request that cannot show yet waits, because a Windows window is not suspended.
- **Dropping is an extra route**, not the only one.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D29 (the archive as one file; B36 for the folder fallback).
