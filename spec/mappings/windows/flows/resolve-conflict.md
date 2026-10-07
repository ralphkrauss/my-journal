---
id: resolve-conflict
title: Resolve changes to review (Windows)
spec: flows/resolve-conflict.md
features: [conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-journal, conflict-review-deletion, conflict-review-unsupported]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Resolve changes to review (Windows)

Conflicting edits are never overwritten silently: both versions are kept until the person chooses one, both, or the deletion, and both originals stay in Version history. What each choice does, the staleness rules and the outcomes are the spec's [resolve-conflict](../../../flows/resolve-conflict.md) and belong to the shared engine; the screens are [conflict-review](../screens/conflict-review.md) and [entry-conflict](../screens/entry-conflict.md). This file maps the route through the Windows app: navigation, what happens to the library behind the page, focus, and what each "something changed meanwhile" looks like.

## Controls

| Spec step | Windows realisation | Notes |
| --- | --- | --- |
| 1. Open the review | Review changes is a page ([conflict-review](../screens/conflict-review.md)). Choosing `review-changes` first awaits the open entry's save, then navigates; the back stack remembers the entry, the list position and the pane choice | If the save fails the page does not open and the alert dialog shows ([save-failure](save-failure.md)). The form is decided from the current versions when the page renders, so a review opened from a stale signal shows the right form or `messages.conflict.resolved` |
| 2a. Entry or template: Keep both; Keep version | Buttons on the page; the keep-one choice has a confirmation `ContentDialog` | [entry-conflict](../screens/entry-conflict.md). Keep both first saves the pending writing (`messages.save.before.resolveEntryConflict` inline in the page's error bar if it fails) |
| 2b. Journal: Keep version | A button and a confirmation dialog; the open entry is saved first (`messages.save.before.reviewChanges`) | |
| 2c. Deletion: Keep entry…, Keep entry as copy…, Keep template, Keep journal, Keep deletion | Buttons; the journal chooser is a deeper level of the page; Keep deletion has the destructive dialog | The review is prepared first, with `common.pleaseWait`; the open entry is saved first |
| 2d. Unsupported | Text and an Export archive button | |
| 3. When something changes meanwhile | The rows below | |
| 4. Outcome | The page goes back to where the person came from and the resolved entry opens (selected in the list, shown in the editor); no message and no announcement. For the Settings route the page goes back to Settings ▸ Sync, where the row has left the list, and focus moves to the next row or the group heading | The journals are read again first; "no success message" is the spec's |

### When something changes meanwhile

| What happened (spec) | Windows presentation |
| --- | --- |
| The versions changed while the page was open, or a choice was refused as stale | Entry form: reads again (progress `messages.conflict.updatingChanges`), then the Informational status bar `messages.conflict.status.updated`, This device shown (at large width both are shown), choice cleared, any confirmation dialog hidden, Narrator notified, focus on the version selector. Journal and deletion forms: `messages.conflict.updatedReviewAgain` as an Informational bar with Reload changes or Review again |
| Reading them again failed | Error bars as in [entry-conflict](../screens/entry-conflict.md) and [conflict-review](../screens/conflict-review.md); choices kept for retry; previews hidden |
| The choice was saved but showing the result failed | `messages.conflict.committedNotReloaded` with Try again (reloads only) and Done; or `messages.conflict.journal.savedNotDisplayed` with Reload; or `messages.conflict.deletion.savedNotDisplayed`. A saved choice is never applied twice |
| Resolved on another device | `messages.conflict.resolved` with Done |
| The chosen journal became unavailable | `messages.conflict.deletion.journalUnavailable` with `common.reloadJournals` |
| A version became unreadable | The page switches to the unsupported form |
| The app locked | The lock page replaces the window; the page and everything it showed are released; uncommitted work stops; after unlocking the library window returns, not the review |
| The library is being replaced | The page goes back (a connection or import flow replaces the library) |
| Any other failure | Its message as an inline bar; choices kept for retry |

## Layout at each window width

As [conflict-review](../screens/conflict-review.md) and [entry-conflict](../screens/entry-conflict.md). The flow adds nothing of its own: the route is a page push at every width, and the small layout's back button is the title bar's.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-changes` | The signals listed in [conflict-review](../screens/conflict-review.md) | none | Unlocked, not replacing the library |

Alt+Left and the back button go back; Esc never leaves the page. A choice has no shortcut: resolving is deliberate, and the destructive confirmation never has a default button ([8.1](../platform.md#81-rules)).

## Copy differences

None beyond the casing and ellipsis proposals in [conflict-review](../screens/conflict-review.md) and [entry-conflict](../screens/entry-conflict.md). Sentence case applies as in platform.md, 12.

## Accessibility

- Opening the page is a navigation, which Narrator reads from the page heading (`common.reviewChanges`); focus starts on the first control of the form (the version selector, or the first card).
- Errors are bars that announce themselves; a stale refresh is announced once by notification. There is no success announcement; the entry's focus is the feedback.
- Confirmation dialogs return focus to the button that opened them. After a cancelled confirmation nothing has changed.
- The flow works with the keyboard alone: every step is a button or a list; no step needs a pointer.

## Different by design

- **The review is a page that returns to where the person came from**, instead of a sheet over the window. The back stack replaces the Apple rule that the sheet closes and the entry opens.
- **Locking leaves the page behind.** The lock page replaces the window, so the review is not restored after unlocking; the Apple sheet closes for the same reason.
- **One version at a time at every width, as in the spec**; side by side is deferred (D50). Esc is not Back.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D50 (side by side reviews, deferred), D52 (journal review entry point).
