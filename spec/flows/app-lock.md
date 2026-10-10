---
id: app-lock
title: App Lock
features: [app-lock, mac-inactivity-lock, lock-now]
sources:
  - apps/apple/JournalApp/Views/AppLockSettings.swift
  - apps/apple/JournalApp/Views/InactivityLockSettings.swift
  - apps/apple/JournalApp/Views/UnlockView.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/DeviceAuthentication.swift
  - apps/apple/JournalApp/Model/InactivityLock.swift
  - apps/apple/JournalApp/Model/LockSaving.swift
  - apps/apple/JournalApp/Model/PrivacyCover.swift
  - apps/apple/JournalApp/AppCommands.swift
  - docs/design/app-lock-system-auth.md
  - docs/design/mac-inactivity-lock-2026-10-03.md
---

# App Lock

## Purpose

Keeps journals out of sight on a shared or unattended device, using only the device's own authentication. It doesn't change how journals are encrypted.

## Turning App Lock on

1. Settings ▸ Privacy ▸ Require {method} (`screens/settings-privacy`).
2. Available only when the device can authenticate its owner (it has a passcode or login password). Otherwise the switch is disabled and the footer says how to set one.
3. The system asks (`settings.privacy.appLock.reason.turnOn`).
   - Success: saved. If saving fails: alert `settings.privacy.appLock.error.turnOn`.
   - Cancelled or failed: the switch returns; nothing said.
   - No passcode (removed meanwhile): stays off.

## Turning App Lock off

1. Switch off; the system asks (`settings.privacy.appLock.reason.turnOff`). Without a passcode, no authentication is needed.
2. Success: saved; if saving fails, alert `settings.privacy.appLock.error.turnOff`.

## When it locks

- At every launch, when App Lock is on.
- Phone/tablet: whenever the app goes to the background (no grace period). It asks for authentication again once the app is in front, not over the device's own Lock Screen.
- Lock My Journal: the button in Settings ▸ Privacy (closes Settings), and on the computer the menu command `lock-my-journal` (application menu, Control-Command-L), enabled only while App Lock is on.
- Computer only:
  - after no use for the chosen time (Lock when inactive: 5, 15, 30 minutes, 1 hour, or Never; default 30);
  - when the computer sleeps or its screen locks;
  - when the user is switched.

### What counts as use (computer)

Key presses, modifier keys, clicks, drags, scrolling and trackpad gestures in any of My Journal's windows; pointer movement only while My Journal is the active app; opening a menu; edits in the editor (including dictation and VoiceOver editing) and choosing another entry. Syncing doesn't count. Any input after the time has passed locks instead of acting. The clock keeps counting while the computer sleeps.

While an action the person started is running (connecting, importing, turning on encryption, exporting, adding a device), the time is held and starts again when it ends.

Changing Lock when inactive to a longer time or Never asks for authentication (`settings.privacy.appLock.reason.change`); a shorter time doesn't. A changed setting counts from the moment it changes.

## Locking

1. Writing in the open entry and in open sheets is saved first, for a moment at most (about two seconds).
2. The journals are locked: every window shows the lock screen (`screens/lock-screen`); sheets, alerts and menus about journals close.
3. Anything not yet saved is saved after locking.

## Unlocking

See `screens/lock-screen`. Once per lock, while the app is active, the system is asked without a tap.

- Success: the journals open where they were.
- Cancel: the lock screen stays; Unlock with {method} asks again.
- Failure or unavailable: `settings.lock.failed`; Use {credential} offers the password or recovery key.
- No passcode any more: App Lock turns itself off, the journals open, and `settings.lock.turnedOff.*` explains once.

## Moving from the old app PIN

Earlier versions used an app PIN. On first launch of this version, the PIN is removed and App Lock uses the device's authentication instead; until the first unlock the lock screen says `settings.lock.pinRetired`. A device without a passcode gets App Lock off and the alert `settings.lock.turnedOff.pinRetired`.

## Other places App Lock asks

When App Lock is on, the device owner authenticates before:
- Export as Markdown (`flows/export-markdown`);
- Erase Journals and Settings (`flows/erase`).
Adding a device always asks, whether or not App Lock is on (`flows/pair-device`).

## Rules

- Only the system's authentication: biometrics with the device passcode or login password as fallback, and a paired watch where offered. Nothing of the app's own.
- App Lock is stored with this device's library and never synced. Erase removes it.
- No journal content is shown while locked, including in the app switcher.
- Locking cancels a system authentication request that is showing.

## Accessibility

- Announcements and focus as in `screens/lock-screen`.

## Platform notes (Apple)

- Locking when inactive, on sleep and on user switching exist only on the Mac; iPhone and iPad lock on leaving the foreground.
- The Mac menu item is My Journal ▸ Lock My Journal (⌃⌘L).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
