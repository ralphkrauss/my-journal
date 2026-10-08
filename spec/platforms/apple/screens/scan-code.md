---
id: scan-code
title: Scan Code (Apple)
spec: screens/scan-code.md
features: [pair-device-scan]
devices: [iphone, ipad]
status: draft
sources:
  - apps/apple/JournalApp/Views/ScanCodeView.swift
  - apps/apple/JournalApp/Views/ConnectionView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/PairingInvite.swift
  - docs/design/effortless-connection.md
---

# Scan Code (Apple)

`ScanCodeView` in `Views/ScanCodeView.swift`, compiled only for iOS (`#if os(iOS)`). It reads the QR code that [add-device](add-device.md) shows on a connected device. It is opened from page 1 of [connect-to-server](connect-to-server.md) and from Scan Again. Spec: [scan-code](../../../screens/scan-code.md). Camera, photos and QR conventions: [platform.md](../platform.md#26-camera-photos-and-images) and [platform.md](../platform.md#29-qr-codes-and-add-device).

## Controls

Presented by `ConnectionSheet` with `.fullScreenCover(isPresented: $scanning)`; it covers the Connect to a Server sheet completely, so there is no sheet chrome. `scanning` is set by the Scan Code button (`flow.error = nil` first) and by `flow.scanRequested` (Scan Again). The view is a `ZStack` on `Color.black.ignoresSafeArea()`:

1. **Camera preview.** `CameraCodeReader`, a `UIViewControllerRepresentable` around VisionKit's `DataScannerViewController` (recognised data `.barcode(symbologies: [.qr])`, `qualityLevel: .balanced`, `recognizesMultipleItems: false`, `isGuidanceEnabled: true`, `isHighlightingEnabled: true`, `isHighFrameRateTrackingEnabled: false`), `.ignoresSafeArea()`, accessibility label `settings.scan.cameraLabel`. It starts scanning when created and stops in `dismantleUIViewController`. Shown when `AVCaptureDevice.authorizationStatus(for: .video) == .authorized`. The delegate passes each added barcode's `payloadStringValue` to `read(_:)`.
2. **Cancel.** Top leading, `Button` `common.cancel` with `.buttonStyle(.bordered).tint(.white)`; calls `dismiss()`. Connect to a Server stays on page 1.
3. **Bottom bar.** `Text(message ?? "Point your camera at the code on your connected device.")` (`settings.scan.instructions`), centred, `.padding(20)`, full width, `.background(.regularMaterial)`, `fixedSize(horizontal: false, vertical: true)`. `message` is set only by a code this app cannot use: `messages.pairing.inviteNewerVersion` (a newer format, `PairingInvite.ReadError.newerVersion`) or `messages.pairing.inviteUnreachable` (a server that is not HTTPS, `.unreachableServer`). It stays until the scanner is closed.
4. **Camera access.**
   - `.notDetermined`: the view's `.task` calls `AVCaptureDevice.requestAccess(for: .video)`; until it is answered nothing but the black screen, Cancel and the instruction text show. The usage text is `NSCameraUsageDescription` in `apps/apple/project.yml` ("Take photos for your entries and scan codes to connect your devices.").
   - `.denied` or `.restricted`: instead of the preview, white centred text `settings.scan.cameraDenied` and a `.borderedProminent` `Button` `common.openSettings`, which opens `UIApplication.openSettingsURLString`.
5. **A code is read** (`read(_:)`): ignored when `found` is already true. `PairingInvite(text:)` parses it. A My Journal code: `found = true`, `UINotificationFeedbackGenerator().notificationOccurred(.success)`, `announceForAccessibility("Code found")` (`settings.scan.found`), `onScan(invite)` (which is `flow.join(_:)`), then `dismiss()`. `ReadError.notInvite` (any other QR code, or text that does not decode): ignored silently, scanning continues. Other errors set `message` as above.

**Availability.** `ScanCodeView.available` is `DataScannerViewController.isSupported` (a debug build also accepts the environment variable `JOURNAL_TEST_SCANNED_CODE`, which makes the view call `read` with that text at once and skip the camera, so simulators can exercise the flow). `ConnectionSheet.canScan` reads it; where it is false the Scan Code row is not shown at all.

**Model type:** none of its own; the result goes to `ConnectionFlow` ([connect-to-server](../flows/connect-to-server.md)). The code text format is `MYJOURNAL1.` plus base64url data; a prefix `MYJOURNAL` followed by another digit means a newer format. Release builds accept only HTTPS server addresses; debug builds also accept `http://localhost` and `http://127.0.0.1` (`PairingInvite.origin(of:)`).

## Layout

- **iPhone and iPad:** full-screen cover on every size and orientation. The preview fills the screen; Cancel and the bottom bar overlay it, the bar reaching the screen's bottom edge. Nothing branches on the size class or device idiom.
- **Mac:** not applicable. The file is `#if os(iOS)`, and a Mac has no Scan Code row.
- Dynamic Type: the bottom text and the denied text wrap; nothing scrolls, so at accessibility sizes the bar grows upward over the preview.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `scan-cancel` | Top-leading bordered button | none | always |
| `scan-open-settings` | Prominent button under the denied text | none | camera access denied or restricted |

No keyboard handling in the view; a hardware keyboard on iPad has no shortcut here.

## Copy differences

None. Same strings on iPhone and iPad; the Mac does not show the screen.

## Accessibility

- The preview has the label `settings.scan.cameraLabel`; the instruction or error text is an ordinary `Text`, read as the screen's text. `isGuidanceEnabled: true` lets the system scanner show its own guidance.
- "Code found" is announced because the screen closes without a tap, and the success haptic confirms it for people who feel but do not see.
- Cancel is a standard button, so Voice Control and Full Keyboard Access reach it.
- Scanning needs a camera aimed at a screen; a person who cannot do that uses Add This Device with the typed nine-digit code instead ([connect-to-server](connect-to-server.md), [add-device](add-device.md)).

## Differences between iPhone, iPad and Mac

- iPhone and iPad are identical in this view.
- Mac: no scanner (`canScan` is false off iOS; the spec states the Mac never scans). A Mac shows a code as the approving device ([add-device](add-device.md)), and a Mac joining a server uses a typed code ([connect-to-server](connect-to-server.md)). The source records no further reason.

## Screenshots

None. The screen cannot be captured on a simulator: it has no camera, so `DataScannerViewController.isSupported` is false and Scan Code is not offered, and a real camera preview on the device cannot be scripted. What the source shows: a black full-screen view with the live preview and VisionKit's highlight around a recognised QR code; a bordered white Cancel button at the top left; at the bottom a translucent material bar with the one-line instruction (or the newer-version or unreachable-server message); and, with camera access denied, white centred text with a prominent Open Settings button in place of the preview. A debug build with `JOURNAL_TEST_SCANNED_CODE` skips the camera but still shows this chrome.

## Source files

View:
- `apps/apple/JournalApp/Views/ScanCodeView.swift`: the screen, camera permission states, the scanner wrapper, the result handling.
- `apps/apple/JournalApp/Views/ConnectionView.swift`: `canScan`, the Scan Code row, the full-screen cover and `scanRequested`.

Model:
- `apps/apple/JournalApp/Model/ConnectionFlow.swift`: `join(_:)` receives the code; `scanAgain()` and `retryScannedCode()` return here.

Core:
- `apps/apple/Packages/JournalCore/Sources/JournalCore/PairingInvite.swift`: parsing the code text and its errors.

Design record: [effortless-connection.md](../../../../docs/design/effortless-connection.md).

## Open questions

See [open-questions.md](../../../open-questions.md). Not verified: how the system scanner announces recognised codes to VoiceOver beyond `isGuidanceEnabled`; the screen itself was never captured.
