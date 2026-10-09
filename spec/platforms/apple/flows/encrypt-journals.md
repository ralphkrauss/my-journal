---
id: encrypt-journals
title: Encrypt your journals (Apple)
spec: flows/encrypt-journals.md
features: [encrypt-existing-journals]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Model/EncryptionOperations.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/LibraryOpening.swift
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/enable-encryption.md
---

# Encrypt your journals (Apple)

Implements [flows/encrypt-journals](../../../flows/encrypt-journals.md). The form, notice and Done sheet are on [screens/encrypt-journals](../screens/encrypt-journals.md); this page records how the work is run and where each error comes from. It reuses the engine that shipped in 1.0 as Turn On Encryption (`Model/EncryptionUpgrade.swift`, `Model/EncryptionOperations.swift`), which copies first, verifies every row and switches with one configuration write; 1.1 changes who starts it and where it is shown. It was written from the design record (`docs/design/1-1-encryption-and-passwords.md`, sections 3.4 and 3.8) at the same time as the code. The English texts are literals in `Model/EncryptionUpgrade.swift`; the keys named here are the spec's.

## Controls

**Who owns the work.** `EncryptionUpgrade` (`AppModel.encryption`) runs the work in its own `Task`, so closing a sheet does not stop it, and the notice shows where it is. `phase` is `syncing`, `encrypting(Double)` or `updatingServer` (nil when idle); `busy` is `phase != nil || preparing`; Cancel is possible while `busy && phase != .updatingServer`.

**Steps to code.**

1. Check (synced libraries): `checkEncryptionReadiness()` returns an `EncryptionCheck` and requires an unlocked, unencrypted library not being replaced (`!replacingVault`); when connected, the server's public encryption details (format 1 or 2 means variant C and the purge endpoint is never called), the encryption-upgrade capability (else `serverOutdated`) and a device list request (an unauthorized answer becomes `lostAccess`, a timeout or other failure `unreachable`), all inside `withTimeLimit` of about 10 seconds (`AppModel.serverQuestionSeconds`); then `requireSpace(for:)` (the re-encryption size plus 50 MB against the volume's available capacity for important usage, else `notEnoughSpace`). A library with no server skips the check and checks space when Encrypt is chosen.
2. Encrypt: compares the two fields (a difference is a field error on Verify, nothing else runs) and announces `messages.encryption.announce.turningOn`. `AppModel.prepareEncryption(password:current:)` does everything that can be refused before the journals pause (a failure here is shown on the form):
   - `verifyAccessPassword` (recovery format 3 on a server only) opens the library's envelope with the typed access password and compares keys; failure is `incorrectPassword`.
   - A new vault key is generated and the master-password envelope is made with `VaultCrypto.makeRecovery(... formatVersion: 2)` in `Task.detached`.
   - `finishPendingSave()` saves the open entry; a failure is `failed`. `requireSpace(for:)` checks the room.
   The journals then appear with the notice, and `AppModel.runEncryption(_:report:)` (`turnOnEncryption(password:current:report:)` is the two calls together) calls `pauseWriting(true)` and, on any end but an unfinished switch, `pauseWriting(false)`; a failure from here on is shown on the notice:
   - Up to two attempts: when connected, `synchronizeBeforeEncrypting()` syncs repeatedly while a pass still reports images to download and the count keeps falling, then checks the store's missing attachments against the server (`imagesMissing`). Then `encrypt(...)`.
   - `encrypt(...)` writes a marker (`EncryptionUpgradeMarker`: copy folder, the new key's Keychain account, envelope, `contactingServer`) to the configuration, stores the new key in the Keychain, holds synchronization, saves again, and makes the copy with `JournalStore.reencryptedCopy`, reporting `.encrypting(fraction)`; the copy is validated (`validateSchema`, `validateSnapshot`, every row compared decrypted against the source).
   - When connected: `Task.checkCancellation()`, `contactingServer = true` saved to the marker, `.updatingServer` reported (announced once as `messages.encryption.announce.updatingServer`), then `askServerToEncrypt`. A refusal because the server changed triggers the second attempt; a second one becomes `stillSyncing`. `alreadyEncrypted` or a refused device during the first sync is `turnedOnElsewhere`, which switches the form to variant C; a refused password `incorrectPassword`; a rate-limit response `rateLimited`; an unauthorized answer `lostAccess`. If the answer is lost, `serverAdoptionIfAnswered` asks the server for its envelope, bounded, and compares the salt: adopted means carry on, not adopted means `unreachable`, no answer means `unfinished`.
   - `commitEncryption`: one configuration write switches `recovery`, `storageFolder`, `keyID`, sets `recoveryConfirmed`, keeps App Lock and its inactivity time, the last journal and entry and the default journal, clears the marker and records the old library as superseded (`SupersededLibraries.swift`); then `openReplacedLibrary` opens the copy and refreshes (a failed refresh sets the alert text `messages.refresh.encryptionOn`), `pauseWriting(false)`, and sync resumes. The readable folder and the old key are removed once the encrypted library has opened and, if connected, synced.
3. Done: `completed()` clears the three password fields, shows the Done sheet and announces `messages.encryption.announce.done`.

**Errors to messages.** `EncryptionUpgrade.explain(_:)` maps `EncryptionFailure` to the spec's keys, before the journals paused to the form and after to the notice: field errors `messages.encryption.incorrectPassword` and `messages.encryption.rateLimited` (on Current Access Password, with focus); `common.couldntReachHost` for `unreachable` on the form and the notice; `messages.encryption.serverOutdated` (host capitalised); `messages.encryption.notEnoughSpace` (size from `ByteCountFormatter`, file style); `messages.encryption.accessLost`; `turnedOnElsewhere` switches the form to variant C with `library.encrypt.messageSignIn`; `messages.encryption.stillSyncing` for `stillSyncing` and `serverChanged`; `messages.encryption.imagesMissing`; `messages.encryption.background`; `messages.encryption.unfinished`; `messages.encryption.failed` for `failed` and anything unknown. Which errors offer Not Now and Stop Syncing… is the table in the spec. Every message is stored and announced (`announceForAccessibility`).

**Unfinished.** When the server may have switched, `encrypt` closes the staged copy and throws `unfinished`; `explain` then sets `unfinished`, and the journals stay read-only with the notice (Try Again, Stop Syncing…). A saved marker with the server switched takes precedence over the form at launch (`finishOpening()` calls `encryption.finishAfterLaunch()`), so the next launch tries to finish by itself first and shows the notice only if that fails. Try Again calls `finish()` → `finishInterruptedEncryption()`: no connection removes the copy; otherwise a bounded question to the server: not switched discards the copy and nothing changed; switched validates the staged copy from its folder and commits; no answer in time leaves the state unfinished with the same two buttons. Stop Syncing… on this notice is `stopSyncingAfterUnfinishedEncryption` (one bounded question, then commit or discard, then `stopSyncing()`), not `AppModel.stopSyncing` alone, which starts with `guard ... !replacingVault`. `discardUnsentEncryptionCopy()` (`LibraryOpening`) removes a copy whose marker never reached `contactingServer` at launch.

**Cancel and lock.** Cancel cancels the task; the `encrypt` catch path discards the staged copy and the Keychain key and `runEncryption` releases the pause; the plain form returns and Not Now is not unlocked. `stopForLock()` (observing `AppModel.$locked`) does the same when Cancel is possible; once the server is being updated a lock does not stop it.

**Background time (iOS only).** `run` calls `UIApplication.beginBackgroundTask(withName:)`. When time runs out while Cancel is still possible, `backgroundExpired` is set and the task cancelled; the cancellation then reports `messages.encryption.background`, with Try Again and Not Now. A run stopped while the server is being asked ends as unfinished, never as lost journals (the test `testBeingStoppedWhileTheServerIsAskedEndsUnfinishedNotLost`). `isIdleTimerDisabled` is set while the work runs and restored on every exit. On the Mac `beginBackgroundTime` is a no-op. With App Lock on, leaving the app on iPhone or iPad locks first (`applicationEnteredBackground` → `lockImmediately`), `stopForLock` cancels the work, and no message is shown because `backgroundExpired` is false.

**Other devices.** After success another device sees the sync state `messages.sync.signInNeeded` and uses Reconnect… (`sync-reconnect`); `AppModel.lostAccess` tells a refused device that encryption was turned on elsewhere, and `reencryptForRejoin` encrypts that device's own journals while it reconnects, showing the same `EncryptionProgressRow` in Connect to a Server (`ConnectionBusyRow`).

## Layout

See [screens/encrypt-journals](../screens/encrypt-journals.md): the form is the window at launch and a sheet from Settings; the notice is on every device.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `turn-on-encryption` | as in [commands.md](../commands.md) | none | not encrypted, unlocked, not replacing the journals |
| `encrypt-journals` | as in commands.md | Return in Verify | check passed, fields filled, not busy |
| `encrypt-journals-not-now` | as in commands.md | none | only where the form cannot succeed or has failed |
| `encrypt-journals-stop-syncing` | as in commands.md | none | no access, server too old, access password wrong or limited; unfinished |
| `encryption-finish` | as in commands.md | none | unfinished |
| `encryption-cancel` | as in commands.md | Escape (Mac) | before the server is asked |
| `encryption-done` | as in commands.md | Return, Escape | Done sheet |
| `sync-reconnect` | as in commands.md | none | variant C |

## Copy differences

None beyond `library.encrypt.duration`'s Mac variant (see the screen page).

## Accessibility

Announcements are posted from `EncryptionUpgrade` (`announceForAccessibility`): encrypting, updating the server, done, every error, and field errors 300 ms after focus has moved. Progress is one element on the notice. See the screen page.

## Differences between iPhone, iPad and Mac

- Background time, the idle timer and the background error exist on iOS only, because only iOS suspends the app.
- An unfinished switch is shown by the same notice on every device (1.0 showed a sheet over the app on iPhone and iPad and Settings plus a notice on the Mac).

## Screenshots

None. The first screens are captured on [screens/encrypt-journals](../screens/encrypt-journals.md) when the capture script has been run; the failure, unfinished and progress states are not captured.

## Source files

- View: `Views/EncryptJournalsView.swift` (form, Done sheet), `Views/EncryptionNotice.swift` (notice).
- Model: `Model/EncryptionUpgrade.swift` (state machine, variants, texts, announcements, background time), `Model/EncryptionOperations.swift` (readiness, the work, the marker, recovery after interruption, adoption), `Model/EncryptionRouting.swift`, `Model/AppModel.swift` (`pauseWriting`, `openReplacedLibrary`, `sync()` hold), `Model/LibraryOpening.swift` (launch recovery).
- Core: `JournalStore.reencryptedCopy`, `VaultCrypto.makeRecovery`, `ServerClient.turnOnEncryption` and `recoveryParameters` in JournalCore.
- Design: [1-1-encryption-and-passwords.md](../../../../docs/design/1-1-encryption-and-passwords.md), [enable-encryption.md](../../../../docs/design/enable-encryption.md).

## Open questions

See [open-questions.md](../../../open-questions.md).
