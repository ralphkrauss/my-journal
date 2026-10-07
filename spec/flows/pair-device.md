---
id: pair-device
title: Pair a new device (approving side, and both sides together)
features: [add-device, pair-device-scan, pair-device-code]
sources:
  - apps/apple/JournalApp/Views/AddDeviceView.swift
  - apps/apple/JournalApp/Model/ConnectionFlow.swift
  - apps/apple/JournalApp/Model/DeviceOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Pairing.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/PairingInvite.swift
  - docs/design/effortless-connection.md
  - docs/design/sync-security-2026-09-24.md
  - docs/design/pre-release-ui-2026-09-27.md
  - protocol/README.md
---

# Pair a new device

## Purpose

A connected device gives a new device access to the server and the journals' key, without the new device typing a password. Two ways: the new device **scans** a QR code the connected device shows, or the connected device **types** the nine-digit code the new device shows and both compare a six-digit **check code**. The new device's side is in `flows/connect-to-server` (steps 2 and 9); this flow is the connected device's side, with the two sides lined up.

## Scanned code

| Connected device (`screens/add-device`) | New device (`screens/connect-to-server`) |
| --- | --- |
| 1. Add Device… → the server is asked whether it takes scanned codes; if so, a QR code appears with `settings.addDevice.scanInstructions` and `settings.addDevice.waiting`. | |
| | 2. Connect to a Server ▸ Scan Code reads the code; the server is checked; Merge Journals if the new device has journals. |
| | 3. Sends a pairing request naming the code (`settings.connect.waitingForApproval` on Finish on Your Other Device). |
| 4. Every four seconds the connected device asks whether a device answered its current code (and the code it replaced in the last 30 seconds). When one did, it verifies the request proves the device read this code; if not, the request is declined and the session ends with `settings.addDevice.error.unverified`. | |
| 5. Contributes a one-time key and waits for the new device to reveal its key (`settings.addDevice.waitingFor`), checking it against the key the new device committed to. | 6. Reveals its key. |
| 7. Shows `settings.addDevice.addQuestion` / `settings.addDevice.addDetail`. If authenticating is itself deliberate (Touch ID, passcode, password, watch) and VoiceOver is off, authentication starts at once; otherwise the person chooses Add Device. | |
| 8. Authenticates the device owner (`settings.addDevice.authReason`), then sends the journals' key, wrapped for the new device, and closes. | 9. Receives the key; the approval must come from the key the code named. Installs and closes. |

## Typed code

| Connected device | New device |
| --- | --- |
| | 1. Add This Device: gets a nine-digit code and shows it. |
| 2. Add Device… → Enter Code Instead… (or directly, when the server doesn't take scanned codes) → types the code → Continue. | |
| 3. The code is looked up; the connected device contributes a one-time key and waits (`settings.addDevice.waitingFor`). | 4. Reveals its key; shows the check code and announces it. |
| 5. Shows `settings.addDevice.checkQuestion`, the same six-digit check code and `settings.addDevice.checkDetail`. | |
| 6. If the codes match: Approve (Command-Return) → authenticate → sends the key. If not: Cancel declines. | 7. If the codes match: Connect (Command-Return). Nothing is installed before Connect, whichever happens first. |
| 8. Closes. | 9. Installs and closes. |

The check code is derived from the request's identifier and both devices' one-time keys (protocol/README.md), so a server can't choose keys that produce a matching code.

## Errors on the connected device

| When | Message | What happens |
| --- | --- | --- |
| The typed code is incomplete (fewer than nine digits) | `settings.addDevice.error.incomplete` ("Enter the 9-digit code from your new device.") | Announced; stays on the field. |
| The code isn't known to the server | `messages.pairing.codeNotFound` | Stays; the code can be corrected. |
| The code expired | `messages.pairing.expired` | Back to the field, cleared. |
| The new device runs an older version | `messages.pairing.deviceOutdated` ("Update My Journal on the new device, then try again.") | Only Done remains. |
| The new device's key didn't match its commitment | `messages.pairing.insecureCandidate` | Back to the field, cleared. |
| The new device didn't reveal its key before its request expired | `messages.pairing.noResponse` ("{device} didn’t respond. Get a new code on the new device and try again.") | Back to the field, cleared. |
| Too many attempts | `messages.server.rateLimited` | Stays. |
| Server error | `messages.server.unavailable` | Stays; Try Again. |
| Other unexpected answer | `messages.server.unanswered` | Stays. |
| A scanned request couldn't be verified | `settings.addDevice.error.unverified` ("Couldn’t verify the new device. Show a new code and try again.") | Session ends; Show New Code. |
| A scanned device stopped while its request was open | notice `settings.addDevice.stoppedConnecting`; plus `settings.addDevice.unreachable` if the server couldn't be reached | A new code is shown. |
| Approving: the connection failed after sending | `settings.addDevice.error.unconfirmed` ("Couldn’t confirm that {device} was added. Check the device list.") | Only Done; never suggests approving again. |
| Approving: authentication cancelled or failed | none | Stays on the confirmation. |
| While showing codes: three failed checks in a row | status `settings.addDevice.unreachable` | Keeps checking. |
| Ten minutes passed | `settings.addDevice.expired` | Show New Code. |

A network failure while looking up or waiting shows the platform's own connection error text (see [open-questions.md](../open-questions.md), A9).

## Rules

- Only a device that's connected and unlocked can approve. Approving sends the journals' key; the new device can then read and sync every journal.
- The device owner authenticates before every approval; a device without a passcode continues without it.
- Approve and Add Device never respond to Return alone.
- Scanned codes need a server that supports them (`pairing-invite`) and has an HTTPS address; typed codes need check-code support (`pairing-check-code`).
- Codes: the QR code changes every two minutes, the previous one is watched 30 seconds more, the whole session lasts ten minutes. The nine-digit pairing code is the server's; it expires when the server says.
- Leaving or locking declines a waiting request (best effort).
- A code is never left on screen in the background or in screen recordings (computer).
- A request from a device that didn't read this code is never shown with a name.

## Accessibility

- The check code is read digit by digit on both devices; the new device announces it when it appears.
- Every error is shown in the sheet; the incomplete-code error is also announced.

## Platform notes (Apple)

- The Mac shows the QR code (for a phone or tablet to scan) but can't scan one itself.
- iPhone and iPad keep the screen awake while showing a code.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
