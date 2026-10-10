---
id: save-entry
title: Saving an entry (Apple)
spec: flows/save-entry.md
features: [autosave]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/JournalEditing.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/LockSaving.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/WindowSafety.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/JournalApp.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/CompactJournalNavigation.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/JournalTests/DraftSaveTests.swift
  - apps/apple/JournalTests/StaleDraftTests.swift
  - apps/apple/JournalTests/LockSavingTests.swift
  - docs/design/mac-inactivity-lock-2026-10-03.md
  - docs/design/sync-now-and-done.md
---

# Saving an entry (Apple)

How the spec's [Saving an entry](../../../flows/save-entry.md) is built. A failing save is on [save-failure.md](save-failure.md). Saving has no screen and no control of its own, so most sections here say what the code does and where.

## Controls

Not applicable as a view: a normal save shows nothing. The parts are all in the model.

- The open entry is `AppModel.draft`, a `JournalItem`. `draftBase` is the copy last stored; `draft == draftBase` means saved. The editors write to the draft through bindings in `RootView` (`binding(_:default:itemID:)`): the body's `NativeEditor` and the title field both call `AppModel.updateDraft(_:)`.
- `updateDraft` ignores a change unless `canEdit` is true, the item is the open one, and the document is editable (or the change only touched text). It then notes use (the Mac inactivity lock), tells the rating request about the edit, stamps `modifiedAt`, takes the new item as the draft (`changeDraftQuietly`, which avoids rebuilding the lists for changes they do not show), increments `saveGeneration` and starts `saveTask` if none runs. There is no delay.
- `flush(whileEditing:announcing:)` does the saving: it waits for a running mutation and any earlier `draftWrite`, returns at once for a journal item, a read-only document, or an unchanged draft (`draft == draftBase`, which is why opening and leaving an entry writes nothing), and otherwise calls `writeDraft` (`JournalEditing.swift`), which runs one `store.save(item)` at a time as a `Task`. On success `adoptSavedDraft` makes the saved item the new base with its new `storedVersion`. If `saveGeneration` moved while it ran, `flush` calls itself again, so changes made during a save are saved right after, until nothing is left. Failure handling is in [save-failure.md](save-failure.md).
- After a successful save: `reviewRequests.noteSaved`, `pendingSync = true`, `syncWhenWritingPauses()` (waits `SyncEngine.writingPause` plus a quarter second and then syncs, restarting the wait with each save) and `rememberSelection()`. Saving on the device is immediate; syncing is separate.
- Never overwriting a newer copy: `updateDraft` stamps the item with the stored version the draft came from (`storedVersion`), and `JournalStore.save` (JournalCore, `Store.swift`) compares it with the stored one. If the record changed meanwhile, both versions are kept instead of one being overwritten: `keepChangedVersion` stores the stored version as a conflict, and the store then settles it, keeping this device's text as the entry and the stored version as a separate entry ([resolve-conflict.md](../flows/resolve-conflict.md)). `AppModel.refresh` replaces the draft with the stored version when nothing here is unsaved (`followStoredDraft`).
- Read-only entries: `canEdit` is false for a locked app, a library being replaced, a deleted entry, a document that is not editable (a newer format) and an entry whose journal is not live. `flush` returns without writing for them, so locking does not save them.

## Layout

Not applicable: nothing is shown, so nothing changes with size class, Dynamic Type or window size.

## Commands and shortcuts

There is no Save command and no Save menu item on any device.

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `finish-editing` | iPhone, iPad: Done (a checkmark) in the editor's navigation bar, trailing, while the text or title has focus (`RootView+Toolbar.swift`). It ends editing (the editor's finish-editing action) and then waits for the save (`model.finishPendingSave()`) | none | While writing (the editor reports editing). Not on the Mac |

Every command that acts on the open entry saves first by calling `finishPendingSave()` or `flush()`: opening another entry or journal (`select`, `show`, `switchJournal`), New Entry (`newEntry`), the iPhone back button (`CompactJournalNavigation.navigate`), Change Date, Move Entry, Save as Template, Image Descriptions, Version History, restoring, deleting, exporting, importing and connecting. Where the save fails the command does nothing and the sheet or action shows its own `messages.save.before.*` or `messages.save.before.goBack` message ([save-failure.md](save-failure.md)).

## Copy differences

None for a normal save. The Mac close and quit alert has its own copy (`messages.save.mac.title`, `messages.save.mac.message`, `messages.save.mac.keepOpen`), shown only on failure.

## Accessibility

Nothing is announced or shown for a normal save, so VoiceOver users hear no extra speech while typing. The accessibility of the failure alert and notice is in [save-failure.md](save-failure.md).

## Differences between iPhone, iPad and Mac

- Quitting (Mac): `ApplicationDelegate.applicationShouldTerminate` returns `.terminateLater`, runs `flush(announcing: .never)` and then `sendWritingBeforeQuitting(within: 3)`; if the save fails it shows the Keep Open alert (`presentSaveRecovery`) and replies that the app must not terminate. Closing the journal window (`WindowCloseGuard`, `windowShouldClose`) does the same flush before `performClose`. iPhone and iPad have no equivalent, because the system, not the app, ends the app.
- Going to the background (iPhone, iPad): `JournalApp.saveAndLock` calls `applicationEnteredBackground()` (which locks if App Lock is on) and then runs `saveWhileLocked` inside `BackgroundActivity.run`, which asks iOS for background time with `beginBackgroundTask`. The save is therefore started as the app leaves the screen but is limited by the time iOS grants. On the Mac a background scene phase runs `flush` and `sendWriting` without locking.
- Locking: `AppModel.lock()` with App Lock on calls `saveBeforeLocking(within: 2 seconds)`, which saves the entry and typed content in open sheets (`savesBeforeLocking`, for example Image Descriptions) and stops waiting after 2 seconds; then `lockImmediately` and `saveWhileLocked`, which continues the save and sends the writing. The Mac also locks on the screen lock notification, sleep and inactivity (`InactivityLock.swift`), all through `lock()`.
- On the Mac, every edit also calls `noteUse()`, so typing counts as use for the inactivity lock (`InactivityLock.swift`). The call does nothing on iPhone and iPad.
- Done exists only on iPhone and iPad, where the keyboard has no other way to say writing is finished.

## Screenshots

None. A normal save is silent, so there is nothing to capture. The state a failed save leaves behind (alert, notice) is on [save-failure.md](save-failure.md); the Settings ▸ Sync footer that says syncing waits is on the Settings pages.

## Source files

View:

- `apps/apple/JournalApp/Views/RootView.swift`: the bindings from the title and body to `updateDraft`.
- `apps/apple/JournalApp/Views/CompactJournalNavigation.swift`: iPhone back button saves, then deselects.
- `apps/apple/JournalApp/Views/RootView+Toolbar.swift`: Done.

Model:

- `apps/apple/JournalApp/Model/AppModel.swift`: `updateDraft`, `flush`, `finishPendingSave`, `draftIsSaved`, `canEdit` is in `JournalNavigation.swift`.
- `apps/apple/JournalApp/Model/JournalEditing.swift`: `writeDraft`, `adoptSavedDraft`, `followStoredDraft`.
- `apps/apple/JournalApp/Model/JournalNavigation.swift`: `select`, `show`, `switchJournal`, `canEdit`.
- `apps/apple/JournalApp/Model/LockSaving.swift`, `AppLockOperations.swift`: saving before and after a lock.
- `apps/apple/JournalApp/Model/WindowSafety.swift`: quitting and closing the window (Mac).
- `apps/apple/JournalApp/Model/SyncSchedule.swift`: `syncWhenWritingPauses`, `sendWriting`.
- `apps/apple/JournalApp/JournalApp.swift`: `saveAndLock` on a background scene phase.

Core:

- `apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift`: `JournalStore.save`, the stored-version comparison and the conflict that keeps a newer copy.

Design records: `docs/design/mac-inactivity-lock-2026-10-03.md`, `docs/design/sync-now-and-done.md`. Tests: `DraftSaveTests.swift`, `StaleDraftTests.swift`, `LockSavingTests.swift` in `apps/apple/JournalTests/`.

## Open questions

None. Pin Entry does not wait for the save (`Model/LibraryOperations.swift`, `setPinned`), as `flows/save-entry` says; `commands.md` and `screens/entry-editor` say otherwise (see [open-questions.md](../../../open-questions.md), A36).
