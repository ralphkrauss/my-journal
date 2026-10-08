---
id: connect-to-server
title: Connect to a server, task page and steps (Windows)
spec: screens/connect-to-server.md
features: [sync-connect, server-discovery, server-setup, join-with-local-journals, pair-device-scan, pair-device-code, recovery-code-join, sync-recovery]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/uwp/api/windows.networking.servicediscovery.dnssd.dnssdservicewatcher
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/password-box
---

# Connect to a server, task page and steps (Windows)

One task page that takes this PC from "not syncing" to syncing with a server, one step at a time. Behaviour and copy keys are the spec's [Connect to a Server](../../../screens/connect-to-server.md); the decision tree and every message are the spec's [flow](../../../flows/connect-to-server.md), whose mapping is [flows/connect-to-server](../flows/connect-to-server.md). The dialog patterns are in [settings](settings.md#dialog-patterns) (the page reuses their field, error and busy patterns); this file adds the steps. It is a page, not a dialog, because a ten-step flow with progress, a back arrow, changing buttons and a title per step is a page's job ([platform.md, 9](../platform.md#9-sheets-popovers-and-notices)).

## Controls

### The task page

A page in the window's content area ([platform.md, 9](../platform.md#9-sheets-popovers-and-notices)) that replaces the page it was started from (Settings ▸ Sync, Devices or Agent access, or the first-launch page) while it runs; Back and Cancel return there. The header is the title bar's back button, where the spec allows Back, and the step's title as the page heading (level 1); there is no breadcrumb, because the steps are not places. The step's content is a column at most 640 epx wide, scrolling, and the step's buttons are a footer row pinned to the bottom of the content area: the primary action first (accent), then Cancel, the order of [8.1](../platform.md#81-rules). The modal guarantee is kept by disabling the navigation pane, the menu bar's commands and the command bars while the page runs.

- **Cancel** (`common.cancel`, a button; Esc is not Back and is not bound) stops what is running, withdraws a pairing request, gives up access received but not used, discards a staged copy and returns to where the flow started ([flows/connect-to-server](../flows/connect-to-server.md)). It is disabled while installing (`CanExecute` false); closing the window then waits for the current atomic step and discards the staged copy, one rule for every flow ([platform.md, 3](../platform.md#3-windows-and-instances)).
- **Back** (the back button and Alt+Left) is not allowed while working, on Server is ready and Finish, and on Protect your journals and Choose a master password once a journal was created in the flow. Back from a step with a typed value keeps the value for the step it returns to; it never discards silently.
- **Error row.** An `InfoBar` (Error, not closable) at the end of the step for a failure not about one field; field errors under their field ([Dialog patterns, 4](settings.md#dialog-patterns)).
- **Busy row.** A `ProgressRing` and the step's busy text (`settings.connect.busy.checking`, `settings.connect.busy.settingUp`, `settings.connect.busy.signingIn`, `settings.connect.busy.downloading`, `common.merging`, `common.connecting`) above the buttons: the app is blocked on the server's answer, so it is a ring ([platform.md, 11](../platform.md#11-progress-and-announcements)). While a device that signs in again encrypts its own journals, the row is a determinate `ProgressBar` with `settings.encryption.progress`.
- Locked: the page closes as Cancel does; while the page is shown unlocked there is no `settings.connect.locked` state, because the window is replaced by the lock page.
- Steps take focus on their first field once the `Frame` has navigated, and the step's heading is the page heading.

### Steps

| Step (spec) | Title | Content | Primary button |
| --- | --- | --- | --- |
| Choose a server | `settings.connect.title` | The nearby list, the address field, their footers (below) | `common.continue`, default; disabled while checking or empty |
| Set up server | `settings.connect.setUp.title` | A value row `settings.connect.server` and the host (selectable); a `TextBox` for the setup code, `Header` `settings.connect.setUp.code`, `PlaceholderText` `settings.connect.setUp.codePlaceholder`, Cascadia Mono, `InputScope` Default, `IsSpellCheckEnabled` false, text re-formatted as typed (upper case, no spaces or dashes, the hyphen after three characters); field error; footer: `settings.connect.setUp.footer`, the `HyperlinkButton` `settings.sync.footer.howToSetUp`, and where it applies `settings.connect.setUp.upload` with `settings.connect.merge.footerUnencrypted` | `settings.connect.setUp.setUp` when it follows directly, else `common.continue`; default; disabled while working or empty |
| Protect your journals | `common.protectYourJournals` | `settings.connect.protect.intro`; a `RadioButtons` group named `settings.connect.protect.choice` with two items: `settings.connect.protect.encrypt` and `settings.connect.protect.encryptDetail` (selected by default), `settings.connect.protect.dontEncrypt` and `common.unencryptedWarning` | `common.continue` or `settings.connect.setUp.setUp`; `common.tryAgain` after a journal was created and the server failed. The choice is disabled while working and once a journal was created |
| Choose a master password | `common.chooseMasterPassword` | `settings.connect.choosePassword.intro`; `PasswordBox` `common.masterPassword`; `PasswordBox` `common.verify`; check box `common.showPassword` ([Show password](settings.md#show-password)); footer `settings.password.footer`; field error on Verify | `settings.connect.setUp.setUp` or `common.tryAgain`; disabled while working or either field is empty. Enter in the first field moves to Verify, Enter in Verify sets up |
| Enter {credential} (set up) | `settings.connect.signIn.title` | `settings.connect.enterExisting.intro`; `PasswordBox` named by the credential; check box `settings.connect.showCredential`; field error; footer `settings.connect.setUp.upload` | `settings.connect.setUp.setUp` |
| Server is ready | `settings.connect.ready.title` | `settings.connect.ready.message`; icon Completed (E930, decorative); a `HyperlinkButton` `settings.connect.ready.addDevice`; the footer `settings.connect.ready.footer` when the journals have a password | `common.done`, the default button (Enter finishes; no other primary button) and it returns to where the flow started. Add another device… opens the [Add device](add-device.md) dialog over this page, which stays on Server is ready; the work is already complete |
| Enter {credential} (sign in) | `settings.connect.signIn.title` | The intro (`settings.connect.signIn.introEncrypted`, `settings.connect.signIn.introRecoveryKey` or `settings.connect.signIn.intro`); `PasswordBox`; check box `settings.connect.showCredential`; field error; footer `settings.connect.signIn.footerEncrypted` or `settings.connect.download`; a `HyperlinkButton` `settings.connect.signIn.useDevice`, disabled while working | `settings.connect.signIn.signIn` or `common.tryAgain` after merging stopped; disabled while working or empty |
| Add this device | `settings.connect.addThisDevice.title` | The pairing code, then the check code, below; the footer `settings.connect.download`; for a server without encryption a `HyperlinkButton` `settings.connect.addThisDevice.useRecoveryCode` | The check code is shown: `common.connect`, no default button, Ctrl+Enter; after a failure `settings.connect.addThisDevice.getNewCode` or `common.tryAgain` |
| Use a recovery code | `settings.connect.recoveryCode.title` | `PasswordBox` `common.recoveryCode`; check box `settings.connect.recoveryCode.show`; field error; footer `settings.connect.recoveryCode.footer` then `settings.connect.download` when nothing is written | `common.connect` or `common.tryAgain` |
| Merge journals (this flow's step, not Merge into) | `settings.connect.merge.title` | `settings.connect.merge.intro`; rows `settings.connect.server` (host, selectable) and `common.onThisDevice` (the summary: `common.journalCount`, `common.entryCount`, then `common.templateCount` and `settings.connect.merge.recentlyDeleted` when not zero, joined with ", "); the footer lines of the spec in order | `common.merge`, no default button, Ctrl+Enter; disabled while working. Back is allowed |
| Finish on your other device (after a scanned code) | not shown | Not offered: there is no scanner | |

`settings.connect.addThisDevice.connectHelp`, `settings.connect.addThisDevice.connectHint`, `settings.connect.merge.help` and `settings.connect.merge.hint` carry the Mac shortcut text and are not shown: the framework adds "Ctrl+Enter" to the button's tooltip and to `AutomationProperties.AcceleratorKey` ([platform.md, 7](../platform.md#7-keyboard-shortcuts)).

### Choose a server, in detail

1. **Servers on this network.** A `ListView` (`SelectionMode` None, `IsItemClickEnabled` true) under the header `settings.connect.nearby.header`: one row per HTTPS server announced, sorted by host; the host with its port when not the default, the announced name below it in `Caption`. While a server is checked its row shows a `ProgressRing` and all rows are disabled. Under it: `settings.connect.nearby.looking` with a ring during the first 5 seconds, then `settings.connect.nearby.none`. Discovery is `DnssdServiceWatcher`, runs only while this step is shown, and needs no permission ([platform.md, 32](../platform.md#32-local-network-and-servers)); `settings.connect.nearby.denied` is never shown. A row reads "{host}, {name}".
2. **Server address.** A `TextBox`, `Header` `common.serverAddress`, `PlaceholderText` `settings.connect.address.placeholder`, `InputScope` Url, spell check, text prediction and automatic capitalisation off, prefilled with the PC's current server address; footer `settings.connect.address.footer`; a busy row `settings.connect.busy.checking` while a typed address is checked. A nearby row fills the address and checks it.
3. **Scan code.** Not offered: no `settings.connect.scanCode` row, no scanned-code state. See [scan-code](scan-code.md).

### The pairing code and the check code

- **Pairing code.** Nine digits in groups of three ("123 456 789") in Cascadia Mono at 32 epx, `IsTextSelectionEnabled`, `AutomationProperties.Name` `settings.connect.addThisDevice.codeLabel` and the digits read one by one. Beside it a `Button` `settings.connect.addThisDevice.copyCode`: it copies the nine digits only, with the clipboard options of [Dialog patterns, 11](settings.md#dialog-patterns). Then `settings.connect.addThisDevice.instructions` and the busy row `settings.connect.waitingForApproval`.
- **Check code.** Heading `settings.connect.checkCode.title` (level 2), six digits in groups of three in the same type, named `settings.connect.checkCode.label` and read digit by digit; `settings.connect.checkCode.instructions`; the busy row or `settings.connect.checkCode.waiting`. When it appears a notification event announces `settings.connect.checkCode.announcement` with the digits (`ImportantMostRecent`).
- Neither code is placed on the clipboard or in a log by anything other than the Copy button; the window is excluded from capture while either code is shown, as in [add-device](add-device.md) and [pair-device](../flows/pair-device.md) (whatever D28 decides), and restored when the step ends.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | A column at most 640 epx wide on the content layer, scrolling; the footer row stays | Mac sheet (480 × 340 points) |
| Small | The page fills the window width with 12 epx margins; the nearby list and fields are full width | iPhone sheet |
| Text size 200% or more | As small; the nine- and six-digit codes keep their size (they do not scale below 32 epx) and wrap by group | Accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `connect-check-server` | Continue button; a nearby row | `Enter` in the address field | Not while checking; address not empty |
| `connect-set-up` | Primary button | `Enter` | Not while working; code not empty |
| `connect-sign-in` | Primary button; the recovery code step | `Enter` | Not while working; field not empty |
| `connect-use-device` | Hyperlink | — | Not while working |
| `connect-copy-code` | Button beside the pairing code | — | A code is shown |
| `connect-confirm-check-code` | Primary button, no default | `Ctrl+Enter` | The check code is shown and not yet confirmed |
| `connect-new-code` | Primary after a failure | — | After a failure with nothing received |
| `connect-use-recovery-code` | Hyperlink | — | Server without encryption; not while installing |
| `connect-merge` | Primary button, no default | `Ctrl+Enter` | Not while working |
| `connect-retry` | Primary button | — | After a failure |
| `connect-cancel` | Cancel button | — | Not while installing |
| `connect-done` | Done button, default | `Enter` | Server is ready |
| `add-device` | Hyperlink on Server is ready | — | Always on that step |
| `connect-scan-code`, `scan-cancel`, `scan-open-settings`, `show-connection` | Not offered | — | No scanner; the task page is modal over the only window |

Enter in a password field chooses the primary button only where the spec says Return does; it never chooses Merge or Connect. Tab order follows the visual order: fields, check box, hyperlinks, buttons.

## Copy differences

Sentence case applies to titles, labels and buttons ("Connect to a server", "Set up server", "Choose a master password", "Show password"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.connect.addThisDevice.instructions` | …then choose Enter Code Instead. | …then select Enter code instead. | vocabulary (platform.md, 12.3) |
| `settings.connect.scanCode`, `settings.connect.scanCode.footer`, `settings.connect.scanAgain`, `settings.connect.finish.*` | Scan Code and its footer | Not shown | removed (no scanner) |
| `settings.connect.nearby.denied` | the Local Network sentences | Not shown | removed (platform.md, 12.3) |
| `settings.connect.addThisDevice.connectHelp`, `settings.connect.addThisDevice.connectHint`, `settings.connect.merge.help`, `settings.connect.merge.hint` | Connect (⌘Return) … | Not shown | shortcut text (platform.md, 12.3) |
| `settings.connect.signIn.useDevice`, `settings.connect.addThisDevice.useRecoveryCode` | Use a Connected Device Instead…, Use a Recovery Code Instead… | Use a connected device instead…, Use a recovery code instead… | casing; the ellipsis stays (they open a step) |
| `messages.connection.serverChanged`, `messages.connection.setUpElsewhere` | …Choose Continue to check it again. / …Choose it again to sign in. | …Select Continue… / …Select it again… | vocabulary, B26 |
| `messages.writingPaused.connecting`, `messages.writingPaused.connectionFailed`, `messages.writingPaused.showConnection` | this Mac…, Show Connection | this PC…; Show Connection not offered | vocabulary (platform.md, 12.3) |

## Accessibility

- The page heading is read on open and again, with the new step's title, through a notification event when the step changes (`MostRecent`); focus goes to the step's first field or, on steps without one, its heading.
- Nearby rows are a list with its size and position; each reads "{host}, {name}". The pairing code and check code are named and read digit by digit; the check code is announced when it appears.
- Field errors are the field's `HelpText` and are announced after focus moves to the field; the error row is read when it opens.
- Busy rows are read as one element ("Checking…"). Progress ring and bar have names; no sound.
- Merge and Connect take Ctrl+Enter and no default button, so Enter in a field cannot choose them before the person has read ([platform.md, 8.1](../platform.md#81-rules)).
- Reduced motion: the step transition is a cross-fade of 0 duration. Contrast themes and 225% text: standard controls; the page scrolls.

## Different by design

- **No Scan Code and no Finish on your other device** (D24): Windows has no built-in camera scanner for desktop apps, and many PCs have no camera. A Windows PC joins with the typed-code path (Add this device) or the password.
- **No local network prompt or message**; discovery that finds nothing just shows the "no servers" text and the person types the address.
- **A task page, not a sheet or a dialog.** A ten-step flow with progress, a back arrow, changing buttons and a title per step is a page's job, and Windows Settings uses pages for its own pairing flows; Add another device opens the Add device dialog over the page. The Mac shows its notices "Show Connection" in the journal window; Windows needs none because the page is modal over the one window (navigation and commands are disabled while it runs).
- **Cancel is a button and Esc is not Back**, which a sheet's Esc was.
- **Show password is a check box** ([settings](settings.md#show-password)).
- **Retry buttons and Back** follow the Windows button order ([8.1](../platform.md#81-rules)); Back is the title bar's back button and Alt+Left.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D41 (Show password control), B26 (select and choose), D45 (device name a PC sends), D28 (capture exclusion while a code shows).
