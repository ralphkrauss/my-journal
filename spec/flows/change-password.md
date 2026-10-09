---
id: change-password
title: Change password
features: [change-password, forgot-password]
sources:
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - apps/apple/JournalApp/Model/PasswordOperations.swift
  - apps/apple/JournalApp/Model/ForgotPasswordOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Crypto.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - docs/design/sync-security-2026-09-24.md
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/pre-release-ui-2026-09-27.md
---

# Change password

## Purpose

Replace the master password on every device at once, without re-encrypting the journals, and never leave this device and the server disagreeing about which password works. Someone whose journals exist only on this device and who no longer knows the master password can choose a new one, after proving they own the device (Forgot Password?).

## Entry points

- Settings ▸ Privacy ▸ Change Password… (`screens/change-password`).
- Settings ▸ Backup ▸ "Not sure of your password? Change Password…" and the same line in the Export Archive sheet (`flows/export-archive`). Typing the current password is the check that it is the saved one; an unwanted change is cancelled.

## Steps

1. The person types the current password, a new one, and the new one again; Change.
2. The device reads the password information:
   - when connected, the server's copy (it's newer if the password was changed on another device); if it can't be read: `messages.password.failed`;
   - otherwise, this device's copy.
3. It checks the current password opens this library's key; checks the new one differs (`messages.password.same`) and isn't empty (`messages.password.empty`).
4. When connected, the server is updated first, proving both passwords with derived secrets (the passwords never leave the device):
   - wrong current password: `messages.password.incorrect`;
   - server too old: `messages.password.serverOutdated`;
   - the server's library doesn't use a master password: `messages.password.unsupported`;
   - connection failed or anything else: `messages.password.failed`.
5. This device saves the new password information.
   - If saving fails after the server was changed: `messages.password.notSavedLocally` ("Your password was changed on your server but not on this device. Try again to finish."), the form stays disabled and the primary becomes Try Again (only the local save is retried; Cancel is disabled). If Try Again fails: `settings.changePassword.error.notSavedRetry` ("Your password was changed on your server but not on this device. Free up space, then try again."), and Cancel becomes available.
6. The sheet closes. Nothing else announces success.

## Forgot Password?

For journals that exist only on this device and a device that can authenticate its owner.

1. Under Current Password the person chooses Forgot Password? (`settings.changePassword.forgot`). It is shown from the start, whenever eligible.
2. The system authenticates the device owner (Face ID, Touch ID, passcode or login password) with the reason `settings.changePassword.authReason`. Cancelled or failed: nothing changes, nothing is said, the sheet stays as it was.
3. Succeeded: the Current Password section is replaced by `settings.changePassword.forgotIntro`; focus moves to New Password and the screen change is announced. The person types and confirms a new password (new-password fields); Change.
4. The same key is protected with the new password (`setPasswordWithoutCurrent`); nothing is re-encrypted. The sheet closes. Failure: `settings.changePassword.error.reset`; the current password still works.

Rules specific to this path:

- Only when: master-password library, not connected to a server, not being replaced, unlocked, and the device can authenticate its owner.
- The authorization is valid for five minutes and one use, and is forgotten when the sheet closes.
- If the library connects to a server, locks or is replaced between authenticating and Change, nothing is set.
- Nothing is re-encrypted; archives exported earlier still need the old password.
- It works offline.

## Other devices

On other devices, the old password keeps working for unlocking until their next unlock with the new one: unlocking with a password tries this device's copy, then the server's newer copy, accepting it only if it opens the same journals.

## Rules

- Archives and backups made earlier keep the password they were made with (`settings.changePassword.intro`).
- Only master-password libraries offer Change Password.
- A new password has no minimum length; every screen that chooses one follows `spec/README.md` (Master passwords).
- If My Journal is locked when Change is chosen: `messages.error.locked` ("Unlock My Journal to continue.").
- Unexpected failures that aren't the app's own errors show `messages.password.failed`.

## Accessibility

- Every error is announced, including the password mismatch when it first appears. After Forgot Password? authenticates, the change of screen is announced and focus lands in New Password.

## Platform notes (Apple)

- None.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
