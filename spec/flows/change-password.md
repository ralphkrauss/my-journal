---
id: change-password
title: Change password
features: [change-password]
sources:
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - apps/apple/JournalApp/Model/PasswordOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Crypto.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - docs/design/sync-security-2026-09-24.md
---

# Change password

## Purpose

Replace the master password on every device at once, without re-encrypting the journals, and never leave this device and the server disagreeing about which password works.

## Entry points

- Settings ▸ Privacy ▸ Change Password… (`screens/change-password`).

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
5. This device saves the new password information and marks the password as checked (so the one-time password check isn't asked).
   - If saving fails after the server was changed: `messages.password.notSavedLocally` ("Your password was changed on your server but not on this device. Try again to finish."), the form stays disabled and the primary becomes Try Again (only the local save is retried; Cancel is disabled). If Try Again fails: `settings.changePassword.error.notSavedRetry` ("Your password was changed on your server but not on this device. Free up space, then try again."), and Cancel becomes available.
6. The sheet closes. Nothing else announces success.

On other devices, the old password keeps working for unlocking until their next unlock with the new one: unlocking with a password tries this device's copy, then the server's newer copy, accepting it only if it opens the same journals.

## Rules

- Archives and backups made earlier keep the password they were made with (`settings.changePassword.intro`).
- Only master-password libraries offer Change Password.
- If My Journal is locked when Change is chosen: `messages.error.locked` ("Unlock My Journal to continue.").
- Unexpected failures that aren't the app's own errors show `messages.password.failed`.

## Accessibility

- Every error is announced.

## Platform notes (Apple)

- None.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
