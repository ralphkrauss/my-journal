---
id: export-archive
title: Export an archive
features: [export-archive, password-check]
sources:
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/ExportView.swift
  - apps/apple/JournalApp/Views/PasswordCheckView.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Model/PasswordCheckOperations.swift
  - docs/design/archives.md
  - docs/design/export-operation-lifetime.md
  - docs/design/pre-release-ui-2026-09-27.md
---

# Export an archive

## Purpose

Saves one file with everything needed to bring the journals back: entries, journals, templates, Recently Deleted, images and earlier versions, encrypted with the journals' password when they're encrypted.

## Entry points

- Settings ▸ Backup ▸ Export Archive… ; File ▸ Export Archive… (sheet) ; Erase Journals and Settings' warning ▸ Export Archive… (sheet).

## Steps

1. Export Archive….
2. **Device authentication** (only when App Lock is on and the journals aren't encrypted, because that archive holds readable entries, images and earlier versions and restoring it needs no password; an archive of encrypted journals needs the recovery credential instead): the device owner authenticates with the reason `settings.backup.archiveReason` ("Export an archive of your journals"). A device without a passcode goes on. Cancelled: nothing happens and nothing is said. Failed (for example biometrics locked out): nothing is exported and `settings.backup.verifyFailed` shows in the place where the export's own errors show. Every way in asks, including the Export Archive… button of the Erase warning.
3. **One-time password check** (only for master-password journals not on a server whose password hasn't been confirmed): Check Your Password (`screens/password-check`).
   - Right password: continue.
   - Not Now: continue; asked again next time.
   - Wrong: `settings.passwordCheck.wrong`; after a wrong try, Forgot Password? may be offered (`flows/forgot-password`).
   - The save dialog appears only after the sheet has closed.
4. **Preparing:** the open entry is saved (if it can't be: `messages.save.before.goBack`); the archive is written to a temporary package. After 0.3 seconds an indicator appears.
5. **Save dialog:** the system's dialog, suggesting `settings.backup.archiveFilename` ("Journal Archive {yyyy-MM-dd}.journalarchive", the date in the Gregorian calendar, numerals 0–9).
   - Saved: done; nothing is announced.
   - Cancelled: nothing; not an error.
   - Saving failed: `messages.export.archiveSaveFailed`.
6. The temporary package is removed when the dialog closes.

## Errors

| When | Message |
| --- | --- |
| The device's authentication failed | `settings.backup.verifyFailed` |
| The open entry can't be saved first | `messages.save.before.goBack` |
| Not enough space | `messages.export.archiveNoSpace` |
| Anything else while preparing | `messages.export.archiveFailed` |
| Saving to the chosen place failed | `messages.export.archiveSaveFailed` |

Errors show in red under the button, selectable, and clear when the next export starts.

## Rules

- One export at a time; pressing again while preparing or while the dialog is open does nothing.
- Locking cancels preparing and closes the dialog; the temporary package is removed.
- Leaving the pane while preparing cancels; while the dialog is open, the export continues.
- Leftover temporary packages (from a cancelled dialog or a quit) are removed at the next launch, matching only their own names.
- The archive uses the journals' current password; journals without encryption give a readable archive (the footer says so).
- Device authentication is asked when App Lock is on and the journals aren't encrypted (owner decision, 2026-10-06); it is not asked otherwise.
- A cancelled authentication says nothing; a failed one says `settings.backup.verifyFailed`. Export as Markdown behaves the same ([flows/export-markdown](export-markdown.md)).

## Accessibility

- The indicator is labelled `settings.backup.preparingArchive`.

## Platform notes (Apple)

- iPhone and iPad suggest the package's own name in the save dialog; the dialog's leftover copy under the same name is removed before the next export.

## Open questions

- None beyond `screens/settings-backup`.
