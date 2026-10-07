---
id: import-archive
title: Import an archive (preview, restore or add)
features: [import-archive]
sources:
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ContentImport.swift
  - docs/design/archives.md
  - docs/design/archive-preview-lifecycle.md
  - docs/design/journal-name-uniqueness.md
---

# Import an archive

## Purpose

Brings journals back from an archive, safely: nothing changes until the person has seen what's in it and confirmed, and existing journals are never replaced.

## Entry points

- Settings ▸ Backup ▸ Import Archive…; File ▸ Import Archive…; the first-launch screen's Import Archive…; opening a `.journalarchive` file from the system.

## Steps

1. Choose the archive in the system's file picker (or open it from the system).
   - The picker fails: alert `settings.backup.openFailed` with the system's message.
   - Opened from the system while locked: waits until unlocked; while the journals are being replaced: `messages.writingPaused.updating`; if the app goes to the background before it can show, it's forgotten.
2. **Import Archive** opens (`screens/archive-import`).
   - If the archive needs a password: type the password or recovery key; Continue.
3. **Open** (`settings.archiveImport.opening`): the archive is read into a separate copy. Errors (`settings.archiveImport.error.*`) leave the sheet open to try again.
4. **Preview:** journal names and counts; what will happen to current journals.
5. **Import:**
   - **No journals on this device:** Restore Journals. The archive's library becomes this device's library with the archive's password. Done shows `settings.archiveImport.restored` and `settings.archiveImport.setUpSync`.
   - **Journals on this device:** Import as New Journals. A copy of the current library is made; the archive's journals are added to it as separate journals (same names get a number); the copy then replaces the library in one step. Connected devices sync the new journals. Done shows `settings.archiveImport.imported`.
   (`settings.archiveImport.importing` while it runs; writing is paused.)
6. Done closes the sheet.

## Errors while importing

| When | Message |
| --- | --- |
| The open entry can't be saved first | `messages.save.before.importArchive` |
| The archive has items from a newer version and journals exist here | `messages.import.archiveNeedsUpdate` |
| Locked meanwhile | `messages.error.locked` |
| Imported, but the journals can't be shown | `messages.refresh.imported` (app error alert; the import stands) |
| Other | the error's own message |

On failure nothing changes: the staged copy and any key written for it are removed.

## Rules

- Never replaces or merges into existing journals; imported journals are always separate.
- The import commits in one step (the configuration switch); a crash before it leaves the library as it was.
- Cancel, closing and locking discard the opened copy.
- The computer doesn't lock for inactivity while opening or importing.

## Accessibility

- Progress labels are text, not only indicators. Errors scroll into view.

## Platform notes (Apple)

- None.

## Open questions

- None.
