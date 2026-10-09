# 1.1: every library is encrypted, one Change Password, one update message, fewer old migrations

Status: revised after the independent review of 2026-10-09 (recorded at the end of this file, with the changes it caused in "Changes after review"); needs a second review before anything is built. Step 1 of the design gate in [AGENTS.md](../../AGENTS.md). Covers simplifications G, J, C and D of [release-1-1-scope.md](release-1-1-scope.md) (owner-approved 2026-10-07). No code, test, spec or protocol file changes with this record; section 7 lists what the implementation changes.

Version 1.0 (build 19) is public before 1.1 ships, so real people will open their 1.0 libraries in 1.1. Three rules decide every choice below:

1. **Nothing is lost, discarded or silently changed, and nobody is locked out of their own journals.** Every 1.0 library opens in 1.1 with every entry, image, version, conflict and identity intact. Where 1.1 must change a library (encrypting it), it makes a verified copy first and switches in one step; a crash leaves the old library as it was. Where encryption can't run or has failed, the person gets their journals back.
2. **The person decides what is secret, so the person chooses the password.** The app never invents a master password or encrypts under a key the person can't recover.
3. **A change in 1.1 must work against 1.0 devices and servers that haven't changed.** The sync protocol, the archive format and the server are untouched by this record.

## 1. Summary

| | Change |
| --- | --- |
| G | Start a Journal has one step (Choose a Master Password). Connect to a Server loses Protect Your Journals. A library that isn't encrypted (made by 1.0 or earlier with Continue Without Encryption, or restored from an unencrypted 1.0 archive) is encrypted by a screen, **Encrypt Your Journals**, shown at launch before the journals. It reuses the machinery of Turn On Encryption, so nothing new can lose data. The journals stay readable while it works (writing is paused, as in 1.0). A healthy library sees only **Encrypt**; **Not Now** appears only where encryption can't run or has failed (the person's own Cancel doesn't count), and opens the journals exactly as 1.0 did. In 1.1, G therefore means "no new unencrypted libraries; existing ones are asked to encrypt": because the exit exists, unencrypted libraries and their code persist for 1.0 holders and are removed in a later release (section 3.7; owner confirmation in section 9). New devices and encrypted libraries never join a server that holds unencrypted data. |
| J | Check Your Password and its Set New Password page go. Change Password gains **Forgot Password?** (journals only on this device, after the device owner authenticates). Export Archive points to Change Password and its success message says to keep the password with the archive. |
| C | Every "this version is too old" state says "Update My Journal". Three texts change, and Pin, Unpin and Move Journal failures from a newer-version library say so (A8). |
| D | Build 16 is the floor, and the result is small: only the old Mac window-layout strings go. The App Lock PIN migration and the local agent cleanup stay, because removing them silently turns protections off or leaves credentials behind. Database schema migrations can't go at all. Section 6 lists both sides and a build 16 fixture proves 1.0 libraries still open. |
| Owner decisions | Two (section 9): confirm what G means in 1.1 (no new unencrypted libraries, existing ones asked to encrypt, Not Now only when it can't succeed, full removal later), and a minimum length of 8 for **new** master passwords. |

## 2. What a 1.0 library can be

The library's format is in `LocalConfiguration.recovery.formatVersion` (`Packages/JournalCore/Sources/JournalCore/Crypto.swift`, `JournalApp/Model/LocalConfiguration.swift`; [protocol/README.md](../../protocol/README.md), formats 1 to 4).

| Format | Called in the app | Content | Created by | In 1.0 data | 1.1 |
| --- | --- | --- | --- | --- | --- |
| 2 | Master Password | encrypted | Start a Journal and Connect to a Server, every build from 9 to 19 | nearly all libraries | opens as today |
| 4 | none | readable | Continue Without Encryption and Don't Encrypt, every build from 9 to 19 | yes: anyone who chose it | **Encrypt Your Journals** (the form) |
| 3 | Access Password | readable, with a password only a server checks | builds before 9 | only a tester who kept an early library | **Encrypt Your Journals**; asks for the access password only when the library is on a server |
| 1 | Recovery Key | encrypted | builds before 9 | same | opens as today; no conversion (open question D10, resolved 2026-10-09) |

`NewVault.prepare` makes format 2 when a password is given and format 4 when none is (`JournalApp/Model/NewVault.swift:18`; the only callers, `CreateJournalView` and `ConnectionFlow.setUp`, pass a password exactly when they encrypt; checked in the build 9 and build 16 sources). Formats 1 and 3 are therefore old test libraries, and they must still open because 1.0 opens them.

## 3. G: every library is encrypted

### 3.1 Current behaviour

- **Start a Journal** (`Views/CreateJournalView.swift`; `spec/flows/create-library.md`): step 1 "Protect Your Journals" offers Use Encryption and, as a link with a warning under it, Continue Without Encryption (lines 55 to 64), which creates a format 4 library at once.
- **Connect to a Server** (`Model/ConnectionFlow.swift`, `Views/ConnectionSteps.swift`): on a device with no library, the step `.protect` (lines 207 to 220) offers Encrypt or Don't Encrypt (`encrypt` flag, `continueFromProtect`). Servers set up without encryption have their own sign-in: Add This Device for a passwordless server and Use a Recovery Code (`passwordless`, `.recoveryCode`).
- **Settings ▸ Privacy** (`Views/TurnOnEncryptionView.swift:5-44`): "Encryption Is Off" with **Turn On Encryption…**, or **Sign In…** when the server was encrypted elsewhere.
- **Turn On Encryption** (`Model/EncryptionUpgrade.swift`, `Model/EncryptionOperations.swift`, `Views/TurnOnEncryptionView.swift`; [enable-encryption.md](enable-encryption.md)): a three-step sheet, the work owned by the app. It encrypts a full copy under a **new** key with every identity kept, verifies it, asks the server (capability `encryption-upgrade`) to purge and re-key, then switches with one configuration write; the plaintext library is removed once the copy has opened and synced (`SupersededLibraries.swift`). Interrupted runs recover at the next launch (`EncryptionUpgradeMarker`). Other devices sign in with the master password and encrypt their own copy, matched by content.
- **Restoring an archive** onto a device with no journals installs the archive's own library, so an unencrypted archive makes an unencrypted library (`Model/ArchiveInstalling.swift:98-114`). Importing it as new journals into an existing library already encrypts the journals with that library's key (`importAsNewJournals`).
- **Unencrypted servers** are joined by a device whose library is unencrypted (`Model/ServerEnvelopeCheck.swift` refuses only an encrypted library).
- **After encryption is turned on from another device**, a device with an unencrypted library gets `SyncHealth.signInNeeded` (`messages.sync.signInNeeded`) and `EncryptionUpgrade.turnedOnElsewhere` (`messages.encryption.turnedOnElsewhere`), two texts for one state (open question B6).

### 3.2 Decision: a screen that asks once, with an exit when it can't succeed

An unencrypted library can't be encrypted without the person's password and, when it is synced, without a pass over the server, so something must ask. Options considered:

- *A background upgrade with a generated password.* Rejected: a password the person never saw is a recovery key they don't have (rule 2), and it would change the library silently.
- *A banner or Settings prompt the person may ignore.* Rejected as the only mechanism: the app would show "Encryption Is Off" and keep every unencrypted state alive for as long as people ignore it.
- *A screen that blocks the journals with no way past it.* Rejected after review. It turns every environmental failure (a nearly full phone, a server that is gone, a flaky link, a latent defect in one library) into being locked out of one's own writing, which breaks rule 1 and "works offline".
- *Encrypt locally and defer only the server switch.* Rejected: the server step needs a complete plaintext sync before the purge, and an encrypted library must never talk to a plaintext vault (SYNC-2 in [enable-encryption.md](enable-encryption.md)). A split state would need new reconciliation code that mixes protection modes, the highest data-loss surface in the product.
- *A screen at launch with a conditional exit.* Chosen. A healthy library sees one decision and one button, **Encrypt**. Where the screen cannot succeed (offline or unreachable server, a server that is too old, no access, not enough space) or has failed once, it also offers **Not Now**, which opens the journals exactly as 1.0 did and asks again at the next launch. While encrypting, the journals stay readable and only writing is paused, as in 1.0.

**Consequence the record accepts:** because Not Now is a full 1.0 library, the unencrypted code paths (the Settings entry, the readable-archive authentication, the unencrypted footers, sync with an unencrypted server, `SyncHealth.signInNeeded`) all stay in 1.1. Only what makes *new* unencrypted libraries goes now. Section 3.7 lists both, and says when the rest can go.

### 3.3 Start a Journal (new libraries)

One sheet, no first step.

- **Layout, all devices.** The sheet that was step 2: a key symbol (decorative); heading `common.chooseMasterPassword`; `library.createLibrary.explanation`; the Master Password and Verify fields (`MasterPasswordFields`) with Show Password; `library.createLibrary.advice`; red error text; `library.createLibrary.creating` with a progress indicator while working. Toolbar: Cancel (`common.cancel`) and Create (`common.create`, Return). iPhone and iPad no longer push a page; the Mac no longer has Back. The first field takes focus when the sheet appears.
- **Both fields are new-password fields.** `passwordAutofill(creating: true)` on both (the `.newPassword` content type), so iOS and macOS can offer a generated password. The specification asks for this on every screen that chooses a password (here, Encrypt Your Journals, Change Password and the new fields after Forgot Password?). Whether the system offers and saves a strong password for an app with no associated domain is **unverified**: the project declares no Associated Domains entitlement and `passwordAutofill(creating:)` only sets the content type. It is checked on a real iPhone and Mac before the spec states it; until then the spec makes no promise, and the minimum length (section 9), Verify, the note under the fields and the Done line carry the weight.
- **Rules.** Create is enabled when both fields are filled; a mismatch shows `messages.connection.passwordsDontMatch` under the fields, announces it and moves focus to Verify. A password shorter than the minimum for new passwords shows `messages.password.tooShort` under the first field and moves focus there, checked when Create is chosen (never live while typing); the minimum is the owner decision in section 9 (recommended: 8 characters). Existing shorter passwords keep working everywhere.
- **Sizes.** Mac sheet 520 × 580 points as step 2 is today; iOS sheet as today.
- **Removed:** `common.protectYourJournals`, `library.createLibrary.useEncryption`, `library.createLibrary.continueWithout`. `CreateJournalView` loses `choosingPassword`, `pushesPasswordStep`, `create(encrypted:)`; `AppModel.start(password:encrypted:)` takes a password only; `NewVault.prepare(in:password:)` no longer makes format 4 or 3 (the unencrypted branch moves to `LibraryFixture`, where tests still need it).
- **Connect to a Server with no library:** Set Up Server → Choose a Master Password → Set Up. `.protect`, `ConnectionFlow.encrypt` and `continueFromProtect` go; `stepAfterSetupCode` returns `.choosePassword` when there is no library. Copy removed: `settings.connect.protect.*` (choice, encrypt, dontEncrypt, encryptDetail, intro). The merge footers for an unencrypted device (`settings.connect.merge.footerUnencrypted`, `.footerWillEncrypt`) stay while Not Now exists.

### 3.4 Encrypt Your Journals (existing unencrypted libraries)

#### Overview

1. **The form** appears at launch, once the library is open and the person is past the lock screen. It takes the place of the journals. A healthy library sees a paragraph, a password pair and **Encrypt**.
2. **Working.** After Encrypt, and once the free-space and server checks pass, the journals appear **read-only** with a notice at the top that shows the progress and a Cancel. Writing is paused (the same pause 1.0 used while encrypting); reading, searching and exporting work.
3. **Done.** A sheet confirms, with what to keep safe and what happens to other devices.
4. **Exits.** **Not Now** (conditional, below) opens the journals as 1.0 did. The person's own **Cancel** returns to the plain form and never unlocks Not Now. A failed run returns the journals to full use, unchanged, with a notice offering Try Again and Not Now. An **unfinished** run (the server switched but this device could not finish) keeps the journals read-only with a notice offering Try Again and Stop Syncing….

**Definitions.** *Launch* means a cold start of the app process. Not Now is held in memory only: backgrounding, unlocking, a new Mac window or the network returning don't clear it, and nothing stores it. There is no "remember my choice" setting; that would silently become permanent. *Presentation:* at launch (and for variant C re-entry) the form is the root screen; opened by the person from Settings ▸ Turn On Encryption…, or after Not Now in this launch, it is a **sheet over the journals with Cancel** (Escape on the Mac), so it can never trap anyone. *Precedence:* a saved encryption marker or a run in progress comes before the form (below).

The window shows, in this order (`Views/RootView.swift`, `spec/screens/welcome.md`): opening progress, lock screen, library problem screen, first-launch screen, **a saved encryption marker with the server switched, or a run in progress (the journals read-only with the notice, below)**, **Encrypt Your Journals (the form, only when there is no marker)**, recovery key, journals. A library whose server already switched must be allowed to finish before it is offered the form (variant C would otherwise appear first). The form is also shown after **Restore Journals** from an unencrypted 1.0 archive onto a device with no journals: the restore installs the archive as it is, then this screen encrypts it (section 3.5).

While the form shows:

- no sync runs. This is new code: today `finishOpening` starts synchronization at launch. The hold is a gate in `sync()` itself, not only in the automatic loop (`synchronizeAutomatically`), because `sync()` is also called from export preparation (`JournalLifecycleView`), `EntryRecoveryNotice` and the Sync Now rows; it also covers `AgentCopyPublisher`, which asks to publish after a sync (the existing `waitsForPerson` flag is the precedent). The hold ends when the person chooses Not Now or when encryption starts (it syncs once itself, first, so nothing on the server is missed: `synchronizeBeforeEncrypting`). A test makes sure no sync or write request reaches a server before then; the readiness check and `finishAfterLaunch` legitimately read it.
- the form is the same in every window of the app, because the state belongs to the app, not to a window;
- Mac menu commands that need a library are disabled, as on the first-launch screen, and Import Archive… is disabled too. A `.journalarchive` opened from outside the app (`onOpenURL`, a Finder double-click) waits, as `pendingArchive` already waits for the lock and for a library problem, until the form and any run are over, then offers the import (`openPendingArchive` gains this condition);
- Settings shows `settings.encryptFirst` ("Choose a master password to encrypt your journals first.") in place of its panes. Once Not Now has been chosen, Settings is normal;
- the library's content is unchanged until the person starts the encryption (the housekeeping every open already does, such as numbering journals that share a name, still runs).

#### The form (iPhone, iPad, Mac)

A centred column, at most 480 points wide, scrolling at large text sizes, like Start a Journal. Order:

1. Lock-shield symbol (decorative).
2. Heading `library.encrypt.title`.
3. A paragraph that depends on the variant (below).
4. **Your Other Devices** (variant B only): a section `settings.encryption.otherDevices.header` with `settings.encryption.otherDevices.update`, `settings.encryption.otherDevices.signIn`, `settings.encryption.otherDevices.agents`.
5. Fields (variants A and B): Current Access Password (only a library with an access password that is on a server), Master Password, Verify (both new-password fields), Show Password. On the Mac focus lands in Master Password about 0.4 seconds after the screen appears; on iPhone and iPad it doesn't (the keyboard and the strong-password bar would cover the note under the fields, and VoiceOver already lands on the heading). Return moves Master Password → Verify → Encrypt.
6. **Directly under the fields:** `library.createLibrary.advice` (variant A) or `settings.password.footer` (variant B). In variant A the fields, this note and the Encrypt button fit the first screen of the smallest supported iPhone at the default text size without scrolling; variant B starts with the other-devices section and scrolls. Under the note, `library.encrypt.duration`. The primary button follows; with the keyboard up the note stays visible above it.
7. An error in red, selectable, when there is one.
8. The primary button, large and prominent: `library.encrypt.action` ("Encrypt"; its accessible name is "Encrypt journals"), `common.tryAgain` after an error, `common.signIn` in variant C.
9. Plain text buttons, at least the standard minimum hit size, below the primary button and always reachable without scrolling past it at the largest text size: **Not Now** (`library.encrypt.notNow`), and **Stop Syncing…** (`settings.sync.stopSyncing`), each only in the situations listed below.

No toolbar buttons: there is no sheet to dismiss. iPhone and iPad ask the system for background time while working, and stop with `messages.encryption.background` if it runs out before the server is updated (as today).

**Variants**

| | When | Paragraph |
| --- | --- | --- |
| A | No server | `library.encrypt.message` |
| B | A server that doesn't use encryption yet | `library.encrypt.messageSynced` |
| C | The server already uses encryption (another device turned it on, or the server was replaced) | `library.encrypt.messageSignIn`; no fields; primary Sign In… |
| D | A synced library whose server can't be used right now | the B paragraph, the error, no fields until the check passes |

A synced library first shows "Checking {host}…" (`settings.encryption.checking`) with a spinner in place of the fields. The app reads the server's public encryption details and checks that this device still has access, that the server supports `encryption-upgrade`, and that there is enough free space. **The check is bounded at about 10 seconds** for the variant decision; if it hasn't finished, the screen becomes variant D with `common.couldntReachHost`, and a late answer only enables Try Again. **Not Now appears sooner**: as soon as the check fails, when the system reports no network path, or after about 3 seconds, whichever comes first, so a flaky link never holds the journals back for the full bound at every cold start. The result chooses B, C or D, and VoiceOver announces which one replaced the spinner, not only a final error. A library with no server skips this and shows A at once, though it still checks free space when Encrypt is chosen.

**Sign In… (variant C)** opens Connect to a Server over the screen with this server chosen and checked, at the Enter Master Password step, exactly as Settings ▸ Sync's Sign In… does today (`EncryptionPresentation`, `flows/reconnect-to-server.md`, "Encryption turned on elsewhere"). Signing in encrypts this device's own library with the server's key, keeping identities and unsynced changes, and the screen gives way to the journals when it finishes. Use a Connected Device Instead… works there as today, and a replaced server that holds another library still gets Merge Journals before anything is sent. Its intro and footer are `settings.connect.signIn.introEncrypted` and `settings.connect.signIn.footerEncrypted`, unchanged.

**Not Now** opens the journals exactly as 1.0 did: editing works, sync resumes as before (an unencrypted library with its unencrypted server, or the Sign In state of variant C with the messages 1.0 has), App Lock is as it was. It is offered only where the form cannot succeed or has not:

| Situation | Not Now |
| --- | --- |
| The check passed (healthy B, or A without a server) | Not shown |
| The check didn't finish in about 10 seconds; the server is unreachable, too old, or this device has no access | Shown |
| Not enough free space | Shown |
| Wrong or limited access password | Shown |
| Variant C (it needs a password the person may not have) | Shown |
| A run in this launch **failed** (`failed`, `stillSyncing`, `imagesMissing`, `background` expiry, unreachable, a lock-triggered stop that left an error) | Shown (on the form, or on the failure notice) |
| The person pressed **Cancel** on a working run | Not by itself: back to the plain form; Not Now only if the check conditions above already offer it |
| Unfinished | Not offered: the journals are already open read-only (below) |

Two consequences are by design. Going offline offers Not Now ("works offline" requires it), and that is the only deliberate way a healthy synced library stays unencrypted. And a person who keeps choosing Not Now because their server is too old or gone sees the form again at every cold start (one extra tap, most often on iPhone, where the system ends the process); Stop Syncing… (non-transient states) and Sign In… (variant C) stay prominent as the ways out. Not Now is not remembered: the form is shown again at the next launch. Until then, Settings ▸ Privacy keeps the 1.0 entry for an unencrypted library, **Turn On Encryption…** (`settings.privacy.encryption.turnOn`), which opens the form as a sheet with Cancel, and **Sign In…** in variant C.

**Stop Syncing…** is for states that will not pass by themselves, and is irreversible in practice, so it is offered only with: this device has no access to the server; the server is too old; the access password is wrong or limited. It is not offered for an unreachable server (use Not Now and try again later). It opens the existing confirmation (`settings.sync.stopSyncing.title`, buttons `settings.sync.stopSyncing.confirm` and `common.cancel`) with `library.encrypt.stopSyncing.message`, followed as today by `settings.sync.stopSyncing.messageUnsent` when items haven't reached the server. The message states the consequence: this device can't sync with that server again (an encrypted library is refused by a server without encryption), the other devices keep using it and won't get changes made here, and the journals stay here and are encrypted next. The record corrects `flows/stop-syncing.md` for this entry point, which otherwise promises that connecting again continues by identity. For a server that is too old, the error says first that updating it is the way to keep syncing, because the person is usually its administrator. Confirming runs the existing Stop Syncing (`flows/stop-syncing.md`); the screen becomes variant A. Nothing is deleted anywhere.

#### While encrypting

The journals are visible and read-only **from the moment Encrypt is chosen**. The engine changes for this to be true: today `pausesWriting` is true only while encrypting, updating the server or unfinished, and `pauseWriting(true)` is called inside `encrypt` after `synchronizeBeforeEncrypting`, so 1.0 allowed writing while checking and syncing. In 1.1 `pauseWriting(true)` is called at Encrypt, after the final flush and before the pre-sync, and released on every exit (cancel, failure, Not Now, done); `turnOnEncryption` and `checkEncryptionReadiness` guard on `!replacingVault`, so the order matters and is tested. Reading is live until the copy starts: incoming sync during the Syncing phase may change the list under the reader. Every writing control is disabled **with a reason** on all three devices (today many `replacingVault` guards just return, which would leave tappable dead buttons: new entry, delete, image insertion, move, restore, pin, import). On iPhone and iPad this is a new surface, not a reuse: 1.0 covered the app with a modal sheet, so a read-only list, editor and search behind a notice is new and gets its own screenshots. A notice sits at the top of the journal window (Mac), above the content in every stacked screen and column (iPhone and iPad): the text `messages.writingPaused.encrypting`, the status row (Checking, Syncing…, the determinate "Encrypting your journals…" bar, "Updating {host}…"), and **Cancel** (`common.cancel`, accessible name "Cancel encryption" so it isn't confused with cancelling something in the journals behind it, Escape on the Mac), disabled while the server is being updated. At accessibility text sizes the notice stacks (text, progress, button). The editor shows the read-only note it showed in 1.0 while writing is paused. This is the Mac pause notice of 1.0 (`EncryptionPauseNotice`), made device-neutral and shown on iPhone and iPad too; the sheet over the app and Show Progress are no longer needed because the progress is in the notice.

Cancel stops the work (until the server step), releases the pause and shows the plain form again; it never unlocks Not Now by itself (finding 1 of the second review). A failure removes the staged copy, resumes writing, and turns the notice into the error with **Try Again** and **Not Now** (Not Now dismisses the notice; the Settings entry stays). The password is held in memory only while the notice or form is up. On iPhone and iPad the idle timer is disabled while the work runs (as `AddDeviceView` does) and restored on every exit, so Auto-Lock can't send the app to the background mid-copy and loop on `messages.encryption.background`.

**Unfinished** (the server switched but this device could not open its encrypted copy, for example the disk filled, or the server is gone after the purge): the journals stay read-only; the notice shows `messages.encryption.unfinished` with **Try Again** and **Stop Syncing…**. Both local copies are complete and verified at that point, so Stop Syncing here is **its own operation, not `stopSyncing`** (which starts with `guard ... !replacingVault`, and this state is `replacingVault == true`): one bounded `serverAdopted` check first; if the server answers "switched" or can't answer, it commits the staged encrypted copy (as `commitEncryption` does) and then removes the connection; if it answers "not switched", nothing was lost and no adoption is needed, so it keeps the original library, discards the copy and drops the connection. The confirmation uses `library.encrypt.adopt.message`, which fits both. `finishInterruptedEncryption` gets a timeout, bounded like the form's check, after which the same two buttons (Try Again, Stop Syncing…) are offered instead of holding the read-only state indefinitely. The next launch tries to finish by itself first (the marker takes precedence over the form) and shows this only if that fails. This is the single exit for a server that vanished after the purge, and it loses nothing.

#### Done

A sheet over the journals (all devices): lock-shield symbol, heading `settings.privacy.encryption.on` ("Your Journals Are Encrypted"), `settings.encryption.done.message`, and the line **`library.encrypt.done.keepPassword`** for everyone ("Keep your master password somewhere safe. It is the only way to open your journals on a new device."); on a synced library a section "Your Other Devices" with `settings.encryption.done.otherDevices` and **Add Another Device…** (`settings.connect.ready.addDevice`, opens Add Device); the note `settings.encryption.done.archives` (earlier archives and backups stay readable). **Done** (`common.done`) is the default action; Return and Escape both close the sheet. A local library gets this sheet too: it is the one place the person learns what to keep and that earlier archives stay readable, and it costs one button. The result is announced (`messages.encryption.announce.done`).

**When the readable copy is removed.** The plaintext folder and the old key are removed as soon as the encrypted library has opened and, when connected, has synced (`SupersededLibraries.swift`). For a local-only library that is right after it opens. This record keeps that, and states the trade-off: nothing readable stays on the device and there is no privacy window, but a wrongly remembered password has no plaintext fallback. The mitigations are the Verify field, the new-password field type (a password manager saves it), the note directly under the fields, and the Done line. Keeping the plaintext until the next launch has opened the encrypted library would cost space and a privacy window, and is not done.

**Per device**

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Form | Full-window screen | Full-window screen, column centred; the same in Split View, Slide Over and every window | Fills each journal window (minimum 801 × 420 points); Settings shows `settings.encryptFirst` |
| Default action | Encrypt below the fields; Return in Verify | Same; hardware keyboard Return | Encrypt is the default button; Return |
| Working notice | Above the content on every stacked screen | Above the columns | Top of the journal window |
| Background | Asks for background time | Same | Not needed |

#### Copy

| Key | Text | Status |
| --- | --- | --- |
| `library.encrypt.title` | Encrypt Your Journals | new |
| `library.encrypt.message` | My Journal now encrypts every journal. Choose a master password to encrypt the journals on this device. Only your devices can read them. | new |
| `library.encrypt.messageSynced` | My Journal now encrypts every journal. Choose a master password to encrypt the journals on this device and on {host}. Only your devices can read them. | new |
| `library.encrypt.messageSignIn` | {host} now uses encryption. Sign in with your master password to encrypt the journals on this device. Changes that haven’t synced are kept. | new (does not claim who turned encryption on; a replaced server looks the same, open question B6) |
| `library.encrypt.action` | Encrypt | new |
| `library.encrypt.notNow` | Not Now | new |
| `library.encrypt.duration` | {"default": "This can take a few minutes if you have many images. Keep My Journal open.", "mac": "This can take a few minutes if you have many images."} | new (replaces `settings.encryption.pauseFooter`) |
| `library.encrypt.stopSyncing.message` | This device won’t be able to sync with {host} again. Your other devices keep using {host} and won’t receive changes made here. Your journals stay on this device and are encrypted next. | new |
| `library.encrypt.adopt.message` | Your journals are already encrypted on this device. This device won’t be able to sync with {host} again. | new |
| `library.encrypt.done.keepPassword` | Keep your master password somewhere safe. It is the only way to open your journals on a new device. | new |
| `settings.encryptFirst` | Choose a master password to encrypt your journals first. | new (used instead of `settings.libraryProblem`) |
| `settings.encryption.otherDevices.update` | Before you encrypt, let your other devices sync. | text changed (a 1.0 device recovers by signing in; nothing requires updating it first) |
| `messages.writingPaused.encrypting` | Writing is paused while your journals are encrypted. | text changed (device-neutral; was "this Mac") |
| `messages.password.tooShort` | Use at least 8 characters. | new, pending the owner decision in section 9 |
| `settings.encryption.checking`, `.progress`, `.progressLabel`, `.progressValue`, `.updatingServer`, `.currentAccessPassword`, `.showPasswords`, `.otherDevices.header`, `.otherDevices.signIn`, `.otherDevices.agents`, `.done.message`, `.done.otherDevices`, `.done.archives`; `settings.privacy.encryption.on`, `.off`, `.turnOn`; `settings.connect.ready.addDevice`; `settings.password.footer`; `library.createLibrary.advice`; `common.masterPassword`, `.verify`, `.showPassword`, `.signIn`, `.tryAgain`, `.done`, `.cancel` | unchanged | reused |

Errors (all announced; field errors are the field's hint and move focus there):

| Situation | Key | Text | Exit |
| --- | --- | --- | --- |
| Not enough space | `messages.encryption.notEnoughSpace` | unchanged ("There isn’t enough space to encrypt your journals. Free up {size} and try again.") | Try Again, Not Now |
| Couldn't reach the server (checking or encrypting) | `common.couldntReachHost` | "Couldn’t reach {host}. Check your connection and try again." | Try Again, Not Now |
| The server is too old | `messages.encryption.serverOutdated` | "{host} needs an update before it can store encrypted journals. Updating it is the way to keep syncing." (host capitalised as today) | Not Now, Stop Syncing… |
| This device lost access | `messages.encryption.accessLost` | "This device no longer has access to {host}. You can stop syncing to encrypt your journals on this device." | Not Now, Stop Syncing… |
| Wrong access password | `messages.encryption.incorrectPassword` | unchanged | Under Current Access Password; Not Now, Stop Syncing… |
| Too many attempts | `messages.encryption.rateLimited` | unchanged | Under Current Access Password; Not Now, Stop Syncing… |
| Encryption was already turned on from another device (the purge answers `alreadyEncrypted`, or access was refused during the pre-sync) | `library.encrypt.messageSignIn` | the form switches to variant C | Sign In…, Not Now |
| Another device wrote meanwhile (twice) | `messages.encryption.stillSyncing` | unchanged | Try Again, Not Now |
| Images missing | `messages.encryption.imagesMissing` | unchanged | Try Again, Not Now |
| iOS background time ran out | `messages.encryption.background` | unchanged | Try Again, Not Now |
| The server switched, this device couldn't finish | `messages.encryption.unfinished` | unchanged; one text for all devices (resolves B17) | Try Again, Stop Syncing… (journals read-only) |
| Anything else (including a copy that failed verification) | `messages.encryption.failed` | "Your journals couldn’t be encrypted. They are unchanged." | Try Again, Not Now |
| The passwords differ | `messages.connection.passwordsDontMatch` | unchanged | Under Verify |
| The password is too short | `messages.password.tooShort` | see above | Under Master Password |
| Encrypted, but the journals can't be shown | `messages.refresh.encryptionOn` | unchanged | App error alert |

Removed from this flow: `messages.encryption.unreachable` (use `common.couldntReachHost`), `messages.writingPaused.encryptionUnfinished` and `messages.writingPaused.showProgress` (the notice carries them), the three-step sheet's keys (`settings.encryption.title`, `.intro`, `.introSynced`, `.passwordIntro`, `.turnOn`, `.pauseFooter`). `messages.encryption.announce.turningOn` becomes "Encrypting your journals". `messages.encryption.turnedOnElsewhere` stays for Settings ▸ Privacy's footer while Not Now exists.

#### States

- **Empty library** (nothing written yet): the same form and flow; fast, no special case.
- **Loading:** "Checking {host}…" (synced, at most about 10 seconds); then, in the notice, "Syncing…" (`settings.sync.syncing`), "Encrypting your journals…" with a determinate bar, and "Updating {host}…" (`settings.encryption.updatingServer`, announced as `messages.encryption.announce.updatingServer`; can't be cancelled).
- **Offline:** variant D with `common.couldntReachHost`, Try Again and **Not Now**. A library that is not on a server never needs the network. A synced unencrypted library can't be encrypted offline (it would leave the server readable and split the devices), so the person either waits for a connection or chooses Not Now and has their journals exactly as in 1.0. This answers the former decision O1.
- **Low space, active household, flaky link, a copy that fails verification:** each leaves the library readable and unchanged and offers Not Now, so none of them can lock anyone out. A latent defect in a real 1.0 library (a row that fails the copy's verification) shows `messages.encryption.failed` and the journals stay available through Not Now; it is also what a test with a deliberately damaged fixture covers.
- **Unfinished:** read-only journals, the notice, Try Again and Stop Syncing… (above).
- **Locked:** the lock screen comes first. Locking while working cancels it if it can still be cancelled (nothing changed) and otherwise lets it finish, as today.
- **Quit or crash:** before the switch, the staged copy is removed at the next launch and the form starts again; after the server switched, the next launch finishes it. Either way the old library is never touched before the new one is verified. An iOS background-time expiry during the server step ends as unfinished, not as data loss.

#### Accessibility

- When the form appears VoiceOver moves to the heading (`JournalAccessibility.screenChanged`). Reading order: symbol (hidden), heading, paragraph, other devices, fields, note, error, primary button, Not Now, Stop Syncing…. The variant chosen by the check is announced when it replaces the spinner.
- Every field has a visible label and the new-password content type; Show Password reveals both. A field error is the field's accessibility hint and is announced after focus moves there. The mismatch is announced when it appears (also fixing open question A38 for this screen).
- The primary button's accessible name is "Encrypt journals" (it starts with the visible word, so Voice Control and Switch Control commands don't collide with the heading). Not Now and Stop Syncing… are plain buttons at the standard minimum hit size.
- The working notice is one element for status: label `settings.encryption.progressLabel`, value `settings.encryption.progressValue`. Announcements: start (`messages.encryption.announce.turningOn`), updating the server, done and every error. The notice stays reachable by VoiceOver on every screen while the journals are read-only.
- The column scrolls at the largest text sizes and the buttons stack; nothing relies on colour alone. There is no animation beyond the system's, so Reduce Motion needs nothing.
- Full Keyboard Access and Tab follow the reading order; Cancel on the Mac is Escape.

### 3.5 Importing an unencrypted archive

- **Preview** (`screens/archive-import`): when the archive isn't encrypted and the device has no journals, a line `settings.archiveImport.unencryptedNote` ("This archive isn’t encrypted. You’ll choose a master password next.") sits above the buttons. Nothing else is asked.
- **Restore Journals** installs the archive as it is (identities kept), shows Done as today, and the window then shows the form. Between the two the library is the archive's copy on this device; nothing was sent anywhere. Failures and Not Now behave as for any unencrypted library.
- **Import as New Journals** (device with journals) needs no change: into an encrypted library the journals are added under that library's key and are encrypted. Into an unencrypted library (Not Now) they are readable until the form runs. No note.
- **Which archives can be unencrypted.** Only archives made by 1.0 or earlier, in the 1.0 directory format (archive header version 2, recovery format 4). 1.1 always exports encrypted archives.
- **Interaction with the single-file archive** ([1-1-archive-v2.md](1-1-archive-v2.md), owned by another author; this record doesn't edit it). That record's review proposes that the new file format hold recovery formats 1 and 2 only, so an unencrypted archive exists only as a 1.0 directory, which Apple 1.1 keeps reading and Windows and Android never read. This record **agrees with that proposal**: nothing in G needs a plaintext file format, and keeping one would give Windows an unauthenticated manifest to handle. If the owner keeps a plaintext variant in format 2 instead, restoring it behaves exactly as above (restore, then the form) on every platform that can read it, and the Windows and Android rows of section 3.8 would need the form's variant A as well. Either way no restore creates an unencrypted library that stays unencrypted unless the person chooses Not Now.

### 3.6 Servers that hold unencrypted data

- **A device that has an encrypted library, or no library, never keeps, joins or sets up a server whose recovery format is 3 or 4.** `checkServerEnvelope` throws `ServerConnectionError.encryptionOff` for them (today only for an encrypted library). A device whose library is unencrypted (Not Now) keeps 1.0's behaviour toward its own unencrypted server: nothing about joining changes for it, and its form variant B encrypts the server.
- **One refusal text** for the check, for pairing and for the sheet's check (resolves B19), pointing at the action rather than an update, since a 1.0 device already has the action: `messages.connection.encryptionOff` = "{host} doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption." It replaces the current `messages.connection.encryptionOff` and `messages.connection.encryptionOffOnHost`. "Turn on encryption in Settings" stays true on 1.0 and on 1.1 (Settings ▸ Privacy ▸ Turn On Encryption…).
- **The route for people with only a plaintext server.** (1) Any device that still has the journals, on 1.0 or 1.1: Turn On Encryption (1.0) or Encrypt (1.1) there, which encrypts the server and revokes the others; then new devices join normally. (2) No device left, but a 1.0 archive: restore it on the new device (the form encrypts it) and set up a new server; the old plaintext server is abandoned. (3) A plaintext server and nothing else: **not supported in 1.1**, and the record says so rather than leaving it unstated. The user guide (`docs/guide/`) and the 1.1 release notes get a short paragraph for (1) to (3) and a warning to encrypt on a device before the last one is retired. A cheaper alternative exists if the owner wants no stranded case: let a device with no library join a plaintext server (the paths all remain while Not Now exists), which ends in the form's variant B at once. It is not recommended because it is the one way 1.1 would create an unencrypted library from nothing.
- **Dead code now:** only what served a *new* device joining a plaintext server and creating an unencrypted library. The passwordless join, the recovery-code step and the format 4 branches of `recoverServer` stay, because an unencrypted library (Not Now) still reconnects that way, and go with the exit (3.7).
- **No server change.** The server keeps formats 3 and 4 and `encryption-upgrade` for as long as 1.0 clients exist; whether a later server refuses to set up an unencrypted vault is part of simplification O.
- **Agents.** Encrypting a synced library removes the server's agent grants; variant B says so (`settings.encryption.otherDevices.agents`).

### 3.7 After G: what changes now, and what waits for the exit to go

**Changes in 1.1**

- Start a Journal and Connect to a Server make encrypted libraries only (3.3).
- The Turn On Encryption three-step sheet is replaced by the form, the working notice, the Done sheet and the unfinished notice (3.4); `EncryptionUpgrade`'s steps and path, `presentedOverApp`, `showProgress` and the Mac-only pause notice are replaced by the device-neutral notice.
- Settings ▸ Privacy for an **encrypted** library is unchanged. For an unencrypted library it keeps "Encryption Is Off" (`settings.privacy.encryption.off`) and **Turn On Encryption…**, which brings the form back, and **Sign In…** in variant C.
- Check Your Password goes (section 4).
- The refusal text and the no-library refusal of a plaintext server (3.6).
- Docs: README.md ("Or choose Continue Without Encryption…"), PRIVACY.md (lines 11, 12, 34, 57, 73), SECURITY.md ("Libraries without encryption", "Turning on encryption later"), docs/guide/getting-started.md, docs/guide/troubleshooting.md, docs/app-store/ (listing and privacy answers; the nutrition-label answers don't change) and CHANGELOG.md say the new rule in the 1.1 entry, and the guide gets the route in 3.6 and one more line: the master password is needed to restore the app's data to a new phone, because the readable copy no longer exists and Check Your Password no longer proves the person can produce it. The public pages that describe Continue Without Encryption change on the day 1.1 ships, not before.

**Stays while Not Now exists** (the earlier draft removed these; with a full 1.0 library behind the exit they must stay, and removing them is a later release's job)

- `SyncHealth.signInNeeded` and its message `messages.sync.signInNeeded`, `EncryptionUpgrade.turnedOnElsewhere`/`offersSignIn`, and the Sign In… rows (open question B6 stays open until then).
- The readable-archive device authentication (`ArchiveExport.confirmOwner`, `settings.backup.archiveReason`) and the unencrypted footers and reasons (`settings.backup.archive.footerUnencrypted`, `settings.backup.markdown.footerUnencrypted`, `settings.backup.markdownReasonUnencrypted`); open question D2 stays as decided.
- The `configuration?.encrypted == false` branches in `MarkdownExportView`, `ArchiveView`, `ConnectionSteps`, `MergeJournalsView`, `ServerAgentsView`, `DocumentTransferOperations`, `MarkdownExportOperations`.
- The passwordless join, Use a Recovery Code, `ConnectionFlow.passwordless`, the format 4 branches of `recoverServer`, `common.unencryptedWarning`, `common.recoveryCode`, `settings.connect.recoveryCode.*`, `settings.connect.merge.footerUnencrypted` and `.footerWillEncrypt`.

**When the exit can go.** Not Now can be removed in a later release (not before 1.2) once 1.1 has been the current version long enough that essentially nobody opens it for the first time with an unencrypted library, which is the owner's judgement at that time; the lines above are then removed with it, and G's full simplification lands. Until then the cost is carried knowingly. A restricted exit (read-only plus export) would let some of those branches go sooner but would give a person with a failing server a library they cannot write in; the record chose full 1.0 behaviour as the cleaner option.

### 3.8 Data migration and interoperability

**One library, step by step (format 4, local only).** Launch → (lock screen) → the form → password twice → Encrypt:

1. The open entry is saved (nothing is open at launch). The space check needs the library's size plus 50 MB. Journals become read-only and the notice appears.
2. A new random 256-bit vault key and a format 2 envelope from the password are made. The key is written to a new Keychain account and an `EncryptionUpgradeMarker` is saved, so a crash can be cleaned up.
3. `reencryptedCopy(to:key:baseline:)` seals the exact bytes of every record, history row, conflict and image under the new key, with the same identities and the same AAD strings. Records this version can only read (`preservedJSON`) are copied as bytes, not re-encoded. Pins, journal order and Version History are inside those rows.
4. The copy is validated (`validateSchema`, `validateSnapshot`, every row compared decrypted against the source). A failure here leaves the old library unchanged and shows `messages.encryption.failed`.
5. One configuration write switches `recovery`, `storageFolder`, `keyID` and `recoveryConfirmed`, keeping App Lock, Lock when inactive, last journal and entry, and the default journal; the old folder and key become a superseded library.
6. The encrypted library opens; the plaintext folder and old key are removed after it has opened (and synced, if connected). Nothing readable remains in the app's data folder. Archives and backups made earlier stay readable, and the Done sheet says so.

**A synced library** adds: sync first; ask the server to purge and re-key (`POST /v1/recovery/encrypt`, capability `encryption-upgrade`: under its write gate it deletes records, changes, operations, attachments and the old backup copy, revokes every other device and sets the new envelope); resume after a lost answer by comparing the server's envelope with the marker; send everything again from the new library, matched by content so another device that signed in first creates no duplicates ([enable-encryption.md](enable-encryption.md), sections 2 and 3). It is the code that shipped in 1.0, covered by `EncryptionLifecycleTests`, `ReencryptionTests` and the end-to-end probes; G changes who starts it and where it is shown.

**Mixed fleets.**

| Situation | What happens |
| --- | --- |
| 1.0 devices, all encrypted; one updates to 1.1 | Nothing changes. Same formats, same protocol, same server. |
| 1.0 devices, all unencrypted, one server; device A updates | A shows variant B. A encrypts and purges the server; every other device is revoked. A 1.0 device then shows "Encryption was turned on from another device. Sign in to keep syncing." and signs in with the master password (1.0 behaviour, unchanged; a test with a state written by build 19 covers it). |
| …then device B updates to 1.1 before signing in | B shows variant C and signs in the same way; its offline edits become normal reviews, nothing is duplicated. |
| …then device B (still unencrypted, 1.1) is offline | B shows variant D; Not Now opens it as 1.0 does until it can reach the server. |
| A new 1.1 device joins that server before any old device updated | Refused with `messages.connection.encryptionOff`, which says what to do on a device that has the journals; nothing is sent. |
| 1.1 archive opened on 1.0 | Opens; archives are unchanged by this record. |
| 1.0 unencrypted archive restored on 1.1 | Restores, then the form. |
| Windows and Android | `apps/windows` holds only a README today, so this row is the specification those clients will follow, not a description of code. They never create unencrypted libraries and have none to migrate; they never read the 1.0 directory archives that could be unencrypted ([1-1-archive-v2.md](1-1-archive-v2.md)); they refuse a server whose recovery format is 3 or 4 with `messages.connection.encryptionOff`. They have no form, Not Now, Stop Syncing for this purpose, or sign-in variant. The sync protocol and the conformance fixtures for formats 3 and 4 stay, since 1.0 devices and archives use them. |

**What the person's data looks like afterwards.** Format 2, encrypted under a new key, same identities, same history, same server position (once resent), old copy gone. A device key lost later is recovered with the master password, as for any encrypted library.

### 3.9 Spec changes for G

- `screens/turn-on-encryption.md` and `flows/turn-on-encryption.md` become `screens/encrypt-journals.md` and `flows/encrypt-journals.md` (rewritten from sections 3.4 to 3.8); `screens/settings-privacy.md` (the unencrypted rows stay), `screens/welcome.md` (the precedence list), `screens/unavailable-content.md` (the same list), `screens/connect-to-server.md`, `flows/connect-to-server.md` (no Protect step for a device without a library; the refusal), `flows/reconnect-to-server.md`, `flows/create-library.md` (one step), `screens/archive-import.md`, `flows/import-archive.md`, `flows/stop-syncing.md` (the entry from the form and the consequence), `screens/settings.md` (Show Progress entry point goes), `flows/save-failure.md` (the encryption notice is device-neutral), `screens/add-device.md`, `screens/recovery-key.md` (precedence line only).
- `messages.md`: update `messages.writingPaused.encrypting`, remove `.encryptionUnfinished` and `.showProgress`; update the rows listed above. `commands.md`: remove `encryption-continue`, `show-encryption-progress`; rename `encryption-turn-on` to `encrypt-journals`; keep `turn-on-encryption` (Settings entry), `encryption-finish`, `encryption-cancel`, `encryption-done`; add `encrypt-journals-not-now` and `encrypt-journals-stop-syncing` (the second uses the `stop-syncing` copy and is also enabled on the unfinished notice, where it adopts the encrypted copy).
- `copy/en.json`: add, change and remove exactly the keys named in sections 3.3 to 3.7, 4.4, 5.3 and 6.2. `copy/same-wording.json`: add `settings.encryption.progressLabel` with `messages.encryption.announce.turningOn`.
- `parity.yaml`: remove `continue-without-encryption` and mark it `not-applicable` on every platform with the reason (as Export Entry); rename `turn-on-encryption` to `encrypt-existing-journals` (`reference: apple`, apple `shipped` when built, windows and android `not-applicable` with the reason that no earlier unencrypted libraries exist there); retitle `encrypt-library` to "Every new library is protected with a master password"; the entry text for `continue-without-encryption` says it goes in 1.1 while an unencrypted library persists for 1.0 holders until the exit is removed; `launch-states` mentions the new screen.
- `platforms/apple/**` and `platforms/windows/**`: the same pages, `index.md` rows, `commands.md` and `messages.md`; Apple screenshots for the form, the working notice and the Done sheet from `design/spec-screenshots/capture.sh` using a seeded legacy fixture library. Windows pages are renamed or removed with the spec pages (the checker requires it).
- `spec/README.md` (or the password flows) gets the shared rule for **new** master passwords: at least the minimum length, counted in characters as the user sees them (grapheme clusters), no composition rules, spaces allowed, no upper limit below 64, checked on Create, Encrypt, Change and Set, never live; existing shorter passwords still unlock, sign in and open archives. Windows and Android follow it.
- `open-questions.md`: B17 and B19 resolved by this design; A45 resolved (the notice is shared); C8 re-decided for new passwords (section 9); B6, D2 and D10 unchanged until the exit is removed.

## 4. J: Check Your Password and Forgot Password fold into Change Password

### 4.1 Current behaviour

- **Change Password** (`Views/ChangePasswordView.swift`, `Model/PasswordOperations.swift`): Settings ▸ Privacy ▸ Change Password…. Current, New, Confirm; the server first when connected; a local-save retry state.
- **Check Your Password** (`Views/PasswordCheckView.swift`, `Model/PasswordCheckOperations.swift`): before the first Export Archive on a master-password library that isn't on a server and whose password has not been typed correctly since it was set (`passwordChecked`, `passwordCheckPending`). "Not Now" continues. A wrong password may offer **Forgot Password?** (journals only on this device, device can authenticate its owner), which asks for the device's authentication, then **Set New Password** (no minimum length, valid for five minutes).

### 4.2 New design

There is one place for passwords.

- **Check Your Password goes**, with the sheet, `passwordChecked` (the field stays in old `configuration.json` files and is ignored; it is no longer written), `passwordCheckPending`, `checkPassword`, `markPasswordChecked`, the export step and the commands `password-check` and `password-check-not-now`. Export Archive goes straight to preparing. The person who wants to confirm the password uses Change Password: typing the current password checks it (and an unwanted change is cancelled).
- **Forgot Password? moves into Change Password**, under the Current Password field, as a borderless button. It is shown whenever the journals exist only on this device and the device can authenticate its owner (same eligibility as today: `canSetPasswordWithoutCurrent` and `canAuthenticateDeviceOwner`). Today it appears only after a wrong password; showing it from the start is the native pattern for a password field and costs one line, and it can't be used without authentication.
- **Flow.** Forgot Password? asks for the device's authentication (Face ID, Touch ID, passcode or login password) with the reason `settings.changePassword.authReason`. Cancelled or failed: nothing changes and nothing is said. Succeeded: the Current Password section is replaced, in the same sheet, by `settings.changePassword.forgotIntro` (secondary text), focus moves to New Password (a new-password field, as is Confirm, so the system offers a strong password and saves it; a new password shorter than the minimum in section 9 is refused with `messages.password.tooShort`), and Change sets the new password without the old one (`setPasswordWithoutCurrent`: the same key is protected by the new password, nothing is re-encrypted, archives exported before still need the old password). The authorization lasts five minutes and one use and is forgotten when the sheet closes; locking, connecting to a server or replacing the library meanwhile sets nothing (`settings.changePassword.error.reset`).
- **Everything else is today's Change Password:** the title, the intro (`settings.changePassword.intro`), Cancel, the busy text, `messages.password.*`, the local-save retry (open question D3, resolved: keep).
- **Export Archive compensates for the missing nudge** (review finding 8), in two places and with no sheet. Under its footer, a borderless button `settings.backup.archive.changePassword` ("Not sure of your password? Change Password…") opens Change Password: typing the current password is the check, and a local-only library can reset. It appears in Settings ▸ Backup and the File ▸ Export Archive sheet, for master-password libraries only. After the save dialog saves the archive, the Export row shows `messages.export.archiveSaved` ("Archive saved. Keep your {credential} with it.", the credential in lower case) until the next export, and announces it. The footer `settings.backup.archive.footerEncrypted` becomes "An archive is an encrypted copy of your journals, including images and earlier versions. It opens only with your {credential}."

### 4.3 Layout per device

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Sheet | Grouped form, inline title, Cancel and Change in the bar | Form sheet, same | 440 points wide, at least 400 tall, same toolbar |
| Forgot Password? | Under Current Password, left aligned, in the section footer with the wrong-password error | Same | Same |
| After authenticating | The Current Password section becomes the forgot explanation; keyboard moves to New Password | Same | Same |
| Export Archive pointer | A borderless button under the footer in Settings ▸ Backup | Same, and in the Export Archive sheet | Same |

### 4.4 Copy

| Key | Text | Status |
| --- | --- | --- |
| `settings.changePassword.forgot` | Forgot Password? | new (replaces `settings.passwordCheck.forgot`) |
| `settings.changePassword.authReason` | {"default": "Set a new password for your journals", "mac": "set a new password for your journals"} | new (replaces `settings.passwordCheck.authReason`; the casing now follows every other reason, resolving B23 and B43) |
| `settings.changePassword.forgotIntro` | Your journals are only on this device, so you can set a new password without the current one. Archives you exported before still need the old password. | moved from `settings.passwordCheck.setNew.intro` |
| `settings.changePassword.error.reset` | Couldn’t set a new password. Your current password still works. | moved from `settings.passwordCheck.setNew.error` |
| `settings.backup.archive.footerEncrypted` | An archive is an encrypted copy of your journals, including images and earlier versions. It opens only with your {credential}. | text changed |
| `settings.backup.archive.changePassword` | Not sure of your password? Change Password… | new |
| `messages.export.archiveSaved` | Archive saved. Keep your {credential} with it. | new (the save used to say nothing) |
| `messages.password.tooShort` | Use at least 8 characters. | new, pending the owner decision in section 9 |
| Removed | `settings.passwordCheck.title`, `.intro`, `.check`, `.notNow`, `.wrong`, `.forgot`, `.authReason`, `.setNew.title`, `.setNew.intro`, `.setNew.set`, `.setNew.error` | removed |

`settings.changePassword.title`, `.current`, `.new`, `.confirm`, `.change`, `.busy`, `.intro`, `.error.notSavedRetry`, `messages.password.*` and `messages.connection.passwordsDontMatch` are unchanged. The mismatch label is announced when it first appears (open question A38).

### 4.5 States

- **Not eligible for Forgot Password?** (on a server, library being replaced, locked, or the device can't authenticate its owner): the button isn't shown. A person on a server who has forgotten the password has no reset; the server keeps its own copy (unchanged rule).
- **Working, wrong current password, same password, server too old, unsupported library, saved on the server but not here:** unchanged from `flows/change-password.md`.
- **Offline:** a library on a server needs it to change the password (`messages.password.failed`); Forgot Password? is local-only and works offline.
- **Other devices.** No protocol or server change. A password changed on a 1.1 device reaches 1.0 devices exactly as today: the old password keeps unlocking until their next unlock with the new one, which they accept from the server's newer copy.
- **Locked:** the sheet closes.

### 4.6 Accessibility

Forgot Password? is a button with its visible label; authentication is the system's. After authenticating, VoiceOver announces the change of screen and focus lands in New Password. Every error is announced (A38 closed). The device's authentication sheet is the system's.

### 4.7 Spec changes for J

`screens/password-check.md` and `flows/forgot-password.md` are removed (their Apple and Windows pages with them); their content moves into `screens/change-password.md` and `flows/change-password.md`; `flows/export-archive.md` and `screens/settings-backup.md` lose the password-check step, gain the Change Password pointer and the saved message ("Saved: done; nothing is announced" changes); `parity.yaml`: `password-check` becomes `not-applicable` everywhere ("folded into Change Password"), `forgot-password` points to `screens/change-password.md` and `flows/change-password.md`; `commands.md`: remove `password-check`, `password-check-not-now`, `set-new-password`, `set-new-password-cancel`, repurpose `forgot-password` (enabled in the sheet), add nothing else; `messages.md`: nothing; `copy`: section 4.4; `open-questions.md`: B23, B43 (Check Your Password part), A38 resolved; D3 note.

## 5. C: "Update My Journal"

### 5.1 The rule

Every state where this version of the app is too old for what it meets says so with the words **Update My Journal**, as a sentence ("Update My Journal to …") or, on the library problem screen, its heading. The sentence names what the person can't do yet or what stays safe; it never names a store (the operating system does the update) and never says "update it" or "needs a newer version" without the instruction. Servers that are too old keep "needs an update" (the person can't act on those from here); that is a different state.

### 5.2 Where it already holds (no change)

`messages.sync.appUpdateNeeded`, `messages.connection.updateApp`, `messages.pairing.deviceOutdated`, `messages.pairing.inviteNewerVersion`, `messages.import.archiveNeedsUpdate`, `messages.import.mergeNeedsUpdate`, `messages.merge.newerVersion`, `messages.lifecycle.unsupportedJournal`, `messages.library.needsUpdate`, `messages.error.unsupportedFormat`, `messages.generic.deleteNeedsUpdate`, `messages.generic.journalDeleteNeedsUpdate`, `messages.conflict.updateToReview`, `messages.conflict.deletion.updateToReview`, `common.updateToRestoreEntry`, `editor.history.updateToRestore`, `messages.unavailable.restoreJournalNeedsUpdate`, `settings.archiveImport.error.newerVersion`, `settings.backup.markdownNote.itemsUnreadable` and `library.problem.updateTitle`.

### 5.3 What changes

| Key | Today | New |
| --- | --- | --- |
| `library.problem.newerVersion.message` | …saved by a newer version of My Journal. Update My Journal in the App Store or TestFlight to open them. | These journals were saved by a newer version of My Journal. Update My Journal to open them. |
| `messages.error.newerVersion` | the same sentence without the store | unchanged; the two keys stay (alert versus paragraph, other platforms add their update link) and join `copy/same-wording.json` |
| `library.problem.settingsUnread.advice` | If you recently used a newer version of My Journal, update it. Then try again. If this keeps happening, restart your {device}. | If a newer version of My Journal saved these settings, update My Journal, then try again. If this keeps happening, restart your {device}. |
| `library.deleteAll.held.newerVersion` | 1 item needs a newer version of My Journal and will stay in Recently Deleted. (plural) | one: "1 item was saved by a newer version and stays in Recently Deleted. Update My Journal to delete it." other: "{count} items were saved by a newer version and stay in Recently Deleted. Update My Journal to delete them." |
| `messages.generic.pinFailed`, `.unpinFailed`, `.moveJournalFailed` | always "Couldn’t pin the entry." etc., even for a library record from a newer version | when the failure is `LibraryError.newerVersion`, show `messages.library.needsUpdate` instead (open question A8) |

`DeleteAllPrompt.swift:178` and its string builders, `LibraryProblemView.swift:70-75` and the three pin and move catches change to read the catalog text. The `library.problem.newerVersion.message` wording is Apple's; the Windows page may add its link (open question B38) without changing the key's meaning.

### 5.4 Layout, accessibility, states

No layout change: only text. The library problem screen's heading `library.problem.updateTitle` and its Learn More button stay; the screen's paragraph is read as one block. Each message is announced where it was announced before (alert, notice, footer). Empty, loading and offline states are untouched.

### 5.5 Spec changes for C

`copy/en.json` as above and the `context` of each changed key; `copy/same-wording.json`; `messages.md` rows for the changed keys and for A8; `screens/unavailable-content.md` table; `open-questions.md`: A8 resolved in part, a C entry for the rule. A catalog check (section 8) keeps the rule from drifting.

## 6. D: migrations for builds before 16

### 6.1 Floor and criterion

Version 1.0 is builds 16 to 19. **Build 16 is the floor: 1.1 guarantees every library, settings file, key item and archive that builds 16 to 19 wrote or left behind.** Builds before 16 were made between 21 September and 4 October 2026 (commit dates), and the history in this repository starts at build 9; builds 1 to 8 can't be inspected.

A conversion goes only when all three are true:

1. **Nothing in builds 9 to 19 writes the old shape.** Each of those builds converts or retires it on every open, so a library that any of them opened no longer has it. The evidence is the code already being in the build 9 import with no writer afterwards (`git log -S` for each symbol).
2. **What a library that still has it sees afterwards is a default or a state the app already explains**, never unreachable data. A read path that lets an old library find its key, files or server stays even if only an early build needs it, because removing it can only strand data.
3. **The default is not a weaker protection and leaves no credential behind.** A conversion that turns a protection off or abandons a secret stays, however few lines it saves.

By that test D is small: one item goes. The inventory behind this section (every migration, fallback and tolerance in the Apple app, the server and the docs, checked against the build commits) is summarised in 6.2 to 6.4.

### 6.2 What goes

| Item | Code | Tests | What a library that still needs it sees |
| --- | --- | --- | --- |
| **Old Mac window layouts.** | `WindowColumns.init?(rawValue:)` accepting `detailOnly`, `doubleColumn` and the form without widths (`Model/WindowColumns.swift:76-98`). | `EditorOnlyTests.testWindowsSavedByEarlierVersionsReopenInTheirLayout`. | An unreadable saved layout falls back to the default (`.all`); nothing is lost. |

Nothing in the spec, copy or `parity.yaml` changes for it.

### 6.3 What stays, and why

| Item | Why it stays |
| --- | --- |
| **App Lock PIN retirement** (`retireAppLockPIN`, `AppLockTurnedOff.pinRetired`, the PIN fields, `settings.lock.pinRetired`, `settings.lock.turnedOff.pinRetired`) | Reviewed and reversed from the first draft. For a library that still had a PIN it sets App Lock on and shows a notice. Removing it would leave that person with App Lock silently off: a protection change without notice, for about 25 lines (criterion 3). |
| **Local agent cleanup** (`Model/LocalAgentCleanup.swift`, `Model/SharedContainer.swift`, the `application-groups` entitlement) | It deletes old agent tokens and files at every launch. Without it they stay in the Keychain until Erase, which sits badly with agent access being explicit and revocable. It saves one file. |
| The five client database migrations (`v1`, `sync-reconciliation`, `history-record-index`, `history-checkpoints`, `server-versions`, `Store.swift:123-156`) and the eight server migrations | GRDB reports a database as made by a newer version when it holds a migration the code doesn't register (`hasBeenSuperseded`, `Store.swift:96`). Removing or renaming any registration would make **every** 1.0 library, and every archive, open as "saved by a newer version". The server refuses to start on an unknown migration for the same reason, and a documented guide tells people to run a standalone server on the old in-app server's data. Squashing is possible only by keeping the identifiers registered, which saves nothing. |
| `journal.pre-migration.db`, server receipts and old-client tolerances | Documented in [protocol/server-backup.md](../../protocol/server-backup.md); server work is simplification O. |
| Former Mac server handling (`Model/FormerMacServer.swift`, the Erase exclusions) | Build 16 still ran the server inside the Mac app; the retirement shipped in build 17. A Mac that went from 16 straight to 1.1 needs it. |
| Built-in template recognition (`BuiltInTemplates`, merge plan) | Every library created before build 15 still holds the four templates, and servers set up by those builds too (owner decision 2026-10-04). |
| Formats 1 to 4 and everything that reads them, the Keep Your Recovery Key screen and its confirmation gate (`RecoveryView`, `isReady`) | Open question D10 and D11 (2026-10-09): early libraries keep working; the gate is the only way to show the key of a library whose key was never confirmed. Format 3's access-password field is part of Encrypt Your Journals (section 3.4). |
| `rememberKeyAccount`, the `keyID ?? keyAccount` and `connectionKeyID ?? keyAccount + "-connection"` fallbacks, `storageFolder == nil` handling, the superseded-library cleanup | They are how a library from before build 9 finds its key, its server connection and its files. Removing them replaces a working library with the missing-key or can't-open screen, or strands files with no credential that brings them back. A line each; Erase sweeps these names too. |
| Library-record leftovers from build 12 (`StoreLibrary.convertLeftovers`, pinned-entries.md rule 5) | A review row or history row for the library record that build 12 made would otherwise stay in the conflicts table and could appear as a review that can't be completed. The code is isolated and tested. Revisit after the last TestFlight build before 16 has expired and one release has shipped. |
| Keychain login-to-data-protection move (`Keychain.swift`), the unmarked-store rule, legacy record fields, document version 1, archives version 1 to 3, the Mac container migration (`container-migration.plist`) | The move and the login-keychain store are what unsigned and team-signed development builds use today. Archives and records are formats other platforms must read. The container migration is what brings a pre-sandbox Mac library into the app; without it the Mac would show the first-launch screen over journals it can't see, which looks like data loss. |
| Older-server tolerances (capability fallbacks, eight-character setup codes) | They concern servers, not TestFlight builds; simplification O decides them. |

### 6.4 What a library from before build 16 sees

| Last opened by | After 1.1 |
| --- | --- |
| Builds 16 to 19 (all of 1.0) | Opens as before. Fixtures written by build 16 and by build 19 prove it (section 8, test 1). |
| Builds 9 to 15 | Opens: every conversion they rely on stays. Not promised and not covered by fixtures; if one breaks, the library problem screen explains and offers Import Archive and Erase, and nothing is removed. |
| Builds 1 to 8 | The same. The one difference is a Mac window that opens in the default layout. An unencrypted library goes through Encrypt Your Journals like any other. |

### 6.5 Confirmation that no 1.0 library loses anything it needs

- The only removed item's source shape has no writer in builds 9 to 19 (6.1), and what replaces it is the default layout.
- Everything build 16 to 19 writes or relies on is in 6.3: formats 2 and 4, `keyAccount` as the prefix of every new Keychain name, `connectionKeyID`, `storageFolder`, `supersededLibraries`, `encryptionUpgrade`, `stoppedSyncingWithFormerMacServer`, the PIN fields, the Mac erase exclusions, `numberDuplicateJournals` and the UserDefaults and SceneStorage keys, none of which was ever renamed.
- The fixtures in section 8 are written by the actual build 16 and build 19 code. Builds 16 to 18 wrote configurations with fields later builds may have dropped (`passwordChecked`, former Mac server flags, leftovers), so a build 19 fixture alone would miss them. The fixtures open under the code after D and G; the removal is last in the order of work.

## 7. Code the implementation changes

The implementation follows the spec-first workflow ([spec/README.md](../../spec/README.md)): spec, notes and screenshots change in the same change as the code, on both Apple and Windows pages.

| Area | Files | Change |
| --- | --- | --- |
| New libraries | `Views/CreateJournalView.swift`, `Model/AppModel.swift` (`start`), `Model/NewVault.swift`, `Packages/JournalCore/.../Crypto.swift` | One step; password only; new-password fields; `VaultCrypto.minimumNewPasswordLength` (a shared JournalCore constant, 8 if the owner confirms) enforced in the model layer (`start`, `turnOnEncryption`, `changePassword`, `setPasswordWithoutCurrent`), not only in the views, while `minimumPasswordLength` stays 1 for unlocking and signing in. The unencrypted branch moves to the test fixture. |
| Encrypt Your Journals | `Views/TurnOnEncryptionView.swift` (replaced by the form, the working notice and the Done sheet), `Model/EncryptionUpgrade.swift`, `Views/RootView.swift`, `Views/SaveFailureNotice.swift` (the Mac-only `EncryptionPauseNotice` becomes the device-neutral notice), `Model/AppModel.swift`, `Model/LibraryOpening.swift`, `JournalApp.swift` | A root form chosen by the library's state (a saved marker or a run in progress takes precedence), the per-launch Not Now held in memory, and the same form as a sheet with Cancel when opened from Settings; the steps and path, `presentedOverApp` and `showProgress` go; the model gains the bounded check step (public encryption details, access, capability, space), the variant, the exit conditions, the Stop Syncing path (including adopting the staged copy when unfinished) and a hold in `sync()` and in `AgentCopyPublisher` until Encrypt or Not Now; `pauseWriting(true)` at Encrypt (after the final flush, before the pre-sync) with every writing control disabled with a reason and `openPendingArchive` waiting; `isIdleTimerDisabled` while the work runs on iPhone and iPad; a new adopt-the-encrypted-copy operation for the unfinished notice (one bounded `serverAdopted` check, then commit the staged copy or discard it; **not** `stopSyncing`, which refuses while `replacingVault`) and a timeout in `finishInterruptedEncryption`. `Model/EncryptionOperations.swift` is reused as it is, apart from the error mapping and the adoption path. |
| Connect to a Server | `Model/ConnectionFlow.swift`, `Views/ConnectionSteps.swift`, `Model/ServerEnvelopeCheck.swift` | `.protect`, `encrypt`, `continueFromProtect` go; the refusal covers an encrypted library or none. The passwordless paths stay. |
| Settings ▸ Privacy | `Views/SettingsView.swift`, `Views/TurnOnEncryptionView.swift:5-44` (`EncryptionSettingsSection`) | Unchanged for an encrypted library; for an unencrypted one, Turn On Encryption… brings back the form. |
| Archives | `Model/ArchiveInstalling.swift`, `Views/ArchiveView.swift` | The unencrypted note on restore; the Change Password pointer and the saved message for Export Archive. |
| Change Password | `Views/ChangePasswordView.swift`, `Views/PasswordCheckView.swift` (deleted; `NewPasswordForm` folds in), `Model/PasswordCheckOperations.swift` (check removed; eligibility, authorization and `setPasswordWithoutCurrent` stay), `Model/PasswordOperations.swift`, `Views/ArchiveView.swift` and `Views/ExportView.swift` (the check sheet), `Model/LocalConfiguration.swift` (`passwordChecked` no longer written; the property may be removed because the decoder ignores unknown keys), `Model/EncryptionOperations.swift`, `Model/ArchiveInstalling.swift`, `Model/AppModel.swift:801` (writes of `passwordChecked`) | As section 4. |
| Update My Journal | `Views/LibraryProblemView.swift`, `Views/DeleteAllPrompt.swift:178`, `Model/LibraryOperations.swift:128` and the pin, unpin and move catches | As section 5. |
| D | `Model/WindowColumns.swift` | The legacy raw values. |
| Fixture | `JournalTests/LibraryFixture.swift` | A `legacyUnencrypted` helper that builds a format 3 or 4 library, so the upgrade stays testable when nothing in the app can create one. |

[docs/design/README.md](README.md) lists this record and marks [enable-encryption.md](enable-encryption.md), [connection-onboarding.md](connection-onboarding.md), the onboarding part of [markdown-writing-revision.md](markdown-writing-revision.md) and the password check in [pre-release-ui-2026-09-27.md](pre-release-ui-2026-09-27.md) as amended.

The dead code that follows from G is **not** removed in this change: it stays while Not Now exists (3.7) and is removed, under simplification A, with the exit.

## 8. Tests worth adding

Only behaviour that would hurt people if it broke ([AGENTS.md](../../AGENTS.md), "Useful tests only"). Real stores, real temporary folders and the test Keychain accounts; the in-process fake server for sync.

1. **1.0 library fixtures (the guard for rules 1 and 3 and for D).** Synthetic libraries written by the real build 16 code and by the real build 19 code (throwaway tools run once from those commits, never from 1.1): format 2 with the password known, format 4, a format 4 library with a server position, each holding journals, entries with a table, a checklist and images, Version History, a conflict, Recently Deleted, pins and journal order. Build 16's matter because builds 16 to 18 wrote configuration fields that build 19 may have dropped. Stored under `JournalTests/Fixtures/` with synthetic content only and a README on how they were made. Tests: each opens in 1.1 and equals a manifest (identities, counts, titles, bytes of images); each format 4 fixture goes through Encrypt Your Journals and the encrypted library equals the same manifest with no readable content left in the data folder (a scan of the database, WAL, shared memory and attachments for a marker string); the format 2 fixture changes its password and exports and re-imports an archive.
2. **Encrypt Your Journals, model level** (extending `EncryptionLifecycleTests`, with `LibraryFixture.legacyUnencrypted` in place of `start(encrypted: false)`):
   - the window routing table (loading, locked, problem, first launch, marker or run in progress, form, recovery key, journals) as a pure function, including the form opened from Settings (a sheet with Cancel) and after Not Now in this launch;
   - the person's own Cancel returns to the plain form and does not offer Not Now on a healthy library, while a failure (including `background` expiry) does; Not Now survives backgrounding, unlocking and the network returning within a launch and is gone after a cold start;
   - `pauseWriting(true)` is in force from Encrypt through the pre-sync, released on cancel, failure and done, with writing controls disabled and an incoming `.journalarchive` waiting;
   - no sync or write request reaches the fake server until Encrypt or Not Now (the readiness check and `finishAfterLaunch` legitimately read it), including a call to `sync()` from export preparation or the Sync Now rows;
   - variant C is chosen when the server's public details are format 1 or 2, and the purge endpoint is never called;
   - **each failure type leaves the library readable and unchanged and offers Not Now:** low space, a copy that fails `validateSnapshot`, `stillSyncing`, unreachable, too-old server, lost access; Not Now then opens it with full 1.0 behaviour and the form returns at the next launch;
   - Stop Syncing leaves a local library that then encrypts, and is not offered for an unreachable server;
   - a local format 3 library needs no access password and a synced one does (the wrong-password test stays);
   - **a kill at each marker state with real files and a faked server answer:** before the copy, copy staged, `contactingServer` true, after the configuration write; an unreachable server with `contactingServer == true` leaves the journals readable (read-only) and Stop Syncing adopts the verified encrypted copy and drops the connection; a server that answers "not switched" keeps the original library, discards the copy and drops the connection; a hung server ends in the same two buttons after the timeout;
   - an iOS background-time expiry during `updatingServer` ends in unfinished, not data loss.
3. **Archives.** Restoring an unencrypted 1.0 archive onto an empty device ends in the routing for the form, and after it every journal and entry ID equals the archive's. Importing an unencrypted archive as new journals into an encrypted library leaves nothing readable on disk.
4. **Connect.** A server with recovery format 3 or 4 is refused for a device with an encrypted library and for one with no library, and when pairing, and nothing is sent to it (the fake server's request log stays empty); a device with an unencrypted library still connects as in 1.0.
5. **Change Password.** Forgot Password? is offered for a local library and not for one on a server; the authorization expires after five minutes and works once; the new password opens the same key and an archive exported earlier still opens only with the old password; no `passwordChecked` is written; Export Archive reaches the save step without any prompt, and the saved message appears after a save. A password shorter than the minimum (counted in grapheme clusters) is refused at the model layer for every new-password path, and an existing short password still unlocks, signs in and opens archives.
6. **Update My Journal.** A pin failure caused by a library record from a newer version shows `messages.library.needsUpdate` (`PinnedListTests`). A rule in `spec/tools/check-spec.py`: every catalog text that says "newer version" or "needs an update" for the app also says "Update My Journal" (a few lines; it keeps C from drifting without a test per message).
7. **Mixed versions, end to end.** A device state written by build 19 (unencrypted, on the fake server), signed out by a purge from the 1.1 flow, rejoins with the master password and loses nothing. The 1.0 behaviour is asserted by running the build 19 client against the same fake server, not only the 1.1 clients.
8. **One UI test per platform family** (iPhone simulator and Mac), replacing `EncryptionUITests`: launch with a seeded unencrypted library; the journals aren't reachable at first; choosing a password and Encrypt shows the read-only journals with the notice, then Done and then the entries. Everything else about the screen is covered by 2.

Deleted with the code they covered: the password-check tests in `PasswordCheckTests.swift`, the Turn On Encryption UI test and the window-layout test listed in 6.2. `ArchiveLifecycleTests` tests for authenticating a readable archive and `ServerEnvelopeTests` tests for the passwordless server stay while Not Now exists. Not tested: copy, layout, and the framework's own sheets.

## 9. Owner decisions

Two, in this order. The earlier offline question is settled by the conditional exit in 3.4 and the question of how far D goes by 6.3.

**O1. Confirm what G means in 1.1.** The scope says "Continue Without Encryption and Turn On Encryption go away." This record delivers: no new unencrypted libraries (Start a Journal and Connect to a Server always encrypt); existing unencrypted libraries are asked to encrypt at launch; and **Not Now** appears only when encryption can't succeed (offline or unreachable server, a server that is too old, no access, not enough space, a failed run, variant C), never because the person pressed Cancel. Because that exit opens a full 1.0 library, Turn On Encryption… stays in Settings for those libraries, and the readable-archive authentication, the unencrypted footers, the passwordless join, Use a Recovery Code and `SyncHealth.signInNeeded` stay with it. Their removal, and G's full simplification, follow in a later release (not before 1.2) when the exit goes. This is the right answer to a screen that could otherwise lock someone out of their own journals, but it shrinks what 1.1 delivers for G and is the owner's product call: **please confirm.**

**O2. A minimum length for new master passwords (open question C8).** C8 (2026-09-29) removed the 12-character minimum for people who chose encryption. The mandatory screen now asks people who didn't choose it, and the master password wraps the vault key in an envelope that the server stores, so anyone with the server database, an admin backup or an archive can guess it offline (PBKDF2, 600,000 iterations; [SECURITY.md](../../SECURITY.md)). [AGENTS.md](../../AGENTS.md) says a short secret is not sufficient protection for encrypted recovery data. Re-deciding C8 would apply to **new** passwords only: Start a Journal, Encrypt Your Journals, Connect to a Server's Choose a Master Password, and the new fields of Change Password and its Forgot Password? path.

- **Recommended: a blocking minimum of 8 characters.** Eight is the floor, not a strong value; it is defensible because most people should be offered a generated password. The rule: counted in characters as the person sees them (grapheme clusters), no composition rules, spaces allowed, no upper limit below 64. It is a shared product rule written in `spec/` for Windows and Android, and `VaultCrypto.minimumNewPasswordLength` carries it in JournalCore for the model layer (`start`, `turnOnEncryption`, change password, set password after Forgot Password?), not only the views. `minimumPasswordLength` stays 1 for unlocking and signing in, so existing shorter passwords keep unlocking, signing in and opening archives (a test proves it). Checked when Create, Encrypt, Change or Set is chosen, never live, with `messages.password.tooShort` under Master Password. Optional and off by default: a short built-in list of the commonest passwords (all one character, "12345678"), and a non-blocking line under 12 characters.
- **Rejected: a hint only.** It lets the mandatory screen collect a one-character secret, which AGENTS.md rules out.
- **Rejected: leave C8 as it is.** For the same reason.

## 10. Risks

- **A new step for real people.** Anyone who chose Continue Without Encryption meets the form at the first 1.1 launch. It has one decision, says why, and has an exit only where it can't succeed, so a person who simply dislikes passwords must still choose one (with the owner's minimum, section 9).
- **Fleets.** Encrypting a synced library revokes every other device and every agent grant at once. Devices recover by signing in with the new password (1.0 and 1.1), but nobody is warned before the form appears unless the other-devices text is read. The copy says it where the password is chosen; it can't say it earlier.
- **Stop Syncing is a one-way exit.** After it, this device can't rejoin that server and the other devices diverge from it. It is offered only for states that won't pass by themselves, and its confirmation says this.
- **People with only a plaintext server and no device** are not supported in 1.1 (3.6), apart from the documented routes. The guide and release notes carry the warning; the owner could allow a no-library device to join a plaintext server at no code cost if this is judged too hard.
- **Not Now keeps unencrypted libraries alive.** Going offline offers it by design, and it is the only deliberate way a healthy synced library stays unencrypted. Some people will use it at every cold start (one extra tap, most often on iPhone). The cost is carried knowingly until the exit is removed (3.7); the dead-code list waits for that.
- **Space and time.** The copy needs the library's size plus 50 MB, and a large image library takes minutes. The journals stay readable meanwhile; on iPhone and iPad the app must stay open, and if the system ends the background time the work stops cleanly and starts again.
- **The server switch is the one irreversible step.** Its recovery (the marker, the server's envelope comparison, "unfinished") is old code but now the default path for a minority of 1.0 users, so it gets the scrutiny of a new feature: tests 1, 2 and 7 and a manual run against the end-to-end probes before release.
- **Check Your Password's safeguard is gone.** A person can still export an archive under a password they have forgotten. The Change Password pointer in Export Archive and the saved message are the mitigations; Forgot Password? doesn't help archives already made.
- **A readable copy is removed at once.** A wrongly remembered password has no plaintext fallback (3.4, "When the readable copy is removed").
- **Public pages.** README, PRIVACY, SECURITY and the guide describe Continue Without Encryption today. They change when 1.1 ships; until then they are correct for 1.0.
- **Windows.** The spec pages for Turn On Encryption, Check Your Password and Forgot Password disappear and the Windows mapping must follow in the same change; whoever is mid-way through those Windows pages needs to be told.

## 11. Dependencies on the other 1.1 simplifications

- **E (Settings tabs):** only the pane names in cross-references move; the Privacy content is as above.
- **I (one Reconnect action):** variant C's Sign In… and Stop Syncing… keep their meaning; if Reconnect absorbs Sign In…, the button takes that name and nothing else changes.
- **A (dead code), O (server cleanup):** G's dead code waits for the exit (3.7); O may later refuse to set up an unencrypted vault, which needs no client change because no 1.1 client sets one up.
- **Single-file archive ([1-1-archive-v2.md](1-1-archive-v2.md)):** independent, with one agreement recorded in 3.5: this record wants the new file format to hold recovery formats 1 and 2 only, so an unencrypted archive exists only as a 1.0 directory, which Apple 1.1 restores (then the form) and Windows and Android never read. If that record keeps a plaintext variant, the restore path is the same.
- **Order of work:** C (text only) and J can go first; G is the largest and gets the fixtures first; D's single removal comes last, after the fixtures prove 1.0 libraries still open.


## Independent review (2026-10-09)

Reviewer: independent design and security reviewer, given the requirements and this proposal only. Checked against `EncryptionOperations.swift`, `EncryptionUpgrade.swift`, `StoreReencryption.swift`, `SupersededLibraries.swift`, `LibraryOpening.swift`, `AppLockOperations.swift`, `Store.swift` (migrator), `server/.../EncryptionEndpoints.cs`, `Crypto.swift`, `spec/flows/stop-syncing.md`, `spec/copy/en.json` and `enable-encryption.md`. No build or simulator was run. Three outcomes of that reading are reassuring and should be kept: the upgrade engine really does copy first, verify every row and image decrypted, and switch with one configuration write, with the marker recovering a crash before and after the server call; the server purge is one transaction with the purge finished at the next start; and the schema migrations really must stay (`hasBeenSuperseded` makes any removed registration look like a newer-version library).

**Verdict: revise and re-review.** The screen's purpose, its single decision and its reuse of the shipped engine are right, and sections 4 to 6 are mostly sound. But as designed the screen is a gate with no way through when the engine cannot or does not succeed, and that turns every environmental or latent-data failure into the person being locked out of their own journal. That contradicts the offline and never-lose-access constraints and needs a structural change (finding 1), not a copy fix. Findings 2 to 6 are Material and should be resolved in the same revision.

### Blockers

**1. The required screen has no exit when encryption cannot run or keeps failing, so a person can be locked out of their own journal. (Blocker)**
Verified in the code: every failure in the error table ends in Try Again, and `Stop Syncing…` exists only for some server errors and only on a synced library. These cases leave no way to read or write anything:
- *Low space.* `requireSpace` needs the library size plus 50 MB while the old library is kept until the copy has opened; a nearly full phone with an image-heavy journal is a normal case. The person cannot free space by deleting entries because they cannot reach them.
- *A latent defect in a real 1.0 library.* `reencryptedCopy` throws `invalidData` if any row fails `validateSchema`, `validateSnapshot` or the byte-for-byte `verify`; the screen then shows `messages.encryption.failed` and Try Again, forever, with no diagnosis and no path to the data. Builds 12 to 19 have already needed leftover conversions (6.3), so this is plausible.
- *Active household.* `stillSyncing` after two tries, `imagesMissing` and `unreachable` on a flaky link repeat without a way out.
- *Local-only libraries* get no Stop Syncing at all, so for them there is no way out of any error.
- *Offline synced library (variant D, O1).* Cannot write, and cannot even read, on first launch after the update, on a plane or at a remote cabin.
- *Unfinished (finding 6).*

The statement "nothing the person does changes the library before they start" is true, but the person is denied the library, not just editing. Compared options:
- *Encrypt locally without blocking and defer only the server switch.* Not recommended. The engine cannot do it safely: the server step needs a full plaintext sync into the store before the purge, and SYNC-2 in `enable-encryption.md` exists precisely to stop an encrypted library from talking to a plaintext vault. A split state would need new reconciliation code mixing protection modes, which is the highest data-loss surface in the product.
- *Make the screen skippable.* The cheap, honest answer. Give the screen a secondary **Not Now** that opens the journals exactly as 1.0 does (the plaintext code paths all still exist because the engine needs them), and show the screen again at the next launch or unlock. To keep G's intent without nagging, offer Not Now only where the screen cannot succeed or has failed once: offline or unreachable synced library, server too old, no access, low space, any `failed`/`stillSyncing`/`imagesMissing`/`background` error, and when the pre-check cannot finish within about 10 seconds. A healthy library with a working server sees only Encrypt. This also answers O1 without making the offline person choose between data and the product rule.
- *Hide only the editing.* Alternatively (or in addition) keep reading available: 1.0 paused writing during encryption but let the person read, and `pauseWriting` already exists. Hiding the journals for the minutes an image-heavy copy takes is a regression (finding 8), and a read-only open with a banner would make the unfinished and failed states safe.

Concrete fix: add Not Now with the conditions above; update section 3.4 (list item 9/10, States), `parity.yaml`/`commands.md` (`encrypt-journals-not-now`), and the code-hygiene note in 3.7: the dead-branch removals that depend on no unencrypted library being usable (readable-archive authentication, the unencrypted export footers, `ServerAgentsView`, `DocumentTransferOperations`) must wait until the gate has no bypass, or the "Not Now" library must be restricted (read-only plus export) so those branches are still unreachable. State that choice in the record; the cleaner option is Not Now = full 1.0 behaviour and a later release removes the branches.

### Material

**2. The record invites one-character master passwords, which the security rules rule out, and the mandatory screen makes weak passwords more likely. (Material, resolve before implementation)**
Section 10 says the way through is cheap "so declining to think about it costs one character". The master password wraps the vault key in an envelope that the server stores (`Crypto.swift`: PBKDF2, 600 000 iterations, `minimumPasswordLength = 1`); anyone holding the server database, an admin backup or an archive can guess it offline. Open question C8 (2026-09-29) removed the minimum for people who chose encryption; this screen now extracts a password from people who did not. AGENTS.md: a short secret is not sufficient protection for encrypted recovery data.
Fix: delete that sentence. Ask the owner to re-decide C8 for new passwords only (Start a Journal, Encrypt Your Journals, Change Password's new field): a minimum of 8 characters, or at least a non-blocking "Use a longer password" hint under the field below 8 that does not stop Encrypt. Existing shorter passwords keep unlocking and signing in. Specify `.newPassword` content type on both fields (`PasswordAutofill.swift` already supports it) so iOS and macOS offer a strong password and save it to the password manager; the design must say this, since it is the main protection against finding 3.

**3. Forced encryption turns a recoverable situation into a possible permanent loss for people who did not ask for it, and the safeguards are thin. (Material)**
A plaintext 1.0 library survives a lost Keychain (a restore onto a new phone, a reset): `openConfiguredLibrary` regenerates a key when `requiresPassword == false`. After this screen the library depends on a password chosen in a hurry, and for a local-only library the plaintext folder and old key are removed right after the copy opens (`removeSupersededLibraries` with `connection == nil`). `Forgot Password?` needs the key, so it does not help in exactly that case. The copy `library.createLibrary.advice` says it, but it is the last item under the fields.
Fix: keep the Verify field (it already catches typos), make the advice sentence visible without scrolling at default text size, and on the Done screen add one line for everyone: `Keep your master password somewhere safe. It is the only way to open your journals on a new device.` (the Done screen already carries the archives note and is where it will be read). Do not add a confirmation step. Optionally keep the superseded plaintext folder until the next launch has opened the encrypted library, so a failure on that first relaunch is not terminal; this costs space and a privacy window, so it is the owner's call, but the record should state that it chose immediate removal.

**4. Stop Syncing… is offered for transient errors, is irreversible in practice, and its confirmation hides that. (Material)**
Stop Syncing is listed for `Couldn’t reach the server`. A phone with a bad signal at launch can therefore lead to a one-way exit. After it, this library is encrypted under a new key and 3.6 forbids any 1.1 device from joining a format 3 or 4 server, so this device can never reconnect to that server; the server keeps the readable copy; other 1.0 devices keep syncing without it and diverge. `library.encrypt.stopSyncing.message` says only that the server "keeps the copy it already has". It also does not tell the person that `settings.sync.stopSyncing.message` normally promises the opposite (the stop-syncing spec says connecting again "continues by identity"; that is false here).
Fix: (a) offer Stop Syncing only for states that are not transient (no access, forgotten or limited access password, server too old when the person cannot update it) and use Not Now for unreachable; (b) change the message to say what is lost: `This device won’t be able to sync with {host} again. Your other devices keep using {host} and won’t receive changes made here. Your journals stay on this device and are encrypted next.`; (c) correct `flows/stop-syncing.md` for this entry point; (d) for a self-hosted server that is "too old", say first that updating the server is the way to continue, since the person is usually the administrator.

**5. Refusing every format 3 or 4 server leaves some people with no way to bring their data into 1.1. (Material)**
Section 3.6 removes the only join path for a plaintext server. Realistic dead ends: all old devices are lost, broken or on an OS that cannot take 1.1 (a household iPad stuck on 1.0), and the person has a new iPhone and a plaintext server; or the person restores a 1.0 plaintext archive on a new device (which becomes library variant A) and then connects, which is refused. The refusal text `messages.connection.encryptionOff` tells them to "Update My Journal on a device that has its journals", but a 1.0 device already has Turn On Encryption and needs no update, and in the lost-device case there is nothing to update.
Fix: change the refusal text to point at the action rather than the update (`{host} doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption.`). And either keep the passwordless "Add This Device" and recovery-code join for a new device so it ends in variant B immediately (the existing join code stays, cost is the lines 3.6 would delete), or write down in the record that the supported route for that person is a new server plus an archive, and say so in the guide. Do not leave it as an unstated consequence.

**6. The unfinished state can strand someone and blocks reading. (Material)**
`finishInterruptedEncryption` needs the server to answer `serverAdopted`; unreachable means `unfinished` again. Section 3.4 shows the full-screen state with Try Again only, no Cancel and no Stop Syncing, and (unlike 1.0, which only paused writing) no journals. If the server is gone after the purge, which is the likeliest reason for the situation, the only exit is Erase. Both local copies are complete and verified at that point (`validateSnapshot` ran before the server call and writing was paused).
Fix: in this state open the journals read-only with a banner (`messages.encryption.unfinished` plus Try Again), and allow Stop Syncing with a message that explains the encrypted copy is adopted locally without the server (commit the staged copy, as the "adopted" branch would, then drop the connection). That is the single exit for a dead server and loses nothing. Add a test: a marker with `contactingServer == true` and an unreachable server leaves the journals readable and Stop Syncing adopts the copy.

**7. Variant B's other-devices copy and the screen's copy mislead. (Material for the first item, Minor for the rest)**
- `settings.encryption.otherDevices.update` ("Before you encrypt, update My Journal on your other devices and let them sync.") implies a requirement that does not exist: a 1.0 device recovers by signing in with the new password, and a 1.1 device does the same through variant C. The useful part is "let them sync" (fewer reviews). Reword: `Before you encrypt, let your other devices sync.` and keep the sign-in line.
- `library.encrypt.message` begins "Every library in My Journal is encrypted." The person has just opened a library that is not, and it gives no reason or sign that something changed. Suggested: `My Journal now encrypts every journal. Choose a master password to encrypt the journals on this device. Only your devices can read them.` and the synced variant likewise. A reader who deliberately chose Continue Without Encryption deserves one plain sentence on why; the sentence above is the shortest honest form.
- Everything else (title, Encrypt, Try Again, the error texts, "Your Journals Are Encrypted") is plain and native. `messages.encryption.accessLost` ("Stop syncing to encrypt your journals on this device.") reads as an instruction in an error; keep it, but only after finding 4 is applied.

**8. The lost password safeguard (J) is a real loss and the footer alone is a weak substitute. (Material)**
Check Your Password was the only moment the app verified that the person can produce the password; Forgot Password? cannot rescue an archive already made under it, and a synced library has no reset at all. With G, many more libraries carry hurried passwords. Moving Forgot Password? into Change Password under the current-password field is a good consolidation (a button that shows before the failure is the native pattern; it is authenticated, so the earlier "after a wrong password only" gating bought nothing).
Fix: keep J, and make the compensation concrete rather than only a footer sentence. In Export Archive's footer (or its success message) add `Not sure of your password? Change Password first.` with the words as a button to Change Password (typing the current password is the check, and a local-only library can reset). Do not reintroduce a sheet. The Export success message should repeat "Keep your master password with the archive." That costs nothing and covers most of the old safeguard.

**9. Minor changes to the screen spec for the "no needless friction" and offline rules.** (Minor, grouped)
- Bound the "Checking {host}…" check (about 10 seconds), then show variant D with Not Now; a slow server must not hold the launch.
- Say in 3.4 that the sync hold for a not-yet-encrypted library is new code: today `finishOpening` starts synchronization; the hold must be tested so a plaintext library cannot push to a server before the person chose (test 2 covers "no request reaches the fake server").
- Done for a local-only library: the screen is a justified single button because it carries the archives note; make Done the default action and let Return and Escape both leave it.
- The Settings text `settings.libraryProblem` ("Settings are available once your journals open.") is wrong for this state. Use a dedicated line: `Choose a master password to encrypt your journals first.`

### Accessibility

Largely sound (heading focus, field errors as hints with announcement, determinate progress as one element, Escape for Cancel, scroll at large text). Add:
- `.newPassword` content types and Show Password, as in finding 2.
- Announce the variant that the check chooses (B, C or D) when it replaces the spinner, not only the final error.
- The plain-text **Stop Syncing…** and **Not Now** buttons need the standard minimum hit size and must stay reachable at the largest Dynamic Type size without scrolling past the primary action.
- Make the order explicit for Switch Control and Voice Control: the primary button's accessible name should be "Encrypt journals", not only "Encrypt", so spoken commands do not collide with the heading.

### D: the migrations

The conclusion (almost nothing can go) is correct and honestly argued; the five client schema migrations and eight server migrations must stay, verified in `Store.swift`. Points:
- **Minor.** Keep `retireAppLockPIN`. Verified: it sets `appLock = true` and `pinRetiredNotice` for a library that had a PIN. Removing it leaves that person with App Lock silently off, which is a protection change without notice and is the one case in D with a downside, for about 25 lines saved. The record already lists the alternative; take it.
- **Minor.** `LocalAgentCleanup` deletes old agent tokens and files at every launch. Removing it leaves credentials in the Keychain until Erase, which sits badly with "explicit, revocable" agent access. It saves one file. Keep it.
- **Minor.** The window-layout conversion is harmless to remove (falls back to default).
- **Minor.** Section 8 test 1 builds fixtures from build 19. The floor is 16, and builds 16 to 18 wrote configurations with fields that 19 may have dropped (`passwordChecked`, former Mac server flags, leftovers). Add one fixture written by build 16.
- O2 is therefore not a real owner decision: the sensible answer is "keep the PIN and agent cleanup, drop only the window layouts, and say so". Present it as a recommendation.

### Owner decisions

- **O1 is genuine and badly framed.** It offers a binary (block versus an unconditional Not Now). The better answer is conditional Not Now as in finding 1: strict when the screen can succeed, an exit when it cannot. Recommend that, not either extreme.
- **O2 is not a decision** (see D above).
- **Missing decision:** whether to keep the 8-character or hint policy of finding 2 (it contradicts C8, so the owner must own it).

### Test and interop notes

- Add: a failure of each type (low space, `validateSnapshot` failure, stillSyncing, unreachable) leaves Not Now available and the library readable and unchanged; a kill at each marker state (before copy, copy staged, `contactingServer` true, after the configuration write) with real files and a faked server answer; an iOS background-time expiry during `updatingServer` ends in `unfinished`, not data loss.
- One end-to-end case that matters for "1.0 and 1.1 must work together": a device state written by build 19, signed out by a 1.1 purge, rejoins (the record asserts the 1.0 behaviour is unchanged but only tests 1.1 clients).
- Windows and Android: `apps/windows` contains only a README; the table in 3.8 describes behaviour that does not exist yet. State it as the spec those clients will follow.

### Summary of required changes before re-review

1. Add the conditional Not Now (and read-only access while encrypting or unfinished); revise 3.4, O1, 3.7 dead-code timing, commands and tests. (Blocker)
2. Remove the one-character justification; decide the minimum or hint for new master passwords; require `.newPassword` content type. (Material)
3. State the loss-of-access consequence on the Done screen; record whether the plaintext copy is removed immediately. (Material)
4. Restrict Stop Syncing to non-transient errors and correct its confirmation. (Material)
5. Decide the route for people with only a plaintext server and no capable device; fix the refusal text. (Material)
6. Make the unfinished state readable, with a local exit. (Material)
7. Reword the other-devices and opening copy; keep the rest. (Material and Minor)
8. Add the concrete Change Password pointer to Export Archive. (Material)
9. Keep App Lock PIN and agent cleanup in D; add a build 16 fixture. (Minor)

## Changes after review

Each finding of the review above, and what the body now says. The review's finding numbers are used.

| # | Finding | What changed |
| --- | --- | --- |
| 1 | Blocker: the screen has no exit when encryption can't run or keeps failing | Adopted the conditional **Not Now** (3.2, 3.4): offered only where the form can't succeed (check not done in about 10 seconds, unreachable, too old, no access, low space, access-password errors, variant C) or after a failed or cancelled run; a healthy library sees only Encrypt. It opens the journals exactly as 1.0 did, returns at the next launch, and Settings ▸ Privacy keeps Turn On Encryption…. **The journals stay readable while encrypting** (read-only with a device-neutral notice, reusing `pauseWriting`), and the unfinished state is read-only with a notice. Because Not Now is a full 1.0 library, the unencrypted code paths stay in 1.1 (3.7), the dead-code removals move to the release that removes the exit ("not before 1.2", the owner's call then), and the choice of full 1.0 behaviour over a restricted exit is stated. New command ids `encrypt-journals-not-now` and `encrypt-journals-stop-syncing` (3.9). Tests: each failure type leaves the library readable with Not Now; kills at each marker state; background expiry (8, test 2). This also answers the former O1. |
| 2 | Material: one-character passwords | Deleted the "costs one character" sentence (section 10). Both password fields are specified as new-password fields (3.3, 3.4, 4.2, accessibility). A single owner decision on a minimum length for new master passwords (section 9), with a recommendation of 8 characters and the alternatives; `messages.password.tooShort`. |
| 3 | Material: forced encryption and thin safeguards | Verify stays; the advice sits directly under the fields and fits the first screen of the smallest iPhone in variant A (3.4); the Done sheet adds `library.encrypt.done.keepPassword` for everyone; no extra confirmation. The record states that the readable copy is removed at once and why (3.4, "When the readable copy is removed"), and what that costs. |
| 4 | Material: Stop Syncing for transient errors with a hiding confirmation | Stop Syncing is offered only for no access, a too-old server and access-password errors; unreachable gets Try Again and Not Now. `library.encrypt.stopSyncing.message` says the consequence in the reviewer's words; `flows/stop-syncing.md` is corrected for this entry (3.9); the too-old error says first that updating the server is the way to keep syncing. |
| 5 | Material: no way in for people with only a plaintext server | The refusal text points at the action ("turn on encryption in Settings") and unifies B19; a documented route (a device that has the journals; an archive and a new server; no supported route when only the server is left, said plainly with a guide and release-note paragraph); the refusal applies to encrypted libraries and devices with none, while a device with an unencrypted library keeps 1.0's behaviour (3.6). The reviewer's other option (keep the join for a new device) is recorded as a no-code-cost alternative for the owner and as a risk (10). |
| 6 | Material: the unfinished state strands people and blocks reading | The unfinished state opens the journals read-only with a notice offering Try Again and **Stop Syncing…**, which adopts the verified encrypted copy and drops the connection (`library.encrypt.adopt.message`). Test: an unreachable server with `contactingServer == true` leaves the journals readable and Stop Syncing adopts the copy (8, test 2). |
| 7 | Material/Minor: copy | `settings.encryption.otherDevices.update` is "Before you encrypt, let your other devices sync."; `library.encrypt.message` and its synced twin begin "My Journal now encrypts every journal."; `messages.encryption.accessLost` is applied only with the restricted Stop Syncing. |
| 8 | Material: Check Your Password's safeguard | Kept J. Export Archive gets a Change Password pointer ("Not sure of your password? Change Password…") and the saved message "Archive saved. Keep your master password with it." (4.2, 4.4). No sheet is reintroduced. |
| 9 | Minor: friction and offline | The check is bounded at about 10 seconds then variant D with Not Now (3.4); the sync hold is stated as new code and tested (3.4, 8); Done is the default action and Return and Escape close it; Settings shows the dedicated `settings.encryptFirst`. |
| Accessibility | Additions | The variant is announced when it replaces the spinner; Not Now and Stop Syncing… keep the standard hit size and stay reachable without scrolling past the primary action; the primary's accessible name is "Encrypt journals"; both fields use the new-password type. |
| D | PIN, agent cleanup, build 16 fixture | The App Lock PIN migration and the local agent cleanup stay (6.3, with a third criterion: a default must not be a weaker protection or leave a credential); only the window-layout strings go (6.2); fixtures are written by build 16 and by build 19 (8, test 1). The former O2 is no longer a question. |
| Owner decisions | O1 badly framed, O2 not a decision, one missing | O1 is replaced by the conditional exit; O2 is dropped; the minimum length for new passwords is the one decision (9). |
| Test and interop notes | Additions | Failure types, kills at each marker state and the background expiry (8, test 2); a build 19 device rejoining after a 1.1 purge, run against the build 19 client (8, test 7); the Windows and Android row is stated as the specification they will follow, since `apps/windows` holds only a README (3.8). |

**Other change: the single-file archive.** [1-1-archive-v2.md](1-1-archive-v2.md) (another author's record, not edited here) proposes in its own review that the new file format hold recovery formats 1 and 2 only. This record agrees. Restoring an unencrypted archive therefore happens only from a 1.0 directory archive on Apple 1.1, ends in the form, and never reaches Windows or Android; if that record keeps a plaintext variant, the restore path is the same and the Windows and Android rows would need the form's variant A (3.5, 3.8, 11).

**Not changed.** The structure of the form, the reuse of the shipped engine, the variants A to D, the merge of Check Your Password into Change Password, the C rule and its three text changes, and the finding that the schema migrations must stay.

### After the second review

The second review (below) approved with changes and found no Blocker. Each finding and what the body now says:

| # | Finding | What changed |
| --- | --- | --- |
| 1 | Material: Not Now reachable by anyone (Cancel loophole); "launch" undefined | The person's own Cancel returns to the plain form and never unlocks Not Now; failures, `background` expiry and a lock-triggered stop that left an error do (3.4 table). Offline offering Not Now is stated as by design and as the only deliberate way a healthy synced library stays unencrypted (3.4, 10). "Launch" is a cold start of the process; Not Now is in memory only and survives backgrounding, unlock, a new Mac window and the network returning; no remember setting; the iPhone repeat cost is stated, with Stop Syncing… and Sign In… kept prominent. |
| 2 | Material: the form from Settings has no way out | Opened from Settings, or after Not Now in this launch, the form is a sheet over the journals with Cancel (Escape on the Mac); the root takeover is only at launch and for variant C re-entry. Added to the routing test (8). |
| 3 | Material: read-only is not what 1.0 does | `pauseWriting(true)` at Encrypt, after the final flush and before the pre-sync, released on every exit; every writing control disabled with a reason on all devices; incoming `.journalarchive` opens wait (`openPendingArchive`); reading is live until the copy starts; the iPhone and iPad presentation is called a new surface; Cancel's accessible name is "Cancel encryption" (3.4, 7, 8). |
| 4 | Material: unfinished precedence and Stop Syncing | A saved marker with the server switched, or a run in progress, comes before the form in the routing order; adoption is its own operation (not `stopSyncing`, which refuses while `replacingVault`) that first makes one bounded `serverAdopted` check and then either commits the staged copy or discards it; `finishInterruptedEncryption` gets a timeout offering the same two buttons; tests for "not switched" and a hung server (3.4, 7, 8). |
| 5 | Material, process: the revision shrinks G | Section 9 now ends with exactly two items, the first asking the owner to confirm that G in 1.1 means "no new unencrypted libraries; existing ones are asked to encrypt, with Not Now only when it can't succeed", with the full removal in a later release. The G row in section 1 and the `parity.yaml` text for `continue-without-encryption` say so (1, 3.9, 9). |
| 6 | Material: the minimum length | Recommendation stays a blocking 8, hint-only rejected, rule tightened as the reviewer asks: grapheme clusters, no composition rules, spaces allowed, no upper limit below 64, a shared `VaultCrypto.minimumNewPasswordLength` used in the model layer plus a spec rule in `spec/` for Windows and Android, `minimumPasswordLength` stays 1 for unlocking, checked on tap and never live, optional extras off by default; test that existing short passwords still unlock, sign in and open archives (9, 7, 8, 3.9). |
| 7 | Minor: the sync hold | The gate is in `sync()` and `AgentCopyPublisher` (the `waitsForPerson` precedent); test 2 says "no sync or write request" (3.4, 8). |
| 8 | Minor: the strong-password claim | The sentence is removed; the spec makes no promise until it is checked on a real iPhone and Mac for an app with no associated domain; the minimum, Verify, the note and the Done line carry the weight (3.3). |
| 9 | Minor: the note hidden by the keyboard | On iPhone and iPad the form no longer auto-focuses; the Mac still does after 0.4 seconds; the note stays above the button with the keyboard up (3.4). |
| 10 | Minor: iPhone copy loops on `background` | `isIdleTimerDisabled` while the work runs, restored on every exit; `library.encrypt.duration` adds "Keep My Journal open." on iPhone and iPad (a `mac` variant without it) (3.4). |
| 11 | Minor: "turned on elsewhere" outcome | A row in the error table: the form switches to variant C with Not Now offered (3.4). |
| 12 | Minor: ten seconds with nothing to escape | Not Now appears when the check fails, when the system reports no network path, or after about 3 seconds; 10 seconds remain for the variant decision (3.4). |
| 13 | Minor: Import as New Journals overstated | Scoped to an encrypted library; into an unencrypted one the journals stay readable until the form runs (3.5). |
| 14 | Minor: the lost-Keychain limit | One more line for the guide and release notes: the master password is needed to restore app data to a new phone (3.7). |

The reviewer's notes on copy stand: `library.encrypt.stopSyncing.message` keeps "won't be able to sync with {host} again", which errs on the safe side.

## Second independent review (2026-10-09)

Reviewer: independent design and security reviewer, given the requirements and the revised record. Checked against `EncryptionOperations.swift`, `EncryptionUpgrade.swift`, `StoreReencryption.swift`, `SupersededLibraries.swift`, `LibraryOpening.swift`, `SyncSchedule.swift`, `SyncHealthOperations.swift` (`stopSyncing`), `SaveFailureNotice.swift` (`EncryptionPauseNotice`), `EraseOperations.swift`, `RootView.swift` (`onOpenURL`), `PasswordAutofill.swift`, the entitlements, `spec/flows/stop-syncing.md` and the scope record. No build or simulator was run.

**Verdict: approve with changes.** There is no Blocker. The first review's Blocker is resolved structurally: a library that cannot be encrypted now opens as it did in 1.0, offline and low-space people keep their journals, and reading stays available while the work runs. Findings 1 to 5 are Material and are edits to the record (plus one owner confirmation), not a redesign; they need no second full review, but 1, 2 and 5 should be re-read by whoever applies them. The mechanisms checked against the code hold: the copy-verify-switch engine, the marker recovery, the single configuration write, and the superseded-library removal.

### Resolution of the first review

| # | Resolved in the body? |
| --- | --- |
| 1 Blocker (no exit) | Yes, with defects: see findings 1, 2 and 3. |
| 2 Weak passwords | Yes, pending the owner decision; see finding 6 for the recommendation and finding 8 for the autofill claim. |
| 3 Thin safeguards | Yes: Verify, advice, Done line, the immediate removal stated. See findings 8 and 9 for what the claims rest on. |
| 4 Stop Syncing for transient errors | Yes. Unreachable gets Try Again and Not Now only; the message states the consequence. |
| 5 Plaintext-server dead end | Yes: the refusal points at the action, and the three routes are written down. |
| 6 Unfinished strands people | Yes in the design; the implementation note in finding 4 is needed. |
| 7 Copy | Yes. |
| 8 Lost password safeguard | Yes: pointer in Export Archive plus the saved message. |
| 9 Friction, offline | Yes, with the small gaps in findings 9 and 10. |
| Accessibility, D | Yes. |

### Material

**1. "Conditional" Not Now is reachable by anyone, and the record does not say whether that is intended. (Material)**
The table in 3.4 offers Not Now after "a run ... was cancelled". Any person, on any healthy library, can type a password twice, press Encrypt and press Cancel (Cancel is enabled until the server step), and Not Now appears. Airplane mode does the same for any synced library. For a local-only library the Cancel route is a race against a copy that takes under a second for a small journal, so the exit is easy for some people and nearly unavailable for others. That asymmetry is accidental. The text "A healthy library sees only Encrypt" is therefore true only for people who do not touch Cancel.
Fix: decide and write it down. Recommended: a person's own Cancel is not a failure; it returns to the plain form (Not Now only if the check conditions already offer it). Failures, including `background` expiry and a lock-triggered stop that left an error, keep Not Now. Record in section 10 that going offline offers Not Now by design ("works offline" requires it) and that this is the only deliberate way a healthy synced library stays unencrypted. If the owner prefers a soft exit for everyone, drop the word "conditional" and say so, rather than leaving a rule that an obvious gesture defeats.
Also define "launch" in the spec: a cold start of the app process. Not Now is held in memory; it is not cleared by backgrounding, unlocking, a new Mac window or the return of the network. On iPhone, where the system ends the process often, the form will return at each cold start for a person who chose Not Now because their server is too old or gone; that is the cost of the owner's rule and is bounded to one extra tap, but Stop Syncing… (non-transient states) or Sign In… (variant C) are the ways out and the form should keep them prominent. Do not add a "remember my choice" setting; that would silently become permanent.

**2. The form opened from Settings ▸ Turn On Encryption… has no way out when the check is healthy. (Material)**
Section 3.4 says Turn On Encryption… "brings the form back", and the form has no toolbar and shows Not Now only on failure. A person who earlier chose Not Now because the server was unreachable, then taps Turn On Encryption… in Settings after the connection returns, lands on a full-window form with a passing check, no Cancel and no Not Now. They cannot return to their journals without encrypting or force-quitting. This is a coercion the owner did not ask for and it breaks "nobody is locked out" in miniature.
Fix: when the form is opened by the person from Settings, or after Not Now has been chosen in this launch, always show the secondary button (label it Cancel in that case, Escape on the Mac) and say which presentation applies: recommended is a sheet over the journals from Settings, the root takeover only at launch and for variant C re-entry. Add the case to the routing test.

**3. Read-only while encrypting is not what 1.0 does, and the engine must change for it to be true. (Material)**
Verified: `EncryptionUpgrade.pausesWriting` is true only for `.encrypting`, `.updatingServer` and `unfinished`; `AppModel.pauseWriting(true)` is called inside `encrypt` after `synchronizeBeforeEncrypting`. So in 1.0 writing is allowed during Checking and Syncing, and the record's "writing is paused, as in 1.0" and "read-only with a notice from Encrypt" differ from the code. On the Mac the notice exists (`EncryptionPauseNotice`, Mac only). On iPhone and iPad 1.0 showed a modal sheet over the app, so the journals were not interactive at all: a read-only, scrollable journal list with an editor, search and pins is a new surface there, not a reuse.
Fix, in 3.4 and section 7:
- Call `pauseWriting(true)` at Encrypt, after the final flush and before `synchronizeBeforeEncrypting`, and release it on every exit (cancel, failure, done). `turnOnEncryption` and `checkEncryptionReadiness` guard on `!replacingVault`, so the order matters and must be tested.
- State that every writing control is disabled with a reason on iPhone and iPad as well. Today many `replacingVault` guards simply return (new entry, delete, import image, move, restore, pin), so a tappable but dead button would be a defect. Include external entry points that are not menu commands: `onOpenURL` for `.journalarchive` files and Finder double-click wait (as `pendingArchive` already waits for `locked` and `libraryProblem`) until the form and the work are over, then offer the import; add the state to `openPendingArchive`'s conditions.
- Incoming sync during the Syncing phase changes the list under the reader; that is fine, but say reading is live until the copy starts.
- Name the Cancel button's accessible name "Cancel encryption" so it is not confused with cancelling something in the journals behind the notice.

**4. The unfinished state needs a defined precedence at launch and its own Stop Syncing implementation. (Material)**
- Routing. At launch, `finishOpening` already calls `encryption.finishAfterLaunch()` for a marker with `contactingServer`. The record's order ("... first-launch screen, the form, recovery key, journals") does not say that the unfinished marker, and a run that is in progress, take precedence over the form. Without it a library with a switched server would show the form (variant C) before it is allowed to finish. Add: marker present means journals read-only plus the notice; the form is shown only with no marker.
- `AppModel.stopSyncing` starts with `guard ... !replacingVault`, and the unfinished state is `replacingVault == true` (writing paused). The existing Stop Syncing therefore does nothing there. The adopt path in 3.4 must be a new operation that commits the staged copy (as `commitEncryption` does) and then removes the connection, not a call to `stopSyncing`. Say so in section 7.
- When Stop Syncing is pressed from the unfinished notice, try one bounded `serverAdopted` check first. If the server answers "not switched", keep the original library, discard the copy and drop the connection (nothing was lost and no adoption was needed); if it answers "switched" or cannot answer, adopt the encrypted copy. The confirmation text already fits both. Add a test for the "not switched" answer.
- `finishInterruptedEncryption` has no timeout (a hung server holds the read-only state indefinitely); bound it like the form's check and offer the same two buttons when it expires.

**5. Offering Not Now and keeping every unencrypted path is a scope change against the owner-approved G, and the record presents it as settled. (Material, process)**
`release-1-1-scope.md` says G means "Continue Without Encryption and Turn On Encryption go away". The revision keeps Turn On Encryption… in Settings, the readable-archive authentication, the unencrypted footers, the passwordless join and Use a Recovery Code, and `SyncHealth.signInNeeded`, and moves their removal to a release "not before 1.2". That is the right engineering answer to the first Blocker, but it is the owner's product decision: the simplification G delivers in 1.1 shrinks to "no new unencrypted libraries". The owner approved the screen, not this cost.
Fix: add a second line to section 9 as an acknowledgement, not a new question: "1.1 ships with a conditional exit, so unencrypted libraries and their code remain until a later release; confirm." Also reflect in section 1 (the G row) and in `parity.yaml` text that `continue-without-encryption` goes but the unencrypted library persists for 1.0 holders.

**6. The minimum-length recommendation (section 9): agree with a blocking minimum of 8, reject the hint-only alternative, and tighten the rule. (Material, for the decision)**
Why 8 and blocking: the master password wraps the vault key in an envelope held by the server and by archives, so the limit is the offline-guessing cost at 600,000 PBKDF2 iterations; a hint-only policy lets the mandatory screen collect a one-character secret, which AGENTS.md rules out. Eight is the floor I would accept, not a strong value; it is defensible only because most people should be offered a generated password. Conditions to put in the record:
- The rule is a shared product rule, so it goes in `spec/` (README or the password flows) for Windows and Android as well, and `VaultCrypto` (JournalCore) carries a `minimumNewPasswordLength` constant used by the model layer (`start`, `turnOnEncryption`, change password, set password after Forgot Password?), not only the views. `minimumPasswordLength` stays 1 for unlocking and signing in; a test proves an existing short password still unlocks, signs in and opens archives.
- Count characters as the user sees them (grapheme clusters), no composition rules, spaces allowed, no upper limit below 64.
- Reject nothing else by default. If the owner wants one more guard, a short built-in list of the commonest passwords (for example all-same-character and "12345678") is cheap and visible; leave it optional.
- Do not show the error live while typing; check at Create, Encrypt, Change and Set as proposed, and keep the field error under Master Password.
- Optionally a non-blocking line under the field below 12 characters; it is the one concession toward the earlier decision and costs a key, so leave it out unless the owner asks.

### Minor

**7. "Hold the sync" is described as the loop but the gate must be at `sync()`. (Minor)** Automatic sync is one loop (`synchronizeAutomatically`), but `sync()` is also called from `JournalLifecycleView` (export preparation), `EntryRecoveryNotice` and Sync Now rows, and `configureSync` creates `AgentCopyPublisher`, which requests publishing after a sync. Put the hold in `sync()` and the publisher (the existing `waitsForPerson` flag is a precedent), and reword test 2 ("no request reaches the fake server") to "no sync or write request": the readiness check and `finishAfterLaunch` legitimately read the server before the person chooses.

**8. The strong-password claim is unverified. (Minor)** Section 3.3 calls the `.newPassword` content type "the main protection against a hurried or weak password" and says a password manager saves it. The project has no Associated Domains entitlement (searched the entitlements and `project.yml`), and `passwordAutofill(creating:)` only sets the content type. Check on a device that iPhone and Mac offer and save a strong password for an app with no associated domain. If not, soften the sentence in the spec to what is true, and let the minimum, Verify and the Done line carry the weight.

**9. The note under the fields is hidden by the keyboard on the smallest iPhone. (Minor)** The record fits the fields, note and button on the first screen of the smallest iPhone but also auto-focuses Master Password 0.4 seconds in. The keyboard and the strong-password bar cover about half the screen, so the advice note (the safeguard from the first review) is below the visible area when the person starts typing. Fix: on iPhone do not auto-focus (VoiceOver heading focus is enough), or move `library.createLibrary.advice` above the fields.

**10. A long copy on iPhone can loop on `background`. (Minor, but now every 1.0 library meets it)** The run relies on `beginBackgroundTask`, which gives about 30 seconds after the app leaves the foreground. Auto-Lock after a minute of no touching sends the app to the background mid-copy, ending in `messages.encryption.background` and Try Again, which does the same again for a large image library. Set `isIdleTimerDisabled` while the work runs (as `AddDeviceView` already does), restore it on every exit, and add "Keep My Journal open." to `library.encrypt.duration` for iPhone and iPad.

**11. The error table lacks the "turned on elsewhere" outcome. (Minor)** `EncryptionFailure.turnedOnElsewhere` is thrown when the purge answers `alreadyEncrypted` and `lostAccess` classifies a refused device that way during the pre-sync. The table has no row for it, so a second device that raced the first would show a generic error. Add: switch the form to variant C with `library.encrypt.messageSignIn`, Not Now offered.

**12. The check shows nothing to escape for up to 10 seconds, every launch. (Minor)** Offline phones fail immediately, but a flaky link holds the journals back for the full bound each cold start. Show Not Now as soon as the check fails, when the system reports no network path, or after about 3 seconds, whichever comes first; keep the 10 seconds for the variant decision.

**13. Section 3.5 overstates Import as New Journals. (Minor)** "Added under this library's key and are encrypted" is true for an encrypted library only. Into an unencrypted library (Not Now) the imported journals are plaintext until the form runs. The test is already scoped to an encrypted library; scope the sentence the same way.

**14. One honest limit to state in the guide and release notes. (Minor)** The unencrypted-library plaintext survives a lost Keychain; the encrypted one does not. A person who restores an app-data backup to a new phone without the password, after the immediate removal of the readable copy, cannot open the journals. The record states the trade-off; add one line in the guide that the password is needed for that restore, since Check Your Password no longer proves the person can produce it.

### Notes on the specific questions

- **When Not Now appears.** Well defined by the table except for the Cancel loophole (finding 1) and the Settings entry (finding 2). The "launch" definition is the other missing piece. It does not loop within a launch; across launches it repeats once per cold start for a person who keeps choosing it, which is the owner's rule.
- **Read-only on the three devices and with sync.** Coherent in design, not in the engine: pausing starts too late and the iPhone and iPad presentation is new (finding 3). Sync and the paused editor interact correctly once the pause covers the Syncing phase, because `holdSynchronization` already keeps a sync from running across the switch. Mac: the notice exists and only needs the device-neutral text. iPad: multiple scenes read the same app-level state, which is right.
- **Copy.** Plain and honest. `library.encrypt.message` now explains the change; `library.encrypt.stopSyncing.message` states the consequence ("won't be able to sync with {host} again" is slightly absolute, because a later join through Merge Journals is possible if the server is encrypted elsewhere, but it errs on the safe side and I would not change it). The only wording risk is `Cancel` on the notice (finding 3).
