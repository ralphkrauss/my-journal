---
id: connect-to-server
title: Connect to a server
features: [sync-connect, server-discovery, server-protocol-revision, server-setup, join-with-local-journals, pair-device-scan, pair-device-code, recovery-code-join]
sources:
  - apps/apple/JournalApp/Model/ConnectionFlow.swift
  - apps/apple/JournalApp/Model/ServerJoining.swift
  - apps/apple/JournalApp/Model/ServerEnvelopeCheck.swift
  - apps/apple/JournalApp/Views/ConnectionView.swift
  - apps/apple/JournalApp/Views/ConnectionSteps.swift
  - apps/apple/JournalApp/Views/MergeJournalsView.swift
  - apps/apple/JournalApp/Views/ScanCodeView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Pairing.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/PairingInvite.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Models.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - docs/design/connection-onboarding.md
  - docs/design/effortless-connection.md
  - docs/design/join-with-local-journals.md
  - docs/design/sync-health-and-recovery.md
  - docs/design/sync-security-2026-09-24.md
---

# Connect to a server

## Purpose

Every way a device starts syncing: setting up a new server, joining a server with a password, a recovery code or another device, with or without journals already on this device. Pages are described in `screens/connect-to-server`; the approving side is `flows/pair-device`.

## Words used here

- **This device has nothing written:** it has no library, or a library that isn't connected and holds no entries or templates that anyone wrote (only untouched starting content). Joining then replaces this device's library with the server's. Otherwise this device **has journals**, and joining merges them into the server's.
- **Credential:** what opens the server's journals: Master Password (current servers), Recovery Key (servers set up by early versions), Access Password (servers set up by early versions without encryption), or nothing (a server without encryption; devices join with another device or a one-time recovery code).
- **Installing:** making the server's journals this device's library, after access was granted.

## Overview

```
Choose a server ──► check it
   │ (scan a code) ───────────────────────────────────────────► [has journals?] ─ yes ─► Merge Journals ─► Finish on Your Other Device
   │                                                                     └ no ─────────────────────────► Finish on Your Other Device
   ├─ not set up ─► Set Up Server ─┬─ no library ─► Choose a Master Password ─► (set up) ─► Server Is Ready
   │                               ├─ library with password ─► Enter Master Password ─► (set up) ─► Server Is Ready
   │                               └─ library without password ─► (set up) ─► Server Is Ready
   └─ set up ─► [has journals?] ─ yes ─► Merge Journals ─┐
                                └ no ────────────────────┤
                                                         ├─ server has a credential ─► Enter {credential} ─► (sign in) ─► done
                                                         │                              └ Use a Connected Device Instead… ─► Add This Device ─► (Connect) ─► done
                                                         └─ server without encryption (only a device with an unencrypted library) ─► Add This Device ─► (Connect) ─► done
                                                                                          └ Use a Recovery Code Instead… ─► Use a Recovery Code ─► (Connect) ─► done
```

A device with an encrypted library, or with no library, is refused by a server without encryption before any other step (see Servers without encryption in Rules).

## Steps

### 1. Choose a server

1. The sheet opens on **Choose a server**. If this device already has a server address, the address field is prefilled with it.
2. If this device's current server needs it to set up again, connect again or sign in again (`flows/reconnect-to-server`), the server is checked at once.
3. Otherwise the person does one of:
   - **Scan Code** (phone/tablet with a camera): the scanner opens (`screens/scan-code`). A code that's read closes the scanner; go to step 2 (scanned code).
   - **Choose a server on this network:** its address is filled in and checked.
   - **Type an address** and choose Continue (or Return).

**Checking a typed or nearby server** (busy row `settings.connect.busy.checking`; the server's status request waits up to 20 seconds for the local network permission prompt and an unresponsive server):

| Outcome | Next |
| --- | --- |
| The server is below protocol revision 1 (see Rules, Old servers) | Error `messages.connection.serverNeedsUpdate` ("This server needs an update before this device can connect."). This is checked first: nothing else is asked of the server, and the address stays for correcting. |
| Server not set up | Set Up Server; focus on the setup code. |
| Set up, and this device has journals not yet agreed to merge with this server | Merge Journals. |
| Set up, without encryption, and this device's library is encrypted or this device has none | Error `messages.connection.encryptionOff` on page 1; nothing is sent. |
| Set up, without encryption, and this device's library is unencrypted (it chose Not Now) | Add This Device. |
| Set up, with a credential | Enter {credential} (sign in); focus on the field. |
| The server speaks a newer protocol (a newer wire major) | Error `messages.connection.updateApp` ("Update My Journal to connect to this server."), also checked before anything else is asked. |
| The address isn't a valid HTTPS address | Error `messages.error.invalidAddress`. |
| The address answers, but not as a My Journal server | Error `messages.connection.notJournalServer`. |
| No connection or server unreachable | Error `messages.connection.cannotConnectTailscale` for hosts ending in `.ts.net`, otherwise `messages.connection.cannotConnect`. |
| Server error (it's running, but can't answer now) | Error `messages.server.unavailable`. |
| Rate limited | Error `messages.server.rateLimited`. |
| Any other unexpected answer | Error `messages.server.unanswered`. |
| A response larger than allowed | Error `messages.server.responseTooLarge`. |

All errors appear on page 1, are announced, and leave the address for correcting.

### 2. Scanned code

The scanner reads only My Journal codes (`MYJOURNAL1.` followed by the encoded data); any other QR code is ignored and scanning continues. A code of a newer format shows `messages.pairing.inviteNewerVersion` under the camera view; a code whose server isn't HTTPS shows `messages.pairing.inviteUnreachable`; scanning continues in both cases.

After a code is read:
1. Page 1 shows the code's server host with `settings.connect.busy.checking`.
2. The server is checked: it must speak this protocol (`messages.connection.updateApp`) and be at protocol revision 1 or later (`messages.connection.serverNeedsUpdate`), be set up, and must not be a server without encryption for a device with an encrypted library or none (`messages.connection.encryptionOff`).
3. If this device has journals not yet agreed for this server: **Merge Journals** (no pairing request is sent before Merge).
4. Otherwise (or after Merge): **Finish on Your Other Device**. A pairing request naming the code is sent; this device waits for approval (`settings.connect.waitingForApproval`).
5. The connected device that showed the code approves (`flows/pair-device`). No check code is compared: the code named the connected device's key, and an approval from any other key is refused.
6. Installing (`common.connecting`): see step 9.

Errors on Finish or page 1 after a scanned code:

| Cause | Message | Primary button |
| --- | --- | --- |
| Connection failed (no network, unreachable) | `messages.connection.cannotConnectTailscale` / `messages.connection.cannotConnect` | Try Again (same code) |
| The connected device declined | `messages.connection.pairingDeclined` ("Your connected device didn’t add this one.") | Scan Again |
| The code expired | `messages.connection.pairingExpired` | Scan Again |
| The approval didn't come from the device that showed the code, or couldn't be opened | `messages.connection.pairingInsecure` | Scan Again |
| The code was already used | `messages.pairing.inviteUsed` ("This code was already used. Show a new code on your other device.") | Scan Again |
| Installing failed after approval | the installing messages in step 9 | Try Again (installs again) |
| Any other failure | its message (step 1's table) | Scan Again |

Scan Again forgets the code, returns to page 1 and opens the scanner again.

### 3. Set Up Server

Shown when the server isn't set up. The person types the setup code the server printed when it started.

Checking the code as typed (no request):
- not 6 characters (after removing spaces and dashes): field error `messages.connection.setupCodeLength` (an 8-character code from a server before 6-character codes is not accepted: such a server is below protocol revision 1);
- characters outside the setup code alphabet (letters and digits 2–9, without I or O; also 0 and 1): field error `messages.connection.setupCodeCharacters`.

Then, if another step follows (Choose a Master Password or Enter Master Password), the code is checked with the server first (`settings.connect.busy.checking`):
- wrong code: field error `messages.connection.setupCodeIncorrect`;
- too many wrong codes: field error `messages.connection.setupCodeRateLimited`;
- the server has no setup code (it was used or never made): error `messages.server.noSetupCode`;
- other failures: step 1's table.

Which step follows:
- this device has no library: **Choose a Master Password** (there is no Protect step and no choice of encryption: every new library is encrypted);
- this device's journals have a password (and aren't an early library waiting to confirm its recovery key): **Enter {credential}**, focus on the field;
- otherwise (journals without a password): Set Up runs directly from this step.

### 4. Choose a Master Password (device without journals)

1. Master Password and Verify, both new-password fields. If they differ: field error `messages.connection.passwordsDontMatch` on Verify. Any non-empty password is accepted (`spec/README.md`, Master passwords). Focus is on Master Password.
2. Set Up (busy `settings.connect.busy.settingUp`):
   1. An encrypted journal is created on this device first, with the password. If that fails: error `messages.connection.createFailed`, or the creation's own message (for example `messages.password.enterMaster`).
   2. From then on, the password can't change in this sheet; Back is no longer available on this step; the primary button becomes Try Again.
   3. The server is set up with the code (step 6).

### 5. Enter {credential} (device with journals that have a password)

The person types the password (or early recovery key) of the journals on this device. Set Up (step 6). A wrong password: field error `messages.connection.credentialIncorrect` with {credential} “password” (“That password isn’t correct.”) or “recovery key” (“That recovery key isn’t correct.”).

### 6. Setting up the server

Busy `settings.connect.busy.settingUp`. The device:
1. saves the open entry (if it can't: `messages.save.before.goBack`);
2. checks it isn't already connected to this server (`messages.connection.alreadyConnected`) or connected to another server (`messages.connection.reconnectSameServer`);
3. sends the setup code with this library's recovery information (derived from the password; the password itself is never sent) and its device name;
4. receives this device's access and saves the connection;
5. uploads this device's journals (they'll sync with the server).

Then **Server Is Ready**. Done closes the sheet.

Failures:
- wrong setup code: back to Set Up Server with field error `messages.connection.setupCodeIncorrect`;
- too many wrong codes: back to Set Up Server with `messages.connection.setupCodeRateLimited`;
- the server's encryption details changed since it was checked: back to page 1 with `messages.connection.serverChanged`;
- the server needs an update for this library's recovery format: `messages.server.updateForRecoveryFormat`;
- the server has no setup code: `messages.server.noSetupCode`;
- any other failure: its message (step 1's table); if a journal was created in this sheet, the message is prefixed with `messages.connection.setupFailedSaved` ("Your journal is saved on this device, but the server couldn’t be set up. ");
- after any failure the server is checked again; if someone else set it up meanwhile: back to page 1 with `messages.connection.setUpElsewhere` ("This server has just been set up. Choose it again to sign in.").

### 7. Merge Journals (device with journals)

Before anything is sent from a device that has journals, Merge Journals names the server and what will be merged. The person reads it and chooses Merge (Command-Return), Back, or Cancel.
- Merge records consent for this server for the rest of the sheet (a new code for the same server doesn't ask again), then continues with the step it interrupted: Finish (scanned code), Add This Device (server without encryption), or Enter {credential} (sign in).
- **Back, like Cancel, gives up the access the step obtained** (owner decision, 2026-10-06): a one-time recovery code's grant or a pairing grant is revoked, and the step Back lands on starts as a new visit:
  - Sign in: the password field is cleared and focused, with no error; Sign In asks the server again, and Merge Journals comes up again for the same agreement.
  - Recovery code: the field is cleared and focused, and `settings.connect.codeUsed` shows above it until the person types, announced when the step appears. A new one-time code is needed.
  - Add This Device: the old code belonged to a withdrawn request, so the screen shows `settings.connect.addThisDevice.gettingCode` and then a new code, and VoiceOver announces `settings.connect.announce.newCode`. The new request starts only after the old one was withdrawn.
- Consent is checked again just before installing: if the library gained writing since (for example in another window), Merge Journals is shown again and nothing is installed.

### 8. Sign in with the credential

Busy `settings.connect.busy.signingIn`, then the joining phases.
1. Saves the open entry (`messages.save.before.goBack`).
2. Checks the server's encryption details are those seen when it was chosen; otherwise back to page 1 with `messages.connection.serverChanged`.
3. Derives the recovery secret from the typed credential and asks the server for access.
4. Installs (step 9).

Errors:
- wrong credential: field error `messages.connection.credentialIncorrect`, with {credential} “password” for any kind of password or “recovery key”;
- too many attempts: field error `messages.connection.credentialRateLimited` (“Too many password attempts on this server. Try again in a few minutes, or use a connected device.”, or “recovery key attempts”);
- the server now holds another library and this device is still connected to the old one: Merge Journals is pushed (nothing sent yet); Merge continues the sign-in;
- merging stopped part way: `messages.connection.mergeFailed` or, when sending had started, `messages.connection.mergeFailedSent`; the primary button becomes Try Again, which finishes without duplicates;
- other: its message (step 1's table, step 9).

### 9. Add This Device with a typed code

Shown for a server without encryption, or after Use a Connected Device Instead….
1. The device asks the server for a pairing code (`settings.connect.addThisDevice.gettingCode`). A server below protocol revision 1: `messages.connection.serverNeedsUpdate` ("This server needs an update before this device can connect."), primary Get New Code.
2. The nine-digit code appears with Copy Code and the instruction; status `settings.connect.waitingForApproval`.
3. On the connected device the person types this code (`flows/pair-device`). When it's accepted there, both devices show the same six-digit **check code**. This device announces it.
4. The person compares the codes and chooses **Connect** (Command-Return). Nothing from the other device is used before this. If the codes don't match, the person chooses Cancel; the request is withdrawn and any access received is given up.
5. After Connect, if the other device hasn't approved yet: `settings.connect.checkCode.waiting`.
6. Once approved: install (busy `common.connecting`).

The device polls the server every second while waiting, slowing to at most every 16 seconds when the server asks it to.

Errors on Add This Device:

| Cause | Message | Primary |
| --- | --- | --- |
| The other device didn't approve | `messages.pairing.declined` | Get New Code |
| The code expired | `messages.pairing.expired` | Get New Code |
| The approval didn't match the check code, or couldn't be opened | `messages.pairing.insecureGrant` | Get New Code |
| Connection failed | `messages.connection.cannotConnect` / `…Tailscale` | Get New Code |
| Installing failed after approval | see below | Try Again |

Leaving Add This Device (Back, Use a Recovery Code Instead…, Cancel, closing) withdraws the pairing request and gives up access that was granted but not used.

### 10. Use a Recovery Code (server without encryption)

The server's administrator can make a one-time recovery code. The person types it; Connect.
- Anything that isn't a recovery code's form (64 hexadecimal digits) is refused without sending: field error `messages.connection.recoveryCodeIncorrect` ("That recovery code isn’t correct or has already been used.").
- The server refuses it: the same field error.
- Too many attempts: error `messages.server.rateLimited`.
- If installing fails after the code was accepted, the code is spent; Try Again continues with the access it gave, and that access is kept only until the sheet is left.

### 11. Installing (all ways of joining)

1. Saves the open entry (`messages.save.before.goBack`); refuses if another connection is being set up (`messages.connection.alreadyConnecting`).
2. A library with nothing written is replaced by the server's journals (they download). A library with journals:
   - if the server holds this same library (same encryption key, or the server already has this library's records): continues with it by identity;
   - otherwise: makes a new copy with everything the server has, merges this device's journals into it (same-name journals combine unless an agent reads the server's journal; then a number is added), and sends them. Phases: `settings.connect.busy.checking`, `settings.connect.busy.downloading`, `common.merging`.
   - A device without encryption joining an encrypted server encrypts its journals first; the busy row shows encryption progress.
3. Only when everything synced does the library switch; then the sheet closes. Writing is paused meanwhile (on the computer, the journal window explains it).

Install failures:
- the server changed since it was checked: back to page 1 (Continue checks again) with `messages.connection.serverChanged`;
- the server doesn't use encryption and this device's library is encrypted or this device has none: `messages.connection.encryptionOff`;
- merging stopped part way: `messages.connection.mergeFailed` / `messages.connection.mergeFailedSent`;
- no library: `messages.connection.finishFailed`;
- a copy waits for Try Again (writing stays paused until it's used or the sheet is left): `messages.connection.finishFailedRetry`;
- otherwise: `messages.connection.finishFailedLocal`;
- after the switch, if the journals can't be shown: the app's error alert shows `messages.connection.connectedNotDisplayed`.

### 12. Safeguards that shouldn't normally be seen

These messages exist for states the flow is designed to prevent; a client must still show them if they occur:
- `messages.connection.chooseUpload` ("Choose whether to upload your local journals before connecting.");
- `messages.connection.createJournalFirst` ("Create a journal before setting up your server.");
- `messages.connection.alreadyHasJournals` ("This device already has journals.");
- `messages.error.locked` ("Unlock My Journal to continue."), when the app locked during the work (the sheet normally closes first);
- `messages.error.invalidData` ("This data couldn’t be read."), for an answer that can't be read;
- `messages.error.unauthorized` ("This device no longer has access."), when the server refuses this device's credential during a step;
- `messages.error.invalidSetupCode` ("That setup code isn’t valid. Check it and try again."), a fallback for a refused setup code outside Set Up Server.

## Servers without encryption

Version 1.1 never creates a library without encryption, so a server whose recovery format is 3 or 4 (set up without encryption by an earlier version) can no longer be used to start a new device:

- **Refused:** by a device with an encrypted library, and by a device with no library (a device being set up from the first-launch screen). One text: `messages.connection.encryptionOff`.
- **Kept as it was:** by a device whose library is unencrypted. Nothing about joining changes for it.
- **The route for people with only a server without encryption:** (1) any device that still has the journals, on the earlier version or this one: Turn On Encryption (earlier version) or Encrypt (this version) there, which encrypts the server and revokes the others; then new devices join normally. (2) No device left, but an archive from an earlier version: restore it on the new device (Encrypt Your Journals then encrypts it) and set up a new server; the old server is abandoned. (3) A server without encryption and nothing else: not supported in this version ([open-questions.md](../open-questions.md), D62).
- Windows and Android refuse such servers the same way; they have no way to join one.

## Rules

- **Nothing is sent before consent.** A device with journals sends no sign-in, pairing request or scanned-code request to a server before Merge on Merge Journals for that server. A device with an encrypted library, or with none, is refused by a server without encryption before any request, with the one text `messages.connection.encryptionOff` ("{host} doesn’t use encryption. On a device that has your journals, turn on encryption in Settings, or connect to a server that uses encryption.") on page 1, for a typed or nearby address, for a scanned code and when finishing a pairing. A device whose library is unencrypted (Not Now) keeps the earlier behaviour toward its own unencrypted server; its Encrypt Your Journals form encrypts the server ([flows/encrypt-journals](encrypt-journals.md)).
- **Old servers (protocol revision, [protocol/README.md](../../protocol/README.md#protocol-revision)):** the server's status is read first and is the only request made to a server below protocol revision 1 (one from before the first 1.0 releases) or one that speaks a newer wire major. The same refusal, `messages.connection.serverNeedsUpdate` (or `messages.connection.updateApp`), comes from every place that needs the server: this sheet, the sync state (`messages.sync.serverUpdateNeeded`, in its own words), Add Device, Change Password, Encrypt Your Journals and Agent Access. It is a gate and nothing else: queued changes, pending images, the sync position, the device's access, agents and the Devices list are not changed, and syncing resumes by itself when a later status read shows revision 1 or more. The revision is read again on every status read and never kept.
- **Never lost:** a failed join leaves this device's library exactly as it was; a staged copy is discarded when the sheet is left, and writing continues.
- **Retries never duplicate:** merging again derives the same identities.
- **Unused access is given up:** access granted by a pairing or recovery code but never used is revoked when the sheet is left (best effort; otherwise the device appears in Devices, where it can be revoked).
- **Passwords never leave the device;** only derived secrets do.
- The device name sent is this device's name as the system reports it.
- Locking closes the sheet and cancels as Cancel does.
- On the computer, the app doesn't lock for inactivity while the sheet is waiting on the server or another device.

## Accessibility

- Every error is announced when it appears; field errors after focus moves to the field.
- The check code is announced when it appears (typed-code pairing only).
- Merge and Connect need Command-Return, never Return.

## Platform notes (Apple)

- Only iPhone and iPad can scan. The Mac shows its own QR code only as the connected device (`screens/add-device`).
- Local network permission: on iOS the system asks the first time nearby servers are looked for; on the Mac the message names System Settings ▸ Privacy & Security ▸ Local Network.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
