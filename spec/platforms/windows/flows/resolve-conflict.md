---
id: resolve-conflict
title: Changes made on two devices (Windows)
spec: flows/resolve-conflict.md
features: [conflict-kept-both, kept-both-notice, changed-on-two-devices-list]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
---

# Changes made on two devices (Windows)

Nothing a person wrote is overwritten or lost when the same item changed on two devices, and nobody is asked. The shared engine settles every conflict it can read: an entry or template that differs keeps both versions as two separate items, a journal keeps one name, and a permanent deletion stays final with the edit saved next to it. What the engine decides, when it decides, the copy rule (title, identity, replacement, the bound) and the pass over what 1.0 left are the spec's [resolve-conflict](../../../flows/resolve-conflict.md) and the contract [protocol/conflicts.md](../../../../protocol/conflicts.md); they belong to the shared engine and Windows implements them exactly. The pass over what 1.0 left applies to a library restored from an archive that carries such conflicts. This file maps what the person sees on Windows: nothing at the moment, then the notice above the open entry or template ([kept-version-notice](../screens/kept-version-notice.md)) and the quiet list ([settings-sync](../screens/settings-sync.md)).

## Controls

| Spec | Windows |
| --- | --- |
| Conflicts are settled by the device; nothing is asked | Nothing shows when it happens: no dialog, `InfoBar`, `InfoBadge`, sound or Narrator announcement, and nothing is added to the sync status flyout ([sync-status](../screens/sync-status.md)). A notice may appear above the open entry or template when the cursor is not resting in it, and the outcome appears in the Changed on two devices group of Settings ▸ Sync when the person next looks |
| An entry or template that differs: this device's version stays, the other becomes a copy "{title} (other version)" | The copy is an ordinary entry or template in the list, next to the original, with its own date; Search, pin, Move entry, Delete and Restore work on it. The engine writes the title (`messages.conflict.copyTitle`); the app never parses it |
| Rename, Delete journal and Restore journal are never blocked | The journal menus have no review item and nothing is dimmed for a conflict ([journals](../screens/journals.md)) |
| A record whose conflict still waits (a few seconds) | The record stays editable. Move entry, Version history restore and Delete permanently show `messages.lifecycle.combining` in the dialog's or page's error bar or the alert dialog as for any refusal; Delete all leaves the item in Recently deleted; Restore and Image descriptions are not offered ([move-entry](../screens/move-entry.md), [version-history](../screens/version-history.md), [recently-deleted](../screens/recently-deleted.md)) |
| A held version (saved by a newer version) | The notice above the open entry or template shows `messages.conflict.kept.noticeUpdate` with no button, and the Sync page has one line `messages.conflict.kept.updateNeeded`; a journal that is held is listed like one saved by a newer version ([unavailable-content](../screens/unavailable-content.md)). Where the person must update, the Microsoft Store's "Get updates" link (D51) applies |
| An edit against a permanent deletion is saved as a new entry or template | It is an ordinary item in Recently deleted, or in Unavailable journals when its journal is gone, where Restore (or Restore to “{name}”) brings it back ([recently-deleted](../screens/recently-deleted.md), [delete-and-restore](delete-and-restore.md)). If the item was open, the editor moves to the new entry without losing the text, draft or cursor |
| Open a Changed on two devices row (`open-kept-note`) | Click, tap, or Enter or Space on the focused card. The Settings page is left and the library window shows the collection that holds the item (its journal, Templates, Recently deleted, or Unavailable journals) with the item selected and open. Back returns to Settings ▸ Sync. Opening marks the note seen; nothing is saved or changed |
| The item no longer exists | The card has already been removed silently; if it goes between rendering and activation nothing happens and the card disappears |
| Rows with nothing to open (a journal rename, a journal deleted) | Plain text; there is no control |
| Clear list (`clear-kept-notes`) | Forgets every note at once, without a dialog; the group disappears. The notes are local to this PC and are not synced |
| What 1.0 left pending | Settled once when a library that carries such conflicts opens, silently, and listed in the group |

## Layout at each window width

As [settings-sync](../screens/settings-sync.md) and [kept-version-notice](../screens/kept-version-notice.md). The flow adds nothing of its own.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `show-other-version`, `dismiss-kept-notice` | The notice's action and close buttons ([kept-version-notice](../screens/kept-version-notice.md)) | none | Unlocked, not replacing the library |
| `open-kept-note` | A card of the Changed on two devices group | none | Unlocked; the item still exists; the card has something to open |
| `clear-kept-notes` | The group's text button | none | Unlocked |

## Copy differences

None beyond the casing proposals in [kept-version-notice](../screens/kept-version-notice.md); the group's header is "Changed on two devices" in sentence case. Sentence case applies as in platform.md, 12.

## Accessibility

- Settling is silent. The notice is read when focus reaches it; the group is where it is found.
- Every step works with the keyboard alone: the notice's buttons, the cards and Clear list are all focusable controls.

## Different by design

- **Opening a note leaves Settings** for the library, where Apple closes the Settings sheet on iPhone and iPad and brings the library window forward on the Mac.
- **No review page.** Windows never had one to port; the Apple 1.0 sheet is gone from the spec.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D51 (update link), D63 to D65 (the older copy, moved against edited, the short refusals).
