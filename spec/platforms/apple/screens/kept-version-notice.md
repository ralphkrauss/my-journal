---
id: kept-version-notice
title: Other version notice (Apple)
spec: screens/kept-version-notice.md
features: [kept-both-notice]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/KeptVersionNotice.swift
  - apps/apple/JournalApp/Model/ConflictNotes.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/KeptNotes.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreConflictCopies.swift
  - apps/apple/JournalUITests/KeptBothUITests.swift
  - docs/design/1-1-conflicts-and-reconnect.md
---

# Other version notice (Apple)

Implements [screens/kept-version-notice.md](../../../screens/kept-version-notice.md): the notice above the open entry or template on the device that kept both versions, with Show Other Version and Dismiss, and the one line for a version that only a newer My Journal can read. It replaced `ConflictNotice`, the exclamation-mark symbol on list rows and the Review Changes sheet (`ConflictReview`, `EntryConflictReview`, `ConflictRouting.swift`), which are deleted. How the versions are kept is [flows/resolve-conflict.md](../flows/resolve-conflict.md); the list of kept versions is [settings-sync.md](settings-sync.md). Notice conventions: [platform.md](../platform.md#9-sheets-popovers-and-notices).

The model is `AppModel.entryNotice(for:)` (`Model/ConflictNotes.swift`): `.updateNeeded` when the item's id is in `heldConflictIDs`, else `.keptBoth(KeptNote)` for the first unseen note of kind `keptBoth` whose `recordID` is the item and whose copy (`otherID`) still exists in `items`, else none. It is nil while locked and for a journal. `AppModel.conflicts` no longer exists: the app holds only `conflictedIDs` (every record with a conflict, for the lifecycle) and `heldConflictIDs` (those a newer version must read).

## Controls

- **The notice**: `KeptVersionNotice` (`Views/KeptVersionNotice.swift`), a `VStack` of a `Text` (`.callout`, wrapping) and, for a kept copy, the two buttons, on `.quaternary` with 16 pt padding and `frame(maxWidth: .infinity)`; accessibility identifier “kept-notice”. The text is chosen by item kind (entry or template) and `note.otherIsNewer` (set when the note was written: the other version's modified time is later than this record's): `messages.conflict.kept.notice.entry`, `.entryNewer`, `.template`, `.templateNewer`; a held version shows `messages.conflict.kept.noticeUpdate` and no buttons.
- **Show Other Version** (`messages.conflict.kept.showOther`): a plain `Button` calling `AppModel.openKeptNote(_:revealing:)`, which opens the copy through `showItem` (selects its journal, clears the search, opens Recently Deleted or Templates when the copy is there; on iPhone `revealing` pushes it on the stack) and then marks the note seen. **Dismiss** (`common.dismiss`): `AppModel.dismissKeptNote(_:)`, which marks it seen (`markKeptNoteSeen`). Both refresh the model, so the notice goes.
- **When it shows.** `KeptVersionNotice` observes `EditorActions.editing` and `editingTable` (the title or the text has the keyboard): while either is true a notice that has not appeared yet waits; the ids of notices already shown are kept in `@State shown`, so one that appeared stays when writing starts again. It is re-evaluated when the view appears (the next time the entry is shown) and when writing ends. `.id(item.id)` gives each entry its own state. No announcement is posted.
- **Placement.** `RootView.detailContent` puts it above the writing: on iPhone and iPad it is the first element of the detail column's `VStack`, above the scrolling editor, so it stays in view however far the entry is scrolled; on the Mac it follows the recovery notice and precedes the title field. The save-failure notice stays in the editor's own scrolling header.

Nothing else signals a kept copy: list rows have no symbol, Move Entry and Version History have no nested button (they show `messages.lifecycle.combining` while a conflict waits, or `messages.lifecycle.unsupportedJournal` when held), and Settings ▸ Sync has no Changes to Review section.

## Layout

- **iPhone**: full width under the navigation bar, above the writing; 16 pt padding. At accessibility Dynamic Type sizes (`dynamicTypeSize.isAccessibilitySize`) the buttons stack vertically (`VStackLayout`, 12 pt) below the text; otherwise they sit in a row (`HStackLayout`, 16 pt). The text is always above the buttons.
- **iPad**: the same band across the detail column.
- **Mac**: the first element of the detail column below any recovery notice, above the title; the buttons are rendered as the system draws a `Button` in a Mac window.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `show-other-version` | The notice's first button | None | Unlocked, not replacing the library, the copy exists |
| `dismiss-kept-notice` | The notice's second button | None | Unlocked, not replacing the library |

Keyboard: Tab reaches both buttons in order on a hardware keyboard and with Full Keyboard Access; Return and Escape are not bound. The held line has no control.

## Copy differences

None. All keys are the same on iPhone, iPad and Mac; no `mac` variants. The texts are literals in `KeptVersionNotice.swift`, identical to the catalog.

## Accessibility

- No announcement: `JournalAccessibility.announce` is not called, so the notice never talks over VoiceOver's typing echo. VoiceOver reads it when focus reaches it: the text, then the two buttons as buttons. Voice Control: "Show Other Version", "Dismiss".
- The text wraps at every size (`fixedSize(horizontal: false, vertical: true)`); nothing is told by colour alone.
- Increase Contrast, Reduce Transparency and Reduce Motion: the fill is the system's quaternary fill with system text and nothing animates.

## Differences between iPhone, iPad and Mac

- The notice is the same view on all three; the Mac draws its buttons with the system's bordered style, iPhone and iPad as plain text buttons.
- On iPhone Show Other Version pushes the copy on the navigation stack; on iPad and Mac it selects the copy in the list columns or the library window.

## Screenshots

None yet: the capture script has not been run for the kept-both notice (captured by `SpecConflictCaptureTests` as entry-editor-kept-both-notice and entry-editor-held-notice, listed by [entry-editor.md](entry-editor.md) once they exist). The 1.0 captures of the Review Changes notice and list marker were removed with their screen.

## Source files

View: `Views/KeptVersionNotice.swift`; placement in `Views/RootView.swift` (`detailContent`).

Model: `Model/ConflictNotes.swift` (`entryNotice(for:)`, `dismissKeptNote`, `openKeptNote`, `adoptConflicts`), `Model/AppModel.swift` (`conflictedIDs`, `heldConflictIDs`, `keptNotes`).

Core: `JournalCore/KeptNotes.swift` (`KeptNote`, `KeptNotesState`, `markKeptNoteSeen`), `JournalCore/StoreConflictCopies.swift` (where a copy and its note are made or replaced), `JournalCore/ConflictResolution.swift`, `JournalCore/StoreConflictResolution.swift`.

Tests: `JournalUITests/KeptBothUITests.swift`, `JournalTests/ConflictNotesTests.swift`. Design record: [1-1-conflicts-and-reconnect.md](../../../../docs/design/1-1-conflicts-and-reconnect.md), section 4.2.

## Open questions

See [open-questions.md](../../../open-questions.md), A49 (resolved: the review sheet that did not check `replacingVault` is gone).
