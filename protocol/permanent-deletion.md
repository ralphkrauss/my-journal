# Permanent deletion

Delete Permanently, offered for items in Recently Deleted, replaces each affected record with a content-free marker that syncs to other devices, and removes those records' local Version History. It is removal from ordinary recovery, not physical or cryptographic erasure: image files are kept, and the server's earlier revisions, server backups, archives and copies held by others still contain the earlier encrypted versions. The interaction is described in the [design record](../docs/design/permanent-deletion.md) as amended by [owner-decisions-2026-09-25.md](../docs/design/owner-decisions-2026-09-25.md).

## Marker

A marker is a record whose optional `permanentlyDeletedAt` timestamp is set ([records.md](records.md)). A canonical marker:

- has kind `journal`, `entry` or `template`;
- has a fresh UUID `permanentDeletionID` (each deletion gets its own, even when timestamps coincide) and no `restoredFromDeletionID`;
- keeps only its ID, kind and deletion identity: `title` is empty, the document is empty, `journalID`, `defaultTemplateID` and `archivedAt` are absent, and `deletedWithJournal` is false;
- has `date`, `modifiedAt` and `deletedAt` equal to `permanentlyDeletedAt`.

A record with marker fields that isn't canonical is kept byte for byte as an unreadable, read-only record ([reading rules](records.md#reading-rules)). It is never treated as a marker and never removes history. Earlier clients that don't know these fields keep markers as unsupported content.

Records that aren't markers can't carry `permanentDeletionID`, and only journals, entries and templates can carry `restoredFromDeletionID`.

## Confirming a deletion

`preparePermanentDeletion` captures what the confirmation describes, bound to one store instance:

- for an entry, the entry, which must be in Recently Deleted;
- for a template, the template, which must be deleted (in Recently Deleted);
- for a journal, the deleted journal and every current entry whose `journalID` is that journal, including entries deleted on their own, but not entries since moved elsewhere;
- the affected history rows;
- history-only entries: entries with history but no current record whose last known journal is the selected journal. They aren't deleted and are counted in the confirmation.

Preparation refuses records this client can't fully read, missing, unsupported or conflicted parents, and any affected record with a known conflict.

`permanentlyDelete` revalidates the captured scope inside one database write. A change to affected content, membership, history or history-only entries, a newly known conflict, restoring the item or its journal, or using the confirmation with another store refuses the deletion and requires a new confirmation. Unrelated edits and a revision change without a content change don't. The transaction then replaces each affected record with a marker at its current server revision and removes that record's local history. Pending sync requests stay byte for byte unchanged; once acknowledged, the newer marker is queued through the ordinary path. Cancellation or any database failure rolls back the whole transaction. The deletion of a journal and its entries is atomic locally, but other devices may receive the records one at a time, with any conflicts kept for review.

## Receiving and saving

- A canonical incoming marker, for a record with no local changes and no unresolved conflict, replaces the record and removes its local history. A replayed older revision is ignored before anything is removed.
- If the record has local changes or an unresolved conflict, the incoming marker is kept as a conflict for review. A newer version of a conflicting record keeps the earlier conflicting version in history first.
- A newer ordinary revision over a current marker becomes a conflict, unless it carries the matching `restoredFromDeletionID` (see below).
- A save made from a copy read before a marker arrived becomes a deletion conflict instead of bringing the item back. Ordinary saves can't create or overwrite a marker, copying from Version History or restoring journal settings can't revive a marked record, and ordinary conflict choices refuse a marker on either side.
- A journal marker doesn't remove entries this device hasn't seen yet; they stay Unavailable while the journal is deleted.
- Lists, search and agent access omit marked records. Additive import keeps markers through a creation-only path with fresh identities, and archives keep marker fields and unknown content unchanged.

No automatic deletion timers exist, and history-only membership is never inferred from old versions.

## Resolving a deletion conflict

`prepareDeletionConflict` captures both versions, the remote revision, device and time, the surviving history and the store. `resolveDeletionConflict` revalidates that state in one transaction; changed history or content requires a fresh review. Records this client can't fully read, and unavailable or conflicted destination journals, are refused.

- **Keep Deletion** keeps the marker and removes the surviving local history.
- **Keep Entry** restores the edited content, date and images under the original identity, in a journal the person chooses. Surviving history stays; history already removed isn't recreated.
- **Keep Entry as Copy** creates one entry with a new identity and keeps the marker. The surviving history stays in archives but isn't attached to the copy.
- **Keep Journal** restores the journal's settings only; it doesn't restore entries or resolve their conflicts.
- **Keep Template** restores the edited template under its original identity.

Restoring under the same identity clears the marker fields and sets `restoredFromDeletionID` to the reviewed marker's `permanentDeletionID`. A device with that marker and no local changes accepts exactly this value as an intentional restoration; an ordinary edit, or a restoration that names an earlier deletion, still becomes a conflict. Copies with a new identity don't carry `restoredFromDeletionID`. These fields record the intent of a client that holds the vault key; they aren't a server authorization mechanism. Markers without a `permanentDeletionID`, which only pre-release test builds wrote, aren't canonical.

Resolution retires the superseded pending request and queues a new operation against the reviewed remote revision; an operation ID is never reused with different bytes. Creating the copy, removing the conflict, updating the marker and queueing are one transaction, rolled back on failure or cancellation. Image files and server history are kept.

## Tests

Real SQLite tests cover rollback after a failure midway through a multi-record deletion (including the original pending bytes), shared images, entries deleted on their own, history of moved entries, history-only entries, stale scope and wrong-store refusal, replay after acknowledgement, intentional restoration and refusal of stale restoration after a second deletion, copies with images and history, and journal-settings recovery. The sync test client (`scripts/test-sync.sh`) publishes markers over the real server, retries them, deletes a journal with pending changes, resolves an offline edit with Keep Entry and checks that other devices converge.
