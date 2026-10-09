---
id: encrypt-journals
title: Encrypt your journals
features: [encrypt-existing-journals]
sources:
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Model/EncryptionOperations.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/LibraryOpening.swift
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/enable-encryption.md
---

# Encrypt your journals

## Purpose

Moves a library that isn't encrypted to encryption with a master password, on this device and on its server, without losing anything, without other devices silently diverging, and without ever locking the person out of their own journals. The screen, its variants and its exits are in `screens/encrypt-journals`; this file is the work and its errors.

Only libraries made before this version can need it: Continue Without Encryption and Don't Encrypt no longer exist, so nothing creates an unencrypted library, and an unencrypted archive can only be restored and then encrypted here.

## Entry points

- The form at launch, or as a sheet from Settings ▸ Privacy ▸ Turn On Encryption… (`screens/encrypt-journals`, Entry points).
- Restoring an unencrypted archive onto a device with no journals (`flows/import-archive`).

## What a library can be

The library's format decides what is offered:

| Format | Called in the app | Content | Here |
| --- | --- | --- | --- |
| 2 | Master Password | encrypted | Opens as it did; never shows this screen. |
| 4 | none | readable | The form. |
| 3 | Access Password (early versions) | readable, with a password only a server checks | The form; it asks for the access password only when the library is on a server. |
| 1 | Recovery Key (early versions) | encrypted | Opens as it did; no conversion. |

## Steps

**One library, local only.** Launch → (lock screen) → the form → the password twice → Encrypt:

1. The open entry is saved (nothing is open at launch). The free-space check needs the library's size plus 50 MB. The journals become read-only and the notice appears.
2. A new random vault key and a master-password envelope are made. The key is stored in the device's secure storage under a new name and a marker is saved so a crash can be cleaned up.
3. A copy of every record, history row, conflict and image is sealed under the new key with the same identities. Records this version can only read are copied byte for byte, not re-encoded. Pins, journal order and Version History are inside those rows. Progress is `settings.encryption.progress`.
4. The copy is validated: the schema, the snapshot and every row compared, decrypted, against the source. A failure leaves the old library unchanged and shows `messages.encryption.failed`.
5. One write of the library's settings switches to the copy, keeping App Lock, Lock when inactive, the last journal and entry, and the default journal. The old folder and key become a superseded library.
6. The encrypted library opens. The readable folder and the old key are removed after it has opened (and synced, if connected). Nothing readable remains in the app's data. The Done sheet appears and `messages.encryption.announce.done` is announced.

**A synced library** adds, after step 1 and before the copy is made:

- The journals are synced first, including every image: images are downloaded until a pass gets none; if the server still has images this device lacks, it stops (`messages.encryption.imagesMissing`).
- After the copy is validated, the server is asked to switch to the encrypted copy (`settings.encryption.updatingServer`, announced; can't be cancelled). Under one write gate it deletes the old records, changes, operations, attachments and the old backup copy, revokes every other device and every agent grant, and stores the new envelope. If another device wrote meanwhile, the copy is made again once; a second time stops with `messages.encryption.stillSyncing`.
- If the answer is lost, the server's envelope is compared with the marker's: switched means carry on, not switched means unreachable, unknown means unfinished.
- After the switch everything is sent again from the new library, matched by content, so another device that signed in first creates no duplicates.

The current access password (recovery format 3 only) is checked before anything else (`messages.encryption.incorrectPassword`, `messages.encryption.rateLimited`).

**After success,** other devices see `messages.sync.signInNeeded` and use Reconnect… (`flows/reconnect-to-server`): they sign in with the master password and encrypt their own copy, keeping their identities and unsynced changes.

## Errors

Every error is announced. Field errors are the field's hint and move focus there.

| When | Message (key) | Where | Next |
| --- | --- | --- | --- |
| Not enough space | `messages.encryption.notEnoughSpace` ("There isn’t enough space to encrypt your journals. Free up {size} and try again.") | Form or failure notice | Try Again, Not Now |
| Couldn't reach the server (checking or encrypting) | `common.couldntReachHost` | Form or failure notice | Try Again, Not Now |
| The server is too old (protocol revision below 1) | `messages.connection.serverNeedsUpdate` | Form | Not Now, Stop Syncing… |
| This device lost access | `messages.encryption.accessLost` ("This device no longer has access to {host}. You can stop syncing to encrypt your journals on this device.") | Form | Not Now, Stop Syncing… |
| Wrong access password | `messages.encryption.incorrectPassword` | Under Current Access Password | Not Now, Stop Syncing… |
| Too many attempts | `messages.encryption.rateLimited` | Under Current Access Password | Not Now, Stop Syncing… |
| Encryption was already turned on from another device (the server answers that it is already encrypted, or access was refused during the first sync) | `library.encrypt.messageSignIn` | The form switches to variant C | Reconnect…, Not Now |
| Another device wrote meanwhile (twice) | `messages.encryption.stillSyncing` | Failure notice | Try Again, Not Now |
| Images missing | `messages.encryption.imagesMissing` | Failure notice | Try Again, Not Now |
| Background time ran out (phone/tablet) | `messages.encryption.background` | Failure notice | Try Again, Not Now |
| The server switched, this device couldn't finish | `messages.encryption.unfinished` | Unfinished notice (journals read-only) | Try Again, Stop Syncing… |
| Anything else, including a copy that failed verification | `messages.encryption.failed` ("Your journals couldn’t be encrypted. They are unchanged.") | Failure notice | Try Again, Not Now |
| The passwords differ | `messages.connection.passwordsDontMatch` | Under Verify | Correct |
| Encrypted, but the journals can't be shown | `messages.refresh.encryptionOn` | The app's error alert | Reopen |

## Rules

- **Nothing is lost.** Identities, history and images are kept; changes from other devices are received first; if another device writes during the switch, the copy is redone once. The old library is never touched before the new one is verified, and a crash leaves it as it was.
- **Cancel** stops the work until the server step, releases the pause and shows the plain form again; the staged copy and its key are removed. It never unlocks Not Now by itself.
- **A failure** removes the staged copy, resumes writing, and shows the failure notice. The password is held in memory only.
- **Locking** cancels the work if it can still be cancelled; once the server is being updated it continues.
- **The server switch is the one irreversible step.** Its recovery (the marker, the comparison of the server's envelope, the unfinished state) is how a lost answer, a quit, a crash or an expired background time end: before the switch the copy is discarded and the form starts again; after it the next launch finishes the job.
- **Unfinished: Stop Syncing is its own operation,** not the ordinary Stop Syncing (which refuses while the journals are being replaced): one bounded check of what the server did, then either commit the verified encrypted copy or discard it, and drop the connection (`screens/encrypt-journals`, Exits).
- **Encrypting is never silent:** the app never invents a master password; the person chooses it (`spec/README.md`, Master passwords).
- A server whose recovery format is 3 or 4 is refused by every device that has an encrypted library or none (`flows/connect-to-server`). A device with an unencrypted library, the one that runs this flow, keeps its own unencrypted server until the flow encrypts both.

## Mixed fleets

| Situation | What happens |
| --- | --- |
| Earlier devices, all encrypted; one updates | Nothing changes. Same formats, protocol and server. |
| Earlier devices, all unencrypted, one server; device A updates | A shows variant B. A encrypts and switches the server; every other device is revoked. An earlier-version device then shows "Encryption was turned on from another device. Sign in to keep syncing." and signs in with the master password. |
| …then device B updates before signing in | B shows variant C and signs in the same way; its offline edits that conflict keep both versions ([flows/resolve-conflict.md](resolve-conflict.md)); nothing is lost. |
| …then device B (unencrypted, this version) is offline | B shows variant D; Not Now opens it as before until it can reach the server. |
| A new device joins that server before any old device updated | Refused with `messages.connection.encryptionOff`; nothing is sent. |
| Windows and Android | They never create unencrypted libraries and have none to migrate. They refuse a server whose recovery format is 3 or 4 with `messages.connection.encryptionOff`. They have no form, Not Now, Stop Syncing for this purpose, or sign-in variant. This is the specification they will follow, not code that exists. |

## Accessibility

- Progress is announced as a percentage; every state change and error is announced (`screens/encrypt-journals`, Accessibility).

## Platform notes (Apple)

- iPhone and iPad ask the system for background time and keep the screen awake while the work runs; if background time expires before the server is updated, the work is cancelled and `messages.encryption.background` shown. The idle timer is restored on every exit. With App Lock on, leaving the app locks first, which cancels the work if it can still be cancelled.
- The Mac needs neither.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
