---
id: forgot-password
title: Forgot password (journals only on this device) (Apple)
spec: flows/forgot-password.md
features: [forgot-password]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/PasswordCheckView.swift
  - apps/apple/JournalApp/Model/PasswordCheckOperations.swift
  - docs/design/pre-release-ui-2026-09-27.md
---

# Forgot password (Apple)

Implements [flows/forgot-password](../../../flows/forgot-password.md). The controls, layout and screenshots of both pages are on [screens/password-check](../screens/password-check.md); this page records the state the flow keeps and the order of the calls.

## Controls

1. **Entry.** The borderless Forgot Password? button in the footer of the Check Your Password page. It exists only while `wrong` is true and `model.canSetPasswordWithoutCurrent` and `AppModel.canAuthenticateDeviceOwner` hold. The second is `LAContext().canEvaluatePolicy(.deviceOwnerAuthentication)`, so a device without a passcode or login password never shows it.
2. **Authentication.** `PasswordCheckView.forgotPassword()` runs `model.authorizePasswordReset()`. It re-checks `canSetPasswordWithoutCurrent`, then awaits `LAContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason:)`. Cancel, failure or a thrown error all return false and the page stays unchanged (no message). Success stores `passwordResetAuthorizedAt = Date()`, clears the password field and sets `setting = true`, which swaps the page for `NewPasswordForm` inside the same sheet.
3. **Set New Password.** `NewPasswordForm.set()` calls `model.setPasswordWithoutCurrent(_:)`. It throws `JournalError.locked` if the authorization is missing or older than 300 seconds, and `PasswordChangeError.unsupported` if `canSetPasswordWithoutCurrent` or the master key changed while the key was derived (a server connection, a lock, another library). Every failure shows `settings.passwordCheck.setNew.error` and announces it.
4. **Done.** On success the new envelope protects the same key, `passwordChecked` is set, the authorization is cleared and `done()` runs: the sheet's `proceed` closure marks the export as continuing and the sheet dismisses; `ArchiveExportControls` then starts the export, which opens the save dialog.
5. **Cancel on Set New Password.** `returnToCheck()` clears `passwordResetAuthorizedAt`, sets `setting = false` and refocuses the password field.

If the sheet is dismissed another way (locking, swiping it down on iPhone or iPad), `passwordResetAuthorizedAt` is not cleared; it expires after 300 seconds, and the next Forgot Password? asks for authentication again anyway.

## Layout

See [screens/password-check](../screens/password-check.md). The authentication prompt is the system's: Face ID, Touch ID or passcode sheet on iPhone and iPad, the Touch ID or password dialog on the Mac.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `forgot-password` | as in [commands.md](../commands.md) | none | after a wrong password, journals only on this device, device can authenticate its owner |
| `set-new-password` | as in commands.md | Return | both fields filled and equal, not busy |
| `set-new-password-cancel` | as in commands.md | Escape | not busy |

## Copy differences

The authentication reason (`settings.passwordCheck.authReason`) is passed unchanged, so the Mac dialog reads as a sentence ("My Journal is trying to ...") and iPhone and iPad show the lower-case text as it is. See [screens/password-check](../screens/password-check.md).

## Accessibility

As [screens/password-check](../screens/password-check.md): the setting failure is announced; focus goes to New Password when the page appears and back to the password field after Cancel.

## Differences between iPhone, iPad and Mac

None in the flow. Only the system's authentication prompt looks different on each device, because it is the system's own.

## Screenshots

None. This flow has no page of its own to capture: it runs inside the Check Your Password sheet, whose default state is listed on [screens/password-check](../screens/password-check.md). The authentication prompt is the system's and is not captured, and Set New Password has no capture.

## Source files

- View: `Views/PasswordCheckView.swift` (`forgotPassword()`, `returnToCheck()`, `NewPasswordForm`).
- Model: `Model/PasswordCheckOperations.swift` (`canSetPasswordWithoutCurrent`, `canAuthenticateDeviceOwner`, `authorizePasswordReset`, `setPasswordWithoutCurrent`; the `passwordResetAuthorizedAt` property is on `AppModel`).
- Design: [pre-release-ui-2026-09-27.md](../../../../docs/design/pre-release-ui-2026-09-27.md).

## Open questions

See [open-questions.md](../../../open-questions.md).
