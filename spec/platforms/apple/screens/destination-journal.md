---
id: destination-journal
title: New Journal (from Move Entry and Version History) (Apple)
spec: screens/destination-journal.md
features: [move-entry, restore-version]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/RecoveryJournalView.swift
  - apps/apple/JournalApp/Views/MoveEntryView.swift
  - apps/apple/JournalApp/Views/VersionHistoryView.swift
  - apps/apple/JournalApp/Views/DeletionConflictView.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - docs/design/history-recovery.md
  - docs/design/move-entry.md
---

# New Journal, as a destination (Apple)

Implements [screens/destination-journal](../../../screens/destination-journal.md): a small sheet that creates a journal without leaving the sheet that needs one. It is not the New Journal alert of the Journals screen ([journals](journals.md)), which is a text-field alert, creates a journal that is then shown, and is available everywhere; this one is a view of its own, creates a journal that is not shown or chosen, and exists only inside three sheets.

## Controls

`RecoveryJournalView(entryID:)` (the name is historical: it was built for recovering into a new journal). It is presented with `.sheet(isPresented: $creatingJournal)` by `MoveEntryView` (with the open entry's id, see [move-entry](move-entry.md)), by `VersionHistoryView` (no entry id, see [version-history](version-history.md)) and by `DeletionConflictView` (permanent-deletion conflict review). Model: `AppModel.createRecoveryJournal(_:entryID:)` in `Model/JournalOperations.swift`.

A `ScrollView` over a `VStack(alignment: .leading, spacing: 16)` with 24 points of padding, so it scrolls at large text sizes:

1. Title: `Text("New Journal")` in `.title2.bold()` (`library.newJournal.title`). It has no explicit header trait.
2. `TextField("Name", text:)` (`common.name`), focused from `.onAppear` through a `@FocusState`, disabled while busy or after creating. Typing clears the error while not busy. Return calls `create()` through `.onSubmit`, only when the name is not blank after trimming and the view is neither busy nor finished.
3. Error text in secondary color when `error` is set. It is announced whenever it changes (`JournalAccessibility.announce`, not while locked).
4. Button row, an `HStack`: `Button(created ? "Done" : "Cancel", role: .cancel)` (`common.cancel` before creating, `common.done` after) at the leading end, disabled while busy; `Button("Create")` (`common.create`) at the trailing end, disabled while busy, after creating or with a blank name.

`create()` sets `busy`, clears the error and calls `model.createRecoveryJournal(name, entryID:)`: it refuses when a different entry is open than the caller's (`JournalError.locked` becomes the error text through `shown(.saving)`), saves the open entry first (`common.saveBeforeCreateJournal` when that fails), checks the name is not blank, saves a new `JournalItem(kind: "journal")` with the trimmed name, puts it at the end of the journal order (`placeJournalAtEnd`), and refreshes through `commitMutation` with an empty selection step, so the new journal is neither shown nor chosen in the parent sheet. On success the sheet dismisses; if only the refresh failed, `library.recoveryJournal.created` is the error text, `created` is true, so Create is disabled and the Cancel button reads Done.

Cancelling work: the sheet cancels its `operation` task when it disappears, and `.interactiveDismissDisabled(busy)` blocks a swipe-down while busy. When locking, it cancels, clears the name and error, drops focus and dismisses. When it was opened from Move Entry and the open entry changes (`model.draft?.id != entryID`), it cancels and dismisses.

## Layout

- **Mac.** `.frame(minWidth: 320, idealWidth: 420, minHeight: 200, idealHeight: 240)`, a sheet over the parent sheet.
- **iPhone and iPad.** A sheet over the parent sheet with the system's default size and no navigation bar; the content is the same `ScrollView`. The sheet has its own button row under the field rather than a navigation bar, unlike most iOS sheets, where Cancel and the confirming button are bar items.
- **Dynamic Type.** The content scrolls; the title and error wrap.

## Commands and shortcuts

No command of [commands.md](../commands.md) opens this sheet: it is a New Journal… button inside Move Entry, Version History and the deletion review. Keyboard: Return in the name field creates when allowed. No `.keyboardShortcut` is set on either button; Escape closes the sheet through the system's sheet handling where the platform provides it (not verified), and not while busy.

## Copy differences

None.

## Accessibility

- The field's accessible name is its placeholder, `common.name`; the title is plain bold text.
- Errors are announced; focus starts in the field.
- While busy the controls are disabled; the sheet cannot be dismissed by gesture.
- Reduce Motion and other display settings: nothing page-specific.

## Differences between iPhone, iPad and Mac

- The Mac sheet has explicit minimum and ideal sizes; on iOS the system sizes the sheet.
- Otherwise none: one view with its own button row on every device, because it is used inside sheets that already have bars or button rows of their own.

## Screenshots

None. The sheet appears only on top of Move Entry, Version History and the deletion review ([move-entry](move-entry.md), [version-history](version-history.md)), and no capture of it exists. The page was checked against the source only, which is why its status is draft.

## Source files

View:
- `apps/apple/JournalApp/Views/RecoveryJournalView.swift`: the sheet.
- `apps/apple/JournalApp/Views/MoveEntryView.swift`, `VersionHistoryView.swift`, `DeletionConflictView.swift`: where it is presented.

Model:
- `apps/apple/JournalApp/Model/JournalOperations.swift`: `createRecoveryJournal`.

Core: `JournalNames` and `JournalStore` in `apps/apple/Packages/JournalCore`.

Design records: `docs/design/history-recovery.md`, `docs/design/move-entry.md`.

## Open questions

None.
