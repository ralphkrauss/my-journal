---
id: create-library
title: Create a library, Start a journal (Windows)
spec: flows/create-library.md
features: [create-library, encrypt-library]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/password-box
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/progress-controls
---

# Create a library, Start a journal (Windows)

Creates this PC's library from Start a journal on the [welcome](../screens/welcome.md) page, with a master password; every library is encrypted and there is no way to create one without encryption. Steps, states and rules are the spec's [create-library](../../../flows/create-library.md).

## Controls

One `ContentDialog` with one step, 520 epx wide, scrolling, no fixed height; the title is `common.chooseMasterPassword`. The page behind stays the welcome page. A left-aligned column: a decorative `FontIcon` (the key glyph, a gap in Segoe Fluent Icons filled by the Fluent UI System Icons, [23](../platform.md#23-icons)), hidden from the tree, and `library.createLibrary.explanation` as secondary text.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Master password | `PasswordBox`, `Header` `common.masterPassword`, `InputScope` Password; takes focus when the dialog opens | Enter moves to the next field. A new-password field in the spec's sense ([spec Master passwords](../../../README.md)); Windows has no password-manager suggestion for it |
| Verify | `PasswordBox`, `Header` `common.verify` | Enter creates |
| Show password | A `CheckBox` `common.showPassword` that sets `PasswordRevealMode` to Visible on both boxes (Hidden when unchecked, so each box has no second reveal glyph) | A check box works by keyboard and Narrator; a press-and-hold reveal does not |
| Mismatch | The field error under the fields (a `TextBlock` with the error glyph in the critical brush, also the fields' `AutomationProperties.HelpText`): `messages.connection.passwordsDontMatch`; focus moves to Verify; editing either field clears it | Announced once focus is on Verify ([Dialog patterns, 4](.././screens/settings.md#dialog-patterns)). Compared only on Create, not while typing |
| Advice | `Caption`, secondary: `library.createLibrary.advice` | |
| Create | `PrimaryButton` `common.create`, the default button | Enabled when both fields are non-empty and nothing is being created. Enter in Verify does the same |
| Cancel | `CloseButton` `common.cancel` | Closes, clears the fields, creates nothing; the welcome page stays |
| Creating | An indeterminate `ProgressBar` along the top of the dialog with `library.createLibrary.creating`; every control disabled; the dialog cannot be dismissed (Esc and Cancel do nothing) | |
| Error | An Error `InfoBar` in the content with the error that stopped creation (for example `messages.password.enterMaster`); a partly created library is removed; the person can try again or cancel | |

### Steps on Windows

1. The person types the password twice and chooses Create (or presses Enter in Verify). A mismatch creates nothing and shows the field error.
2. The library is created: one journal named `library.createLibrary.defaultJournalName` and no templates; the key is written to the secret store (the DPAPI-protected store of [14](../platform.md#14-secure-storage)). The dialog closes and both boxes are cleared. The library window replaces the welcome page, the journal is shown, empty and offering New entry, and focus goes to the New entry button of the list header.

If the secret store refuses the key (for example the profile cannot be written), the error shows in the bar and nothing is left behind.

Rules of the spec kept: no minimum length and no strength meter, the password is only checked for being non-empty and matching; a library created here is confirmed at once (no recovery-key step); encryption can never be turned off.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Dialog 520 epx wide, left-aligned column, scrolling | Mac sheet, 520 pt wide |
| Small | Fills the window width; the column keeps its 12 epx margins | iPhone sheet |
| 200% text size or more | Text wraps, the dialog scrolls, the buttons stay in reach at the foot | accessibility sizes |

## Commands and shortcuts

None of the steps is a command of [commands.md](../commands.md). Keyboard: Enter chooses the default button (Create); Enter in the first box moves to Verify, which handles the key itself so the default button does not fire early; Esc is Cancel unless busy; Tab order is the reading order.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)):

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `common.chooseMasterPassword` | Choose a Master Password | Choose a master password | casing |
| `common.masterPassword`, `common.showPassword` | Master Password, Show Password | Master password, Show password | casing |

`library.createLibrary.advice` mentions a password manager and stays. The Windows PasswordBox has no system suggestion for a new password; the spec promises none ([open-questions.md](../../../open-questions.md), D61).

## Accessibility

- The icons are decorative. Focus goes to Master password when the dialog opens.
- The mismatch is announced when its bar opens, and focus moves to Verify. Busy state is read once as `library.createLibrary.creating`.
- Both boxes are `PasswordBox`es with names from their headers; the check box has a name and state. The dialog scrolls at 225% text size; contrast themes use theme brushes.

## Different by design

- **A dialog with Cancel and Create buttons** where Apple has a sheet with Cancel and Create in its bar.
- **A Show password check box** replaces the per-field reveal press, so the keyboard and Narrator can use it.
- **No password-manager suggestion and no autocorrection settings**: a `PasswordBox` has neither.
- **Focus goes to New entry** when the library window opens, since Windows has no equivalent of the Mac's focus on the first control.

## Open questions

None.
