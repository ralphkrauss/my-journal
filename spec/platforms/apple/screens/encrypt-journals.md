---
id: encrypt-journals
title: Encrypt Your Journals (Apple)
spec: screens/encrypt-journals.md
features: [encrypt-existing-journals]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/EncryptJournalsView.swift
  - apps/apple/JournalApp/Views/EncryptionNotice.swift
  - apps/apple/JournalApp/Model/EncryptionRouting.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Views/SaveFailureNotice.swift
  - apps/apple/JournalApp/Views/ConnectionView.swift
  - apps/apple/JournalApp/Views/ConnectionSteps.swift
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Model/EncryptionOperations.swift
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/enable-encryption.md
---

# Encrypt Your Journals (Apple)

Implements [screens/encrypt-journals](../../../screens/encrypt-journals.md). The sequence of work, errors and cancellation rules are on [flows/encrypt-journals](../flows/encrypt-journals.md). This note was written from the 1.1 design record (`docs/design/1-1-encryption-and-passwords.md`, sections 3.3 to 3.8 and its owner decisions of 2026-10-09) at the same time as the code; it replaces the 1.0 three-step Turn On Encryption sheet. Until the screens are captured by the script and the page is checked against the source it is `draft`. The views hold the English text as literals; the copy keys named here are the spec's keys for the same text.

## Controls

- **Model.** `EncryptionUpgrade` (`Model/EncryptionUpgrade.swift`, one per app, `AppModel.encryption`) holds the variant (A to D), whether the check is running (`checking`), the phase of a run (`syncing`, `encrypting(Double)`, `updatingServer`), the form's and the notice's errors, `unfinished`, `notNowChosen` (this launch only, in memory, never stored), `failedThisLaunch` and the running `Task`. The work is in `Model/EncryptionOperations.swift`: `checkEncryptionReadiness` (bounded), `prepareEncryption` (everything that can be refused before the journals pause) and `runEncryption` (`turnOnEncryption` is the two together), `finishInterruptedEncryption`, and `stopSyncingAfterUnfinishedEncryption`, the adopt-the-encrypted-copy operation. `Model/EncryptionRouting.swift` decides what each window shows as a pure function of the app state (below).
- **Routing.** `RootView` shows, in order: opening progress, the lock screen, the library problem screen, the first-launch screen, then **the journals with the notice when a saved encryption marker has the server switched or a run is in progress**, then **the form** (only when there is no marker, the library is unencrypted and Not Now has not been chosen in this launch), then the recovery key, then the journals. The state belongs to the app, not to a window, so every Mac window shows the same thing. The form as a sheet (from Settings ▸ Privacy, or after Not Now in this launch) is `.sheet` over the journals with Cancel.
- **The form** (`Views/EncryptJournalsView.swift`). A `ScrollView` with a centred `VStack` at most 480 points wide, like `CreateJournalView`. Lock-shield symbol (`lock.shield`, hidden from accessibility); heading `library.encrypt.title` (`.title2.bold()`, header trait); the variant's paragraph; for variant B a "Your Other Devices" section (`settings.encryption.otherDevices.header`, with `.update`, `.signIn`, `.agents`); the fields (rounded-border `SecureField`s, or `TextField`s while Show Password is on, as in Start a Journal: Master Password and Verify with `.passwordAutofill(creating: true)`, and a `Toggle` `common.showPassword`), plus a field `settings.encryption.currentAccessPassword` (plain `.password` autofill) only for recovery format 3 on a server, in which case the toggle reads `settings.encryption.showPasswords`; directly under the fields `library.createLibrary.advice` (variant A) or `settings.password.footer` (variant B) and then `library.encrypt.duration` (`mac` variant on the Mac); an error `Text` in red (selectable); the primary `Button` `library.encrypt.action` (`.borderedProminent`, `.controlSize(.large)`, `.accessibilityLabel` `library.encrypt.action.accessibilityLabel`; `common.tryAgain` after an error, `common.reconnect` in variant C); below it `.plain` buttons `library.encrypt.notNow` and `settings.sync.stopSyncing`, each only in the situations listed in the spec. As a sheet it also has a Cancel in `.cancellationAction`.
- **Check.** For a synced library the form first shows `connectionStatus` (a `ProgressView` beside `settings.encryption.checking`). The check reads the server's public encryption details, the encryption-upgrade capability and the device list (an unauthorized answer is lost access), and checks free space; it is bounded at about 10 seconds (`AppModel.serverQuestionSeconds`) and a late answer is dropped. Not Now is offered as soon as the check fails or after about 3 seconds (`EncryptionUpgrade.earlyExitSeconds`), whichever comes first; the system's network-path report is not consulted, because a phone with no network fails the check at once. The chosen variant is announced with `announceForAccessibility`.
- **Focus.** On the Mac `@FocusState` moves to Master Password about 0.4 seconds after the form appears. On iPhone and iPad it does not (the keyboard and the strong-password bar would cover the note under the fields; VoiceOver already lands on the heading through `JournalAccessibility.screenChanged`). Return moves Master Password to Verify to Encrypt.
- **The working notice** (`Views/EncryptionNotice.swift`, device-neutral; it replaces the Mac-only `EncryptionPauseNotice`). Text `messages.writingPaused.encrypting`, the status row (`connectionStatus` for checking and syncing, `EncryptionProgressRow` for `settings.encryption.progress` with `ProgressView(value:)` as one accessibility element with label `settings.encryption.progressLabel` and value `settings.encryption.progressValue`, `settings.encryption.updatingServer`), and a Cancel `Button` (`common.cancel`, accessibility label `settings.encryption.cancel.accessibilityLabel`, Escape on the Mac, disabled while the server is being updated). It sits at the top of the editor column of the journal window on the Mac (`ConnectionPauseNotice`, where the connection notice is) and above the whole navigation on iPhone and iPad (`RootView.journals`), on `.quaternary`, as an `HStack` or, at accessibility Dynamic Type sizes, a leading-aligned `VStack` (text, progress, button). There is no animation. The same view shows the failure state (error text with Try Again and Not Now) and the unfinished state (`messages.encryption.unfinished` with Try Again and Stop Syncing…).
- **Read-only.** `prepareEncryption` saves the open entry and checks the room, then `runEncryption` calls `AppModel.pauseWriting(true)` before the first sync (it used to be called inside `encrypt` after `synchronizeBeforeEncrypting`), and every end but an unfinished switch releases it. `prepareEncryption` and `checkEncryptionReadiness` guard on `!replacingVault`, so the order matters. The controls that would write are disabled through `AppModel.writingPausedForEncryption`, with the notice as the reason: the entry actions (Change Date, Move Entry, Save as Template, Restore, Delete, in the row menu and as swipe actions), the journal actions and every New Journal button and menu item, Import Archive…, and, through `canEdit` and `canCreateEntry`, the editor and New Entry. Exporting works: `validateVaultSession(_:readingWhileEncrypting:)` lets the archive and Markdown exports run during the pause. `openPendingArchive` waits while the form shows or a run is in progress. The editor shows the read-only note it shows whenever writing is paused. On iPhone and iPad this is a new surface: 1.0 covered the app with a modal sheet.
- **Sync hold.** Until Not Now is chosen or the library is encrypted (`AppModel.encryptionHoldsSynchronization`), `sync()` itself is gated, not only `synchronizeAutomatically`, because `EntryRecoveryNotice` and the Sync Now rows also call it; `sendWriting()`, the watcher's wait for changes and its agent-copy publishing are gated the same way. The hold ends at Not Now or when encryption starts, which syncs once itself first (`synchronizeBeforeEncrypting`). The readiness check and `finishAfterLaunch` legitimately read the server.
- **Variant C, Reconnect….** The button sets the sign-in request (`signInRequested`; from the sheet the sheet closes first and Settings opens it), which the encryption presenter (`EncryptionPresentation`, a `ViewModifier` applied in `JournalApp.swift`) turns into a `ConnectionView` sheet over the form, at the Enter Master Password step, exactly as Settings ▸ Sync's Reconnect… does. The window gives way to the journals when it finishes.
- **Stop Syncing….** On the form: a `.confirmationDialog` (title `settings.sync.stopSyncing.title`, message `library.encrypt.stopSyncing.message` plus `settings.sync.stopSyncing.messageUnsent`, buttons `settings.sync.stopSyncing.confirm` and `common.cancel`), then `stopSyncing` and the form becomes variant A. On the unfinished notice: the same confirmation with `library.encrypt.adopt.message`, running its own operation, `stopSyncingAfterUnfinishedEncryption` (not `stopSyncing`, which refuses while `replacingVault`): one bounded check of the server's envelope; switched or no answer commits the staged encrypted copy as `commitEncryption` does and removes the connection; not switched keeps the original library, discards the copy and drops the connection. `finishInterruptedEncryption` bounds its question to the server the same way, after which the same two buttons are offered.
- **Done sheet** (`Views/EncryptJournalsView.swift`). A `.sheet` over the journals: `lock.shield` at 48 points (hidden), heading `settings.privacy.encryption.on` (header trait), `settings.encryption.done.message`, `library.encrypt.done.keepPassword`; when synced a section `settings.encryption.otherDevices.header` with `settings.encryption.done.otherDevices` and a `Button` `settings.connect.ready.addDevice` presenting `AddDeviceView`; footer `settings.encryption.done.archives`; one `common.done` (a large prominent button, the default action); Return and Escape both close it. `EncryptionUpgrade.completed()` clears the password fields and announces `messages.encryption.announce.done`.
- **Idle timer (iPhone, iPad).** `UIApplication.shared.isIdleTimerDisabled` is set while the work runs, as `AddDeviceView` does, and restored on every exit (Auto-Lock would otherwise send the app to the background mid-copy and loop on `messages.encryption.background`).
- **Settings.** While the form is the root screen Settings shows `settings.encryptFirst` in place of its panes (`SettingsView` reads the routing). Menu commands that need a library and Import Archive… are disabled, as on the first-launch screen (`AppCommands.swift`). A `.journalarchive` opened from outside waits.

## Layout

- **iPhone.** The form is the full window; the notice is a bar above the content on every stacked screen (Journals, Entries, Entry); the Done sheet is a standard sheet. In variant A the fields, note and Encrypt fit the first screen of the smallest supported iPhone at the default text size.
- **iPad.** The form is the full window with the column centred, the same in Split View, Slide Over and every window; the notice is above the columns; the Done sheet is the regular-width system sheet.
- **Mac.** The form fills each journal window (minimum 801 by 420 points); Encrypt is the window's default button; the notice sits at the top of the editor column of the journal window. The form as a sheet from Settings is a sheet on the Settings window with Cancel (Escape).
- **Dynamic Type.** The form scrolls and the buttons stack; the notice stacks at accessibility sizes.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `turn-on-encryption` | Settings ▸ Privacy button; opens the form as a sheet | none | not encrypted, unlocked, not replacing the journals (or the work is already running) |
| `encrypt-journals` | The form's primary button | Return in Verify; the Mac's default button | check passed, both new fields (and the access password if shown) filled, not busy |
| `encrypt-journals-not-now` | Plain button under the primary | none | only in the situations in the spec |
| `encrypt-journals-stop-syncing` | Plain button under the primary; unfinished notice | none | no access, server too old, access password wrong or limited; unfinished |
| `encryption-finish` | Try Again on the unfinished notice | none | unfinished, not busy |
| `encryption-cancel` | Cancel on the notice; Cancel of the sheet | Escape on the Mac | notice: before the server is updated; sheet: always |
| `sync-reconnect` | Primary in variant C | none | variant C |
| `add-device` | Done sheet | none | synced |
| `encryption-done` | Done sheet | Return, Escape | always |

## Copy differences

- `library.encrypt.duration` has a `mac` variant without "Keep My Journal open.".
- Otherwise none; the text is the same on all devices (the notice no longer says "this Mac").

## Accessibility

- The heading takes VoiceOver focus when the form appears; reading order is symbol (hidden), heading, paragraph, other devices, fields, note, error, primary, Not Now, Stop Syncing….
- The primary's accessible name is "Encrypt journals" (`library.encrypt.action.accessibilityLabel`); the notice's Cancel is "Cancel encryption". Not Now and Stop Syncing… are plain buttons at the standard minimum hit size and stay reachable without scrolling past the primary at the largest text size.
- Field errors are the field's `errorHint` and are announced 300 ms after focus moves there; the password mismatch is announced when it appears.
- The notice is one status element (label `settings.encryption.progressLabel`, value `settings.encryption.progressValue`). Announcements: `messages.encryption.announce.turningOn` at start, `messages.encryption.announce.updatingServer`, `messages.encryption.announce.done`, every error, and the variant when it replaces the spinner.
- Full Keyboard Access and Tab follow the reading order. Reduce Motion needs nothing beyond the notice's fade.

## Differences between iPhone, iPad and Mac

- Focus: the Mac focuses Master Password after 0.4 seconds; iPhone and iPad do not, because the keyboard would cover the note under the fields.
- Background time and the idle timer exist on iOS only; the Mac is not suspended.
- Cancel on the notice has Escape on the Mac only.
- The notice is new on iPhone and iPad (1.0 covered the app with a sheet); on the Mac it is the former pause notice made device-neutral.

## Screenshots

None. The form, the working notice, the failure and unfinished notices and the Done sheet are captured by `design/spec-screenshots/capture.sh` from a seeded legacy fixture library; screenshots are refreshed by the capture script when the owner says ready. The 1.0 captures of the three-step Turn On Encryption sheet were removed with that sheet.

## Source files

- View: `Views/EncryptJournalsView.swift` (form, Done sheet), `Views/EncryptionNotice.swift` (the working, failed and unfinished notice), `Views/RootView.swift` (routing, sheet), `Views/CreateJournalView.swift` (Start a Journal), `Views/ConnectionView.swift` (`connectionStatus`, `announceForAccessibility`), `Views/PasswordAutofill.swift`.
- Model: `Model/EncryptionUpgrade.swift` (state, variants, texts, announcements, background time), `Model/EncryptionOperations.swift` (readiness, the work, the marker, recovery after interruption, adopting the encrypted copy), `Model/EncryptionRouting.swift` (what each window shows, the sync hold, `writingPausedForEncryption`), `Model/AppModel.swift` (`pauseWriting`, `openReplacedLibrary`), `Model/LibraryOpening.swift` (launch recovery).
- Core: `JournalStore.reencryptedCopy` and `VaultCrypto.makeRecovery` in JournalCore.
- Design: [1-1-encryption-and-passwords.md](../../../../docs/design/1-1-encryption-and-passwords.md), [enable-encryption.md](../../../../docs/design/enable-encryption.md).

## Open questions

See [open-questions.md](../../../open-questions.md), D61 and D62.
