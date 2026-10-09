---
id: move-entry
title: Move Entry
features: [move-entry]
sources:
  - apps/apple/JournalApp/Views/MoveEntryView.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift (moveEntry, commitEntryMove)
  - apps/apple/JournalTests/MoveLifecycleTests.swift
  - docs/design/move-entry.md
  - docs/design/pre-release-fixes-2026-09-27.md (item g)
---

# Move Entry

## Purpose

Move one entry to another journal. (Restoring an entry from Recently Deleted is a separate verb that picks the journal itself: [screens/recently-deleted](recently-deleted.md).)

## Entry points

- Entry Actions ▸ Move Entry… (`move-entry`), for an editable entry in a journal in use. An entry in Recently Deleted can't be moved: restore it first.

## Content

Sheet. Title `library.moveEntry.title`. Phone and tablet: navigation bar with `common.cancel` and the action button; computer: title at the top, content, divider, `common.cancel` (leading, Escape) and the action button (trailing, Return); 320–420 pt wide, 280–360 pt tall.

The action button is `library.moveEntry.move`; disabled until a choosable journal is selected, and while moving.

Content:

1. **No other journals**: a centred group with `library.moveEntry.noOtherJournals` (headline), `library.moveEntry.noOtherJournals.message` (secondary) and `common.newJournalEllipsis`.
2. Otherwise a **list of journals** in use, except the entry's current journal, in the journals' order. Each row shows the journal's name and a checkmark when selected. A journal whose name is the same as another listed journal's (ignoring case) is dimmed, can't be chosen, and shows `library.moveEntry.sameName` below its name; below the list then: `library.moveEntry.renameExplanation` (variant: computer “in the sidebar”, phone and tablet “in the Journals list”).
3. `common.newJournalEllipsis` below the list (when there are journals).
4. Error text in red (identifier “Move error”), when there is one.
5. While moving: progress indicator with `library.moveEntry.moving`.

## Actions

| Action | Enabled | Result |
| --- | --- | --- |
| Choose a journal | Choosable, not moving | Selects it and clears the error. |
| Move | A choosable journal is selected; not moving | Saves the open entry first, then moves it. The sheet closes; the entry stays open, now shown in the destination journal's list. |
| New Journal… | Not moving | `screens/destination-journal.md`. |
| Cancel, Escape | Not moving | Closes; nothing changes. |

## States

| State | Copy |
| --- | --- |
| No other journals | `library.moveEntry.noOtherJournals`, `library.moveEntry.noOtherJournals.message` |
| Moving | `library.moveEntry.moving` (can't swipe to dismiss) |
| The selected journal disappears or becomes ambiguous | `common.journalGone` (selection cleared) |
| A change from another device on the entry, its journal or the destination journal still waits to be combined | `messages.lifecycle.combining`; choose Move again after the next sync |
| The entry's journal or the destination is saved by a newer version | `messages.lifecycle.unsupportedJournal` |
| Open entry couldn't be saved | `messages.save.before.goBack` in the sheet |
| Moved but not shown | the app's error alert with `common.entryMovedNotDisplayed` |
| Other errors | the error's own text |
| Locked, or another entry opened | the sheet closes; the move is cancelled if not committed |

Errors are announced to VoiceOver.

## Rules

- Only this entry moves; nothing else in either journal changes. The entry keeps its date, text and images.
- The final edit is saved before the move, so the moved entry has it (`MoveLifecycleTests.testMovingFlushesFinalEditAndRetainsSelectionWithoutChangingAnotherEntry`).
- Edit ▸ Undo doesn't undo a move.
- A lock after the move is committed can't save the old journal membership back (`MoveLifecycleTests.testLockAfterMoveCommitCannotSaveOldJournalMembership`).

## Accessibility

- The selected row has the Selected trait; its checkmark is hidden from VoiceOver.
- Dimmed rows read as dimmed; the explanation is read after the list.
- Errors are announced.

## Platform notes (Apple)

- The same-name explanation names where journals are renamed on each platform (sidebar on the computer, Journals list on the phone and tablet).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
