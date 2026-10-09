---
id: change-password
title: Change password (Windows)
spec: screens/change-password.md
features: [change-password, forgot-password]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/password-box
---

# Change password (Windows)

A dialog with three password fields, and Forgot password? for journals that exist only on this PC. Behaviour and copy keys are the spec's [Change Password](../../../screens/change-password.md); the steps and failure branches are the [change-password flow](../flows/change-password.md). The dialog patterns are in [settings](settings.md#dialog-patterns).

## Controls

A `ContentDialog`, `Title` `settings.changePassword.title`, default width. Content, top to bottom:

| Spec element | Control | Notes |
| --- | --- | --- |
| Explanation | `TextBlock` (`Body`, secondary brush), `settings.changePassword.intro` | |
| Current password | `PasswordBox`, `Header` `settings.changePassword.current`, `InputScope` Password; focused when the dialog opens | Its field error shows under it: `messages.password.incorrect` with the error glyph, critical brush |
| Forgot password? | A `HyperlinkButton`, `settings.changePassword.forgot`, left aligned directly under the Current password box | Offered only when the journals exist only on this PC (not on a server), the library uses a master password, it is not being replaced, the window is unlocked, Windows Hello is available and nothing is working. A PC without Hello never shows it. See Forgot password? below |
| New password | `PasswordBox`, `Header` `settings.changePassword.new`, a new-password field: no autofill, no suggestion, no minimum length | |
| Confirm new password | `PasswordBox`, `Header` `settings.changePassword.confirm`, a new-password field | |
| Show password | A `CheckBox`, `common.showPassword`, under the three fields ([Show password](settings.md#show-password)) | Not in the spec's list, which relies on the platform's reveal control; added so the reveal works on Windows without press-and-hold, because the person types a new password twice (D41) |
| Field errors under the new fields | A `TextBlock` with the error glyph and the critical brush: `messages.connection.passwordsDontMatch`, `messages.password.same`, `messages.password.empty` | Errors about the fields ([Dialog patterns, 4](settings.md#dialog-patterns)); cleared when a field changes |
| Other errors and the busy line | An `InfoBar` (Error, not closable, at the end of the content) for `messages.connection.serverNeedsUpdate`, `messages.password.unsupported`, `messages.password.failed`, `messages.password.notSavedLocally`, `settings.changePassword.error.notSavedRetry` and `messages.error.locked`; while working a `ProgressRing` and `settings.changePassword.busy` | Errors that are not about one field ([Dialog patterns, 4](settings.md#dialog-patterns), [messages](../messages.md)); announced when the bar opens |
| Buttons | Primary `settings.changePassword.change` (default), or `common.tryAgain` when the server has the new password but this PC could not save it; Close `common.cancel` | |

### Forgot password?

Choosing the link asks Windows Hello through [the authentication gate](settings.md#the-authentication-gate) with the reason `settings.changePassword.authReason` (capitalised form). Cancelled or failed: nothing changes, nothing is said, the dialog stays as it was. Succeeded: the Current password box and the link are replaced, in the same dialog, by `settings.changePassword.forgotIntro` (`Body`, secondary brush), and focus moves to New password; the change of content is announced (see Accessibility). Change then sets the new password without the old one. The authorization lasts five minutes and one use and is forgotten when the dialog closes; if it has expired, or the library connected to a server, locked or was replaced meanwhile, nothing is set and `settings.changePassword.error.reset` shows in the dialog's error bar (announced). The same key is protected with the new password; nothing is re-encrypted, and archives exported earlier still need the old password. It works offline.

Password manager suggestions and AutoFill do not exist for native Windows fields ([platform.md, 25](../platform.md#25-text-input-and-spelling)); the fields are plain `PasswordBox`es. A person's password manager can still type into them with its own hotkey.

**Rules from the spec.**

- Primary is disabled until all three fields are filled (the two new fields only, after Forgot password?), the new password matches the confirmation, and the window is unlocked and not working. Any non-empty new password is accepted: there is no minimum length and no strength meter.
- The mismatch message shows only once Confirm is not empty, differs from New, and either Confirm has been left once or is at least as long as New.
- Enter moves from Current to New to Confirm (from New to Confirm after Forgot password?) (each field's `KeyDown` moves focus and marks the key handled); Enter in Confirm presses the primary button.
- Working: the fields are disabled, the dialog cannot be dismissed (Esc does nothing, Close disabled), `settings.changePassword.busy` shows.
- Wrong current password: `messages.password.incorrect` under Current, and focus returns to Current.
- Saved on the server but not on this PC: the fields stay disabled, primary is `common.tryAgain`, Close is disabled until Try again fails once more; then `settings.changePassword.error.notSavedRetry` shows and Close is enabled.
- On success the dialog closes; nothing else announces it.
- Passwords are cleared from the fields when the dialog closes; none is logged.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Dialog 548 epx wide; fields full width | Mac sheet 440 points |
| Small | The dialog fills the width | iPhone sheet |
| Text size 200% or more | The dialog scrolls; no field is cut off | Accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `change-password-submit` | Primary button | `Enter` in the last field | All three filled (the two new fields after Forgot password?), new matches confirm, unlocked, not working |
| `change-password-retry` | Primary button | — | After a local save failed |
| `change-password-cancel` | Close button | `Esc` | Not while working; not while a local save is pending |
| `forgot-password` | Link button under Current password | — | Journals only on this PC, not being replaced, unlocked, Windows Hello available, not working |

## Copy differences

Sentence case applies ("Change password", "Current password", "New password", "Confirm new password", "Changing password…", "Forgot password?"). The reason `settings.changePassword.authReason` uses its default (capitalised) form, not the Mac variant. Beyond that: none. The new check box uses the existing `common.showPassword`. The Export Archive pointer `settings.backup.archive.changePassword` is on the [Backup page](settings-backup.md), not here.

## Accessibility

- Each `PasswordBox` is named by its header. Errors are the field's `HelpText` and are announced after focus moves, as the spec asks ("every error is announced"); the busy text is a notification event.
- Focus starts in Current password. After an error, focus returns to the field that caused it. The link is a button with its visible label; Windows Hello's prompt is the system's. After Windows Hello succeeds, a notification (`MostRecent`) announces the new content, `settings.changePassword.forgotIntro`, and focus lands in New password.
- Narrator does not read password text; the reveal check box is the only way to see it, and it applies to all three fields.

## Different by design

- **Forgot password? is a link under the field, offered only when Windows Hello is available**, as the spec requires that the device can authenticate its owner; the authentication is Windows Hello, where Apple uses Face ID, Touch ID, passcode or login password.
- **Check box for reveal** instead of the platform's reveal control or autofill suggestions (D41).
- **No sheet title bar rows**: Apple repeats the title as a heading row on older Macs; a Windows dialog always has its title.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D41 (Show password control).
