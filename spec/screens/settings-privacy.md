---
id: settings-privacy
title: Settings ▸ Privacy
features: [encryption-status, encrypt-existing-journals, change-password, forgot-password, sync-recovery, app-lock, mac-inactivity-lock, lock-now]
sources:
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Model/EncryptionUpgrade.swift
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - apps/apple/JournalApp/Views/AppLockSettings.swift
  - apps/apple/JournalApp/Views/InactivityLockSettings.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/DeviceAuthentication.swift
  - apps/apple/JournalApp/Model/InactivityLock.swift
  - apps/apple/JournalApp/Model/LocalConfiguration.swift
  - docs/design/enable-encryption.md
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/sync-security-2026-09-24.md
  - docs/design/app-lock-system-auth.md
  - docs/design/mac-inactivity-lock-2026-10-03.md
---

# Settings ▸ Privacy

## Purpose

Shows whether the journals are encrypted and offers the next step (encrypt the journals of a library made before every library was encrypted, change the password, or reconnect after it was turned on elsewhere), and controls App Lock.

## Entry points

- Settings ▸ Privacy (`screens/settings`).

## Content

When there is no library (only while Settings closes after erasing), the pane is empty.

### 1. Encryption section

Header `settings.privacy.encryption.header`.

1. A status line: `settings.privacy.encryption.on` ("Your Journals Are Encrypted") or `settings.privacy.encryption.off` ("Encryption Is Off").
2. One action, the first that applies:
   - encrypted, with a master password: `settings.privacy.changePassword` ("Change Password…") → `screens/change-password` (which also holds Forgot Password?). Encrypted libraries from early versions (recovery key) show no action.
   - not encrypted, and the server's journals are now encrypted (encryption was turned on from another device): `common.reconnect` ("Reconnect…") → Reconnect, straight to signing in (`flows/reconnect-to-server`).
   - not encrypted: `settings.privacy.encryption.turnOn` ("Turn On Encryption…") → the Encrypt Your Journals form as a sheet with Cancel (`screens/encrypt-journals`). Only a library made before 1.1 can be here, after Not Now: nothing creates an unencrypted library any more.
3. Footer:
   - encrypted: `settings.privacy.encryption.footerOn` ("Keep your {credential} somewhere safe. It can’t be recovered."), with the credential's name in lower case (master password, recovery key);
   - Reconnect… offered: `messages.encryption.turnedOnElsewhere`;
   - not encrypted: `common.unencryptedWarning`.

### 2. App Lock section

Header `settings.privacy.appLock.header`.

1. A switch `settings.privacy.appLock.require` ("Require {method}"), where {method} is what the device asks for: `library.lock.method.faceID` ("Face ID"), `library.lock.method.touchID`, `library.lock.method.opticID`, `library.lock.method.passcode` ("Passcode"), `library.lock.method.loginPassword` ("Login Password"). Devices that can't name a method use Passcode (phone/tablet) or Login Password (computer).
2. Computer only, when App Lock is on: a pop-up `settings.privacy.appLock.inactive` ("Lock when inactive") with the choices `settings.privacy.appLock.inactive.minutes` for 5, 15 and 30 minutes, `settings.privacy.appLock.inactive.hours` for 1 hour, and `common.never` ("Never"), in that order with Never last. A stored time that isn't one of these (from another version) is added in its place in the order.
3. When App Lock is on: a button `common.lockMyJournal` ("Lock My Journal").
4. Footer:
   - authentication available: `settings.privacy.appLock.footer` ("{who} is needed to open My Journal.{automatic} App Lock doesn’t change how your journals are encrypted."). {who} is the method phrase with its first letter capitalised:
     - `library.lock.phrase.biometric` ("{method} or your {device} passcode", Face ID and Optic ID),
     - `library.lock.phrase.touchID` (computer: "Touch ID or your login password"; phone/tablet: "Touch ID or your {device} passcode"),
     - `library.lock.phrase.passcode` ("your {device} passcode"),
     - `library.lock.phrase.loginPassword` ("your login password");
     {device} is `library.lock.device.iPhone`, `library.lock.device.iPad` or `library.lock.device.mac`.
     {automatic}, computer only and only while App Lock is on: `settings.privacy.appLock.footerInactive` (a lock time is chosen) or `settings.privacy.appLock.footerSleepOnly` (Never). Each starts with a space.
   - no passcode: `settings.privacy.appLock.noPasscode` (variant: computer "…set a login password for your Mac user in System Settings."; phone/tablet "…set a passcode for this {device} in Settings.");
   - not available: `settings.privacy.appLock.unavailable`.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Turn On Encryption… | `turn-on-encryption` | Unlocked, and not while the journals are being replaced (except to show a run in progress) | Opens the Encrypt Your Journals form as a sheet with Cancel (`screens/encrypt-journals`, `flows/encrypt-journals`). |
| Change Password… | `change-password` | Unlocked | Opens Change Password (`flows/change-password`). |
| Reconnect… | `sync-reconnect` | Unlocked | Opens Reconnect at signing in. |
| Require {method} | `toggle-app-lock` | Not while the system is asking; turning on needs authentication to be available; turning off is always possible | Asks for authentication, then saves (`flows/app-lock`). |
| Lock when inactive (computer) | `set-inactivity-lock` | App Lock on; not while the system is asking | A shorter time saves at once; a longer time or Never asks for authentication first. |
| Lock My Journal | `lock-my-journal` | App Lock on | Saves what's open, locks, and closes Settings. |

## States

- **Switch while asking:** shows the requested value until the system answers; disabled meanwhile. Cancelled or failed authentication returns it, with nothing said.
- **Couldn't save App Lock:** alert `settings.privacy.appLock.error.turnOn` ("Couldn’t Turn On App Lock") or `settings.privacy.appLock.error.turnOff`, message `settings.privacy.appLock.error.message` ("Try again."), button `common.ok`. App Lock stays as it was.
- **Couldn't save Lock when inactive:** alert `settings.privacy.appLock.inactive.error` ("Couldn’t Change Setting"), message `settings.privacy.appLock.error.message`, button `common.ok`.
- **No passcode:** the switch is disabled while off; while on (the passcode was removed), it stays enabled so App Lock can be turned off.
- **Encryption being turned on:** the journals show the working notice; Turn On Encryption… shows where the work is.
- **Locked:** Settings shows only its locked text.

## Rules

- App Lock uses only the device's own authentication (Face ID, Touch ID, Optic ID, the device passcode, or the computer's login password, and a paired watch where the system offers it). There's no app PIN.
- App Lock is per device and isn't synced. It doesn't change encryption.
- Turning App Lock on or off asks for authentication (`settings.privacy.appLock.reason.turnOn` "Turn on App Lock", `settings.privacy.appLock.reason.turnOff` "Turn off App Lock"). Turning off without a passcode (the passcode was removed) needs none.
- Lock when inactive: default 30 minutes; stored per library. A longer time or Never weakens App Lock, so it asks for authentication first (`settings.privacy.appLock.reason.change` "Change App Lock settings"); a shorter time doesn't. See `flows/app-lock` for what counts as use.
- The availability (and so the method name and footer) is read again whenever the pane appears and when the app becomes active, so a passcode set meanwhile is reflected.
- Change Password is offered only for master-password libraries (the current format). Turn On Encryption… is offered only for libraries without encryption, which persist for people who chose Continue Without Encryption in an earlier version and chose Not Now; the unencrypted rows (status, footer, Turn On Encryption…, Reconnect…) stay until Not Now is removed in a later release. Encryption can't be turned off.

## Accessibility

- The switch is labelled with the method it requires.
- The status line is plain text; the actions are buttons with ellipses where they open a sheet.

## Platform notes (Apple)

- Lock when inactive and the automatic-lock footer sentences exist only on the Mac; iPhone and iPad lock whenever the app leaves the screen.
- Mac labels in sentence case: "Lock when inactive", and the choices "For 5 minutes", "For 1 hour", as System Settings ▸ Lock Screen.
- On the Mac, the system's authentication dialog reads “My Journal is trying to {reason}”, so reasons start in lower case there (`mac` variants).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
