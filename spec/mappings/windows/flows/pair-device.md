---
id: pair-device
title: Pair a new device (Windows)
spec: flows/pair-device.md
features: [add-device, pair-device-scan, pair-device-code]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Pair a new device (Windows)

A connected device gives a new device access to the server and the journals' key without the new device typing a password: the new device scans a QR code or the connected device types the nine-digit code and both compare a check code. Behaviour, every error and the two sides lined up are the spec's [flow](../../../flows/pair-device.md); the approving side's dialog is [add-device](../screens/add-device.md) and the new device's steps are in [connect-to-server](connect-to-server.md). **Pairing never needs a camera on a Windows PC.**

## Controls

### A Windows PC in each role

| Role | What the PC does | Where |
| --- | --- | --- |
| Approving device, scanned code | Shows the QR code; a phone or tablet scans it. This is the usual way for a Windows PC to add a phone | [add-device](../screens/add-device.md) |
| Approving device, typed code | The person types the nine-digit code the new device shows, then compares the check code and approves | [add-device](../screens/add-device.md), Entering a code |
| New device, typed code | The PC shows the nine-digit code (Add this device); the other device approves; the PC shows the check code and the person chooses Connect | [connect-to-server](../screens/connect-to-server.md) |
| New device, scanned code | Not offered: the PC has no scanner in version 1 ([scan-code](../screens/scan-code.md)) | |

So a Windows PC joining from an iPhone or iPad uses typed codes, with the phone as the approving device typing the PC's nine-digit code. A Windows PC joining another Windows PC uses typed codes on both sides. Only a phone or tablet joining a Windows PC uses the scan.

### The Windows-specific steps

- **Authentication before approving** is Windows Hello through [the gate](../screens/settings.md), always, whether or not App Lock is on, with `settings.addDevice.authReason`. A PC without Hello continues without it. The Windows prompt appears over the dialog, and the library window is deactivated meanwhile (the inactivity timer is held; nothing else reacts, because there is no cover).
- **Approve and Add device never respond to Enter alone.** The buttons have no default and take Ctrl+Enter, on both sides (Connect and Approve). A verified scanned request always waits for Add device, because a PC cannot know whether Hello will be a deliberate act ([add-device](../screens/add-device.md)).
- **Secrets on screen and on the clipboard.** The QR code, and the check code while it is shown, are in a window excluded from capture (`SetWindowDisplayAffinity` with the constant chosen in [platform.md, 20](../platform.md#20-screen-capture-and-window-privacy), whatever the Privacy setting says) for as long as they are visible, and the previous state is restored when the dialog closes. Excluding the whole window while a code shows is unconditional and is correct even if the accessibility spike changes the default of the setting. The nine-digit code's Copy button uses the clipboard options of [platform.md, 15](../platform.md#15-clipboard): not in history, not roamed, cleared after two minutes if still unchanged. Nothing is logged: no code, key, name of a pending device or server answer is written to a log or crash report.
- **The QR code** is dark on a white tile with its margin in every theme, and a placeholder replaces it while the window is inactive.
- **Timers.** The QR code changes every two minutes (the old one is watched 30 seconds more), the session lasts ten minutes, the server is asked every four seconds and three failures in a row show the unreachable status; the new device polls every second, up to every 16 seconds when the server asks. On Windows these are `DispatcherTimer`s tied to the dialog, stopped when it closes. The PC's display is kept on while a code is shown ([add-device](../screens/add-device.md)).
- **Leaving or locking declines a waiting request** (best effort): the dialog's Close button, Esc, Alt+F4 (the window's close ends the app, so the request is declined first) and a lock do the same. If the app is closed without a chance to decline, the request expires.
- **A name** shown for a pending device is cleaned as the spec says and shown as plain text.
- **Network changes.** A lost connection while looking up or waiting shows the spec's messages (`messages.server.unavailable`, `messages.server.unanswered`) and, for failed approval, `settings.addDevice.error.unconfirmed` with only Done. Windows adds one trigger: `NetworkStatusChanged` ends a wait that is already failing sooner than the next poll ([platform.md, 30](../platform.md#30-sync-lifecycle-and-power)). The platform's own error text for a network failure is not shown (open-questions A9): the spec's message is.
- **Errors** are the spec's table, shown as the `InfoBar` or field error of the dialog ([Dialog patterns](../screens/settings.md)); the incomplete-code error is announced.

## Layout at each window width

The dialogs follow their files. Nothing in the flow depends on the width, except that at small widths the QR tile is centred and keeps its size.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `add-device` | Button on the Devices page, link in two dialogs | — | Connected, loaded, not busy |
| `add-device-approve` | Approving dialog | `Ctrl+Enter` | The confirmation is shown |
| `connect-confirm-check-code` | New device's dialog | `Ctrl+Enter` | The check code is shown |
| `add-device-cancel`, `connect-cancel` | Close buttons | `Esc` | Not while approving or installing |

## Copy differences

None beyond the page files: the scanned-code strings (`settings.connect.finish.*`, `settings.connect.scanCode*`, `messages.pairing.inviteNewerVersion`, `messages.pairing.inviteUnreachable`, `messages.pairing.inviteUsed`, `messages.connection.pairingDeclined` after a scan) are not shown on a PC, because a PC never scans; `messages.pairing.*` and `settings.addDevice.*` for typed codes are. Sentence case applies as in [platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary).

## Accessibility

- The check code is read digit by digit on both sides; the new device announces it when it appears; the approving dialog shows it with its heading.
- Every error is in the dialog (an `InfoBar` or field error) and read when it opens. Waiting states are notifications (`MostRecent`).
- Approve and Connect are reached by Tab and by Ctrl+Enter; Narrator reads the accelerator. The QR code has a text alternative (the instruction) and Enter code instead is one Tab away.
- Focus after the Windows Hello prompt closes returns to the primary button.

## Different by design

- **No scanner on the PC** (D24): a Windows PC is a QR code's displayer, never its reader, in version 1.
- **Whole-window capture exclusion** while a code shows, because the dialog is part of the window.
- **Windows Hello** for the owner check; **display kept on** while a code shows, as the phone does with its idle timer.
- **No auto-start of authentication** for scanned requests.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose).
