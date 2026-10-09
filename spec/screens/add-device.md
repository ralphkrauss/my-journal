---
id: add-device
title: Add Device
features: [add-device, pair-device-scan, pair-device-code]
sources:
  - apps/apple/JournalApp/Views/AddDeviceView.swift
  - apps/apple/JournalApp/Views/PairingCodeImage.swift
  - apps/apple/JournalApp/Model/DeviceOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Pairing.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/PairingInvite.swift
  - docs/design/effortless-connection.md
  - docs/design/sync-security-2026-09-24.md
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/join-with-local-journals.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---

# Add Device

## Purpose

On a device that's already connected, lets a new device join: by showing a code the new device scans, or by taking the nine-digit code a new device shows and comparing check codes. Approving gives the new device the journals' key, so it can read and sync all journals. The full flow is `flows/pair-device`.

## Entry points

- Settings ▸ Sync ▸ Devices ▸ Add Device… (`screens/settings-devices`).
- Connect to a Server ▸ Server Is Ready ▸ Add Another Device….
- Encrypt Your Journals ▸ the Done sheet ▸ Add Another Device… (synced libraries, `screens/encrypt-journals`).

## Content

A sheet titled `settings.addDevice.title` ("Add Device").

- **Locked:** only `settings.addDevice.locked`.

### Preparing
An activity indicator while the server's status is read. A server below protocol revision 1 ends here: the error row shows `messages.connection.serverNeedsUpdate` and only `common.done` remains (Finished); if the status can't be read at all, the typed-code step is shown instead.

### Showing a code (the server has an HTTPS address)
1. A section, centred:
   - a notice when one applies, in smaller text (for example `settings.addDevice.stoppedConnecting`);
   - the QR code, black on white with a quiet margin and rounded corners, 220 points plus margin, not scaling with text size (accessibility label `settings.addDevice.qrLabel`). On the phone and tablet, while the app isn't active (app switcher) a plain placeholder of the same size replaces it; on the computer the placeholder shows only when the app goes to the background, so another window in front doesn't hide the code from a phone held up to the screen (owner decision, 2026-10-06). When the session ended: `settings.addDevice.expired` ("This code has expired.") in its place;
   - the instruction `settings.addDevice.scanInstructions`;
   - a status line: `settings.addDevice.waiting` ("Waiting for your new device…") with an indicator, or, after three failed checks in a row, `settings.addDevice.unreachable` ("Couldn’t reach the server. Check your connection."). No status once expired.
2. A row: `settings.connect.server` → the server's host (selectable), so the person can tell the new device's Merge Journals names the same server.
3. A section with the button `settings.addDevice.enterCodeInstead` ("Enter Code Instead…") and footer `settings.addDevice.enterCodeInstead.footer` ("For a Mac or a device that can’t scan the code.").
- Primary: `settings.addDevice.showNewCode` ("Show New Code") only once expired.

### Entering a code (typed-code pairing; also when the status can't be read)
1. A monospaced field (label `settings.addDevice.codeField` "Pairing Code", placeholder `settings.addDevice.codePlaceholder` "123 456 789"), number pad; it groups digits in threes as typed. Footer `settings.addDevice.codeFooter` ("On the new device, choose Connect to a Server, then Add This Device.").
2. When connected through HTTPS: rows `common.serverAddress` ("Server Address") → the full address (selectable), and a button `settings.addDevice.copyAddress` ("Copy Address").
   When connected through a plain HTTP address (only possible for a server on this computer): `settings.addDevice.httpOnly` ("Other devices can’t connect to {host}. To add devices, connect this device to the server’s HTTPS address.") in secondary text.
- Primary: `common.continue` (disabled when empty or busy); while looking the code up, an activity indicator in its place.

### Waiting for the new device
An indicator and `settings.addDevice.waitingFor` ("Waiting for {device}…"), while the new device reveals its key. Hidden after an error.
- Primary: after an error with a typed code, `common.tryAgain`.

### Confirming
- **Scanned code:** heading `settings.addDevice.addQuestion` ("Add “{device}”?") and `settings.addDevice.addDetail` ("It will be able to read and sync all your journals."). Primary `settings.addDevice.add` ("Add Device"); cancel button `settings.addDevice.dontAdd` ("Don’t Add").
- **Typed code:** heading `settings.addDevice.checkQuestion` ("Does {device} show this code?"), the six-digit check code in large monospaced type grouped “123 456” (accessibility label `settings.connect.checkCode.label`, read digit by digit), and `settings.addDevice.checkDetail` ("Approve only if the codes match. {device} will be able to read and sync all your journals."). Primary `settings.addDevice.approve` ("Approve"); cancel button `common.cancel`.
- Both primaries use Command-Return, never Return. While approving, an activity indicator replaces the primary and the cancel button is disabled.

### Finished
Nothing more can be done here (for example the new device must be updated, or it's unknown whether approval reached the server): the error row, and only `common.done`.

### Error row
Any error appears in red at the end of the form.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Enter Code Instead… | `add-device-enter-code` | Stops showing codes; shows the code field. |
| Continue | `add-device-look-up` | Looks up the typed code. |
| Show New Code | `add-device-new-code` | Starts a new ten-minute session of codes. |
| Copy Address | `add-device-copy-address` | Copies the server address. |
| Add Device / Approve | `add-device-approve` | Asks for the device owner's authentication (Face ID, Touch ID or the device passcode or login password), then approves. |
| Don’t Add / Cancel | `add-device-cancel` | Declines a request that's waiting (best effort) and closes. |
| Try Again | `add-device-try-again` | Waits for the new device again. |
| Done | `add-device-done` | Closes. |

## States

See `flows/pair-device` for every error. In brief:
- **Expired session:** `settings.addDevice.expired`; Show New Code.
- **Unreachable while showing:** status line `settings.addDevice.unreachable`; checking continues.
- **The new device went away while its request was open (scanned):** a new code appears with the notice `settings.addDevice.stoppedConnecting` ("“{device}” stopped connecting."), plus the error `settings.addDevice.unreachable` if the server couldn't be reached.
- **Locked:** locking cancels (declines what's waiting) and closes.

## Rules

- A shown code changes every two minutes; the code it replaced is still watched for 30 seconds more, in case a device scanned it just before. The sheet shows codes for at most ten minutes, then expires.
- The server is asked whether a device answered a shown code every four seconds; three failures in a row show the unreachable status.
- When the app goes to the background the code is dropped (none is left behind); a new one appears when it returns. Only entering the background counts, not brief inactivity (Face ID, Control Center).
- The screen stays awake while a code is shown (phone/tablet).
- The sheet's window is excluded from screen sharing and recordings (computer), because its code lets a device join.
- A scanned request is shown only if it proves the device read this code; otherwise it's declined and the session ends with `settings.addDevice.error.unverified`.
- Device names are shown cleaned: control and direction-changing characters removed, trimmed, `settings.addDevice.newDevice` ("New Device") when empty, at most 60 characters (59 plus “…”).
- **Authentication before approving:** the device owner must authenticate (`settings.addDevice.authReason` "Add “{device}” to your journals"). A device without a passcode continues without it.
- **Scanned approval without a tap:** when authentication is itself a deliberate act (Touch ID, a passcode or password, a watch), a verified scanned request goes straight to authentication. With Face ID, with VoiceOver running, or without a passcode, the person chooses Add Device first.
- Cancel and closing decline a waiting request (best effort); otherwise it simply expires.
- The computer doesn't lock for inactivity while a code is shown or a device is answering.

## Accessibility

- The QR code is one image element labelled `settings.addDevice.qrLabel`.
- The check code is read digit by digit.
- Approve and Add Device use Command-Return so they can't be triggered before reading.

## Platform notes (Apple)

- Mac: a sheet of about 460 × 540 points, excluded from screen capture. The Mac shows QR codes too, for a phone or tablet to scan.
- iPhone and iPad: the idle timer is off while a code is shown.
- Authentication reason on the Mac completes “My Journal is trying to …”, so it starts in lower case: `settings.addDevice.authReason` has a `mac` variant.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
