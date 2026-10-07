---
id: password-check
title: Check your password and set new password (Windows)
spec: screens/password-check.md
features: [password-check, forgot-password]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
---

# Check your password and set new password (Windows)

The one-time check before the first archive export, and the replacement of a forgotten password for journals that exist only on this PC. Behaviour and copy keys are the spec's [Check Your Password](../../../screens/password-check.md); the forgotten-password branch is the [forgot-password flow](../flows/forgot-password.md), and the export it belongs to is [export-archive](../../../flows/export-archive.md). The dialog patterns are in [settings](settings.md#dialog-patterns).

## Controls

One `ContentDialog` with two contents, swapped inside the same dialog (never a second dialog).

### Check your password

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | `settings.passwordCheck.title` | |
| Intro | `settings.passwordCheck.intro` | |
| Field | `PasswordBox`, `Header` `common.masterPassword`, focused on open | Wrong password: `settings.passwordCheck.wrong` under it with the error glyph; the field is cleared and takes focus; announced |
| While checking | A `ProgressRing` under the field | Field and buttons disabled; the dialog cannot be dismissed |
| Forgot password? | A `HyperlinkButton` `settings.passwordCheck.forgot` under the field | Only after a wrong password, for journals only on this PC, when Windows Hello can authenticate ([the gate](settings.md#the-authentication-gate)) |
| Buttons | Primary `settings.passwordCheck.check`, default, enabled when the field is not empty and not checking; Close `settings.passwordCheck.notNow` | Esc is Not now |

Check is done on this PC only; nothing is sent. Right: the check is recorded and the export continues (the dialog closes and the picker opens, [settings-backup](settings-backup.md)). Not now: the export continues; the check is asked again next time.

### Set new password

Title `settings.passwordCheck.setNew.title`; intro `settings.passwordCheck.setNew.intro`; `PasswordBox` `settings.changePassword.new` and `PasswordBox` `settings.changePassword.confirm`; the `CheckBox` `common.showPassword` ([Show password](settings.md#show-password)); under the fields `messages.connection.passwordsDontMatch` as the field error (the same rule as [change-password](change-password.md)); any other error in an `InfoBar` (Error, not closable); a `ProgressRing` while saving. Primary `settings.passwordCheck.setNew.set` (default, enabled when both match and are not empty); Close `common.cancel`.

Close here does not close the dialog: it goes back to Check your password (the authentication is forgotten), by cancelling the `Closing` event and swapping the content. Esc does the same. A second Esc on the check page is Not now.

**Windows Hello for Forgot password.** The link asks Windows Hello with `settings.passwordCheck.authReason` (capitalised, B23). Success shows Set new password; Cancelled or failed does nothing and says nothing. The authorisation lasts five minutes and one use. If the library connects to a server or locks in between, nothing is set. A PC where Hello is not set up never sees the link; the person can still choose Not now and export later, or remember the password. Couldn't set: `settings.passwordCheck.setNew.error`, announced; the current password still works.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Dialog 548 epx wide | Mac sheet 440 points |
| Small and text size 200% or more | The dialog fills the width and scrolls | iPhone large title sheet |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `password-check` | Primary button | `Enter` | Field not empty, not checking |
| `password-check-not-now` | Close button | `Esc` | Not while checking |
| `forgot-password` | Hyperlink | — | After a wrong password; journals only on this PC; Windows Hello available |
| `set-new-password` | Primary button | `Enter` | Both fields match and are not empty |
| `set-new-password-cancel` | Close button | `Esc` | Not while saving |

## Copy differences

Sentence case applies ("Check your password", "Not now", "Forgot password?", "Set new password", "Set password").

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.passwordCheck.authReason` | set a new password for your journals | Set a new password for your journals | vocabulary: the lower-case form was written for the Mac's sentence (open-questions B23), B23 |

## Accessibility

- `settings.passwordCheck.wrong` is announced and is the field's `HelpText`; focus returns to the emptied field.
- Focus starts in the password field; on Set new password it starts in New password; when it goes back, focus is on the password field of the check page.
- Narrator reads the title when the content swaps (a notification event with the new title, `MostRecent`).

## Different by design

- **Windows Hello** for the owner check, not the device passcode (platform.md, 13).
- **One dialog with two contents**, because Windows does not stack dialogs. Apple pushes the second page.
- **No large title** for long titles: a Windows dialog title wraps.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B23 (authentication reason casing).
