---
id: destination-journal
title: New Journal (from Move Entry and Version History)
features: [move-entry, restore-version]
sources:
  - apps/apple/JournalApp/Views/RecoveryJournalView.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift (createRecoveryJournal)
  - docs/design/history-recovery.md
  - docs/design/move-entry.md
---

# New Journal (destination)

## Purpose

Create a journal to move an entry into, or to restore a version into, without leaving the sheet that needs it.

## Entry points

- Move Entry: New Journal… (`screens/move-entry.md`).
- Version History: New Journal… (`screens/version-history.md`).

## Content

A small sheet over the sheet that opened it (computer: 320–420 pt wide, 200–240 pt tall), scrolling:

1. Title `library.newJournal.title`.
2. Text field `common.name`, focused when the sheet appears.
3. Error text (secondary) when there is one.
4. Button row: `common.cancel` (before creating) or `common.done` (after creating, if the sheet stays) at the leading end; `common.create` at the trailing end.

## Actions

| Action | Enabled | Result |
| --- | --- | --- |
| Create, or Return in the name field | Name not blank after trimming; not busy; not created yet | Saves the open entry first, then creates a journal with the trimmed name at the end of the journal order. On success the sheet closes. The new journal is **not** selected as the destination; the person chooses it. |
| Cancel / Done | Not busy | Closes. |

## States

- Busy: fields and buttons disabled; can't swipe to dismiss.
- Open entry couldn't be saved: `messages.save.before.goBack`.
- Created but not shown: `library.recoveryJournal.created`; the button becomes Done.
- Locked, or (from Move Entry) another entry opened: the sheet closes and the work is cancelled.
- Errors are announced to VoiceOver.

## Rules

- Editing the name clears the error.

## Accessibility

- The field is labelled by its placeholder; errors are announced.

## Platform notes (Apple)

- Same sheet everywhere, with its own button row (no navigation bar).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
