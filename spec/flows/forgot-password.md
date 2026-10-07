---
id: forgot-password
title: Forgot password (journals only on this device)
features: [forgot-password]
sources:
  - apps/apple/JournalApp/Views/PasswordCheckView.swift
  - apps/apple/JournalApp/Model/PasswordCheckOperations.swift
  - docs/design/pre-release-ui-2026-09-27.md
---

# Forgot password

## Purpose

Someone whose journals exist only on this device and who no longer knows the master password can choose a new one, after proving they own the device, before exporting an archive they couldn't otherwise open.

## Entry points

- Check Your Password, after a wrong password (`screens/password-check`). There's no other entry point.

## Steps

1. Export Archive… → Check Your Password → a wrong password shows `settings.passwordCheck.wrong` and, when allowed, Forgot Password?.
2. Forgot Password? asks the system to authenticate the device owner (Face ID, Touch ID, passcode or login password) with the reason `settings.passwordCheck.authReason`.
   - Cancelled or failed: nothing changes; the page stays.
3. Set New Password: the person types and confirms a new password; Set Password.
4. The same key is protected with the new password; the password is marked as checked; the export continues (the save dialog appears).
   - Failure: `settings.passwordCheck.setNew.error`; the current password still works.

## Rules

- Only when: master-password library, not connected to a server, not being replaced, unlocked, and the device can authenticate its owner.
- The authentication is valid for five minutes and one use.
- Nothing is re-encrypted; archives exported earlier still need the old password.
- If the library connects to a server, or locks, between authenticating and setting, nothing is set.

## Accessibility

- As `screens/password-check`.

## Platform notes (Apple)

- None.

## Open questions

- None.
