---
id: messages
title: Messages (Apple)
spec: messages.md
features: [sync-health, sync-status, sync-item-refusal, save-failure-recovery, writing-paused-notice, generic-error-alert, conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-journal, conflict-review-deletion, conflict-review-unsupported, library-open-failure, read-only-newer-content, unavailable-journals, privacy-cover, accessibility-announcements]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Views/RootView+Toolbar.swift
  - apps/apple/JournalApp/Views/Mac/JournalToolbarController.swift
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Views/EntryHeaderView.swift
  - apps/apple/JournalApp/Views/UnlockView.swift
  - apps/apple/JournalApp/Views/LibraryProblemView.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - apps/apple/JournalApp/Views/JournalConflictView.swift
  - apps/apple/JournalApp/Views/DeletionConflictView.swift
  - apps/apple/JournalApp/Views/DeletionConflictAlert.swift
  - apps/apple/JournalApp/Views/JournalAccessibility.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/FailureMessage.swift
  - apps/apple/JournalApp/Model/NetworkFailureMessage.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/Model/WindowSafety.swift
  - apps/apple/JournalApp/Model/LibraryProblem.swift
  - apps/apple/JournalApp/Model/PrivacyCover.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - docs/design/sync-health-and-recovery.md
  - docs/design/build-18-fixes-2026-10-06.md
---

# Messages (Apple)

Maps [messages.md](../../messages.md), the catalog of messages that come from the model layer. This page does not repeat the catalog: it says where each group is shown on iPhone, iPad and the Mac and which Swift type produces it. The text of every key is in [copy/en.json](../../copy/en.json). Status is `draft`: the groups below were traced through the source, but the page has no captured screenshots and not every one of the roughly 400 messages was checked individually.

## Controls

The spec's surfaces and their Apple implementation. `AppModel` (`Model/AppModel.swift`) owns the state: `error` (the pending message), `syncError`, `syncHealth`, `saveFailure`, `conflicts`, `libraryProblem`, `locked`.

| Surface | Apple control and file | Model type that produces it |
| --- | --- | --- |
| Generic alert | `.alert` on the window's root `Group` in `RootView.swift`: title literal, message `AppModel.error`, buttons OK (`role: .cancel`) and, only while `model.saveFailure`, Try Again (`model.flush(announcing: .always)`). Shown only while `!model.locked` and the first-journal sheet is not open. One alert per window; on the Mac the Settings window has no alert of its own, so an error raised there appears in the journal window | `Error.shown(.reading or .saving)` in `FailureMessage.swift` turns an error into text; `AppModel.error` is set by every operation (`report(_:_:)` and direct assignments) |
| Lock screen note | Red `.callout` text in `UnlockView` (`problem`), announced when it changes | `AppModel.error`, `unlockState.problem` |
| Library problem screen | `LibraryProblemView` (title, paragraphs, buttons) | `LibraryProblem` and `AppModel.failOpening`, see [screens/unavailable-content](screens/unavailable-content.md) |
| Sheet errors | An error `Text` in the sheet itself, usually red or secondary, announced with `JournalAccessibility.announce`: `MoveEntryView`, `EntryDateView`, `JournalLifecycleView`, `RecoveryJournalView`, `ImageDescriptionsView`, `JournalConflictView`, `EntryConflictReview`, `DeletionConflictView`, `ConnectionView`, `AddDeviceView`, `ChangePasswordView`, `ExportView`, `MarkdownExportView`, `ArchiveView`, `MergeJournalView`, `VersionHistoryView`, `JournalHistoryView` | Each sheet's own `@State error` or its flow object (`ConnectionFlow`, `ArchiveExport`); text from `shown(_:)` or from a `LocalizedError` in JournalCore |
| Settings ▸ Sync footer | `Section` footer in `SettingsView.syncSettings`, one `Text`. Priority: `SyncPauseNotice.saveFailed` (connected and `saveFailure`), `AppModel.syncError`, not-connected text, `AppModel.libraryFooter` (pins and journal order) | `SyncHealth.message(host:)` in JournalCore, `AppModel.syncError`, `AppModel.librarySync` |
| Sync action | One Button in `SyncNowRows` (`model.syncStatusAction.title`): Sync Now, Try Again, Check Again, Set Up Server Again…, Connect Again…, Sign In… | `SyncHealth.kind`, `SyncHealthOperations.swift` |
| Sync Status | iPhone and iPad: a `Menu` labelled Sync Status (`exclamationmark.icloud`) inside the entry's Entry Actions menu (`syncMenu` in `RootView+Toolbar.swift`). Mac: a toolbar item with a menu, plus an overflow item (`JournalToolbarController`). The menu holds the sync message as text, the action, and Sync Settings… | `AppModel.showsSyncStatus` (only when the person must act, or after a day of failing); see [screens/sync-status](../../screens/sync-status.md) |
| Save-failure notice | `SaveFailureNotice`: red status, Try Again Button, `ProgressView("Saving…")` while retrying. iPhone and iPad: first item of the entry's scrolling header (`EntryHeaderView`); Mac: a band below the editor in `RootView.detailContent`. Announces its status when it appears | `AppModel.saveFailure`, `flush(whileEditing:announcing:)` |
| Keep Open alert | Mac only: an app-modal `NSAlert` with one button, shown by `AppModel.presentSaveRecovery` when quitting (`applicationShouldTerminate`) or closing the journal window (`windowShouldClose`) while the open entry cannot be saved; the quit or close is cancelled | `ApplicationDelegate`, `WindowDelegateProxy` in `WindowSafety.swift` |
| Writing paused | Mac only: `ConnectionPauseNotice` and `EncryptionPauseNotice`, bands above the editor in the journal window (HStack, stacked at accessibility sizes, `.quaternary` background, fade unless Reduce Motion) with Show Connection or Show Progress. The connecting notice appears after one second | `AppModel.serverConnectionPause`, `EncryptionUpgrade.pausesWriting` |
| Entry notices | `ConflictNotice` (conflict), `EntryRecoveryNotice` (recovery and unavailable), `EntryEditingNote` (read-only and Markdown-source note under the title). iOS: in the entry's header or just above the editor; Mac: bands above the title | `AppModel.conflicts`, `JournalLifecycleSnapshot.location(of:)`, `JournalDocument.isEditable` |
| Changes to Review | `ConflictSettingsSection` in Settings ▸ Sync, shown only when unlocked and there is a conflict; the exclamation mark on a list row has the accessibility label `messages.conflict.needsReview` | `AppModel.conflicts` |
| Review sheets | `ConflictReview` routes to `EntryConflictReview`, `JournalMetadataConflictReview`, `DeletionConflictView` or a `DeletionSheet` with the update message. A deletion refused for changes to review uses `DeletionConflictAlert` first | `AppModel.conflicts`, `DeletionConflict` |
| Privacy cover | `LockedCover` overlay and, on iOS, system-level windows, see [screens/unavailable-content](screens/unavailable-content.md) | `PrivacyCover` |
| Announcements | `JournalAccessibility.announce` (`UIAccessibility` announcement on iOS, `NSAccessibility` on the Mac) and the model's `announceForAccessibility` | after a manual sync (`SyncSchedule.swift`), pin and journal moves (`LibraryOperations.swift`), encryption progress (`EncryptionUpgrade.swift`), errors in open sheets |

Which messages go where, by the spec's groups:
- **Sync states, sync actions, item refusals** (`messages.sync.*`, `common.signIn`): produced by `SyncHealth` (14 states, among them `localDataUnavailable`) in JournalCore and `AppModel.syncError`; shown in the Settings ▸ Sync footer, the single action Button and the Sync Status menu; `messages.sync.pausedForSaveFailure` is `SyncPauseNotice.saveFailed`. Record and image refusals set `syncError` without a failure state, so the action stays Sync Now.
- **Library record** (`messages.library.needsUpdate`, `messages.library.waitingForServer`): `AppModel.libraryFooter`, Settings ▸ Sync footer, only while connected.
- **Server and network errors outside sync, connecting, pairing, password change, Turn On Encryption** (`messages.server.*`, `messages.connection.*`, `messages.pairing.*`, `messages.password.*`, `messages.encryption.*`): errors inside the sheet of the flow (the error text of `ConnectionView`, `AddDeviceView`, `ChangePasswordView`, `TurnOnEncryptionView`), not the generic alert. Network failures are worded by `NetworkFailureMessage`.
- **JournalError and other operation errors** (`messages.error.*`, `messages.lifecycle.*`, `messages.restore.*`, `messages.entry.*`, `messages.history.*`, `messages.merge.*`, `common.journalGone`): the error text of the sheet that ran the operation ([screens/move-entry](screens/move-entry.md), [screens/change-date](screens/change-date.md), [screens/restore-journal](screens/restore-journal.md) and the history and merge sheets); the generic alert when the operation has no sheet (pin, move journal, default journal, Delete Journal).
- **Save failures** (`common.saveFailed`, `messages.save.*`): `common.saveFailed` is the generic alert's message with Try Again; `messages.save.notSaved` and `messages.save.saving` are `SaveFailureNotice`; `messages.save.mac.*` is the Keep Open alert; `common.saveFailedLocked` is the lock screen note; the "Save your … before …" messages are errors thrown by the model before an operation starts (`JournalError.server(...)`) and appear in that operation's sheet or the generic alert.
- **Saved, but not displayed** (`messages.refresh.*`): `AppModel.error` assigned after a committed change whose refresh failed, so the generic alert; `library.restoreEntry.displayFailed` and the restore sheet's own text stay in their sheet.
- **Other generic alert messages** (`messages.generic.*`): the generic alert; the deletion refusals also reach it, except changes to review, which have their own alert.
- **Export and import, images** (`messages.export.*`, `messages.import.*`, `messages.image.*`): the error line of the export, import and archive sheets; image import errors set `AppModel.error` (generic alert). The progress notice `ImageImportNotice` (Adding Image…, with Stop) is progress, not one of these messages.
- **Unavailable and read-only content, privacy cover** : see [screens/unavailable-content](screens/unavailable-content.md) and [screens/recently-deleted](screens/recently-deleted.md).
- **Conflicts** (`messages.conflict.*`): the conflict notice, the Changes to Review section, the row mark and the review sheets, as in the table.

## Layout

- **iPhone:** the generic alert is a centered system alert; the recovery and save-failure notices scroll with the entry (`EntryHeaderView`) while the conflict notice stays above the editor; Sync Status is a submenu of the entry's "…" menu, so it is reachable only while an entry is open.
- **iPad:** the same as iPhone for notices and Sync Status (in the editor toolbar); the Settings ▸ Sync footer is in the Settings sheet.
- **Mac:** notices are fixed bands above the title or editor, so they stay in view when the entry scrolls; the generic alert is a window alert; the Keep Open alert is app-modal; Sync Status is a toolbar button that keeps its place even when hidden so the toolbar does not move (`JournalToolbarController`). The Settings window shows the Sync footer and the Changes to Review section.
- **Dynamic Type:** notices that sit side by side (conflict, writing paused, image import) switch to a vertical stack at accessibility sizes (`dynamicTypeSize.isAccessibilitySize`); the Mac recovery notice scrolls inside half the detail height.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `sync-now` | Settings ▸ Sync action row; Sync Status menu | none | Connected, unlocked, not replacing the journals, no failed save, no sync running (as in [commands.md](commands.md)) |
| `sync-reconnect` | Settings ▸ Sync action row; Sync Status menu | none | When the state is Needs you, Server changed or No access |
| `sync-status` | Entry Actions menu (iPhone, iPad); toolbar (Mac) | none | `AppModel.showsSyncStatus` |
| `try-syncing-again` | Recovery notice | none | Journal missing and the library syncs |
| `review-changes` | Conflict notice, Changes to Review rows, recovery notice | none | Unlocked; the record has a conflict |
| `show-connection` | Writing-paused band (Mac) | none | While connecting from Settings |
| `show-encryption-progress` | Writing-paused band (Mac) | none | While encrypting or unfinished |

Keyboard: alerts follow the system (Return and Escape per button role; the Keep Open alert has one button). Notice Buttons are standard Buttons reachable with Full Keyboard Access.

## Copy differences

- `common.alertTitle` is "Journal" in the spec; the code titles the generic alert "My Journal" (`RootView.swift`, build 18 §1.11). One of the two is wrong.
- Code strings not in `copy/en.json`: the `FailureMessage` texts (for example "Something went wrong. Try again.", the damaged-data text that points to Export Archive in Settings ▸ Backup, "There isn’t enough space on this device. Free up space, then try again."), the `NetworkFailureMessage` texts ("You’re offline. Check your connection."), the library problem screen's text, and `SyncHealth.localDataUnavailable` ("Couldn’t sync right now. My Journal will try again.").
- `messages.sync.localDataUnreadable`: the spec says "My Journal couldn’t read its data on this device. Your journals haven’t been changed. To keep a copy, choose Export Archive in Settings > Backup."; the code says "My Journal can’t read your journals on this device. Nothing has been removed. To keep a copy, choose Export Archive in Settings ▸ Backup." (the same text as `FailureMessage.damagedReading`).
- `messages.error.newerVersion` and `messages.library.cannotOpen` are no longer shown at launch; the library problem screen replaces them.
- Messages that say "this Mac" (`messages.writingPaused.*`) exist only on the Mac; `messages.encryption.background` only on iPhone and iPad.
- The model's device wording (iPhone, iPad, Mac) comes from `DeviceUnlockMethod.deviceName`.

## Accessibility

- An alert is read by the system; notices are read in place, in reading order, before the title they sit above.
- Announcements: the sync result after Sync Now, Try Again or Check Again (the held message, else Synced, else Couldn’t sync.), never for automatic syncs; "Not Saved" when the save-failure notice appears; Pinned and Unpinned; journal moves ("Moved above …"); encryption progress; errors when they appear in an open sheet, the lock screen and the library problem screen. The editor adds announcements that the spec does not list (Image added, Link removed, Copied, Saved to Photos, Image deleted, heading levels).
- Writing-paused and conflict bands stack their button under the text at accessibility sizes; their fade is skipped with Reduce Motion.
- The Sync Status exclamation icon always keeps its Sync Status label and help tag; the list row's conflict mark is labelled "Changes need review".

## Differences between iPhone, iPad and Mac

- Save failure while quitting or closing exists only on the Mac (Keep Open alert), because only the Mac has a window close and a quit that the app can refuse; on iOS the app saves when it enters the background (`saveAndLock`, `BackgroundActivity` in `JournalApp.swift`) and shows the notice.
- Writing-paused notices exist only on the Mac, because only the Mac connects and encrypts from a Settings window that stays open beside the journal window and so needs a notice there; on iOS Settings is a sheet over the journal.
- Sync Status is a toolbar button on the Mac (the toolbar reserves its place) and an item in the Entry Actions menu on iOS, whose entry bar holds only that menu and Done.
- On iOS the recovery and save-failure notices scroll with the text (they are in the editor's header); on the Mac they are fixed bands, following how each editor is hosted.
- Errors raised from the Mac Settings window use the journal window's alert; on iOS Settings is a sheet over the same window, so its errors are in the sheet or the window alert.

## Screenshots

None. This page covers messages across many screens and states; the screens that show them have their own pages and screenshots: [recently-deleted](screens/recently-deleted.md), [restore-journal](screens/restore-journal.md), [move-entry](screens/move-entry.md), [change-date](screens/change-date.md) and [unavailable-content](screens/unavailable-content.md), plus the spec's [sync-status](../../screens/sync-status.md) and [conflict-review](../../screens/conflict-review.md).

## Source files

View: `Views/RootView.swift` (generic alert, window choice, notices placement), `Views/SettingsView.swift` and `Views/SyncNowRows.swift` (footer, action), `Views/RootView+Toolbar.swift` and `Views/Mac/JournalToolbarController.swift` (Sync Status), `Views/SaveFailureNotice.swift` (save notice, Mac writing-paused band), `Views/UnlockView.swift`, `Views/LibraryProblemView.swift`, `Views/ConflictRouting.swift` and the conflict views, `Views/DeletionConflictAlert.swift`.

Model: `Model/AppModel.swift` (`error`, `syncError`, `saveFailure`), `Model/FailureMessage.swift` and `Model/NetworkFailureMessage.swift` (system errors in words), `Model/SyncHealthOperations.swift` and `Model/SyncSchedule.swift` (states, action, announcement), `Model/WindowSafety.swift` (Keep Open), `Model/LibraryProblem.swift`.

Core: `SyncHealth.swift` (states and their text), `ServerClient.swift`, `SyncEngine.swift` (errors that become states).

Design records: `docs/design/sync-health-and-recovery.md`, `docs/design/build-18-fixes-2026-10-06.md`.

## Open questions

See [open-questions.md](../../open-questions.md), B2, B5 and B15. Differences found while writing this page (generic alert title, texts missing from the catalog) are in the report to the owner.
