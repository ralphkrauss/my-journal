---
id: conflict-review
title: Review Changes (conflicts) (Apple)
spec: screens/conflict-review.md
features: [conflict-notice, changes-to-review-list, conflict-review-unsupported]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - apps/apple/JournalApp/Views/PermanentDeletionView.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - docs/design/entry-conflict-accessibility.md
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - docs/design/permanent-deletion.md
  - docs/design/unsupported-conflict-review.md
  - docs/design/1-1-conflicts-and-reconnect.md
screenshots:
  - screenshots/iphone/conflict-review-default.png
  - screenshots/iphone/conflict-review-notice.png
  - screenshots/ipad/conflict-review-default.png
  - screenshots/ipad/conflict-review-notice.png
  - screenshots/mac/conflict-review-notice.png
---

# Review Changes (conflicts) (Apple)

Implements [screens/conflict-review.md](../../../screens/conflict-review.md): where changes to review are signalled, the Changes to Review list in Settings, and the Review Changes sheet with its entry and template form and its unsupported form. Journals and permanent deletions have no sheet any more: the store settles them ([flows/resolve-conflict.md](../flows/resolve-conflict.md)) and the notes are in Settings ▸ Sync ([settings-sync.md](settings-sync.md)). The entry and template form is in [entry-conflict.md](entry-conflict.md); the steps and outcomes are in [flows/resolve-conflict.md](../flows/resolve-conflict.md). Sheet, alert and notice conventions are in [platform.md](../platform.md#9-sheets-popovers-and-notices).

The model is `AppModel.conflicts`, an array of `ConflictVersion` (record id, this device's `local` item, the received `remote` item, the remote revision, the recorded device id) read from the store's `conflicts` table by `JournalStore` and republished after every refresh. Every entry point below reads it; none caches a conflict across a lock.

## Controls

**Signals and entry points** (order of the spec's Entry points table)

- **Notice above the writing**: `ConflictNotice` (in `SettingsView.swift`), shown by `RootView.detailContent` when `model.conflicts` holds the open item. A `Text` (`.callout`, key `messages.conflict.entryNotice`) and a plain `Button` (`common.reviewChanges`) in an `HStack` with a `Spacer`, on a `.quaternary` background. At accessibility Dynamic Type sizes it becomes a `VStack` (`AnyLayout` switch on `dynamicTypeSize.isAccessibilitySize`). The button runs `model.flush()` (saves the open writing); only if that succeeds it calls `model.refresh()` and presents `ConflictReview` as a `.sheet`. If the save fails nothing opens and the save-failure alert/notice shows (see `flows/save-failure`). The notice has no `replacingVault` check of its own; the sheet closes itself when a library replacement starts.
- **Entries list row**: `RootView.entryConflictIndicator` puts `Image(systemName: "exclamationmark.circle")` with accessibility label `messages.conflict.needsReview` at the trailing end of the row's first line (date line). At accessibility sizes the date line is a `VStack` and the symbol sits beside the date. It is not a button; the row's own selection opens the entry.
- **Settings ▸ Sync ▸ Changes to Review**: `ConflictSettingsSection`, a `Section` at the end of the Sync pane's `Form` (`.formStyle(.grouped)`), shown only when `!model.locked` and `model.conflicts` is not empty. Header `messages.conflict.settingsSection`. Each row is a `VStack` of the title (wrapping `Text`), the date (`Text(_, format: .dateTime)`, secondary) and a `Button` `common.reviewChanges` whose accessibility label is `common.reviewChangesFor` with the title. The pane owns a `@State var reviewingConflict` and presents `ConflictReview` with `.sheet(item:)`; the sheet is dropped when the app locks.
- **Move Entry** (`MoveEntryView`) shows `common.reviewChanges` when a conflict on the entry blocks the move and presents `ConflictReview` nested.

Nothing else opens the sheet: the deleted journal's page, the recovery notice, Move Entry for a journal, Version History, the journal actions and the delete paths have no conflict button, no dimmed Rename… and no alert. A journal's conflict is settled by the store or held, and a held one reads like a journal saved by a newer version. Deleting an entry or template that still has changes to review ends in the general error alert like an item that changed meanwhile.

**The Review Changes sheet** is `ConflictReview` (`ConflictRouting.swift`), a `Group` that re-decides its form on every render from `model.conflicts` (the table in the spec). In order: locked shows plain text `messages.conflict.locked` (the child views close the sheet themselves when `model.locked` becomes true; this text only shows if the sheet renders while locked); the entry form `EntryConflictReview` when neither version carries preserved JSON from a newer version and both documents are `isEditable`; the unsupported form when either has preserved JSON or is not editable; and when the conflict is no longer in `model.conflicts`, a completed `DeletionSheet` with `messages.conflict.resolved`. `@State entryReviewStarted` keeps the entry form on screen while a committed entry choice removes its conflict from the model, so the sheet does not flip to the resolved text before it closes itself.

Both forms are wrapped in `DeletionSheet` (`PermanentDeletionView.swift`): title `common.reviewChanges`, a `ScrollView` of 24 pt padding, and a Cancel button (`role: .cancel`, `.keyboardShortcut(.cancelAction)`) that reads `common.done` once `completed`. `.interactiveDismissDisabled(busy)` stops swipe-down and the Cancel button is `.disabled(busy)`.

**Unsupported form** is inline in `ConflictReview`: `DeletionSheet` with `messages.conflict.updateToReview` and `ArchiveExportControls` (the Export Archive… button of Settings ▸ Backup, including the one-time password check sheet). Nothing else is offered.

Empty/loading/error states: those of the entry form ([entry-conflict.md](entry-conflict.md)); there is no empty state (the section and notice are simply not shown).

## Layout

- **iPhone (compact width)**: both forms are a full-height `.sheet` with a `NavigationStack`, inline title and the Cancel/Done button in `.cancellationAction` (leading). The notice sits between the navigation bar and the writing and is full width; the entry marker is in the list row. At accessibility sizes `DeletionSheet` repeats the title as a heading inside the scroll content (iOS only).
- **iPad (regular width)**: the same `.sheet` is the system's centered card (about 580 pt wide in the capture); there are no detents. The notice is full width above the editor in the detail column. Entry markers show in the middle (entries) column.
- **Mac**: the notice is the first element of the detail column (above the title, below any recovery notice). Sheets are not a `NavigationStack`: `DeletionSheet` is a `VStack` of a centered `.title2.bold()` title, the scroll content, a `Divider` and a footer row with Cancel/Done at the leading edge; frame `minWidth 360, idealWidth 480, minHeight 400, idealHeight 600` . Settings ▸ Sync is a tab of the Settings window (`TabView`, 560 pt wide), which presents the sheet itself.
- The switch is `#if os(iOS)` / `#else` inside `DeletionSheet`, and `dynamicTypeSize.isAccessibilitySize` for the notice stacking. Dynamic Type enlarges all text; only the notice and the sheet title change structure.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-changes` | Notice above the entry, Settings ▸ Sync ▸ Changes to Review and the Move Entry button; as in [commands.md](../commands.md) | None | Unlocked; the notice button is not disabled for anything else |
| `export-archive` | Export Archive… inside the unsupported form | None | Not while an export is preparing (`export.showsProgress`) |

Keyboard: in `DeletionSheet` Cancel/Done is the cancel action, so Escape closes it on the Mac and a hardware keyboard on iPad (not while busy). Confirmation dialogs take their default and Escape keys from the system. Tab order follows the view order; Full Keyboard Access reaches every button.

## Copy differences

None. Keys with a `mac` variant do not appear here. Some error texts in these views are written inline in Swift and match `copy/en.json` except those noted in Open questions.

## Accessibility

- The entry form's status uses focus instead of an announcement; see [entry-conflict.md](entry-conflict.md).
- The marker is a labelled image (`messages.conflict.needsReview`); the notice text and button are separate elements.
- Each Changes to Review row is a `VStack` of title, date and button; the button's label names the record (`common.reviewChangesFor`) so VoiceOver and Voice Control can tell the rows apart.
- The notice stacks its text above the button at accessibility sizes; the preview follows the body size through `@ScaledMetric`.

## Differences between iPhone, iPad and Mac

- The notice button is plain text on iPhone and iPad and a bordered button on the Mac (system rendering of `Button` in a Mac window); same control.
- Sheet chrome differs: `NavigationStack` with a Cancel button in the bar (iPhone, iPad) against a title, footer and divider built by hand (Mac), because a Mac sheet has no navigation bar; the Mac footer places Cancel at the leading edge and gives the sheet a minimum size.
- iPad shows a centered card sheet where iPhone is full height; both are the system presentation of `.sheet` for the size class.
- The Settings entry is a pushed pane of the Settings sheet on iPhone and iPad and a tab of the Settings window on the Mac; the section is the same.
- Escape closes both forms on the Mac; touch devices have no Escape.

## Screenshots

The sheet itself is shown in [entry-conflict.md](entry-conflict.md); these captures show the signals. The unsupported form of the sheet and the Changes to Review section are not captured (they need records in those states; the sample library only has two conflicting entries).

| Device | Image | State |
| --- | --- | --- |
| iPhone | ![entries list](../screenshots/iphone/conflict-review-default.png) | Entries list of Personal; Slow Sunday and Gratitude each carry the exclamation-mark-in-a-circle marker at the trailing end of the date line |
| iPhone | ![notice](../screenshots/iphone/conflict-review-notice.png) | The open entry Slow Sunday with the grey notice and the Review Changes button below the navigation bar |
| iPad | ![entries list and notice](../screenshots/ipad/conflict-review-default.png) | Three columns: the markers in the list and the notice above the editor |
| iPad | ![notice](../screenshots/ipad/conflict-review-notice.png) | Same state as above (identical capture); the notice text and Review Changes on one line |
| Mac | ![notice](../screenshots/mac/conflict-review-notice.png) | Window in the background: markers in the list and the notice above the title, with a bordered Review Changes button |

## Source files

View:

- `Views/ConflictRouting.swift`: `ConflictReview` (form routing), `ConflictSettingsSection`.
- `Views/EntryConflictReview.swift`: the entry and template form and `ConflictPlacement`.
- `Views/PermanentDeletionView.swift`: `DeletionSheet` (the sheet frame; it also frames the unsupported form).
- `Views/SettingsView.swift`: `ConflictNotice` and where the section is placed. `Views/RootView.swift`: the row marker and notice placement. `Views/MoveEntryView.swift`: the nested button.

Model:

- `Model/AppModel.swift`: `conflicts`.

Core:

- `JournalCore/Store.swift`: `ConflictVersion`, `ConflictChoice`, `conflicts()`, `resolve`. `JournalCore/ConflictResolution.swift` and `StoreConflictResolution.swift`: the automatic rule for journals and permanent deletions. `JournalCore/SyncReconciliation.swift`: where conflicts are recorded.

Design records: [entry-conflict-accessibility.md](../../../../docs/design/entry-conflict-accessibility.md), [stale-conflict-recovery.md](../../../../docs/design/stale-conflict-recovery.md), [journal-conflicts.md](../../../../docs/design/journal-conflicts.md), [permanent-deletion.md](../../../../docs/design/permanent-deletion.md), [unsupported-conflict-review.md](../../../../docs/design/unsupported-conflict-review.md).

## Open questions

See [open-questions.md](../../../open-questions.md), A49 (the notice does not check `replacingVault`).
