# Mac: lock after inactivity

Status: reviewed 2026-10-03, approved with required changes, all applied (see "Review outcome"). Amends [app-lock-system-auth.md](app-lock-system-auth.md), which said "There is no timeout or grace period."

## Owner request

> "Check that the Mac locks automatically after a while: when the app is idle for a while (like 30 minutes by default, make it configurable) the journal should automatically go into lock."

## What exists today (checked in the code at 3bd25c8 plus the uncommitted tree)

There is one lock: **App Lock** (`LocalConfiguration.appLock`, Settings ▸ Privacy ▸ App Lock ▸ Require Touch ID / Require Login Password). It uses only the system's device owner authentication. A library's master password is not a separate lock. It is only the fallback credential on the lock screen when device authentication fails or the device key is missing (`UnlockView`). `lockImmediately()` does nothing unless `appLockOn`, so a library without App Lock never locks.

What locks the Mac today:

| Trigger | Locks? | Evidence |
| --- | --- | --- |
| Launch | Yes, when App Lock is on | `AppModel.load()`: `locked = appLockOn` |
| Screen lock | Yes | `ApplicationDelegate.applicationDidFinishLaunching` observes `com.apple.screenIsLocked` and calls `model.lock()` (Model/WindowSafety.swift) |
| App ▸ Lock My Journal (⌃⌘L), Settings ▸ Privacy ▸ Lock My Journal | Yes | AppCommands.swift, Views/AppLockSettings.swift |
| Inactivity | **No** | No idle timer, event monitor or idle measurement exists anywhere in the app |
| System sleep | **No**, unless the screen locks with it | `NSWorkspace.willSleepNotification` is observed only by sync (SyncSchedule.swift, `.sleep` for the change watcher). Whether sleep locks depends on the Mac's "Require password after screen saver begins or display is turned off" setting |
| App deactivated, hidden or windows closed | **No** | `applicationResignedActive()` only records `applicationActive = false`. On the Mac, `JournalApp.saveAndLock()` only saves when the scene goes to the background |

iPhone and iPad lock as soon as the app enters the background (`JournalApp.saveAndLock()` → `lockImmediately(prompting: true)`), with `PrivacyCover` while inactive. **No iOS setting exists for a delay** (nothing like "Require Face ID: Immediately / After 1 minute"). Locking work on iOS is owned by another task at the same time and is not changed here.

## Design

### What "inactive" means

My Journal is inactive when the person hasn't used it for the chosen time. That is measured from the last input to any of its windows (the journal window, Settings, sheets and alerts), whether My Journal is in front or not. Someone who leaves My Journal open behind another app for 30 minutes therefore finds it locked.

What counts as use:
- keyboard input, clicks, scrolling and trackpad gestures in My Journal's windows. Clicking or scrolling in My Journal's window while another app is in front counts. Moving the pointer over it doesn't: pointer movement counts only while My Journal is the active app;
- opening a menu in the menu bar while My Journal is active;
- edits to the open entry that arrive without a key press, such as Dictation and Voice Control (`AppModel.updateDraft`, which only the editor's user-edit path calls; changes from sync go through `followStoredDraft`);
- choosing an entry, which also covers VoiceOver and Voice Control, whose actions aren't keyboard or mouse events.

What doesn't count: syncing, a remote device changing the open entry, the local server, input in other apps, and VoiceOver reading aloud on its own (Read All).

**Input after the deadline locks.** The wake-up at the deadline can run late: App Nap throttles timers for a hidden app, and the Mac may have slept. If the first input after the deadline arrives before the wake-up has run, it doesn't postpone anything. It locks, and the input itself is discarded, so that key or click never acts on the journal. The same check runs when My Journal becomes active, when the Mac wakes and when a window becomes visible again. From the moment the lock starts until the lock screen shows, input is discarded.

**An action in progress holds the time.** My Journal doesn't lock for inactivity while an action the person started is still running, because watching a progress indicator involves no input. These hold it:
- adding a device while its code is shown or a device is answering (at most 10 minutes);
- connecting to a server, or joining one and merging journals;
- importing an archive, and preparing one for export (not while the save dialog waits);
- Merge Into…, Move, Change Date and Restore while being committed;
- turning on encryption;
- setting up this Mac as the server.

When the action ends, the time starts again. Sleep, screen lock and ⌃⌘L still lock at once, as today.

### Sleep, screen lock and switching users

When App Lock is on, My Journal also locks when the Mac goes to sleep (`NSWorkspace.willSleepNotification`) and when the person switches to another user (`sessionDidResignActiveNotification`), whatever the inactivity setting, including Never. Both are new. Screen lock keeps locking as today. These are system events where the person has clearly stepped away, and the guide already promises that someone who sits down at the Mac can't read the journals. Display sleep alone doesn't lock: it is covered by the screen lock when the Mac requires a password, and otherwise by the inactivity time.

### The setting

Mac Settings ▸ Privacy ▸ App Lock, a standard pop-up `Picker` between the switch and Lock My Journal. It is shown only while App Lock is on, like Lock My Journal: without App Lock there is nothing to lock with.

```
App Lock
  Require Touch ID                                  [on]
  Lock when inactive                 [For 30 minutes ⌄]
  Lock My Journal
  Touch ID or your login password is needed to open My Journal. It also locks when you
  haven’t used it for the time you choose, and when your Mac sleeps or its screen
  locks. App Lock doesn’t change how your journals are encrypted.
```

- **Label:** "Lock when inactive" (sentence case, like the Mac's other Settings labels, for example "Default journal").
- **Options:** For 5 minutes · For 15 minutes · For 30 minutes · For 1 hour · Never. The wording and "Never" follow macOS System Settings ▸ Lock Screen ("Start Screen Saver when inactive: For 20 minutes"). There's no one-minute choice: it would interrupt pauses for thought. A stored value that isn't in the list, for example from a later version, is kept and shown as an extra item ("For 2 hours").
- **Default:** For 30 minutes. This applies to existing App Lock users too, because nothing is stored until a choice is made.
- **Footer (Mac, App Lock on):** as shown above. With Never: "Touch ID or your login password is needed to open My Journal. It also locks when your Mac sleeps or its screen locks. App Lock doesn’t change how your journals are encrypted." The other footers (App Lock off, no login password, unavailable) are unchanged.
- **Changing it** takes effect at once and counts from the change. A **longer time or Never** weakens the lock, so it asks for authentication like turning App Lock off: "My Journal is trying to change App Lock settings." While the system asks, the pop-up shows the new choice. Cancelling puts it back with no message. A shorter time needs nothing. Without a login password there's nothing to ask, as when turning App Lock off.
- **Saving:** the choice is stored per device and per library in `configuration.json` (`LocalConfiguration.inactivityLockMinutes`: absent means 30 minutes, 0 means Never), like App Lock itself, and carried over wherever App Lock is (joining a server). It isn't synced: devices differ, and iOS has no such setting. It isn't kept in UserDefaults either, because a development build with a test library shares the installed app's defaults, while `configuration.json` belongs to the library. If saving fails, the pop-up returns to the previous choice and an alert says **Couldn’t Change Setting** / "Try again.", like the App Lock switch's alerts.
- **Plain library without App Lock** (with or without a master password): no pop-up, no timer, no event monitor, and nothing changes.

### iPhone and iPad

No setting. iOS locks as soon as My Journal leaves the screen, and the iPhone's own Auto-Lock sends it there when the device is idle. An iPad left awake in front with Auto-Lock set to Never stays unlocked. This is listed as an owner decision below and isn't built now.

### Locking without losing writing

When the time is up:

1. Writing still open is saved, for at most 2 seconds, so a stuck save can't keep the journals unlocked:
   - the open entry (`flush()`). Typing is already saved on every edit, so this normally only waits for a save in progress. On the Mac, text being composed with an input method is already part of the entry: the editor reads the text storage, marked text included, on every change;
   - typed but unsaved image descriptions in an open Image Descriptions sheet, saved as Done would save them. Without this the lock would drop them, because the sheet clears its fields when the journals lock.
2. It locks exactly like ⌃⌘L (`lock()`): the lock screen replaces the journals, and anything not yet stored is saved again and then sent to the server.

If a save fails or takes longer, it still locks: protecting the journals matters more than keeping them on screen. The entry's unsaved writing stays in memory (the lock never clears the open draft), the save is retried right after locking, and the lock screen shows the existing "Couldn’t save your changes. Unlock My Journal to try again." After unlocking, the existing save-failure alert offers Try Again. The entry's writing is never discarded.

Every lock the person or the system starts while the journals are open takes the same steps: Lock My Journal (⌃⌘L and Settings), the screen locking, sleep, switching users and inactivity all go through `lock()`, which saves first (`saveBeforeLocking`, at most 2 seconds), then locks. Descriptions the sheet couldn't save first, including when iPhone and iPad lock at once on leaving the app, are kept in memory (`UnsavedImageDescriptions`). They are saved after the next unlock while their entry is open; otherwise the sheet shows them again the next time it opens for that entry, still to be saved with Done. While an action is being committed or the library is being replaced, a lock is still immediate and cancels it, as before; the open entry is saved right after locking. Sleep and screen lock now lock up to 2 seconds later than before. The screen lock covers the window meanwhile, and a lock that the Mac's sleep interrupts finishes on waking.

### Sheets, panels, menus and alerts

The same as every lock today (RootView and RootView+MacWindow clear their presentations on `locked`):
- sheets, popovers and alerts in the journal window close: Move, Change Date, Version History, Image Descriptions, Rename, New Journal, templates, Link, the archive open panel and image import;
- the Settings window stays open and shows "Unlock My Journal to open Settings.";
- an open menu stays open, and its journal commands become disabled;
- the system's own Touch ID or password request is cancelled.

Text typed into one of those sheets, for example a half-typed journal name or link, isn't kept. That's the case for every lock today. Only the entry's writing and image descriptions are saved first.

A modal "Couldn’t save changes on this Mac." alert from closing the window stays up. It shows no journal content, and the window behind it locks.

### Accessibility

- The pop-up is a standard `Picker` with a visible label. VoiceOver reads "Lock when inactive, For 30 minutes, pop-up button", and Full Keyboard Access and Tab reach it.
- On locking, the existing lock screen appears. It puts VoiceOver focus on "My Journal Is Locked" and reaches **Unlock with Touch ID** from the keyboard (Return).
- No new motion, colour, transparency or text-size behaviour. Only system controls are used.
- VoiceOver and Voice Control actions aren't keyboard or mouse events, so only their edits and entry choices count. Someone reading one entry with VoiceOver for longer than the chosen time is locked. For 1 hour or Never avoids that.

### Implementation

- **`Model/InactivityLock.swift`** (Mac only), a `@MainActor` controller owned by `AppModel` (`inactivityLock`):
  - Watches input with one local `NSEvent` monitor (key down, flags changed, mouse down, moved and dragged, scroll wheel and gestures) and with `NSMenu.didBeginTrackingNotification`. An event only records the time of the input: no timer is rescheduled per event, so mouse movement costs one clock read.
  - One wake-up is scheduled for the deadline (last input + interval) on the continuous clock, which keeps counting during sleep, with a few seconds' tolerance. When it fires, it locks if the interval has passed since the last input. Otherwise it schedules one wake-up for the new deadline. While the person is active it wakes at most once per interval. There's no polling.
  - It is armed only while App Lock is on, the journals are unlocked and the setting isn't Never. It follows `locked`, `configuration` and the actions in progress (the model's `vaultReplacement`, `committingMutation`, `connectingToServer` and `joinPhase`, plus holds that sheets register). Arming, a changed interval and the end of an action all count from that moment. When it is disarmed, the monitor and the wake-up are removed.
  - Observes sleep, switching users, becoming active, waking and window visibility, as described above.
  - The clock and wake-ups are injected (`InactivityClock`), so tests control time.
- **Views:** a `keepsUnlockedWhile(_:)` modifier for the sheets that run actions (Add Device, Connect, Archive Import/Export, Merge Into…, Use This Mac as Your Server). Image Descriptions registers its save for the pre-lock step. On iOS both do nothing.
- Started once after launch on the Mac (JournalApp's Mac launch block), never in the process that hosts unit tests.
- Debug builds only: the `JOURNAL_UI_TEST_INACTIVITY_LOCK_SECONDS` launch variable replaces the chosen interval (unless Never), so the real app can be checked in seconds. Release builds ignore it.

### Tests (behaviour only)

With an injected clock and a real isolated library with App Lock on and a test authenticator:
- it locks once the interval has passed with no input, and not before;
- input before the deadline postpones the lock to a full interval after that input;
- input after the deadline, before the late wake-up runs, locks instead of postponing;
- Never doesn't lock;
- a changed setting takes effect at once and counts from the change;
- a longer time or Never needs authentication, cancelling keeps the old time, and a shorter time doesn't ask;
- an action in progress holds the lock, and the time starts again when it ends;
- pointer movement counts only while My Journal is active;
- unsaved writing in the open entry is stored before the lock, and the stored entry has it;
- the choice survives joining a server, if an existing join test can check it cheaply.

Checked by hand on the Mac: a Debug build signed with the team's development identity, a scratch library and the short test interval. Screenshots of the setting and of the locked window.

## Copy summary

| Place | Text |
| --- | --- |
| Pop-up label | Lock when inactive |
| Options | For 5 minutes · For 15 minutes · For 30 minutes · For 1 hour · Never (plus "For N minutes/hours" for an unlisted stored value) |
| Footer (Mac, App Lock on) | Touch ID or your login password is needed to open My Journal. It also locks when you haven’t used it for the time you choose, and when your Mac sleeps or its screen locks. App Lock doesn’t change how your journals are encrypted. |
| Footer (Mac, Never) | … It also locks when your Mac sleeps or its screen locks. … |
| System reason | Change App Lock settings ("My Journal is trying to change App Lock settings.") |
| Save failure alert | Couldn’t Change Setting · "Try again." |
| Lock screen | unchanged |

## Documentation

docs/guide/app-lock.md, "When My Journal locks", Mac bullet: "On the Mac, when you haven’t used My Journal for 30 minutes, or the time you choose in Settings > Privacy > Lock when inactive. Using other apps doesn’t count. Also when your Mac sleeps or its screen locks, or when you choose My Journal > **Lock My Journal** (⌃⌘L)." design/README.md: this record.

## Decisions for the owner

1. An iPad (or an iPhone with Auto-Lock set to Never) left open in front never locks by itself. Should iOS get the same setting? It isn't proposed now, because iOS already locks on leaving the app.
2. Lock on system sleep whatever the setting (proposed and built), or only through the screen lock as before. If the Mac also asks for its password after sleep, waking means two authentications: the Mac login, then Unlock with Touch ID.
3. The choices are 5, 15 and 30 minutes, 1 hour and Never. The owner may want a longer one, such as 4 hours.

## Review outcome

An independent design review approved the first version with required changes. All of them are applied above, and the reviewer said no re-review was needed if they were applied as described.

Required:
1. **R1, overdue input:** input that arrives after the deadline, before the late wake-up, locks and is discarded. The same check runs on becoming active, waking and window visibility.
2. **R2, actions in progress:** running actions hold the lock (listed above). The time restarts when they end.
3. **R3, weakening needs authentication:** a longer time or Never asks with "Change App Lock settings". A shorter time doesn't ask.
4. **R4, passive pointer movement:** pointer movement counts only while My Journal is active.
5. **R5, image descriptions:** typed descriptions are saved before an inactivity lock.

Recommended and adopted:
- The saves before locking are capped at 2 seconds. Input during them no longer cancels the lock.
- Menus count through `NSMenu.didBeginTrackingNotification`.
- Switching users locks.
- The wake-up has some tolerance.
- The setting is carried over when joining a server.
- The footer says what inactive means. The guide copy is the reviewer's.
- The VoiceOver statement is corrected, and choosing an entry counts as use.
- `updateDraft` is checked to be reached only from the editor's user-edit path: programmatic editor updates return early while `applying`, and sync changes set the draft through `followStoredDraft`.
- Input-method composition is checked to be part of the saved text on the Mac.

Optional and adopted:
- No one-minute choice.
- "Couldn’t Change Setting" as the alert title.
- An unlisted stored value is kept and shown.
- The debug variable is named `JOURNAL_UI_TEST_INACTIVITY_LOCK_SECONDS`.
- Double authentication after sleep is listed for the owner.

Not adopted:
- Editor text-selection changes don't count as use. Sync can move the selection when it replaces the open entry's text, and that would let a remote device keep the Mac unlocked.
- The footer stays as is while App Lock is off. The existing "needed to open" footer applies, and the pop-up and its explanation appear with the switch.

## Implementation and verification (2026-10-03)

Built as designed. Files:
- New: `Model/InactivityLock.swift` and `Views/InactivityLockSettings.swift` (the pop-up, the `keepsUnlockedWhile` and `savesBeforeInactivityLock` modifiers, and the footer sentence).
- Changed:
  - `LocalConfiguration` (`inactivityLockMinutes`), `ServerJoining` (carries it over) and `AppModel` (`inactivityLock`; `updateDraft` and choosing an entry count as use);
  - `JournalApp` (starts it after launch on the Mac) and `AppLockSettings` (pop-up row and footer);
  - the sheets that hold or save: Add Device, Connect, Archive export and import, Merge Into…, Use This Mac as Your Server, and Image Descriptions;
  - docs/guide/app-lock.md.
- Shared App Lock code: `lockImmediately` and `DeviceAuthentication` are unchanged. In `AppLockOperations`, `lock()` saves first (`saveBeforeLocking`) unless already locked, and `readJournalsAfterUnlocking()` retries kept image descriptions. New `Model/LockSaving.swift`. `AppModel` has the sheet save registry (`savesBeforeLocking`) and the kept descriptions (`unsavedImageDescriptions`).

Tests: `JournalTests/InactivityLockTests.swift`, nine cases matching "Tests" above. `JournalTests/LockSavingTests.swift` covers three more: Lock My Journal runs an open sheet's save before locking; descriptions a lock kept are saved after unlocking; a hanging save doesn't hold the lock. The first two fail with the change to `lock()` and the retry removed. The test that unsaved writing is saved before locking was checked to fail when the pre-lock save is removed. No cheap existing join test reads the configuration, so carrying the choice over when joining a server isn't tested.

Real app: a Debug build signed with the team's Apple Development identity, with its own bundle identifier, a scratch passwordless library with App Lock on, the scripted test authenticator and `JOURNAL_UI_TEST_INACTIVITY_LOCK_SECONDS=25`. A temporary in-process harness, since removed, recorded times and rendered the app's own windows.
- Unlocked at 0 s. Locked at 25.1 s with no input, while Settings was open. The Settings window then showed "Unlock My Journal to open Settings.", and the journal window's title became "My Journal".
- Settings ▸ Privacy showed "Lock when inactive: For 30 minutes" between the switch and Lock My Journal, with the new footer. The method reads "Face ID" there only because the scripted test authenticator reports Face ID.
- The Mac's screen was locked during the run, so the window couldn't be captured from outside. Input-driven behaviour (use postponing, late input locking) and the save before locking are covered by the unit tests, not by hand.

## Owner decisions (3 October 2026)

The owner accepted the recommendations:
- There is no inactivity setting on iOS; the app already locks when it leaves the foreground.
- The Mac locks on sleep and when switching users, even when the setting is Never.
- The choices are 5, 15 and 30 minutes, 1 hour, and Never; there is no longer option.
