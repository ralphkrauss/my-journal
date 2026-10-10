---
id: app-lock
title: App Lock (Apple)
spec: flows/app-lock.md
features: [app-lock, mac-inactivity-lock, lock-now]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/AppLockSettings.swift
  - apps/apple/JournalApp/Views/InactivityLockSettings.swift
  - apps/apple/JournalApp/Views/UnlockView.swift
  - apps/apple/JournalApp/Model/AppLockOperations.swift
  - apps/apple/JournalApp/Model/DeviceAuthentication.swift
  - apps/apple/JournalApp/Model/InactivityLock.swift
  - apps/apple/JournalApp/Model/LockSaving.swift
  - apps/apple/JournalApp/Model/PrivacyCover.swift
  - apps/apple/JournalApp/Model/WindowSafety.swift
  - apps/apple/JournalApp/AppCommands.swift
  - apps/apple/JournalApp/JournalApp.swift
  - docs/design/app-lock-system-auth.md
  - docs/design/mac-inactivity-lock-2026-10-03.md
---

# App Lock (Apple)

Implements [flows/app-lock](../../../flows/app-lock.md). The lock screen and privacy cover are on [screens/lock-screen](../screens/lock-screen.md), with its captures. The views hold the English text as literals; the copy keys named here are the spec's. Conventions: [platform.md](../platform.md#13-device-authentication-and-app-lock).

## Controls

**Settings ▸ Privacy ▸ App Lock** is `AppLockSettingsSection` (`Views/AppLockSettings.swift`), a `Section` in the Privacy `Form` (`.formStyle(.grouped)`) with header `settings.privacy.appLock.header` and a footer chosen by `DeviceOwnerAvailability`:

- A `Toggle` titled `settings.privacy.appLock.require` with `{method}` from `DeviceUnlockMethod.name`. Its binding reads `requested ?? model.appLockOn`; setting it calls `change(_:)`, which holds the requested value in `@State requested` while the system asks, so the switch shows the new position until the answer arrives. It is `.disabled(requested != nil || (!usable && !model.appLockOn))`: turning off stays possible without a passcode, turning on needs `.available`.
- Mac only, while App Lock is on: `InactivityLockPicker` (`Views/InactivityLockSettings.swift`), a `Picker` titled `settings.privacy.appLock.inactive` with the choices 5, 15, 30 and 60 minutes and Never (`common.never`), the stored time added if it is not one of them; item texts "For 5 minutes" and "For 1 hour" follow `settings.privacy.appLock.inactive.minutes` and `.hours`. It uses the same `requested` pattern and is disabled while a request is pending.
- While App Lock is on: a `Button` `common.lockMyJournal`, which runs `model.lock()` and then the section's `locked` closure; Settings passes `dismiss()`, so Settings closes.
- Footers: `settings.privacy.appLock.footer` (the sentence starts with the method's phrase, capital first letter, plus `AppModel.automaticLockSentence`, which is empty on iPhone and iPad and, on the Mac with App Lock on, `settings.privacy.appLock.footerInactive` or `settings.privacy.appLock.footerSleepOnly`); `settings.privacy.appLock.noPasscode` (Mac variant: login password in System Settings; iOS: passcode of "this iPhone" or "this iPad"); `settings.privacy.appLock.unavailable`.
- Alerts: `.alert(item:)` with the titles `settings.privacy.appLock.error.turnOn` or `settings.privacy.appLock.error.turnOff`, message `settings.privacy.appLock.error.message`, when the change could not be saved; the picker has its own alert `settings.privacy.appLock.inactive.error`. `AppLockChange.cancelled`, `.unavailable` say nothing.

**Turning on or off.** `AppModel.setAppLock(_:)` (`Model/AppLockOperations.swift`) refuses while locked or already authenticating, re-reads availability, and for "on" requires `.available`. It asks `SystemDeviceOwner.authenticate` (`LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)`) with `settings.privacy.appLock.reason.turnOn` or `.turnOff` (first letter lowercased on the Mac), discards the answer if a lock happened meanwhile, treats `.noPasscode` as success only when turning off, and saves `configuration.appLock` (true or nil) and clears `pinRetiredNotice` through `saveAppLock`, which keeps the previous setting if the write fails. App Lock is stored in the local configuration and not synced.

**Locking.**

- `AppModel.lock()`: when App Lock is on and unlocked, `saveBeforeLocking(within: .seconds(2))` (`Model/LockSaving.swift`) saves the open entry and typed content in open sheets (`savesBeforeLocking` closures), skipped while a mutation is committing or the library is being replaced; then `lockImmediately()`; then `saveWhileLocked()`. `lockImmediately` cancels a showing authentication request, bumps `unlockState.lockCount`, clears the journals from memory (`items`, the conflict ids and `keptNotes`, the image cache, the search query, derived lists), clears a sensitive pasteboard item and stops agent copies. It returns false, and nothing locks, when there is no App Lock or the library has a problem.
- Launch: `finishOpening()` sets `locked = appLockOn` and `promptPending`.
- iPhone and iPad: `JournalApp.saveAndLock()` runs when `scenePhase` becomes `.background`: `applicationEnteredBackground()` locks at once (no save first; `lockImmediately(prompting: true)` so the system is asked when the app returns) and `BackgroundActivity.run("Save and lock")` saves afterwards under a background task. On the Mac the same phase change only flushes writing.
- Lock My Journal: Settings button, and on the Mac the menu item in `AppCommands.swift` (`CommandGroup(before: .systemServices)`, `.keyboardShortcut("l", modifiers: [.command, .control])`, `.disabled(!model.appLockOn)`).
- Mac only, `InactivityLock` (`Model/InactivityLock.swift`, started by `startInactivityLock()` in `JournalApp.swift`): `interval` is the stored minutes (`configuration.inactivityLockMinutes`, nil means 30, 0 means Never) while App Lock is on and unlocked. An `NSEvent.addLocalMonitorForEvents` monitor records the time of key, modifier, mouse down and drag, scroll, magnify, rotate and swipe events and of mouse movement while the app is active, and `AppModel.noteUse()` records use that does not arrive as an event (dictation, VoiceOver editing, choosing another entry); opening a menu counts (`NSMenu.didBeginTrackingNotification`). Input after the deadline is discarded (the monitor returns nil) and starts the lock. One scheduled wake-up (`Task.sleep(until:tolerance:clock:)` on the continuous clock, 5 s tolerance) waits for the deadline and reschedules if there was input; the deadline is also checked on wake from sleep, on becoming active and on a window occlusion change. `NSWorkspace.willSleepNotification` and `sessionDidResignActiveNotification` (user switching) lock at once, whatever the time setting. The screen lock is observed elsewhere: `ApplicationDelegate` (`Model/WindowSafety.swift`) listens for the distributed notification `com.apple.screenIsLocked` and calls `model.lock()`. Locking goes through `model.lock()`.
- The time is held while `vaultReplacement`, `committingMutation`, `connectingToServer` or a join phase is set, and while a sheet applies `.keepsUnlockedWhile(...)` (archive export and import, Markdown export, the connection flow, Add Device while waiting, journal merge).
- Longer time or Never: `setInactivityLock(minutes:)` asks `settings.privacy.appLock.reason.change` first (skipped when the device has no passcode); a shorter time does not ask. A changed setting counts from the moment it changes.

**Unlocking.** `unlockWithDevice()` (details on the lock screen page): success calls `finishDeviceUnlock`, which clears `locked`, reads the journals and selects an entry; a success that arrives while the app is inactive waits in `pendingSuccess` and is applied when it becomes active, unless a lock happened meanwhile (`lockCount`). `noPasscode` runs `turnOffWithoutPasscode`: App Lock off, `unlockState.turnedOff` set (`passcodeRemoved`, or `pinRetired` when `pinRetiredNotice` is set), journals open, and the alert from `AppLockTurnedOffAlert` appears.

**Moving from the old PIN.** `retireAppLockPIN()` (called from `LibraryOpening`) removes the PIN's salt, hash, biometrics flag and attempt counters; if a PIN existed and App Lock was not already set it sets `appLock = true` and `pinRetiredNotice = true`. A failed save is logged and the next launch repeats it.

**Other places App Lock asks** (`AppModel.checkDeviceOwner`, `authenticateDeviceOwner`): Export as Markdown (every time App Lock is on); Erase Journals and Settings; restoring an archive onto a library that has no store while App Lock is on (`installArchive`); Add Device always. The spec lists only the Markdown and Erase cases.

## Layout

- **iPhone, iPad.** The App Lock section is in the Privacy page of the Settings sheet; no inactivity picker.
- **Mac.** In the Privacy tab of the Settings window, 560 points wide; the picker sits between the switch and Lock My Journal; the menu item is in the application menu below Settings….
- **Dynamic Type.** Standard `Form` behaviour.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `toggle-app-lock` | as in [commands.md](../commands.md) | none | not while a request is pending; on needs authentication available |
| `set-inactivity-lock` | as in commands.md | none | Mac only, App Lock on, not while a request is pending |
| `lock-my-journal` | as in commands.md | Control-Command-L on the Mac (menu item) | App Lock is on |
| `unlock-with-device` | as in commands.md | Return on the Mac | locked, not authenticating |

## Copy differences

- `settings.privacy.appLock.reason.turnOn`, `.turnOff` and `.change` have Mac variants (lower case); the code lowercases the first letter on the Mac through `AppModel.authenticationReason`.
- `settings.privacy.appLock.noPasscode` has a Mac variant; the iOS text names the device ("this iPhone" or "this iPad").
- `settings.lock.turnedOff.*` have Mac variants (see [screens/lock-screen](../screens/lock-screen.md)).
- Reasons of the other prompts that go through `checkDeviceOwner`: `settings.erase.authReason` and `settings.backup.markdownReason` have `mac` variants (lower case), which is what the Mac produces by lowercasing the first letter in `authenticationReason`. `settings.archiveImport.restoreReason` ("Restore journals on this device") is also a literal in code with a `mac` variant in the catalog.

## Accessibility

- The switch announces its own state as a `Toggle`; no custom label beyond the title with the method name.
- After a lock, the lock screen takes over the window; VoiceOver behaviour is on [screens/lock-screen](../screens/lock-screen.md).
- Failed saves are alerts, which VoiceOver announces natively.

## Differences between iPhone, iPad and Mac

- Locking on leaving the screen, the prompt after returning and the background save task are iOS only, because only iOS suspends the app.
- Lock when inactive, on sleep, on screen lock and on user switching, and the menu item with its shortcut, are Mac only, because the Mac window stays visible while the person is away.
- The authentication reason is lower case on the Mac because the system builds a sentence around it.

## Screenshots

None. The flow's screens are the lock screen (captured, see [screens/lock-screen](../screens/lock-screen.md)) and the Settings ▸ Privacy page, which belongs to the Settings pages; no capture shows the App Lock section on its own.

## Source files

- View: `Views/AppLockSettings.swift` (section, switch, Lock My Journal, alerts), `Views/InactivityLockSettings.swift` (picker, `keepsUnlockedWhile`, `automaticLockSentence`), `Views/UnlockView.swift` (lock screen, turned-off alert), `AppCommands.swift` (menu item), `JournalApp.swift` (scene phase, cover).
- Model: `Model/AppLockOperations.swift` (`setAppLock`, `lock`, unlock, PIN retirement, application activity), `Model/DeviceAuthentication.swift`, `Model/InactivityLock.swift`, `Model/LockSaving.swift`, `Model/PrivacyCover.swift`, `Model/WindowSafety.swift` (Mac screen lock), `Model/LibraryOpening.swift` (launch lock).
- Core: none specific.
- Design: [app-lock-system-auth.md](../../../../docs/design/app-lock-system-auth.md), [mac-inactivity-lock-2026-10-03.md](../../../../docs/design/mac-inactivity-lock-2026-10-03.md).

## Open questions

See [open-questions.md](../../../open-questions.md).
