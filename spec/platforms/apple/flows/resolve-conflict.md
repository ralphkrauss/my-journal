---
id: resolve-conflict
title: Changes made on two devices (Apple)
spec: flows/resolve-conflict.md
features: [conflict-kept-both, kept-both-notice, changed-on-two-devices-list]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreConflictCopies.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/KeptNotes.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncReconciliation.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreDeletion.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreMerge.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/ConflictNotes.swift
  - apps/apple/JournalApp/Views/KeptVersionNotice.swift
  - apps/apple/JournalApp/Views/KeptNotesSection.swift
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - docs/design/permanent-deletion.md
  - docs/design/1-1-conflicts-and-reconnect.md
---

# Changes made on two devices (Apple)

Implements [flows/resolve-conflict.md](../../../flows/resolve-conflict.md) on iPhone, iPad and the Mac. There is no flow for the person to walk through any more: the store settles every conflict it can read, and the person finds out from the notice above the open entry or template ([screens/kept-version-notice.md](../screens/kept-version-notice.md)) and the list in Settings ▸ Sync ([screens/settings-sync.md](../screens/settings-sync.md)). This page records how that is wired: where conflicts come from in the code, which part of JournalCore settles which, what the app does to its own state afterwards. The Review Changes sheet (`ConflictReview`, `EntryConflictReview`, `ConflictRouting.swift`, `ConflictNotice`, the row symbol) and the choices Keep Both and Keep Version were removed in 1.1; `JournalStore.resolve(_:choice:)` and `ConflictChoice` stay public for tools and tests only and no screen calls them. Sync behaviour: [platform.md](../platform.md#30-sync-lifecycle-and-background).

## Controls

The model type throughout is `AppModel` (`@MainActor`) over the `JournalStore` actor in JournalCore.

**How a conflict comes to exist** (core, not UI)

- A remote change arrives for a record that is dirty here, or that already has a conflict, or that is a permanent-deletion marker being replaced by live content: `JournalStore.recordConflict` writes one row to the `conflicts` table (remote payload, server revision, device id, modification time). One row per record: a newer remote version replaces the row and the replaced one goes to history (`preserveSupersededConflict`). `SyncReconciliation` also records one when a library joins a server by identity and the contents differ; a record that merely lacks the server's version is re-uploaded instead.
- This device saves over a version that changed after the saved copy was read: `keepChangedVersion` stores the stored version as the other side, with the all-zero device id standing for an unknown device, so the copy it becomes is never replaced by a later one. Typing over a change that arrived but was not shown is covered by `StaleDraftTests`.
- Merging journals (`StoreMerge.swift`) inserts a `conflicts` row when the same record exists in two different versions, and an archive imported as new journals carries the archive's unresolved conflicts over with new ids (`Store.importHistory`).
- The library record (pins and journal order) never becomes a conflict; it is reconciled field by field.
- `AppModel.adoptConflicts` takes the ids of the rows from each refresh's snapshot: `conflictedIDs` (every record with a conflict; the lifecycle waits on them), `settlingConflictIDs` (those that settle at the next pull, which do not keep a journal out of use) and `heldConflictIDs` (those a newer version must read, from `JournalStore.heldConflictIDs()`). A held change sets `heldChangesNeedUpdate`, which drives the Sync footer line `messages.conflict.kept.updateNeeded` and notes a problem for the rating request. Nothing else counts: `AppModel.conflicts` and its `reviewRequests.noteProblem()` call are gone.

**Settled by the store** (core, no UI)

- `JournalStore.resolveConflicts(at:holding:)` (`StoreConflictResolution.swift`) runs for a `ConflictResolutionPoint`: the end of a completed pull (`SyncEngine`, also when pushing another record failed), the opening of a library, and `.local` (after a local merge or import, or after a stale save when no server is configured). It settles each row in its own write transaction with `ConflictResolution.resolve(local:other:ids:)`, a pure function over decoded items (outcomes `held`, `keepBoth`, `sameContent`, `parked`, `twoMarkers`, `journal`, `journalMarker`). It does nothing while a reconciliation is in progress, for a record that is being written (`isBeingWritten`: a save in the last two seconds), for a record the caller holds (the open entry while its save has failed, `AppModel.conflictsToHold`), or for a version the app can't read (`held`).
- **Row 3, entries and templates (`keepBoth`).** The record keeps this device's bytes and the other version's revision, queued on that revision. `StoreConflictCopies.keepOtherVersionAsCopy` then, in this order: leaves everything alone if a record with the derived identity exists in any state; else replaces the latest earlier copy of the same record (same known origin device, higher revision, plaintext digest unchanged, no conflict or queued change on it, not being written), the replaced content going to the copy's Version History; else inserts the copy at revision 0 and queues it. The copy's title is `ConflictResolution.copyTitle(of:)` (`messages.conflict.copyTitle`, the first line cut at 60 grapheme clusters, “New Entry” or “Untitled Template”). It adds or updates a `KeptNote` of kind `keptBoth`.
- A permanent deletion against an edit parks the edit as a new entry or template with an identity derived from the edited text (`ConflictCopyIdentity`, the label “conflict-park”; the derivation key is HKDF from the vault key, a public constant in a library without encryption). A record that already has that identity, in any state, is left alone. `AppModel.followResolved` moves the open entry's draft to the parked entry (`followParkedEntry`) so typing continues into one entry.
- Opening a library first runs `completeOpeningPass()`: it settles the rows an earlier version left, once per library, in two recorded steps (journals and permanent deletions, then every kind), before any sync can replace a row's other version. This includes the entries and templates 1.0 left in Review Changes. `AppModel.settleConflictsOnOpening` calls it and writes nothing when there is nothing to settle.
- Without a server there is no pull, so `AppModel.resolveConflictsWhenWritingPauses` settles a stale save's row about 2.25 seconds after writing stops.
- Each outcome that the person should know about adds a `KeptNote` to the sealed settings key “kept-notes” (`KeptNotes.swift`, `KeptNotesState`: up to 20 notes, 30 days, rename notes last to go; up to 200 remembered automatic copies; AAD `journal:v1:local:kept-notes`). The key is local: never synced, re-sealed with “library-changes” when protection changes, ignored if it can't be opened. No table or schema object was added. A replaced copy updates its note and keeps whether the person saw it.

**What the person sees** (UI)

- The notice above the open entry or template (`KeptVersionNotice`) and the list (`KeptNotesSection`, rows from `AppModel.keptNoteRows`): see their pages. Show Other Version and a list row both call `AppModel.openKeptNote`, which marks the note seen; Dismiss calls `AppModel.dismissKeptNote`.

**Refusals while a conflict waits** (UI)

- `JournalStore.requireNoConflict` throws `JournalLifecycleError.conflict` for Move Entry (the entry, its journal and the destination), restoring a Version History version (the destination journal), Restore and Delete Journal (an entry waiting), and Delete Permanently (`PermanentDeletionError.conflict`). `MoveEntryView` and `VersionHistoryView` show `messages.lifecycle.combining` when the id is not in `heldConflictIDs` and `messages.lifecycle.unsupportedJournal` when it is; `PermanentDeletionPrompt` shows `messages.lifecycle.combining` or, for a held record, `messages.generic.deleteNeedsUpdate`. Delete All reads the waiting item as `DeletionHold.other` (the `.review` case is gone). `RestoreAvailability.unavailable` hides Restore; `canDescribeImages` and `offersImageDescriptions` exclude `conflictedIDs`.

**After the flow.** While a record has a conflict it can still be opened and edited: autosave writes the local version, and the sync outbox skips any record that has a `conflicts` row (the `LEFT JOIN conflicts` in `Store.pending`), so nothing is sent until the store settles it. A journal is never dimmed for a settling conflict: a journal whose row is held is located as unsupported by `JournalLifecycleSnapshot`, which lists its entries under Unavailable Journals with `common.updateToRestoreEntry`.

## Layout

The flow has no layout of its own; the notice and the list are on their pages. Nothing is a sheet and nothing blocks the library: the person never leaves the entry list.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `show-other-version`, `dismiss-kept-notice` | The notice's buttons ([screens/kept-version-notice.md](../screens/kept-version-notice.md)) | None | Unlocked, not replacing the library |
| `open-kept-note`, `clear-kept-notes` | Settings ▸ Sync ▸ Changed on Two Devices ([settings-sync.md](../screens/settings-sync.md)) | None | Unlocked |

`export-archive` is no longer part of a conflict: it lives in Settings ▸ Backup only.

## Copy differences

None. All keys are the same on iPhone, iPad and Mac; no `mac` variants.

## Accessibility

- Settling posts nothing, and the notice posts no announcement. The notice is read when focus reaches it; each list row is one element with a hint ([settings-sync.md](../screens/settings-sync.md)).
- Locking hides the list and the notice; nothing they showed is kept.

## Differences between iPhone, iPad and Mac

- The same code path and the same results on all three. Only the containers differ: the notice (see its page) and the list (a pane of the Settings sheet on iPhone and iPad, a tab of the Settings window on the Mac; a row brings the library window forward on the Mac).

## Screenshots

None yet: the capture script has not been run for the kept-both notice or the new list rows (the notice is captured by `SpecConflictCaptureTests` as entry-editor-kept-both-notice and entry-editor-held-notice). The 1.0 captures of the review sheet were removed with it, so this page stays a draft until the new ones exist.

## Source files

Core:

- `JournalCore/Store.swift`: `conflicts()`, `recordConflict`, `keepChangedVersion`, `requireNoConflict`, `pending`, import of conflicts; `resolve(_:choice:)` and `ConflictChoice` (tools and tests only).
- `JournalCore/SyncReconciliation.swift`: when a remote version becomes a conflict. `JournalCore/SyncEngine.swift`: the resolution point after a pull.
- `JournalCore/ConflictResolution.swift`, `JournalCore/StoreConflictResolution.swift`, `JournalCore/StoreConflictCopies.swift`: the rule, its orchestration, the copies and the one-time pass. `JournalCore/KeptNotes.swift`: the notes. `JournalCore/StoreDeletion.swift`: permanent deletion.

Model:

- `Model/AppModel.swift`: `conflictedIDs`, `settlingConflictIDs`, `heldConflictIDs`, `heldChangesNeedUpdate`, `keptNotes`. `Model/ConflictNotes.swift`: `adoptConflicts`, `keptNoteRows`, `entryNotice`, `dismissKeptNote`, `openKeptNote`, `settleConflictsOnOpening`, `resolveConflictsWhenWritingPauses`, `followResolved`.

View:

- `Views/KeptVersionNotice.swift`, `Views/KeptNotesSection.swift`.

Design records: [stale-conflict-recovery.md](../../../../docs/design/stale-conflict-recovery.md), [journal-conflicts.md](../../../../docs/design/journal-conflicts.md), [permanent-deletion.md](../../../../docs/design/permanent-deletion.md), [1-1-conflicts-and-reconnect.md](../../../../docs/design/1-1-conflicts-and-reconnect.md).

## Open questions

See [open-questions.md](../../../open-questions.md), D63 to D65 (an older copy in Recently Deleted, moved against edited, the short refusals).
