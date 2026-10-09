---
id: export-archive
title: Export an archive (Apple)
spec: flows/export-archive.md
features: [export-archive, change-password]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/ArchiveView.swift
  - apps/apple/JournalApp/Views/ExportView.swift
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - apps/apple/JournalApp/Model/DocumentTransferOperations.swift
  - apps/apple/JournalApp/Model/ForgotPasswordOperations.swift
  - apps/apple/JournalApp/AppCommands.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Archive.swift
  - docs/design/archives.md
  - docs/design/export-operation-lifetime.md
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/build-18-fixes-2026-10-06.md
screenshots:
  - screenshots/iphone/export-archive-default.png
  - screenshots/ipad/export-archive-default.png
  - screenshots/mac/export-archive-default.png
---

# Export an archive (Apple)

Neutral spec: [flows/export-archive.md](../../../flows/export-archive.md). The surfaces are on `settings-backup`; this page records the sequence and the system dialogs. Conventions: [platform.md](../platform.md#16-files-pickers-and-document-types).

## Controls

Entry points: the Export Archive… button of Settings ▸ Backup (all devices), File ▸ Export Archive… (Mac, iPad with a keyboard; opens `ArchiveExportSheet`), and the Erase warning's Export Archive… button (opens the same sheet). All three show `ArchiveExportControls` (`Views/ArchiveView.swift`), so the behaviour is identical.

Steps, with the code that does each:
1. **Button press** (`common.exportArchive`). Ignored when `export.busy` (preparing or the save dialog open); otherwise `export.start(with: model)`. There is no password check in 1.1: the sheet `PasswordCheckView`, `passwordCheckPending` and `passwordChecked` writes are gone.
2. **The pointer.** Under the footer of `ArchiveControls` and `ArchiveExportSheet`, for master-password libraries, a borderless `Button` `settings.backup.archive.changePassword` presents `ChangePasswordView` (command `change-password`). Typing the current password there is the check, and a local-only library can reset a forgotten one with Forgot Password? (`ForgotPasswordOperations.swift` keeps the eligibility and the five-minute authorization).
3. **Preparing** (`ArchiveExport.prepare`). If App Lock is on and the library is not encrypted, the device owner authenticates first (see `settings-backup`). A 0.3 second timer then shows the small indicator (`settings.backup.preparingArchive`). `model.prepareArchive()` awaits `finishPendingSave()`; if the open entry cannot be saved it throws the message `messages.save.before.goBack`; otherwise `VaultArchive.export(store:recovery:key:to:)` writes a package `export-<uuid>.journalarchive` into the app's data folder. Locking or a new vault session (connecting, importing) cancels it and removes the package.
4. **Save dialog**: `.fileExporter(isPresented: $export.presenting, document: JournalFile, contentType: .journalArchive, defaultFilename:)`. The suggested name is `settings.backup.archiveFilename` with the date formatted `yyyy-MM-dd` in the POSIX locale (digits 0 to 9, Gregorian). `JournalFile.fileWrapper` hands the system the package with that preferred name. A cancelled dialog is `CocoaError.userCancelled` and is not an error; any other failure sets `messages.export.archiveSaveFailed`. Success sets the saved message `messages.export.archiveSaved` (lower-case credential; none for an unencrypted library) until the next export starts.
5. **Clean-up**: `discard()` removes the package and the dialog's leftover copy `Journal Archive <date>.journalarchive` in the temporary folder when the dialog closes; `ArchiveExportLeftovers.removeAtLaunch` removes anything left by a quit, matching only the app's own names, directories only, no symbolic links.

Errors (red, selectable `Text` under the button, cleared when the next export starts): `messages.save.before.goBack` (thrown as `JournalError.saveRequired`), `messages.export.archiveNoSpace` (`NSFileWriteOutOfSpaceError` or `ENOSPC`), `messages.export.archiveFailed` (anything else), `messages.export.archiveSaveFailed` (dialog result). A failed device authentication shows `settings.backup.verifyFailed` ("Couldn’t verify it’s you. Try again.").

Models: `AppModel`, `ArchiveExport`, `JournalFile`.

## Layout

The flow's surfaces: the Settings pane (see `settings-backup`), the File-menu sheet (a window sheet on the Mac with minimum 460 by 220 points, a system sheet on iPad), and the system save dialog:
- iPhone: the Files browser as a bottom sheet over the Settings sheet; the screenshot shows it while it is still appearing.
- iPad: the Files browser as a centred sheet with its sidebar, "Save as" field and Tags button.
- Mac: the File-menu sheet with the button, footer and Done; the save panel then appears over the window.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `export-archive` | as in [commands.md](../commands.md) | none | library open, unlocked, nothing exporting |
| `change-password` | the borderless pointer under the footer | none | master-password library, unlocked |
| `export-sheet-done` | Done in the File-menu sheet | Escape | always |

Keyboard: the save dialog uses the system's keys; Return and Escape in the File-menu sheet are the standard default and cancel actions.

## Copy differences

The authentication reason for an unencrypted library's archive (when App Lock is on) is `settings.backup.archiveReason`, lower-cased on the Mac by `AppModel.authenticationReason` (it has a `mac` variant).

## Accessibility

- The indicator is labelled `settings.backup.preparingArchive`. The saved message `messages.export.archiveSaved` is announced when it appears. Archive errors are shown in the pane but, unlike Markdown errors, not announced; a porter should announce them.
- The save dialog and authentication panel are the system's.

## Differences between iPhone, iPad and Mac

- Dialog: Files browser on iOS (the exported package keeps a copy under its suggested name in the temporary folder until `discard()`), save panel on the Mac.
- Menu entry: File menu on the Mac and an iPad with a hardware keyboard only; iPhone reaches the flow from Settings.
- The Mac keeps the app unlocked while the package is being prepared (`keepsUnlockedWhile`); iOS has no inactivity lock.
- The Change Password sheet the pointer opens is 440 points wide on the Mac; on iOS the system sizes it.

## Screenshots

| Device | State |
| --- | --- |
| iPhone | ![Save dialog on iPhone](../screenshots/iphone/export-archive-default.png) The Files bottom sheet appearing over Settings ▸ Backup. |
| iPad | ![Save dialog on iPad](../screenshots/ipad/export-archive-default.png) The Files save dialog with "Journal Archive 2026-10-07" and the Tags button. |
| Mac | ![Export Archive sheet on Mac](../screenshots/mac/export-archive-default.png) The File-menu sheet: the Export Archive… button, the encrypted-archive footer and Done. |

## Source files

View:
- `apps/apple/JournalApp/Views/ArchiveView.swift`: `ArchiveExportControls`, `ArchiveExportSheet`.
- `apps/apple/JournalApp/Views/ExportView.swift`: `JournalFile`, `UTType.journalArchive`, `archiveFilename`.
- `apps/apple/JournalApp/Views/ChangePasswordView.swift`: the sheet the pointer opens (it also holds Forgot Password? and the new-password form).

Model:
- `apps/apple/JournalApp/Model/DocumentTransferOperations.swift`: `ArchiveExport`, `prepareArchive()`, `ArchiveExportLeftovers`.
- `apps/apple/JournalApp/Model/ForgotPasswordOperations.swift`: the eligibility and authorization for Forgot Password? (formerly part of the password check).

Core:
- `apps/apple/Packages/JournalCore/Sources/JournalCore/Archive.swift`: `VaultArchive` (the package format; see `docs/design/archives.md`).

Design records: `docs/design/archives.md`, `export-operation-lifetime.md`, `pre-release-ui-2026-09-27.md`, `build-18-fixes-2026-10-06.md`.

## Open questions

See [open-questions.md](../../../open-questions.md), A29 and B43. D2 (device authentication before an archive) is resolved: the code authenticates and the spec now says so.
