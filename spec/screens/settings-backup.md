---
id: settings-backup
title: Settings ▸ Backup, and the Export sheets
features: [export-archive, import-archive, export-markdown, change-password]
sources:
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/MarkdownExportView.swift
  - apps/apple/JournalApp/Views/ExportView.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Model/MarkdownExportOperations.swift
  - docs/design/archives.md
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/archive-actions-accessibility.md
  - docs/design/export-operation-lifetime.md
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---

# Settings ▸ Backup

## Purpose

Makes a complete, private copy of the journals that can be imported later (an archive), brings an archive back, and saves the journals as Markdown files other apps can open.

## Entry points

- Settings ▸ Backup (`screens/settings`).
- File ▸ Export Archive… and File ▸ Export Journals as Markdown… (computer, tablet with menu bar) open the matching sheet below (commands `export-archive`, `export-markdown`).
- File ▸ Import Archive… and the first-launch screen's Import Archive… open the system's file picker, then `screens/archive-import` (command `import-archive`).
- Erase Journals and Settings' warning offers Export Archive…, which opens the Export Archive sheet.

## Content

### 1. Archive section

Header `settings.backup.archive.header` ("Archive").
1. A button `common.exportArchive` ("Export Archive…"). While the archive is being prepared for longer than 0.3 seconds, a small activity indicator appears at the row's end (accessibility label `settings.backup.preparingArchive` "Preparing Archive…"); the row keeps its size.
2. An error line in red, selectable, when the last export failed. After a save, in the same place and until the next export starts: `messages.export.archiveSaved` ("Archive saved. Keep your {credential} with it.", credential in lower case), announced when it appears. Journals without encryption show nothing.
3. A button `common.importArchive` ("Import Archive…").
- Footer: `settings.backup.archive.footerEncrypted` ("An archive is an encrypted copy of your journals, including images and earlier versions. It opens only with your {credential}.", credential in lower case) or, for journals without encryption, `settings.backup.archive.footerUnencrypted` ("An archive includes readable entries, images and earlier versions. Keep it private.").
- Under the footer, for master-password journals only: a borderless button `settings.backup.archive.changePassword` ("Not sure of your password? Change Password…"), which opens Change Password (`screens/change-password`). There is no password check before exporting; typing the current password in Change Password is the check, and a local-only library can reset a forgotten password there.

### 2. Markdown section

Header `settings.backup.markdown.header` ("Markdown").
1. A button `settings.backup.exportMarkdown` ("Export as Markdown…"), disabled while preparing or without a library. Indicator after 0.3 seconds (accessibility label `settings.backup.preparingFiles` "Preparing Files…").
2. An error line in red, when the last export failed.
3. A note in secondary text after a successful save that left something out (see `flows/export-markdown`).
- Footer: `settings.backup.markdown.footer` for encrypted journals (it says the files aren’t encrypted), or `settings.backup.markdown.footerUnencrypted`.

### Export Archive sheet (File menu, and from Erase)

A sheet titled `settings.backup.exportArchiveSheet.title` ("Export Archive") with the same Export Archive… button, indicator, error line and saved message, the archive footer, the Change Password pointer, and a cancel-position button `common.done` that closes it. Closes when the app locks.

### Export as Markdown sheet (File menu)

A sheet titled `settings.backup.exportMarkdownSheet.title` ("Export as Markdown") with the same Export as Markdown… button, error and note, the Markdown footer, and `common.done`. Closes when the app locks.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Export Archive… | `export-archive` | Library open and unlocked; not while one is being prepared or saved | `flows/export-archive`. |
| Import Archive… | `import-archive` | Unlocked | File picker for journal archives; then `screens/archive-import`. A picker failure shows the alert `settings.backup.openFailed` ("Couldn’t Open Archive") with the system's message and `common.ok`. |
| Not sure of your password? Change Password… | `change-password` | Master-password journals, unlocked | Opens Change Password. |
| Export as Markdown… | `export-markdown` | Library open and unlocked; not while preparing | `flows/export-markdown`. |
| Done (sheets) | `export-sheet-done` | Always | Closes the sheet. |

## States

- **Preparing:** the button does nothing if pressed again; the indicator shows after 0.3 seconds.
- **Saving:** the system's save dialog is open; leaving Settings doesn't cancel it.
- **Error:** the red line under the button (cleared when the next export starts).
- **Locked:** preparing stops and the save dialog closes; the sheets close.

## Rules

- One export of each kind at a time.
- With App Lock on, both exports ask for the device's authentication first: Export Archive only when the journals aren't encrypted (`settings.backup.archiveReason`), Export as Markdown always (`settings.backup.markdownReason`, `settings.backup.markdownReasonUnencrypted`). A cancel says nothing; a failure shows `settings.backup.verifyFailed` in the export's error line ([flows/export-archive](../flows/export-archive.md), [flows/export-markdown](../flows/export-markdown.md)).
- Leaving the pane or sheet while preparing cancels the export; while the save dialog is open it stays.
- The computer doesn't lock for inactivity while an export is being prepared (it may while the save dialog waits).
- Temporary copies are removed after the dialog closes, and at the next launch if the app quit meanwhile.
- A not enough space failure on export (`messages.export.archiveNoSpace`) means the archive was not saved; so does `messages.export.archiveSaveFailed`.

## Accessibility

- The indicators have labels (`settings.backup.preparingArchive`, `settings.backup.preparingFiles`).
- Markdown export errors and notes are announced when they appear.

## Platform notes (Apple)

- iPhone and iPad: Settings ▸ Backup only (and the iPad's File menu with a keyboard). Mac: the Backup tab and the File menu.
- The save dialogs are the system's (file exporter); the archive is a file (`.journalarchive`, a ZIP container), the Markdown export a folder.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
