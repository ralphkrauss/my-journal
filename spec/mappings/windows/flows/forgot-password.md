---
id: forgot-password
title: Forgot password (Windows)
spec: flows/forgot-password.md
features: [forgot-password]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
---

# Forgot password (Windows)

Someone whose journals exist only on this PC and who no longer knows the master password can choose a new one, after proving they own the PC, before exporting an archive they could not otherwise open. Steps and rules are the spec's [flow](../../../flows/forgot-password.md); the page is [password-check](../screens/password-check.md); the owner check is Windows Hello through [the gate](../screens/settings.md).

## Controls

| Spec step | Windows |
| --- | --- |
| 1 Export Archive… → Check your password → a wrong password | `settings.passwordCheck.wrong` and, only when every condition holds, the link `settings.passwordCheck.forgot` |
| 2 Authenticate the device owner | The gate asks Windows Hello with `settings.passwordCheck.authReason` (capitalised). Cancelled or failed: nothing changes and nothing is said. The authorisation is valid for five minutes and one use |
| 3 Set new password | The dialog's content is swapped for Set new password; two `PasswordBox`es and the show-password check box |
| 4 Save and continue | The same key is protected with the new password; the password is marked as checked; the dialog closes and the save picker appears ([settings-backup](../screens/settings-backup.md)). Failure: `settings.passwordCheck.setNew.error`; the current password still works |

The conditions for the link, from the spec: a master-password library, not connected to a server, not being replaced, unlocked, and the device can authenticate its owner. **On Windows the last condition means Windows Hello is available** (Available in the table of [app-lock](app-lock.md#the-windows-hello-gate)). A PC where Hello is not set up, is off by policy or is not present therefore never offers the link; the person can choose Not now, export later, or remember the password. The conditions are re-read each time the page is shown. If the library connects to a server, or locks, between authenticating and setting, nothing is set.

Nothing is re-encrypted: archives exported earlier still need the old password (`settings.passwordCheck.setNew.intro` says so).

## Layout at each window width

Not applicable.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `forgot-password` | Link in Check your password | — | After a wrong password, with the conditions above |
| `set-new-password`, `set-new-password-cancel` | Dialog buttons | `Enter`, `Esc` | As in [password-check](../screens/password-check.md) |

## Copy differences

`settings.passwordCheck.authReason` in its capitalised form (B23). Otherwise none.

## Accessibility

As [password-check](../screens/password-check.md): the wrong-password message is announced; focus starts in the password field; after the swap, on New password; after going back, on the password field.

## Different by design

- **Windows Hello decides availability.** On Apple nearly every device has a passcode; many Windows PCs have a password-only account, so the link will be missing more often. The product rule (an owner check before replacing the password) is kept, and the person can still export after choosing Not now.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B23 (authentication reason casing).
