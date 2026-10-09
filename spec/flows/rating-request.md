---
id: rating-request
title: Asking for a rating
features: [rating-request]
sources:
  - apps/apple/JournalApp/Model/ReviewRequest.swift
  - apps/apple/JournalApp/Model/ReviewRequestTiming.swift
  - apps/apple/JournalApp/Views/ReviewRequestPresenter.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/EraseOperations.swift
  - docs/design/about-and-ratings-2026-10-05.md
  - docs/design/1-1-settings-messages-editor.md
---

# Asking for a rating

## Purpose

Occasionally asks, through the platform's own rating prompt, for a rating from someone who clearly uses the app, at a natural pause, never in the way of writing or a problem. The app shows no prompt of its own; Rate My Journal in About and the Help menu is always available (`screens/settings-about`).

## When it may ask (all must hold)

> It asks for a rating once the person has saved writing on at least **five different days**, no sooner than **120 days** after the last time it asked, at the quiet pause after they leave an entry they wrote in, and not right after something went wrong.

1. **Installed from the store:** release builds from the store only; test and development builds never ask.
2. **Writing on five days:** the person's own edits to an entry were saved on at least 5 different local calendar days (each day counts once).
3. **Not recently:** at least 120 days since the last time it asked.
4. **No problem this session:** nothing showed an error alert, a failed save or a change from another device that waits for a newer version since the app launched (or since Erase Journals and Settings) (see below).

There is no minimum age of the installation and no limit per app version: five writing days take at least five days, and 120 days between requests gives at most three a year, which is the platform's own limit.

## The moment

1. The person edits an entry, then leaves it: chooses another entry, or goes back to the list.
2. Two seconds later, if nothing happened meanwhile, and:
   - the app is active and unlocked, and the system's own authentication isn't in front;
   - nothing is running: no connecting, importing, encrypting, erasing, deleting all, creating an entry, or opening journals;
   - no failed save, no error, no change from another device waiting for a newer version;
   - Sync Status isn't showing: no sync state needs the person, and sync has not been failing for a day while changes wait ([screens/sync-status](../screens/sync-status.md));
   - no sheet or panel is open (Settings, template chooser, export or import, New Journal), and nothing covers the window (alert, popover, menu);
   - no text field has focus;
   - the selected entry isn't a new, empty one (it's about to be written in);
   the rules above are checked, and if they hold, the platform's rating prompt is requested over this window.
3. Asking records the date, whether or not the system shows anything.

## What interrupts or cancels

- Any edit, selection change, sheet, lock, or the app becoming inactive cancels a pending request.
- Locking ends the session's “edited entry”; unlocking is never the moment.

## What counts as a problem

Three things mark the session, and no request is made until the app launches again (locking and unlocking don't clear it):
- an error alert;
- a failed save;
- a change from another device that waits for a newer version of My Journal (a held conflict). Everything the app settles itself, entries and templates kept as two versions included, and the notes of Changed on Two Devices, never count.

A sync problem is not remembered: while Sync Status shows one, the moment above is not clear, and once it is gone the next pause can ask. A person who fixed a sync problem a few minutes ago may be asked; one who has had an error, a failed save or a held change this session cannot.

## Storage

- Kept only on this device, in the app's own preferences: the number of writing days and the last one, and the date of the last request. The record is created at the first saved edit. No journal content; never synced or sent.
- A record written by version 1.0 also holds the first use and the version of the last request; they are ignored, and its count and last request still apply.
- Erase Journals and Settings removes it, as at a first launch.

## Rules

- Never more than the platform allows; the platform may show nothing.
- Never during writing, a problem or an operation.

## Accessibility

- The platform's prompt is accessible; the app adds nothing.

## Platform notes (Apple)

- Uses the system's review request (StoreKit), only for App Store (production) installs, verified by the app transaction.
- Windows and Android use their store's in-app review API with the same rules.

## Open questions

- None.
