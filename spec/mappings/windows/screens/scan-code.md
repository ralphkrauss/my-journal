---
id: scan-code
title: Scan code (Windows)
spec: screens/scan-code.md
features: [pair-device-scan]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings
---

# Scan code (Windows)

Not offered in version 1. This file records the decision and what a later version would build, so the screen is not mapped again from nothing. The spec's [Scan Code](../../../screens/scan-code.md) is the behaviour a later version must keep.

## Controls

Not applicable in version 1: [platform.md, 29](../platform.md#29-qr-codes-and-add-device) and open-questions D24 leave Scan Code out. Connect to a server shows no Scan code row ([connect-to-server](connect-to-server.md)), and the commands `connect-scan-code`, `scan-cancel` and `scan-open-settings` are "Not offered" in [commands.md](../commands.md). Why:

- Windows has no built-in camera barcode scanner for desktop apps. Scanning needs a camera preview (`MediaCapture`, the Webcam capability in the package manifest) and a QR decoder library, which is a new dependency with its own review.
- Many PCs have no usable camera, and a PC that has one points it at its user, not at a phone screen.
- A PC does not need it: it joins with the typed nine-digit code (Add this device) and compare-the-check-code, or with the password, and the approving side can type the code or, on a phone, scan a QR code the PC shows ([add-device](add-device.md)). No capability is lost.

### What a later version would do

If D24 is reopened, the design is a step of the Connect task page, offered only when a camera is present (`DeviceInformation.FindAllAsync` for video capture devices) and shown as a row `settings.connect.scanCode` with a QRCode (ED14) icon and the footer `settings.connect.scanCode.footer`:

- A step in the task page's `Frame` (not a dialog) with a `CaptureElement` or `MediaPlayerElement` preview named `settings.scan.cameraLabel`, the instruction `settings.scan.instructions` below it (replaced by `messages.pairing.inviteNewerVersion` or `messages.pairing.inviteUnreachable` when a code cannot be used), and Cancel (`common.cancel`).
- Camera access denied: `settings.scan.cameraDenied` in the Windows form ("Allow camera access in Settings > Privacy & security > Camera") and a `Button` `common.openSettings` that launches `ms-settings:privacy-webcam`.
- A found code: Narrator hears `settings.scan.found`, the step closes and the page checks the server. Only one code is used per opening; only `MYJOURNAL1.` codes with an HTTPS address in release builds.
- The decoder runs on frames in memory only: nothing is stored or logged, and the camera is released when the step closes.

## Layout at each window width

Not applicable: the screen is not offered.

## Commands and shortcuts

Not applicable: the screen is not offered. The commands `connect-scan-code`, `scan-cancel` and `scan-open-settings` have no Windows placement.

## Copy differences

Not applicable while the screen is not offered. The keys `settings.scan.*`, `settings.connect.scanCode`, `settings.connect.scanCode.footer` and `settings.connect.scanAgain` are not shown on Windows. If a scanner is added, `settings.scan.cameraDenied` needs a Windows variant that names Settings > Privacy & security > Camera instead of "Settings" (a vocabulary change, proposed then).

## Accessibility

Not applicable now. A later scanner must announce `settings.scan.found` (a notification event) because the change happens without a click, and must offer the typed-code route on the same page.

## Different by design

- **The whole screen is absent** on Windows in version 1 (D24), with the reasons above. `parity.yaml` marks `pair-device-scan` for the owner to decide ("different-by-design" for Windows, with the typed-code route as the replacement); this file does not edit it.
- Apple offers the scanner on iPhone and iPad only, not on the Mac, so a computer without it is not a new situation.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D24 (camera and scanning).
