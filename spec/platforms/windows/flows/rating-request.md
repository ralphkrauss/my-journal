---
id: rating-request
title: Asking for a rating (Windows)
spec: flows/rating-request.md
features: [rating-request]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/uwp/monetize/request-ratings-and-reviews
  - https://learn.microsoft.com/en-us/uwp/api/windows.services.store.storecontext.requestrateandreviewappasync
  - https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-store-app
---

# Asking for a rating (Windows)

Occasionally asks, through the platform's own rating prompt, for a rating from someone who clearly uses the app, at a natural pause, never in the way of writing or a problem. The conditions, the moment, what cancels it, what counts as a problem and what is stored are the spec's [rating-request](../../../flows/rating-request.md); the same rules apply on Windows, which the spec says. This file maps each signal to its Windows source and the request to the Microsoft Store's API ([28](../platform.md#28-rating)). The app shows no prompt of its own.

## Controls

There is no control of the app's own. The only visible surface is the Microsoft Store's rating and review dialog, shown by the system over the window. The always-available route is Rate My Journal ([settings-about](../../../screens/settings-about.md)), which opens the Store's review page.

| Spec element | Windows realisation | Notes |
| --- | --- | --- |
| 1. Installed from the store | `Package.Current.SignatureKind` is Store. A development, sideloaded or unpackaged build never asks | The same check hides Rate My Journal in other builds ([28](../platform.md#28-rating)) |
| 2–3. Writing on five days, not recently | Device-only values in the app's local settings: the number of local calendar days with a saved edit of the person's own writing and the last of them, and the date of the last request | Not in the library, never synced or sent, no journal content. Erase removes them |
| 4. No problem this session | The session is marked, until the app starts again, by: an alert dialog shown; a save failure notice; a change from another device that waits for a newer version (everything the device settles itself, and the notes of Changed on two devices, never count) | Locking and unlocking do not clear it. [messages](../messages.md) names the surfaces. A sync state that needs the person, or sync failing for more than a day with changes waiting, blocks the moment while the Sync page shows it, but is not remembered |
| The moment: the person edits an entry, then leaves it | The editor reports a leave after an edit (another entry chosen, or back to the list in the stacked layout); the request is scheduled 2 seconds later | Locking ends the session's "edited entry"; unlocking is never the moment |
| Active and unlocked, no system authentication in front | The library window's `Window.Activated` state is not Deactivated; App Lock is not locked; no Windows Security prompt is showing | |
| Nothing running | No connecting, importing, encrypting, erasing, deleting all, creating an entry or opening journals | The dialog queue is idle |
| No failed save, no error, no change waiting for a newer version, no sync problem showing | As item 4, and the Sync status is not showing an attention state | |
| No sheet or panel open | The window shows the library page (not Settings, a history page); the dialog queue is empty; no flyout, menu or other popup is open (`VisualTreeHelper.GetOpenPopupsForXamlRoot` has none); the template chooser and search suggestions are closed | |
| No text field has focus; the entry is not a new empty one | The focused element is not a text input; the selected entry has content | |
| Request | `StoreContext.GetDefault()`, initialised with the window handle (`WinRT.Interop.InitializeWithWindow`), then `await RequestRateAndReviewAppAsync()` on the UI thread | The Store shows its own dialog; the app shows nothing before or after it |
| Asking records the date | Written when the call returns `Succeeded` or `CanceledByUser` (the Store showed its dialog, or the person closed it). After `NetworkError` or `OtherError` nothing is recorded, so a later natural pause (a later session) tries again; each session makes at most one attempt. No message and no sound either way | The spec's "always record it" is changed on Windows because a failed call asked nobody (D53, the review's recommendation) |
| Cancels a pending request | Any edit, selection change, dialog, lock, or the window being deactivated or minimised | The timer is dropped; it is not paused |

Rules kept: never during writing, a problem or an operation; never more than the platform allows. Windows adds one rule from the Store's policy: every review goes to the Store's own mechanism, so the app never asks how the person likes it first and never routes unhappy feedback away. The Store does not throttle the request, so the app's own limits (five writing days, 120 days apart) are the only ones.

### The Store dialog

When the Store's dialog takes the foreground, the library window is deactivated. That needs no special handling: the Windows app has no privacy cover to coordinate with ([20](../platform.md#20-screen-capture-and-window-privacy), D28), so the request is made with App Lock on or off. App Lock's inactivity timer is not reset by input to the Store's dialog, which is short.

## Layout at each window width

Not applicable: the Store's dialog is the system's and has no app layout. The request does not depend on the window's width.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `help-rate` | Help ▸ Rate My Journal (after a separator) | none | Store builds only: opens the Store review page (`ms-windows-store://review/?ProductId=` and the product id) |
| `about-rate` | Settings ▸ About | none | As `help-rate` |

## Copy differences

None. The app has no text of its own for the prompt, and Rate My Journal is "Rate My Journal" in the Help menu and Settings ▸ About, a product name, so the sentence-case rule leaves it ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)).

## Accessibility

- The Store's dialog is the system's and accessible; the app adds nothing. Nothing is announced when the request is made or when it is skipped.
- Focus returns to where it was when the dialog closes, because the request only starts when no text field has focus and the list or pane has it.

## Different by design

- **The Store's API replaces StoreKit**, and it is not throttled by the system, so the app's rules are the only limit.
- **Store installs are recognised by the package's signature**, not an app transaction; development and sideloaded copies never ask.
- **A failed call is retried later**: only `Succeeded` and `CanceledByUser` count as asked; `NetworkError` and `OtherError` do not (D53).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D53 (what counts as asked).
