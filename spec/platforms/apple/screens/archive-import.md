---
id: archive-import
title: Import Archive (sheet) (Apple)
spec: screens/archive-import.md
features: [import-archive]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Model/ArchiveInstalling.swift
  - apps/apple/JournalApp/Model/LibraryProblem.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Archive.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ArchiveSummary.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ContentImport.swift
  - docs/design/archives.md
  - docs/design/archive-preview-lifecycle.md
  - docs/design/journal-name-uniqueness.md
  - docs/design/build-18-fixes-2026-10-06.md
---

# Import Archive (sheet) (Apple)

Neutral spec: [screens/archive-import.md](../../../screens/archive-import.md); the flow is `import-archive` ([flows/import-archive.md](../../../flows/import-archive.md)). The pane that starts it is `settings-backup`. Conventions: [platform.md](../platform.md#16-files-pickers-and-document-types) and [platform.md](../platform.md#9-sheets-popovers-and-notices).

## Controls

`ArchiveImportView` (`Views/ArchiveView.swift`), a `.sheet` that receives the chosen file URL. It is presented from two places: `ArchiveImportButton` (Settings ▸ Backup, a sheet attached to the Import Archive… button) and `RootView` (`archiveToImport`: File ▸ Import Archive…, the first-launch screen, the library problem screen, the missing-key lock screen and archive files opened from outside). Model: `AppModel` (`store`, `connection`, `libraryProblem`, `lockBlocksImport`, `vaultSessionID`, `inspectArchive`, `installArchive`, `discardImportedCopy`); the archive format and summary are in JournalCore.

Structure: a `ScrollViewReader` around a `ScrollView` whose content is a `VStack(alignment: .leading, spacing: 18)` with `.padding(24)`, framed `minWidth: 320, idealWidth: 480, minHeight: 280, idealHeight: 420`. The ideal size is what a Mac window sheet takes (about 480 by 420 points); on iPhone and iPad the system sizes the sheet and the minimum applies.

Content, by state:
- **Locked** (`model.lockBlocksImport`: locked and not the missing-key problem): title `settings.archiveImport.title` (`.title2.bold()`), `settings.archiveImport.locked` (secondary) and a `Button` `common.cancel` with `.keyboardShortcut(.cancelAction)`.
- **Before opening** (`prepared == nil && requiresPassword`): title; a `SecureField` `common.passwordOrRecoveryKey` with `.passwordAutofill()` and `.textFieldStyle(.roundedBorder)`, `onSubmit` runs `inspect()` unless busy; the hint `settings.archiveImport.fieldHint`. `requiresPassword` starts true and is set in `onAppear` by `VaultArchive.requiresPassword(at:)` inside a security-scoped access to the file.
- **Preview** (after opening, or when no password is needed): `ArchivePreviewSummary` (each journal's title as `.headline`, or `common.untitledJournal`; `settings.archiveImport.entries`; `settings.archiveImport.recentlyDeleted` secondary; when there are unavailable entries `settings.archiveImport.unavailable` and `settings.archiveImport.unavailableNote`). Then, depending on the device: with an open store, `settings.archiveImport.kept` or, when an imported name is already used (`namesUsed`), `settings.archiveImport.keptNumbered`, plus `settings.archiveImport.willSync` when `model.connection != nil`; with no store and a library problem that offers import (`model.libraryProblem?.offersImport`), `library.problem.importNote`, a sentence that restoring removes the journals that cannot be opened and ends syncing.
- **Error**: a red selectable `Text` below the content, with an `id` so `proxy.scrollTo` brings it into view when it appears (`onValueChange(of: error)`).
- **Done** (`completed`): title `settings.archiveImport.imported` or `settings.archiveImport.restored` (`wasAdditive`), after a restore the line `settings.archiveImport.setUpSync`, and a `Button` `common.done` with `.borderedProminent`.

Buttons: `ArchiveImportActions` (a view in the same file), with a progress `ProgressView` title `settings.archiveImport.opening` or `settings.archiveImport.importing` (shown while `busy`; `committing` selects the second), `Button(role: .cancel)` `common.cancel` (disabled only while `committing`, so it also stops opening) and the primary `.buttonStyle(.borderedProminent)`: `common.continue` before the archive is opened, then `settings.archiveImport.restore` when `model.store == nil` or `settings.archiveImport.importAsNew`. The primary is enabled when not busy and (opened, or no password needed, or a password typed). It declares no key equivalent; Return in the password field is the submit.

Errors on opening (`showInspectionError`): `JournalError.invalidRecoveryKey` gives `settings.archiveImport.error.wrongPassword` and refocuses the field; `unsupportedFormat` or `newerVersion` gives `settings.archiveImport.error.newerVersion`; `invalidData` gives `settings.archiveImport.error.damaged`; anything else `settings.archiveImport.error.couldntOpen`, which includes a folder archive made by version 1.0 without encryption (its manifest is plain text, recovery format 3 or 4): this version does not read it, so the sheet shows the same message and installs nothing. Encrypted folder archives from 1.0 are read as before. Errors while importing are `error.shown(.saving)`; the ones the spec names include `messages.import.archiveNeedsUpdate` (thrown by `ContentImport`) and `messages.save.before.goBack`.

Lifecycle: `.interactiveDismissDisabled(committing)`; `.keepsUnlockedWhile(busy || committing)` (Mac inactivity lock); locking cancels the operation, clears the preview and password and dismisses; `onDisappear` cancels and calls `model.discardImportedCopy(prepared)` so the opened copy (`import-<uuid>` in the data folder) is removed; the password is set to an empty string once the archive is open.

## Layout

- **iPhone.** A system sheet; the content scrolls inside it; at accessibility sizes `ArchiveImportActions` stacks: progress, the primary at full width, then Cancel (`dynamicTypeSize.isAccessibilitySize`).
- **iPad.** The same sheet in the centred form-sheet style.
- **Mac.** A window sheet sized to the ideal 480 by 420 points; the buttons sit in one row: Cancel at the leading end, progress and the primary at the trailing end.
- No screenshot exists for this sheet (see Screenshots).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `archive-open` | the primary button before the archive is opened | Return in the password field | a password is typed, or none is needed, and not busy |
| `archive-import` | the primary button after opening | none declared | not busy |
| `archive-import-cancel` | Cancel | Escape in the locked state only (declared); elsewhere the system's sheet behaviour | not while committing |
| `archive-import-done` | Done | none declared | always |

The picker that precedes the sheet starts with `import-archive`, as in [commands.md](../commands.md). Keyboard: focus starts in the password field only after a wrong password (`recoveryKeyFocused`); the field is not focused on appearance.

## Copy differences

None for the sheet's text; every string is the catalog default, including the restore-warning sentence for journals that cannot be opened (`library.problem.importNote`) and the authentication reason `settings.archiveImport.restoreReason` (`mac` variant in lower case).

## Accessibility

- The progress views carry their text as the label, so the state is text, not only an indicator.
- New errors are scrolled into view (`ScrollViewReader`).
- At accessibility text sizes the buttons stack and the primary fills the width.
- The password field uses `.passwordAutofill()` (system password manager).
- Reduce Motion and contrast are the system's; no overrides.

## Differences between iPhone, iPad and Mac

- Size: the Mac sheet takes the ideal size; iOS sheets are sized by the system, with the minimum as a floor.
- The Mac holds off the inactivity lock while opening or importing (`keepsUnlockedWhile`); iOS has none.
- The file picker is the system's `.fileImporter` offers `ArchiveFileType.importTypes` (the archive file type, `journalbackup`, and the 1.0 folder type, `journalarchive`) on every device; opening one of them from Files or Finder reaches the sheet through `onOpenURL` (see `import-archive`).

## Screenshots

None. No capture of this sheet exists: it needs an archive file chosen in the system file picker, which the sample-library captures do not include. Its appearance is not shown by the Settings ▸ Backup captures (`settings-backup`); the layout above comes from the source only.

## Source files

View:
- `apps/apple/JournalApp/Views/ArchiveView.swift`: `ArchiveImportButton`, `ArchiveImportView`, `ArchivePreviewSummary`, `ArchiveImportActions`.
- `apps/apple/JournalApp/Views/RootView.swift`: the sheet from the File menu, welcome and problem screens, `onOpenURL`, `openPendingArchive()`.

Model:
- `apps/apple/JournalApp/Model/DocumentTransferOperations.swift`: `inspectArchive`, `discardImportedCopy`, `validateVaultSession`.
- `apps/apple/JournalApp/Model/ArchiveInstalling.swift`: `installArchive` and the staging.
- `apps/apple/JournalApp/Model/LibraryProblem.swift`: `canImportArchive`, `refusesImport`, `lockBlocksImport`.

Core:
- `apps/apple/Packages/JournalCore/Sources/JournalCore/Archive.swift`: `VaultArchive.restore`, `requiresPassword`.
- `apps/apple/Packages/JournalCore/Sources/JournalCore/ArchiveSummary.swift`: the counts.
- `apps/apple/Packages/JournalCore/Sources/JournalCore/ContentImport.swift`: refusing newer-version content.

Design records: `docs/design/archives.md`, `archive-preview-lifecycle.md`, `journal-name-uniqueness.md`, `build-18-fixes-2026-10-06.md`.

## Open questions

None.
