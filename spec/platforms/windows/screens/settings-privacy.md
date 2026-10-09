---
id: settings-privacy
title: Settings ▸ Privacy (Windows)
spec: screens/settings-privacy.md
features: [encryption-status, turn-on-encryption, change-password, sync-recovery, app-lock, mac-inactivity-lock, lock-now]
status: draft
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
  - https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingsexpander
---

# Settings ▸ Privacy (Windows)

Encryption status and its next step, and App Lock with Windows Hello. Behaviour and copy keys are the spec's [Settings ▸ Privacy](../../../screens/settings-privacy.md); App Lock itself (when it locks, what counts as use, the results of the Windows Hello prompt) is in [flows/app-lock](../flows/app-lock.md), which this page links to rather than repeats. The shell and patterns are in [settings](settings.md#card-patterns).

## Controls

Page title: breadcrumb "Settings > Privacy". With no library (Settings opened from the welcome page) the page shows nothing, as in the spec, and Back returns to the welcome page; just after erasing, Settings closes by itself and the window shows the first-launch page.

### Encryption group

Header `settings.privacy.encryption.header`. One `SettingsCard`:

| Part | Content |
| --- | --- |
| `Header` | `settings.privacy.encryption.on` (icon ShieldLock F5B4) or `settings.privacy.encryption.off` (no icon) |
| `Description` | Encrypted: `settings.privacy.encryption.footerOn`, the credential's name in lower case. Sign in offered: `messages.encryption.turnedOnElsewhere`. Not encrypted: `common.unencryptedWarning` |
| Trailing `Button`, the first that applies | Encrypted with a master password: `settings.privacy.changePassword` ([change-password](change-password.md)). Not encrypted and the server's journals are now encrypted: `common.reconnect`, accent (opens the Connect task page at signing in: [flows/reconnect-to-server](../../../flows/reconnect-to-server.md)). Not encrypted: `settings.privacy.encryption.turnOn` ([turn-on-encryption](turn-on-encryption.md)). Libraries from early versions (recovery key) show no button |

While encryption is being turned on, `settings.privacy.encryption.turnOn` reopens the task page where the work is; the page is the only place the work shows ([flows/turn-on-encryption](../flows/turn-on-encryption.md)). Not enabled while the library is being replaced, except to show a run in progress.

### App lock group

Header `settings.privacy.appLock.header`. One `SettingsExpander`:

| Part | Content |
| --- | --- |
| Header | `settings.privacy.appLock.require` with the method "Windows Hello" (`library.lock.method.*` has one Windows name, [platform.md, 12.3](../platform.md#123-vocabulary)); icon Lock (E72E) |
| `Description` | The footer, below |
| Header's `Content` | A `ToggleSwitch`. While Windows Hello is being asked it shows the requested value and is disabled |
| Expanded item 1 | A choice card: `settings.privacy.appLock.inactive`, a `ComboBox`: `settings.privacy.appLock.inactive.minutes` for 5, 15 and 30, `settings.privacy.appLock.inactive.hours` for 1, `common.never`, in that order with Never last. A stored time that is not one of these (from another version) is added in its place. Default 30; stored per library |
| Expanded item 2 | An action card: `common.lockMyJournal`, icon Lock. Saves what is open, navigates the window back to the library, and locks ([flows/app-lock](../flows/app-lock.md)) |

Both items are always shown. While App Lock is off they are disabled (`IsEnabled` false) and the description explains that they apply when App Lock is on; the expander stays an expander and never swaps to a plain card (Microsoft's guidance: show the same settings regardless of context and disable with an explanation; a swap loses focus, makes Narrator re-announce and makes the page jump). It expands by itself when App Lock is turned on.

**Footer, the first that applies** (the Windows Hello state is read when the page appears, when the window is activated and after every prompt):

| State | Footer | Switch |
| --- | --- | --- |
| Windows Hello available | `settings.privacy.appLock.footer` with who "Windows Hello" and, while App Lock is on, `settings.privacy.appLock.footerInactive` (a time chosen) or `settings.privacy.appLock.footerSleepOnly` (Never), each starting with a space | Enabled |
| Not set up for this account | The Windows variant of `settings.privacy.appLock.noPasscode` (B32), then a `HyperlinkButton` that opens Sign-in options (`ms-settings:signinoptions`) | Disabled while off. While on (Hello was removed) it stays enabled so App Lock can be turned off; App Lock is paused meanwhile and a bar in the window says so ([flows/app-lock](../flows/app-lock.md), D42) |
| Turned off by an organization's policy | A new string (B32) | As above |
| No Windows Hello device found, busy, or unknown | `settings.privacy.appLock.unavailable` (this PC, B32) | As above |

### Screenshots and screen sharing

A third group follows App lock (draft default of D28): a switch card with a new header and description (B33), on by default **pending the accessibility spike** ([platform.md, 20](../platform.md#20-screen-capture-and-window-privacy): Windows Magnifier, Narrator and Quick Assist must still work with the window excluded, or the default becomes off). It sets the capture exclusion of every top-level window of the app; it applies at once and is saved on this device. It never governs the QR and check-code screens, which are always excluded while shown. If D28 chooses a fixed rule instead, the group is not built.

### Errors

A failed save of App Lock or of Lock when inactive shows `ContentDialog` with the spec's title (`settings.privacy.appLock.error.turnOn`, `settings.privacy.appLock.error.turnOff` or `settings.privacy.appLock.inactive.error`), message `settings.privacy.appLock.error.message`, Close `common.ok`; App Lock stays as it was, and the switch or combo box returns to its saved value. The specific title is kept (not dropped as `common.alertTitle` is, [8.1, rule 3](../platform.md#81-rules)).

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Groups in the column; the expander's items indented under the header | Mac Privacy tab |
| Small and text size 200% or more | The switch moves under the header text; the footer wraps | iPhone pushed pane |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `turn-on-encryption` | Button in the encryption card | — | Unlocked; not while the library is being replaced (except to show a run) |
| `change-password` | Button in the encryption card | — | Unlocked |
| `sync-reconnect` | Accent Sign in… button | — | Unlocked |
| `toggle-app-lock` | Switch in the expander header | — | Not while Windows Hello is being asked; turning on needs Windows Hello available; turning off is always possible |
| `set-inactivity-lock` | Combo box in the expander | — | App Lock on; not while Windows Hello is being asked |
| `lock-my-journal` | Action card; File menu | `Ctrl+L` (as in commands.md) | App Lock on |

Turning App Lock on or off asks Windows Hello with `settings.privacy.appLock.reason.turnOn` or `settings.privacy.appLock.reason.turnOff`; a longer Lock when inactive time, or Never, asks first with `settings.privacy.appLock.reason.change`; a shorter time saves at once ([flows/app-lock](../flows/app-lock.md), results and what each does). Cancelled or failed Windows Hello returns the control to its value and says nothing. A device that cannot authenticate turns App Lock off without asking.

## Copy differences

Sentence case applies ("App lock", "Lock when inactive", "Your journals are encrypted", "Encryption is off"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.lock.method.faceID`, `.touchID`, `.opticID`, `.passcode`, `.loginPassword` and `settings.privacy.appLock.require` | Face ID, Touch ID, …, "Require {method}" | One method, "Windows Hello": "Require Windows Hello" | vocabulary (platform.md, 12.3) |
| `library.lock.phrase.biometric`, `.touchID`, `.passcode`, `.loginPassword`, `library.lock.device.*` | "{method} or your {device} passcode", … | "Windows Hello" as {who}; `library.lock.device.*` not shown | vocabulary (platform.md, 12.3) |
| `settings.privacy.appLock.noPasscode` | {"default": "To use App Lock, set a passcode for this {device} in Settings.", "mac": …} | To use app lock, set up Windows Hello in Settings > Accounts > Sign-in options. | vocabulary, B32 |
| `settings.privacy.appLock.unavailable` | App Lock isn’t available on this device. | App lock isn’t available on this PC. | vocabulary, B32 |
| A new key for the policy state | none | App lock isn’t available because your organization turned off Windows Hello. | new, B32 |
| A new key for the link that opens Sign-in options | none | Open Sign-in options | new, B32 |
| New keys for the App lock is paused bar (a title and three reason messages) | none | In [copy-proposals.md](../copy-proposals.md) | new, B32, D42 |
| `settings.privacy.appLock.footerInactive`, `settings.privacy.appLock.footerSleepOnly` | …when your Mac sleeps or its screen locks. | …when this PC sleeps or is locked. | vocabulary, B28 |
| `settings.privacy.appLock.reason.turnOn`, `.turnOff`, `.change`, `.unlock` | {"default": "Turn on App Lock", "mac": "turn on App Lock"} | The default (capitalised) form, sentence case: "Turn on app lock" | vocabulary (platform.md, 12.3) |
| `settings.privacy.appLock.error.turnOn`, `.turnOff`, `settings.privacy.appLock.inactive.error` | Couldn’t Turn On App Lock, … | Couldn’t turn on app lock, … | casing |
| New switch card for capture (if D28 is approved) | none | see B33 | new |

## Accessibility

- The status text and its description are read from the card ("Your journals are encrypted, Keep your master password somewhere safe. It can’t be recovered."); its button is named by its label.
- The switch reads "Require Windows Hello, On, switch"; while disabled Narrator reads why through the description (the footer is the description). The footer's link is a link.
- When Windows Hello answers, focus returns to the switch (or the combo box). A cancelled prompt says nothing; a failed save is the error dialog.
- The expander's expanded state is announced by the control; turning App Lock on expands it and focus stays on the switch.
- Windows Security's own prompt is accessible by itself; the app does not draw a replacement.
- Contrast themes, 225% text and keyboard only: all controls are standard.

## Different by design

- **Windows Hello only.** Apple offers Face ID, Touch ID, Optic ID, the device passcode or the login password, and an app PIN was retired. Windows offers the one system prompt, Windows Hello (face, fingerprint or PIN), and a PC account with no Hello set up cannot turn App Lock on ([platform.md, 13](../platform.md#13-device-authentication-and-app-lock), D25). The footer says how to set Hello up and links to the Settings page.
- **Lock when inactive and the sleep and screen-lock triggers** exist on Windows as on the Mac, since a PC is a computer.
- **Footer states.** Windows has a policy-disabled state of its own, and an App Lock that pauses when Hello cannot be used (D42).
- **The App lock expander keeps its items, disabled, while off** instead of swapping to a plain card.
- **Lock My Journal** returns to the library before locking, because Settings is a page of the window the lock replaces.
- **Capture exclusion** (D28) has a switch, on by default pending the accessibility spike; the Apple app has no setting like it (its privacy cover protects the app switcher, which Windows does not have).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B32 (Windows Hello strings), B33 (capture switch strings), D42 (App lock when Windows Hello cannot be used), B28 (Apple names in sentences), D25 (Windows Hello and secret storage), D28 (privacy beyond the lock).
