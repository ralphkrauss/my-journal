---
id: change-password
title: Change password (Windows)
spec: flows/change-password.md
features: [change-password, forgot-password]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/password-box
---

# Change password (Windows)

Replaces the master password on every device at once, without re-encrypting the journals, and never leaves this PC and the server disagreeing about which password works. For journals that exist only on this PC, a forgotten password can be replaced without the old one after Windows Hello (Forgot password?). The steps and branches are the spec's [flow](../../../flows/change-password.md); the dialog is [change-password (screen)](../screens/change-password.md).

## Controls

The spec's six steps happen in the dialog of the screen file. Windows details:

| Spec step | Windows |
| --- | --- |
| 1 Type current, new, confirm; Change | Three `PasswordBox`es and the Change button; the passwords stay in memory only as long as the dialog needs them and are cleared when it closes. They are never written to a log, a crash report or the undo stack of a text box |
| 2 Read the password information | Connected: the server's copy (newer if changed elsewhere), `messages.password.failed` when it cannot be read; otherwise this PC's copy |
| 3 Checks | The current password must open this library's key; the new one differs (`messages.password.same`) and is not empty (`messages.password.empty`); if the window is locked, `messages.error.locked` |
| 4 Server first | Proves both passwords with derived secrets (the passwords never leave the PC): `messages.password.incorrect`, `messages.password.serverOutdated`, `messages.password.unsupported`, `messages.password.failed` |
| 5 This PC saves | The new password information is written to the library's configuration in the app's local folder, with no other marker. If the write fails after the server changed: `messages.password.notSavedLocally`, primary Try again, Cancel disabled; if Try again fails, `settings.changePassword.error.notSavedRetry` and Cancel is enabled. A full disk, a read-only folder and security software holding the file are the likely causes on Windows, and the messages ask the person to free up space |
| 6 Close | The dialog closes; nothing else announces success |

Archives that the person exported before keep the password they were made with, which is why the Backup page's Export archive pointer opens this dialog ([settings-backup](../screens/settings-backup.md)): typing the current password there is the check that it is the saved one.

The device key is not touched: the journals are not re-encrypted, so `ISecretStore` keeps the same key. Other devices keep the old password working for unlocking until their next unlock with the new one, as in the spec.

### Forgot password?

For journals that exist only on this PC and a PC with Windows Hello. The spec's steps happen in the same dialog:

| Spec step | Windows |
| --- | --- |
| 1 The link under Current password | `settings.changePassword.forgot`, shown from the start whenever eligible: a master-password library, not connected to a server (a server keeps its own copy of the password), not being replaced, unlocked, Windows Hello available. A PC without Hello never shows it |
| 2 The owner authenticates | Windows Hello through [the authentication gate](../screens/settings.md) with `settings.changePassword.authReason`. Cancelled or failed: nothing changes and nothing is said |
| 3 The form changes | The Current password box is replaced by `settings.changePassword.forgotIntro`; focus moves to New password and the change is announced. The person types and confirms a new password (new-password fields, any non-empty password) and chooses Change |
| 4 Set without the current password | The same key is protected with the new password; nothing is re-encrypted; the dialog closes. Failure: `settings.changePassword.error.reset` and the current password still works |

The authorization lasts five minutes and one use and is forgotten when the dialog closes. If the library connects to a server, locks or is replaced between authenticating and Change, or the time has passed, nothing is set and `settings.changePassword.error.reset` shows. It works offline.

## Layout at each window width

Not applicable: the dialog's layout is in the [screen file](../screens/change-password.md).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `change-password` | Button in Settings > Privacy; the pointer under the archive footer on the Backup page and in the File-menu export dialog | — | Unlocked; master-password libraries only |
| `forgot-password` | Link button under Current password | — | Journals only on this PC, unlocked, not being replaced, Windows Hello available, not working |
| `change-password-submit`, `change-password-retry`, `change-password-cancel` | Dialog buttons | `Enter`, `Esc` as in the screen file | As in the screen file |

## Copy differences

None beyond sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)); the explanation `settings.changePassword.intro` is unchanged, and `settings.changePassword.authReason` uses its default form.

## Accessibility

Every error is announced after focus moves to the field that can fix it, and the busy text `settings.changePassword.busy` is a notification. The rest is in the screen file.

## Different by design

None beyond the screen file: the flow is the same on every platform.

## Open questions

None.
