---
id: recently-deleted
title: Recently deleted (Windows)
spec: screens/recently-deleted.md
features: [recently-deleted, restore-entry, restore-and-move, restore-journal, delete-permanently, delete-all-deleted, unavailable-journals]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Recently deleted (Windows)

The Recently Deleted collection, a deleted journal's page, the recovery notice and Delete All. Behaviour and copy keys are the spec's [recently-deleted](../../../screens/recently-deleted.md); the list is the [entry list](entry-list.md) with the differences below.

## Controls

| Spec element | Control | Notes |
| --- | --- | --- |
| Title and subtitle | List header: `common.recentlyDeleted` with `common.itemCount` or `library.window.subtitle.noItems` | |
| Explanation and Delete all (Mac bar) | In the list header: a `Caption` secondary `TextBlock` `library.recentlyDeleted.footer` under the title, and a `Button` (plain, default tint, not red) `library.recentlyDeleted.deleteAll` at the trailing end with a `ToolTip` `library.recentlyDeleted.deleteAll.help`, or `library.recentlyDeleted.deleteAll.helpSearching` while a search is active | Shown when the list has something; disabled with the searching tooltip while a search is active, as on the Mac, so the explanation of why stays in reach. The header scrolls with nothing: it is part of the header, not the list |
| Sections | A grouped `ListView`: group Journals (`common.journals`); group Templates (`library.journals.templates`); group Entries, whose first month header is preceded by a header `library.recentlyDeleted.section.entries`, then month groups as entry-list | Each group only when it has rows |
| Deleted journal row | Name (`common.untitledJournal` when blank) and under it `library.recentlyDeleted.journalCount`; icon Library | Narrator value `library.entryList.journalValue` |
| Deleted template row | Entry-style row; Narrator value `library.entryList.templateValue` | |
| Row context menu and Entry actions | Image descriptions… and Version history… (read-only); Restore (`common.restore`, icon Undo E7A7) when the entry's journal is in use and it was not deleted with its journal by an earlier version, or a template; then a separator and Delete permanently (`library.entryActions.deletePermanently`, icon Delete), the spec's order | Pin, Change date, Move entry, Save as template and Delete entry are not offered |
| Swipe | Leading Restore (`SwipeControl`), trailing Delete (`common.delete`, Execute), touch and pen only | A swipe never removes the row before the question: on Windows the trailing swipe opens the Delete permanently dialog and the row stays until the person confirms, so no row has to be brought back |
| Opening an item | Entry or template: read-only in the editor with the recovery notice above the title. Deleted journal: the detail below in the editor pane | |
| Empty | `library.entryList.empty.noDeletedItems`, no Delete all. A deleted journal or template counts as content | |
| Search | The search box prompt `library.search.deleted`; no results: `library.entryList.empty.noResults` with `library.entryList.empty.clearSearch` | [search](search.md) |

### Deleted journal's page (editor pane)

Replaces the editor with a `StackPanel` in the 760 epx column:

1. Title: the journal's name, `TitleTextBlockStyle`, heading level 1.
2. `library.recentlyDeleted.journalCount`, secondary.
3. `Button` (accent) `library.recentlyDeleted.restoreJournal` opening [restore-journal](../../../screens/restore-journal.md); or, for a journal saved by a newer version, the text `messages.unavailable.restoreJournalNeedsUpdate` and a `HyperlinkButton` `common.exportArchive` that opens Settings ▸ Backup.
4. `HyperlinkButton` `common.reviewChanges` when the journal has changes to review.
5. `HyperlinkButton` `common.versionHistoryEllipsis` when the journal has saved versions.
6. `Button` `library.entryActions.deletePermanently`, with the destructive treatment of [8.1](../platform.md#81-rules) (no special colour required).

All disabled while the library is being replaced.

### Recovery notice

An `InfoBar` above the title of a read-only entry or template opened from Recently deleted or Unavailable journals: `Severity` Informational, `IsOpen` while the item is shown, `IsClosable` false, `IsIconVisible` true, message from the spec's table, actions as `ActionButton`s of the bar (the first) and a `HyperlinkButton` in the bar's `Content` (the second). One `InfoBar` allows one action button, so a second action uses the content area. At 200% text size or more the bar's height is capped at half the editor pane and scrolls.

| Situation | Message | Actions |
| --- | --- | --- |
| Template in Recently deleted | `library.recoveryNotice.template` | `common.restore` (if editable) |
| Entry in Recently deleted, journal in use | `library.recoveryNotice.entry` | `common.restore`; `library.recoveryNotice.restoreAndMove` |
| Entry in Recently deleted, journal also deleted, editable, no changes to review | `library.recoveryNotice.entry` | `library.recoveryNotice.restoreWithJournal` (a dialog, [restore-journal](../../../screens/restore-journal.md)); `library.recoveryNotice.restoreAndMove` |
| Entry deleted with its journal by an earlier version | `library.recoveryNotice.legacy` | `library.recoveryNotice.restoreAndMove` |

Unavailable-journal reasons are in [unavailable-content](unavailable-content.md). Restore and move opens [move-entry](move-entry.md) in its restoring form. Restore runs at once without confirmation. As in [delete-and-restore](../flows/delete-and-restore.md) and the spec, it returns an entry to its journal, which is shown with the entry open (a template: Templates, shown with the template open); pins come back.

### Delete permanently

`ContentDialog`: title `library.deletePermanently.title` with the item's name (`library.entryList.untitledEntryInAlert`, `library.entryList.untitledTemplate` or `common.untitledJournal` when blank), or `library.deletePermanently.titleWithEntries` for a journal with entries; content `library.deletePermanently.journalEntries` (journal with entries) then `library.deletePermanently.retention`; Primary `common.delete`, Close `common.cancel`, no default button. The open entry is saved and the item checked first. On Delete the row, and for a journal its entries' rows, leave at once and an open item closes. Failures use the general error dialog with the spec's messages.

### Delete all

A `ContentDialog` shaped by the spec's rules: the button is disabled while the list is checked; one item (or one journal with entries) shows the Delete permanently dialog; one kind shows `library.deleteAll.title.entries`, `library.deleteAll.title.templates` or `library.deleteAll.title.journals`; several kinds show `library.deleteAll.title.items`, with content starting `library.deleteAll.includes` (counts joined with the system list format), then the held sentence (`library.deleteAll.held.review`, `library.deleteAll.held.newerVersion` or `library.deleteAll.held.other`), always last `library.deletePermanently.retention`. Primary `common.delete`, Close `common.cancel`, no default button. When nothing can be deleted there is no confirmation: a dialog titled `library.deleteAll.nothing.title`, content `library.deleteAll.nothing.review`, `library.deleteAll.nothing.newerVersion` or `library.deleteAll.nothing.other`, Close `common.ok`. Items that changed in between stay, and a dialog says `library.deleteAll.changed.title` with `library.deleteAll.changed.message`. Progress is the dialog's indeterminate `ProgressBar` while items are checked and deleted; the dialog's buttons are disabled meanwhile, as the spec disables the button.

## Layout at each window width

As [entry-list](entry-list.md). The deleted journal's page replaces the editor pane at large and medium widths; at small width it is the page after the list. The Delete all button moves into the list page's command bar at small width.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `restore` | Row context menu; Entry actions; recovery notice; leading swipe | none | See Controls; at once, no confirmation |
| `restore-with-journal`, `restore-and-move` | Recovery notice | none | As the notice table |
| `restore-journal` | Button on a deleted journal's page | none | Not while the library is being replaced |
| `try-syncing-again` | Recovery notice (unavailable) | none | |
| `delete-permanently` | Row context menu; Entry actions; a deleted journal's page | Delete, Shift+Delete | Focus in the list with an entry or template selected; both keys ask. Elsewhere Shift+Delete is not bound |
| `delete-all-recently-deleted` | File menu (after a separator); the list header button | Ctrl+Shift+Delete | Recently deleted is shown, has rows, has no search, no Delete all is running, and the library is open, unlocked and not being replaced |
| `review-changes` | Deleted journal's page; notice | none | The journal has changes to review |
| `journal-version-history` | Deleted journal's page | none | The journal has saved versions |

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `library.recentlyDeleted.deleteAll` | Delete All on iPhone and iPad, Delete All… on the Mac | Delete all | ellipsis (platform.md, 12.2) |
| `library.menu.file.deleteAll` | Delete All in Recently Deleted… | Delete all in Recently deleted | ellipsis and casing (platform.md, 12.2) |
| `library.entryActions.deletePermanently` | Delete Permanently… | Delete permanently | ellipsis (platform.md, 12.2) |
| `library.deletePermanently.title`, `library.deletePermanently.titleWithEntries` | Delete “{name}” Permanently? | Delete “{name}” permanently? | casing |

## Accessibility

- The explanation and Delete all are the first elements of the list header, before the list. The button's name is `library.recentlyDeleted.deleteAll` with its tooltip as the description.
- Deleted journal rows read name, count and "Journal"; template rows read "Template".
- After Cancel in a Delete permanently dialog focus returns to the row. After Delete all empties the list, focus moves to the list's empty state, which is read as `library.entryList.empty.noDeletedItems`; there is no extra announcement.
- The recovery notice is announced when it opens (an `InfoBar` raises its own notification) and its buttons are in the tab order after the title bar of the editor pane and before the title.
- The Delete all button is a plain text button in the default tint, not red, as in Notes and Photos.

## Different by design

- **Swipe never removes the row first.** On iPhone a destructive swipe removes the row before the alert asks and Cancel brings it back, because SwiftUI cannot keep a swipe open behind an alert. A `SwipeControl` item can stay put while the dialog is open, so Windows asks first.
- **The explanation and Delete all are in the header on every layout**, as on the Mac, not in a footer and a bar button.
- **Delete all has no ellipsis** and the dialog has no default button ([8.1](../platform.md#81-rules)).
- **Recovery notice is an `InfoBar`** with a hyperlink for the second action, not a tinted band.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose).
