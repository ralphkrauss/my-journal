---
id: archive-import
title: Import Archive (sheet)
features: [import-archive]
sources:
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ArchiveSummary.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ContentImport.swift
  - docs/design/archives.md
  - docs/design/archive-preview-lifecycle.md
  - docs/design/journal-name-uniqueness.md
---

# Import Archive

## Purpose

Opens a My Journal archive, shows what it holds, and either restores it (on a device without journals) or adds its journals as new journals (on a device with journals). Flow: `flows/import-archive`.

## Entry points

- Settings ▸ Backup ▸ Import Archive…, File ▸ Import Archive…, the first-launch screen's Import Archive…, after choosing a file.
- Opening a `.journalarchive` file from the system (Files, Finder, Mail): the sheet opens once the journals are shown (after unlocking, if needed).

## Content

A sheet that scrolls, about 480 × 420 points, with padding.

- **Locked:** heading `settings.archiveImport.title` ("Import Archive"), `settings.archiveImport.locked`, and `common.cancel`.
- **Before opening** (the archive is protected): heading `settings.archiveImport.title`; a secure field `common.passwordOrRecoveryKey` ("Password or Recovery Key") with password autofill, Return opens; `settings.archiveImport.fieldHint` ("Use the password or recovery key for this archive.") in secondary text.
- **Preview** (after opening):
  1. Each journal's name as a heading (`common.untitledJournal` when it has none).
  2. `settings.archiveImport.entries` ("{count} entries in journals", plural).
  3. `settings.archiveImport.recentlyDeleted` ("{count} in Recently Deleted"), secondary.
  4. When there are any: `settings.archiveImport.unavailable` ("{count} in Unavailable") and `settings.archiveImport.unavailableNote`, secondary.
  5. When this device already has journals: `settings.archiveImport.kept`, or `settings.archiveImport.keptNumbered` when an imported journal's name is already used (here or by another imported journal); and when connected, `settings.archiveImport.willSync` ("Imported journals will also sync to your server.").
- **Error:** in red, selectable, below the content; the sheet scrolls to it.
- **Buttons** (side by side: Cancel, then the progress, then the primary at the trailing end; stacked at accessibility text sizes with progress, primary, Cancel):
  - `common.cancel`, disabled while importing;
  - progress: `settings.archiveImport.opening` ("Opening Archive…") or `settings.archiveImport.importing` ("Importing Journals…");
  - primary, prominent: `common.continue` (before opening), `settings.archiveImport.restore` ("Restore Journals", no journals on this device) or `settings.archiveImport.importAsNew` ("Import as New Journals"). Enabled when not busy and (opened, or a password typed).
- **Done:** heading `settings.archiveImport.imported` ("Journals Imported") or `settings.archiveImport.restored` ("Journals Restored"); after a restore, `settings.archiveImport.setUpSync` ("You can set up sync in Settings."); a prominent `common.done`.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Continue | `archive-open` | Opens the archive with the typed password or recovery key; shows the preview. |
| Restore Journals / Import as New Journals | `archive-import` | Imports; shows Done. |
| Cancel | `archive-import-cancel` | Stops opening, discards the opened copy, closes. |
| Done | `archive-import-done` | Closes. |

## States

- **Opening errors** (field keeps focus after a wrong password):
  - wrong password or recovery key: `settings.archiveImport.error.wrongPassword`;
  - newer format: `settings.archiveImport.error.newerVersion` ("Update My Journal to open this archive.");
  - incomplete or damaged: `settings.archiveImport.error.damaged`;
  - anything else (file not available, no space), and a folder archive made by version 1.0 without encryption (its manifest is plain text, recovery format 3 or 4), which this version doesn't read: `settings.archiveImport.error.couldntOpen`.
- **Import errors:** the error's own message, for example `messages.save.before.goBack`, `messages.import.archiveNeedsUpdate`, `messages.error.locked`.
- **Imported but not shown:** the app's error alert with `messages.refresh.imported`; the import isn't offered again.
- **Locked:** closes; the opened copy is discarded.
- **Library being replaced** when an archive file is opened from the system: the app's error alert with `messages.writingPaused.updating` instead of the sheet.

## Rules

- The opened copy lives apart from the journals until imported; cancelling, closing or locking discards it.
- The sheet can't be dismissed while importing; the computer doesn't lock for inactivity while opening or importing.
- The password is cleared from the field once the archive opens.
- Restoring makes the archive's library this device's library, with the archive's password.
- Importing adds the archive's journals as separate new journals; existing journals are kept; same names get a number (“Default 2”). The imported journals are encrypted with the library's key.

## Accessibility

- At accessibility text sizes the buttons stack and the primary fills the width.
- New errors are scrolled into view.

## Platform notes (Apple)

- The file picker is the system's, limited to the journal archive type.

## Open questions

- None.
