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
  - apps/apple/JournalApp/Model/ArchiveInstalling.swift
  - apps/apple/JournalApp/Model/LibraryProblem.swift
  - docs/design/build-18-fixes-2026-10-06.md
  - docs/design/archives.md
  - docs/design/archive-preview-lifecycle.md
  - docs/design/journal-name-uniqueness.md
---

# Import an archive

## Purpose

Brings journals back from an archive, safely: nothing changes until the person has seen what's in it and confirmed, and existing journals are never replaced.

## Entry points

- Settings ▸ Backup ▸ Import Archive…; File ▸ Import Archive…; the first-launch screen's Import Archive…; the library problem screen's Import Archive… and the missing-device-key lock screen's, when the journals can't be opened ([screens/unavailable-content](../screens/unavailable-content.md)); opening a `.journalarchive` file from the system.

## Steps

1. Choose the archive in the system's file picker (or open it from the system).
   - The picker fails: alert `settings.backup.openFailed` with the system's message.
   - Opened from the system while locked: waits until unlocked; while the journals are being replaced: `messages.writingPaused.updating`; if the app goes to the background before it can show, it's forgotten.
2. **Import Archive** opens (`screens/archive-import`).
   - If the archive needs a password: type the password or recovery key; Continue.
3. **Open** (`settings.archiveImport.opening`): the archive is read into a separate copy. Errors (`settings.archiveImport.error.*`) leave the sheet open to try again.
4. **Preview:** journal names and counts; what will happen to current journals. For an archive that isn't encrypted, on a device with no journals: `settings.archiveImport.unencryptedNote`.
5. **Import:**
   - **No journals on this device:** Restore Journals. The archive's library becomes this device's library with the archive's password. Done shows `settings.archiveImport.restored` and `settings.archiveImport.setUpSync`. If the archive wasn't encrypted (made by an earlier version), the window then shows Encrypt Your Journals (`flows/encrypt-journals`): the restore installs the archive as it is, and the form encrypts it. Failures and Not Now there behave as for any unencrypted library.
   - **Journals on this device:** Import as New Journals (an unencrypted archive needs no special handling: the journals are added under the library's key, so they are encrypted, or stay readable until Encrypt Your Journals runs if the library is unencrypted). A copy of the current library is made; the archive's journals are added to it as separate journals (same names get a number); the copy then replaces the library in one step. Connected devices sync the new journals. Done shows `settings.archiveImport.imported`.
   (`settings.archiveImport.importing` while it runs; writing is paused.)
   - **Journals on this device that can't be opened** (the library problem screen after a failed open, or a missing device key): the sheet shows `library.problem.importNote` above its buttons and the button reads Restore Journals. With App Lock on, the device owner authenticates before the commit (`settings.archiveImport.restoreReason`); cancelled: nothing changes. The archive was read and checked before anything is replaced, so a bad archive or a wrong password leaves everything as it was. This is why Import is offered at once while Erase waits for a failed Try Again.
6. Done closes the sheet.

## Errors while importing

| When | Message |
| --- | --- |
| The open entry can't be saved first | `messages.save.before.goBack` |
| The archive has items from a newer version and journals exist here | `messages.import.archiveNeedsUpdate` |
| Locked meanwhile | `messages.error.locked` |
| Imported, but the journals can't be shown | `messages.refresh.imported` (app error alert; the import stands) |
| Other | the error's own message |

On failure nothing changes: the staged copy and any key written for it are removed.

## Rules

- Never replaces or merges into existing journals; imported journals are always separate.
- No restore ever leaves an unencrypted library that stays unencrypted, unless the person chooses Not Now on the form.
- A `.journalarchive` opened from outside the app while Encrypt Your Journals shows, or while it works, waits until the form and the run are over, then offers the import.
- The import commits in one step (the configuration switch); a crash before it leaves the library as it was.
- Replacing a library that couldn't be opened records it as superseded, so its files and keys are removed later and none is orphaned; the new library names its own connection item; and the settings App Lock and Lock when inactive carry over from the configuration it replaces, so restoring never turns App Lock off.
- Journals a newer version wrote, and settings that couldn't be read, are never imported over: Import Archive… isn't offered for them.
- Cancel, closing and locking discard the opened copy.
- The computer doesn't lock for inactivity while opening or importing.

## Accessibility

- Progress labels are text, not only indicators. Errors scroll into view.

## Platform notes (Apple)

- None.

## Open questions

- None.
