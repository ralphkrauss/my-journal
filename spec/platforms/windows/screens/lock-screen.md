---
id: lock-screen
title: Lock screen and privacy cover (Windows)
spec: screens/lock-screen.md
features: [app-lock, privacy-cover, missing-device-key-unlock]
status: draft
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Lock screen and privacy cover (Windows)

What the window shows while My Journal is locked, what happens instead of the lock page when Windows Hello cannot be used, and why there is no cover when another window is in front. Behaviour and copy keys are the spec's [Lock screen and privacy cover](../../../screens/lock-screen.md); when it locks and the results of the Windows Hello prompt are in [flows/app-lock](../flows/app-lock.md), written together with [platform.md, 13, 14 and 20](../platform.md#13-device-authentication-and-app-lock).

## Controls

### The lock page

Locking replaces the window's content with a `Page` and releases the journal views, so UI Automation, Narrator and magnifiers cannot read journal content while locked. Every dialog and flyout is hidden with no result; the title bar stays, with the app icon, the name, one More button (Help and Exit) and the caption buttons: **the menu bar and the pane button are not shown**, because a row of disabled menus is noise and tells Narrator the app has content; the window title is `library.app.name`, as always. The previous page's `Frame` back stack is cleared on locking, not merely hidden. The page fills the window, content centred in a column at most 480 epx wide, in a `ScrollViewer` (it scrolls at large text sizes), on the normal window background (Mica falls back to solid, [21](../platform.md#21-theming-and-contrast)).

| Spec element | Control | Notes |
| --- | --- | --- |
| Lock symbol | `FontIcon` Lock (E72E), 48 epx, decorative | |
| Heading | `TextBlock` `common.myJournalIsLocked`, `TitleTextBlockStyle`, heading level 1 | |
| Error | `InfoBar` (Error), not closable, above the button: the app's error, or after a failed attempt `settings.lock.failed` | Read when it opens |
| Unlock with Windows Hello | An accent `Button` `settings.lock.unlockWith` ("Unlock with Windows Hello"), the page's default button; takes focus when the page appears; disabled while the prompt is open | Enter chooses it |
| App Lock moved from a PIN | Not shown (`settings.lock.pinRetired`): Windows never had an app PIN | |
| Use master password | A `HyperlinkButton` `settings.lock.useCredential`, after a failed attempt and when the journals have a password; {credential} is the library's (`common.masterPassword`, `library.lock.credential.recoveryKey`) | |

**Credential form** (the device key is unavailable, or Use master password was chosen): `PasswordBox`, `Header` the credential's name (`common.passwordOrRecoveryKey` when it is not known), `InputScope` Password, focused, with the built-in reveal button (the spec has no Show Password switch on the lock screen, [platform.md, 25](../platform.md#25-text-input-and-spelling)); an `InfoBar` for the error; an accent `Button` `settings.lock.unlock`, the default button, disabled while the field is empty (Enter in the field unlocks); and, when the PC can still use Windows Hello, a `HyperlinkButton` `settings.lock.useMethod` ("Use Windows Hello") that returns to the first state.

Errors, as the spec lists them: `messages.error.invalidRecoveryKey` (Error), `messages.library.deviceKeyUnavailable` (Warning: it explains why the password is asked), `messages.library.cannotOpen` (Error; Windows form below), or another error's own message. Unlocking with the password also tries the server's copy of the password when this PC's fails, accepting it only if it opens these journals; unlocking with the master password marks the password as checked; App Lock stays on after unlocking with the credential; the device key is saved again ([Missing device key](#missing-device-key)).

### Unlocking with Windows Hello

The page asks without a click once per lock, when the window is active and in the foreground; the Windows Security prompt can open behind an inactive app, so the request waits for `Window.Activated` and a foreground window ([platform.md, 13](../platform.md#13-device-authentication-and-app-lock)). The request is `UserConsentVerifierInterop.RequestVerificationForWindowAsync(hwnd, message)` with the library window's handle and the message `settings.privacy.appLock.reason.unlock` (capitalised). The results and what each does are the table in [flows/app-lock](../flows/app-lock.md); on this page:

- Verified: the journals open where they were.
- Cancelled: the lock page stays; the button asks again; nothing is said.
- Not set up for this account, no Windows Hello device, or turned off by policy: the lock page is not shown at all: App Lock pauses, the journals open and a warning bar explains (below, D42).
- Busy or retries exhausted (transient): `settings.lock.failed` and, with a password, Use master password.
- A success that answers an earlier lock is never applied after a new lock (each lock has a generation number; an answer carries the one it was asked for).
- Locking while a prompt is showing cancels it: the app cancels the pending request and, whatever the prompt does, ignores a late answer.
- After unlocking, focus moves to the journals (the entry list); after a cancel, it returns to the Unlock button. A notification event is not needed: Narrator follows focus ([platform.md, 11](../platform.md#11-progress-and-announcements)).

### App Lock is paused

If App Lock is on and Windows Hello is not set up for the account, not present (a Remote Desktop session is the common case: no biometrics, and the Hello PIN prompt is not guaranteed to work) or turned off by an organization's policy, a person with journals that have no password would have no way in. So App Lock **pauses**: at launch, at unlock and whenever a trigger would lock, the lock page is not shown, the journals open, and a persistent warning `InfoBar` ([flows/app-lock](../flows/app-lock.md), App Lock is paused) at the top of the library window says that App Lock is paused and why, with an Open Sign-in options link when the person can fix it. It resumes by itself when Hello is available again. It is an interface lock, not encryption, and an organisation policy should not be able to lock a person out of data on their own PC. The Apple behaviour (App Lock turns itself off with an alert) is not copied; `settings.lock.turnedOff.title`, `settings.lock.turnedOff.passcodeRemoved` and `settings.lock.turnedOff.pinRetired` are not shown on Windows. The alternative, a lock page that stays, is D42.

### Missing device key

The library's key is kept for this PC and user with the Windows Data Protection API behind `ISecretStore` ([platform.md, 14](../platform.md#14-secure-storage)). It is unusable, and the journals can only be opened with the password or recovery key, whether or not App Lock is on, after: restoring the profile or the app's data on another PC; resetting the account's password with an administrator tool; reinstalling Windows; a profile that was recreated; removing the app's data. This is more common on Windows than on Apple (PCs are replaced and reset more often), so it is a normal page, not an error screen:

- The page opens directly in the credential form, with `messages.library.deviceKeyUnavailable` (Warning) above the field; there is no Windows Hello button, because there is no key to unlock with.
- A wrong password shows `messages.error.invalidRecoveryKey`; the field is cleared and keeps focus.
- On success the key is protected and saved again through `ISecretStore` and the journals open. If the app cannot save it (the local folder is read-only or full) the journals still open for this session, a one-time Warning `InfoBar` says that the key could not be saved on this PC and that the password will be asked again at the next launch (so that launch is not a surprise), and the same page appears at the next launch; the spec does not say more (D43).
- The blob is never in Documents, a roaming profile or a OneDrive folder, and Erase removes it.

### No privacy cover

The Apple app covers the window whenever App Lock is on and the app is not active. The Windows app does not ([platform.md, 20](../platform.md#20-screen-capture-and-window-privacy), D28): Windows has no app-switcher snapshot, windows sit side by side and lose focus all day (snapped beside a document, on another monitor, behind a Windows Hello prompt for another app), and a cover would blank the journal at each of those moments, which nothing in Notepad, OneNote, Mail or Photos does. A topmost window the size of the library window would also sit over other apps. The protection comes from locking: on launch, Ctrl+L, the inactivity timer, Win+L, user switch, disconnect, display off, lid and sleep. This also removes the special cases a cover needed for the Windows Hello prompt, the Store rating dialog and the pickers.

**Capture.** The window follows the capture exclusion setting of the rest of the app (`SetWindowDisplayAffinity`, the flag and its accessibility check are in [platform.md, 20](../platform.md#20-screen-capture-and-window-privacy); D28): the lock page never appears in screenshots, screen sharing or Recall when it is on, and the person's own screenshots of the page are blocked too.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium, small | The same page, content centred, at most 480 epx wide; at small widths it fills the width with 24 epx margins | iPhone, iPad and Mac lock screens |
| Text size 200% or more | Scrolls; nothing is cut off | Accessibility sizes |

The page has no state to lose: layouts change under the lock page without effect.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `unlock-with-device` | Default button | `Enter` | Not while the prompt is open; Windows Hello available or not (a failure explains) |
| `use-credential` | Hyperlink | — | After a failed attempt, with a password |
| `unlock-with-credential` | Default button of the credential form | `Enter` | Field not empty |
| `use-device-unlock` | Hyperlink | — | The PC can still use Windows Hello |
| `lock-my-journal` | File menu while unlocked (not here) | `Ctrl+L` | Not while locked |

Win+L is the system lock and is not intercepted; it locks the library too ([flows/app-lock](../flows/app-lock.md)). Alt+F4 closes the window while locked; nothing is saved because nothing is unsaved.

## Copy differences

Sentence case applies ("My Journal is locked", "Use master password", "Unlock"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.lock.unlockWith` with `library.lock.method.*` | Unlock with {method} | Unlock with Windows Hello | vocabulary (platform.md, 12.3) |
| `library.lock.phrase.*`, `library.lock.device.*` | "{method} or your {device} passcode" | "Windows Hello"; device names not shown | vocabulary (platform.md, 12.3) |
| `settings.lock.pinRetired`, `settings.lock.turnedOff.pinRetired` | App Lock now uses… instead of a PIN. | Not shown | removed (platform.md, 12.3) |
| `settings.lock.turnedOff.title`, `settings.lock.turnedOff.passcodeRemoved` | App Lock Is Off; This {device} no longer has a passcode… | Not shown: App lock pauses instead of turning itself off (D42) | removed, B32 |
| New strings for App lock is paused: a title, three messages (Windows Hello not set up, not available right now, turned off by an organization) and the link Open Sign-in options | none | In [copy-proposals.md](../copy-proposals.md) | new, B32, D42 |
| New string for the one-time warning when the device key cannot be saved again | none | In [copy-proposals.md](../copy-proposals.md) | new, D43 |
| `messages.library.cannotOpen` | Your journals couldn’t be opened. Quit and reopen My Journal. | Your journals couldn’t be opened. Close My Journal and open it again. | vocabulary (platform.md, 12.3) |
| `settings.privacy.appLock.reason.unlock` | {"default": "Unlock your journals", "mac": …} | The default form | vocabulary (platform.md, 12.3) |
| `messages.library.deviceKeyUnavailable` | Your device key is unavailable. Use your recovery key to unlock your journals. | Your device key is unavailable. Use your master password to unlock your journals. | vocabulary, B35 |

## Accessibility

- The heading is level 1; the problem message is announced when its bar opens. The page is the window's only content: the journal views do not exist while it is up, so Narrator's scan mode finds only the heading, the message and the controls.
- Focus: the Unlock button on appearance; the credential form's field in credential mode; the entry list after unlocking; the Unlock button after a cancelled prompt. Tab order: message, field, check box, buttons, links.
- The prompt itself is Windows Security's and accessible by itself.
- The window title reads "My Journal" always. The App lock is paused bar is a Warning `InfoBar`, read when it opens (a changed reason closes it and opens a new one).
- Contrast themes: the page uses theme brushes; the lock icon has the foreground brush.
- 225% text: the page scrolls and stays centred.

## Different by design

- **Windows Hello only, one name.** Apple names Face ID, Touch ID, Optic ID, Passcode or Login Password; Windows names Windows Hello, which offers face, fingerprint or PIN in its own prompt. There is no app PIN and no password fallback in the app itself: the credential form is for the journals' password, not for the Windows password.
- **A page, not an overlay,** so assistive technology cannot reach the journals ([platform.md, 13](../platform.md#13-device-authentication-and-app-lock)).
- **No cover on deactivation.** Reason: Desktop windows lose focus constantly and sit side by side; see No privacy cover above.
- **App Lock pauses instead of locking a person out** when Windows Hello cannot be used (D42), and instead of turning itself off with an alert as on Apple.
- **Device key unavailable is first-class** ([Missing device key](#missing-device-key)).
- **No grace after Win+L** beyond the spec: the session lock locks the library, and the window asks again on return. After signing in to Windows the person proves identity a second time; this known cost is D54.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B32 (Windows Hello strings), D42 (App lock when Windows Hello cannot be used), D43 (device key that cannot be saved again), D54 (a second prompt after Win+L), B35 (device key wording), D25 (Windows Hello and secret storage), D28 (privacy beyond the lock).
