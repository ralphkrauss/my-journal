---
id: destination-journal
title: New journal as a destination (Windows)
spec: screens/destination-journal.md
features: [move-entry, restore-version]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# New journal as a destination (Windows)

Creates a journal to move an entry into, or to restore a version into, without leaving the dialog or page that needs it. Behaviour and copy keys are the spec's [destination-journal](../../../screens/destination-journal.md). It differs from the ordinary New journal dialog of [journals](journals.md) only in what happens after Create.

## Controls

A `ContentDialog` cannot open another `ContentDialog` ([8.1](../platform.md#81-rules)), so the surface depends on where it is used:

| Used from | Surface |
| --- | --- |
| [Move entry](move-entry.md) and Restore and move | A step of the same dialog: its title becomes `library.newJournal.title`, a back arrow at the top left of the content returns to the list, and the buttons are the step's |
| Version history (a page) | A `ContentDialog` over the page |
| Permanent-deletion conflict review (a page) | A `ContentDialog` over the page |

Content, in both:

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | `library.newJournal.title` | |
| Name field | `TextBox`, `Header` `common.name`, focused when the step appears, selected text none | Editing the name clears the error |
| Error | `InfoBar`, Severity Error, not closable (a taken name is not here: it is the name field's own error, `messages.journal.nameTaken`, under the field) | Announced; `common.saveBeforeCreateJournal` when the open entry could not be saved; `library.recoveryJournal.created` when the journal was created but could not be displayed |
| Create | `PrimaryButton` `common.create`, `DefaultButton` Primary | Enabled when the name is not blank after trimming, not busy, not created yet. Enter in the name field does the same |
| Cancel or Done | `CloseButton` `common.cancel` before creating; `common.done` after creating if the step stays | In the Move entry step Cancel and Esc return to the list; they do not close the whole dialog |

Create saves the open entry first, then creates a journal with the trimmed name at the end of the journal order. On success the step closes (the list returns, or the dialog closes). The new journal is **not** selected as the destination: the person chooses it. A taken name shows as the name field's own error, as in [journals](journals.md). Busy: the field and buttons are disabled and the dialog cannot be dismissed. A lock closes the dialog and cancels the work; from Move entry, another entry opening does the same.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | The same width as its host dialog (320 to 420 epx); scrolling | Mac sheet 320–420 × 200–240 pt |
| Small | Fills the window width | iPhone sheet |
| 200% text size or more | Grows; scrolls | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `new-journal` | The link or button in Move entry, in Version history and in the deletion review that opens this step | none (the app-wide Ctrl+Shift+J is not active while a dialog is open) | Not while moving or creating |

Enter creates; Esc goes back or closes.

## Copy differences

Sentence case: "New journal" ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). No other differences.

## Accessibility

- Focus moves to the name field when the step appears and back to the New journal link when it returns. Narrator reads the new title on the step change (the dialog's title element changes, and a notification event confirms it).
- Errors are announced when they open.

## Different by design

- **A step, not a sheet over a sheet**, where the host is a dialog. Apple layers a small sheet above the first.
- **Cancel returns one step**, as the Apple nested sheet's Cancel returns to the first sheet.

## Open questions

None.
