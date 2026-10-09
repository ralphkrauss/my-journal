---
id: change-password
title: Change Password
features: [change-password, forgot-password]
sources:
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - apps/apple/JournalApp/Model/PasswordOperations.swift
  - apps/apple/JournalApp/Model/ForgotPasswordOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Crypto.swift
  - docs/design/sync-security-2026-09-24.md
  - docs/design/connection-onboarding.md
  - docs/design/1-1-encryption-and-passwords.md
  - docs/design/pre-release-ui-2026-09-27.md
---

# Change Password

## Purpose

Changes the master password that protects the journals' key, on this device and on its server. The journals aren't re-encrypted. For journals that exist only on this device, a forgotten password can be replaced without the old one, after the device owner authenticates (**Forgot Password?**). This is the one place for passwords: typing the current password is also how a person checks they still know it. Flow: `flows/change-password`.

## Entry points

- Settings ▸ Privacy ▸ Change Password… (master-password libraries only).
- Settings ▸ Backup ▸ Export Archive and the Export Archive sheet: "Not sure of your password? Change Password…" (`settings.backup.archive.changePassword`, `screens/settings-backup`).

## Content

A sheet titled `settings.changePassword.title` ("Change Password").

1. An explanation in secondary text: `settings.changePassword.intro`.
2. A secure field `settings.changePassword.current` ("Current Password") with password autofill. Its section footer shows, after a wrong password, `messages.password.incorrect` with an alert icon, in red. Under the field, in the footer and left aligned, a borderless button `settings.changePassword.forgot` ("Forgot Password?"), shown whenever the journals exist only on this device and the device can authenticate its owner (see Rules). After the owner has authenticated, this whole section is replaced by `settings.changePassword.forgotIntro` in secondary text (see Forgot Password? below).
3. Secure fields `settings.changePassword.new` ("New Password") and `settings.changePassword.confirm` ("Confirm New Password"), both **new-password fields** (`spec/README.md`, Master passwords). The section footer shows, in red with an alert icon:
   - `messages.connection.passwordsDontMatch` when Confirm doesn't match (see Rules);
   - any other error message;
   - while working, an indicator with `settings.changePassword.busy` ("Changing Password…").
- Toolbar: `common.cancel`; primary `settings.changePassword.change` ("Change"), or `common.tryAgain` when the server has the new password but this device couldn't save it.

### Forgot Password?

Choosing it asks the system to authenticate the device owner (Face ID, Touch ID, passcode or login password) with the reason `settings.changePassword.authReason` ("Set a new password for your journals"; the Mac's authentication dialog reads “My Journal is trying to set a new password for your journals”). Cancelled or failed: nothing changes and nothing is said. Succeeded: the Current Password section is replaced, in the same sheet, by `settings.changePassword.forgotIntro`; focus moves to New Password; Change then sets the new password without the old one. The authorization lasts five minutes and one use and is forgotten when the sheet closes.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Forgot Password? | `forgot-password` | Journals only on this device, not being replaced, unlocked, owner authentication available; not while working | Authenticates the owner; on success shows the forgot form above. |
| Change | `change-password-submit` | All three filled (the two new fields only, after Forgot Password?), new matches confirm, unlocked, not working | Changes the password; closes on success. |
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
- **Forgot Password? not eligible** (on a server, the journals being replaced, locked, or the device can't authenticate its owner): the button isn't shown. A person on a server who has forgotten the password has no reset; the server keeps its own copy.
- **Couldn't set a new password** (after Forgot Password?): `settings.changePassword.error.reset` ("Couldn’t set a new password. Your current password still works."), announced. This includes the authorization having expired or the library having connected to a server, locked or been replaced meanwhile: nothing is set.
- **Offline:** a library on a server needs the connection to change its password (`messages.password.failed`); Forgot Password? is local only and works offline.
- **Saved on the server, not on this device:** `messages.password.notSavedLocally`; the form stays disabled; primary Try Again; Cancel disabled. If Try Again fails, `settings.changePassword.error.notSavedRetry` and Cancel becomes available.
- **Other failures:** their message, for example `messages.error.locked`.

## Rules

- The confirmation mismatch shows only once Confirm isn't empty, differs from New, and either Confirm has been left once or is at least as long as New. It is announced when it first appears.
- Any non-empty new password is accepted (no minimum length). The shared rule is in `spec/README.md` (Master passwords).
- Forgot Password? is offered only for journals that exist only on this device (a server keeps its own copy of the password), only for master-password libraries, and only when the device can authenticate its owner. It is shown from the start, not only after a wrong password; it can't be used without authentication.
- A new password set with Forgot Password? must be set within five minutes of authenticating, and the authorization works once; otherwise nothing is set. It protects the same key; nothing is re-encrypted. Archives exported before still need the old password (`settings.changePassword.forgotIntro`).
- Locking, connecting to a server or replacing the library between authenticating and Change sets nothing.
- Every error is announced.

## Accessibility

- Errors are shown under their section with an icon and announced.
- Focus starts in Current Password. Forgot Password? is a button with its visible label; the authentication is the system's. After authenticating, the change of screen is announced and focus lands in New Password.

## Platform notes (Apple)

- iPhone: a grouped form with an inline title, Cancel and Change in the bar. iPad: a form sheet, the same. Mac: a sheet 440 points wide, at least 400 tall, the same toolbar. Forgot Password? sits under Current Password on all three, in the section footer with the wrong-password error.
- On the Mac the authentication dialog reads “My Journal is trying to set a new password for your journals”, so the reason is lower case there (the `mac` variant of `settings.changePassword.authReason`).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
