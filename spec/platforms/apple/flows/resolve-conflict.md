---
id: resolve-conflict
title: Changes made on two devices (Apple)
spec: flows/resolve-conflict.md
features: [conflict-kept-both, changed-on-two-devices-list, conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-unsupported]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/KeptNotes.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncReconciliation.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreDeletion.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreMerge.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - docs/design/entry-conflict-accessibility.md
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - docs/design/permanent-deletion.md
  - docs/design/1-1-conflicts-and-reconnect.md
screenshots:
  - screenshots/iphone/resolve-conflict-default.png
  - screenshots/iphone/resolve-conflict-keep-one.png
  - screenshots/ipad/resolve-conflict-default.png
  - screenshots/ipad/resolve-conflict-keep-one.png
---

# Changes made on two devices (Apple)

Implements [flows/resolve-conflict.md](../../../flows/resolve-conflict.md) on iPhone, iPad and the Mac. The screens it moves through are [screens/conflict-review.md](../screens/conflict-review.md) (signals, routing and the unsupported form) and [screens/entry-conflict.md](../screens/entry-conflict.md) (entry and template form); read them for controls and layout. This page records how the flow is wired: where conflicts come from in the code, which part of JournalCore settles which, which function commits each entry choice, and what the app does to its own state afterwards. Sheet and alert conventions: [platform.md](../platform.md#9-sheets-popovers-and-notices). Sync behaviour: [platform.md](../platform.md#30-sync-lifecycle-and-background).

## Controls

Flow step by step, with the control and the code behind it. The model type throughout is `AppModel` (`@MainActor`) over the `JournalStore` actor in JournalCore.

**How a conflict comes to exist** (core, not UI)

- A remote change arrives for a record that is dirty here, or that already has a pending review, or that is a permanent-deletion marker being replaced by live content: `JournalStore.recordConflict` writes one row to the `conflicts` table (remote payload, server revision, device id, modification time). One row per record: a newer remote version replaces the row and the replaced one goes to history (`preserveSupersededConflict`). `SyncReconciliation` also records one when a library joins a server by identity and the contents differ; a record that merely lacks the server's version is re-uploaded instead.
- This device saves over a version that changed after the saved copy was read: `keepChangedVersion` stores the stored version as the other side, with the all-zero device id standing for an unknown device, so the review never overwrites it. Typing over a change that arrived but was not shown is covered by `StaleDraftTests`.
- Merging journals (`StoreMerge.swift`) inserts a `conflicts` row when the same record exists in two different versions, and an archive imported as new journals carries the archive's unresolved conflicts over with new ids (`Store.importHistory`).
- The library record (pins and journal order) never becomes a review; it is reconciled field by field.
- `AppModel.conflicts` is filled from each refresh's snapshot with the rows the person must review: entries, templates and those with content from a newer version. Setting it invalidates the derived lists and calls `reviewRequests.noteProblem()`, so no rating request appears while any exist. Journals and permanent deletions are not in it; held ones are only `JournalStore.heldConflictIDs()`, which drives the footer line `messages.conflict.kept.updateNeeded` in Settings ▸ Sync and the newer-version behaviour of the journal.

**Settled by the store: journals and permanent deletions** (core, no UI)

- `JournalStore.resolveConflicts(at:)` (`StoreConflictResolution.swift`) runs for a `ConflictResolutionPoint`: the end of a completed pull, the opening of a library, and after a local merge or import (or a stale save when no server is configured). It settles each row in its own write transaction with `ConflictResolution.resolve(local:other:ids:)`, a pure function over decoded items (`ConflictResolution.swift`, outcomes `held`, `review`, `sameContent`, `parked`, `twoMarkers`, `journal`, `journalMarker`). `review` is the outcome for entries and templates that differ: the row stays. It does nothing while a reconciliation is in progress, for a record that is being written (a save in the last moments), or for a version the app can't read (`held`).
- Opening a library first runs `completeOpeningPass()`: it settles the journal and permanent-deletion rows an earlier version left, once per library (the sealed key records that it has), before any sync can replace a row's other version.
- A permanent deletion against an edit parks the edit as a new entry or template with an identity derived from the edited text (`ConflictCopyIdentity`, the label “conflict-park”; the derivation key is HKDF from the vault key, a public constant in a library without encryption). A record that already has that identity, in any state, is left alone.
- Each outcome that the person should know about adds a `KeptNote` to the sealed settings key “kept-notes” (`KeptNotes.swift`, `KeptNotesState`: up to 20 notes, 30 days, rename notes last to go; up to 200 remembered automatic copies; AAD `journal:v1:local:kept-notes`). The key is local: never synced, re-sealed with “library-changes” when protection changes, ignored if it can't be opened. No table or schema object was added.

**1. Open the review.** The notice, row, Settings and other buttons are listed in [conflict-review.md](../screens/conflict-review.md). The notice's button calls `model.flush()` and `model.refresh()` first; if the flush fails nothing opens. `ConflictReview` then picks the form on each render. Every sheet is a SwiftUI `.sheet`; the one nested from Move Entry stacks another sheet on top of the host sheet.

**2a. Entry or template** (`EntryConflictReview`)

- Keep Both: `AppModel.finishPendingSave()`, then `JournalStore.resolve(conflict, choice: .keepBoth)`. In one write transaction: both originals go to history, the pending outbox row and the conflict row are removed, the record keeps this device's version (with a new modification time) at the remote revision, and the other version is inserted as a new record with a fresh id and queued for upload with revision 0.
- Keep One Version: the same call with `.local` or `.remote`; the chosen version is stamped with the current time, the other stays only in history. For `.remote` the confirmation message first says what moves, re-dates or archives the entry (built by `ConflictPlacement.outcome`).
- The store re-reads the row inside the transaction and throws `JournalError.conflict` if the remote revision or either payload differs from the snapshot the view holds, if either side is permanently deleted (`PermanentDeletionError.permanentlyDeleted`) or not editable (`JournalError.unsupportedFormat`). The view maps `JournalError.conflict` to a refresh, never to a retry.
- Outcome: `committed = true`, then `model.refresh`, select the resolved entry if nothing else is open, dismiss.

**2b. Unsupported.** `ArchiveExportControls`; the export runs `ArchiveExport` and a `.fileExporter`, after the one-time password check if `model.passwordCheckPending`. See `screens/settings-backup`.

**3. When something changes meanwhile.** Entry form: `refreshReview` (generation counter, scroll and VoiceOver focus). Locking cancels the running `Task`, clears confirmations, previews and images, and dismisses.

**After the flow.** While a record has changes to review it can still be opened and edited: autosave writes the local version, and the sync outbox skips any record that has a `conflicts` row (the `LEFT JOIN conflicts` in `Store.pending`), so nothing is sent until the review is resolved or the store settles it. A journal is never dimmed for a conflict: `AppModel.editJournal` and `AppModel.journalActions` no longer check one, and a journal whose row is held is located as unsupported by `JournalLifecycleSnapshot`, which lists its entries under Unavailable Journals with `common.updateToRestoreEntry`.

## Layout

The flow has no layout of its own; each step's layout is on the screen pages. What the flow adds:

- **iPhone and iPad**: every step is a sheet over the library; the person never leaves the entry list. After a commit the model selects the kept result behind the sheet (`AppModel.selectedID`, `draft`).
- **Mac**: the sheet is attached to the library window or, for Settings ▸ Sync ▸ Changes to Review, to the Settings window. A Changed on Two Devices row brings the library window forward and selects the item. Nothing is selected in the library window until the sheet closes.
- Dynamic Type changes the notice and the entry form's version control (menu at accessibility sizes); no step changes order.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-changes` | Starts the flow; as in [commands.md](../commands.md) | None | Unlocked |
| `export-archive` | Export Archive… in the unsupported form | None | As in commands.md |
| `open-kept-note`, `clear-kept-notes` | Settings ▸ Sync ▸ Changed on Two Devices ([settings-sync.md](../screens/settings-sync.md)) | None | Unlocked |

Keep Both and Keep Version… have no command ids and no shortcuts, so a choice is never one key press. The sheet's Cancel/Done is the Escape key on the Mac and with a hardware keyboard.

## Copy differences

None. All keys are the same on iPhone, iPad and Mac; no `mac` variants.

## Accessibility

- No success announcement: closing the sheet and opening the entry is the confirmation. The entry form moves VoiceOver focus to its status line after a refresh. Settling a journal or a deletion posts nothing.
- Locking mid-review dismisses the sheet; VoiceOver then lands on the lock screen as for any lock (see [platform.md](../platform.md#13-device-authentication-and-app-lock)).

## Differences between iPhone, iPad and Mac

- The same code path and the same results on all three. Only presentation differs (see the screen pages): sheet chrome (navigation bar on iPhone and iPad, hand-built title and footer on the Mac) and the Escape key.
- The Mac Changes to Review section lives in a Settings window tab; on iPhone and iPad it is in the Sync pane of the Settings sheet.

## Screenshots

Only the entry or template form is captured; the unsupported form and the Changed on Two Devices list are not (the sample library has no such records, and the capture script is not extended until the owner asks), so this page stays a draft until they are. The two `default` images are the same files as the other device captures of [screens/entry-conflict.md](../screens/entry-conflict.md); the keep one images show the Keep One Version menu open. No Mac capture exists for this flow.

| Device | Image | State |
| --- | --- | --- |
| iPhone | ![Other Device selected](../screenshots/iphone/resolve-conflict-default.png) | Review of Slow Sunday with Other Device selected |
| iPhone | ![Keep One Version menu](../screenshots/iphone/resolve-conflict-keep-one.png) | The Keep One Version menu open with its two items (each leads to a confirmation) |
| iPad | ![Other Device selected](../screenshots/ipad/resolve-conflict-default.png) | The same, as a card sheet |
| iPad | ![Keep One Version menu](../screenshots/ipad/resolve-conflict-keep-one.png) | The menu open as a popover over the card |

## Source files

Core:

- `JournalCore/Store.swift`: `conflicts()`, `resolve` (keep both, this device, other device), `recordConflict`, `keepChangedVersion`, import of conflicts.
- `JournalCore/SyncReconciliation.swift`: when a remote version becomes a conflict.
- `JournalCore/ConflictResolution.swift`, `JournalCore/StoreConflictResolution.swift`: the rule and its orchestration for journals and permanent deletions. `JournalCore/KeptNotes.swift`: the notes. `JournalCore/StoreDeletion.swift`: permanent deletion.

Model:

- `Model/AppModel.swift`: `conflicts`, `commitMutation`, `finishPendingSave`, `flush`.

View:

- `Views/ConflictRouting.swift`, `Views/EntryConflictReview.swift`, `Views/SettingsView.swift` (the lists).

Design records: [stale-conflict-recovery.md](../../../../docs/design/stale-conflict-recovery.md), [journal-conflicts.md](../../../../docs/design/journal-conflicts.md), [permanent-deletion.md](../../../../docs/design/permanent-deletion.md), [entry-conflict-accessibility.md](../../../../docs/design/entry-conflict-accessibility.md).

## Open questions

See [open-questions.md](../../../open-questions.md), C24: the spec says "Keep Both ... the other device's version becomes a new entry where that device had it"; the store writes the copy with the current time as its modification time and keeps its own journal and date fields, which matches, but the spec does not say the copy's modification time changes.
