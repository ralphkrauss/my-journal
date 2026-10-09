---
id: resolve-conflict
title: Changes made on two devices (Windows)
spec: flows/resolve-conflict.md
features: [conflict-kept-both, changed-on-two-devices-list, conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-unsupported]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
---

# Changes made on two devices (Windows)

Nothing a person wrote is overwritten or lost when the same item changed on two devices. The shared engine settles journals and permanent deletions itself, keeps both versions and says so afterwards in a quiet list; entries and templates that differ are kept as two versions until the person chooses. What the device decides, when it decides, the staleness rules and the outcomes are the spec's [resolve-conflict](../../../flows/resolve-conflict.md) and belong to the shared engine. This file maps what the person sees on Windows: the quiet list, the route to the saved item, the route into the entry and template review, and what each "something changed meanwhile" looks like. The screens are [settings-sync](../screens/settings-sync.md), [conflict-review](../screens/conflict-review.md) and [entry-conflict](../screens/entry-conflict.md).

## Controls

### What the device settles itself (journals and permanent deletions)

| Spec | Windows |
| --- | --- |
| Journals and permanent deletions are settled by the device; nothing is asked | Nothing shows when it happens: no dialog, `InfoBar`, `InfoBadge`, sound or Narrator announcement, and nothing is added to the sync status flyout ([sync-status](../screens/sync-status.md)). The outcome appears in the Changed on two devices group of Settings ▸ Sync when the person next looks ([settings-sync](../screens/settings-sync.md)) |
| Rename, Delete journal and Restore journal are never blocked | The journal menus have no review item and nothing is dimmed for a conflict ([journals](../screens/journals.md)) |
| A held version (saved by a newer version) | One line `messages.conflict.kept.updateNeeded` on the Sync page; a journal that is held is listed like one saved by a newer version ([unavailable-content](../screens/unavailable-content.md)). The page has no button for it; where the person must update, the Microsoft Store's "Get updates" link (D51) applies |
| An edit against a permanent deletion is saved as a new entry or template | It is an ordinary item in Recently deleted, or in Unavailable journals when its journal is gone, where Restore (or Restore to “{name}”) brings it back ([recently-deleted](../screens/recently-deleted.md), [delete-and-restore](delete-and-restore.md)). If the item was open, the editor moves to the new entry without losing the text, draft or cursor |
| What 1.0 left pending | Settled once when the library opens, silently, and listed in the group |

### Open a Changed on two devices row

| Step | Windows |
| --- | --- |
| Activate a row that opens something (`open-kept-note`) | Click, tap, or Enter or Space on the focused card. The Settings page is left and the library window shows the collection that holds the saved item (Recently deleted, or Unavailable journals when its journal is gone) with the item selected and open, read-only, with its recovery notice. Back returns to Settings ▸ Sync. Nothing is saved or changed by opening it |
| The item no longer exists | The card has already been removed silently; if it goes between rendering and activation nothing happens and the card disappears |
| Rows with nothing to open (a journal rename, a journal deleted) | Plain text; there is no control |
| Clear list (`clear-kept-notes`) | Forgets every note at once, without a dialog; the group disappears. The notes are local to this PC and are not synced |

### Entries and templates (the review)

| Spec step | Windows realisation | Notes |
| --- | --- | --- |
| 1. Open the review | Review changes is a page ([conflict-review](../screens/conflict-review.md)). Choosing `review-changes` first awaits the open entry's save, then navigates; the back stack remembers the entry, the list position and the pane choice | If the save fails the page does not open and the alert dialog shows ([save-failure](save-failure.md)). The form is decided from the current versions when the page renders, so a review opened from a stale signal shows the right form or `messages.conflict.resolved` |
| 2a. Entry or template: Keep both; Keep version | Buttons on the page; the keep-one choice has a confirmation `ContentDialog` | [entry-conflict](../screens/entry-conflict.md). Keep both first saves the pending writing (`messages.save.before.goBack` inline in the page's error bar if it fails) |
| 2b. Unsupported | Text and an Export archive button | |
| 3. When something changes meanwhile | The rows below | |
| 4. Outcome | The page goes back to where the person came from and the resolved entry opens (selected in the list, shown in the editor); no message and no announcement. For the Settings route the page goes back to Settings ▸ Sync, where the row has left the list, and focus moves to the next row or the group heading | The journals are read again first; "no success message" is the spec's |

### When something changes meanwhile

| What happened (spec) | Windows presentation |
| --- | --- |
| The versions changed while the page was open, or a choice was refused as stale | Reads again (progress `messages.conflict.updatingChanges`), then the Informational status bar `messages.conflict.status.updated`, This device shown (at large width both are shown), choice cleared, any confirmation dialog hidden, Narrator notified, focus on the version selector |
| Reading them again failed | Error bars as in [entry-conflict](../screens/entry-conflict.md); choices kept for retry; previews hidden |
| The choice was saved but showing the result failed | `messages.conflict.committedNotReloaded` with Try again (reloads only) and Done. A saved choice is never applied twice |
| Resolved on another device | `messages.conflict.resolved` with Done |
| A version became unreadable | The page switches to the unsupported form |
| The app locked | The lock page replaces the window; the page and everything it showed are released; uncommitted work stops; after unlocking the library window returns, not the review |
| The library is being replaced | The page goes back (a connection or import flow replaces the library) |
| Any other failure | Its message as an inline bar; choices kept for retry |

## Layout at each window width

As [settings-sync](../screens/settings-sync.md), [conflict-review](../screens/conflict-review.md) and [entry-conflict](../screens/entry-conflict.md). The flow adds nothing of its own: the review route is a page push at every width, and the small layout's back button is the title bar's.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-changes` | The signals listed in [conflict-review](../screens/conflict-review.md) | none | Unlocked, not replacing the library |
| `open-kept-note` | A card of the Changed on two devices group | none | Unlocked; the item still exists; the card has something to open |
| `clear-kept-notes` | The group's text button | none | Unlocked |

Alt+Left and the back button go back; Esc never leaves the page. A choice has no shortcut: resolving is deliberate, and the confirmation never has a default button ([8.1](../platform.md#81-rules)).

## Copy differences

None beyond the casing and ellipsis proposals in [conflict-review](../screens/conflict-review.md) and [entry-conflict](../screens/entry-conflict.md); the group's header is "Changed on two devices" in sentence case. Sentence case applies as in platform.md, 12.

## Accessibility

- Opening the review page is a navigation, which Narrator reads from the page heading (`common.reviewChanges`); focus starts on the first control of the form (the version selector, or the first card).
- Errors are bars that announce themselves; a stale refresh is announced once by notification. There is no success announcement; the entry's focus is the feedback. Settling a journal or a deletion is silent; the group in Settings is where it is found.
- Confirmation dialogs return focus to the button that opened them. After a cancelled confirmation nothing has changed.
- The flow works with the keyboard alone: every step is a button, a card or a list; no step needs a pointer.

## Different by design

- **The review is a page that returns to where the person came from**, instead of a sheet over the window. The back stack replaces the Apple rule that the sheet closes and the entry opens.
- **Locking leaves the page behind.** The lock page replaces the window, so the review is not restored after unlocking; the Apple sheet closes for the same reason.
- **One version at a time at every width, as in the spec**; side by side is deferred (D50). Esc is not Back.
- **Opening a note leaves Settings** for the library, where Apple closes the Settings sheet on iPhone and iPad and brings the library window forward on the Mac.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D50 (side by side reviews, deferred).
