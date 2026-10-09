---
id: restore-journal
title: Restore journal and Restore entry (Windows)
spec: screens/restore-journal.md
features: [restore-journal, restore-entry]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Restore journal and Restore entry (Windows)

One confirmation that restores a deleted journal with the entries deleted with it, or restores an entry together with its deleted journal. Behaviour, states, rules and copy keys are the spec's [restore-journal](../../../screens/restore-journal.md); how the entry reaches it is the recovery notice of [recently-deleted](recently-deleted.md); the wider flow is [delete-and-restore](../flows/delete-and-restore.md).

## Controls

One `ContentDialog`, default width (up to 548 epx), content scrolling, **no default button** (the spec gives Restore no Return shortcut, [8.1](../platform.md#81-rules), rule 3). It is the only confirmation; nothing is restored until the person presses the button.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Title | `library.restoreJournal.title` or `library.restoreEntry.title` | |
| Restore entry only: the entry | A `StackPanel`: the entry's title (`Subtitle` style), its date (year, month, day, in the user's format, secondary), then `library.restoreEntry.needsJournal` | |
| The journal | Its name (`Subtitle` style; `common.untitledJournal` when blank) and `library.recentlyDeleted.journalCount` (secondary, singular and plural) | |
| Explanation | `TextBlock`: `library.restoreJournal.explanation` or `library.restoreEntry.explanation` | |
| Earlier-version entries | `library.restoreJournal.legacy`, secondary, when it applies | |
| Name taken | `common.restoredAsRenamed` as a Warning `InfoBar` (not closable) when another journal in use has the name | The restored journal gets a number |
| Error | An Error `InfoBar` with selectable text | Announced when it opens |
| Progress | An indeterminate `ProgressBar` with `common.pleaseWait`; the buttons and recovery links are disabled; the dialog cannot be dismissed | |
| The confirming action | `PrimaryButton` `library.restoreJournal.title` (Restore journal) or `common.restore` (Restore entry), accent style but not the default button | Hidden (empty `PrimaryButtonText`) until the check that opening the dialog starts has succeeded, as the spec requires |
| Close | `CloseButton` `common.cancel`, or `common.done` once the action completed | Esc is Close |
| Recovery actions | `HyperlinkButton`s in the content, only when they apply: `common.tryAgain`, `library.restoreJournal.reviewEntry`, `common.trySyncingAgain`, `common.reviewChanges`, and `common.exportArchive` for content saved by a newer version | Review changes closes the dialog and opens the review page ([conflict-review](conflict-review.md)); going back from it reopens this dialog for the same item and the check runs again. If the changes were resolved meanwhile the review shows `messages.conflict.resolved` with `common.done` |

### Opening and restoring

Opening saves the open entry and checks the journal (and entry); until the check succeeds only Close is shown. Restore returns the journal to its place in the order (or the end) with every entry deleted with it, including entries that sync later; entries deleted separately stay in Recently deleted; for Restore entry the entry returns too. The dialog closes and the journal is shown (Restore entry: with the entry open).

### States

| State | Windows |
| --- | --- |
| Busy | Everything disabled; not dismissable |
| Missing journal | `library.restoreJournal.unavailableLocal`, or `common.journalNotArrived` with `common.trySyncingAgain` when the library syncs; and Export archive |
| Changes to review | `messages.lifecycle.needsReview` with Review changes |
| Already restored | The journal is shown and the dialog says `messages.lifecycle.alreadyRestored` (Close becomes Done), or `messages.save.before.goBack` when the open entry cannot be saved; Restore entry then offers Review entry (`messages.restore.alreadyRestored`), which shows the entry where it is now |
| Errors | `messages.lifecycle.changedContinue` (then Try again and a new explicit Restore), `messages.save.before.goBack`, `messages.lifecycle.unsupportedJournal`, `messages.restore.changed`, `messages.restore.unavailable`, `messages.error.unsupportedFormat`, `messages.lifecycle.missingJournal`, `messages.lifecycle.alreadyDeleted` — all in the dialog's error bar |
| Stored but not shown | `messages.refresh.journalRestored` or `library.restoreEntry.displayFailed` in the error bar; Close becomes Done; restoring is not offered again |
| Locked | The dialog hides and nothing is restored if it had not started |

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Dialog 360 to 548 epx wide; the content scrolls, names wrap | Mac sheet 360–460 pt |
| Small | Fills the window width | iPhone sheet |
| 200% text size or more | Names and explanations wrap; the dialog scrolls and keeps its buttons in reach | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `restore-journal` | Button on a deleted journal's page ([recently-deleted](recently-deleted.md)) | none | Not while the library is being replaced |
| `restore-with-journal` | The recovery notice's action | none | The entry's journal is also deleted, the entry is editable and nothing is awaiting review |
| `try-syncing-again` | The recovery link | none | The journal is missing and the library syncs |
| `review-changes` | The recovery link | none | The journal has changes to review |

Keyboard: Tab reaches the recovery links and the Restore button; Enter does nothing unless a button has focus; Esc closes unless busy.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "Restore journal", "Restore entry", "Review entry". `common.restore` is already the verb. No other differences.

## Accessibility

- Narrator reads the title, then the name and counts, then the explanation, then any warning; errors are read when their bar opens; counts use singular and plural forms.
- Focus starts on the first link when one is shown, otherwise on Close (Restore is not focused first because it is not the default); after the check succeeds the person Tabs to Restore.
- After closing, focus returns to the button or notice that opened the dialog, or to the restored journal or entry.
- At 225% text size everything wraps; contrast themes use theme brushes.

## Different by design

- **No default button and the verb is the Primary button**; Apple's left-aligned prominent action becomes the leftmost dialog button, with Cancel at the right.
- **Review changes closes the dialog and reopens it on return**, instead of nesting a sheet, because a page cannot sit inside a dialog.
- **Hiding the confirming button until the check succeeds** uses the dialog's empty button text.

## Open questions

None.
