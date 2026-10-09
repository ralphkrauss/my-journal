---
id: version-history
title: Version history, entries and templates (Windows)
spec: screens/version-history.md
features: [version-history, restore-version]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/combo-box
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Version history, entries and templates (Windows)

See earlier versions of an entry or template and copy one back as a new entry or template. The current item and its history are never changed. Behaviour, states, rules and copy keys are the spec's [version-history](../../../screens/version-history.md). Journals have no version history: a name changed by mistake is changed back with Rename ([journals](journals.md)).

## Controls

A **page** in the window's content area with a back button and a `BreadcrumbBar` ([9](../platform.md#9-sheets-popovers-and-notices)): the library panes are replaced and return exactly as they were. The preview needs the width; a dialog would squeeze it, and restoring can raise a second step (a new journal) that is easier as a dialog over a page than as a step inside a dialog. Opening the page saves the open entry first.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Header | The back button and a `BreadcrumbBar`: the entry's title (`library.entryList.untitledEntry` or `library.entryList.untitledTemplate` when blank), then `editor.history.title` | Heading level 1 is `editor.history.title`. Back (Alt+Left, the back button, the breadcrumb) is the spec's Done: it closes and changes nothing. Esc is not Back. It is disabled while restoring. There is no Done button, as on the Settings pages |
| Loading | An indeterminate `ProgressBar` along the top with `editor.history.loading` in secondary text | |
| No versions | A centred secondary `TextBlock` `editor.history.empty` | |
| Version picker | A `ComboBox`, `Header` `common.version`, `PlaceholderText` `editor.history.chooseVersion`; items newest first, each named by when it was made (abbreviated date and time with seconds, in the user's regional format, [31](../platform.md#31-dates-time-zones-and-formats)); names that read the same are `editor.history.versionDuplicate` (numbered 1, 2, … in list order) | The drop-down wraps long names. Choosing shows the version and loads its images |
| Preview | A heading with the version's title (`Subtitle` style), for entries its date (secondary), then the editor control in read-only mode, at least 220 epx tall, formatting and images as in the entry ([entry-editor](entry-editor.md)); the text is selectable and copyable | A version in a format this version cannot read shows `editor.history.updateToRestore` and a `Button` `common.exportArchive` instead (the archive export of Settings ▸ Backup with its one-time password check, [export-archive](../flows/export-archive.md)) |
| Journal picker (entries) | A `ComboBox`, `Header` `editor.history.journalLabel`, `PlaceholderText` `common.chooseJournal`, listing every journal in use; same-named journals show as `editor.history.journalDuplicate` (name, creation date and time, number); a journal without a name is `common.untitledJournal`. Initially the entry's own journal when it is in use, otherwise none | Below it a `HyperlinkButton` `common.newJournalEllipsis`, which opens the New journal dialog over the page ([destination-journal](destination-journal.md)); creating a journal does not select it or restore anything. With no journals: `editor.history.createJournalFirst` and the same button |
| Restore | A `Button` (accent) `editor.history.restoreAsNewEntry`, or `editor.history.restoreAsNewTemplate` for a template | Enabled as the spec's table: a readable version, for entries a journal in use, not loading, restoring or restored, unlocked. Not the default button: Enter belongs to the combo boxes |
| Error | An Error `InfoBar` with selectable text above the buttons; the spec's recovery buttons next to it: `editor.history.reload`, `common.reloadJournals` | Announced when it opens |
| Restored but not shown | An Informational bar `editor.history.restored` or `editor.history.restoredTemplate`; Restore is hidden | |
| Working | The controls disabled, an indeterminate `ProgressBar` with `editor.history.loadingJournals` or `editor.history.restoring`; back disabled | |

### States and actions

The spec's table applies as written. Windows presentation of the notable rows:

| State | Windows |
| --- | --- |
| Open entry could not be saved first | Opening: the page does not open and the alert dialog explains. Restoring: `messages.save.before.goBack` in the page's error bar; the chosen version and journal are kept |
| Version gone | `messages.history.versionUnavailable` with Reload history |
| Journal gone | `messages.history.chooseJournal` in the bar; the journal picker clears; also when the chosen journal disappears while the page is open |
| Chosen journal saved by a newer version | `messages.lifecycle.unsupportedJournal` in the page's error bar |
| Restoring succeeded | The page goes back; the copy opens in the editor with its journal or Templates shown |
| Locked | The lock page replaces the window: the page, previews and the work are released; a copy already committed stays |

## Layout at each window width

| Width (epx) | Presentation | Apple equivalent |
| --- | --- | --- |
| Large, 1008 and up | Two columns. Left, 320 to 360 epx: the version picker, the journal picker, New journal, Restore, then the bar. Right: the preview filling the height, its text column at most 760 epx. The versions and the version shown are side by side | Mac sheet 360–600 × 420–620 pt |
| Medium, 641 to 1007 | One column at most 600 epx wide: the pickers and Restore first, the preview below | iPad sheet |
| Small, 640 and down | One full-width column with 12 epx margins; the back button is the title bar's; Restore fills the width | iPhone sheet |
| 200% text size or more | One layout narrower; values wrap; the page scrolls and nothing truncates | accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `entry-version-history` | Entry actions; the entry row's context menu | none | Always, including items in Recently deleted |
| `new-journal` | The link under the journal picker | as in commands.md | Not while restoring or while the library is being replaced |
| `export-archive` | The button under a version in a newer format | none | The version cannot be read here |

Keyboard: Tab goes through the pickers, the link, Restore; Up and Down change the selection of an open combo box; Alt+Left goes back unless restoring (Esc closes an open drop-down and never leaves the page). Restore has no accelerator.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Version history", "Restore as new entry", "Restore as new template", "Reload history", "Choose a version", "No earlier versions". `common.versionHistoryEllipsis` keeps its ellipsis ("Version history…") because it opens a page that asks for a choice. No other differences.

## Accessibility

- The combo boxes read their header and value ("Version, 6 Oct 2026 at 10:42:07"); the preview is the editor in read-only mode, so Narrator reads the version's text, headings and image descriptions as in an entry, and its help text names the version.
- Errors are bars that announce themselves; the restoring and loading text is also in the live progress text, never only the bar.
- After Restore the page goes back and focus moves to the copy in the list or the editor. After a cancelled New journal dialog focus returns to the link.
- All controls work at 225% text size; values wrap. In contrast themes the preview and cards use theme brushes.

## Different by design

- **A page with the versions beside the preview** where Apple has a sheet; the actions are the same.
- **No Done button**: Back is Done, as in the Settings pages.

## Open questions

None.
