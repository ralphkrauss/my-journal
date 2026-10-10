---
id: lock-screen
title: Lock screen and privacy cover
features: [app-lock, privacy-cover, missing-device-key-unlock, erase-unopened-library]
sources:
  - apps/apple/JournalApp/Views/UnlockView.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/PasswordOperations.swift
  - apps/apple/JournalApp/Model/PrivacyCover.swift
  - apps/apple/JournalApp/JournalApp.swift
  - docs/design/app-lock-system-auth.md
  - docs/design/app-lock-accessibility.md
  - apps/apple/JournalApp/Views/UnopenedEraseButton.swift
  - docs/design/build-18-fixes-2026-10-06.md
  - docs/design/missing-device-key-unlock.md
  - docs/design/pre-release-fixes-2026-09-27.md
---

# Lock screen and privacy cover

## Purpose

While My Journal is locked, its windows show nothing of the journals and one way in: the device's own authentication, or the journals' password or recovery key when the device can't help.

## Entry points

- App Lock is on and: the app starts; the phone or tablet app goes to the background; the person chooses Lock My Journal; the computer locks after inactivity, when it sleeps, when its screen locks or when the user is switched (`flows/app-lock`).
- The device key is unavailable (for example after restoring the device from a backup that doesn't include it): the journals can only be opened with their password or recovery key, whether or not App Lock is on. Import Archive… and Erase Journals and Settings… are offered here too.

## Content

The whole window, scrolling at large text sizes, centred:
1. A lock symbol (decorative).
2. Heading `common.myJournalIsLocked` ("My Journal Is Locked").
3. **Unlocking with the device** (normal case):
   - an error, in red, when there is one: the app's error, or after a failed attempt `settings.lock.failed` ("My Journal couldn’t be unlocked. Try again.");
   - a prominent default button `settings.lock.unlockWith` ("Unlock with {method}", for example “Unlock with Face ID”; {method} from `library.lock.method.*`), disabled while the system is asking;
   - after App Lock moved from an old app PIN to the device's authentication, until the first unlock: `settings.lock.pinRetired` ("App Lock now uses {phrase} instead of a PIN.", {phrase} from `library.lock.phrase.*`) in secondary text;
   - after a failed attempt: a link-style button `settings.lock.useCredential` ("Use {credential}", for example “Use Master Password”).
4. **Unlocking with the credential** (device key unavailable, or Use {credential} chosen):
   - a secure field labelled with the credential's name (`common.masterPassword`, `library.lock.credential.recoveryKey`; `common.passwordOrRecoveryKey` "Password or Recovery Key" when the name isn't known), with password autofill; Return unlocks;
   - an error in red, when there is one;
   - a prominent button `settings.lock.unlock` ("Unlock"), disabled while the field is empty;
   - when the device can still unlock: a link-style button `settings.lock.useMethod` ("Use {method}") to go back;
   - when the device key is unavailable (the credential form is the only way): a group captioned `library.problem.missingKey.caption` ("Don’t have your {credential}?") with link-style Import Archive… (`import-archive`) and a destructive Erase Journals and Settings… (`erase-unopened`), for a person who no longer has the credential ([screens/unavailable-content](unavailable-content.md), [flows/erase](../flows/erase.md)). The group is one container for screen readers, labelled with its caption.

### Privacy cover

While App Lock is on and the app isn't active (app switcher, Control Center, a permission alert, another app in front on the computer), every window, including sheets, popovers and alerts, is covered by a plain background. It shows the lock symbol and `common.myJournalIsLocked` only when My Journal is actually locked; an app that is merely inactive shows a blank cover. The cover isn't shown while the system's own authentication request is in front, or while its panel closes.

### App Lock Is Off alert

When App Lock turned itself off because the device no longer has a passcode or login password, an alert once after unlocking: title `settings.lock.turnedOff.title` ("App Lock Is Off"), message `settings.lock.turnedOff.passcodeRemoved` or, for a device that used an old app PIN and has no passcode, `settings.lock.turnedOff.pinRetired` (variants for computer and phone/tablet), button `common.ok`.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Unlock with {method} | `unlock-with-device` | Asks the system (`settings.privacy.appLock.reason.unlock` "Unlock your journals"). Success opens the journals; cancel does nothing; failure shows `settings.lock.failed` and offers Use {credential}. |
| Use {credential} | `use-credential` | Shows the credential form. |
| Unlock (credential) | `unlock-with-credential` | Opens the journals with the typed password or recovery key; saves the device key again. |
| Use {method} | `use-device-unlock` | Returns to unlocking with the device. |

## States

- **Prompting automatically:** once per lock, when the app is active (at launch, and on phone/tablet after returning from the background), the system is asked without a tap.
- **Device can't authenticate (unavailable):** tapping Unlock shows `settings.lock.failed` and Use {credential}.
- **No passcode any more:** App Lock turns off, the journals open, and the App Lock Is Off alert explains.
- **Credential errors:** `messages.error.invalidRecoveryKey` ("That password or recovery key couldn’t unlock your journals."), `messages.library.deviceKeyUnavailable` ("Your device key is unavailable. Use your {credential} to unlock your journals.", credential in lower case: “master password”, or “recovery key” for a library from an early build), or a failure message in plain words ([messages.md](../messages.md), Failure messages). A library that can't be opened at all, or that a newer version wrote, never reaches this screen: it shows the library problem screen ([screens/unavailable-content](unavailable-content.md)). `messages.library.cannotOpen` remains only as a guard when unlocking finds no library.

## Rules

- A success that answers an earlier lock is never applied after a new lock.
- On phone/tablet, a success that arrives while the app isn't active is applied when it becomes active, unless it locked again meanwhile.
- After unlocking, VoiceOver's focus moves to the journals; after a cancel it returns to Unlock with {method}.
- Unlocking with the password also checks the server's copy of the password when this device's copy fails (a password changed on another device), accepting it only if it opens these journals.
- Unlocking with the master password marks the password as checked.
- App Lock stays on after unlocking with the credential.

## Accessibility

- The heading is a header. The problem message is announced when it appears.
- The layout scrolls at the largest text sizes.

## Platform notes (Apple)

- The method name follows the device: Face ID, Touch ID, Optic ID, Passcode, Login Password.
- iPhone and iPad cover all windows from the moment the app starts to leave the screen, so the app switcher's snapshot never shows journals.

## Open questions

- None.
