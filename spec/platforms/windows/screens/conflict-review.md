---
id: conflict-review
title: Review changes, journals, deletions and the list (Windows)
spec: screens/conflict-review.md
features: [conflict-notice, changes-to-review-list, conflict-review-journal, conflict-review-deletion, conflict-review-unsupported]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
---

# Review changes, journals, deletions and the list (Windows)

When the same entry, template or journal changed on this device and on another, both versions are kept and the person decides. This file maps where changes to review are signalled, the Changes to review list, how the Review changes page chooses its form, and the journal, deletion and unsupported forms. The entry and template form is [entry-conflict](entry-conflict.md); what each choice does is [resolve-conflict](../flows/resolve-conflict.md). Behaviour, states, rules and copy keys are the spec's [conflict-review](../../../screens/conflict-review.md).

## Controls

### A page, not a dialog

Review changes is a **page** in the window's content area, with a back button and a `BreadcrumbBar` ([9](../platform.md#9-sheets-popovers-and-notices)): the library panes are replaced and return exactly as they were. Reasons: the forms compare two versions and show previews and journal lists, which need the width a dialog does not have; a person must be able to read a version for as long as they need; and a page leaves the confirmations as the only dialogs, so the one-dialog rule ([8.1](../platform.md#81-rules)) is never in the way. Locking replaces the whole window with the lock page, so the page is simply gone and nothing it showed remains ([13](../platform.md#13-device-authentication-and-app-lock)).

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Where the review opens from | Page navigation in the main window's `Frame`; the back stack returns to where the person came from (the entry, Settings ▸ Sync, Version history, Move entry's dialog, the deleted journal's page) | Opening first saves the open writing; if that fails the page does not open and the alert dialog shows ([save-failure](../flows/save-failure.md)) |
| Title and header | A back button and a `BreadcrumbBar`: the record's title (or the journal's name, or `messages.conflict.deletion.deletedTitle.entry`, `.template`, `.journal` for a permanent deletion), then `common.reviewChanges`. The page heading `common.reviewChanges` is heading level 1 | Back (Alt+Left, the back button and the breadcrumb) is the spec's Cancel; it is disabled while a choice is being saved. Esc is not Back |
| Done | After a completed or already resolved review, a `Button` `common.done` (accent) next to the message, which goes back | Replaces the spec's Cancel-becomes-Done |
| Form chosen on each render | One content region swapped by the same conditions as the spec's table: locked, entry or template ([entry-conflict](entry-conflict.md)), deletion, unsupported, journal, resolved | |
| Locked | `messages.conflict.locked` is never visible: locking removes the page. If the page renders while the lock races, the text is shown in the page's error bar for the moment | |

### Where changes to review are signalled

| Where (spec) | Windows | Opens |
| --- | --- | --- |
| The open entry or template: notice above the writing | The Warning `InfoBar` of [entry-editor](entry-editor.md): `messages.conflict.entryNotice`, `ActionButton` `common.reviewChanges` | the review of that record |
| Entries list row marker | Icon Error (E783) at the row's trailing end; the row's Narrator value includes `messages.conflict.needsReview` ([entry-list](entry-list.md)) | the entry, by selecting it |
| Settings ▸ Sync ▸ Changes to Review | The group below | the review of that row |
| A journal's settings (Mac and the Journals sheet) | Windows has no journal settings surface. The journal's row in the navigation pane carries an attention dot `InfoBadge` and its Narrator value `messages.conflict.needsReview`; **a Warning `InfoBar` at the top of that journal's entry list** says `common.journalNeedsReview` with the action `common.reviewChanges` ([entry-list](entry-list.md)), because at medium and small widths the navigation pane is hidden and a dot alone is invisible exactly when a conflict needs attention (D52); the journal context menu and Journal actions menu start with `common.reviewChanges` while the journal has changes, before the items the spec dims (Rename, Default template, Merge into…), which stay visible and dimmed ([journals](journals.md)) | the journal's review |
| A deleted journal shown from Recently deleted | A `HyperlinkButton` `common.reviewChanges` on its page ([recently-deleted](recently-deleted.md)) | the journal's review |
| An entry in a journal with changes to review (Unavailable journals) | The notice `common.journalNeedsReview` with `common.reviewChanges` ([unavailable-content](unavailable-content.md)) | the journal's review |
| A journal's Version history | The page shows the review's link in place of restoring ([journal-history](journal-history.md)) | the journal's review |

### Changes to review (Settings ▸ Sync)

In the Sync page, a group headed `messages.conflict.settingsSection` (a sub-heading `TextBlock`, level 2), shown only when the app is unlocked and at least one record has changes to review. One `SettingsCard` per record, in the store's order, `IsClickEnabled` false:

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | The card's `Header`: the record's display title (this device's version), or for a permanently deleted record `messages.conflict.deletion.deletedTitle.entry`, `.template` or `.journal` | Wraps; no truncation |
| Date and time | The card's `Description`: the record's date and time (the deletion time for a permanently deleted record), in the user's regional format ([31](../platform.md#31-dates-time-zones-and-formats)) | |
| Review changes | A `Button` in the card's trailing area, `common.reviewChanges`; `AutomationProperties.Name` `common.reviewChangesFor` | Opens the review page |

### The journal review

| Spec element | Control | Notes |
| --- | --- | --- |
| Version choice | A `SelectorBar` with two items `common.thisDevice` and `messages.conflict.version.otherDevice`, `AutomationProperties.Name` `common.version`, at every width | One version at a time, as in the spec (D50) |
| Heading and time | `TextBlock`s: the version's heading, its modification date and time. Under Other device an `Expander` `messages.conflict.journal.details` with the recorded device ID in lower case in a selectable `TextBlock`, `AutomationProperties.Name` `messages.conflict.journal.deviceIDLabel` | |
| Summary | Three label and value pairs, each pair one element for Narrator, values selectable: `common.name` (the name or `common.untitledJournal`), `common.defaultTemplate` (the template's name, `common.blankEntry` or `messages.conflict.journal.value.unavailableTemplate`), `messages.conflict.journal.field.location` (`common.journals` or `common.recentlyDeleted`) | |
| Keep version | `Button` `messages.conflict.journal.keepVersion` (accent) | There is no Keep both for journals. Opens the confirmation dialog |
| Confirmation | `ContentDialog`, title `messages.conflict.journal.confirmThisDevice` or `messages.conflict.journal.confirmOtherDevice`, content `messages.conflict.journal.confirmMessage`, Primary `messages.conflict.keepVersion`, Close `common.cancel`, no default button | Keeping a version of a journal changes its name and template for every device, so Enter does not choose |
| Progress | An indeterminate `ProgressBar` along the top of the content with `messages.conflict.journal.loading` or `messages.conflict.savingChanges` | Choices dim; back is disabled |
| Error | An Error `InfoBar` with the message (name `messages.conflict.journal.errorLabel`), selectable text, and a `Button` `messages.conflict.journal.reloadChanges`, or `messages.conflict.journal.reload` after a saved choice | Announced when it opens |
| After a saved choice | `messages.conflict.journal.saved` with `common.done`; or `messages.conflict.journal.savedNotDisplayed` with `messages.conflict.journal.reload` | The journal's controls are enabled again and its entries leave Unavailable journals |
| Changed meanwhile | `messages.conflict.updatedReviewAgain` as an Informational bar with the reload button; the choice is cleared and This device is shown | |

### The deletion review

| Spec element | Control | Notes |
| --- | --- | --- |
| Two version blocks | Two cards stacked in one column at every width (D50). Each card is one element for Narrator: the title (or `messages.conflict.deletion.deletedTitle.*`), the location line (`common.onThisDevice` or `messages.conflict.deletion.receivedVersion`), the device line `messages.conflict.deletion.unknownDevice`, and the date and time | |
| An edited version | For an entry or template, its title and a read-only preview with images (the editor surface in read-only mode, [entry-editor](entry-editor.md)); for a journal the journal summary above | Follows the body text size |
| Choices | Each a `Button` followed by its explanation in a secondary `TextBlock`, in this order: entry, `messages.conflict.deletion.keepEntry` then `messages.conflict.deletion.keepEntryAsCopy` (each with its `…Explanation`); template, `messages.conflict.deletion.keepTemplate`; journal, `messages.conflict.deletion.keepJournal` (and `common.restoredAsRenamed` when the name is taken); always last `messages.conflict.deletion.keepDeletion` with `messages.conflict.deletion.keepDeletionExplanation.journal` or `.other` | Keep entry and Keep entry as copy open the journal chooser; Keep template and Keep journal save at once; Keep deletion opens the confirmation |
| Both versions are deletions | `messages.conflict.deletion.bothDeleted.entry`, `.template` or `.journal`, `messages.conflict.deletion.bothDeletedExplanation` and the destructive `messages.conflict.deletion.keepDeletion` | |
| Journal chooser (after Keep entry or Keep entry as copy) | The same page, one level deeper: the breadcrumb gains a crumb, `common.chooseJournal`, and the back button returns to the choices (`common.back` is the back button's name). A `ListView` (`SelectionMode` Single) of journals, journals with changes to review left out, same-named journals with their creation date and time and then the shortest distinguishing ID prefix; `common.newJournalEllipsis` as a `HyperlinkButton` below ([destination-journal](destination-journal.md), a dialog over the page) | The chosen row uses the standard selection visual; the spec's checkmark and selected trait are the selection. Below the list `messages.conflict.deletion.selectedJournal`, then the `Button` `messages.conflict.deletion.confirmKeepEntry` or `messages.conflict.deletion.confirmKeepEntryAsCopy`, enabled when a journal is chosen |
| Keep deletion confirmation | `ContentDialog`, title `messages.conflict.deletion.confirmDeleteEdited.entry`, `.template` or `.journal` (an edited version), or `messages.conflict.deletion.confirmKeepDeleted.entry`, `.template` or `.journal` (both deleted). Content: the edited version's title (and an entry's date) with `messages.conflict.deletion.keepDeletionExplanation.*`, or the deletion's block (location `messages.conflict.deletion.deletionToKeep`) with `messages.conflict.deletion.remainingVersionsRemoved`; then `messages.conflict.deletion.consequence.sync`, `messages.conflict.deletion.consequence.copies`, `messages.conflict.deletion.consequence.noUndo`. Primary `messages.conflict.deletion.deletePermanently`, Close `common.cancel`, no default button | The one place nothing can be undone: Enter never chooses, and focus starts on Cancel. While it runs the content shows `messages.conflict.deletion.deleting` with an indeterminate `ProgressBar`, both buttons are disabled and the dialog cannot be dismissed |
| Progress | An indeterminate `ProgressBar` with `common.pleaseWait` | |
| Errors and recovery | An Error `InfoBar` (selectable text), then `messages.conflict.deletion.reviewAgain`, `common.reloadJournals`, or `common.exportArchive` when a version cannot be read; `messages.conflict.deletion.journalUnavailable`, `messages.conflict.deletion.updateToReview`, `messages.conflict.deletion.savedNotDisplayed` as the spec | Announced when they open |

### The unsupported review

`messages.conflict.updateToReview` as text, then `common.exportArchive` as a `Button`: the archive export of Settings ▸ Backup including its one-time password check ([export-archive](../flows/export-archive.md)), run from this page; its errors show in an Error `InfoBar`, and `messages.save.before.goBack` while a save has failed. Nothing can be resolved; both versions stay. Where the message says to update, a "Get updates" link opens the Microsoft Store's updates page (D51).

## Layout at each window width

| Width (epx) | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium, 641 and up | The page fills the content area (pane and list are replaced). One column, at most 600 epx wide, left-aligned with 24 epx margins. The journal review shows one version at a time with the `SelectorBar`; the deletion review stacks the two blocks | Mac sheet; iPad sheet |
| Small, 640 and down | Full-width page with 12 epx margins; the back button is the title bar's; the action buttons fill the width and stack | iPhone sheet |
| 200% text size or more | One layout narrower; the page scrolls; the version blocks and previews follow the text size; nothing is truncated | accessibility sizes |

The Changes to review cards follow the Sync page's layout ([settings-sync](../../../screens/settings-sync.md)): below 600 epx the trailing button wraps under the text.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-changes` | The entry notice; the Changes to review cards; the journal menus; the deleted journal's page; the unavailable-entry notice | none | Unlocked and the library not being replaced; the open entry is saved first |
| `journal-version-history` | A journal's page and menu | as in commands.md | Unchanged |

Keyboard: Alt+Left and the back button go back (not while a choice is being saved); Esc closes an open dropdown or dialog and never leaves the page; Tab order follows the reading order of the form: status, version selection, preview, actions; arrow keys move in the `SelectorBar` and in the journal chooser; Enter in the chooser chooses the confirm button only when a journal is selected. Dialogs follow [8.1](../platform.md#81-rules).

## Copy differences

Sentence case applies ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Review changes", "This device", "Other device", "Keep both", "Details", "Delete permanently". Ellipses follow 12.2: an ellipsis only where more input is needed.

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `messages.conflict.journal.keepVersion` | Keep Version… | Keep version | ellipsis (it only opens a confirmation) |
| `messages.conflict.deletion.keepDeletion` | Keep Deletion… | Keep deletion | ellipsis |
| `messages.conflict.deletion.keepEntry`, `messages.conflict.deletion.keepEntryAsCopy` | Keep Entry…, Keep Entry as Copy… | Keep entry…, Keep entry as copy… | casing; the ellipsis stays because a journal is chosen next |
| `common.exportArchive` | Export Archive… | Export archive… | casing |
| `messages.conflict.deletion.deletePermanently` | Delete Permanently | Delete permanently | casing |

## Accessibility

- The page heading is level 1 and the form's groups are headings; each version block, each journal summary pair and each Changes to review card is one element with its title and date. The icon in an entry row is hidden and the row's value says `messages.conflict.needsReview`.
- Errors in the journal and deletion reviews are `InfoBar`s that announce themselves when they open; a repeated message closes and reopens the bar. There is no success announcement: the page going back and the entry opening are the feedback.
- After Keep both or Keep version, focus moves to the resolved entry in the list or editor; after an error it moves to the bar's action. After Back from the journal chooser focus returns to the button that opened it.
- Confirmation dialogs are read when they open; Delete permanently is named in words, and no colour or icon is the only sign that it is destructive.
- Four contrast themes: cards use theme brushes and borders; previews use the editor's decorations in system colours. At 225% text size nothing truncates and the page scrolls.

## Different by design

- **A page with a back button**, not a sheet with Cancel and Done: Windows 11 uses pages for comparisons ([9](../platform.md#9-sheets-popovers-and-notices)).
- **The journal chooser is a level of the page**, with a breadcrumb crumb and the back button, not an inner screen of a sheet.
- **No Keep deletion default**: the destructive confirmation never has a default button and focus starts on Cancel.
- **Journal review entry points** are the pane row and the journal menus because Windows has no journal settings surface (D52).
- **Esc is not Back in any form**: Back is Alt+Left and the back button, and Esc dismisses transient surfaces only ([7.2](../platform.md#72-additions)). The Mac's Cancel has Escape in the entry and deletion forms and none in the journal form (an open question of the spec's own).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D50 (side by side reviews, deferred), D51 (update link), D52 (journal review entry point).
