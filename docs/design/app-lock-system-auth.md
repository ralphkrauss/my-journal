# App Lock with the device's own authentication

Status: approved with required changes by an independent design review, 2026-09-30 (see “Review outcome”); implemented. Supersedes the PIN parts of [app-lock-accessibility.md](app-lock-accessibility.md), [owner-decisions-2026-09-25.md](owner-decisions-2026-09-25.md) §9 (App Lock sheet) and the unlock-copy item P2-5 of [feedback-stabilization-2026-09-23.md](feedback-stabilization-2026-09-23.md). [missing-device-key-unlock.md](missing-device-key-unlock.md) still applies, with the changes in "Device key unavailable" below.

## Owner decision

> "app lock is ridiculous, it should simply work with the existing biometrics or pincode, not with another custom pin code"

App Lock uses only the system's device owner authentication: `LAPolicy.deviceOwnerAuthentication`. That means Face ID, Touch ID or Optic ID, with the iPhone or iPad passcode or the Mac login password as the fallback. On the Mac, the system also tries a paired Apple Watch at the same time. The app has no PIN of its own anywhere.

## What exists today (and what goes)

- `LocalConfiguration` stores `pinSalt`, `pinHash` (a key-derivation verifier of the PIN), `useBiometrics`, `failedUnlocks` and `unlockRetryAfter`. App Lock is "on" when `pinHash != nil`.
- `AppLockSheet` turns App Lock on, changes the PIN and turns it off. Settings > Privacy shows Turn On App Lock…, Unlock with Face ID, Change PIN…, Turn Off App Lock… and Lock My Journal.
- `UnlockView` shows a PIN field, **Unlock**, **Use Face ID**, and either **Use Master Password** (recovery credential) or **Unlock with This Device** (`deviceOwnerAuthentication`, for libraries without a password).
- Triggers: launch; on iPhone and iPad, entering the background (`lockImmediately()` in `JournalApp.saveAndLock`), with `PrivacyCover` covering every window while inactive; on the Mac, `com.apple.screenIsLocked`, App ▸ Lock My Journal (⌃⌘L), and Settings ▸ Privacy ▸ Lock My Journal. There is no timeout setting.

**Is anything wrapped with the PIN?** No. The vault key is a Keychain item (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `Keychain.swift`) that the PIN never touches. It is recoverable from the recovery envelope with the master password or recovery key. The PIN only produced a verifier in `configuration.json`, and `unlock(pin:)` compared against it. Server credentials, agent grants, archives and the local server don't use the PIN either (`grep pinHash` finds only the configuration, App Lock code, `ServerJoining` copying the settings, and tests). Removing the PIN therefore can't cost anyone access to data. It also removes a short-PIN verifier that anyone with a backup of `configuration.json` could brute-force (SECURITY.md, "App Lock").

Removed: the PIN, Change PIN, the PIN sheet, the attempt delay, and the separate "Unlock with Face ID" switch. A switch that only allows biometrics duplicates a system setting, which the HIG advises against ([Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts): "avoid offering an app-specific setting for opting in to biometric authentication").

## Model

- `LocalConfiguration.appLock: Bool?` (nil or false means off). The legacy fields stay decodable, only so that they can be migrated and then cleared (see Migration).
- `DeviceOwnerAuthentication` (a small type in `DeviceAuthentication.swift`, injectable for tests):
  - `availability() -> Availability`: `.available(Method)`, `.noPasscode` (`LAError.passcodeNotSet`), or `.unavailable` (any other `canEvaluatePolicy(.deviceOwnerAuthentication)` failure).
  - `Method` names what the person will be asked for. It includes biometrics only when `canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` succeeds, or fails with `biometryLockout` (the system then asks for the passcode, but Face ID is still the method this device uses):
    - iOS: **Face ID**, **Touch ID**, **Optic ID**, otherwise **Passcode**. When the person has denied Face ID to My Journal, or has no face or finger enrolled, the method is Passcode.
    - macOS: **Touch ID**, otherwise **Login Password**. Apple Watch is never named; the system dialog offers it on its own.
    - The name comes from `biometryType`, so it stays stable. Passcode or Login Password replaces it only when no face or finger is enrolled, or when Face ID is denied to My Journal. It is not replaced when Touch ID is only temporarily unavailable, for example with the lid closed or the keyboard unplugged.
  - `authenticate(reason:) async -> Outcome`: `.success`, `.cancelled` (userCancel, systemCancel, appCancel, userFallback), `.noPasscode`, or `.failed`.
  - A test build can replace it: `#if DEBUG` only, through the environment variable `JOURNAL_UI_TEST_DEVICE_AUTH` (`success`, `cancel`, `noPasscode`, `unavailable`). Release builds contain no bypass.
- Each check uses a new `LAContext`. `evaluatedPolicyDomainState` is not tracked. Anyone who knows the passcode can already unlock, and can also enroll a new face or finger, so a biometric-enrollment check would add nothing.
- The vault key is **not** bound to App Lock (no `SecAccessControl` with `.userPresence`). App Lock stays a gate on the interface, as documented. Binding the key would make the data depend on the passcode: iOS deletes `WhenPasscodeSet` items when the passcode is removed.

## Settings ▸ Privacy ▸ App Lock

This is one section in the existing Privacy form (Mac Settings tab, iOS Settings ▸ Privacy). The header is **App Lock**.

Rows when App Lock can be used:

1. A switch named for the method, using the words of iOS's own app locking ([Lock or hide an app on iPhone](https://support.apple.com/guide/iphone/lock-or-hide-an-app-iph00f208d05/ios): "Require Face ID (or Touch ID or Passcode)"):
   - **Require Face ID** / **Require Touch ID** / **Require Optic ID** / **Require Passcode** (iOS)
   - **Require Touch ID** / **Require Login Password** (Mac)
2. **Lock My Journal**, a button shown only while the switch is on (unchanged; locks now and closes Settings on iOS).

Footer, one variant each:

- iOS with biometrics: "Face ID or your iPhone passcode is needed to open My Journal. App Lock doesn’t change how your journals are encrypted." (use "iPad" on iPad, and Touch ID or Optic ID as appropriate)
- iOS without biometrics: "Your iPhone passcode is needed to open My Journal. App Lock doesn’t change how your journals are encrypted."
- Mac with Touch ID: "Touch ID or your login password is needed to open My Journal. App Lock doesn’t change how your journals are encrypted."
- Mac without Touch ID: "Your login password is needed to open My Journal. App Lock doesn’t change how your journals are encrypted."

**Turning it on.** This is allowed only when `availability()` is `.available` at that moment. Flipping the switch on asks the system right away. The reason is "Turn on App Lock" on iOS, and "turn on App Lock" on the Mac, where the dialog reads "My Journal is trying to …". The switch shows on while the dialog is up.
- Success: `appLock = true` is saved. The app stays unlocked, since the person just authenticated.
- Cancel: the switch returns to off, with no message.
- Saving fails: the switch returns to off, and an alert appears: **Couldn’t Turn On App Lock** / "Try again." / **OK**.
- Authentication runs first, which also means the Face ID permission prompt ("Unlock your journals and confirm adding a device.") appears at the moment the person chooses to use Face ID.

**Turning it off.** This also asks first: "Turn off App Lock" / "turn off App Lock". iOS's own "Don’t Require Face ID" does the same. It stops someone who finds the app open from switching the lock off for later. Cancel leaves it on. A failed save shows **Couldn’t Turn Off App Lock** / "Try again."

**No passcode or login password** (`.noPasscode`): the switch is shown off and disabled (`Require Passcode` / `Require Login Password`), and there is no Lock My Journal button. Footer:
- iOS: "To use App Lock, set a passcode for this iPhone in Settings." ("iPad" on iPad)
- Mac: "To use App Lock, set a login password for your Mac user in System Settings."

**Privacy cover.** While the app's own authentication request is showing, the cover is not shown when the app becomes inactive. On iPhone and iPad it also stays hidden after the answer until the app is active again, while the system's panel closes (see "Unlock timing"). It is still shown when the app enters the background.

**Other unavailability** (`.unavailable`, for example a restricted device): the switch is disabled. Footer: "App Lock isn’t available on this device."

Availability and the method are read again when Settings appears and when the app becomes active, so returning from the system Settings after setting a passcode enables the switch.

## Lock triggers (unchanged apart from the condition)

`appLock == true` replaces `pinHash != nil` everywhere: `load()`, `lockImmediately()`, the SwiftUI `LockedCover` overlay, `PrivacyCover`, the Lock My Journal menu command, and the Settings button.

- Launch: the app always opens locked.
- iOS and iPadOS: it locks as soon as it enters the background. While it's inactive or in the app switcher, `PrivacyCover` shows the cover ("My Journal Is Locked") over every window. The system's own authentication dialog makes the scene inactive but not backgrounded, so it can't cause a relock loop.
- Mac: it locks when the screen locks, and with App ▸ Lock My Journal (⌃⌘L) or Settings ▸ Privacy ▸ Lock My Journal.
- There is no timeout or grace period. None exists today, and iOS's own app locking has none. Writing is saved first, as now (`saveWhileLocked`). Agents can't read while the app is locked, as now.

## Unlock screen

This replaces the PIN layout inside the existing `UnlockView` scroll container (the Dynamic Type layout from app-lock-accessibility.md is kept). Centered, top to bottom:

1. The `lock` symbol, large, secondary colour, hidden from VoiceOver.
2. **My Journal Is Locked** (title2, a header trait for VoiceOver).
3. An error line, only when there is one (callout, red, wraps).
4. One button, `.borderedProminent`, the default action (Return on the Mac and on iPad with a keyboard): **Unlock with Face ID** / **Unlock with Touch ID** / **Unlock with Optic ID** / **Unlock with Passcode** / **Unlock with Login Password**. The HIG asks apps to name the method ("Sign In with Face ID", not "Sign In").
5. For people who used a PIN, one line under the button until they first unlock: "App Lock now uses Face ID or your passcode instead of a PIN." (the variant matches the footer's method words; Mac: "Touch ID or your login password"). Callout, secondary.

6. **Use ‹credential name›** (for example **Use Master Password**), a plain accent link. It appears only after an outcome other than a cancel, or when App Lock is on but device authentication is unavailable. It opens the existing credential form (`unlockWithRecovery`), and **Use Face ID** (the method name) returns. Recovery keeps App Lock on. A library without a password has no credential, so it shows only the button.

There are no PIN fields and no **Unlock with This Device**.

**Automatic prompt.** The reason is "Unlock your journals" / "unlock your journals". The system asks at most once per lock, and only while the app is active:
- iOS: at launch and on return from the background. Locking with Lock My Journal doesn't prompt, because Face ID would unlock again at once.
- Mac: only at launch, or when the app first becomes active after launch. After a relock (screen lock, ⌃⌘L, Settings), the default button waits for a click or Return.

If the person cancels, there is no second automatic prompt until the next lock. The button asks again. Only one request runs at a time, and the button is disabled while one is showing. A request made while the app wasn't active (`LAError.notInteractive`) is retried the next time the app becomes active.

**Outcomes:**
- Success: unlocks, with the existing session checks and revalidation after refresh (the same guards as `biometricUnlock`, from missing-device-key-unlock.md). The success is applied only if the lock counter hasn't changed and the app is active, or, on iPhone and iPad, inactive only since the request made it so (see "Unlock timing"). Any other success that arrives while the app is inactive waits for it to become active again, and is dropped if a lock happens first.
- The model keeps the request's `LAContext` and calls `invalidate()` on `lockImmediately()`, which also covers entering the background, the Mac screen lock and ⌃⌘L.
- Cancelled: stays locked, with no message. VoiceOver focus moves to the Unlock button.
- Failed or unavailable: "My Journal couldn’t be unlocked. Try again." is announced, and the button stays.
- No passcode: see the next section.

### The passcode was removed while App Lock is on

Removing the passcode on iPhone or iPad needs the passcode, and removing a Mac login password needs that password. Only the device owner can get the device into this state. Apple Notes lets you keep opening notes locked with the device passcode after you remove it ([Lock notes on iPhone or iPad](https://support.apple.com/102537)). My Journal does the same, rather than locking the person out:

1. Just before asking, check `availability()` once, with the app active, and require `.noPasscode`. Any other error keeps it locked.
2. Save `appLock = false`, then unlock. If the save fails, unlock anyway for this session. The next launch runs the same check.
3. Show a one-time alert:
   - **App Lock Is Off**
   - "This iPhone no longer has a passcode. To use App Lock again, set a passcode, then turn on App Lock in Settings ▸ Privacy." (Mac: "Your Mac user no longer has a login password. To use App Lock again, set a login password, then turn on App Lock in Settings ▸ Privacy.")
   - **OK**

### Device key unavailable

This case isn't App Lock (missing-device-key-unlock.md): the Keychain key is gone and the journals can only be opened with the recovery credential. `UnlockView` then shows the existing credential form directly:
- the `credentialName` secure field;
- **Unlock**;
- the error "Your device key is unavailable. Use your recovery key to unlock your journals."

There is no Use PIN toggle, and no system prompt, because it can't open anything. Unlike today, a successful recovery **keeps App Lock on**. It used to clear the PIN in case it was forgotten, and the system passcode can't be forgotten in the same way. The app unlocks at once, because the recovery credential is stronger than device authentication.

### Unlock timing (2026-10-02)

Owner report: after Face ID succeeded, "My Journal Is Locked" stayed on screen for one to two seconds.

Measured in a Release build on an iPhone 17 simulator with simulated Face ID and 300 entries with photos (four returns from the background, two launches): the system reported the success while its Face ID panel was still closing, and the app became active again 1.23–1.25 s later. The success waited for that, and meanwhile the full-window cover showed "My Journal Is Locked", because the request was no longer showing but the app was still inactive. Reading the Keychain key, opening the store and reading the journals afterwards took 2 ms, 6–90 ms and 60–220 ms; no key is derived when the device key exists.

- **Applying the success.** On iPhone and iPad, the app notes when the system's request makes it inactive (the resign-active that arrives while the request is showing). Until the app is next active or enters the background, a success is applied at once: the lock screen goes away and the journals are read behind the closing panel. iOS can't say why an app stays inactive, so this also covers Control Center, Notification Center or the app switcher opened while the panel closes. That is accepted: the person authenticated less than a second earlier. Entering the background locks again (the lock counter changes), and the cover window is added in the did-enter-background handler, before the system takes its snapshot, so a success after leaving the app never unlocks.
- **Mac unchanged.** A Mac window stays visible behind the app the person switched to, so a success still waits until My Journal is active.
- **Cover.** The cover stays hidden while the request makes the app inactive, before and after the answer. After a cancel or a failure the lock screen, with its Unlock button, stays visible instead of the cover.
- **Loading.** From the unlock until the journals have been read (a fraction of a second), the entry list and the editor area show no empty state: no "No Entries", "New Journal…" or "New Entry", which would be wrong and could be tapped. The list is blank under its usual title and toolbar, with no spinner, text or animation. This also applies after unlocking with the recovery credential, and a library that really is empty shows its empty state once read. If reading fails, the existing error alert appears.
- **VoiceOver.** The system panel has VoiceOver's focus while it closes, so a screen-changed notification is posted when the app becomes active after such an unlock.
- No copy changes.

Review: an independent design review approved this with required changes, all applied above: state the trade-off of the inactive window; set the flag only in the resign-active handler while a request is showing and clear it on activation and in the background; keep the Mac's rule; use an explicit reading flag, not empty lists; post screen-changed on activation. Its concern about focusing the editor while inactive doesn't apply: restoring the remembered entry on iPhone pushes it without bringing up the keyboard. Automatic sync starting during the panel is ordinary background work.

### Locking the iPhone with My Journal open (2026-10-03)

Owner report: “When I lock the phone while the My Journal app is open, the Face ID is being triggered on the home screen.”

Reproduced on the iPhone 17 simulator (iOS 26.5) with the side button (`XCUIDevice` `pressLockButton`) and temporary lifecycle tracing. Within about 20 ms: the scene deactivated, the app entered the background, `scenePhase` became `.background` and the app locked with the automatic prompt pending; the lock screen's view appeared in the background and asked for Face ID. The app's “active” flag was still set, because the resign-active notification reaches the model through an asynchronous hop and arrived about 130 ms later. On a phone, Face ID then shows over the Lock Screen and, as the person is looking at it, succeeds and unlocks the journal in the background, so returning to the app shows the journal without asking. Pressing Home or using the app switcher didn't show it: there, resign-active arrives well before the background. The order varies between runs (one of two runs on the simulator).

Fix: entering the background marks the app inactive before it locks (`applicationEnteredBackground`), whatever order the notifications arrive in. The prompt waits for the app to become active again, as on return from the Home Screen. No interface or copy change. `AppLockTests.testLockingTheDeviceAsksOnlyOnceTheAppIsInFrontAgain` feeds the model a device lock's order of events; a UI test couldn't show the problem reliably, because the order depends on timing.

## Migration of PIN users

This runs in `load()`, after decoding and before anything is shown. `locked` is already true at that point.

1. If `pinHash != nil` and `appLock == nil`: set `appLock = true` and `pinRetiredNotice = true`, and set `pinSalt`, `pinHash`, `useBiometrics`, `failedUnlocks` and `unlockRetryAfter` to nil. Save once, atomically (`persistConfiguration`, `.atomic`).
2. If the save fails: keep the migrated state in memory (locked, system authentication) and log without details. The legacy fields on disk migrate again at the next launch. It never fails open.
3. The app opens locked with the new unlock screen and the notice line.
   - If the device has a passcode, App Lock stays on and the notice clears after the first successful unlock.
   - If it has no passcode, the unlock attempt takes the path above, with the alert text: **App Lock Is Off** / "App Lock now uses your iPhone passcode instead of a PIN. This iPhone doesn’t have a passcode, so App Lock is off." (Mac: "…uses your login password… Your Mac user doesn’t have a login password…").

   The owner accepted this trade-off: a device without a passcode loses the PIN's protection.
4. No journal data, Keychain item or recovery envelope is touched. A configuration without a PIN is unchanged, and App Lock stays off.

`ServerJoining` (new library after joining) and archive import carry over `appLock` instead of the PIN fields.

## Accessibility

- Settings uses a standard `Toggle`, whose label names the method. A disabled switch keeps its explanatory footer, which VoiceOver reads.
- Unlock screen:
  - At appearance, VoiceOver focus goes to the title. The system dialog handles its own accessibility.
  - Error text is announced (`JournalAccessibility.announce`), as are the alerts.
  - Full Keyboard Access and Tab reach the button, and Return activates it.
  - The symbol is decorative.
- Dynamic Type up to AX5 wraps text with no truncation, inside the existing scroll view. Nothing animates beyond the system transitions, so Reduce Motion is respected. Increased contrast and Reduce Transparency: only system colours and materials (`.background`, `.secondary`, `.tint`, `.red`).
- Face ID starts scanning immediately (Apple's sample notes this), which is why the automatic prompt appears only when the app is active and the lock screen is what the person sees. With VoiceOver on, the automatic prompt still appears. The system dialog is accessible, and iOS's app lock behaves the same.

## Copy summary

| Place | Text |
| --- | --- |
| Section header | App Lock |
| Switch | Require Face ID · Require Touch ID · Require Optic ID · Require Passcode · Require Login Password |
| Footer (on or off) | "Face ID or your iPhone passcode is needed to open My Journal. App Lock doesn’t change how your journals are encrypted." (variants above) |
| Footer (no passcode) | "To use App Lock, set a passcode for this iPhone in Settings." · Mac: "To use App Lock, set a login password for your Mac user in System Settings." |
| Footer (unavailable) | "App Lock isn’t available on this device." |
| Button | Lock My Journal |
| System reasons | "Unlock your journals" · "Turn on App Lock" · "Turn off App Lock" (lowercase first letter on the Mac) |
| Lock screen | My Journal Is Locked · Unlock with Face ID (etc.) |
| Lock screen error | My Journal couldn’t be unlocked. Try again. |
| PIN notice | App Lock now uses Face ID or your passcode instead of a PIN. |
| Alerts | Couldn’t Turn On App Lock / Couldn’t Turn Off App Lock: "Try again." · App Lock Is Off (texts above) |

## Documentation to update with the implementation

- docs/guide/app-lock.md (rewrite) and docs/guide/troubleshooting.md: remove "I forgot my App Lock PIN" and add "My iPhone no longer has a passcode".
- docs/guide/README.md, README.md: the feature line and the Privacy screenshot alt text. The iPhone screenshot `02-privacy.jpg` shows the old switch; it needs a new capture, which is flagged for the owner.
- PRIVACY.md, SECURITY.md (drop the PIN-verifier paragraph and say App Lock uses the device passcode), docs/architecture.md, CHANGELOG.md.
- design/README.md: this record, marked as amending app-lock-accessibility.md.

## Tests (behaviour only)

- **Migration:** a legacy configuration with a PIN opens locked with `appLock == true`, and no PIN field is left on disk. If saving fails, it stays locked and migrates again on relaunch. A configuration without a PIN stays off.
- **Unlock with a fake authenticator:**
  - success unlocks;
  - cancel stays locked with no error;
  - `.noPasscode` turns App Lock off, unlocks and flags the notice;
  - an unavailable result stays locked;
  - the existing stale-session and missing-key guards still hold (these replace PINRetryTests and the PIN cases in AppLockTests).
- **Turn on and off:** both need authentication. Cancelling or a failed save leaves the setting as it was, and turning either way while locked is refused.
- **Recovery with a missing device key** keeps App Lock on.
- **Existing lifecycle tests** (Move, History, Conflict, Archive, StaleDraft, LocalServer) switch from `unlock(pin:)` to a test helper that unlocks through the fake authenticator.
- **One iOS UI test**, replacing the PIN flow in AppLockUITests, with `JOURNAL_UI_TEST_DEVICE_AUTH`:
  - locking from Settings shows the cover and the lock screen;
  - cancel keeps it locked;
  - the button unlocks and the entry is intact;
  - relaunch is locked again.
- Checked by hand on hardware, not automated: real Face ID and Touch ID, and the Mac password dialog.

## Files

- Changed: LocalConfiguration, AppModel (load, lockImmediately, unlockWithRecovery), AppLockOperations (rewritten), DeviceAuthentication (rewritten), PrivacyCover, JournalApp, AppCommands, SettingsView, ServerJoining, and the tests and docs listed above.
- New: `Views/UnlockView.swift` (moved out of RootView) and `Views/AppLockSettings.swift`.
- Removed with the owner's approval: `Views/AppLockSheet.swift` and `JournalTests/PINRetryTests.swift`. Both were backed up to the session scratchpad first.
- UI tests that recover a seeded library now wait for the Recovery Key field directly, because a missing device key shows the credential form without a **Use Recovery Key** step.

## Review outcome

An independent design review approved the design with required changes, and no further review round was needed. The reviewer confirmed that nothing is encrypted with the PIN. Everything below has been applied in the sections above.

1. **No permanent lockout.** After any outcome other than a cancel, and whenever App Lock is on but authentication is unavailable, the lock screen offers **Use ‹credential name›**. Recovery keeps App Lock on.
2. **A stale success can't unlock.** The request's `LAContext` is invalidated on every lock. A success is applied only if the lock counter is unchanged and the app is active (on iPhone and iPad, also while the request's own panel closes; see "Unlock timing"), and model tests cover a success that arrives after a relock.
3. **Mac prompts.** The Mac prompts automatically only at launch. The "journal window is key" condition was dropped.
4. **Stable method names.** Names come from `biometryType`, with Passcode or Login Password only when nothing is enrolled or Face ID is denied to My Journal. On the Mac the wording is "Require Login Password" and "Unlock with Login Password".
5. **Turning on** requires `.available` at that moment.

Answers to the open questions:
- The passcode having been removed turns App Lock off, after one check made while the app is active.
- The Mac doesn't prompt automatically after a relock.
- The labels stay "Require Face ID" and the other method names.

Also adopted from the optional suggestions:
- The privacy cover is skipped on deactivation during the app's own request.
- The footer copy now reads "App Lock doesn’t change how your journals are encrypted."
- A test checks that turning on is refused without a passcode.

Implementation, after the review: libraries without a password have no credential to fall back to, so if device authentication is unavailable they keep only the Unlock button. This was the case before too, since their only unlock was device authentication.
