---
id: encrypt-journals
title: Encrypt Your Journals
features: [encrypt-existing-journals]
sources:
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Model/EncryptionOperations.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/enable-encryption.md
---

# Encrypt Your Journals

## Purpose

Every library in My Journal is encrypted. Libraries made before 1.1 with Continue Without Encryption, and unencrypted archives restored on a device with no journals, are not. This screen asks the person once to choose a master password and encrypts the journals on this device and, when syncing, on the server. It is the only way an unencrypted library is changed; nothing is created unencrypted any more. The work, every error and every rule are in `flows/encrypt-journals`.

The screen has five parts: the **form**, the **working notice** (the journals read-only while the work runs), the **unfinished** notice, the **Done** sheet, and the **exits** (Not Now, Cancel, Stop Syncing…). It is for the platforms that have such libraries (Apple); other platforms never show it (`parity.yaml`, `encrypt-existing-journals`).

## Entry points

- **At launch**, once the library is open and the person is past the lock screen: the form takes the place of the journals (the window order is in `screens/welcome`). Also when variant C is reached again.
- **Settings ▸ Privacy ▸ Turn On Encryption…** (`turn-on-encryption`, `screens/settings-privacy`): the same form as a **sheet over the journals with Cancel**.
- **After Not Now** has been chosen in this launch, Turn On Encryption… is the way back; it opens the sheet.
- **After Restore Journals** from an unencrypted archive onto a device with no journals: the window shows the form (`flows/import-archive`).
- **A saved encryption marker**, or a run in progress, shows the working or unfinished notice over the journals, not the form (see Rules, precedence).

## Content

### The form

A centred column, at most 480 points wide, scrolling at large text sizes, like Start a Journal (`flows/create-library`). In order:

1. A lock-shield symbol (decorative).
2. Heading `library.encrypt.title` ("Encrypt Your Journals").
3. A paragraph that depends on the variant (below).
4. **Variant B only:** a section headed `settings.encryption.otherDevices.header` ("Your Other Devices") with three lines: `settings.encryption.otherDevices.update`, `settings.encryption.otherDevices.signIn`, `settings.encryption.otherDevices.agents`.
5. **Variants A and B:** the fields, none pre-filled:
   - `settings.encryption.currentAccessPassword` ("Current Access Password"), only for a library with an access password (recovery format 3) that is on a server;
   - `common.masterPassword` and `common.verify`, both **new-password fields** (`flows/create-library`, Rules), each with its field error;
   - a switch `common.showPassword` ("Show Password"), or `settings.encryption.showPasswords` ("Show Passwords") when the current access password is also shown.
6. **Directly under the fields,** `library.createLibrary.advice` (variant A) or `settings.password.footer` (variant B); under that, `library.encrypt.duration`. In variant A the fields, this note and the Encrypt button fit the first screen of the smallest supported phone at the default text size without scrolling; variant B starts with the other-devices section and scrolls. With the keyboard up the note stays visible above the button.
7. An error in red, selectable, when there is one.
8. The primary button, large and prominent: `library.encrypt.action` ("Encrypt", accessible name `library.encrypt.action.accessibilityLabel` "Encrypt journals"); `common.tryAgain` after an error; `common.reconnect` ("Reconnect…") in variant C.
9. Plain text buttons below the primary button, at least the standard minimum hit size, always reachable without scrolling past the primary button at the largest text size, each only in the situations listed under Exits: `library.encrypt.notNow` ("Not Now") and `settings.sync.stopSyncing` ("Stop Syncing…").

When the form is a sheet (from Settings, or after Not Now in this launch) it also has Cancel (`common.cancel`, Escape on a computer) in the sheet's bar. At launch there is no bar: there is nothing to dismiss.

**Variants**

| | When | Paragraph |
| --- | --- | --- |
| A | No server | `library.encrypt.message` |
| B | A server that doesn't use encryption yet | `library.encrypt.messageSynced` ({host}) |
| C | The server already uses encryption (another device turned it on, or the server was replaced) | `library.encrypt.messageSignIn` ({host}); no fields; primary Reconnect… |
| D | A synced library whose server can't be used right now | the B paragraph, the error, no fields until the check passes |

**The check (synced libraries).** A synced library first shows a busy row `settings.encryption.checking` ("Checking {host}…") with a spinner in place of the fields. The app reads the server's public encryption details and checks that this device still has access, that the server supports turning on encryption, and that there is enough free space. The check is bounded at about 10 seconds for choosing the variant; if it hasn't finished, the screen becomes variant D with `common.couldntReachHost`, and a late answer only enables Try Again. **Not Now appears sooner:** as soon as the check fails, when the system reports no network path, or after about 3 seconds, whichever comes first, so a flaky link never holds the journals back for the full bound at every launch. The result chooses B, C or D, and the screen reader hears which one replaced the spinner (the variant's paragraph, or the error). A library with no server skips the check and shows A at once, though it still checks free space when Encrypt is chosen.

**Variant C, Reconnect….** Opens Connect to a Server over the screen with this server chosen and checked, at the Enter Master Password step, exactly as Settings ▸ Sync's Reconnect… does for encryption turned on elsewhere (`flows/reconnect-to-server`). Signing in encrypts this device's own library with the server's key, keeping identities and unsynced changes, and the screen gives way to the journals when it finishes. Use a Connected Device Instead… works there as it does anywhere, and a replaced server that holds another library still gets Merge Journals before anything is sent. Its intro and footer are `settings.connect.signIn.introEncrypted` and `settings.connect.signIn.footerEncrypted`, unchanged.

### The working notice

From the moment Encrypt is chosen the journals are visible and **read-only**, with a notice at the top of the journal window (computer) or above the content of every stacked screen and column (phone, tablet):

1. The text `messages.writingPaused.encrypting` ("Writing is paused while your journals are encrypted.").
2. A status row: `settings.encryption.checking`, `settings.sync.syncing` ("Syncing…"), `settings.encryption.progress` ("Encrypting your journals…") with a determinate progress bar, or `settings.encryption.updatingServer` ("Updating {host}…").
3. Cancel (`common.cancel`, accessible name `settings.encryption.cancel.accessibilityLabel` "Cancel encryption", so it isn't taken for cancelling something in the journals behind it; Escape on a computer), disabled while the server is being updated.

At accessibility text sizes the notice stacks: text, progress, button. The editor shows the read-only note it shows whenever writing is paused (`flows/save-failure`). Every writing control (New Entry, delete, insert image, move, restore, pin, import and the like) is disabled **with a reason** on every device; none is left tappable and dead. Reading, searching and exporting work. Reading is live until the copy starts: changes arriving from the server during the Syncing phase may change a list under the reader.

### The failure notice

A failed run removes the staged copy, returns the journals to full use, unchanged, and turns the notice into the error message (see Errors in `flows/encrypt-journals`) with **Try Again** (`common.tryAgain`) and **Not Now** (`library.encrypt.notNow`). Not Now dismisses the notice; the Settings entry stays.

### The unfinished notice

The server switched to the encrypted copy but this device couldn't open its own (for example the disk filled, or the server is gone after the switch). The journals stay read-only with a notice: `messages.encryption.unfinished`, **Try Again** (`common.tryAgain`, command `encryption-finish`) and **Stop Syncing…** (`settings.sync.stopSyncing`, command `encrypt-journals-stop-syncing`). Stop Syncing here is its own operation: it adopts the encrypted copy (below). Not Now is not offered: the journals are already open.

### The Done sheet

A sheet over the journals (all devices), shown when the work finishes:

1. A lock-shield symbol (decorative), the heading `settings.privacy.encryption.on` ("Your Journals Are Encrypted") and `settings.encryption.done.message`.
2. The line `library.encrypt.done.keepPassword` for everyone.
3. On a synced library, a section headed `settings.encryption.otherDevices.header` with `settings.encryption.done.otherDevices` and a button `settings.connect.ready.addDevice` ("Add Another Device…") that opens Add Device (`screens/add-device`).
4. The note `settings.encryption.done.archives`.
5. `common.done`, the default action; Return and Escape both close the sheet.

A local library gets the sheet too: it is the one place the person learns what to keep and that earlier archives stay readable.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Turn On Encryption… (Settings ▸ Privacy) | `turn-on-encryption` | Unlocked, not encrypted, not replacing the journals (except to show a run in progress) | Opens the form as a sheet with Cancel. |
| Encrypt / Try Again | `encrypt-journals` | The check passed and both new fields (and the current access password, if asked) are filled; not working | Encrypts (`flows/encrypt-journals`). |
| Reconnect… (variant C) | `sync-reconnect` | Variant C | Opens Connect to a Server at signing in. |
| Not Now | `encrypt-journals-not-now` | Only in the situations under Exits | Opens the journals as before this version; asks again at the next launch. |
| Stop Syncing… | `encrypt-journals-stop-syncing` | Only for the states under Exits, and on the unfinished notice | The confirmation below; then stops syncing and encrypts locally (on the form), or adopts the encrypted copy (when unfinished). |
| Try Again (unfinished) | `encryption-finish` | Unfinished, not busy | Finishes the switch the server already made. |
| Cancel | `encryption-cancel` | The working notice: before the server is updated. The sheet: always, until Encrypt is chosen | The notice: stops the work and shows the plain form again. The sheet: closes it. |
| Add Another Device… | `add-device` | Done sheet, synced | Opens Add Device. |
| Done | `encryption-done` | Done sheet | Closes the sheet. |

### Exits

**Not Now** opens the journals exactly as before this version: editing works, sync resumes as it did (an unencrypted library with its unencrypted server, or the sign-in state of variant C with its usual messages), App Lock is as it was. It is offered only where the form cannot succeed or has not:

| Situation | Not Now |
| --- | --- |
| The check passed (healthy B, or A without a server) | Not shown |
| The check didn't finish in about 10 seconds; the server is unreachable, too old, or this device has no access | Shown |
| Not enough free space | Shown |
| Wrong or limited access password | Shown |
| Variant C (it needs a password the person may not have) | Shown |
| A run in this launch **failed** (failed, still syncing, images missing, background time ran out, unreachable, a lock-triggered stop that left an error) | Shown, on the form or on the failure notice |
| The person pressed **Cancel** on a working run | Not by itself: back to the plain form; Not Now only if the check conditions above already offer it |
| Unfinished | Not offered: the journals are already open read-only |

Two consequences are by design. Going offline offers Not Now (working offline requires it), and that is the only deliberate way a healthy synced library stays unencrypted. And a person who keeps choosing Not Now because their server is too old or gone sees the form again at every launch (one extra tap); Stop Syncing… and Reconnect… stay prominent as the ways out. There is no "remember my choice": that would silently become permanent.

**Cancel** on a working run is not a failure and never unlocks Not Now by itself.

**Stop Syncing…** is for states that will not pass by themselves, and is irreversible in practice, so it is offered only when: this device has no access to the server; the server is too old; the access password is wrong or limited. It is not offered for an unreachable server (use Not Now and try again later). The confirmation: title `settings.sync.stopSyncing.title`, message `library.encrypt.stopSyncing.message`, followed by `settings.sync.stopSyncing.messageUnsent` when items haven't reached the server; buttons `settings.sync.stopSyncing.confirm` and `common.cancel`. The message states the consequence: this device can't sync with that server again (an encrypted library is refused by a server without encryption), the other devices keep using it and won't get changes made here, and the journals stay here and are encrypted next. Confirming runs Stop Syncing (`flows/stop-syncing`); the form becomes variant A. Nothing is deleted anywhere. For a server that is too old, the error says first that updating the server is the way to keep syncing, because the person is usually its administrator.

**Stop Syncing… on the unfinished notice** uses the confirmation with the message `library.encrypt.adopt.message`, which fits both outcomes. It makes one bounded check of what the server did. If the server answers that it switched, or can't answer, this device keeps its verified encrypted copy and drops the connection. If the server answers that it did not switch, nothing was lost and no adoption is needed: the original library is kept, the copy is discarded and the connection dropped. Either way nothing is lost. This is the single exit for a server that vanished after the switch.

## States

- **Empty library** (nothing written yet): the same form and flow; fast, no special case.
- **Checking:** `settings.encryption.checking` with a spinner, at most about 10 seconds.
- **Working:** the notice, with `settings.sync.syncing`, the determinate `settings.encryption.progress` bar, and `settings.encryption.updatingServer` (announced as `messages.encryption.announce.updatingServer`; can't be cancelled).
- **Offline:** variant D with `common.couldntReachHost`, Try Again and Not Now. A library that isn't on a server never needs the network. A synced unencrypted library can't be encrypted offline (it would leave the server readable and split the devices), so the person waits for a connection or chooses Not Now.
- **Low space, active household, flaky link, a copy that fails verification:** each leaves the library readable and unchanged and offers Not Now, so none of them locks anyone out.
- **Unfinished:** read-only journals, the notice, Try Again and Stop Syncing…. The next launch tries to finish by itself first and shows this only if that fails; if the server doesn't answer within the bound used for the check, the same two buttons are offered rather than holding the read-only state.
- **Locked:** the lock screen comes first. Locking while working cancels the work if it can still be cancelled (nothing has changed) and otherwise lets it finish.
- **Quit or crash:** before the switch, the staged copy is removed at the next launch and the form starts again; after the server switched, the next launch finishes it. The old library is never touched before the new one is verified.

## Rules

- **Window order** (the same rule after every change of state): `screens/welcome` lists it. A saved encryption marker with the server switched, or a run in progress, comes before the form, so a library whose server already switched is allowed to finish before it is offered the form.
- **Presentation.** At launch (and for variant C re-entry) the form is the root screen. Opened by the person from Settings, or after Not Now in this launch, it is a sheet over the journals with Cancel, so it can never trap anyone.
- **Launch** means a cold start of the app process. Not Now is held in memory only: backgrounding, unlocking, a new computer window or the network returning don't clear it, and nothing stores it.
- **While the form shows,** no sync runs: the hold is a gate in synchronization itself, not only in the automatic loop, because sync is also started by export preparation, the entry-recovery notice and Sync Now; it also covers the publishing of agent copies. The hold ends when the person chooses Not Now or when encryption starts (which syncs once itself, first, so nothing on the server is missed). The form is the same in every window of the app, because the state belongs to the app, not to a window.
- Menu commands that need a library are disabled, as on the first-launch screen, and Import Archive… too. A `.journalarchive` opened from outside the app waits until the form and any run are over, then offers the import.
- Settings shows `settings.encryptFirst` ("Choose a master password to encrypt your journals first.") in place of its panes while the form is the root screen. Once Not Now has been chosen, or the form is a sheet, Settings is normal.
- The library's content is unchanged until the person starts the encryption (the housekeeping every open does, such as numbering journals that share a name, still runs).
- **Read-only from Encrypt.** Writing is paused from the moment Encrypt is chosen (after the final flush, before the first sync) and released on every exit: cancel, failure, Not Now, done.
- **The password** is held in memory only while the form or notice is up, and cleared once encryption is on.
- Choosing the password follows the shared rule in `spec/README.md` (Master passwords): two fields, new-password types, the two must match, no minimum length.
- **The readable copy is removed as soon as the encrypted library has opened** and, when connected, has synced. For a local-only library that is right after it opens. Nothing readable stays on the device and there is no privacy window, but a wrongly remembered password has no plaintext fallback. The mitigations are Verify, the new-password field type, the note directly under the fields and the line on the Done sheet.
- Archives and backups made earlier stay readable (`settings.encryption.done.archives`).
- Encryption can't be turned off.
- Encrypting a synced library removes the server's agent grants; variant B says so.

## Accessibility

- When the form appears the screen reader moves to the heading. Reading order: symbol (hidden), heading, paragraph, other devices, fields, note, error, primary button, Not Now, Stop Syncing…. The variant chosen by the check is announced when it replaces the spinner.
- Every field has a visible label and the new-password type; Show Password reveals both. A field error is the field's hint and is announced after focus moves there. The mismatch (`messages.connection.passwordsDontMatch`) is announced when it appears.
- The primary button's accessible name is "Encrypt journals" (it starts with the visible word, so voice and switch commands don't collide with the heading). Not Now and Stop Syncing… are plain buttons at the standard minimum hit size.
- The working notice is one element for status: label `settings.encryption.progressLabel`, value `settings.encryption.progressValue`. Announcements: start (`messages.encryption.announce.turningOn`), updating the server (`messages.encryption.announce.updatingServer`), done (`messages.encryption.announce.done`) and every error. The notice stays reachable by the screen reader on every screen while the journals are read-only.
- The column scrolls at the largest text sizes and the buttons stack; nothing relies on colour alone. There is no animation beyond the system's.
- Keyboard: Tab follows the reading order; Return moves Master Password to Verify to Encrypt; Cancel on a computer is Escape.
- On a computer, focus lands in Master Password about 0.4 seconds after the form appears. On a phone or tablet it does not (the keyboard and the strong-password bar would cover the note under the fields, and the screen reader already lands on the heading).

## Platform notes (Apple)

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Form | Full-window screen | Full-window screen, column centred; the same in Split View, Slide Over and every window | Fills each journal window (minimum 801 × 420 points); Settings shows `settings.encryptFirst` |
| Default action | Encrypt below the fields; Return in Verify | Same; hardware keyboard Return | Encrypt is the default button; Return |
| Working notice | Above the content on every stacked screen | Above the columns | Top of the journal window |
| Background | Asks the system for background time and keeps the screen awake while working; if the time runs out before the server is updated, stops with `messages.encryption.background` | Same | Not needed |

`library.encrypt.duration` has a `mac` variant without "Keep My Journal open.". The Apple notes are `platforms/apple/screens/encrypt-journals`.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md) (D61 the strong-password offer, D62 a plaintext server with no device).
