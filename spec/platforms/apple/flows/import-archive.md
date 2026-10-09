---
id: import-archive
title: Import an archive (preview, restore or add) (Apple)
spec: flows/import-archive.md
features: [import-archive]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/LibraryProblemView.swift
  - apps/apple/JournalApp/Views/UnlockView.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Model/ArchiveInstalling.swift
  - apps/apple/JournalApp/Model/LibraryProblem.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/AppCommands.swift
  - apps/apple/project.yml
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Archive.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ContentImport.swift
  - docs/design/archives.md
  - docs/design/archive-preview-lifecycle.md
  - docs/design/journal-name-uniqueness.md
  - docs/design/build-18-fixes-2026-10-06.md
---

# Import an archive (preview, restore or add) (Apple)

Neutral spec: [flows/import-archive.md](../../../flows/import-archive.md). The sheet is `archive-import` ([screens/archive-import.md](../../../screens/archive-import.md)); the starting pane is `settings-backup`. Conventions: [platform.md](../platform.md#16-files-pickers-and-document-types).

## Controls

The flow is a chain of system and app surfaces: a file picker (or a file opened from outside), the `ArchiveImportView` sheet, and the install in `AppModel`. Model: `AppModel` (`archiveImportRequested`, `lockBlocksImport`, `refusesImport`, `replacingVault`, `inspectArchive`, `installArchive`).

**1. Reaching the picker or the file.**
- Settings ▸ Backup: `ArchiveImportButton` has its own `.fileImporter(allowedContentTypes: [.journalArchive])`. A chosen URL opens the sheet attached to the button. A picker failure sets `ArchiveImportView.couldntOpen` and shows an `.alert` titled `settings.backup.openFailed` with that text and `common.ok`; the spec says the alert shows the system's message, the code shows the fixed text (B44).
- File ▸ Import Archive… (Mac, iPad with a keyboard), the first-launch screen's Import Archive… (`RootView`), the library problem screen's Import Archive… (`LibraryProblemView`, when the problem offers import) and the missing-key lock screen (`UnlockView`) all set `model.archiveImportRequested`. `RootView` owns the matching `.fileImporter` (iOS presents one per view hierarchy, which is why these screens do not carry their own). Its completion ignores the result unless it is a success and `!model.lockBlocksImport && !model.replacingVault`; a failure or cancel shows nothing here. The File menu item is enabled by `model.canImportArchive` (not locked; with a library problem, only when it offers import).
- From outside the app: the app declares the type `org.privatejournal.archive` (a package, extension `journalarchive`) with a `CFBundleDocumentTypes` entry (Viewer role, Owner handler rank), and on iOS `LSSupportsOpeningDocumentsInPlace` (`apps/apple/project.yml`). `RootView.onOpenURL` accepts a file URL whose extension is `journalarchive` and stores it in `pendingArchive`; `openPendingArchive()` then waits until `model.loaded`, no change is being stored (`committingMutation`) and no retry of opening runs. While locked (not the missing-key problem) it waits for the unlock; the request is forgotten if the scene goes to the background. If the library problem refuses import (journals from a newer version, unreadable settings), the file is dropped without a message. If the library is being replaced (`replacingVault`) the app error alert shows `messages.writingPaused.updating`. Otherwise the sheet opens (`archiveToImport`).

**2. The sheet** (`archive-import`): password field when `VaultArchive.requiresPassword(at:)` says so; Continue calls `inspect()`, which runs `model.inspectArchive(source, phrase:)` inside a security-scoped access to the file. That restores the archive into a separate folder `import-<uuid>` in the app's data folder (`VaultArchive.restore`), and `ArchiveSummary(snapshot:)` produces the preview. Each await checks `validateVaultSession`, so locking, connecting or replacing the library discards the copy. Cancel, closing and locking call `discardImportedCopy`, which removes only a folder directly inside the data folder that starts with `import-` and is not the configured storage folder.

**3. Install** (`ArchiveImportView.install()` then `AppModel.installArchive`, `Model/ArchiveInstalling.swift`):
1. `checkArchiveCanBeInstalled()`: refuses when a library problem does not offer import (`LibraryNotOpenError`), while replacing, retrying or locked (except the missing-key lock screen).
2. `finishPendingSave()`; if the open entry cannot be saved, `messages.save.before.goBack`.
3. When there is a configuration but no open store and App Lock is on, the device owner authenticates (reason `settings.archiveImport.restoreReason` "Restore journals on this device", lower-cased on the Mac by `AppModel.authenticationReason`). Cancelled: nothing changes and no error is shown.
4. `vaultReplacement = true` pauses writing and syncing.
5. With an open library (add): the current library is snapshotted into a new `vault-<uuid>` folder, a `JournalStore` is opened on it with the same key, and `importAsNewJournals(from:)` adds the archive's journals, giving duplicated names a number. `ContentImport` refuses content from a newer version with `messages.import.archiveNeedsUpdate`. The connection and settings stay; the earlier library is recorded as superseded.
6. Without an open library (restore, including a library that cannot be opened): the opened copy becomes the library; the configuration is built from the archive's recovery envelope (`recoveryConfirmed: true`; `passwordChecked` is no longer written). An archive whose recovery format is 3 or 4 (unencrypted, made by an earlier version) is installed as it is; the window then routes to Encrypt Your Journals (`Model/EncryptionRouting.swift`, `screens/encrypt-journals`), and `ArchiveView` shows `settings.archiveImport.unencryptedNote` in the preview when the device has no journals; App Lock and its inactivity time, and superseded libraries, are carried over from the unopened configuration; a new connection key name is used.
7. A new key item is written to the keychain under `keyAccount-<uuid>`, then the configuration is persisted. That write is the commit: before it a crash leaves the old library; after it the import stands. On failure `StagedInstall.discard()` closes the new store and removes its folder and keychain item.
8. `open(_:key:)` swaps the store, clears selection and image cache, reconfigures sync and refreshes. If refreshing fails, `model.error` shows `messages.refresh.imported` and the import is not offered again.
9. `completed = true` (unless locked meanwhile) shows Done with `settings.archiveImport.imported` or `settings.archiveImport.restored`.

States: the sheet's own (see `archive-import`); the app's general error alert for `messages.writingPaused.updating` and `messages.refresh.imported`.

## Layout

The picker is the system's: the Files browser (sheet or popover, system-chosen) on iPhone and iPad, an open panel on the Mac. The sheet is described on `archive-import`. Nothing in the flow is laid out by this code beyond the sheet.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `import-archive` | Settings ▸ Backup, File menu, first-launch and problem screens, as in [commands.md](../commands.md) | none | not locked; File item: `canImportArchive` |
| `archive-open` | the sheet's Continue | Return in the password field | password typed or none needed |
| `archive-import` | the sheet's Restore Journals or Import as New Journals | none declared | not busy |
| `archive-import-cancel` | the sheet's Cancel | see `archive-import` | not while committing |
| `archive-import-done` | the sheet's Done | none declared | always |

Keyboard: the system picker's own keys.

## Copy differences

None. The restore sentence for unopenable journals is `library.problem.importNote`; the authentication reason is `settings.archiveImport.restoreReason`, lower-cased on the Mac.

## Accessibility

- Progress labels are text; errors scroll into view (see `archive-import`).
- The picker, the authentication panel and the alerts are the system's.

## Differences between iPhone, iPad and Mac

- Entry points: File menu on the Mac and iPad with a keyboard; iPhone has Settings, the first-launch screen and the problem screens only.
- Open from outside: Files (in place, `LSSupportsOpeningDocumentsInPlace`) on iOS, Finder (double click or Open With) on the Mac; the same `onOpenURL` handler.
- The Mac does not lock for inactivity while opening or importing; iOS has no inactivity lock.
- On the Mac the File menu item first brings forward or opens a journal window (`inJournalWindow`), because the picker and the sheet belong to that window.

## Screenshots

None. The flow is picker, sheet and install, and the sample-library captures contain no archive file. The sheet is `archive-import`, which also has none.

## Source files

View:
- `apps/apple/JournalApp/Views/ArchiveView.swift`: the Settings button and picker, `ArchiveImportView`.
- `apps/apple/JournalApp/Views/RootView.swift`: the window's importer, `onOpenURL`, `openPendingArchive()`.
- `apps/apple/JournalApp/Views/LibraryProblemView.swift` and `UnlockView.swift`: the other entry points.
- `apps/apple/JournalApp/AppCommands.swift`: File ▸ Import Archive….

Model:
- `apps/apple/JournalApp/Model/DocumentTransferOperations.swift`: `inspectArchive`, `discardImportedCopy`.
- `apps/apple/JournalApp/Model/ArchiveInstalling.swift`: the commit sequence.
- `apps/apple/JournalApp/Model/LibraryProblem.swift`: when import is offered or refused.
- `apps/apple/project.yml`: the document type and exported type declarations.

Core:
- `apps/apple/Packages/JournalCore/Sources/JournalCore/Archive.swift`: `VaultArchive`.
- `apps/apple/Packages/JournalCore/Sources/JournalCore/ContentImport.swift`: newer-version refusal.
- `apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift`: `importAsNewJournals`.

Design records: `docs/design/archives.md`, `archive-preview-lifecycle.md`, `journal-name-uniqueness.md`, `build-18-fixes-2026-10-06.md`.

## Open questions

None.
