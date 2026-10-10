---
id: save-failure
title: Save failure and paused writing (Apple)
spec: flows/save-failure.md
features: [save-failure-recovery, writing-paused-notice]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/LockSaving.swift
  - apps/apple/JournalApp/Model/WindowSafety.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Views/EntryHeaderView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Editor/JournalWritingView.swift
  - apps/apple/JournalApp/Views/UnlockView.swift
  - docs/design/save-failure-retry.md
  - docs/design/save-failure-retry-review.md
  - docs/design/owner-decisions-2026-09-25.md
---

# Save failure and paused writing (Apple)

How the spec's [Save failure and paused writing](../../../flows/save-failure.md) is built. A save that works is on [save-entry.md](save-entry.md); the entry it shows in is on [entry-editor.md](../screens/entry-editor.md) and the lock screen that can show the locked message on [lock-screen.md](../screens/lock-screen.md). The page has two parts: the failed save (alert and notice) and, on the Mac, the notices that explain why writing is paused.

## Controls

State: `AppModel.saveFailure` (a published Bool, set and cleared only by `flush`) and `AppModel.error` (the message the window's alert shows). The unsaved writing stays in `AppModel.draft`; `draftBase` still holds the last stored copy, so `draftIsSaved` is false and `draftHasUnsavedEdits` is true while `saveFailure` is set.

- Alert: the window's generic `.alert("My Journal", isPresented:)` in `RootView.window`, shown while `model.error` is non-nil and the app is not locked. Its message is `model.error`. Buttons: `Try Again` (only while `model.saveFailure`) runs `model.flush(announcing: .always)`; `OK` has `role: .cancel` and clears the error. Keys `common.alertTitle`, `common.saveFailed`, `common.tryAgain`, `common.ok`. `flush` writes the message itself: "Couldn’t save “{displayTitle}”. Keep it open and try again.", where `displayTitle` is the title, else the first line, else New Entry (`library.entryList.untitledEntry`); when the app is locked it writes `common.saveFailedLocked` instead, which `UnlockView` shows in place of the alert. By default only the first failure raises the alert (`SaveFailureAnnouncement.firstFailure`); the retry from the alert or the notice uses `.always`; quitting and closing the window use `.never`.
- Notice: `SaveFailureNotice` (`SaveFailureNotice.swift`), a `VStack` of `Text("Not Saved")` in `.red` (`messages.save.notSaved`), a `Button` Try Again (`common.tryAgain`), and, while a retry runs, `ProgressView("Saving…")` (`messages.save.saving`). Its Try Again calls `flush(whileEditing: entryID, announcing: .always)` in a task that is cancelled when the notice disappears, the app locks or the library is replaced, and never runs unless the open entry is still the one the notice was made for. The button is disabled while it runs. It does not take focus.
- Placement: iPhone and iPad put it first in `EntryHeaderView`, the header that `JournalWritingView` hosts inside the entry's text view, above the recovery and other-version notices and the title, so it scrolls with the entry. The Mac puts it in `RootView.detailContent`, below the editor, outside the scrolling text.
- Revealing it (iPhone, iPad): `NativeEditor.revealSaveFailure` is `saveFailure && error == nil`, so the header is scrolled to the top, without animation, once the alert has been dismissed (`JournalWritingView.layoutHeader`, `failurePinned`). The pin ends when the person scrolls or touches the text.
- Blocking while it is set, all read from `saveFailure` or from a failed `flush`:
  - Leaving the entry: `select`, `show`, `switchJournal` and New Entry call `flush()` first and stay on the entry when it fails (the alert shows again). iPhone's back button pops at once and then calls `flush()` in a task (`CompactJournalNavigation.navigate`); the entry is deselected only if the save succeeds, so it stays selected with its writing in memory.
  - Sync: `AppModel.sync` returns early, `canSyncNow` is false (Sync Now is dimmed) and `SyncSchedule` does not start a sync; `SettingsView` shows `messages.sync.pausedForSaveFailure` while connected.
  - Operations that need the entry saved call `finishPendingSave()` (Image Descriptions and Change Date use `entryAutosaveSettled()`) and throw one typed error, `JournalError.saveRequired`, whose `errorDescription` is `messages.save.before.goBack`: every sheet and pane shows that text through `error.shown(.saving)`. The app's alert reports through `AppModel.report(_:_:)` instead: for `saveRequired` it keeps the typed error in `saveRequiredAlert` and assigns no string. `AppModel.alertText` is read when `RootView` draws the alert: `model.error` if set, else, while `saveRequiredAlert` is set **and** `saveFailure` is still true, `FailureMessage.saveRequiredWithTryAgain` (`messages.save.before.tryAgain`); the Try Again button reads `saveFailure` in the same draw. If a retry saved the entry first, `saveFailure` clears `saveRequiredAlert` and nothing shows. Alert sites: restoring a template (`restoreTemplate`), `JournalDeletionPrompt` (Delete Journal), `PermanentDeletionView` (Delete Permanently), `DeleteAllPrompt` and `restore(_:)` (Move Entry for Restore and Move…). A site that still assigns `error.shown(.saving)` shows the `goBack` text.
  - Change Date: Save is disabled (`EntryDateView`). Erase Journals and Settings is unavailable (`EraseOperations`). The template suggestion is hidden (`TemplateSuggestion`). The rating request does not run (`reviewMomentIsClear`, and `noteProblem()` when `saveFailure` becomes true).
- Locking: `saveBeforeLocking(within: 2 seconds)` saves first, then the lock, then `saveWhileLocked` saves again. A failure then sets `common.saveFailedLocked` on the lock screen. `saveFailure` is not cleared by locking, so the notice is back after unlocking.
- Mac window and quit: `WindowDelegateProxy.windowShouldClose` and `ApplicationDelegate.applicationShouldTerminate` call `flush(announcing: .never)`; on failure `AppModel.presentSaveRecovery()` runs an app-modal `NSAlert` (`runModal`) with the single button Keep Open, and closing or quitting is refused. Keys `messages.save.mac.title`, `messages.save.mac.message`, `messages.save.mac.keepOpen`.

Writing paused while the library is replaced:

- While the library is being replaced (`replacingVault`), `canEdit` is false, so the editor is read-only and `flush` and `sync` do nothing. The open entry is saved before the replacement starts, or the replacement does not start.
- Mac only: `ConnectionPauseNotice` (`SaveFailureNotice.swift`, `#if os(macOS)`) sits above the editor in `RootView.detail`. The notice is an `HStack` of callout text, a spacer and a button on `.quaternary`, and takes a fade (A45). At accessibility text sizes (`dynamicTypeSize.isAccessibilitySize`) a `VStack` with the button below. Texts: `messages.writingPaused.connecting`, `messages.writingPaused.connectionFailed` with `messages.writingPaused.showConnection` (opens Settings). The model is `AppModel.serverConnectionPause` (`.connecting`, `.waitingForRetry`). The connecting notice waits 1 second so that a quick connection does not flash it (`.task(id:)`).
- iPhone and iPad have no such notice: the connection sheet covers the app.
- An archive opened while the library is replaced: `RootView.openPendingArchive` sets the generic alert to `messages.writingPaused.updating`.

## Layout

- iPhone and iPad: the notice is part of the header above the title. It is a column (status, then button, then progress) at every size, so it wraps with Dynamic Type; the header grows with it (`JournalWritingView.layoutHeader` re-measures it).
- iPad: the same, in the detail column, at any width.
- Mac: the notice is a column below the editor inside the detail column (maximum width 760 points), padded, with the same three rows. The pause notices are full-width bars above the editor, stacked at accessibility text sizes.
- The alert and the Mac Keep Open alert are system alerts.

## Commands and shortcuts

`commands.md` has no row for Try Again of a failed save; the notice's button and the alert's button are not command ids there. Keyboard behaviour of the alert's buttons is the system's and was not checked. Quitting and closing the window (`quit`, `close-window`) are the commands that the Mac guards; both are in [commands.md](../commands.md).

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `quit` | As in commands.md | ⌘Q | As in commands.md; refused with the Keep Open alert while the open entry cannot be saved |
| `close-window` | As in commands.md | ⌘W | As in commands.md; refused the same way |

## Copy differences

- The Mac alert for quitting or closing is Mac only (`messages.save.mac.*`).
- The Mac pause notices say "this Mac" (`messages.writingPaused.*`); iPhone and iPad have no such notice.
- Everything else is the same on all devices. The alert title is the literal "My Journal", as `common.alertTitle` now says. All strings are literal English.

## Accessibility

- The alert is the announcement; it is a standard alert whose cancel button reads OK. When the notice first appears (`onAppear`) it also posts the announcement "Not Saved" (`JournalAccessibility.announce`), once, not on each edit. It does not take focus.
- "Not Saved" is red and says so in words. Try Again and its disabled state are standard button traits; Saving… is the progress view's label.
- Reduce Motion: the Mac connection notice fades with `.transition(.opacity)` and no animation under Reduce Motion.
- At accessibility text sizes the pause notices put the button below the text; the save-failure notice is already a column.
- VoiceOver on iPhone and iPad reaches the notice first in the header, before the title.

## Differences between iPhone, iPad and Mac

- Place of the notice: iPhone and iPad put it in the header, which scrolls with the text and leaves the bottom of the screen to the keyboard and writing controls; the Mac puts it below the editor because the window has room and the notice then stays in view.
- Only the Mac guards closing the window and quitting (`WindowCloseGuard`, `ApplicationDelegate`). On iPhone and iPad the app asks iOS for background time to save (`BackgroundActivity`) but iOS can still end it; a draft that could not be saved then is lost (open question D17).
- Only iPhone and iPad scroll the header to the notice after the alert (`revealSaveFailure`).
- Only the Mac shows writing-paused notices, because on iPhone and iPad the connection sheet covers the app.

## Screenshots

None. The failed state needs a store that cannot be written, which the capture script does not produce, so no capture exists for any device. The list the notice sits in is on the entry editor and entry list pages.

## Source files

View:

- `apps/apple/JournalApp/Views/SaveFailureNotice.swift`: the notice and the Mac connection pause notice.
- `apps/apple/JournalApp/Views/EntryHeaderView.swift`: the notice's place on iPhone and iPad.
- `apps/apple/JournalApp/Views/RootView.swift`: the alert, the Mac placement, the archive-while-updating message.
- `apps/apple/JournalApp/Editor/JournalWritingView.swift`: the header host and the scroll to the notice.
- `apps/apple/JournalApp/Views/UnlockView.swift`, `SyncNowRows.swift`: the locked message and the dimmed Sync Now.

Model:

- `apps/apple/JournalApp/Model/AppModel.swift`: `saveFailure`, `flush`, `draftIsSaved`, `serverConnectionPause`.
- `apps/apple/JournalApp/Model/JournalNavigation.swift`, `SyncSchedule.swift`, `LockSaving.swift`: what waits for the save.
- `apps/apple/JournalApp/Model/WindowSafety.swift`: the Mac close and quit guard and the Keep Open alert.

Core: none specific; the store's write is `JournalStore.save` in JournalCore.

Design records: `docs/design/save-failure-retry.md`, `docs/design/save-failure-retry-review.md`, `docs/design/owner-decisions-2026-09-25.md`.

## Open questions

See [open-questions.md](../../../open-questions.md), D17 and A45. The alert title (B5, resolved: "My Journal") and the alert shown once per failure (A1, resolved in build 18) no longer differ. Still reported: the "Not Saved" announcement when the notice appears.
