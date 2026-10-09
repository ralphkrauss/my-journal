---
id: resolve-conflict
title: Changes made on two devices
features: [conflict-kept-both, kept-both-notice, changed-on-two-devices-list]
sources:
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreConflictResolution.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreConflictCopies.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/KeptNotes.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/Store.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/StoreDeletion.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncEngine.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncReconciliation.swift
  - apps/apple/JournalApp/Model/ConflictNotes.swift
  - apps/apple/JournalApp/Views/KeptVersionNotice.swift
  - apps/apple/JournalApp/Views/KeptNotesSection.swift
  - docs/design/stale-conflict-recovery.md
  - docs/design/journal-conflicts.md
  - docs/design/permanent-deletion.md
  - docs/design/1-1-conflicts-and-reconnect.md
  - protocol/conflicts.md
---

# Changes made on two devices

## Purpose

Nothing a person wrote is overwritten or lost when the same item changed on two devices, and nobody is asked to decide. Since 1.1 the device settles every conflict it can read itself: an entry or template that differs keeps both versions as two separate items, a journal keeps one name, and a permanent deletion stays final with the edit saved next to it. The person is told afterwards, quietly, by a notice above the open entry or template ([screens/kept-version-notice.md](../screens/kept-version-notice.md)) and by a list in Settings ([screens/settings-sync.md](../screens/settings-sync.md), Changed on Two Devices). There is no review sheet, no marker in the list and no hold on syncing.

The rule, the equality it uses and the orchestration are a client contract in [protocol/conflicts.md](../../protocol/conflicts.md); this file says what the person sees and what stays true for them. Version 1.0 asked the person to choose in a Review Changes sheet; that sheet is gone, and what it left pending is settled the first time 1.1 opens the library (below).

## When it happens

A conflict exists when:

- **sync receives a version** of an entry, template or journal that this device also changed and hasn't sent yet, or that differs from this device's version when a library joins a server by identity;
- **this device saves over a version that changed meanwhile** (for example a sync arrived between reading and saving): the change that arrived is kept instead of being overwritten;
- **one side deleted the item permanently** while the other edited it, or both deleted it;
- **merging or importing** finds the same record in two different versions.

Until it is settled the record can be edited and saved on this device, but its changes aren't sent. It is settled within seconds of the next sync (below).

## What the device decides

**L** is the version this device holds as the record and **R** is the other version, the latest one the server holds. "Last" is the order in which the server accepted the versions, never a device clock: a device that was offline for a week and syncs last has its text win the record. The first row that fits applies.

| Situation | Record | The other version | Note in Changed on Two Devices |
| --- | --- | --- | --- |
| A version this app can't read (saved by a newer version) | **Held**: nothing changes, nothing is sent | none | none; a line in the Settings ▸ Sync footer, `messages.conflict.kept.updateNeeded`, and on the open entry or template `messages.conflict.kept.noticeUpdate` |
| Same content (below) | The merged deletion state (below) on that content; if that equals R, R is adopted and nothing is sent | none | none |
| An entry or template that differs, neither deleted permanently | **This device's version, unchanged** (the same bytes, so an editor that has it open sees nothing) | The other version, saved as a **separate entry or template** (below) | `messages.conflict.kept.entry` or `messages.conflict.kept.entryNewer` |
| An entry or template against a permanent deletion | The deletion (final) | The edited version, **saved as a new entry or template** in Recently Deleted (below) | `messages.conflict.kept.deletedAndChanged` |
| Two permanent deletions | One deletion | none | none |
| A journal, content differs, neither deleted permanently (a rename on two devices) | The later name (L) | R's name, in the note and in the journal record's history | `messages.conflict.kept.journalRenamed` |
| A journal against a permanent deletion | The deletion (final) | none: no journal is created | `messages.conflict.kept.journalDeleted` |

**Same content** means the title, the whole document (text, images and their descriptions, links, block identities), date, journal and archive state of an entry; title, document, date and archive state of a template; and title and the stored default-template field of a journal are equal. The time of the last change is not content. The comparison is strict: a difference in anything else, including only the block identities, makes the versions different. A conflict that is only "deleted on one device, untouched on the other" is therefore not a conflict: the item ends up in Recently Deleted once, with its content.

**Deletion state.** Whether and when an item is in Recently Deleted is merged as one unit with no clock: when only one version is deleted, its deletion is taken; when both are, the one an earlier version made together with its journal is taken, else the other device's. An item restored on one device and deleted on the other stays deleted, one Restore away.

### An entry or template that differs on two devices

This device's version stays where it is and keeps its text. The other version becomes a **separate entry or template**, its **copy**:

- **Title.** `messages.conflict.copyTitle`: the other version's title followed by "(other version)". When that version has no title, the title the lists show for it is used: its first line, cut at 60 characters, or "New Entry" (`library.entryList.untitledEntry`) or "Untitled Template" (`library.entryList.untitledTemplate`). The text is always appended and never detected, so a copy of a copy reads "X (other version) (other version)". It is the only thing changed: the body is untouched.
- **Content, date and place.** The other version's, unchanged, with its images, image descriptions and links. Each version keeps its date and stays where it is: a version that was in Recently Deleted is a copy in Recently Deleted; one whose journal is gone is under Unavailable Journals, where Restore puts it in the Default Journal ([flows/delete-and-restore.md](delete-and-restore.md)). Its last-change time is the other version's; nothing reads the clock.
- **Images.** The copy refers to the same image files; none is copied.
- **Identity.** Derived from the other version's exact text, so every device that finds the same conflict makes the same copy, once ([protocol/conflicts.md](../../protocol/conflicts.md#identities)). If an entry or template with that identity already exists in any state (it arrived from another device first, was edited, deleted or deleted permanently there, or this device made it earlier), nothing is made, noted or revived: that item is the copy.
- **Replacement.** An untouched copy is replaced, not multiplied: when the other device keeps typing, its later version takes the earlier copy's place (the earlier content goes to the copy's Version History) as long as nobody has changed the copy, here or elsewhere. A copy that was edited, moved or deleted is never replaced; the later version is then a new copy. A version kept by a save on this device has no known device and is never replaced.
- **The bound.** Two devices typing in one entry make one copy of each other's latest version, not one per pause. Where two devices meet the same version while one of them replaces an earlier copy, that content can exist once more under another identity: exactly one extra copy per replacement, nothing lost. It is not removed automatically; delete it if it is unwanted.
- **Three devices.** Each device that overwrites a version it had not seen keeps that version as a copy, so every text exists once on every device.
- **Edited on one device, deleted on another.** The edited text stays in its journal and the other version stays in Recently Deleted: each version stays where it is. If the deleting device held the unedited original, Recently Deleted gets an older copy of text that also exists, edited, in the journal; the app does not try to guess.
- **Moved on one device, edited on another** gives two entries: the moved one holds the old text. The app keeps no common ancestor, so it cannot tell which fields changed.

Because the version that reached the server last is the record, a stale text from a device that was offline for a week can become the entry and the newer text its copy. The notice and the row say when the other version is newer ("that version is newer"), by the two devices' clocks; the clocks only choose the wording.

### An edit against a permanent deletion

Someone used Delete Permanently on one device while the item was edited (or restored) on another. The deletion keeps its promise and stays final; the edit is not discarded.

- The deletion is the record on every device.
- The edited version becomes a **new entry or template** with the same title, content, date and journal, deleted at the time of the permanent deletion, so it is in [Recently Deleted](../screens/recently-deleted.md) and one Restore brings it back. It gets a derived identity, so every device that finds the same conflict makes the same one, once.
- If its journal is live it is in Recently Deleted; if the journal was also deleted permanently or is gone it is in Unavailable Journals, where Restore puts it in the Default Journal ([flows/delete-and-restore.md](delete-and-restore.md), Restore).
- If the item was open, the editor moves to the new entry without losing the text, the draft or the cursor, so typing continues into one entry.
- For a journal nothing is created: a journal is a name and a deletion state, with no writing. Entries edited elsewhere in it are separate records and are saved as above.
- An automatic copy never brings a permanent deletion back: when a copy this device made and has not sent meets a deletion, the deletion wins and the copy is dropped, because its content is in the other record.

### A journal renamed on two devices

The later name (the server's order, not the newer edit) stays; the other name is in the note, which never expires, and in the record's history. Nothing displays that history, so the device whose name lost sees the other name arrive with no trail of its own. Renamed on one device and deleted on the other, the journal is deleted with its own name, one Restore away. If a name is then taken by another journal, the name rule numbers the later one ("Work 2") as an ordinary change; Rename gives it a name of its own. A default template one device changed is kept as this device has it and ignored by 1.1.

### What stays held

A version this app cannot read stays as it is. The record isn't sent, the item is not changed, nothing is created. At each point below the app tries again, so it settles once the app can read both. The person sees the line in the Sync footer and, on the open entry or template, the notice with no buttons ([screens/kept-version-notice.md](../screens/kept-version-notice.md)). A journal that is held is treated like one saved by a newer version everywhere ([screens/unavailable-content.md](../screens/unavailable-content.md)). A held entry or template can still be edited here; Move Entry, Version History restore and Delete Permanently show the update messages.

## When the device settles it

1. The conflicts the device finds are kept in a local list, one per record (the latest other version only; earlier ones go to Version History).
2. They are settled **at the end of every completed pull** (also when pushing another record failed), **when the library opens** for what an earlier version left and, when no server is configured, for any conflict, and **after a local merge or import**. Never while the library is being restored from the server, never for a record being written (the cursor rests in it, or a save has failed), and never for a held one. A person who types is never interrupted: nothing changes under the cursor.
3. **One transaction per record**: the outcome, the copy or the new entry, the note and the removal of the conflict happen together or not at all; a failure leaves everything as it was and the next round repeats it. At most one settlement per record per round.
4. After it the round sends what it queued; the person waits for nothing.

While a record's conflict waits, which is a few seconds in the normal case, the record can be edited but four actions refuse with `messages.lifecycle.combining`: Move Entry, restoring a version from Version History, and Delete Permanently; Delete All leaves the item in Recently Deleted like any item that can't be deleted yet. Image descriptions and Restore are not offered for it. A conflict that only a newer version can read shows the update messages instead (`messages.lifecycle.unsupportedJournal` for Move Entry and Version History, `messages.generic.deleteNeedsUpdate` for Delete Permanently).

### What 1.0 left pending

When 1.1 opens a library in which 1.0 left conflicts pending, it settles them once with the same rule, before any sync can start, and lists each outcome in Changed on Two Devices. That includes entries and templates the person left in 1.0's Review Changes: both versions are kept, and the other becomes a copy. A deletion the person had meant to confirm with Keep Deletion is made final and the edit saved separately, never the reverse. A pending conflict whose versions no longer fit is dropped, its other version kept in Version History. Nothing is asked: both versions are kept. The pass runs in two recorded steps, journals and permanent deletions first and every other kind second, so a library that only finished the first step settles its entries and templates the next time it opens. A conflict that is held stays held.

## What the person sees

- **Above the open entry or template**, on the device that kept both, a notice with Show Other Version and Dismiss ([screens/kept-version-notice.md](../screens/kept-version-notice.md)). It is local: other devices see the copy, with its title, as an ordinary entry.
- **In Settings ▸ Sync ▸ Changed on Two Devices**, one row per settled change for 30 days ([screens/settings-sync.md](../screens/settings-sync.md)); a row for a copy opens it. A copy that is replaced by a later version updates its row instead of adding another.
- **In the lists**, the copy sits next to the original with its own date. Search, pins, Move Entry, Delete and Restore work on it as on any entry. Agents granted the journal see it as one more entry, read-only like everything.
- Nothing else: no alert, no badge, no sound, no Sync Status, no hold on syncing.

## Rules

- Both versions are kept in every outcome. Nothing is overwritten silently; a permanent deletion is never undone by an edit.
- No clock decides. The version that reached the server last is the record; an item the person typed longer ago can win, and the other version is then its copy. Device clocks only choose the notice's and the row's wording ("newer").
- Nobody is asked and nothing blocks syncing. Only a held conflict needs the person, by updating My Journal.
- A conflict never counts as a problem for the rating request ([flows/rating-request.md](rating-request.md)); a held one still does.
- A record being written is never settled under the person.
- The notes are local to the device: never synced, 30 days, at most 20; journal rename notes stay until Clear List.

## Accessibility

- Settling is silent: no announcement is made. The notice is read when focus reaches it, as text followed by two buttons; the list rows are single controls with a label and a hint ([screens/settings-sync.md](../screens/settings-sync.md)).

## Platform notes (Apple)

- Identical behaviour on iPhone, iPad and Mac; only the container of the notice and of the list differs (see the screen pages).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
