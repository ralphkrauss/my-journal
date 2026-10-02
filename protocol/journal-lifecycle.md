# Journal lifecycle

The interaction decisions are in [journal-lifecycle-proposal.md](../docs/design/journal-lifecycle-proposal.md) and its [review](../docs/design/journal-lifecycle-review.md). This page defines how deletion and restoration of journals and entries are represented and applied.

## Representation and ordering

A journal's existing encrypted deletedAt value controls inherited visibility. Deleting it changes only that journal record. Children retain their bytes, identity, parent relationship, independent tombstones, history and pending operations. Restoring a parent clears its tombstone; it never rewrites children or guesses which deletion cycle an old boolean belonged to. Existing server record revisions and conflict handling order parent changes. No wall-clock last-write-wins or child-cascade messages are introduced.

An entry's effective location is derived from one atomic JournalLifecycleSnapshot containing records and conflict identities:

1. Missing parent: unavailable/missing.
2. Unsupported parent: unavailable/unsupported.
3. Parent with unresolved conflict: unavailable/conflict, irrespective of which version happens to look live.
4. Deleted parent, independently deleted entry, or legacy deletedWithJournal marker: Recently Deleted.
5. Otherwise: ordinary journal membership. Unsupported entry content remains a separate editability constraint; an unresolved entry conflict still requires its existing review flow.

Agent create/list/search/read use this same snapshot. Grants cannot initially include unavailable parents; existing grants remain scoped to their original IDs but expose no deleted/unavailable/conflicted-parent entries. Agent entries additionally exclude unsupported documents and unresolved entry conflicts. Snapshots avoid reading records and conflicts at different points in a concurrent store mutation. This does not replace lock/revocation epoch checks, which remain in force.

## Atomic operations

- prepareJournalDeletion captures current journal ID/name and the locally live child ID set, excluding independent/legacy deletions. It refuses unsupported/missing/deleted parents and identifies an affected parent/child conflict.
- deleteJournal revalidates the name, affected set and conflicts inside the same SQLite write that saves the parent tombstone. A changed name/set requires a new user confirmation; it cannot silently include newly arrived entries. Counts are local and the approved UI must explain offline devices.
- restoreJournal requires a supported, conflict-free parent and clears only its tombstone. Confirmation callers supply the displayed expected title, checked atomically; a renamed journal requires renewed review. An already-restored journal returns an explicit outcome to confirmation callers. Deletion likewise distinguishes already-deleted state from stale membership/name. Independently deleted and legacy children stay deleted. Child conflicts are not resolved or rewritten; native readers must retain their review requirement.
- moveEntry retains its ordinary no-tombstone-clearing behavior. Source and destination parents must be present/supported/conflict-free; destination must be live. A parent-hidden live entry can move out of a deleted journal, keeping its own identity/content.
- restoreAndMoveEntry explicitly clears only that entry's own tombstone and legacy marker, changing its parent to a live supported destination. Source/destination and entry conflicts are refused. A supported legacy-marker entry may be explicitly recovered even when its source parent is missing; this clears only that entry’s marker/tombstone and assigns the chosen destination. Ordinary missing-parent entries and entries under unsupported parents remain read-only. This operation never restores the original parent or siblings.
- prepareEntryRestoration and restoreEntryAndJournal restore an entry together with its deleted journal. The immutable, store-bound plan captures the entry identity and displayed title and date, the journal's identity, title and deletion state, and the journal's children with their deletion states. The commit revalidates that scope in one local transaction, restores the journal and clears deletion flags only on the selected entry; other children keep their stored state, and inherited deletion ends with the journal's. A changed scope requires a fresh review. If the journal was already restored, the plan refreshes the captured entry without writing. Pending sync requests are preserved, and the local transaction does not deliver both records to other devices atomically.

Writes preserve existing immutable outbox retry bytes. If an older pending version is acknowledged, the existing save/acknowledge machinery queues the later lifecycle change at the updated revision. Cancellation is checked before entering each synchronous transaction. Operations return the canonical saved record for model reconciliation; native callers must own the operation through commit and must not save an old retained draft over a committed change.

## Journal names

Journals that aren't in Recently Deleted have different names ([design](../docs/design/journal-name-uniqueness.md)). Two names are the same when they're equal after trimming surrounding white space and ignoring case; an empty title counts as "Untitled Journal". Titles are encrypted, so servers can't enforce this; clients do:

- **Local writes** (create, rename, restoring a name from Version History) refuse a name another listed journal has. A write that keeps a journal's name, or only changes its case, is never refused. Restoring a journal from Recently Deleted, keeping a journal in a deletion review, importing an archive and joining a server add a number instead: "‹name› 2", or the smallest number from 2 whose name is free, always added to the whole name.
- **Receiving never refuses or changes a journal because of its name.** After a client has read every page of changes, it groups listed journals by name. In each group the oldest by (`date`, then record ID) keeps its name, and every other journal, in that order, gets the next free numbered name; the numbers don't depend on which journals the client may rename. A client renames only journals with no local change waiting to be sent, no change to review and content it can fully edit. It sends each rename as an ordinary change on the revision it read and stores it only once accepted: a rename refused as stale is dropped, and the client reads again and repeats the rule. Every client computes the same result, so a client that syncs later finds nothing to do, and an automatic rename never creates a change to review.
- A library without a server applies the same rule, as ordinary edits, whenever it opens.
- **Older app versions** don't apply the rule. Their journals are renamed by newer clients like any other; a name an older client creates or restores into a taken name stays duplicated until a newer client syncs.

## Tests

JournalLifecycleTests use real encrypted stores and per-record receipts across reordered pages and three replicas: a child before its parent, a deleted parent before restoration, late independently deleted entries, repeated cycles, stale parent replay, and an entry written on an offline third store before deletion but delivered after restoration. They also check refusal of changed membership or name confirmations, unchanged pending bytes, image preservation, recovery of a legacy entry without restoring its parent, refusal of reads and changes under a conflicted parent, and preservation of unknown parent fields. The receipt helper is an in-process protocol harness; the separate Swift and .NET sync probe (`scripts/test-sync.sh`) checks the real transport. Encrypted history and backups are retained: these operations don't promise physical erasure.
