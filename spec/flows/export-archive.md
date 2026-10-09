---
id: export-archive
title: Export an archive
features: [export-archive, change-password]
sources:
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/ExportView.swift
  - apps/apple/JournalApp/Model/ArchiveFileType.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - docs/design/archives.md
  - docs/design/export-operation-lifetime.md
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/1-1-encryption-and-passwords.md
---

# Export an archive

## Purpose

Saves one file with everything needed to bring the journals back: entries, journals, templates, Recently Deleted, images and earlier versions, encrypted with the journals' password.

## Entry points

- Settings ▸ Backup ▸ Export Archive… ; File ▸ Export Archive… (sheet) ; Erase Journals and Settings' warning ▸ Export Archive… (sheet).

## Steps

1. Export Archive….
2. **Device authentication** (only when App Lock is on and the journals aren't encrypted, because that archive holds readable entries, images and earlier versions and restoring it needs no password; an archive of encrypted journals needs the recovery credential instead): the device owner authenticates with the reason `settings.backup.archiveReason` ("Export an archive of your journals"). A device without a passcode goes on. Cancelled: nothing happens and nothing is said. Failed (for example biometrics locked out): nothing is exported and `settings.backup.verifyFailed` shows in the place where the export's own errors show. Every way in asks, including the Export Archive… button of the Erase warning.
3. **Preparing:** the open entry is saved (if it can't be: `messages.save.before.goBack`); the archive is written to a temporary file in the app's own storage, with enough free space checked first. After 0.3 seconds an indicator appears.
4. **Save dialog:** the system's dialog, suggesting `settings.backup.archiveFilename` ("Journal Archive {yyyy-MM-dd}.journalarchive", the date in the Gregorian calendar, numerals 0–9).
   - Saved: the Export row shows `messages.export.archiveSaved` ("Archive saved. Keep your {credential} with it.", the credential in lower case: master password or recovery key) until the next export starts, and the message is announced. An archive of journals without encryption has no credential and shows nothing.
   - Cancelled: nothing; not an error.
   - Saving failed: `messages.export.archiveSaveFailed`.
5. The temporary file is removed when the dialog closes.

There is no password check before exporting. A person who isn't sure of their password uses **Not sure of your password? Change Password…** (`settings.backup.archive.changePassword`), shown under the footer in Settings ▸ Backup and in the Export Archive sheet, for master-password journals only. It opens Change Password (`flows/change-password`): typing the current password is the check, a local-only library can reset a forgotten one with Forgot Password?, and an unwanted change is cancelled. Archives made before a change keep the old password.

## Errors

| When | Message |
| --- | --- |
| The device's authentication failed | `settings.backup.verifyFailed` |
| The open entry can't be saved first | `messages.save.before.goBack` |
| Not enough space, before anything is written (database, images and 256 MiB free are needed) or when the chosen place fills | `messages.export.archiveNoSpace` |
| Anything else while preparing | `messages.export.archiveFailed` |
| Saving to the chosen place failed | `messages.export.archiveSaveFailed` |

Errors show in red under the button, selectable, and clear when the next export starts.

## Rules

- One export at a time; pressing again while preparing or while the dialog is open does nothing.
- Locking cancels preparing and closes the dialog; the temporary file is removed.
- Leaving the pane while preparing cancels; while the dialog is open, the export continues.
- Leftover temporary files (from a cancelled dialog or a quit), and folders left by version 1.0, are removed at the next launch, matching only their own names.
- The archive uses the journals' current password. It is one file that can be attached to a message or sent by AirDrop as it is.
- Only journals with a password have an archive. Journals that are still not encrypted (the person chose Not Now) have no file to write: preparing ends with `messages.export.archiveFailed` (open question D66).
- Device authentication is asked when App Lock is on and the journals aren't encrypted (owner decision, 2026-10-06); it is not asked otherwise.
- A cancelled authentication says nothing; a failed one says `settings.backup.verifyFailed`. Export as Markdown behaves the same ([flows/export-markdown](export-markdown.md)).

## Accessibility

- The indicator is labelled `settings.backup.preparingArchive`.

## Platform notes (Apple)

- iPhone and iPad suggest the file's own name in the save dialog; the dialog's leftover copy under the same name is removed before the next export.
- The dialog saves the file from a wrapper that refers to the temporary file. Where the destination is on the same volume the system can clone it; for iCloud Drive, an external drive or another volume it is a copy, so the peak is the temporary file plus the saved one. A destination that fills ends with nothing saved and `messages.export.archiveNoSpace`; any other failure while saving is `messages.export.archiveSaveFailed`.

## Open questions

- None beyond `screens/settings-backup`.
