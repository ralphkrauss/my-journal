---
id: change-date
title: Change Date (sheet)
features: [change-entry-date]
sources:
  - apps/apple/JournalApp/Views/EntryDateView.swift
  - apps/apple/JournalApp/Model/EntryActionOperations.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/EntryDate.swift
---

# Change Date

## Purpose

Changes an entry's date, which decides where it's listed. Dates are shown in the list and changed here, never as a persistent control in the editor (AGENTS.md).

## Entry points

- `library.entryActions.changeDate` in an entry's context menu or Entry Actions.

## Content

Title `library.changeDate.title`; a date picker labelled `library.changeDate.date`, starting on the entry's date (date only, no time). Error text in red under it (announced). Buttons `common.cancel` and `common.save`.

## Actions

- **Save:** stores the new date. The entry moves to its new place in the list (another month, or within Pinned). The sheet closes. No message.
- **Cancel** (Escape on the Mac): closes without changing anything.

Save is disabled while saving and while the entry has a failed save.

## States

- **Busy:** controls disabled; not dismissable.
- **Errors:** `messages.entry.dateChanged`, `messages.save.before.goBack`, `messages.entry.unavailableForEditing`.
- **Stored but not shown:** error alert `messages.refresh.dateSaved`.
- **Another entry opened, or locked:** the sheet closes.

## Accessibility

- At accessibility sizes the label sits above the picker and the buttons stack (Save first) on the Mac.

## Platform notes (Apple)

- **iPhone and iPad:** a form sheet, Cancel top left, Save top right.
- **Mac:** a small sheet with Cancel (Escape) and Save (Return) at the bottom.

## Open questions

- None.
