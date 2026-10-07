---
id: rating-request
title: Asking for a rating
features: [rating-request]
sources:
  - apps/apple/JournalApp/Model/ReviewRequest.swift
  - apps/apple/JournalApp/Model/ReviewRequestTiming.swift
  - apps/apple/JournalApp/Views/ReviewRequestPresenter.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/EraseOperations.swift
  - docs/design/about-and-ratings-2026-10-05.md
---

# Asking for a rating

## Purpose

Occasionally asks, through the platform's own rating prompt, for a rating from someone who clearly uses the app, at a natural pause, never in the way of writing or a problem. The app shows no prompt of its own; Rate My Journal in About and the Help menu is always available (`screens/settings-about`).

## When it may ask (all must hold)

1. **Installed from the store:** release builds from the store only; test and development builds never ask.
2. **A week of use:** this device's first use was at least 7 days ago.
3. **Writing on four days:** the person's own edits to an entry were saved on at least 4 different local calendar days (each day counts once).
4. **Not this version:** the system hasn't been asked during this app version (marketing version).
5. **Not recently:** at least 120 days since the last time it asked.
6. **No problem this session:** nothing needed the person's attention since the app launched (or since Erase Journals and Settings) (see below).

## The moment

1. The person edits an entry, then leaves it: chooses another entry, or goes back to the list.
2. Two seconds later, if nothing happened meanwhile, and:
   - the app is active and unlocked, and the system's own authentication isn't in front;
   - nothing is running: no connecting, importing, encrypting, erasing, deleting all, creating an entry, or opening journals;
   - no failed save, no error, no changes to review;
   - no sheet or panel is open (Settings, Journals, template chooser, export or import, New Journal), and nothing covers the window (alert, popover, menu);
   - no text field has focus;
   - the selected entry isn't a new, empty one (it's about to be written in);
   the rules above are checked, and if they hold, the platform's rating prompt is requested over this window.
3. Asking records this version and the date, whether or not the system shows anything.

## What interrupts or cancels

- Any edit, selection change, sheet, lock, or the app becoming inactive cancels a pending request.
- Locking ends the session's “edited entry”; unlocking is never the moment.

## What counts as a problem

Any of these marks the session, and no request is made until the app launches again (locking and unlocking don't clear it):
- an error alert;
- a failed save;
- changes to review (conflicts);
- a sync state that needs the person (anything but offline/unreachable/unavailable);
- sync failing for more than a day while changes wait.

## Storage

- Kept only on this device, in the app's own preferences: first use, number of writing days and the last one, and the version and date of the last request. No journal content; never synced or sent.
- Erase Journals and Settings removes it, as at a first launch.

## Rules

- Never more than the platform allows; the platform may show nothing.
- Never during writing, a problem, or an operation.

## Accessibility

- The platform's prompt is accessible; the app adds nothing.

## Platform notes (Apple)

- Uses the system's review request (StoreKit), only for App Store (production) installs, verified by the app transaction.
- Windows and Android use their store's in-app review API with the same rules.

## Open questions

- None.
