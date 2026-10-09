---
id: scan-code
title: Scan Code
features: [pair-device-scan]
sources:
  - apps/apple/JournalApp/Views/ScanCodeView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/PairingInvite.swift
  - docs/design/effortless-connection.md
---

# Scan Code

## Purpose

Reads the code a connected device shows under Settings ▸ Sync ▸ Devices ▸ Add Device, so a new phone or tablet can join without typing anything.

## Entry points

- Connect to a Server ▸ Scan Code (`screens/connect-to-server`).
- Scan Again after a scanned code failed.

## Content

A full-screen camera view on black:
1. The live camera preview (accessibility label `settings.scan.cameraLabel` "Camera preview"), highlighting QR codes it recognises.
2. At the top left, a bordered button `common.cancel`.
3. At the bottom, on a translucent bar, centred text: `settings.scan.instructions` ("Point your camera at the code on your connected device."), replaced by an error message when a code can't be used.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Cancel | `scan-cancel` | Closes the scanner; Connect to a Server stays on page 1. |
| Open Settings | `scan-open-settings` | Opens the system's settings for My Journal (camera denied). |

## States

- **Asking for camera access:** on first use, the system asks; nothing else shows until it's answered.
- **Camera denied or restricted:** instead of the preview, centred white text `settings.scan.cameraDenied` ("Allow camera access in Settings to scan the code.") and a prominent button `common.openSettings` ("Open Settings").
- **Code found:** a success haptic, VoiceOver announces `settings.scan.found` ("Code found"), the scanner closes and Connect to a Server checks the server.
- **Not a My Journal code:** ignored; scanning continues.
- **A newer code format:** bottom text `messages.pairing.inviteNewerVersion` ("Update My Journal to use this code."); scanning continues.
- **A code for a server other devices can't reach (not HTTPS):** bottom text `messages.pairing.inviteUnreachable`; scanning continues.

## Rules

- Only one code is used per opening; later reads are ignored.
- A code is `MYJOURNAL1.` followed by base64url data; any `MYJOURNAL<digit>` prefix other than 1 means a newer format.
- Release builds accept only HTTPS server addresses in a code.

## Accessibility

- The preview has a label; the instruction text is read as the screen's text.
- “Code found” is announced because the change happens without a tap.

## Platform notes (Apple)

- iPhone and iPad only, and only where the system's live scanner is supported; otherwise Scan Code isn't offered. The Mac never scans.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
