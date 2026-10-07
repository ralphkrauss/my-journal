---
id: turn-on-encryption
title: Turn on encryption
features: [turn-on-encryption]
sources:
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Model/EncryptionOperations.swift
  - apps/apple/JournalApp/Views/TurnOnEncryptionView.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - docs/design/enable-encryption.md
---

# Turn on encryption

## Purpose

Moves journals without encryption to encryption with a master password, on this device and on its server, without losing anything and without other devices silently diverging.

## Entry points

- Settings ▸ Privacy ▸ Turn On Encryption… (only when the journals aren't encrypted).

## Steps

1. **Turn On Encryption** explains what happens. Continue:
   - checks there's enough free space for an encrypted copy;
   - when syncing: checks the server supports turning on encryption and that this device still has access (busy `settings.encryption.checking`).
2. **Choose a Master Password.** Libraries with an access password also need the current one. Turn On (announced `messages.encryption.announce.turningOn`):
   1. The current access password is checked (if needed).
   2. The open entry is saved.
   3. When syncing: everything on the server is received, including every image (busy `settings.sync.syncing`). Images are downloaded until a pass gets none; if the server still has images this device lacks, it stops (`messages.encryption.imagesMissing`).
   4. An encrypted copy of the journals is made, keeping every identity (`settings.encryption.progress`, with progress). Writing is paused from here.
   5. When syncing: the server switches to the encrypted copy (`settings.encryption.updatingServer`, announced; can't be cancelled). If another device wrote meanwhile, the copy is made again once; a second time stops with `messages.encryption.stillSyncing`.
   6. This device opens the encrypted copy; writing resumes.
3. **Your Journals Are Encrypted** (announced `messages.encryption.announce.done`). When syncing, it explains that other devices sign in, and offers Add Another Device….

After success, other devices see `messages.sync.signInNeeded` and use Sign In… (`flows/reconnect-to-server`). Agents with access on the server lose it.

## Errors

| When | Message (key) | Where | Next |
| --- | --- | --- | --- |
| Wrong current access password | `messages.encryption.incorrectPassword` ("That password isn’t correct.") | Under Current Access Password | Correct it. |
| Too many attempts on the server | `messages.encryption.rateLimited` | Under Current Access Password | Wait. |
| Couldn't reach the server, on step 1 | `common.couldntReachHost` ("Couldn’t reach {host}. Check your connection and try again.") | Step 1 | Try Again. |
| Couldn't reach the server, on step 2 | `messages.encryption.unreachable` ("Couldn’t reach {host}. Encryption wasn’t turned on. Check your connection and try again.") | Step 2 | Try Again. |
| Server too old | `messages.encryption.serverOutdated` ("{Host} needs an update before you can turn on encryption.", host capitalised) | Current step | — |
| Not enough space | `messages.encryption.notEnoughSpace` ("There isn’t enough space to encrypt your journals. Free up {size} and try again.") | Current step | Try Again. |
| This device lost access | `messages.encryption.accessLost` ("This device no longer has access to {host}. Connect again in Settings > Devices, then try again.") | Current step | — |
| Encryption was already turned on from another device | `messages.encryption.turnedOnElsewhere` | Current step | Primary becomes Sign In…; Settings ▸ Privacy then offers Sign In…. |
| Other devices still writing | `messages.encryption.stillSyncing` ("Your other devices are still syncing. Wait for them to finish, then try again.") | Current step | Try Again. |
| Images not downloaded | `messages.encryption.imagesMissing` | Current step | Try Again after a moment. |
| Server switched, this device couldn't finish | `messages.encryption.unfinished` ("Your journals are encrypted on {host}, but this device couldn’t finish. Free up space, then try again.") | Step 2, unfinished | Only Try Again; writing stays paused; at the next launch it finishes or shows this again (phone/tablet: the sheet over the app; computer: Settings ▸ Privacy). |
| The app was in the background too long (phone/tablet) | `messages.encryption.background` ("Encryption stopped because My Journal was in the background. Keep My Journal open and try again.") | Current step | Try Again. |
| Anything else | `messages.encryption.failed` ("Encryption wasn’t turned on. Your journals are unchanged.") | Current step | Try Again. |
| The new fields differ | `messages.connection.passwordsDontMatch` | Under Verify | Correct. |
| Encrypted, but the journals can't be shown | `messages.refresh.encryptionOn` ("Encryption is on, but your journals couldn’t be displayed. Reopen My Journal to try again.") in the app's error alert | App | Reopen. |

Every error is announced.

## Rules

- Encryption can't be turned off.
- Cancelling before the server is updated leaves the journals unchanged; the copy is discarded.
- Nothing is lost: identities, history and images are kept; changes from other devices are received first; if another device writes during the switch, it is redone once.
- Writing is paused from encrypting until finished; on the computer the journal window says so (`messages.writingPaused.encrypting`).
- Locking cancels the work if it can still be cancelled; once the server is being updated it continues.
- Archives and backups made earlier stay unencrypted (`settings.encryption.done.archives`).

## Accessibility

- Progress is announced as a percentage; all state changes and errors are announced.

## Platform notes (Apple)

- iPhone/iPad ask the system for background time; if it expires before the server is updated, the work is cancelled and the background error shown.
- Mac: the journal window's notice and Show Progress.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
