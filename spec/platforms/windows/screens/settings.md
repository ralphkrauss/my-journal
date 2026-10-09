---
id: settings
title: Settings (Windows)
spec: screens/settings.md
features: [settings, about-links, erase-device]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingsexpander
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Settings (Windows)

The Settings page and the patterns every other Settings and connection page reuses: the page shell, the card patterns, the dialog patterns and the authentication gate. [platform.md, 10](../platform.md#10-settings) decides that Settings is a page inside the library window (open question D26); this file applies it to the spec's [Settings](../../../screens/settings.md). Behaviour, states and copy keys are the spec's.

The other Settings and connection pages link here instead of repeating: [Card patterns](#card-patterns), [Dialog patterns](#dialog-patterns) and [The authentication gate](#the-authentication-gate).

## Controls

### The page shell

| Spec element | Windows control | Notes |
| --- | --- | --- |
| The Settings window (Mac) or sheet (phone, tablet) | A `Page` in the library window's content `Frame`, opened from the navigation pane's built-in Settings item (`library.toolbar.settings`, gear E713, handled in `ItemInvoked`), File ▸ Settings and Ctrl+, | The list and editor columns are replaced by the page; the open entry, the selection and unsaved writing stay as they were and return exactly on Back ([library-window](library-window.md)). Opening Settings saves the open entry first; if that fails nothing opens and the usual failure notice shows |
| Window title | `AppWindow.Title` stays `library.app.name` while the page is open | The window title never changes ([library-window](library-window.md), B29); it is readable by every process, so it names neither a journal nor the page |
| Title area of the page | At the home page, `settings.title` as a `TextBlock` (`TitleTextBlockStyle`, heading level 1). At a pane page, a `BreadcrumbBar` whose items are `settings.title` and the pane's name, in `TitleTextBlockStyle` size; the last item is the current page and is not clickable. A third level (an agent, Recent activity) adds an item | The Windows 11 Settings pattern. Choosing an earlier item goes back to that page. The breadcrumb is the page's heading for Narrator |
| Back | The `TitleBar` back button is shown while a Settings page is open, in every layout; Alt+Left and the mouse back button do the same | Windows pages with a stack. Back from the home page returns to the library, or to the welcome page when there is none. There is no Done button (`settings-done` is not offered) |
| Body | A `ScrollViewer` holding one column at most 1000 epx wide, left-aligned, 24 epx margins (12 at small width), 4 epx between cards, 24 epx before a group header | [platform.md, 10](../platform.md#10-settings) |
| Home page | Clickable `SettingsCard`s in the order of the spec (the spec has five panes since 1.1 and this page still lists six: open question C27; `settings.pane.general`, `settings.pane.sync`, the Devices page, `settings.pane.privacy`, `settings.pane.backup`, `settings.pane.agents`), each with a `HeaderIcon` (see below), the pane's name as `Header` and a chevron as `ActionIcon`. Then the About group ([settings-about](settings-about.md)) | The pane called Writing on iPhone and iPad is General here ([platform.md, 12.3](../platform.md#123-vocabulary)); Erase is not on this page ([settings-erase](settings-erase.md)) |
| Pane icons | General: Edit (E70F); Sync: Sync (E895); Devices: Devices (E772); Privacy: Shield (EA18); Backup: SaveLocal (E78C); Agent access: Robot (E99A) | [platform.md, 23](../platform.md#23-icons). Decorative |
| Locked | Not shown. The lock page replaces the whole window, so `settings.locked` is never displayed ([lock-screen](lock-screen.md)) | Different by design |
| No library (first launch, or just after erasing) | Settings can be opened from the welcome page (File ▸ Settings, Ctrl+,): the Privacy page shows nothing and Back returns to the welcome page. Just after erasing, the page closes by itself and the window shows the first-launch page ([settings-erase](settings-erase.md)) | The spec: Settings opens independently of the journal window |

### Card patterns

Every pane is built from these. A pane's file names the pattern and the copy keys; it does not redraw the pattern.

| Pattern | Control | Used for |
| --- | --- | --- |
| Group | A `TextBlock` in `BodyStrongTextBlockStyle`, heading level 2, above its cards, then the cards | The spec's section headers (`settings.connect.server`, `settings.privacy.encryption.header`, …). A section with no header is a group with no heading |
| Value card | `SettingsCard`, `Header` the label, the value as trailing `TextBlock` (selectable where the spec says so) | Last synced, Not on server yet, Last used, Added |
| Switch card | `SettingsCard` with a `ToggleSwitch` (the default On and Off labels, which the system localises) as `Content`; the footer is the `Description` | Format Markdown as you type, Require Windows Hello |
| Choice card | `SettingsCard` with a `ComboBox` as `Content` | Default journal, Lock when inactive, Access ends |
| Primary button card | `SettingsCard` with explanatory `Header` or `Description` and an accent `Button` as `Content`. One accent button per page | Connect to a server, Add device |
| Action card | A `SettingsCard` with an explanatory `Header` or `Description` and a real `Button` as `Content` carrying the action's label (standard style; accent only for the page's one primary action). **Every action has a button**, including destructive ones, and no card is clickable without a visible button or chevron, because a clickable card with no button affordance looks like a heading and invites an accidental click. No red; the confirmation dialog protects the action | One-button sections: Stop syncing, Export archive, Import archive, Change password, Lock My Journal, Erase journals and settings |
| Navigation card | A clickable `SettingsCard` with a chevron `ActionIcon`; clickable cards are for navigation and external links only | The six panes, a request, an agent, Recent activity |
| Link card | A clickable `SettingsCard` with the external-link glyph (E8A7) as `ActionIcon`; `AutomationProperties.LocalizedControlType` "link" | The About links |
| Expander card | `SettingsExpander`: the dependent setting's switch in the header, the dependent items inside. While the switch is off the items stay visible and disabled with an explaining description; the expander never swaps to a plain card | App lock and Lock when inactive |
| Footer | One line about one card: the card's `Description`. Longer text, text about several cards, or text with a link: a `TextBlock` in `CaptionTextBlockStyle` with the secondary brush under the group, `TextWrapping` Wrap | The spec's section footers ([platform.md, 10](../platform.md#10-settings)) |
| Status or error line | An `InfoBar` under the group it belongs to: Error for a failure, Warning for a state that needs the person, Informational for the rest. `IsClosable` false, an icon always shown, the text in `Message`, selectable text as a `TextBlock` with `IsTextSelectionEnabled` in `Content`. An action the spec offers with the message (Try Again, Connect Again…) is the bar's `ActionButton` | [platform.md, 9.1](../platform.md#91-notices). Severity follows the messages mapping where it has a table; the severities in these files are provisional until it is reviewed |
| Busy state | A small indeterminate `ProgressBar` (about 80 epx wide) beside the text, or the text alone, in the card's trailing area; the card keeps its size and its button is disabled. The page stays usable, so it is not a `ProgressRing` (a ring means the app is blocked, [platform.md, 11](../platform.md#11-progress-and-announcements)) | "Syncing…", "Checking…", "Loading…"; it shows only after 0.3 seconds where the spec says so |
| Empty or unavailable group | The spec's text as a `TextBlock` (`TextFillColorSecondaryBrush`, `BodyTextBlockStyle`), with the button below it where the spec has one | Not connected |

At widths under 600 epx the toolkit moves a card's content under its header; nothing else changes. A card that holds only text is not focusable; a card with one control puts focus on that control; a clickable card is one tab stop.

### Dialog patterns

Every short sheet opened from Settings (Add device, the passwords, the confirmations, the erase warnings) is a `ContentDialog` over the page ([platform.md, 8](../platform.md#8-dialogs)); the multi-step flows (Connect, Import archive) are task pages ([platform.md, 9](../platform.md#9-sheets-popovers-and-notices)) that reuse rules 3 to 4, 6 and 10 to 11 below with their own footer row. These rules apply to dialogs:

1. **One dialog at a time, never a dialog on a dialog.** A step that the Apple app shows as a second sheet or an alert is, on Windows, a replacement of the content of the same dialog (a swap with a new title), or the dialog closes and the next one opens in the dialog service's queue. Each file says which.
2. **A dialog has at most two steps or states.** A short flow (Create library, Add device) swaps the content of the same dialog: the `PrimaryButtonClick` handler runs the step's work, sets `args.Cancel` to true so the dialog stays open, and swaps the content when the work succeeds; a back arrow (an `AppBarButton`, icon Back E72B, `AutomationProperties.Name` `common.back`) sits at the top left of the content only where the spec allows Back. A flow with more steps or with progress is a task page, not a dialog ([platform.md, 9](../platform.md#9-sheets-popovers-and-notices)).
3. **Work in progress.** The step's fields are disabled, a `ProgressRing` and the busy text show in the content, the primary button is disabled (`IsPrimaryButtonEnabled`) and the Close button is disabled with a `CloseButtonCommand` whose `CanExecute` is false, where the spec disables Cancel. The `Closing` event sets `args.Cancel` to true while the dialog may not close, so Esc does nothing too.
4. **Field errors** show under their field: a `TextBlock` with an error glyph (Error E783), in the critical brush, and the same text as the field's `AutomationProperties.HelpText`. After the error appears, focus returns to the field and the message is announced (a notification, after focus has moved, so it is not cut off). Errors clear when the field changes. Errors that are not about one field show in an `InfoBar` (Error) at the end of the content.
5. **No default button where the spec says Command-Return** (Connect, Merge journals, Approve, Add Device): `DefaultButton` None, `PrimaryButtonStyle` set to the accent style explicitly (the accent treatment is otherwise a side effect of being the default button), and a `KeyboardAccelerator` Ctrl+Enter on the dialog or page that invokes the primary button. Enter in a field does not choose it. The first shell build proves Ctrl+Enter works with focus in a `PasswordBox` and a `TextBox` ([platform.md, 7](../platform.md#7-keyboard-shortcuts), rule 7).
6. **Enter in a form** chooses the primary button when that button is the `DefaultButton`. Where the spec says Return moves from field to field, the field's `KeyDown` moves focus and marks Enter handled; only the last field lets it through.
7. **Destructive confirmations** follow [8.1, rule 3](../platform.md#81-rules): title a question, primary the verb, Close `common.cancel`, no default button. The one exception is the Erase warning when journals would be lost ([settings-erase](settings-erase.md), D44).
8. **Locking** closes every dialog with no result ([8.1, rule 5](../platform.md#81-rules)); each file says what is cancelled.
9. **Size.** Default width (548 epx); Add device raises `ContentDialogMaxWidth` to 640 and scrolls its content. No fixed heights.
10. **Passwords.** A password is a `PasswordBox`, `InputScope` Password, never `TextBox`. Its reveal control is the check box described in [Show password](#show-password) below. No password, key or code is ever written to a log, a crash report or a text box's undo history, and the field is cleared when the step ends.
11. **Copying secrets.** The only secrets the app puts on the clipboard are pairing codes the person copies; they use the options in [platform.md, 15](../platform.md#15-clipboard) (not in clipboard history, not roamed, cleared after two minutes if unchanged). A `PasswordBox` has no Copy or Cut, so a typed password cannot reach the clipboard from the app. Addresses (server, MCP) are plain copies.

#### Show password

The spec's Show Password switches (`common.showPassword`, `settings.connect.showCredential`, `settings.connect.recoveryCode.show`) are a `CheckBox` under the field or fields, which sets `PasswordRevealMode` of all of them to Visible or Hidden; the `PasswordBox`'s own press-and-hold reveal button is turned off (Hidden mode removes it). Microsoft documents this pattern for a password box. Reason: press-and-hold cannot be done with a switch device, the keyboard or Narrator, and the spec's copy and behaviour stay the same. The check box is used where the spec has a Show Password switch and in the dialogs that set a new password twice (Create library, Change password with and without Forgot password?); a secure field that reads back an existing password (lock page, Open archive) keeps the built-in reveal button, which Alt+F8 also operates (D41).

### The authentication gate

Every place the spec asks for the device owner's authentication (turn App Lock on or off, longer inactivity time, add a device, export as Markdown, erase, forgot password) goes through one interface, the Windows counterpart of the Apple `DeviceOwnerAuthenticating`: availability, authenticate with a reason, cancel. It is built on `UserConsentVerifier` as described in [platform.md, 13](../platform.md#13-device-authentication-and-app-lock) and [flows/app-lock](../flows/app-lock.md), which holds the table of results. A dialog or page never calls `UserConsentVerifier` itself. The reason text is the spec's reason key, capitalised.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, 1008 and up | The navigation pane stays open with the Settings item selected; the page fills the area of the list and editor | Mac Settings window; iPad sheet |
| Medium, 641 to 1007 | The pane is the overlay; the page fills the window under the title bar; cards as above | iPad narrower than 1,000 points |
| Small, 640 and down | The page is one step of the stacked navigation (Journals, then Settings, then a pane); the title bar back button goes back one step. Cards put their controls under the header; the page margin is 12 epx | iPhone sheet with pushed panes |
| Text size 200% or more | One layout narrower than the width would give; cards wrap their text and put controls on a new line; nothing is truncated | iPad at accessibility text sizes |

Dialogs over the page fill the window width at small widths and scroll ([platform.md, 8.1, rule 6](../platform.md#81-rules)). Resizing keeps the page, its scroll position, and an open dialog with its content.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `open-settings` | The built-in Settings item; File menu | as in commands.md | The window is unlocked (a library is not needed). Saves the open entry first |
| `settings-open-pane` | A card on the home page | Enter or Space on the focused card | Always |
| `settings-done` | Not offered | — | Back leaves Settings |

Keyboard behaviour of the page:

- Tab and Shift+Tab move through the controls; ↑ and ↓ also move between the cards of the home page. Enter and Space open a clickable card.
- Alt+Left goes back one page; Esc does nothing on a page and closes the topmost dialog or flyout ([8.1](../platform.md#81-rules)). The spec's rule that Escape never closes Settings itself holds.
- F6 moves between the navigation pane and the page.
- Opening Settings at a pane (from a notice or a sync message) navigates to the home page and then the pane, so Back leads to the home page ([platform.md, 10](../platform.md#10-settings)). When it opens a task page or a dialog on top (for example Sign in…, which opens the Connect page), it opens after the pane has loaded.
- The page does not remember its last pane: it opens on the home page. The Mac opens on Sync by accident (open-questions A30); Windows has no such state.

## Copy differences

Sentence case applies to every title, header and label as in [platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.pane.general` | General | General | the same on every platform since 1.1 |
| `settings.locked` | Unlock My Journal to open Settings. | Not shown | removed: the lock page replaces the window |

No new strings: the window title stays `library.app.name` (B29).

## Accessibility

- Landmarks: the page body is Main (name `settings.title`). The title area is heading level 1; each group header is heading level 2.
- Each card is read as its header, then its description or value, then its control's state ("Require Windows Hello, On"). A clickable card is read as a button (a link card as a link) with its description as help text.
- Focus: going forward moves focus to the first card (or the first control) of the new page and Narrator reads the title; going back returns it to the card that opened the page. Closing a dialog returns focus to the control that opened it, or, when that control is gone, to the nearest card ([8.1, rule 7](../platform.md#81-rules)).
- A change a person did not cause (the list of devices reloading, the agents list refreshing) is announced only when it adds something that needs attention (a new request); otherwise nothing is announced. The page works in the four contrast themes: card borders, chevrons and icons use theme brushes ([21](../platform.md#21-theming-and-contrast)).
- At 225% text size cards reflow; no text is truncated.

## Different by design

- **A page, not a window or a sheet.** Apple has a Mac window with tabs and a phone sheet with a Done button. Windows has a page with a breadcrumb and a back button, and no Done ([platform.md, 10](../platform.md#10-settings)).
- **About on the home page, Erase in General.** Apple's Mac has neither About nor a separate Erase section; the phone has both. Windows puts About on the home page and Erase last in General, as the Mac does.
- **No locked text.** Apple's Settings can show `settings.locked`. On Windows locking replaces the window, so Settings cannot be on screen while locked.
- **Dialogs do not stack.** Apple layers alerts over sheets (Stop Syncing over Settings, a mismatch alert over Allow Access). Windows swaps content or queues dialogs ([Dialog patterns](#dialog-patterns)).
- **Show password is a check box**, not a switch with the platform's autofill. See D41.
- **Window title** is not composed: it stays "My Journal", so a window picker or Task Manager shows nothing about what is open (B29).
- **Every action is a button in its card**, even destructive ones, and the multi-step flows are task pages, not dialogs.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D41 (Show password control), B34 (relative times), B29 (window title), D26 (Settings as a page).
