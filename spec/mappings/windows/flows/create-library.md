---
id: create-library
title: Create a library, Start a journal (Windows)
spec: flows/create-library.md
features: [create-library, encrypt-library, continue-without-encryption]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/password-box
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
---

# Create a library, Start a journal (Windows)

Creates this PC's library from Start a journal on the [welcome](../screens/welcome.md) page, with a master password (encrypted, the default path) or without encryption. Steps, states and rules are the spec's [create-library](../../../flows/create-library.md).

## Controls

One `ContentDialog` with two steps, the multi-step pattern of [9](../platform.md#9-sheets-popovers-and-notices): a `Frame` of two pages, the title following the step, a back arrow at the top left of the content on step 2, the buttons following the step. 520 epx wide, scrolling, no fixed height. The page behind stays the welcome page.

**Both steps** (a left-aligned column): a decorative `FontIcon` (ShieldLock F5B4 on step 1; the key glyph on step 2, a gap in Segoe Fluent Icons filled by the Fluent UI System Icons, [23](../platform.md#23-icons)), hidden from the tree; the heading as the dialog's title (`common.protectYourJournals`, then `common.chooseMasterPassword`); and `library.createLibrary.explanation` as secondary text.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Step 1: Use encryption | `PrimaryButton` `library.createLibrary.useEncryption`, accent, the default button | Moves to step 2 |
| Step 1: Continue without encryption | A plain `Button` (not the accent) in the content, `library.createLibrary.continueWithout`, with `common.unencryptedWarning` in `Caption` secondary text directly under it | Creates the library at once, without a confirmation, as the spec says. In the content rather than a dialog button so the warning sits with the choice it describes and the person reads it before pressing; it is not the default |
| Step 1: Cancel | `CloseButton` `common.cancel` | Closes, creates nothing; the welcome page stays |
| Step 2: Master password | `PasswordBox`, `Header` `common.masterPassword`, `InputScope` Password; the first field takes focus when the step appears | Enter moves to the next field |
| Step 2: Verify | `PasswordBox`, `Header` `common.verify` | Enter creates |
| Step 2: Show password | A `CheckBox` `common.showPassword` that sets `PasswordRevealMode` to Visible on both boxes (Hidden when unchecked, so each box has no second reveal glyph) | A check box works by keyboard and Narrator; a press-and-hold reveal does not |
| Step 2: Mismatch | The field error under the fields (a `TextBlock` with the error glyph in the critical brush, also the fields' `AutomationProperties.HelpText`): `messages.connection.passwordsDontMatch`; focus moves to Verify; editing either field clears it | Announced once focus is on Verify ([Dialog patterns, 4](.././screens/settings.md#dialog-patterns)). Compared only on Create, not while typing |
| Step 2: Advice | `Caption`, secondary: `library.createLibrary.advice` | |
| Step 2: Create | `PrimaryButton` `common.create`, the default button | Enabled when both fields are non-empty and nothing is being created. Enter in Verify does the same |
| Step 2: Back | The back arrow at the top left of the content, `AutomationProperties.Name` `common.back` | Returns to step 1; not offered while busy |
| Creating | An indeterminate `ProgressBar` along the top of the dialog with `library.createLibrary.creating`; every control disabled; the dialog cannot be dismissed (Esc and Cancel do nothing); the back arrow is hidden | |
| Error | An Error `InfoBar` in the content with the error that stopped creation (for example `messages.password.enterMaster`); a partly created library is removed; the person can try again or cancel | |

### Steps on Windows

1. Use encryption: step 2 replaces step 1 in the same dialog; the first box takes focus once it is shown.
2. The person types the password twice and chooses Create (or presses Enter in Verify). A mismatch creates nothing and shows the bar.
3. The library is created: one journal named `library.createLibrary.defaultJournalName` and no templates; the key is written to the secret store (the DPAPI-protected store of [14](../platform.md#14-secure-storage)). The dialog closes and both boxes are cleared. The library window replaces the welcome page, the journal is shown, empty and offering New entry, and focus goes to the New entry button of the list header.

Without encryption the same result happens from step 1, with no master password. If the secret store refuses the key (for example the profile cannot be written), the error shows in the bar and nothing is left behind.

Rules of the spec kept: the password is checked only for being non-empty (no strength meter); a library created here is confirmed at once (no recovery-key step); encryption can be turned on later in Settings ▸ Privacy but never off.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Dialog 520 epx wide, left-aligned column, scrolling | Mac sheet, 520 pt wide |
| Small | Fills the window width; the column keeps its 12 epx margins | iPhone: step 2 pushed inside the sheet with the system back button |
| 200% text size or more | Text wraps, the dialog scrolls, the buttons stay in reach at the foot | accessibility sizes |

## Commands and shortcuts

None of the steps is a command of [commands.md](../commands.md). Keyboard: Enter chooses the default button (Use encryption on step 1, Create on step 2); in step 2 Enter in the first box moves to Verify, which handles the key itself so the default button does not fire early; Esc is Cancel unless busy; Back on step 2 is the back arrow button; Tab order is the reading order.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)):

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `common.protectYourJournals`, `common.chooseMasterPassword` | Protect Your Journals, Choose a Master Password | Protect your journals, Choose a master password | casing |
| `library.createLibrary.useEncryption`, `library.createLibrary.continueWithout` | Use Encryption, Continue Without Encryption | Use encryption, Continue without encryption | casing |
| `common.masterPassword`, `common.showPassword` | Master Password, Show Password | Master password, Show password | casing |

`library.createLibrary.advice` mentions a password manager and stays. The Windows PasswordBox has no system suggestion for a new password, which the spec's rule about password-manager suggestions does not require.

## Accessibility

- The icons are decorative. The step change is announced by the dialog's title change and a notification; focus goes to the first control of the step (Use encryption's default on step 1, Master password on step 2).
- The mismatch is announced when its bar opens, and focus moves to Verify. Busy state is read once as `library.createLibrary.creating`.
- Both boxes are `PasswordBox`es with names from their headers; the check box has a name and state. The dialog scrolls at 225% text size; contrast themes use theme brushes.

## Different by design

- **A two-page dialog with a back arrow**, not a pushed screen with the system back button and a toolbar of Cancel, Back and Create.
- **Continue without encryption is a link with its warning beneath it**, kept inside the content, where Apple has the same link under a prominent button.
- **A Show password check box** replaces the per-field reveal press, so the keyboard and Narrator can use it.
- **No password-manager suggestion and no autocorrection settings**: a `PasswordBox` has neither.
- **Focus goes to New entry** when the library window opens, since Windows has no equivalent of the Mac's focus on the first control.

## Open questions

None.
