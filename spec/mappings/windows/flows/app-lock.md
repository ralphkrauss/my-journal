---
id: app-lock
title: App Lock (Windows)
spec: flows/app-lock.md
features: [app-lock, mac-inactivity-lock, lock-now]
status: draft
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
  - https://learn.microsoft.com/en-us/windows/win32/api/wtsapi32/nf-wtsapi32-wtsregistersessionnotification
  - https://learn.microsoft.com/en-us/windows/win32/power/wm-powerbroadcast
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerpowersettingnotification
---

# App Lock (Windows)

Keeps the journals out of sight on a shared or unattended PC, using only Windows Hello. It changes nothing about how the journals are encrypted. Behaviour and copy keys are the spec's [App Lock](../../../flows/app-lock.md); the screens are [settings-privacy](../screens/settings-privacy.md) and [lock-screen](../screens/lock-screen.md); conventions are [platform.md, 13](../platform.md#13-device-authentication-and-app-lock), [14](../platform.md#14-secure-storage) and [20](../platform.md#20-screen-capture-and-window-privacy). This file owns the Windows Hello table that every authentication on Windows uses. Windows 11 (build 22000 or later) is required because the desktop Windows Hello call needs it.

## Controls

### The Windows Hello gate

One interface, `IDeviceOwnerAuthenticator`, with three members (the Windows counterpart of the Apple `DeviceOwnerAuthenticating`): `Availability()`, `AuthenticateAsync(reason)` and `Cancel()`. It is the only code that calls `UserConsentVerifier`; pages call the gate ([settings](../screens/settings.md)). The desktop form is used: `UserConsentVerifierInterop.RequestVerificationForWindowAsync(hwnd, message)` with the library window's handle ([Retrieve a window handle](https://learn.microsoft.com/en-us/windows/apps/develop/ui-input/retrieve-hwnd)); a call to `RequestVerificationAsync` does not work from a desktop window.

**Availability** (`CheckAvailabilityAsync`, read when a page that needs it appears, when the window is activated, and before every request):

| System answer | Gate says | Meaning |
| --- | --- | --- |
| Available | Available | Windows Hello (face, fingerprint or PIN) can be used. The method is always named "Windows Hello" |
| NotConfiguredForUser | NotSetUp | This account has no Hello PIN or biometric. A Hello PIN can be created on any account, with or without biometric hardware |
| DisabledByPolicy | Policy | An organization turned the prompt off |
| DeviceNotPresent | Unavailable | Nothing to ask now (a remote session is the common case) |
| DeviceBusy, anything else | Busy | Transient: try again |

**Result of a request** and what each caller does:

| System result | Gate says | Turn on App Lock | Turn off, longer inactivity time, Add device, Export as Markdown, Erase | Unlock |
| --- | --- | --- | --- | --- |
| Verified | Success | Saves | Continues | Opens the journals |
| Canceled | Cancelled | Switch returns; nothing said | Nothing happens; nothing said | Lock page stays; Unlock asks again |
| NotConfiguredForUser | NoPasscode | Cannot turn on: footer says how to set Hello up | Continues without authentication (turning off needs none) | **App Lock pauses**: no lock page, the journals open, the paused bar explains (below, D42) |
| DisabledByPolicy, DeviceNotPresent | Cannot | Cannot turn on: footers in [settings-privacy](../screens/settings-privacy.md) | Continues without authentication, as the spec's rule "a device without a passcode continues" | **App Lock pauses**, as above |
| RetriesExhausted, DeviceBusy, anything else | Failed | Switch returns; nothing said | Nothing happens; nothing said (Add device stays on its confirmation) | `settings.lock.failed` and Use master password when there is a password |

Reasons are the spec's reason keys in their capitalised form: `settings.privacy.appLock.reason.turnOn`, `settings.privacy.appLock.reason.turnOff`, `settings.privacy.appLock.reason.change`, `settings.privacy.appLock.reason.unlock`, `settings.addDevice.authReason`, `settings.backup.markdownReason`, `settings.backup.markdownReasonUnencrypted`, `settings.erase.authReason`, `settings.passwordCheck.authReason`. The reason is the prompt's message.

**Rules of the gate.**

- A request is made only while the library window is active and in the foreground; the Windows Security prompt can open behind an inactive app, so the call waits for activation.
- One request at a time; a second call while one is open does nothing.
- While a request is open the window is deactivated by the prompt. The gate sets a flag so that the inactivity timer is held and `Window.Activated` does not start a second automatic prompt; the flag stays set for half a second after the prompt closes (the Apple "or while its panel closes"). There is no cover to suppress: the Windows app does not cover its window on deactivation ([platform.md, 20](../platform.md#20-screen-capture-and-window-privacy)).
- `Cancel()` cancels the pending asynchronous operation. Whether that closes the prompt on screen is checked in a spike; whatever the prompt does, the result of a cancelled or superseded request is ignored, and each request carries a generation number so that "a success that answers an earlier lock is never applied after a new lock".
- The library's key is never used to decide anything here: App Lock is a lock of the interface ([platform.md, 13](../platform.md#13-device-authentication-and-app-lock)), and the gate returns only a yes or a no.
- The app never shows its own PIN or password prompt for App Lock, and never asks for the Windows account password (`CredUIPromptForWindowsCredentials` would give the app the typed password, which the spec's "only the system's authentication" rule avoids).

### Turning App Lock on and off

Steps 1 to 3 of the spec's "Turning App Lock on" use the gate: the switch is available only when the gate says Available; the request uses `settings.privacy.appLock.reason.turnOn`; Success saves; a failed save shows the error dialog in [settings-privacy](../screens/settings-privacy.md). Turning off asks with `settings.privacy.appLock.reason.turnOff`, or continues without a request when Hello is not set up, off by policy or not present. The old app PIN does not exist on Windows, so the spec's "Moving from the old app PIN" is not applicable.

### App Lock is paused

If Windows Hello is removed, turned off by policy or not available (a Remote Desktop session) while App Lock is on, App Lock **pauses** rather than locking the person out or silently turning itself off (D42, the review's recommendation): at launch, at unlock and whenever a trigger would lock, the gate's availability is read first; when it is NotSetUp, Policy or Unavailable the library does not lock, the journals open, and a Warning `InfoBar` at the top of the library window, not closable and shown on every page of the window while the state lasts, says that App Lock is paused (a new title string, settings ▸ privacy.appLock.paused.title, B32) with the reason message and, for NotSetUp, the link Open Sign-in options (B32). The setting stays on. The bar closes and App Lock resumes by itself when the gate says Available again (read when the window is activated and before every trigger); the next trigger then locks normally. A person who wants App Lock off turns it off in Settings > Privacy, which needs no authentication in these states. The transient result Busy keeps the lock page with Try again. This replaces the Apple behaviour (turn itself off, then the App Lock is off alert, which is not shown on Windows). The alternative is the lock page that stays, which can lock someone out of a journal without a password; a refinement is to pause only when the journals have no password, because with one the lock page offers it (D42).

### When it locks

| Trigger | Windows mechanism |
| --- | --- |
| Launch | Always when App Lock is on, before any journal is read |
| Lock My Journal | File menu, Ctrl+L, Settings > Privacy. Settings and any page of the window are left first, so after unlocking the library shows where it was |
| Lock when inactive: 5, 15 or 30 minutes, 1 hour, Never (default 30, stored per library) | The inactivity timer below |
| The display turns off, the lid closes, the PC sleeps | `RegisterPowerSettingNotification` for `GUID_CONSOLE_DISPLAY_STATE` (lock when the display turns off, not when it comes back) and `GUID_LIDSWITCH_STATE_CHANGE`; `WM_POWERBROADCAST` suspend; a heartbeat is only the backstop (below) |
| The screen locks (Win+L), the user is switched, the session disconnects | `WM_WTSSESSION_CHANGE` through `WTSRegisterSessionNotification` for this session: lock, switch away, console or remote disconnect |
| The window loses focus | Does not lock, and nothing covers the window ([lock-screen](../screens/lock-screen.md), [platform.md, 20](../platform.md#20-screen-capture-and-window-privacy)) |

**Modern Standby.** Most new laptops go into Modern Standby when the lid closes, and Windows sends no suspend message there; the app is also throttled, so a timer cannot be the trigger. The triggers are **display and lid notifications**: `RegisterPowerSettingNotification` for `GUID_CONSOLE_DISPLAY_STATE` (the library locks when the display turns off, so it is already locked before the person returns, not on resume) and `GUID_LIDSWITCH_STATE_CHANGE`, plus `WM_WTSSESSION_CHANGE` for the session. A heartbeat every 15 seconds stays only as a **backstop**: a gap of more than a minute between two beats means the PC slept, and the library locks at once on the first beat after waking, before the window is shown to input. Win+L already fires the session lock on a normally configured laptop. All of these are checked in a spike. The cost of a missed trigger is that the library stays unlocked until the timer or the next launch.

After Win+L and signing in again the app is locked, and the person is asked once more, with Windows Hello. This is the spec's rule (a screen lock locks) applied as written; the person has just proved who they are to Windows, so this is a known cost, and an option to skip the second prompt after a session lock is D54.

### What counts as use, and the timer

Input to My Journal's own windows resets the timer: key presses and modifier keys, mouse and pen clicks and drags, the wheel and touchpad gestures, touch, pointer movement only while the window is active, opening a menu, edits in the editor (including voice typing with Win+H, dictation and Narrator editing) and choosing another entry. Syncing does not count. Input is observed at the window level (a subclass of the window procedure, or the content island's input sources), never with a global keyboard or mouse hook and never from the system-wide idle time, so other apps do not count either way. A spike checks that popups, flyouts and dialogs report their input. Any input after the time has passed locks instead of acting (the first key or click is consumed).

The time is held while the person's own long action runs: connecting, importing, turning on encryption, exporting, adding a device, merging journals, and while the Windows Security prompt is open. It starts again when the action ends. The clock keeps counting while the PC sleeps (the wall clock decides); changing the setting counts from the moment of the change; a longer time or Never asks first with `settings.privacy.appLock.reason.change`.

### Locking

1. Writing in the open entry and in open dialogs is saved first, for about two seconds at most ([flows/save-entry](save-entry.md)).
2. The library locks: the content is replaced by the lock page, the journal views are released, dialogs and flyouts hide with no result, and each page's locking rule runs (an export is cancelled and its temporary copy removed; the Connect page cancels as Cancel does; a waiting pairing request is declined; encryption continues once the server is being updated).
3. Whatever could not be saved in step 1 is saved after locking, without showing journal content.

### Unlocking

See [lock-screen](../screens/lock-screen.md). Once per lock, when the window is active, the gate is asked without a click.

### Other places Windows Hello is asked

When App Lock is on, the device owner authenticates before Export as Markdown and Erase journals and settings. Adding a device always asks, whether or not App Lock is on. A PC without Windows Hello continues without it in each of these (the table above). Forgot password also asks, but it is the exception: the link is offered only when Windows Hello is available, as the spec requires that the device can authenticate its owner, so a PC without Hello never shows it.

## Layout at each window width

Not applicable: App Lock has no layout of its own. The lock page and the settings are in their files; the lock follows the window at every width.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `toggle-app-lock` | Switch in Settings > Privacy | — | See [settings-privacy](../screens/settings-privacy.md) |
| `set-inactivity-lock` | Combo box in Settings > Privacy | — | App Lock on |
| `lock-my-journal` | File menu; Settings > Privacy | `Ctrl+L` | App Lock on. The editor's own Ctrl+L is turned off ([platform.md, 7](../platform.md#7-keyboard-shortcuts)) |

## Copy differences

Sentence case applies, with the Windows Hello vocabulary of [platform.md, 12.3](../platform.md#123-vocabulary) for every `library.lock.*`, `settings.lock.*` and `settings.privacy.appLock.*` key; the keys themselves are listed in the two screen files, not repeated here. `settings.lock.pinRetired`, `settings.lock.turnedOff.pinRetired`, `settings.lock.turnedOff.title` and `settings.lock.turnedOff.passcodeRemoved` are not shown (App Lock pauses instead of turning itself off). New strings for the paused bar (a title, three reason messages and the Open Sign-in options link) are in [copy-proposals.md](../copy-proposals.md) (B32, D42).

## Accessibility

- The prompt is Windows Security's and is accessible by itself; the app does not draw one. Focus: after a request closes, focus returns to the control that asked; after unlocking, to the journals; after a cancel, to Unlock.
- Locking is not announced (the lock page appears with its heading; Narrator reads the new page). Failures and the App Lock is paused bar are `InfoBar`s that Narrator reads when they open.
- Nothing in the lock timer is announced; no sound.

## Different by design

- **Locks on session lock, user switch, display off, lid, sleep and disconnect, not on losing focus,** as on the Mac. On Windows display and lid notifications cover Modern Standby, which the Mac has no counterpart for; a heartbeat is only the backstop.
- **App Lock pauses when Windows Hello cannot be used** instead of turning itself off with an alert (Apple) or locking the person out (D42).
- **Lock when inactive exists on Windows** (the Mac's feature for a computer), observed at window level, not through a global hook.
- **One method name and no password fallback in the app**; a PC with no Hello cannot use App Lock (D25), and the journals' own password is the only way in when the device key is gone.
- **Moving from the old PIN is not applicable.**
- **Cancelling a request is best effort** (a spike), so late answers are discarded by generation number.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B32 (Windows Hello strings), D42 (App lock when Windows Hello cannot be used), D54 (a second prompt after Win+L), D25 (Windows Hello and secret storage).
