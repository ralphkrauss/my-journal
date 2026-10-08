---
id: turn-on-encryption
title: Turn on encryption (Apple)
spec: flows/turn-on-encryption.md
features: [turn-on-encryption]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Model/EncryptionOperations.swift
  - apps/apple/JournalApp/Views/TurnOnEncryptionView.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/LibraryOpening.swift
  - docs/design/enable-encryption.md
---

# Turn on encryption (Apple)

Implements [flows/turn-on-encryption](../../../flows/turn-on-encryption.md). The sheet's controls and layout are on [screens/turn-on-encryption](../screens/turn-on-encryption.md), with its captures; this page records how the work is run and where each error comes from. The English texts are literals in `Model/EncryptionUpgrade.swift`; the keys named here are the spec's.

## Controls

**Who owns the work.** `EncryptionUpgrade` (`Model/EncryptionUpgrade.swift`) is an `ObservableObject` held by `AppModel.encryption`. It runs the work in its own `Task` (`run(_:_:)`), so closing the sheet does not stop it and `present()` on an unfinished or busy upgrade shows where it is instead of resetting. `phase` is `EncryptionPhase?` (`checking`, `syncing`, `encrypting(Double)`, `updatingServer`); `busy` is `phase != nil`; `canCancel` is `phase != .updatingServer && !unfinished`.

**Steps to code.**

1. Continue: `continueFromAbout()` runs `.checking` around `AppModel.checkEncryptionReadiness()`: requires an unlocked, unencrypted library not being replaced; `requireSpace(for:)` (the re-encryption size plus 50 MB against the volume's available capacity for important usage, else `notEnoughSpace`); when connected, a status request that must list the encryption-upgrade feature (else `serverOutdated`) and a device list request (an unauthorized answer becomes `lostAccess`, any other failure `unreachable`). On success `path = [.password]` and focus is requested for Current Access Password or Master Password.
2. Turn On: `turnOn()` first compares the two fields (a difference is a field error on Verify, nothing else runs), announces `messages.encryption.announce.turningOn`, and runs `.syncing` (synced) or `.encrypting(0)` around `AppModel.turnOnEncryption(password:current:report:)`:
   - `verifyAccessPassword` (only for recovery format 3) opens the library's envelope with the typed access password and compares keys; failure is `incorrectPassword`.
   - `finishPendingSave()` saves the open entry; a failure is `failed`.
   - A new vault key is generated and the master-password envelope is made with `VaultCrypto.makeRecovery(... formatVersion: 2)` in `Task.detached`.
   - Up to two attempts: when connected, `synchronizeBeforeEncrypting()` syncs repeatedly while a pass still reports images to download and the count keeps falling, then checks the store's missing attachments against the server (`imagesMissing`). Then `encrypt(...)`.
   - `encrypt(...)` writes a marker (`EncryptionUpgradeMarker`: copy folder, new key's Keychain account, envelope, `contactingServer`) to the configuration, stores the new key in the Keychain, calls `pauseWriting(true)`, holds synchronization, saves again, and makes the copy with `JournalStore.reencryptedCopy`, reporting `.encrypting(fraction)`.
   - When connected: `Task.checkCancellation()`, `contactingServer = true` saved to the marker, `.updatingServer` reported (announced once as `messages.encryption.announce.updatingServer`), then `askServerToEncrypt`. A refusal because the server changed (`serverChanged`) triggers the second attempt; a second one becomes `stillSyncing`. `alreadyEncrypted` is `turnedOnElsewhere`; a refused password `incorrectPassword`; a rate-limit response `rateLimited`; an unauthorized answer `lostAccess`. If the answer is lost, `serverAdopted` asks the server for its envelope and compares the salt: adopted means carry on, not adopted means `unreachable`, unknown means `unfinished`.
   - `commitEncryption`: one configuration write switches `recovery`, `storageFolder`, `keyID`, sets `recoveryConfirmed` and `passwordChecked`, clears the marker and records the old library as superseded; then `openReplacedLibrary` opens the copy and refreshes (a failed refresh sets the alert text `messages.refresh.encryptionOn`), `pauseWriting(false)`, and sync resumes.
3. Done: `completed()` clears the three password fields, appends `.done` to `path` and announces `messages.encryption.announce.done`.

**Errors to messages.** `EncryptionUpgrade.explain(_:)` maps `EncryptionFailure` to the spec's keys: field errors `messages.encryption.incorrectPassword` and `messages.encryption.rateLimited` (on Current Access Password, with focus); `messages.encryption.unreachable` on step 2 or `common.couldntReachHost` text on step 1 (the code branches on `path.isEmpty`); `messages.encryption.serverOutdated` (host capitalised); `messages.encryption.notEnoughSpace` (size from `ByteCountFormatter`, file style); `messages.encryption.accessLost`; `messages.encryption.turnedOnElsewhere` (also sets `turnedOnElsewhere` and `errorOffersSignIn`); `messages.encryption.stillSyncing` for `stillSyncing` and `serverChanged`; `messages.encryption.imagesMissing`; `messages.encryption.unfinished`; `messages.encryption.failed` for `failed` and anything unknown. Every message goes through `report(_:)`, which stores it for the current step and announces it.

**Unfinished.** When the server may have switched, `encrypt` closes the staged copy and throws `unfinished`. `explain` then sets `unfinished`, forces `path = [.password]` and presents the sheet if it is not showing: over the app on iOS (`presentedOverApp`), through `showProgress()` on the Mac. Try Again calls `finish()` → `finishInterruptedEncryption()`: no connection removes the copy; otherwise `serverAdopted`: not adopted discards the copy and nothing changed; adopted validates the staged copy from its folder and commits. At launch `discardUnsentEncryptionCopy()` (`LibraryOpening`) removes a copy whose marker never reached `contactingServer`, and `finishOpening()` calls `encryption.finishAfterLaunch()` when `encryptionUnfinished`.

**Cancel and lock.** Cancel cancels the task and closes the sheet; the `encrypt` catch path discards the staged copy and the Keychain key, and un-pauses writing. `stopForLock()` (observing `AppModel.$locked`) does the same when `canCancel`; once the server is being updated a lock does not stop it.

**Background time (iOS only).** `run` calls `UIApplication.beginBackgroundTask(withName: "Turn on encryption")`. When time runs out and `canCancel && busy`, `backgroundExpired` is set and the task cancelled; the cancellation then reports `messages.encryption.background`. On the Mac `beginBackgroundTime` is a no-op. With App Lock on, leaving the app on iPhone or iPad locks first (`applicationEnteredBackground` → `lockImmediately`), `stopForLock` cancels the work and closes the sheet, and no message is shown because `backgroundExpired` is false.

**Other devices.** After success another device sees the sync state `messages.sync.signInNeeded` and uses Sign In… (`sync-reconnect`); `AppModel.lostAccess` is what tells a refused device that encryption was turned on elsewhere, and `reencryptForRejoin` encrypts that device's own journals while it signs in, showing the same `EncryptionProgressRow` in Connect to a Server (`ConnectionBusyRow`).

## Layout

See [screens/turn-on-encryption](../screens/turn-on-encryption.md): sheet on every device, the Mac notice bar in the journal window.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `turn-on-encryption` | as in [commands.md](../commands.md) | none | not encrypted, unlocked, not replacing the journals |
| `encryption-continue` | as in commands.md | Return per commands.md | not busy |
| `encryption-turn-on` | as in commands.md | Return in Verify | both fields filled (and current password if asked), not busy |
| `encryption-finish` | as in commands.md | none | unfinished |
| `encryption-cancel` | as in commands.md | Escape (system sheet) | before the server is asked, not unfinished |
| `encryption-done` | as in commands.md | none | last step |
| `show-encryption-progress` | as in commands.md | none | Mac only |
| `sync-reconnect` | as in commands.md | none | the error says encryption was turned on elsewhere |

## Copy differences

None beyond the Mac notice wording on [screens/turn-on-encryption](../screens/turn-on-encryption.md).

## Accessibility

Announcements are posted from `EncryptionUpgrade` (`announceForAccessibility`): turning on, updating the server, done, every general error, and field errors 300 ms after focus has moved. Progress is one element on the sheet. See the screen page.

## Differences between iPhone, iPad and Mac

- Background time and the background error exist on iOS only, because only iOS suspends the app.
- An unfinished switch is shown by a sheet over the app on iPhone and iPad and by Settings plus the notice on the Mac, because the Mac has a separate Settings window and a journal window to explain the pause in.
- Cancel is always visible on the Mac and only where Back is missing on iOS.

## Screenshots

None. This flow shares its id with the screen; the first step's captures are listed on [screens/turn-on-encryption](../screens/turn-on-encryption.md). The later steps, errors and progress are not captured.

## Source files

- View: `Views/TurnOnEncryptionView.swift` (sheet, steps, presenter, Mac notice).
- Model: `Model/EncryptionUpgrade.swift` (state machine, texts, announcements, background time), `Model/EncryptionOperations.swift` (readiness, the work, the marker, recovery after interruption), `Model/AppModel.swift` (`pauseWriting`, `openReplacedLibrary`), `Model/LibraryOpening.swift` (launch recovery).
- Core: `JournalStore.reencryptedCopy`, `VaultCrypto.makeRecovery`, `ServerClient.turnOnEncryption` and `recoveryParameters` in JournalCore.
- Design: [enable-encryption.md](../../../../docs/design/enable-encryption.md).

## Open questions

See [open-questions.md](../../../open-questions.md).
