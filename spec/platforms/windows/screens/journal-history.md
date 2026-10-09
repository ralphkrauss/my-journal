---
id: journal-history
title: Journal version history (Windows)
spec: screens/journal-history.md
features: [journal-version-history]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/combo-box
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
---

# Journal version history (Windows)

See earlier versions of a journal's settings (its name and default template) and put one back. Entries, and whether the journal is in Recently deleted, never change here. Behaviour, rules and copy keys are the spec's [journal-history](../../../screens/journal-history.md); the entry and template form is [version-history](version-history.md).

## Controls

A **page** with a back button and a `BreadcrumbBar` (the journal's name, `common.untitledJournal` when blank, then `editor.history.title`), like [version-history](version-history.md). Restoring settings opens a comparison, which is a `ContentDialog` over the page: a dialog opened from a page is allowed, and the comparison is a confirmation that must be answered before anything is saved ([8](../platform.md#8-dialogs)). Back is the spec's Done and is disabled while a restore is being prepared or saved.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Loading, no versions | An indeterminate `ProgressBar` with `editor.history.loading`; a centred secondary `TextBlock` `editor.history.empty` | |
| Version picker | A `ComboBox`, `Header` `common.version`, `PlaceholderText` `editor.history.chooseVersion`, newest first, named by date and time with seconds; same-named versions are `editor.history.versionDuplicate`, numbered 1, 2, … in the order recorded. The first version is chosen at the start | |
| Summary of the chosen version | Three label and value pairs, each pair one element for Narrator, values selectable: `common.name` (the name or `common.untitledJournal`), `common.defaultTemplate` (the template's name, `common.blankEntry` or `messages.conflict.journal.value.unavailableTemplate`), `messages.conflict.journal.field.location` (`common.journals` or `common.recentlyDeleted`) | The same pairs as the journal conflict review ([conflict-review](conflict-review.md)) |
| Restore settings | A `Button` (accent) `library.journalHistory.restoreSettings` | Shown for a version this app can read; for a newer version `editor.history.updateToRestore` and a `Button` `common.exportArchive` instead |
| Preparing | An indeterminate `ProgressBar` with `library.journalHistory.loadingSettings` | |
| Error, result | An `InfoBar`: Error for failures, with selectable text; Informational for `library.journalHistory.restored`. Recovery buttons next to it: `editor.history.reload`, `common.reviewChanges`, `common.exportArchive` | Errors are announced when the bar opens |

### The comparison dialog

`ContentDialog`, title `library.journalHistory.confirm.title`, up to 640 epx wide, scrolling. Primary `library.journalHistory.confirm.restore` ("Restore"), Close `common.cancel`, **no default button**: the person has to read both sides before anything is saved, so Enter never chooses. It cannot be dismissed while restoring.

1. `library.journalHistory.confirm.explanation`.
2. Two summaries side by side: headed `library.journalHistory.confirm.current` (`common.name` and `common.defaultTemplate` of the journal now) and `common.restore` (the same two fields of the chosen version). When the dialog is narrower than 480 epx they stack, current first.
3. When another journal in use has the earlier name: `library.journalHistory.confirm.nameTaken` as a Warning `InfoBar`, and Primary is disabled.
4. While restoring: an indeterminate `ProgressBar` with `library.journalHistory.confirm.restoring`; the buttons are disabled.

A default template is named by its title or `library.entryList.untitledTemplate`; templates that share a title are `library.journalHistory.templateDuplicate`; a template that no longer exists is `messages.conflict.journal.value.unavailableTemplate`, numbered with `library.journalHistory.unavailableTemplateNumbered` when the two summaries name more than one.

### Actions and states

| Action or state | Windows |
| --- | --- |
| Restore settings | Reads the journal as it is now, any change to review and the templates, then opens the comparison. If the journal has changes to review: `messages.lifecycle.needsReview` with Review changes (a deeper page). If it is missing or from a newer version: `library.journalHistory.cantChange` with Export archive |
| Restore (in the comparison) | Puts back the name and default template. On success the dialog closes and the page goes back, the pane showing the restored name; if the list could not refresh, the dialog closes and the page stays with `library.journalHistory.restored` |
| Cancel | Closes the comparison; nothing changes |
| Reload history | After a failed load or `messages.history.versionUnavailable` |
| The journal changed after the comparison opened | The dialog closes and the page shows `messages.history.journalChanged` in its bar; the person opens Restore settings again |
| Settings already the same | `messages.history.settingsInUse` as an Informational bar; the page stays and its controls are disabled (completed) |
| Open entry could not be saved first | `messages.save.before.goBack` in the page's bar |
| Locked | The lock page replaces the window; the page, the dialog, the versions and the errors are released |

## Layout at each window width

| Width (epx) | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | One column at most 600 epx wide, left-aligned with 24 epx margins: picker, summary, Restore settings, bar. The comparison dialog is 480 to 640 epx wide with the two summaries side by side | Mac sheets 360–460 pt wide |
| Small | Full-width page with 12 epx margins; the comparison dialog fills the window width and stacks the summaries | iPhone sheets |
| 200% text size or more | The summaries stack; everything wraps; the page and the dialog scroll | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `journal-version-history` | The journal's context menu and Journal actions; a deleted journal's page | none | Always (on the deleted journal's page: when it has versions) |
| `review-changes` | The recovery button | none | The journal has changes to review |
| `export-archive` | The button for a version in a newer format, or a journal that cannot be changed | none | As the spec |

Keyboard: Alt+Left goes back unless busy (Esc never leaves the page); in the dialog Esc is Cancel, Enter does nothing until a button has focus, Tab reaches Restore after the summaries.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Version history", "Restore settings", "Restore". The spec's Mac variant of the confirming button (Restore Settings) is not used: Windows uses the default, "Restore", as on iPhone and iPad.

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.journalHistory.restoreSettings` | Restore Settings… | Restore settings | ellipsis: it opens a comparison that only asks for confirmation (platform.md, 12.2) |

## Accessibility

- Each summary pair reads as one element; each summary heading has heading level 3; the combo box reads "Version" and its value. Errors are announced when their bar opens.
- The dialog is read when it opens (title, explanation, then the two summaries); focus starts on the first summary heading, then Tab reaches the buttons.
- After a successful restore focus moves to the journal's row in the pane.
- At 225% text size values wrap; contrast themes use theme brushes.

## Different by design

- **A page, with a dialog for the comparison**, where Apple nests two sheets.
- **No default button in the comparison**, and the two sides are side by side where there is room.
- **No ellipsis on Restore settings** (the comparison only confirms).

## Open questions

None.
