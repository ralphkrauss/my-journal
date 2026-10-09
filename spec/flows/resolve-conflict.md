---
id: resolve-conflict
title: Changes made on two devices
features: [conflict-kept-both, changed-on-two-devices-list, conflict-notice, changes-to-review-list, conflict-review-entry, conflict-review-unsupported]
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/KeptNotes.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreDeletion.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncReconciliation.swift
  - apps/apple/JournalApp/Model/JournalOperations.swift
  - apps/apple/JournalApp/Views/ConflictRouting.swift
  - apps/apple/JournalApp/Views/EntryConflictReview.swift
  - docs/design/entry-conflict-accessibility.md
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - docs/design/permanent-deletion.md
  - docs/design/1-1-conflicts-and-reconnect.md
  - protocol/conflicts.md
---

# Changes made on two devices

## Purpose

Nothing a person wrote is overwritten or lost when the same item changed on two devices. Since 1.1 the device settles journals and permanent deletions itself, keeps both versions and says so afterwards in a quiet list ([screens/settings-sync.md](../screens/settings-sync.md), Changed on Two Devices). Entries and templates that differ are not settled yet: both versions are kept until the person chooses in the Review Changes sheet ([screens/conflict-review.md](../screens/conflict-review.md), [screens/entry-conflict.md](../screens/entry-conflict.md)). That form goes when simplification H reaches its second step.

The rule, the equality it uses and the orchestration are a client contract in [protocol/conflicts.md](../../protocol/conflicts.md); this file says what the person sees and what stays true for them.

## When it happens

A conflict exists when:

- **sync receives a version** of an entry, template or journal that this device also changed and hasn't sent yet, or that differs from this device's version when a library joins a server by identity;
- **this device saves over a version that changed meanwhile** (for example a sync arrived between reading and saving): the change that arrived is kept for the decision instead of being overwritten;
- **one side deleted the item permanently** while the other edited it, or both deleted it;
- **merging or importing** finds the same record in two different versions.

Until it is settled the record can be edited and saved on this device, but its changes aren't sent.

## What the device decides: journals and permanent deletions

**L** is the version this device holds as the record and **R** is the other version, the latest one the server holds. "Last" is the order in which the server accepted the versions, never a device clock: a device that was offline for a week and syncs last has its text win the record. The first row that fits applies.

| Situation | Record | The other version | Note in Changed on Two Devices |
| --- | --- | --- | --- |
| A version this app can't read (saved by a newer version) | **Held**: nothing changes, nothing is sent | none | none; one line in the Settings ▸ Sync footer, `messages.conflict.kept.updateNeeded` |
| Same content (below) | The merged deletion state (below) on that content; if that equals R, R is adopted and nothing is sent | none | none |
| An entry or template against a permanent deletion | The deletion (final) | The edited version, **saved as a new entry or template** in Recently Deleted (below) | `messages.conflict.kept.deletedAndChanged` |
| Two permanent deletions | One deletion | none | none |
| A journal, content differs, neither deleted permanently (a rename on two devices) | The later name (L) | R's name, in the note and in the journal record's history | `messages.conflict.kept.journalRenamed` |
| A journal against a permanent deletion | The deletion (final) | none: no journal is created | `messages.conflict.kept.journalDeleted` |
| An entry or template that differs, neither deleted permanently | **Still the review** | | |

**Same content** means the title, the whole document (text, images and their descriptions, links, block identities), date, journal and archive state of an entry; title, document, date and archive state of a template; and title and the stored default-template field of a journal are equal. The time of the last change is not content. The comparison is strict: a difference in anything else makes the versions different. A conflict that is only "deleted on one device, untouched on the other" is therefore not a conflict: the item ends up in Recently Deleted once, with its content.

**Deletion state.** Whether and when an item is in Recently Deleted is merged as one unit with no clock: when only one version is deleted, its deletion is taken; when both are, the one an earlier version made together with its journal is taken, else the other device's. An item restored on one device and deleted on the other stays deleted, one Restore away.

### An edit against a permanent deletion

Someone used Delete Permanently on one device while the item was edited (or restored) on another. The deletion keeps its promise and stays final; the edit is not discarded.

- The deletion is the record on every device.
- The edited version becomes a **new entry or template** with the same title, content, date and journal, deleted at the time of the permanent deletion, so it is in [Recently Deleted](../screens/recently-deleted.md) and one Restore brings it back. It gets a derived identity, so every device that finds the same conflict makes the same one, once.
- If its journal is live it is in Recently Deleted; if the journal was also deleted permanently or is gone it is in Unavailable Journals, where Restore puts it in the Default Journal ([flows/delete-and-restore.md](delete-and-restore.md), Restore).
- If the item was open, the editor moves to the new entry without losing the text, the draft or the cursor, so typing continues into one entry.
- For a journal nothing is created: a journal is a name and a deletion state, with no writing. Entries edited elsewhere in it are separate records and are saved as above.

### A journal renamed on two devices

The later name (the server's order, not the newer edit) stays; the other name is in the note, which never expires, and in the record's history. Nothing displays that history. Renamed on one device and deleted on the other, the journal is deleted with its own name, one Restore away. If a name is then taken by another journal, the name rule numbers the later one ("Work 2") as an ordinary change; Rename gives it a name of its own. A default template one device changed is kept as this device has it and ignored by 1.1.

### What stays held

A version this app cannot read stays as it is. The record isn't sent, the item is not changed, nothing is created. At each point below the app tries again, so it settles once the app can read both. The person sees only the footer line; for an entry or template the review sheet shows its unsupported form ([screens/conflict-review.md](../screens/conflict-review.md)). A journal that is held is treated like one saved by a newer version everywhere ([screens/unavailable-content.md](../screens/unavailable-content.md)).

## When the device settles it

1. The conflicts the device finds are kept in a local list, one per record (the latest other version only; earlier ones go to Version History).
2. They are settled **at the end of every completed pull** (also when pushing another record failed), **when the library opens** for what an earlier version left and, when no server is configured, for any conflict, and **after a local merge or import**. Never while the library is being restored from the server, never for a record being written (the cursor rests in it, or a save has failed), and never for a held one.
3. **One transaction per record**: the outcome, the new entry or template, the note and the removal of the conflict happen together or not at all; a failure leaves everything as it was and the next round repeats it.
4. After it the round sends what it queued; the person waits for nothing.

### What 1.0 left pending

When 1.1 opens a library in which 1.0 left journal or permanent-deletion conflicts pending, it settles them once with the same rule, before any sync can start, and lists each outcome in Changed on Two Devices. A deletion the person had meant to confirm with Keep Deletion is made final and the edit saved separately, never the reverse. A pending conflict whose versions no longer fit is dropped, its other version kept in Version History. Nothing is asked: both versions are kept. Entries and templates 1.0 left pending still wait for the person.

## Entries and templates (the review)

### 1. Open the review

1. The open entry's writing is saved first. If that fails, the review doesn't open and the save-failure alert explains (see [flows/save-failure.md](save-failure.md)).
2. The sheet decides its form from the current versions: entry or template, or unsupported. If the changes are already gone it shows `messages.conflict.resolved`.

### 2a. Entry or template

1. The person compares This Device and Other Device: title, modification date, where each version is (`messages.conflict.placement.*`, only when they differ), and the full text with images.
2. **Keep Both.** The pending save of the open entry finishes first (failure: `messages.save.before.goBack`, nothing changed). Then this device's version stays as the record, and the other device's version becomes a new, separate entry (or template) where that device had it, with its own date. Both are sent.
3. **Keep Version from This Device… / Other Device….** Confirmation `messages.conflict.keepOne.title` with `messages.conflict.keepOne.history`; for Other Device, what happens to the entry here comes first (`messages.conflict.outcome.*`: it moves, is archived, or changes date). Keep Version saves the chosen version as the record; the other is kept only in Version History.
4. **Outcome.** The changes are marked resolved, the journals are read again, the resolved entry opens, and the sheet closes. No success message.

### 2b. Unsupported

A version has content this version of My Journal can't read. The person can only Export Archive… to keep a copy (the archive includes both versions and history) or Cancel. Updating My Journal makes the review possible.

### 3. When something changes meanwhile

| What happened | Entry review |
| --- | --- |
| The versions changed while the sheet was open, or the store refused a choice as stale | Reads them again (`messages.conflict.updatingChanges`), then `messages.conflict.status.updated`; This Device shown, choice cleared, focus on the status |
| Reading them again failed | `messages.conflict.status.refreshFailed` with Try Again; previews hidden |
| The choice was saved, but showing the result failed | `messages.conflict.committedNotReloaded` with Try Again (reloads only) and Done |
| Resolved on another device | `messages.conflict.resolved` with Done |
| A version became unreadable | the sheet switches to the unsupported form |
| The app locked | the sheet closes; uncommitted work stops; nothing it showed is kept |
| Any other failure | its message as the status; choices kept for retry |

## Rules

- Both versions are kept in every outcome. Nothing is overwritten silently; a permanent deletion is never undone by an edit.
- No clock decides. The version that reached the server last is the record; an item the person typed longer ago can win, and the other version is then in the note or the review.
- A journal or permanent-deletion conflict never asks, never blocks Rename, Delete Journal, Move Entry or Restore, and never shows an alert, a badge, a sound or Sync Status. Only a held one needs the person, by updating.
- Entry and template review: every choice stores both originals in Version History in the same transaction; it applies only to the versions shown (a stale choice is never applied and a committed one never twice); once committed, cancelling, locking or a failed refresh never undoes or repeats it.
- While an entry or template has changes to review it can be edited and saved on this device, but its changes aren't sent until it is settled.
- Keep Both is offered only for entries and templates.
- Only entries and templates the person must review count as a problem for the rating request ([flows/rating-request.md](rating-request.md)); the notes of Changed on Two Devices never do.

## Accessibility

- The entry review's status receives VoiceOver focus after an explicit refresh.
- No success announcement; the sheet closing and the entry opening are the feedback. Settling a journal or a deletion is silent; the list in Settings is where it is found ([screens/settings-sync.md](../screens/settings-sync.md)).
- Confirmation dialogs are standard.

## Platform notes (Apple)

- Identical behaviour on iPhone, iPad and Mac; only sheet chrome differs (see the screen file).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
