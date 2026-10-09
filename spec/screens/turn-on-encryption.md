---
id: turn-on-encryption
title: Turn On Encryption (sheet)
features: [turn-on-encryption]
sources:
  - apps/apple/JournalApp/Views/TurnOnEncryptionView.swift
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Model/EncryptionOperations.swift
  - docs/design/enable-encryption.md
---

# Turn On Encryption

## Purpose

Encrypts journals that aren't encrypted, on this device and, when syncing, on the server, with a new master password. It can't be undone. The flow, with every error, is `flows/turn-on-encryption`.

## Entry points

- Settings ▸ Privacy ▸ Turn On Encryption… (`screens/settings-privacy`).
- Computer: the journal-window notice's Show Progress.
- Phone/tablet: shown over the app at launch when a previous run switched the server but this device couldn't finish.

## Content

A sheet with a navigation stack of three steps. On the computer before macOS 26 a heading row repeats the title (sheets there have no title bar).

### Step 1: Turn On Encryption

Title `settings.encryption.title`.

1. Intro (secondary text): `settings.encryption.intro` when not syncing; `settings.encryption.introSynced` ("…on this device and on {host}…") when syncing.
2. When syncing, a section headed `settings.encryption.otherDevices.header` ("Your Other Devices") with three lines:
   - `settings.encryption.otherDevices.update`;
   - `settings.encryption.otherDevices.signIn`;
   - `settings.encryption.otherDevices.agents` ("Agents with access to your journals on {host} lose it. Give them access again afterward.").
3. Footer: `settings.encryption.pauseFooter`.
4. While checking (syncing only): busy row `settings.encryption.checking` ("Checking {host}…").
5. Error row (red).
- Primary: `common.continue`; after an error, `common.tryAgain`; when the error is that encryption was turned on from another device, `common.reconnect` ("Reconnect…"). Disabled while working.
- Cancel: `common.cancel`.

### Step 2: Choose a Master Password

Title `common.chooseMasterPassword`.

1. Intro: `settings.encryption.passwordIntro` ("Your master password encrypts your journals on this device.") or, when syncing, `settings.connect.choosePassword.intro` ("…before they’re sent to {host}.").
2. Libraries with an access password (early versions without encryption) first show a section headed `settings.encryption.currentAccessPassword` ("Current Access Password") with a secure field of that name and its field error.
3. Fields `common.masterPassword` and `common.verify` (new-password autofill), each with its field error; a switch `common.showPassword` ("Show Password"), or `settings.encryption.showPasswords` ("Show Passwords") when the current access password is also shown.
4. Footer: `settings.password.footer`.
5. While working, a status row: `settings.sync.syncing` ("Syncing…"), the encryption progress (`settings.encryption.progress` "Encrypting your journals…" with a progress bar), or `settings.encryption.updatingServer` ("Updating {host}…").
6. Error row.
- Fields are disabled while working and while unfinished.
- Primary: `settings.encryption.turnOn` ("Turn On"), or `common.tryAgain` after an error; when unfinished, `common.tryAgain` (finishes). Disabled until both new fields (and the current access password, if shown) are filled, and while working.
- Back is available only here and only when not working.

### Step 3: Your Journals Are Encrypted

No title in the bar.
1. A centred block: a lock-shield symbol (decorative), heading `settings.privacy.encryption.on` ("Your Journals Are Encrypted"), and `settings.encryption.done.message` ("Only your devices can read your journals.").
2. When syncing: a section headed `settings.encryption.otherDevices.header` with `settings.encryption.done.otherDevices` and a button `settings.connect.ready.addDevice` ("Add Another Device…") → `screens/add-device`; footer `settings.encryption.done.archives`. Otherwise just the footer `settings.encryption.done.archives`.
- Toolbar: only `common.done`.

### Computer: notice in the journal window

While this computer encrypts (or waits for Try Again after the server switched), the journal window shows a notice bar: `messages.writingPaused.encrypting` ("Writing is paused while this Mac encrypts your journals.") or `messages.writingPaused.encryptionUnfinished`, with a button `messages.writingPaused.showProgress` ("Show Progress").

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Continue | `encryption-continue` | Checks free space and, when syncing, that the server can do this and this device still has access; then step 2. |
| Turn On | `turn-on-encryption` | Encrypts (`flows/turn-on-encryption`). |
| Try Again (unfinished) | `encryption-finish` | Finishes the switch the server already made. |
| Reconnect… | `sync-reconnect` | Closes the sheet and opens Reconnect at signing in. |
| Cancel | `encryption-cancel` | Stops the work, as long as the server isn't being updated; closes. Disabled while updating the server; hidden while unfinished. |
| Add Another Device… | `add-device` | Opens Add Device. |
| Done | `encryption-done` | Closes. |
| Show Progress (computer) | `show-encryption-progress` | Opens Settings ▸ Privacy with this sheet. |

## States

- **Checking / Syncing / Encrypting / Updating:** fields locked; status row; Cancel available until Updating.
- **Updating the server:** announced `messages.encryption.announce.updatingServer` ("Updating {host}. You can’t stop this now."); Cancel disabled.
- **Unfinished:** the server switched but this device couldn't open its encrypted copy (for example out of space); only Try Again; the sheet can't be dismissed; writing stays paused.
- **Locked:** locking cancels work that can still be cancelled and closes the sheet.

## Rules

- The work belongs to the app, not the sheet: closing the sheet's window doesn't stop it, and opening the sheet again shows where it is.
- The sheet can't be swiped away while working or unfinished.
- Passwords are cleared from the fields once encryption is on.
- Any non-empty password is accepted; the two new fields must match.

## Accessibility

- Progress is one element: label `settings.encryption.progressLabel` ("Encrypting your journals"), value `settings.encryption.progressValue` (“{percent} percent”).
- Announcements: `messages.encryption.announce.turningOn` ("Turning on encryption") when Turn On starts, the updating announcement, `messages.encryption.announce.done` ("Your journals are encrypted.") at the end, and every error.
- Field errors are the fields' hints; focus moves to the field with the error.

## Platform notes (Apple)

- Mac: a sheet on the Settings window, about 480 × 560 points; Cancel is always shown on the Mac.
- iPhone/iPad: Cancel shows only where Back isn't available. The app asks the system for time to finish in the background; if that runs out before the server is updated, the work stops (see the flow).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
