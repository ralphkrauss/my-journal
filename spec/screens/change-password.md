---
id: change-password
title: Change Password
features: [change-password]
sources:
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - apps/apple/JournalApp/Model/PasswordOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Crypto.swift
  - docs/design/sync-security-2026-09-24.md
  - docs/design/connection-onboarding.md
---

# Change Password

## Purpose

Changes the master password that protects the journals' key, on this device and on its server. The journals aren't re-encrypted. Flow: `flows/change-password`.

## Entry points

- Settings ▸ Privacy ▸ Change Password… (master-password libraries only).

## Content

A sheet titled `settings.changePassword.title` ("Change Password").

1. An explanation in secondary text: `settings.changePassword.intro`.
2. A secure field `settings.changePassword.current` ("Current Password") with password autofill. Its section footer shows, after a wrong password, `messages.password.incorrect` with an alert icon, in red.
3. Secure fields `settings.changePassword.new` ("New Password") and `settings.changePassword.confirm` ("Confirm New Password"), with new-password suggestions. The section footer shows, in red with an alert icon:
   - `messages.connection.passwordsDontMatch` when Confirm doesn't match (see Rules);
   - any other error message;
   - while working, an indicator with `settings.changePassword.busy` ("Changing Password…").
- Toolbar: `common.cancel`; primary `settings.changePassword.change` ("Change"), or `common.tryAgain` when the server has the new password but this device couldn't save it.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Change | `change-password-submit` | All three filled, new matches confirm, unlocked, not working | Changes the password; closes on success. |
| Try Again | `change-password-retry` | After a local save failed | Saves the new password on this device again. |
| Cancel | `change-password-cancel` | Not while working; not while a local save is pending unless retrying failed | Closes; nothing changes. |

Return moves from Current to New to Confirm; Return in Confirm changes.

## States

- **Working:** the form is disabled; the sheet can't be dismissed; `settings.changePassword.busy`.
- **Wrong current password:** `messages.password.incorrect` under Current; focus returns to Current.
- **New equals current:** `messages.password.same`.
- **Server too old:** `messages.password.serverOutdated`.
- **Library doesn't use a master password:** `messages.password.unsupported`.
- **Couldn't change (connection or server):** `messages.password.failed`.
- **Empty new password:** `messages.password.empty` (only reachable if the button's checks are bypassed).
- **Saved on the server, not on this device:** `messages.password.notSavedLocally`; the form stays disabled; primary Try Again; Cancel disabled. If Try Again fails, `settings.changePassword.error.notSavedRetry` and Cancel becomes available.
- **Other failures:** their message, for example `messages.error.locked`.

## Rules

- The confirmation mismatch shows only once Confirm isn't empty, differs from New, and either Confirm has been left once or is at least as long as New.
- Any non-empty new password is accepted (no minimum length).
- Every error is announced.

## Accessibility

- Errors are shown under their section with an icon and announced.
- Focus starts in Current Password.

## Platform notes (Apple)

- Mac: a sheet 440 points wide, at least 400 tall.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
