---
id: password-check
title: Check Your Password, and Set New Password
features: [password-check, forgot-password]
sources:
  - apps/apple/JournalApp/Views/PasswordCheckView.swift
  - apps/apple/JournalApp/Model/PasswordCheckOperations.swift
  - docs/design/pre-release-ui-2026-09-27.md
---

# Check Your Password / Set New Password

## Purpose

Before the first archive export, makes sure the master password is the one the person saved, because the archive can't be opened without it. For journals that exist only on this device, a forgotten password can be replaced after the device owner authenticates. Flows: `flows/export-archive`, `flows/forgot-password`.

## Entry points

- Export Archive…, when the check is pending (`flows/export-archive`).

## Content

A sheet with a large title (phone/tablet), showing one of two pages.

### Check Your Password

Title `settings.passwordCheck.title` ("Check Your Password").
1. `settings.passwordCheck.intro`.
2. A secure field `common.masterPassword` ("Master Password") with password autofill. Footer, when applicable:
   - after a wrong password, in red with an alert icon: `settings.passwordCheck.wrong` ("Wrong password. Try again.");
   - while checking: an activity indicator;
   - after a wrong password, when a new password may be set without the old one (journals only on this device, and the device can authenticate its owner): a borderless button `settings.passwordCheck.forgot` ("Forgot Password?").
- Toolbar: cancel button `settings.passwordCheck.notNow` ("Not Now", Escape); primary `settings.passwordCheck.check` ("Check", Return), enabled when the field isn't empty and not checking.

### Set New Password

Title `settings.passwordCheck.setNew.title` ("Set New Password").
1. `settings.passwordCheck.setNew.intro`.
2. Secure fields `settings.changePassword.new` and `settings.changePassword.confirm`. Footer: `messages.connection.passwordsDontMatch` (same rule as Change Password), an error message, or an indicator while saving.
- Toolbar: `common.cancel` (Escape; back to Check Your Password); primary `settings.passwordCheck.setNew.set` ("Set Password", Return), enabled when both match and aren't empty.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Check | `password-check` | Right: the check is recorded and the export continues. Wrong: `settings.passwordCheck.wrong`, the field clears and takes focus. |
| Not Now | `password-check-not-now` | The export continues; the check is asked again next time. |
| Forgot Password? | `forgot-password` | Asks for the device owner's authentication (`settings.passwordCheck.authReason` "set a new password for your journals"); on success shows Set New Password. |
| Set Password | `set-new-password` | Saves the new password; the export continues. |
| Cancel (Set New Password) | `set-new-password-cancel` | Returns to Check Your Password; the authentication is forgotten. |

## States

- **Checking / saving:** fields and buttons disabled; the sheet can't be dismissed while checking.
- **Couldn't set the new password:** `settings.passwordCheck.setNew.error` ("Couldn’t set a new password. Your current password still works."), announced.
- **Locked:** the sheet closes.

## Rules

- Asked only for master-password libraries that aren't connected to a server and whose password hasn't been typed correctly since it was set (connecting, unlocking with it, changing it, importing an archive with it all count).
- Checking happens on this device only; nothing is sent.
- Forgot Password? is offered only after a wrong password, only for journals that exist only on this device (a server keeps its own copy of the password), and only when the device can authenticate its owner.
- A new password must be set within five minutes of authenticating; otherwise nothing is set.
- Setting a new password protects the same key; nothing is re-encrypted. Archives exported before still need the old password.

## Accessibility

- `settings.passwordCheck.wrong` is announced.
- Focus starts in the password field.

## Platform notes (Apple)

- Large navigation titles on iPhone, because both titles are too long for the bar between two buttons.
- Mac: a sheet 440 points wide. On the Mac the authentication dialog reads “My Journal is trying to set a new password for your journals.”; iPhone and iPad show the same reason as is.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
