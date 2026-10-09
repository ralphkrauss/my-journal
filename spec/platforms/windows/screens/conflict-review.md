---
id: conflict-review
title: Review changes and the list (Windows)
spec: screens/conflict-review.md
features: [conflict-notice, changes-to-review-list, conflict-review-unsupported]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
---

# Review changes and the list (Windows)

When the same entry or template changed on this device and on another and the two versions differ, both are kept and the person decides. This file maps where changes to review are signalled, the Changes to review list, how the Review changes page chooses its form, and the unsupported form. The entry and template form is [entry-conflict](entry-conflict.md); what each choice does is [resolve-conflict](../flows/resolve-conflict.md). Behaviour, states, rules and copy keys are the spec's [conflict-review](../../../screens/conflict-review.md).

Journals and permanent deletions have no review on Windows: the device settles them itself and lists them in Settings ▸ Sync under Changed on Two Devices ([settings-sync](settings-sync.md), [resolve-conflict](../flows/resolve-conflict.md)). A version of a journal this app cannot read stays held and is told only by a line in the Sync page's footer.

## Controls

### A page, not a dialog

Review changes is a **page** in the window's content area, with a back button and a `BreadcrumbBar` ([9](../platform.md#9-sheets-popovers-and-notices)): the library panes are replaced and return exactly as they were. Reasons: the forms compare two versions and show previews, which need the width a dialog does not have; a person must be able to read a version for as long as they need; and a page leaves the confirmations as the only dialogs, so the one-dialog rule ([8.1](../platform.md#81-rules)) is never in the way. Locking replaces the whole window with the lock page, so the page is simply gone and nothing it showed remains ([13](../platform.md#13-device-authentication-and-app-lock)).

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Where the review opens from | Page navigation in the main window's `Frame`; the back stack returns to where the person came from (the entry, Settings ▸ Sync, Move entry's dialog) | Opening first saves the open writing; if that fails the page does not open and the alert dialog shows ([save-failure](../flows/save-failure.md)) |
| Title and header | A back button and a `BreadcrumbBar`: the record's title, then `common.reviewChanges`. The page heading `common.reviewChanges` is heading level 1 | Back (Alt+Left, the back button and the breadcrumb) is the spec's Cancel; it is disabled while a choice is being saved. Esc is not Back |
| Done | After a completed or already resolved review, a `Button` `common.done` (accent) next to the message, which goes back | Replaces the spec's Cancel-becomes-Done |
| Form chosen on each render | One content region swapped by the same conditions as the spec's table: locked, entry or template ([entry-conflict](entry-conflict.md)), unsupported, resolved | |
| Locked | `messages.conflict.locked` is never visible: locking removes the page. If the page renders while the lock races, the text is shown in the page's error bar for the moment | |

### Where changes to review are signalled

| Where (spec) | Windows | Opens |
| --- | --- | --- |
| The open entry or template: notice above the writing | The Warning `InfoBar` of [entry-editor](entry-editor.md): `messages.conflict.entryNotice`, `ActionButton` `common.reviewChanges` | the review of that record |
| Entries list row marker | Icon Error (E783) at the row's trailing end; the row's Narrator value includes `messages.conflict.needsReview` ([entry-list](entry-list.md)) | the entry, by selecting it |
| Settings ▸ Sync ▸ Changes to Review | The group below | the review of that row |
| Move entry of an entry with changes to review, when the conflict blocks the move | `common.reviewChanges` in the dialog's error bar ([move-entry](move-entry.md)) | the review of that entry |

A journal has no marker and no review. Windows shows no attention dot on a journal's row in the navigation pane, no `InfoBar` at the top of a journal's entry list and no `common.reviewChanges` item in the journal menus; Rename and Delete journal… are never dimmed for a conflict ([journals](journals.md)). A journal whose conflict is held behaves like one saved by a newer version ([unavailable-content](unavailable-content.md)).

Delete permanently on an entry or template with changes to review is refused like an item that changed meanwhile ([delete-and-restore](../flows/delete-and-restore.md)); there is no separate alert.

### Changes to review (Settings ▸ Sync)

In the Sync page, a group headed `messages.conflict.settingsSection` (a sub-heading `TextBlock`, level 2), shown only when the app is unlocked and at least one entry or template has changes to review, including those saved by a newer version. It sits beside Changed on Two Devices ([settings-sync](settings-sync.md)). One `SettingsCard` per record, in the store's order, `IsClickEnabled` false:

| Spec element | Control | Notes |
| --- | --- | --- |
| Title | The card's `Header`: the record's display title (this device's version) | Wraps; no truncation |
| Date and time | The card's `Description`: the record's date and time, in the user's regional format ([31](../platform.md#31-dates-time-zones-and-formats)) | |
| Review changes | A `Button` in the card's trailing area, `common.reviewChanges`; `AutomationProperties.Name` `common.reviewChangesFor` | Opens the review page |

### The unsupported review

`messages.conflict.updateToReview` as text, then `common.exportArchive` as a `Button`: the archive export of Settings ▸ Backup including its one-time password check ([export-archive](../flows/export-archive.md)), run from this page; its errors show in an Error `InfoBar`, and `messages.save.before.goBack` while a save has failed. Nothing can be resolved; both versions stay. Where the message says to update, a "Get updates" link opens the Microsoft Store's updates page (D51).

## Layout at each window width

| Width (epx) | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium, 641 and up | The page fills the content area (pane and list are replaced). One column, at most 600 epx wide, left-aligned with 24 epx margins. The entry and template review shows one version at a time ([entry-conflict](entry-conflict.md)) | Mac sheet; iPad sheet |
| Small, 640 and down | Full-width page with 12 epx margins; the back button is the title bar's; the action buttons fill the width and stack | iPhone sheet |
| 200% text size or more | One layout narrower; the page scrolls; the previews follow the text size; nothing is truncated | accessibility sizes |

The Changes to review cards follow the Sync page's layout ([settings-sync](../../../screens/settings-sync.md)): below 600 epx the trailing button wraps under the text.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-changes` | The entry notice; the Changes to review cards; the Move entry dialog's error bar | none | Unlocked and the library not being replaced; the open entry is saved first |

Keyboard: Alt+Left and the back button go back (not while a choice is being saved); Esc closes an open dropdown or dialog and never leaves the page; Tab order follows the reading order of the form: status, version selection, preview, actions; arrow keys move in the `SelectorBar`. Dialogs follow [8.1](../platform.md#81-rules).

## Copy differences

Sentence case applies ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Review changes", "This device", "Other device", "Keep both", "Details". Ellipses follow 12.2: an ellipsis only where more input is needed.

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `common.exportArchive` | Export Archive… | Export archive… | casing |

## Accessibility

- The page heading is level 1 and the form's groups are headings; each version block and each Changes to review card is one element with its title and date. The icon in an entry row is hidden and the row's value says `messages.conflict.needsReview`.
- Errors on this page are `InfoBar`s that announce themselves when they open; a repeated message closes and reopens the bar. There is no success announcement: the page going back and the entry opening are the feedback.
- After Keep both or a version is kept, focus moves to the resolved entry in the list or editor; after an error it moves to the bar's action.
- No colour or icon is the only sign that an action is destructive.
- Four contrast themes: cards use theme brushes and borders; previews use the editor's decorations in system colours. At 225% text size nothing truncates and the page scrolls.

## Different by design

- **A page with a back button**, not a sheet with Cancel and Done: Windows 11 uses pages for comparisons ([9](../platform.md#9-sheets-popovers-and-notices)).
- **No journal or deletion review**: the device settles them itself, so there is no journal entry point to map (open question D52 no longer applies).
- **Esc is not Back in any form**: Back is Alt+Left and the back button, and Esc dismisses transient surfaces only ([7.2](../platform.md#72-additions)). The Mac's Cancel has Escape in the entry and unsupported forms.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D50 (side by side reviews, deferred), D51 (update link).
