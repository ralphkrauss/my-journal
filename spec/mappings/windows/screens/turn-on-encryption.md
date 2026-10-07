---
id: turn-on-encryption
title: Turn on encryption, task page (Windows)
spec: screens/turn-on-encryption.md
features: [turn-on-encryption]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
  - https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate
---

# Turn on encryption, task page (Windows)

A three-step task page that encrypts the journals on this PC and its server with a new master password. It cannot be undone. Behaviour and copy keys are the spec's [Turn On Encryption](../../../screens/turn-on-encryption.md); the work and every error are the [turn-on-encryption flow](../flows/turn-on-encryption.md). The field, error and busy patterns are in [settings](settings.md#dialog-patterns). It is a page, not a dialog, because it has progress, a back arrow and a title per step ([platform.md, 9](../platform.md#9-sheets-popovers-and-notices)).

## Controls

A task page in the window's content area ([platform.md, 9](../platform.md#9-sheets-popovers-and-notices)) with a `Frame` of three steps: the title bar's back button where the spec allows Back, the step's title as the page heading (level 1), a column at most 640 epx wide and scrolling, and a footer row of the step's buttons (primary first, then Cancel `common.cancel`). Navigation and the menu bar's commands are disabled while it runs. Esc is not bound; closing the window follows the one rule of [platform.md, 3](../platform.md#3-windows-and-instances).

### Step 1: Turn on encryption

Page heading `settings.encryption.title`.

| Spec element | Control |
| --- | --- |
| Intro | `TextBlock`: `settings.encryption.intro`, or `settings.encryption.introSynced` when syncing |
| Your other devices (syncing only) | A heading `settings.encryption.otherDevices.header` (level 2) and three paragraphs: `settings.encryption.otherDevices.update`, `settings.encryption.otherDevices.signIn`, `settings.encryption.otherDevices.agents` |
| Footer | `Caption` text `settings.encryption.pauseFooter` |
| Checking (syncing only) | A `ProgressRing` and `settings.encryption.checking` |
| Error | An `InfoBar` (Error) at the end of the step |
| Buttons | Primary `common.continue`; after an error `common.tryAgain`; when the error is that encryption was turned on from another device `common.signIn`, which leaves this page and opens the Connect task page at signing in. Disabled while working. Cancel `common.cancel` |

### Step 2: Choose a master password

Page heading `common.chooseMasterPassword`. Back, only here and only when not working.

| Spec element | Control |
| --- | --- |
| Intro | `settings.encryption.passwordIntro`, or `settings.connect.choosePassword.intro` when syncing |
| Current access password (libraries from early versions) | A heading `settings.encryption.currentAccessPassword` and a `PasswordBox` named by it, with its field error (`messages.encryption.incorrectPassword`, `messages.encryption.rateLimited`) |
| New password | `PasswordBox` `common.masterPassword`; `PasswordBox` `common.verify`; each with its field error; `messages.connection.passwordsDontMatch` on Verify |
| Show password | A `CheckBox` `common.showPassword`, or `settings.encryption.showPasswords` when the current access password is also shown ([Show password](settings.md#show-password)) |
| Footer | `settings.password.footer` |
| Status row while working | `settings.sync.syncing` with a `ProgressRing`; or the encryption progress: `settings.encryption.progress` above a determinate `ProgressBar` named `settings.encryption.progressLabel` whose `AutomationProperties.ItemStatus` is `settings.encryption.progressValue` ("{percent} percent"); or `settings.encryption.updatingServer` |
| Error | An `InfoBar` (Error) |
| Buttons | Primary `settings.encryption.turnOn`, or `common.tryAgain` after an error, or when unfinished (finishes it). Disabled until both new fields (and the current access password if shown) are filled, and while working. Cancel `common.cancel`: stops the work while the server is not being updated, and returns; disabled while updating the server; not shown while unfinished |

Fields are disabled while working and while unfinished. Passwords are cleared once encryption is on.

### Step 3: Your journals are encrypted

Page heading `settings.privacy.encryption.on`. Icon ShieldLock (F5B4, 48 epx, decorative); `settings.encryption.done.message`. When syncing: a heading `settings.encryption.otherDevices.header`, `settings.encryption.done.otherDevices`, a `HyperlinkButton` `settings.connect.ready.addDevice` and the footer `settings.encryption.done.archives`; otherwise only the footer. `common.done`, the default button (Enter finishes; no other primary button). Add another device… opens the [Add device](add-device.md) dialog over this page, which stays on this step; the work is complete.

### Unfinished, and where the page shows

The work belongs to the app, not to the page: the page can only be left when the work can still be cancelled or has finished, and opening it again (Turn on encryption in Settings > Privacy, which is the card's button while work is running or unfinished) shows where the work is. Writing is paused from the moment the encrypted copy is made, and the page is modal, so no separate notice is needed while it is open. When a previous run switched the server but this PC could not finish, the page opens by itself once the window is unlocked at launch, on step 2 in its unfinished state: only Primary `common.tryAgain`, no Cancel, no Back. Windows has no Show Progress notice, so a closed window that is reopened gets the same page and never a library that cannot be written to without explanation. The window's own Close button is never blocked: closing in this state just closes, and the same page appears at the next launch.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | A column up to 640 epx on the content layer; content scrolls | Mac sheet 480 × 560 points |
| Small | The page fills the width with 12 epx margins | iPhone sheet |
| Text size 200% or more | Scrolls; the progress bar keeps its full width | Accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `encryption-continue` | Primary on step 1 | `Enter` | Not working |
| `encryption-turn-on`, `turn-on-encryption` | Primary on step 2 | `Enter` | Both fields (and the access password) filled, not working. Enter in a field moves to the next; Enter in the last chooses it |
| `encryption-finish` | Primary when unfinished | — | Unfinished |
| `sync-reconnect` | Primary after "turned on elsewhere" | — | That error |
| `encryption-cancel` | Cancel button | — | Not while updating the server; hidden when unfinished |
| `add-device` | Hyperlink on step 3 | — | Syncing |
| `encryption-done` | Done button on step 3, default | `Enter` | Always |
| `show-encryption-progress` | Not offered | — | The page is the only place the work shows |

## Copy differences

Sentence case applies ("Turn on encryption", "Choose a master password", "Your journals are encrypted", "Your other devices"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.encryption.done.otherDevices` | On each of your other devices, choose Sign In and enter your master password, or add it from this device. | …select Sign in… | vocabulary, B26 |
| `messages.writingPaused.encrypting`, `messages.writingPaused.encryptionUnfinished`, `messages.writingPaused.showProgress` | this Mac…, Show Progress | this PC…; Show Progress not offered | vocabulary (platform.md, 12.3) |
| `messages.encryption.background` | Encryption stopped because My Journal was in the background… | Not shown | removed: Windows desktop apps are not suspended in the background |

## Accessibility

- Progress is one element: the bar's name is `settings.encryption.progressLabel`, its range value is read as a percentage, and `AutomationProperties.ItemStatus` carries `settings.encryption.progressValue`. A notification (`MostRecent`) is raised for every 10% step, at most once every five seconds; `messages.encryption.announce.turningOn` when Turn on starts, `messages.encryption.announce.updatingServer` (`ImportantMostRecent`), and `messages.encryption.announce.done` at the end; every error is announced.
- Field errors are the fields' `HelpText`, and focus moves to the field with the error.
- Focus: step 1 on the first control, step 2 on Master password (or Current access password), step 3 on the heading. When the page opens by itself at launch Narrator reads the heading and the unfinished error.
- Contrast themes and 225% text: standard controls; the page scrolls.

## Different by design

- **A task page replaces the notice bar and Settings > Privacy round trip** of the Mac (`show-encryption-progress` is not offered); an unfinished switch opens the page by itself at launch, as on iPhone and iPad. It is a page rather than a dialog because it has progress, a back arrow and a title per step, and Cancel is a button (Esc is not Back).
- **No background-time errors.** iOS ends background work; a Windows desktop app runs until closed. The PC is kept awake while encrypting ([flows/turn-on-encryption](../flows/turn-on-encryption.md)).
- **Show password is a check box** (D41).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D41 (Show password control), B26 (select and choose).
