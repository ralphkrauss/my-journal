---
id: change-password
title: Change password (Apple)
spec: flows/change-password.md
features: [change-password]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/ChangePasswordView.swift
  - apps/apple/JournalApp/Model/PasswordOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Crypto.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ServerClient.swift
  - docs/design/sync-security-2026-09-24.md
---

# Change password (Apple)

Implements [flows/change-password](../../../flows/change-password.md). The sheet's controls, layout and screenshots are on [screens/change-password](../screens/change-password.md); this page records how the steps map to the code.

## Controls

The flow uses no control of its own beyond the sheet. Step by step:

1. **Change.** `ChangePasswordView.change()` sets `busy`, clears `failure` and `message`, then runs one `Task` that calls `model.preparePasswordChange(current:new:)`.
2. **Read the password information.** In `preparePasswordChange`: `guard !locked`, a master key and a local envelope, else `JournalError.locked` (shown as `messages.error.locked` through `Error.shown`); `formatVersion != 2` throws `PasswordChangeError.unsupported` (`messages.password.unsupported`). When `connection != nil` the server's envelope replaces the local one (`ServerClient.recoveryEnvelope()`); a failure to read it is `PasswordChangeError.failed` (`messages.password.failed`).
3. **Check and re-wrap.** `VaultCrypto.changePassword` runs in `Task.detached` so the key derivation stays off the main actor. It rejects an equal password (`messages.password.same`), an empty new one (`messages.password.empty`, unreachable from the button) and a current password that does not open this library's key (`messages.password.incorrect`).
4. **Server first.** `ServerClient.changePassword` posts to the recovery password endpoint with both derived secrets. HTTP 403 maps to `incorrectPassword`, 404 and 405 to `serverOutdated` (`messages.password.serverOutdated`), 409 to `unsupported`, anything else, and any `URLError` except a cancel, to `failed`. A library without a server connection skips this call.
5. **Then this device.** The view sets `unsaved` to the new envelope before calling `model.savePasswordChange`, so the form is already disabled if saving throws. `savePasswordChange` writes `configuration.recovery`, sets `passwordChecked = true` (no later password check, see [screens/password-check](../screens/password-check.md)) and calls `persistConfiguration()`; on failure it restores the previous configuration and throws `notSavedLocally` (`messages.password.notSavedLocally`). Try Again calls `retrySave()`, which only repeats the local save; a second failure sets `retryFailed` and the message `settings.changePassword.error.notSavedRetry`.
6. **Close.** `finish()` clears the three fields and `dismiss()`es. There is no success message and no announcement.

Error routing in `show(_:)`: `incorrectPassword` shows under Current and refocuses it; an error that is neither a `PasswordChangeError` nor a `JournalError` (for example a `URLError` from step 4) becomes `messages.password.failed`; everything else is `error.shown(.saving)`, which keeps the app's own text. The message is announced with `announceForAccessibility`.

Other devices: `AppModel.recoverKey(_:phrase:)` (same file) tries this device's envelope first, then, only for a version 2 library with a saved connection, asks the server for its envelope and accepts it only if it opens the same journals (`masterKey` equal when unlocked, or the candidate store reads items).

## Layout

Nothing beyond the sheet; see [screens/change-password](../screens/change-password.md).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `change-password` | as in [commands.md](../commands.md) | as in commands.md | master-password library, unlocked |
| `change-password-submit` | as in commands.md | Return in Confirm | all fields valid, not busy |
| `change-password-retry` | as in commands.md | none | server changed, local save failed |
| `change-password-cancel` | as in commands.md | system sheet Escape (not verified) | not busy, not while a local save is pending |

## Copy differences

None.

## Accessibility

Failures are announced by `announceForAccessibility` (high priority on the Mac, a plain announcement on iOS); success is silent. The confirmation mismatch is shown but not announced; see the screen page.

## Differences between iPhone, iPad and Mac

None in the flow. The sheet's chrome differs; see the screen page.

## Screenshots

None. This flow shares its id with the screen; the sheet's captures are listed on [screens/change-password](../screens/change-password.md). The error and retry states have no capture.

## Source files

- View: `Views/ChangePasswordView.swift` (`change()`, `retrySave()`, `show(_:)`, `finish()`).
- Model: `Model/PasswordOperations.swift` (`preparePasswordChange`, `savePasswordChange`, `recoverKey`).
- Core: `Sources/JournalCore/Crypto.swift` (`VaultCrypto.changePassword`, `PasswordChangeError` and its texts), `Sources/JournalCore/ServerClient.swift` (`changePassword`).
- Design: [sync-security-2026-09-24.md](../../../../docs/design/sync-security-2026-09-24.md).

## Open questions

See [open-questions.md](../../../open-questions.md).
