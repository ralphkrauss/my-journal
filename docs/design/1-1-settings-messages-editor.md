# 1.1 Settings, messages and editor rules — 2026-10-09

Status: design for the design gate ([AGENTS.md](../../AGENTS.md)). Reviewed 2026-10-09 (approve with changes, at the end of this record); revised below, and "Changes after review" maps each finding to what changed. Not built. This record changes no code, test, spec or protocol file. No owner decision remains open.

Scope: simplifications E, B, F and A of [release-1-1-scope.md](release-1-1-scope.md), and the owner decisions of 2026-10-09 D5, D6, D7 and D55 ([spec/open-questions.md](../../spec/open-questions.md), section D). G, J (encryption, Change Password) and I (one Reconnect) are designed elsewhere; K, L, M and N are in [1-1-library-simplifications.md](1-1-library-simplifications.md). Where they meet this record, it says what it assumes. Paths are relative to `apps/apple/JournalApp` unless they start with `Packages/`, `docs/` or `spec/`.

## Summary

| | Change | Devices |
| --- | --- | --- |
| E | Settings has five panes in one order: General, Sync, Privacy, Backup, Agent Access. Devices becomes a section of Sync and Writing becomes General. Erase Journals and Settings… stays where it is (last section of the iPhone and iPad list, last group of the Mac's General). | iPhone, iPad, Mac |
| B | The save-before messages become two: one for the app's alert, one for any other presenter. | all |
| F | The rating request follows one rule: five writing days, at least 120 days since the last ask, at a clear pause that is not right after a problem. | all |
| D5 | One formatting rule for Bold, Italic, Underline, Strikethrough and Inline Code. | all |
| D6 | Return splits a heading in the middle into two headings; at the end it starts a paragraph. | all |
| D7 | One table command list in one order in the cell menus and in Format ▸ Table (now also on iPad), with the current alignment checked. | all |
| D55 | A failed Don't Allow says so on the Agent Access page, and the request stays. | all |
| A | Inventory of dead code (section 8). | none |

## 1. E. Settings: five panes

### 1.1 Current behaviour

- Six panes: Writing (General on the Mac), Sync, Devices, Privacy, Backup, Agent Access. `Views/SettingsView.swift` builds both shells: a `List` of `NavigationLink`s inside a sheet on iPhone and iPad (plus an About section and, as its own last section, Erase Journals and Settings…), and a `TabView` in the Settings window on the Mac (Erase is the last group of General). Pane titles are literal English strings; `settings.pane.general` has a `mac` variant ([spec/screens/settings.md](../../spec/screens/settings.md), [spec/platforms/apple/screens/settings.md](../../spec/platforms/apple/screens/settings.md)).
- `Views/DevicesView.swift` is a pane of its own: one section per device, errors, Try Again, a reconnect button when this device's access was refused, and Add Device…. It learns why access was refused with its own sync (`SyncHealthOperations.lostAccessHealth`), so it can disagree with Sync (open question A14), and it does not reload when a Connect sheet closes (A39).
- Ways into a pane from elsewhere: `AppModel.openSyncSettings()` (Sync Status ▸ Sync Settings…, sets `settingsTab = .sync` on the Mac and `settingsRequestedTab = .sync` elsewhere); `EncryptionUpgrade.showProgress()` (Mac notice, Privacy plus the Turn On Encryption sheet); the Mac notice "Show Connection" (`Views/SaveFailureNotice.swift`), which opens Settings on whatever tab was last selected. There is no URL scheme, App Intent or Spotlight entry for Settings (`onOpenURL` only opens `.journalarchive` files). Neither Settings nor Search Entries searches settings, and none is added.
- Messages and guides name panes by path: "Settings > Devices > Add Device", "Settings > Sync", "Settings ▸ Backup" and "Settings > Privacy" (open question B4).

### 1.2 New structure

The same five panes, in the same order, on every device. Nothing about the shell changes: a sheet with a list on iPhone and iPad, a tabbed window on the Mac.

| # | Pane (all devices) | Symbol | Holds |
| --- | --- | --- | --- |
| 1 | General | `gearshape` | Default Journal; Format Markdown as You Type. On the Mac also Erase Journals and Settings… (last group), as today. |
| 2 | Sync | `arrow.triangle.2.circlepath` | Server; Changes to Review; Devices; Stop Syncing… |
| 3 | Privacy | `hand.raised` | Placeholder for G and J: the encryption section (status, Change Password) and App Lock. |
| 4 | Backup | `externaldrive` | Archive; Markdown. Unchanged. |
| 5 | Agent Access | `person.badge.key` | Requests; Agents; Connect an Agent. Unchanged except section 7. |

**iPhone and iPad.** The Settings sheet keeps its title `settings.title` and its Done button (`common.done`). The list has:

```
Settings                                   Done
  General          >
  Sync             >
  Privacy          >
  Backup           >
  Agent Access     >

  About                       (iPhone and iPad only; unchanged: Privacy Policy,
  Privacy Policy                Support, Source Code, Rate My Journal, version)
  Support
  Source Code
  Rate My Journal
  Version 1.1 (build)

  Erase Journals and Settings…     (own last section, as today)
```

Erase Journals and Settings… stays its own last section of the list, below About, as the owner decided after testing build 15 ([erase-device-2026-10-04.md](erase-device-2026-10-04.md) §11: a standalone function, not part of a pane). The pushed pane's title is the row's name.

**Mac.** The Settings window has five toolbar tabs in the order above, with the same symbols; the window title is the selected tab's name. Sizing is unchanged: 560 points wide, the height of the content up to the screen less 120 points, Sync, Privacy, Backup and Agent Access at least 440 points tall so the sheets they present fit, General without a minimum. The Sync tab is now longer and scrolls like any tab that outgrows the screen. There is no About and no Done, as today.

**Why General everywhere.** The pane that holds Default Journal and the Markdown switch is Writing on iPhone and iPad and General on the Mac, and Windows plans General. One name is one string for every platform, and General is the pane every Apple settings list starts with. Only the name changes: where Erase sits is not part of E and is unchanged. The remaining difference stays in "Differences between iPhone, iPad and Mac": Erase is the last group of General on the Mac (its window has no list level) and the last section of the list on iPhone and iPad.

### 1.3 General

Content and order are what Writing has today:

1. **Default Journal** section, only when at least one journal exists: the picker `settings.general.defaultJournal` and its footer `settings.general.defaultJournal.footer`.
2. **Formatting** section: the switch `settings.general.formatAsYouType` and its footer.
3. **Mac only:** the Erase Journals and Settings… group, last, exactly as today ([spec/screens/settings-erase.md](../../spec/screens/settings-erase.md)). On iPhone and iPad the same button, footer, alerts and `closeAfterErasing()` are unchanged in the list's last section.

Labels keep their casing rules: sentence case inside Mac forms, title case on iPhone and iPad (`{"default", "mac"}` variants of the control keys). Only the pane title stops differing.

### 1.4 Sync, with Devices

Order, top to bottom, on every device. Sections that do not apply are absent, not dimmed.

```
Server                                   (settings.connect.server)
  https://journal.example.net            (address, selectable)
  Last Synced                 5 minutes ago
  Not on Server Yet           2 items    (only while items wait)
  [ Sync Now ]                           (the one action; I names it)
  footer: the sync state's message / pause notice / pin note
Changes to Review                        (only when there are conflicts;
  Title        date  [Review Changes]     H shrinks and then removes it)
Devices                                  (one section, one header:
  [ Add Device… ]                         settings.sync.devices.header)
  Loading Devices…                       (while loading)
  MacBook Pro                            (one row per device: name, "This Device"
    Added during server setup on …        when it is, how and when added, with a
                       [ Revoke Access… ] trailing Revoke Access… for every other)
  iPhone — This Device
    Added by MacBook Pro on …
  error line + [ Try Again ]             (only after an error)
[ Stop Syncing… ]                        (section of its own, last)
```

- **Server.** Exactly today's section: not connected shows Connect to a Server… and the not-connected footer; connected shows the address, Last Synced, Not on Server Yet and the one action chosen by the sync state (`syncStatusAction`). The action's wording and the single Reconnect belong to simplification I; this record only fixes where it lives: in this section, once, with the footer that explains the state. The Devices section never carries a reconnect button of its own.
- **Changes to Review** moves above Devices because it asks for a decision; it was below Stop Syncing. H removes it in two steps; when nothing is left the order is Server, Devices, Stop Syncing.
- **Devices** is [spec/screens/settings-devices.md](../../spec/screens/settings-devices.md) moved into the pane, with the same actions, confirmation and copy, as one section: one header (`settings.sync.devices.header`, a heading), Add Device… as its **first** row because it is the frequent task after connecting and should not sit below a long list, then one row per device. A row is the device's name, "This Device" when it is, and how and when it was added, read as one element; every other device's row has a trailing destructive **Revoke Access…** button (its own accessibility element, labelled as today with the device's name). At accessibility text sizes the button sits under the text. Add Device… opens Add Device as a sheet (over Settings on the Mac). The Revoke confirmation is unchanged.
  - Shown only while connected and the server accepts this device. Not connected: absent (Connect to a Server… is in the Server section). Access refused (any sync state that stops automatic sync because the server does not accept this device): absent, because the Server section already says why and offers the reconnect action. This ends the disagreement of A14 and the missing reload of A39.
  - Loads when the pane appears, when Add Device closes, when a Connect or Reconnect sheet opened from this pane closes, and after a revoke. It does not reload on every background sync.
  - A load that gets "not authorised" asks the model to learn why, as today, and the result appears in the Server section; the Devices section simply disappears.
  - The device list's error line and Try Again stay in the Devices section (`settings.devices.error.load`, `common.couldntRevokeAccess`).
- **Stop Syncing…** is last, in a section of its own, as Sign Out is last in iOS Settings. It asks first, unchanged (`settings.sync.stopSyncing.*`). Once the device stops syncing, Devices and Stop Syncing disappear.
- **Mac tab height.** The Settings window is as tall as the selected tab's content, so a Sync tab that grows when the device list arrives, or that gains and loses the Devices section when the connection changes, would make the window jump. The Sync tab therefore has a fixed height, the smaller of 640 points and the room the screen allows (`maxPaneHeight`), and scrolls inside it; the other tabs size as today.

### 1.5 Where links and references land

| From | Today | New |
| --- | --- | --- |
| Sync Status ▸ Sync Settings… (`openSyncSettings`) | Sync | Sync, scrolled to the top, where the Server section shows the state and its action. Unchanged. |
| Mac notice "Show Connection" | Settings on its last tab | **Sync** (`settingsTab = .sync`), because the Connect to a Server sheet it brings forward belongs to that pane. |
| Mac notice "Show Progress" (encryption) | Privacy plus the Turn On Encryption sheet | Unchanged; G decides whether the notice still exists. |
| Settings opened from the Journals screen or sidebar | iPhone, iPad: the list. Mac: last selected tab (initially General) | Unchanged. |
| Text that names a pane | "Settings > Devices > Add Device", "Settings > Sync", "Settings > Privacy", "Settings ▸ Backup" | Always the "▸" form, and "Settings ▸ Sync ▸ Devices ▸ Add Device" for the device task (table in 1.9). Settings paths use one form, which settles B4 for the strings touched here. |

`AppSettingsTab` loses `.devices` (`Model/AppModel.swift:8`). The selected tab is never stored on disk, so no stored value needs migrating. The guides and notes that name panes change in the same step (section 10).

### 1.6 What G, I and J can assume

- **Privacy** keeps its name, symbol, tab and third place whatever G and J leave in it. If encryption becomes a status line plus Change Password, it is the first section; App Lock follows. The Mac `Show Progress` deep link and the Turn On Encryption sheet are theirs.
- **Sync** has one place for the reconnect action: the Server section. I may rename the action; it may not add another.
- **Agent Access** already has its own "Connect Again…" (`settings.agents.connect.noAccess`); I decides whether it stays.

### 1.7 Accessibility

- Rows and tabs keep a text label plus a decorative icon. The pane list reads "General, button" and so on; nothing says "Writing" any more.
- The Devices header is the section's one heading, followed by Add Device… and one row per device (name, This Device and how it was added as one element; each Revoke Access… button labelled with the device).
- A list that loads or reloads is silent. An error in the Devices section is announced when it first appears with the same `JournalAccessibility.announce` the Backup pane uses; Try Again keeps keyboard and VoiceOver focus when it is pressed. The other panes are unchanged.
- Add Device… and Stop Syncing… end with an ellipsis because they open a sheet or ask first. After Add Device closes, focus returns to the button.
- Keyboard: the Mac tabs are the system's; Escape closes a sheet from Settings, not the window. iPad with a keyboard: arrow keys and Full Keyboard Access move through the list. No new shortcut.
- Dynamic Type, Reduce Motion, Increase Contrast: system forms; no overrides.

### 1.8 States, empty and error

- Locked, library problem, no library: unchanged (`settings.locked`, `settings.libraryProblem`, Privacy empty).
- Offline: Sync shows the offline message and Try Again in the Server section; the Devices section shows its last list, or `settings.devices.error.load` with Try Again if it never loaded.
- Not connected: Server section only. The footer says what Devices used to say, in one text (1.9).
- Loading: `settings.devices.loading` in the Devices section; Add Device… is dimmed.

### 1.9 Copy and catalog

| Key | Change |
| --- | --- |
| `settings.pane.general` | Text "General" for every device; the `mac` variant is removed. Context: "Settings row or tab for writing preferences (and, on the computer, Erase Journals and Settings…)". |
| `settings.pane.devices` | **Removed** (no longer a pane). |
| `settings.sync.devices.header` | **Added**: "Devices". Header of the Devices section. |
| `settings.devices.notConnected`, `settings.devices.locked` | **Removed**. Not connected: the Devices section is absent. Locked: Settings shows only `settings.locked`, so the branch in `DevicesView` was never reachable. |
| `settings.sync.footer.notConnected` | **Changed** to "Your journals are saved on this device. To sync them with your other devices, connect to a server." (the Learn More and How to Set Up a Server links stay on a new line), which carries the one idea the removed text had. |
| `settings.devices.add`, `settings.devices.loading`, `settings.devices.error.load`, `settings.devices.revoke*`, `settings.devices.added.*`, `common.revokeAccessFor`, `common.couldntRevokeAccess` | Text unchanged; contexts now say "Settings ▸ Sync ▸ Devices". |
| `messages.encryption.accessLost`, `settings.connect.addThisDevice.instructions`, `settings.connect.scanCode.footer`, `settings.addDevice.scanInstructions`, `settings.sync.stopSyncing.message`, `messages.connection.encryptionOffOnHost` | Path text changes: "Settings > Devices > Add Device" becomes "Settings ▸ Sync ▸ Devices ▸ Add Device"; "Settings > Sync" and "Settings > Privacy" become "Settings ▸ Sync" and "Settings ▸ Privacy". G removes the two encryption messages if their situations go; the others stay. Code literals in `Views/ConnectionSteps.swift`, `Views/ConnectionView.swift`, `Views/AddDeviceView.swift`, `Views/SyncNowRows.swift` and `Model/ConnectionFlow.swift` change with them. |
| `settings.connect.nearby.denied` | "System Settings > Privacy & Security > Local Network" is the system's own path and stays. |

### 1.10 Spec and documentation changes

Neutral spec: `screens/settings.md` (five panes, content for phone and tablet and for the computer, entry points, requested pane, "initial tab" rule, Platform notes: the pane is General everywhere and the Erase difference stays), `screens/settings-general.md` (title; Erase stays the Mac's last group), `screens/settings-sync.md` (Devices section, Changes to Review before Devices, Stop Syncing last, the single reconnect action), `screens/settings-devices.md` (kept as the page for the Devices section: title "Settings ▸ Sync ▸ Devices", entry point, states for "access refused", Locked and Not connected rewritten), `screens/settings-about.md` ("after the five pane rows"), `flows/sync-recovery.md`, `flows/reconnect-to-server.md`, `flows/markdown-as-you-type.md` and the screens that name the panes, `messages.md`, `commands.md`, `copy/en.json`, `parity.yaml` (the `settings` title says five panes; `devices-list`, `revoke-device`, `add-device` keep their ids and point at the same page), and `open-questions.md` (A14 and A39 resolved by the move; B4 resolved for the touched strings; D26's Windows note).

Apple notes under `spec/platforms/apple/`: `screens/settings.md`, `settings-general.md`, `settings-sync.md`, `settings-devices.md`, `platform.md` section 10, `index.md`, `flows/reconnect-to-server.md`, `flows/sync-recovery.md`, `flows/pair-device.md`, `flows/markdown-as-you-type.md`. Screenshots come from the capture scripts only: `SpecSettingsCaptureTests` (the Writing and Devices pages), `SpecSyncCaptureTests` (connected Sync with Devices), `design/spec-screenshots/capture.sh iphone ipad mac`, from the seeded library.

Windows mapping pages (`platforms/windows/screens/settings.md`, `settings-general.md`, `settings-sync.md`, `settings-devices.md`, `platform.md` 12.3 and `copy-proposals.md` for `settings.pane.general`) describe six panes and the Writing/General variant. The Windows agent updates them; this change edits only the statements that would otherwise be false and records the rest as a new open question in section C, as C23 does for build 18.

Public documentation: `docs/guide/README.md` (pane list for Mac and iPhone), `docs/guide/devices.md`, `docs/guide/troubleshooting.md` (every "Settings > Devices"), `docs/app-store/review-notes.md`. The store screenshots and `docs/app-store/screenshots-plan.md` wait for the owner (App Store and README screenshots are recaptured only when the owner says they are ready). UI tests that tap "Writing" or "Devices" (`JournalUITests.swift`, `CollectionNavigationUITests.swift`, `PermanentDeletionUITests.swift`) and the capture tests are updated with the code.

## 2. B. Two "save first" messages

### 2.1 Current behaviour

When a save has failed (`AppModel.saveFailure`), operations that need the open entry written first call `finishPendingSave()` or `entryAutosaveSettled()`, get `false`, and throw their own sentence. There are 20 catalog keys and 25 code sites ([spec/flows/save-failure.md](../../spec/flows/save-failure.md) lists the keys by operation; [spec/messages.md](../../spec/messages.md) rows for `messages.save.before.*`, `common.saveBeforeMoveEntry`, `common.saveBeforeCreateJournal`, `messages.connection.saveBeforeConnecting`). Three wordings say the same thing ("Save your changes before …", "Save your entry before …", "Save your current entry before …") and two say something different (`changeDate`: close the sheet; `imageDescriptions`: copy your descriptions first). The sentence shows in one of two places: the app's alert (`model.error`), which offers Try Again while a save has failed, or inline in a sheet or pane, where Try Again is not on screen.

Inventory by site. "Gone" means another 1.1 simplification removes the site; the remaining sites are 16.

| Site | Message today | Surface | After 1.1 |
| --- | --- | --- | --- |
| `Model/EntryRestorationOperations.swift:22, 57, 70` | `reviewEntry`, `restoreEntry` (x2) | Restore Journal sheet | Gone (N) |
| `Model/EntryDeletionOperations.swift:138` restore a template | `restoreTemplate` | alert | alert |
| `Model/JournalOperations.swift:8` `moveEntry` | `common.saveBeforeMoveEntry` | Move Entry sheet; alert when called by Restore | sheet; alert |
| `:33` resolve a journal conflict | `reviewChanges` | review form | Gone (H, step 1) |
| `:54`, `:63` prepare and commit Delete Journal | `deleteJournal` | alert | alert |
| `:71` `restoreJournal` | `restoreJournal` | Restore Journal sheet | alert (N: no sheet) |
| `:96` `mergeJournal` | `mergeJournal` | Merge sheet | Gone (L) |
| `:131` `createRecoveryJournal` | `common.saveBeforeCreateJournal` | name sheet | sheet |
| `Model/DocumentTransferOperations.swift:58` | `exportArchive` | Backup pane or Export sheet | sheet or pane |
| `Model/MarkdownExportOperations.swift:17` | `exportMarkdown` | Backup pane or Export sheet | sheet or pane |
| `Model/ArchiveInstalling.swift:34` | `importArchive` | import preview or pane | sheet or pane |
| `Model/PermanentDeletionOperations.swift:49` | `reviewChanges` | alert | alert |
| `Model/ServerJoining.swift:11, 74, 181` | `messages.connection.saveBeforeConnecting` | Connect to a Server sheet | sheet |
| `Model/EntryActionOperations.swift:25` | `changeDate` (`EntryDateError.saveRequired`) | Change Date sheet | sheet |
| `AppModel.swift:534` (`ImageDescriptionError.entrySaveRequired`) | `imageDescriptions` | Image Descriptions sheet | sheet |
| `Model/HistoryOperations.swift:8` | `restoreVersion` | Version History sheet | sheet |
| `:31` | `restoreJournalSettings` | journal history | Gone (K) |
| `Views/JournalLifecycleView.swift:333` | `openRestoredJournal` | Restore Journal sheet | Gone (N) |
| `Views/JournalConflictView.swift:130` | `exportArchiveForConflict` | review form | Gone (H, step 1) |
| `Views/EntryConflictReview.swift:179` | `resolveEntryConflict` ("Your latest changes couldn’t be saved. Try again.") | review form | Gone (H, step 2) |

### 2.2 New behaviour

The model throws one typed error, `JournalError.saveRequired`, wherever it throws a "save first" sentence today (`EntryDateError.saveRequired` and `ImageDescriptionError.entrySaveRequired` are replaced by it). The error carries no sentence of its own for the alert; each presenter chooses:

| Key | Text | Used where |
| --- | --- | --- |
| `messages.save.before.tryAgain` | Your changes aren’t saved yet. Choose Try Again, then repeat what you were doing. | The app's alert (`common.alertTitle`), which has a Try Again button while a save has failed: restore a template, Delete Journal (two sites), restore a journal, Delete Permanently, and Move Entry's site when Restore calls it. 6 sites. |
| `messages.save.before.goBack` | Your changes aren’t saved yet. Go back to your entry, choose Try Again under Not Saved, then repeat what you were doing. | The fallback, and the text of `JournalError.saveRequired.errorDescription`: every presenter that is not the alert. The name sheet of Move Entry, Version History, Change Date, Image Descriptions, Backup (Export Archive, Export as Markdown, Import Archive) and Connect to a Server (three sites) are 10 other sites; Move Entry's site, when its sheet calls it, is the same site as in the first row. 16 sites in all. |

How the alert chooses (there is no single place that turns an error into `model.error`: it is a `String?` assigned at about 25 sites, and the alert shows Try Again only `if model.saveFailure`, read when the alert is drawn, `Views/RootView.swift`):

- The six alert sites stop assigning a string. They call one model function, `report(_ error:)`, which for `JournalError.saveRequired` keeps the typed error (`AppModel.saveRequiredAlert`) and for anything else behaves as today (`error.shown(.saving)` into `model.error`).
- `RootView` draws the alert for `model.error` as today, and also while `saveRequiredAlert` is set **and** `model.saveFailure` is still true; its message is `messages.save.before.tryAgain`. The wording is therefore decided when the alert is drawn, with the Try Again button in the same decision. If the save succeeded before the alert showed (the retry that runs on every edit worked), `saveFailure` is false, nothing is shown, and the typed error is cleared: no message about a problem that is gone.
- A site that still assigns `error.shown(.saving)` shows the `goBack` text. It is wordier but never wrong, so a forgotten site cannot say "Choose Try Again" with no button. A new operation needs no new sentence.
- The notice's Try Again, the alert's Try Again and the button wording are unchanged. Nothing else about save failure changes ([spec/flows/save-failure.md](../../spec/flows/save-failure.md)): the first failure still shows `common.saveFailed`; a failed save still blocks the operation and keeps the writing; locking, closing the Mac window and quitting are unchanged.
- Change Date's Save and the Image Descriptions sheet's Done are already dimmed while a save has failed, so these two messages appear only in a race. In Image Descriptions the typed descriptions stay in the sheet and its **Copy Descriptions** button stays visible, which is why the sentence no longer says to copy them.
- "Go back to your entry" means closing the sheet on iPhone and iPad and on the Mac's journal window, and switching from the Settings window to the journal window on the Mac (the Settings window is a window, not a sheet; the Mac note in `spec/platforms/apple/messages.md` says so). "Not Saved" is the notice's word on every device (`messages.save.notSaved`).

### 2.3 Accessibility and errors

- In the alert the message is read as the alert is. Inline errors in a sheet are announced when they appear; each presenter keeps the announcement it has now (Image Descriptions and Allow Access announce their error text; Backup announces export errors).
- Error states: nothing new. The notice and the alert remain the only places that can fix the cause.

### 2.4 Catalog and spec

Added: the two keys above. Removed: `common.saveBeforeMoveEntry`, `common.saveBeforeCreateJournal`, `messages.connection.saveBeforeConnecting` and the 17 existing keys under `messages.save.before.` (changeDate, deleteJournal, exportArchive, exportArchiveForConflict, exportMarkdown, imageDescriptions, importArchive, mergeJournal, openRestoredJournal, resolveEntryConflict, restoreEntry, restoreJournal, restoreJournalSettings, restoreTemplate, restoreVersion, reviewChanges, reviewEntry). K, L, N and H also remove some of these; whichever change lands last removes the rest, and the spec checker warns about keys nobody references. `spec/flows/save-failure.md` replaces its "save first" table with two rows (alert, sheet or pane) and the list of operations above; `spec/flows/save-entry.md` stops naming `common.saveBeforeMoveEntry`, `messages.save.before.restoreVersion` and `messages.save.before.changeDate`; `spec/messages.md` replaces its 20 rows with two; B1 in `open-questions.md` is resolved; `Tests` below. `JournalTests/FailureMessageTests.swift` (`testTheAppsOwnErrorsKeepTheirText`) uses the literal "Save your changes before connecting." and changes to the new error.

## 3. F. Rating request: one rule

### 3.1 Current behaviour

`Model/ReviewRequest.swift` and `Model/ReviewRequestTiming.swift` ([spec/flows/rating-request.md](../../spec/flows/rating-request.md)): installed from the App Store; at least 7 days since the first use; writing saved on at least 4 local calendar days; the system not asked during this app version; at least 120 days since the last ask; no problem since launch. The moment: the person edits an entry and leaves it, two seconds pass with nothing happening, and the screen is clear (no sheet, alert, popover, text focus, running operation, failed save, error or conflict, no new empty entry). Stored per device in preferences: `firstUse`, `writingDays`, `lastWritingDay`, `lastRequestVersion`, `lastRequest`. "No problem since launch" is a memory: `noteProblem()` is called from five places (`AppModel.swift:154` error, `:157` failed save, `:188` conflicts, `:209` long sync wait, `SyncHealthOperations.swift:77` any sync state that is not temporary).

### 3.2 What Apple asks for

Apple's guidance (Human Interface Guidelines, Ratings and reviews; the StoreKit `requestReview` documentation) is: ask only after the person has used the app enough to have an opinion; ask at a natural pause after finishing something, not in the middle of a task and not in response to a button; do not ask right after launch or after something went wrong; and expect the system to decide, since it shows the prompt at most three times in 365 days and may show nothing.

### 3.3 The rule

> My Journal asks for a rating once the person has saved writing on at least **five different days**, no sooner than **120 days** after the last time it asked, at the quiet pause after they leave an entry they wrote in, and not right after something went wrong.

- **Kept:** installed from the App Store (TestFlight and development builds never ask); the pause (leave an entry that was edited, wait two seconds, ask only if nothing happened meanwhile); the clear-screen check as it is today, so no running operation, failed save, error, conflict, sheet, popover or text focus; recording that it asked, whether or not the system shows anything.
- **Kept, narrower: "not right after something went wrong."** `problemThisSession` stays, but only for the three causes that show on screen: an error alert (`AppModel.error`), a failed save (`saveFailure`) and changes to review (`conflicts`). Those are the three `didSet` hooks in `AppModel.swift` (`:154`, `:157`, `:188`) that call `noteProblem()`; nothing else does.
- **Added to the clear-screen check:** Sync Status is not showing, that is, no sync state needs the person and sync has not been failing for a day (`AppModel.showsSyncStatus` is false). This is a live read of what the toolbar already shows, and it replaces the two sync callers of `noteProblem()` (`:209` long wait, `SyncHealthOperations.swift:77` a state that is not temporary), which are removed.
- **Removed:** the 7-day rule and `firstUse` (five writing days take at least five days), the once-per-version rule and `lastRequestVersion` (120 days spacing gives at most three asks in a year, which is the system's own cap), and the two sync callers above. `noteLaunch()` goes too; the record is created at the first saved edit. The `JOURNAL_UI_TEST_REVIEW` seam (`ReviewRequestTiming.swift:48`) builds its in-memory record without `firstUse`.
- **Stored data:** the 1.0 record keeps working. `ReviewUsage` drops the two fields; decoding ignores them, so an existing `lastRequest` and `writingDays` count from the first launch of 1.1, and someone asked during 1.0 is not asked again for 120 days.
- **What this gives up:** the session memory of a sync problem. A person who fixed a sync problem a few minutes ago can be asked at the next pause; one who has an error, a failed save or a conflict this session cannot.
- **Why five and 120:** five days is one more than today's four, to make up for dropping the one-week floor; 120 days stays as it is. They are the only two numbers left and are tuning, not product policy; this record decides them.

### 3.4 Interface, copy, accessibility

No interface and no copy: the prompt is the system's. Nothing is announced, and focus is never moved. `spec/flows/rating-request.md` is rewritten around the rule above ("When it may ask" shrinks to three rules; "What counts as a problem" lists the three on-screen causes and says Sync Status showing blocks the moment; Storage shrinks); `spec/platforms/apple/flows/rating-request.md` loses the sync callers of `noteProblem` and the version rule; C24's mention of `messages.sync.localDataUnavailable` is no longer needed.

## 4. D5. One formatting rule

### 4.1 Current behaviour

[spec/flows/editing-rules.md](../../spec/flows/editing-rules.md) F-1 and F-3. Bold, Italic and Underline with a selection turn on unless every character that can carry them has them (`RichText.toggling` on the Mac, `Editor/RichTextRuns.swift:81`; on iPhone and iPad `Editor/NativeEditor.swift` calls UIKit's `toggleBoldface`, `toggleItalics` and `toggleUnderline`, whose behaviour for a mixed selection is not recorded anywhere). Strikethrough and Inline Code follow the first selected character: if it lacks the style the whole selection gets it, otherwise the whole selection loses it (`MarkdownEditing.toggle`, `Editor/MarkdownEditing.swift:188`). Table cells take the first rule for Bold, Italic and Underline (`TableCellFormatting`, `state != .on`) and the second for Strikethrough and Inline Code. The Formatting surface shows On, Off or Mixed from `FormattingState` and applies a different rule from the one it shows.

### 4.2 New behaviour (owner decision 2026-10-09)

With a selection, any of the five styles **turns on for the whole selection unless the whole selection already has it, in which case it turns off.** A Mixed selection therefore turns on, as in TextEdit, Pages and Notes. The state the control shows and the action are computed by the same code over the same characters:

- **One predicate.** `carries(style, attributes)` says whether a character can have a style at all. `FormattingState` uses it to decide what it samples for On, Off and Mixed, and the command uses it to decide what it changes and what it counts. The command turns the style on unless the state over the carrying characters is On. Characters that do not carry a style: for Bold, a heading's text (its weight is its style, F-2); for all five, text in a code block (F-5) and image placeholders. Line breaks never decide: they are skipped when deciding and receive the new value when applying. A selection with no carrying character leaves the command doing nothing.
- **Every route calls it:** the Format menu and its shortcuts (⌘B, ⌘I, ⌘U, ⇧⌘X, ⌥⌘C), the Formatting popover and panel, the keyboard bar, table cells, and, on iPhone and iPad, the system's own routes below. After one press the control reads On; a test asserts it for a heading plus a bold paragraph, a struck selection across a line break, and a selection that contains an image.
- **iPhone and iPad system routes.** The editor sets `allowsEditingTextAttributes`, so the system edit menu's B, I and U and a hardware ⌘B, ⌘I or ⌘U that UIKit handles before the app's key commands call `toggleBoldface(_:)`, `toggleItalics(_:)` and `toggleUnderline(_:)` on the text view, with UIKit's own rule for a mixed selection. `JournalTextView` (`Editor/NativeTextView.swift`, the `UITextView` subclass) overrides all three to run the shared command, and answers `validateCommand` / `canPerformAction` so the system menu shows the same On, Off or Mixed as the Formatting surface. The three direct calls in `Editor/NativeEditor.swift` go. If an override proves unreliable on a device (a menu that still reaches UIKit's rule), `allowsEditingTextAttributes` is turned off and the edit menu offers the app's own Format actions instead; the rule above is not relaxed.
- **Mac.** The Format menu and the Formatting surface are the only routes; the system Fonts menu and font panel are not present.
- **No selection (F-4):** the style toggles for the next typed text, on unless the typing style already has it. Unchanged.
- **Source view** is unchanged: the command adds or removes the Markdown marker pair around the selection.
- **Strikethrough and Inline Code** stop following the first selected character (`MarkdownEditing.toggle`); they use the predicate like the others, in the body and in table cells.

F-1 becomes the one rule above and says what cannot carry each style; F-3 is marked "merged into F-1" (the id stays, tests cite it); F-6 says that pressing a Mixed control turns the style on.

### 4.3 Accessibility

The control's value reads "On", "Off" or "Mixed" as today (`editor.format.state.*`), in the Formatting surface and in the iPhone and iPad edit menu. Pressing a Mixed control makes it read "On". Nothing new is announced. Undo is one step named by the command, as today.

### 4.4 Catalog

None. `spec/flows/editing-rules.md` F-1, F-3, F-6; `spec/screens/format-sheet.md` (Actions row for the five styles); `spec/flows/edit-table.md` step 3 (rule is the same in a cell); `open-questions.md` D5 gets "Built in 1.1".

## 5. D6. Return in a heading

### 5.1 Current behaviour

`RichText.newlineAction` (`Editor/RichText.swift:618`, heading branch at `:629`) inserts a line break that carries the heading's style at the caret and sets the typing style to a paragraph, on every device. At the end of a heading that is right. In the middle the text after the caret keeps the heading style while typing continues as a paragraph, so the second half is a heading or a paragraph depending on what happens next (N-8, open question D6).

### 5.2 New behaviour (owner decision 2026-10-09; the gaps are filled by convention)

For any of the six heading levels, with an empty selection and no text being composed:

| Caret | Result |
| --- | --- |
| In an empty heading | The heading becomes a plain empty paragraph; the caret stays on it. No new line is added (as Return on an empty list item leaves the list, N-5). |
| At the end of the heading's text | A new empty plain paragraph below; the caret is in it. As today. |
| In the middle | The heading splits into two headings of the same level. The first keeps the block's identity; the text after the caret becomes a new heading block with a new identity. The caret is at the start of the second. |
| At the very start of a non-empty heading | An empty plain paragraph is added above; the heading keeps its identity, level and text; the caret stays at the start of the heading text. (The same rule as N-3 for list items; it avoids an empty heading in the Markdown.) |

How the split is made, so that undo is one step and the identity is stable:

- **One replacement.** The replacement covers the text from the caret to the end of the heading, so the line break and the tail with its new `journalBlockID` attribute are written in one `replace` and are one undo step ("Undo Typing"). The first half keeps the old `journalBlockID`; the tail gets a fresh `UUID` in its own attributes. This matters because `RichText.document` replaces a repeated `journalBlockID` with a new random one every time it reads the text, so a tail that merely repeated the first half's ID would change identity on every save and look like a new block to history, conflict detection and sync. Test 4 reads the document twice and compares the IDs, and checks that undo restores the single original ID and redo restores the two.
- **Typing attributes.** After a split the typing attributes are the heading's (its kind, and its font), without a link, not a paragraph's (`nextKind: "paragraph"` is what the end case sets today), so typing at the start of the second heading does not turn it back into a paragraph. After the end case they are a paragraph's, as now.
- **Text is not trimmed.** The second heading may start with a space, as in any word processor; the Markdown writer drops it on export as it does for any heading, so the blocks round-trip as two headings and the exact leading space does not.
- **Selections.** With a selection, Return first replaces it, and the result is classified by where the caret lands. A selection that crosses blocks behaves as it does today.
- **Composition.** Return while text is being composed (marked text) commits the composition and does not split; the existing `hasMarkedText()` guards on both editors keep this, and one test covers it.
- **Inline formatting** (bold, links, code) stays on the text it was on; the caret's typing style continues the formatting at the caret, as N-4.
- **Kinds are exclusive.** A heading cannot also be a list item or a quote in this model, so there is no list-in-heading case. Import of Markdown such as `> # Title` is not changed by this record.
- Nothing is announced; VoiceOver users hear the new line when the caret moves.
- Not changed: Return in source view (plain text), in a table cell (N-15), and lines inserted in one piece by dictation or a paste (N-11 and PA rules); a key burst "# Title⏎Text" still ends in a paragraph because the Return is at the end (N-12).

`spec/flows/editing-rules.md` N-8 is rewritten to the table above; `TypingRoomTests` ("Return after a heading") keeps its end case. Both the Mac and the iOS editor call the same `newlineAction`; the new branches are shared code with no platform split.

## 6. D7. One table command list

### 6.1 Current behaviour

Three lists for the same commands ([spec/flows/edit-table.md](../../spec/flows/edit-table.md), [spec/platforms/apple/flows/edit-table.md](../../spec/platforms/apple/flows/edit-table.md)):

| Where | Items today |
| --- | --- |
| Mac, cell context menu ▸ Table (`Editor/InlineTableGridMac.swift:195`) | Add Row Below, Add Column After, Align Left, Align Center, Align Right (flat), Delete Row, Delete Column, Delete Table |
| Mac, Format ▸ Table (`AppCommands.swift:200`) | Add Row Below, Add Column After, —, Delete Row, Delete Column, Delete Table (no alignment) |
| iPhone and iPad, cell edit menu ▸ Table (`Editor/InlineTableGridIOS.swift:191`) | Add Row Below, Add Column After, Alignment ▸ (Left, Center, Right), Delete Row, Delete Column, Delete Table (destructive) |

### 6.2 New behaviour (owner decision 2026-10-09)

One list, in one order, in every place the commands appear:

```
Add Row Below                       library.menu.format.table.addRow
Add Column After                    library.menu.format.table.addColumn
Alignment                       >   editor.table.alignment
  ✓ Left                            editor.table.alignment.left
    Center                          editor.table.alignment.center
    Right                           editor.table.alignment.right
------------------------------
Delete Row                          library.menu.format.table.deleteRow
Delete Column                       library.menu.format.table.deleteColumn
Delete Table                        library.menu.format.table.deleteTable
```

- **Mac cell context menu:** the standard text items, a separator, then Table ▸ the list above. **Format ▸ Table on the Mac and on iPad:** the same list; it is enabled only while a cell is being edited (`editor.editingTable`). **iPhone and iPad cell edit menu:** the system's items followed by Table ▸ the same list, with the three Delete items destructive (red) and a divider before them (an inline group). On the Mac, menus do not colour destructive items.
- **Format ▸ Table on iPad.** The iPad menu bar gets the same `Menu` as the Mac, from the same definition, so a person with a hardware keyboard, Full Keyboard Access, Switch Control or Voice Control has a route that does not need the touch-opened edit menu. `AppCommands.swift` drops the `#if os(macOS)` around it, and the iOS editor wires `editor.tableAction` as the Mac's does (`Editor/NativeTableIntegration.swift`; the wiring is Mac-only today, and the implementer verifies on a device that the menu enables with the caret in a cell). On the phone there is no menu bar; the cell's edit menu is the route.
- **Current alignment is checked.** In the Alignment submenu the column's current alignment has a checkmark (`NSMenuItem.state`, `UIAction.state`, a checked item in the SwiftUI `Menu`). A column with no stored alignment shows Left checked, as the grid draws it; choosing Left still stores `:--` as today. Menus built from the definition receive the cell's alignment with the list.
- The three renderings are built from one definition (items with action, destructive flag, submenu and checked state) in `Editor/TablePresentation.swift` and rendered by small adapters (`NSMenu`, `UIMenu`, SwiftUI `Menu`). Nothing else about a table changes: caret position after an edit, one undo step each, deleting the last row or column removes the table (TB-4).
- The list is built only when the entry is editable. A read-only entry shows no Table menu, as the spec already says; this also fixes open question A43.
- Accessibility: menu items are read by title; the Alignment submenu is read as "Alignment, submenu" and the current alignment as selected. Full Keyboard Access reaches the Mac menus through the menu bar; there are no shortcuts for these items, as today.

### 6.3 Catalog and spec

Removed: `editor.table.alignLeft`, `editor.table.alignCenter`, `editor.table.alignRight` (the Mac's flat items). Contexts changed: `editor.table.alignment`, `editor.table.alignment.*` (now "all devices, Table ▸ Alignment ▸"), `library.menu.format.table` and `library.menu.format.table.*` (cell menu, Format ▸ Table on the Mac). `spec/flows/edit-table.md` step 4 and its platform note, `spec/flows/editing-rules.md` TB-4, `spec/commands.md` and `spec/platforms/apple/commands.md` table rows (the table commands appear in Format ▸ Table on the Mac and iPad, and `table-align-left`, `table-align-center`, `table-align-right` in Table ▸ Alignment ▸ everywhere; the Format menu order line says "then Table ▸" on both), `spec/platforms/apple/flows/edit-table.md` Controls and "Items of the structure menu", and D7 in `open-questions.md`.

## 7. D55. Don't Allow that can't reach the server

### 7.1 Current behaviour

In Allow Access, Don't Allow (`Views/ServerAgentsView.swift`, `decline()`) cancels the sheet's work, starts `Task { try? await controller.decline(...) }`, announces `settings.allowAgent.declinedAnnouncement`, and closes at once. `ServerAgentsController.decline` removes the request from the list first, then sends the decline. If the send fails the person is told nothing, "Request declined." was announced, and the request comes back on a later refresh ([spec/flows/allow-agent.md](../../spec/flows/allow-agent.md), Rules).

### 7.2 New behaviour (owner decision 2026-10-09)

The Agent Access page shows the message. The sheet still closes at once, because it has no other way out and the server can be slow. The decline is sent in the background by an owner that lives as long as the app session, and the page reports the outcome.

- **Owner.** `ServerAgentsController` is a `@StateObject` of `SettingsView` and `clear()` cancels its tasks, so it cannot own a decline that must survive closing Settings. A small `@MainActor` object, `AgentRequestDeclines`, held by `AppModel` (so it lives as long as the session), keeps the set of requests being declined, their tasks and the failure message. The Settings controller reads it and no longer sends declines itself. It cancels its tasks on Erase Journals and Settings and on Stop Syncing (the connection they belong to is gone), not on lock (a decline exposes nothing), not when Settings closes. A task ends when the server answers or the request times out, and removes itself from the set.
- **Hidden while in flight.** A request being declined is left out of the Requests list, and a refresh that still lists it (the server has not recorded the decline yet) does not show it.
- **Mapping of the server's answer**, done where the response is read and covered by a test of its own:

  | Answer | Result |
  | --- | --- |
  | 2xx | Declined. |
  | 404 `agent_request_not_found` (`AgentCopyError.requestNotFound`: expired, replaced or answered elsewhere) | Done: the request is gone, nothing to retry. |
  | Cancelled (Erase, Stop Syncing) | Nothing is shown. |
  | A network error (`URLError`), not authorised, `serverOutdated`, `failed` or any other status | Failed. |

- **Done:** `settings.allowAgent.declinedAnnouncement` ("Request declined.") is announced once, now and not before; focus does not move.
- **Failed:** the row returns to the Requests list, and the message `settings.agents.requests.declineFailed` shows as the footer of the Requests section, in the pane's ordinary error style (secondary text, as the Devices and Backup errors; the words and the announcement carry it, not colour). It is announced once when it appears. The person opens the request and chooses Don't Allow again. The message stays until a later decline succeeds, the person opens that request again, a reload lists the request no more, or the app locks. If Settings is closed before the failure arrives, nothing is shown; the request is still listed when the pane opens again, since the server still holds it (it expires after 10 minutes).
- The sheet's other paths are unchanged: a wrong number still declines on the server and shows `settings.allowAgent.mismatch.*`; a request that has ended still shows `settings.allowAgent.ended.*`.

```
Requests
  Claude Code
  journal.example.net · just now          (the row is back)
  Couldn’t decline the request from Claude Code. Open it and choose Don’t Allow to try again.
```

Accessibility: the message is the footer of the Requests section, read after the rows, and announced once when it appears. Voice Control and Full Keyboard Access use the row as before.

### 7.3 Copy and spec

Added: `settings.agents.requests.declineFailed` = "Couldn’t decline the request from {name}. Open it and choose Don’t Allow to try again." ({name} is the client name cleaned by `AgentDisplayName.clean`, exactly as in the row; it is the agent's own text, shown as data and never as an instruction). The sentence does not blame the connection, because the server may have answered with an error. `settings.allowAgent.declinedAnnouncement` context: "Announced when the server has recorded the decline (the sheet has closed by then), or after a wrong number." `spec/flows/allow-agent.md` (step 8, the Rules line "Declining sends no error"), `spec/screens/allow-agent.md` (Actions row for Don't Allow, States), `spec/screens/settings-agent-access.md` (Requests: footer and states), the Apple pages, and D55 in `open-questions.md`.

## 8. A. Dead code to remove

Method: a name search of every Swift file under `apps/apple` (app, JournalCore, tests, probes) for declarations referenced nowhere else, then a manual trace of each hit and of everything only the hit reaches. No analyzer such as Periphery is installed. Delegate methods and framework callbacks (AppKit, UIKit, GRDB, StoreKit) show up in a name search and are not dead. Evidence is by search; the implementer re-runs the same searches and builds before deleting. For `JournalSettingsView` the trace went on to the model functions it called (`changeJournal(name:)` and `changeJournal(template:)`, `journalNameTaken`, `offersDefaultTemplateChoice`, `journalRecords`, `prepareJournalDeletion`, `deleteJournal`): all are still reachable from other views, so removing the view loses no feature, and **the model functions stay** (`prepareJournalDeletion` and `deleteJournal` are used by `JournalDeletionPrompt` and by five test files, even though the Delete Journal mode of `JournalLifecycleView` is dead). `JournalSettingsView`'s accessibility identifiers (`journal-default-template-…`, "New journal name") are referenced by no UI test, so no test changes.

**Dead, confirmed by search**

| What | Evidence |
| --- | --- |
| `Views/JournalsSheet.swift`, `Views/JournalSettingsView.swift` (with `JournalNameField` and `JournalNameTakenMessage`) | `JournalsSheet` is created in `Views/RootView.swift:169` and `:174` from `managedJournal` and `model.journalsPresented`. `managedJournal` is never assigned (`RootView.swift:30` is its only declaration, `:265` only clears it) and `journalsPresented` is never set to true (`Model/AppModel.swift:226`; `RootView.swift:264` and `ReviewRequestTiming.swift:148` read or clear it). Open question C2. |
| `RootView.managedJournal`, its sheet (`:169`), the `journalsPresented` sheet (`:174`) and the two resets (`:264`, `:265`); `AppModel.journalsPresented`; its use in `AppModel.reviewMomentIsClear` (`Model/ReviewRequestTiming.swift:148`) | Same: nothing sets them. |
| The Delete Journal mode of `Views/JournalLifecycleView.swift` (`restoring == false`: title at `:25`, the destructive button at `:117-131`, the plan and commit at `:250-290`) | Its only callers that pass `restoring: false` are `JournalSettingsView.swift:80`, itself dead. `Views/DeletedJournalView.swift:39` and `Views/EntryRecoveryNotice.swift:28` pass `restoring: true`. Open question C3. (N then removes the rest of the file.) |
| `settings.devices.locked` and its branch in `Views/DevicesView.swift` | `SettingsView.body` shows `settings.locked` for the whole pane before `DevicesView` is built (`SettingsView.swift:19`). |
| `noteLaunch`, `ReviewUsage.firstUse` and `lastRequestVersion`, and the sync callers of `ReviewRequests.noteProblem` | Made dead by F (section 3). `noteProblem` and `problemThisSession` stay for the three on-screen causes. |
| `AppSettingsTab.devices`, `DevicesView`'s own reconnect button, `settings.pane.devices`, `settings.devices.notConnected` | Made dead by E. |
| `JournalError`/`EntryDateError.saveRequired`/`ImageDescriptionError.entrySaveRequired` wording and the 20 save-before keys | Made dead by B. |

**Dead once the other 1.1 simplifications land** (listed so nothing is missed; their own records say how): `AppModel.journalRecords` after the dead sheet goes (only `JournalTests/PinnedListTests.swift:52` still uses it, so that test moves to `model.journals`), and the model functions and views K, L, M, N and H name in [1-1-library-simplifications.md](1-1-library-simplifications.md).

**Candidates to check before removing (not proven dead, or kept for a reason)**

| What | Why it is only a candidate |
| --- | --- |
| `JournalStore.setEntryArchived`, `EntryArchivingError`, `Packages/JournalCore/Sources/JournalCore/EntryArchiving.swift`, `EntryArchivingTests`, `JournalProbe/ArchivingProbe.swift` | No app code calls it; Archive was removed by owner decision. Probes and tests still use it to check that an `archivedAt` written by an earlier build syncs. The field stays in the data model. Keep the writer function and its probe as a fixture (they check that an `archivedAt` written by an earlier build syncs) unless the owner says otherwise. |
| `JournalStore.restoredTitle(of:)` (`JournalNames.swift:106`) | Used only by `JournalNameTests.swift:60`; its caller, the restore sheet, is removed by N. |
| `PermanentDeletionConfirmation.historicalOnlyEntryCount` | Used only by one test. |
| `RichText.formattingState` (`Editor/RichText.swift:83`), `DocumentTransferOperations.finishPreparing`, `StoreCheckpoints.useClock`, `libraryChanges`, `setLibraryValues`, `sealedPayload` | Used only by tests as seams; fine to keep, listed for completeness. |
| Texts in code with catalog rows but no reachable path (open question B15): `messages.server.syncRequestFailed`, `.imageUploadFailed`, `.revokeFailed`, `.cancelPairingFailed`, `messages.library.itemUnavailable`, `messages.entry.archiveChanged`, `messages.conflict.journal.chooseOne`, `messages.password.enterMaster`, `messages.connection.invalidRecoveryCode`, `messages.error.invalidSetupCode` | Each string exists in code (`ServerClient.swift`, `Pairing.swift`, `StoreLibrary.swift`, `EntryArchiving.swift`, `Store.swift`, `NewVault.swift`, `ServerEnvelopeCheck.swift`, `Models.swift`) behind a branch another check makes unreachable; B15 argues each case. Removing a branch is a behaviour change if the argument is wrong, so each needs a test or a trace first. |

The Swift tooling already forbids unused imports and warns on unused code it can see; the hygiene lane catches none of the above because every item is used by something that is itself unreachable.

## 9. Tests worth adding

Following [AGENTS.md](../../AGENTS.md) ("Useful tests only"): each protects a behaviour that has gone wrong or plausibly will.

1. **Save first** (`JournalTests`, one table-driven test): with `saveFailure` true and writes rejected, each remaining operation (Move Entry, name sheet, Version History restore, Export Archive, Export as Markdown, Import Archive, Connect to a Server, restore of an entry, template and journal, Delete Journal, Delete Permanently) throws `JournalError.saveRequired` and changes nothing in the library. The alert shows `tryAgain` while `saveFailure` is true, every other presenter shows `goBack`, and when the save succeeded before the alert was drawn no save message shows at all. Replaces the literal in `FailureMessageTests`.
2. **Rating** (`ReviewRequestTests`): the rules table now has two rows to cross (five writing days, 120 days) with their boundaries, and a stored 1.0 record (with `firstUse` and `lastRequestVersion`) decodes and still spaces asks by `lastRequest`. A live problem (a sync state that needs the person) blocks the moment and a sync problem that has gone does not; an error, a failed save or a conflict earlier in the session still blocks asking for the rest of the session. The `JOURNAL_UI_TEST_REVIEW` record is built without `firstUse`. The tests for the removed sync callers go.
3. **Inline styles** (`FormattingRuntimeTests`): for each of the five styles, selections that are none, some and all styled: the result is on unless all were, on both the Mac and iOS code paths, in a table cell, and the shown state equals the action: after one press the shown state is On for a heading plus a bold paragraph, a struck selection across a line break typed without the style, and a selection with an image. On iOS the test calls the responder actions `toggleBoldface(_:)`, `toggleItalics(_:)` and `toggleUnderline(_:)` on the text view, not only the app's command.
4. **Return in a heading** (`EditorTests` or `TypingRoomTests`): start, middle, end and empty for each of the six levels; the tail's new identity and the level; reading the document twice gives the same two IDs; undo restores the single original ID in one step and redo the two; typing attributes after a split are the heading's; selection replaced first; Return during composition only commits; the Markdown of the result; a typed key burst.
5. **Table menus** (`TableEditorTests`): the Mac cell menu, Format ▸ Table (Mac and iPad) and the iOS edit menu are built from the one list (same titles, order, submenu, destructive flags), the current alignment is the checked item (Left for a column with none), and no list is built for a read-only entry.
6. **Decline** (`AgentRequestDeclinesTests`, fake server): the status mapping of 7.2 (2xx and request-not-found are done; a network error, not authorised and other statuses fail; cancel shows nothing); a failed decline brings the row back with the message; success removes it and announces once; a refresh during an in-flight decline does not show the row; closing Settings (the controller going away) does not cancel the decline; Erase and Stop Syncing do; locking clears the message but not the task.
7. **Settings** (existing UI journeys, not new ones): `SyncRecoveryUITests` asserts that after Connect Again the Devices section lists devices without reopening the pane; `JournalUITests` reads the added-by lines in Sync; the capture tests tap General and Sync only.

No test is added for copy strings, pane order, menu symbols or the dead-code removals (the compiler and the spec checker cover them).

## 10. Spec, notes and documentation checklist

For the implementer, in the same change as the code ([spec/README.md](../../spec/README.md)); run `python3 spec/tools/check-spec.py` and `mise exec -- scripts/format.sh` after.

- `spec/copy/en.json`, `spec/copy/same-wording.json` (the two new save messages share no text with any other; the three removed Mac alignment keys leave no group behind).
- `spec/screens/`: `settings.md`, `settings-general.md`, `settings-sync.md`, `settings-devices.md`, `settings-about.md`, `settings-agent-access.md`, `allow-agent.md`, `format-sheet.md`, `connect-to-server.md`, `scan-code.md`, `add-device.md`.
- `spec/flows/`: `save-failure.md`, `save-entry.md`, `rating-request.md`, `editing-rules.md` (F-1, F-3, F-6, N-8, TB-4), `edit-table.md`, `allow-agent.md`, `sync-recovery.md`, `reconnect-to-server.md`, `markdown-as-you-type.md`, `turn-on-encryption.md`.
- `spec/messages.md`, `spec/commands.md`, `spec/parity.yaml`, `spec/open-questions.md` (A14, A39, A43, B1, B4, C2, C3, D5, D6, D7, D55 marked built or resolved in 1.1; a new C item for the Windows pages).
- `spec/platforms/apple/`: the pages named in 1.10, `commands.md`, `flows/edit-table.md`, `flows/rating-request.md`, `flows/save-failure.md`, `flows/allow-agent.md`, `messages.md`, `screens/allow-agent.md`, `screens/settings-agent-access.md`, screenshots by `design/spec-screenshots/capture.sh iphone ipad mac`.
- Windows mapping: only the false statements (1.10).
- `docs/guide/`, `docs/app-store/review-notes.md`, `docs/design/README.md` (this record and its review).
- Code, by feature: `Views/SettingsView.swift`, `Views/DevicesView.swift` (moved into a Devices section view), `Model/AppModel.swift`, `Model/SyncHealthOperations.swift`, `Views/SaveFailureNotice.swift`; `Model/*Operations.swift` listed in 2.1 and `Model/FailureMessage.swift`; `Model/ReviewRequest*.swift`; `Editor/MarkdownEditing.swift`, `Editor/RichTextRuns.swift`, `Editor/NativeEditor.swift`, `Editor/TableCellFormatting.swift`, `Editor/FormattingState.swift`; `Editor/RichText.swift`; `Editor/TablePresentation.swift`, `Editor/InlineTableGridMac.swift`, `Editor/InlineTableGridIOS.swift`, `AppCommands.swift`; `Views/ServerAgentsView.swift`, `Model/ServerAgentsController.swift`, `Model/AgentRequestDeclines.swift` (new), `Editor/NativeTextView.swift`, `Editor/NativeTableIntegration.swift`, `Views/RootView.swift` (the alert).

## 11. Decisions for the owner

None remain.

- Erase Journals and Settings… stays its own last section on iPhone and iPad, as the owner decided in [erase-device-2026-10-04.md](erase-device-2026-10-04.md) §11 (1.2).
- The rating numbers (five days, 120 days) and Return at the very start of a heading are decided here by convention (3.3, 5.2).
- D55 is read as the Agent Access page showing the message, with the sheet closing at once, which is what the owner's decision says (7.2).

## 12. Risks

- **E.** The Sync tab is long on the Mac; it has a fixed height and scrolls, and sheets (Add Device, Connect) must still fit the 440-point minimum. A row with a trailing Revoke Access… button must keep both targets usable at the largest Dynamic Type size (the button moves under the text); the implementer checks it on a device.
- **E and G, I.** If G or I land first and change the Privacy pane or the reconnect action, only the placeholders in 1.6 move; the structure here does not depend on their wording.
- **B.** The alert draws from a typed error and `saveFailure` at the same moment, so two sites that still assign a string show the longer `goBack` text; that is wordier but never says "Choose Try Again" without a button. For Image Descriptions, `goBack` asks the person to leave a sheet that can only be cancelled; the state is a race that needs a save to fail while the sheet is open (the editor is read-only behind it), and Copy Descriptions stays visible.
- **F.** The session guard covers errors, failed saves and conflicts; a sync problem that has gone no longer blocks asking. The clear check still covers every problem on screen at the moment of asking.
- **D5.** Overriding `toggleBoldface(_:)`, `toggleItalics(_:)` and `toggleUnderline(_:)` must catch every UIKit route (edit menu, hardware keys, Writing Tools). If a route escapes, the fallback in 4.2 (turn off `allowsEditingTextAttributes`, offer the app's own actions) applies; the rule is never relaxed. UIKit's own rule for a mixed selection was not run here.
- **D6.** The tail's identity and the line break must be one replacement, or undo takes two steps and a half-made split can be saved; test 4 covers it.
- **D7.** The iOS editor does not wire `editor.tableAction` for the menu bar today, so Format ▸ Table on iPad needs that wiring and a device check that it enables with the caret in a cell.
- **D55.** A decline that fails after Settings closed shows nothing; the request is still listed at the next visit and expires on the server after 10 minutes. The new session-lifetime object must not hold a request past Erase or Stop Syncing.
- **Windows.** The Windows mapping describes six panes and a Writing/General variant until the Windows agent updates it; this change does not edit those pages beyond the false statements.

## Changes after review

Every finding of the review below, and what the record now says. Section numbers are this record's.

| # | Finding | What changed |
| --- | --- | --- |
| 1 | Erase moved against the owner's earlier decision | Reverted. Erase stays its own last section on iPhone and iPad and the last group of the Mac's General; E is only the rename and the Devices move. Summary, 1.2 (sketch and "Why General everywhere"), 1.3, 1.9, 1.10 and section 12 changed; the pushed-pane `dismiss` risk and the `settings-erase.md` change are gone. The owner question is removed, because the owner already decided (section 11). |
| 2 | UIKit's Bold, Italic and Underline routes stay live on iPhone and iPad | 4.2: `JournalTextView` overrides `toggleBoldface(_:)`, `toggleItalics(_:)` and `toggleUnderline(_:)` to run the shared command and answers `validateCommand` / `canPerformAction` for the edit menu's state; the fallback if an override is unreliable is turning off `allowsEditingTextAttributes`. Test 3 calls the responder actions. Risk added. |
| 3 | The shown state and the action count different characters | 4.2: one predicate `carries(style, attributes)` (Bold not headings; all five not code blocks or image placeholders; line breaks never decide) used by `FormattingState` and by the command. Test 3 asserts that after one press the state is On for a heading plus a paragraph, a struck selection across a line break, and a selection with an image. |
| 4 | The decline task cannot be owned by a view-lifetime controller | 7.2: a session-lifetime `AgentRequestDeclines` held by `AppModel` owns the in-flight set, tasks and message; it cancels on Erase and Stop Syncing, not on lock or when Settings closes. The status mapping is a table (2xx and request-not-found done; network, not authorised, outdated and other statuses fail; cancel shows nothing). Test 6 covers the mapping and the lifetime. |
| 5 | Table commands unreachable from a keyboard on iPad | 6.2: Format ▸ Table is added to the iPad menu bar from the same definition (the `#if os(macOS)` goes; the iOS `tableAction` wiring is named); the risk bullet is replaced by an implementation risk. The current alignment is checked in all renderings. Summary and test 5 updated. |
| 6 | There is no single alert path in B | 2.2: the six alert sites call `report(_:)`, which keeps the typed error; `RootView` draws the alert while `saveRequiredAlert` and `saveFailure` are both true and chooses `tryAgain` at that moment; if the save has succeeded, nothing shows. `goBack` is the fallback for every other presenter and for any site that still assigns a string. Test 1 covers "succeeded before the alert showed". |
| 7 | D6 does not say where the new heading's identity is made | 5.2: one replacement from the caret to the end of the heading carries the line break and the tail's new `journalBlockID`; the first half keeps the old one; the heading's typing attributes (no link) follow a split. Test 4 reads the document twice and checks undo and redo of the IDs. |
| 8 | D6 gaps | 5.2: (a) Return in an empty heading makes it a paragraph; (b) text is not trimmed, and the leading space is dropped by the Markdown writer as for any heading; (c) one line on exclusive kinds and unchanged import; (d) composition only commits, with a test; (e) unchanged. |
| 9 | Settings structure details | 1.4: one Devices section with one header, Add Device… first, one row per device with a trailing Revoke Access… (VoiceOver: one heading, N rows); the Mac Sync tab has a fixed height (the smaller of 640 points and the room the screen allows) so the window does not jump. The path text says "Settings ▸ Sync ▸ Devices ▸ Add Device", so no "scroll to Devices" wording is needed. |
| 10 | Save messages need plainer text | 2.2: `tryAgain` is "Your changes aren’t saved yet. Choose Try Again, then repeat what you were doing."; `goBack` is "Your changes aren’t saved yet. Go back to your entry, choose Try Again under Not Saved, then repeat what you were doing." The Mac Settings window case is named in the Mac note of `spec/platforms/apple/messages.md` ("go back" there means switching to the journal window); no Mac variant. Copy Descriptions stays visible. |
| 11 | F drops a guard Apple names | 3.3: `problemThisSession` stays for the three on-screen causes (error, failed save, conflicts) and goes for sync, which the live `showsSyncStatus` check covers. Five days and 120 days are decided here; the owner question is removed. The `JOURNAL_UI_TEST_REVIEW` seam and test 2 are updated. |
| 12 | D55 copy and presentation | 7.2 and 7.3: the text is "Couldn’t decline the request from {name}. Open it and choose Don’t Allow to try again."; the message uses the pane's ordinary secondary error style and is announced once; the owner question is removed (settled by D55's own words). |
| 13 | Dead-code section | 8: the Delete Journal mode is dead but `prepareJournalDeletion` and `deleteJournal` stay (said in the method note); `JournalSettingsView`'s identifiers are referenced by no UI test; the model functions it called were traced and are live; `setEntryArchived` and its probe are kept as a fixture unless the owner says otherwise. |
| 14 | Copy and catalog | 1.9: the path form is "Settings ▸ Sync ▸ Devices ▸ Add Device"; the changed not-connected footer is kept, links on their own line. 1.7: the Devices error uses the Backup pane's `JournalAccessibility.announce` and Try Again keeps focus. 7.3: `{name}` uses `AgentDisplayName.clean` and is data, never an instruction. |
| – | Minor: the "6 + 10" count | 2.2 says the first table row has 6 sites, the second 10 other sites, one site (Move Entry's) shared, 16 in all. |
| – | Re-review | The review says it is not needed if findings 1 to 7 are answered in the text; they are, and Erase's layout is unchanged from today. |

## Independent review (2026-10-09)

Reviewer: independent design agent, given the owner-approved scope (E, B, F, D5, D6, D7, D55, A), the proposal and `apps/apple/AGENTS.md`. File references and dead-code claims were checked against `apps/apple` and `spec/`; where the proposal is right, the review says so briefly, and where it is wrong or incomplete the finding says what the code shows. No simulator or build was run.

**Verdict: approve with changes.** No Blocker. The shape of E, B, F, D5, D6, D7 and D55 is sound, and the dead-code inventory is accurate. Seven Material findings need a text change or a decision before implementation: Erase is moved against the owner's own earlier words (1), D5 is not enforceable on iPhone and iPad because UIKit's own Bold, Italic and Underline routes stay live (2), the shown Mixed state and the action disagree for headings, line breaks and images, so the Mixed control can never reach On (3), the D55 controller does not live as long as the proposal says (4), the table menu is unreachable from a keyboard on iPad (5), the "one alert path" for the save messages does not exist (6), and the D6 block identity is not specified where the code decides it (7). A second full review is not needed; findings 1, 2, 3 and 4 change specified behaviour, so the owner should see the revised text of those four when answering the decisions.

### Claims checked and found correct

- Dead code: nothing assigns `RootView.managedJournal` or sets `AppModel.journalsPresented` to true (`RootView.swift:30, 169, 174, 264-265`; `AppModel.swift:226`; `ReviewRequestTiming.swift:148` only reads it). `JournalNameField` and `JournalNameTakenMessage` are used only inside `JournalSettingsView`. `JournalLifecycleView` is built with `restoring: false` only from `JournalSettingsView.swift:80` (`$0.deletedAt != nil` can be false); `DeletedJournalView.swift:39` and `EntryRecoveryNotice.swift:28` pass `true`. `settings.devices.locked` is unreachable (`SettingsView.swift:17` shows the locked text for the whole pane first). `journalRecords` is used only by the dead view and `PinnedListTests.swift:52`.
- Everything `JournalSettingsView` reached is still reachable elsewhere: `changeJournal(name:)` and `changeJournal(template:)` from `JournalMoreMenu`, `JournalSidebarView` and the Mac window; `JournalHistoryView` from four other places; Delete Journal through `JournalDeletionPrompt`. Removing the view loses no feature.
- `prepareJournalDeletion` and `deleteJournal` stay alive (`JournalDeletionPrompt.swift:56, 64`, five test files), so the Delete Journal rows in the B table are right even though the Delete Journal mode of `JournalLifecycleView` is dead. Say so in the record so nobody deletes the model functions (finding 12).
- The 25 code sites and 16 survivors of B add up. The "6 + 10" split counts Move Entry's site twice (it appears in both lists), so the sentence should read "6 alert sites and 10 others, one of which can show either"; trivial.
- F: the five `noteProblem()` callers match the proposal, and `showsSyncStatus` (`connection != nil && (syncNeedsAttention || syncLongWait)`) is the same condition as the two sync callers (`syncHealth.kind != .temporary`, long wait), plus `syncError`. Sound replacement for those two.
- D5, D6, D7 current behaviour is described correctly: `RichText.toggling` (Mac, ignores headings for Bold), `MarkdownEditing.toggle` (first character, `replacement.attribute(key, at: 0)`), `newlineAction` heading branch, three different table menus (`InlineTableGridMac.swift:195`, `AppCommands.swift:200`, `InlineTableGridIOS.swift:191`). Mac and iOS both reach `RichText.newlineAction` (`NativeEditor.swift:313, 802`; `MarkdownShortcutEditing.swift:121`).
- Mixed turns on is the platform convention (TextEdit, Pages and Notes turn a mixed selection fully on), so D5 matches what people expect.

### Material

1. **Material: decision 1 reverses an explicit owner instruction, and E does not need it.** [erase-device-2026-10-04.md](erase-device-2026-10-04.md) §11 records the owner's words after testing build 15: Erase "is a standalone function", it was "in the wrong place" inside a pane it was unrelated to, and the decision was the last section of the iPhone and iPad list. Putting it into General, a pane of two settings, re-files it under a pane whose name says nothing about it, which is the complaint the owner made about Privacy. The proposal's argument (one name everywhere, Windows has it in General) does not require the move: renaming Writing to General is E; where Erase sits is separate, and the Mac already has it in General because its window has no list level. iOS Settings itself does not bury Reset in a form: Transfer or Reset iPhone is a row of General that pushes its own page. Fix: rename the pane to General everywhere (E) and keep Erase as the last section of the iPhone and iPad list, with the Mac and Windows placement unchanged; record the one remaining difference in "Differences between iPhone, iPad and Mac". Keep decision 1 as a real owner decision, with this as the recommendation, because it overturns §11. This also removes the pushed-pane `dismiss` risk in section 12 and the change to `settings-erase.md`.

2. **Material: D5 cannot be enforced on iPhone and iPad while UIKit's own routes stay live.** Section 4.2 says every route calls the shared function and the three UIKit toggles are not used for a non-empty selection. But the text view sets `allowsEditingTextAttributes = true` (`NativeEditor.swift:528`) and nothing overrides `toggleBoldface(_:)`, `toggleItalics(_:)` or `toggleUnderline(_:)` (the only occurrences are the three calls at `NativeEditor.swift:937-943`). The system edit menu's B, I and U buttons, and any hardware ⌘B, ⌘I or ⌘U that UIKit handles before the app's `UIKeyCommand`s, call those responder actions directly, with UIKit's undocumented mixed-selection rule, so the control and the action disagree again and only on iPhone and iPad. Fix: override the three responder actions in `NativeTextView` to run the shared command (and `validate` them so the menu shows On, Off, Mixed from `FormattingState`); say that in 4.2; and make test 3 call the responder action, not only the app's command. If the overrides cannot be made reliable, turn `allowsEditingTextAttributes` off for the editor and offer the app's own Format actions in the edit menu.

3. **Material: the shown state and the action disagree for characters that cannot carry a style, so a Mixed control never reaches On.** Section 4.2 says characters that cannot carry the style are not counted, "from the same `FormattingState`". `FormattingState` does count them as Off: Bold samples every attribute run and maps a heading to `false` (`FormattingState.swift:48-52`), and line breaks and attachments are ordinary samples for all five styles. A selection of a heading and a bold paragraph therefore shows Mixed, while `RichText.toggling` ignores the heading, finds every applicable run On, and turns Bold off. Pressing a Mixed Bold with a heading in the selection also turns it on for the paragraph only, and the control still reads Mixed afterwards. The same happens to Strikethrough and Inline Code over a line break typed without the style (the case the proposal names) and over an image placeholder or a code block (F-5). Fix: one predicate, `carries(style, attributes)`, used by `FormattingState` for what it samples and by the toggle for what it changes (Bold: not headings; all five: not code blocks, not image placeholders; line breaks only when they have the style on both sides or the selection ends on them); state in F-1 what cannot carry each style; add to test 3 an assertion that after one press the shown state is On, for a heading plus paragraph, a struck selection across a line break, and a selection with an image.

4. **Material: the Don't Allow task cannot be "owned by the controller" as the code stands.** Section 7.2 says the controller keeps the set of requests being declined and that leaving Settings does not cancel the decline. `ServerAgentsController` is a `@StateObject` of `SettingsView` (`SettingsView.swift:8`), so it is destroyed when the Settings sheet or window closes, and `clear()` cancels its tasks (`ServerAgentsController.swift:141-147`). The decline would be cancelled exactly in the case the proposal wants to protect, or would outlive its owner (AGENTS.md: no unowned long-running tasks). The proposal also never says how "the request is gone" is told apart from "anything else" (which status codes `publisher.decline` maps), and never says what happens on the Mac, where the Settings window can stay open but hidden. Fix: put the in-flight set and the task in an object that lives as long as the app session (`AppModel` or a small owner it holds), cancel on Erase and on Stop Syncing, not on lock (as the proposal says), and let the Settings controller read it; name the status mapping (accepted and gone are done, a network error or any other status is a failure) and put a test on the mapping, not only on the controller (test 6).

5. **Material: the table commands are unreachable from a keyboard on iPad.** Section 6.2 leaves out Format ▸ Table on iPad because "people with a keyboard use the cell's edit menu". The edit menu opens by touch or pointer; there is no key that opens it, so a person using a hardware keyboard with Full Keyboard Access, Switch Control or Voice Control for dictation has no route to add or delete a row, a column or the table. Since D7 makes one definition rendered by adapters, the iPad menu bar is a third `Menu` over the same list (the `#if os(macOS)` guard at `AppCommands.swift:200` and `editor.tableAction` are all that stop it), enabled only while a cell is being edited. Fix: add Format ▸ Table to the iPad menu bar in the same change and remove the risk bullet. Also mark the current alignment with a checkmark in the Alignment submenu in all three renderings (the proposal specifies none), so the menu shows what the cell has, as Format menus do.

6. **Material: B's "AppModel's one alert path" does not exist, and the alert's Try Again can be gone when the text is read.** Section 2.2 picks the alert text "in the place that turns an error into `model.error`". `model.error` is a `String?` assigned at about 25 sites through `error.shown(.saving)` or literals (`AppModel.swift:403, 420, 646, 657, 775, 785`, `JournalEditing.swift:64`, `EntryDeletionOperations.swift:41, 86, 138, 156` and others), and sheets show their own inline text. The alert shows `Try Again` only `if model.saveFailure` (`RootView.swift:113`), evaluated when the alert is drawn. The text is chosen when the error is thrown. If the retry that runs on every edit succeeds in between, the alert says "Choose Try Again" and has only OK. Fix: keep the typed error (`JournalError.saveRequired`) until the alert is drawn, or let `FailureMessage` take the surface as a parameter, and choose the wording where `saveFailure` is read; make `goBack` the fallback for any presenter that does not say it is the alert, and say that in the record; test 1 should also cover "the save succeeded before the alert showed", which should show no save message at all.

7. **Material: D6 does not say where the new heading's identity is made, and the code makes identities in a way that would hide the bug.** Block identity is a `journalBlockID` attribute on the characters (`RichText.swift:288, 394, 712`). `RichText.document` replaces a repeated ID with a fresh random one on every call (`RichText.swift`, the `seen` loop at the end of `document`). If the split gives both halves the same attribute, the second half gets a different random ID each time the document is read, so history, conflict detection and sync see a block that changes identity on every save. The proposal's risk bullet names the problem but the behaviour table does not fix it. Fix: say in 5.2 that the replacement covers the text from the caret to the end of the heading (so the tail's new ID attribute and the line break are one replacement and one undo step), that the tail is given a new UUID in its attributes, and that the first half keeps the old one; test 4 must read the document twice and compare IDs, and undo and redo must restore the original single ID. Also say that the typing attributes after the split are the heading's (not a paragraph's, as `nextKind: "paragraph"` sets today) without a link, so typing at the start of the second heading does not make it a paragraph again.

### Minor

8. **Minor: D6 gaps in the table.** (a) Return in an empty heading leaves an empty heading behind and adds a paragraph (exported as `## `); list items leave the list in that case (N-3), and the same exit is cheaper and consistent: Return in an empty heading turns it into a paragraph. (b) Characters are not trimmed, so the second heading can start with a space; the Markdown writer drops it on round trip, so the "round-trips with the same two headings" sentence holds for blocks but not for the exact text. Trim one leading space of the tail, or say it is accepted. (c) A heading cannot also be a list item or a quote in this model (kinds are exclusive), so "lists inside headings" is not a case; say it in one line, with what import does with `> # Title` (not checked here). (d) Return while text is being composed (marked text) must commit the composition and not split; say so and test it once. (e) A selection that crosses blocks stays as today: fine.

9. **Minor: Settings structure.** The two-pane shape is native (Mail, Notes and System Settings all have General first and an account-like pane second) and Stop Syncing last matches Sign Out in iOS Settings. Three details. (a) A header over the first of several grouped sections reads as heading only that device; use one Devices section whose rows are the devices (name, "This Device", how added as one element), with Revoke Access… as each other device's trailing action or on its row's detail, as the device list in Apple ID does, and Add Device… as the last row. That is also a better VoiceOver result: one heading, N rows. (b) The Mac tabs are as tall as their content (`SettingsView.swift:83-92`), so when the device list arrives after the pane opens, the Sync tab changes height and the window jumps; give Sync a stable height (for example its maximum) or reserve the Devices section while it loads. (c) Add Device… is a frequent first task after connecting and sits below N device cards; if the list is long on iPhone it is two scrolls away. Acceptable, but consider Add Device… first in the Devices section, as the Mac Accounts pane does, and let the "choose Add Device" text in the path messages say "scroll to Devices" on iPhone and iPad.

10. **Minor: the two save messages need a plainer second sentence.** "then do this again" does not say what "this" is, and "Choose Try Again to save them, then try again" is what a reader will say aloud; the Not Saved notice and the alert use the words "Not Saved" and "Try Again", so use them. Suggested: `messages.save.before.tryAgain` "Your changes aren’t saved yet. Choose Try Again, then repeat what you were doing." and `messages.save.before.goBack` "Your changes aren’t saved yet. Go back to your entry, choose Try Again under Not Saved, then repeat what you were doing." "Go back to your entry" is wrong for the Mac Settings window (a separate window, not a sheet); either say "Switch to your journal window" for the Mac Settings sites or accept "Go back" and name it in the Mac note. For Image Descriptions the sheet can only be cancelled; keep Copy Descriptions visible (as proposed) and let the notice say nothing more.

11. **Minor: F drops a guard that Apple's guidance names, cheaply.** The live `showsSyncStatus` check is a faithful replacement for the two sync callers, and the moment itself (edit, leave, two quiet seconds, clear screen) is right. What it gives up is "not right after something went wrong": a person who fixed a sync problem five minutes ago, or dismissed an error alert, can be asked as soon as they leave the next entry. Either accept this (the proposal says so, and the system prompt is capped at three a year), or keep `problemThisSession` for the three on-screen causes only (error, failed save, conflict) and drop it for sync, which `showsSyncStatus` covers. Decision 2 is not an owner question: five days against four is tuning; decide and record it. The `JOURNAL_UI_TEST_REVIEW` seam (`ReviewRequestTiming.swift:48`) builds `ReviewUsage(firstUse:)` and changes with the field; add it to section 9 test 2.

12. **Minor: D55 copy and presentation.** "Check your connection and try again" is wrong when the server answered with an error; use "Couldn’t decline the request from {name}. Open it and choose Don’t Allow to try again." The proposal makes the message red, but the neighbouring error lines (`DevicesView` error, Backup) are secondary text; use the existing error style and do not rely on colour (the announcement and the words carry it). The announcement of success after the sheet has closed, seconds later, is fine for VoiceOver; keep it a single announcement and do not move focus. Decision 4 is mostly settled by D55's own wording ("the page shows a short message and the request stays"); confirm it in one line rather than as an open question.

13. **Minor: the dead-code section.** Add to the inventory: the Delete Journal mode of `JournalLifecycleView` is dead but `prepareJournalDeletion` and `deleteJournal` are live (finding in the checked list); `JournalSettingsView`'s accessibility identifiers (`journal-default-template-…`, "New journal name") are referenced nowhere else, so no UI test changes. The method note (a name search plus a manual trace) is honest; the trace for `JournalSettingsView` stopped at the view, so state that the model functions it called were checked and are still live. The candidates table is correctly conservative; keep `setEntryArchived` and its probe as a fixture (it checks that an `archivedAt` written by an earlier build syncs) unless the owner says otherwise.

14. **Minor: copy and catalog.** (a) "Settings ▸ Sync, then choose Add Device" mixes a path with an instruction; "Settings ▸ Sync ▸ Devices ▸ Add Device" is one form and matches the catalog contexts. (b) The changed `settings.sync.footer.notConnected` text is good plain language; keep the Learn More and setup links on their own line. (c) Section 1.7 says a Devices error is announced; say that it uses the same `JournalAccessibility.announce` as Backup and that Try Again keeps focus. (d) `settings.agents.requests.declineFailed` contains `{name}` from an agent-supplied client name; it is already cleaned for the row (`AgentDisplayName.clean`), so say the same cleaning is used and that the name is data, not an instruction (AGENTS.md).

### Questions asked in section 13

- Five panes, Erase inside General, Devices below Server and Changes to Review: the order is right and Erase belongs where it is today (finding 1). One Devices header over per-device cards: no, use one section (finding 9).
- Save messages: clear enough for a reader who knows "Not Saved" and "Try Again"; reword as in finding 10, fix the mechanism in finding 6.
- Rating rule: an acceptable reading of Apple's guidance; see finding 11.
- Mixed turns on: yes, it is the platform convention, but only if the state and the action count the same characters (finding 3) and the system routes are covered on iPhone and iPad (finding 2).
- Split at the caret, plain paragraph above at the very start: yes, and consistent with N-3. Decide it by convention; it is not an owner question.
- Sheet closes and the page reports the failure: yes, if the task outlives the Settings view (finding 4).

### The four owner decisions

1. Erase placement: a genuine owner decision, because it reverses the owner's own words (finding 1). Recommend keeping the iPhone and iPad placement.
2. Five days and 120 days: not an owner decision; decide by judgement. The only real change is the loss of the one-week floor and the session memory (finding 11).
3. Return at the very start of a non-empty heading: decide by convention. The plain paragraph above is right, matches N-3 and avoids an empty heading in Markdown.
4. D55 reading: already settled by D55's text; confirm in one line.

### Re-review

Not needed if findings 1 to 7 are answered in the text. Re-review only if the owner chooses to keep Erase in General and the section 1 layout changes materially.
