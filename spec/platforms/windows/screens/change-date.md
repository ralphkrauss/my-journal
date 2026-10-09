---
id: change-date
title: Change date (Windows)
spec: screens/change-date.md
features: [change-entry-date]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/calendar-date-picker
---

# Change date (Windows)

Changes an entry's date, which decides where it is listed. Dates are shown in the list and changed here, never as a persistent control in the editor. Behaviour and copy keys are the spec's [change-date](../../../screens/change-date.md).

## Controls

A `ContentDialog` opened from Change date… in the entry row's context menu or the Entry actions menu ([entry-list](entry-list.md)).

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | `ContentDialog.Title`, `library.changeDate.title` | |
| Date | `CalendarDatePicker`, `Header` `library.changeDate.date`, `Date` set to the entry's date, `IsTodayHighlighted` true, `IsGroupLabelVisible` true, date only | Honours the user's calendar system, first day of the week and regional format ([31](../platform.md#31-dates-time-zones-and-formats)). `MinDate` and `MaxDate` are widened so the entry's own date is always inside the range. Only the date is chosen: the entry keeps its time of day, as the spec says (date only, no time) |
| Error text | `InfoBar`, Severity Error, not closable, under the picker | `messages.entry.dateChanged`, `messages.save.before.goBack`, `messages.entry.unavailableForEditing`; announced when it opens |
| Save | `PrimaryButton` `common.save`, `DefaultButton` Primary | Disabled while saving and while the entry has a failed save |
| Cancel | `CloseButton` `common.cancel`; Esc | |

**Save** stores the new date; the entry moves to its new place in the list (another month, or within Pinned); the dialog closes; no message. If the date was stored but the view could not refresh, the dialog closes and then the general error dialog shows `messages.refresh.dateSaved` (one dialog at a time, [8.1](../platform.md#81-rules)).

**Busy:** the picker and buttons are disabled and the dialog cannot be dismissed (its `Closing` event is cancelled, Esc is ignored). Another entry opening or the library locking closes the dialog, cancelling the operation.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Default dialog, about 360 epx wide | Mac sheet |
| Small | Fills the window width | iPhone form sheet |
| 200% text size or more | The header sits above the picker and the buttons stack, Save first; no fixed height | The Mac's accessibility-size layout |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `change-date` | Entry row context menu; Entry actions | none | The entry is editable in a journal in use. Saves the open entry first; if that fails, nothing opens |

- Enter chooses Save when focus is not inside the open calendar; Esc closes the calendar first if it is open, then the dialog.
- Focus starts on the date picker; closing returns it to the control that opened the dialog.

## Copy differences

Sentence case: "Change date" for `library.changeDate.title`, "Change date…" for the menu item ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). `messages.entry.dateChanged` says "Close this sheet" and becomes "Close this dialog" (platform.md, 12.3).

## Accessibility

- The picker is a button that opens a calendar grid; Narrator reads its header, the date and the calendar's own navigation. The error is announced when it opens.
- At 225% text size the header sits above the picker and the buttons stack.
- Dates are read in the person's regional format.

## Different by design

- **A `CalendarDatePicker` instead of a graphical date picker**; the date is typed or picked.

## Open questions

None.
