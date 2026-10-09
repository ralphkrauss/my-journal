# Settling conflicts (conflicts v1)

When two devices change one record, each keeps its own version until they meet at the server ([Sync and conflicts](README.md#sync-and-conflicts)). A client that implements this page settles what it can without asking: it keeps both versions' content, readable, and tells the person afterwards. The design is in [docs/design/1-1-conflicts-and-reconnect.md](../docs/design/1-1-conflicts-and-reconnect.md).

The page has its own version, **conflicts v1**, because it is a client contract and changes no wire format: no endpoint, capability, record field, archive table or server release is involved, and the server never learns that a conflict happened. `/v1` and every existing fixture stay valid.

- A client that predates this page and shows review forms (Apple 1.0) remains conforming. Both kinds of client sync together; see [Mixed clients](#mixed-clients).
- A client that implements this page implements all of the rules marked in effect below, and nothing less. A rule applied differently makes devices disagree about which records exist.
- Titles and notes are catalog text. Clients never parse them, and the rules below decide sameness by identity and content, never by wording.

**Status of this revision.** Rows 1, 2, 4, 5, 6 and 7 are in effect: journals, permanent deletions, and versions with the same content. A client that settles these and still shows its review for **entries and templates whose content differs (row 3)** conforms to this revision; row 3, with copies and their replacement, is added to this version before it ships beyond testing, with its fixtures. The identity construction for copies is already fixed here because parked entries use it.

## Words

- **L** is the version this device holds as the record: unsent, or just saved. **R** is the other version: the latest the server holds, or, when a save found a stored version it had not seen, that one. Only the latest R per record is used in a round; earlier ones go to the record's history.
- **Marker** is a canonical permanent-deletion marker ([permanent-deletion.md](permanent-deletion.md)).
- **Last** and **first** are the order in which the server accepted the versions, never a clock. The version that reached the server last stays the record; it is not "newest": a device offline for a week gives its stale text the record.
- **Parked**: saved as a new entry or template in Recently Deleted next to a permanent deletion.

## The rules

Given L and R of one record, the first row that matches decides. The function takes the two decoded versions and, for identities, their exact plaintext ([Identities](#identities)). It reads no clock and no database.

| # | Situation | Record | Other version | Note for the person |
| --- | --- | --- | --- | --- |
| 1 | Either version is not editable by this client, or carries content from a newer client | **Held** | none | held |
| 2 | Neither is a marker and the content is the same ([Same content](#same-content)) | L's content with the merged deletion state ([Deletion state](#deletion-state)); when that equals R in every field but the modified time, R's bytes are adopted and the record is clean (nothing is sent) | none | none |
| 3 | An entry or template, content differs, neither is a marker | not in effect: the client keeps both versions for review, as before | | |
| 4 | An entry or template against a marker | **The marker** (final) | The edited version, **parked** ([Parking](#parking)) | edited and deleted |
| 5 | Two markers | R's marker; this device's marker is dropped | none | none |
| 6 | A journal, content differs, neither is a marker | L, with the merged deletion state; R is kept in the record's history | none | renamed, when the names differ |
| 7 | A journal against a marker | **The marker** (final) | none: a journal copy would not carry its entries | deleted |

Row 2 is for two versions that both have content. A marker is only ever the record (rows 4, 5 and 7), so a live entry whose fields happen to equal a marker's is not "the same".

**Held (row 1).** A client must not save over a record it cannot fully read ([records.md](records.md#reading-rules)). The conflict stays, the record stays unsent and nothing is created. At every resolution point the held conflicts are tried again, so they settle once both versions can be read. The person is told that a newer version of the app is needed, without a form.

### Same content

A false "same" would lose an edit silently and a false "different" only keeps another version, so equality is strict and field by field. Two versions have the same content when all of these are equal:

- **entries:** `title`, `document`, `date`, `journalID`, `archivedAt`;
- **templates:** `title`, `document`, `date`, `archivedAt`;
- **journals:** `title`, `defaultTemplateID`.

`document` is compared as a JSON value, so it covers the Markdown text and the whole of `metadata` (`blockIDs`, `segmentLengths`, `imageTypes`) of a version 2 document, and the blocks of a version 1 document: objects are unordered, arrays ordered, strings compared by code points, and a member that is absent is not equal to one that is present. `title` is compared the same way, so a composed and a decomposed é are different titles and nothing is normalized first. A version that differs only in `blockIDs`, `segmentLengths` or `imageTypes` is therefore different. Dates are compared as instants at whole-second resolution, rounded down.

`modifiedAt` and `restoredFromDeletionID` are not content (the first is informational, the second is marker bookkeeping), and neither is `deletedAt` or `deletedWithJournal`, which are the deletion state. Unknown members are not compared, because a version that has any is held. Comparison is of decoded values, never bytes: another device seals the same content differently, and writes members in another order.

### Deletion state

`(deletedAt, deletedWithJournal)` is one unit, and no clock chooses it:

- When only one version has a `deletedAt`, that version's pair is taken.
- When both have one, the pair with `deletedWithJournal` true if either has it, else R's pair.
- When neither has one, the pair is none.

`deletedWithJournal` is only set by writers before 1.0; current writers delete a journal by its own `deletedAt` and its entries follow by inheritance ([journal-lifecycle.md](journal-lifecycle.md)). The clause matters for legacy entries only. A deletion against a restoration therefore stays deleted: it is in Recently Deleted, one Restore from being back.

### Parking

Someone used Delete Permanently on one device while the item was edited on another. The deletion stays final and the edit is not discarded:

- The marker is the record on every device, exactly as a deletion with no conflict, and the record's earlier versions are removed whichever device's marker it is, including any a pull set aside meanwhile. Markers are never revived and no `restoredFromDeletionID` is written.
- The edited version is saved as a **new** entry or template: the identity is derived from the edited version ([Identities](#identities), label `conflict-park`); title, document, date, journal and `archivedAt` are the edited version's, unchanged; `modifiedAt` is the edited version's; `deletedAt` is the marker's `permanentlyDeletedAt`, the same on every device; `deletedWithJournal` is false; `restoredFromDeletionID` is absent. It is created at revision 0 like any new record.
- It is in Recently Deleted when its journal is in use. When its journal is gone, deleted permanently, or never arrived, it is under Unavailable Journals, and Restore brings it back into the Default Journal ([journal-lifecycle.md](journal-lifecycle.md)).
- A parked entry this device made and has not sent is replaced by a version of the same identity that arrives first, and dropped when it meets a marker (its content is in the other record), only while its plaintext still has the digest this device recorded. One the person edited since is kept by the ordinary rules: it is neither replaced nor dropped, and against a marker it is parked again from its edited text.
- Its images are the edited version's attachment ids; no bytes are copied. A second Delete Permanently on it is an ordinary marker.
- A journal against a marker (row 7) creates nothing: a journal holds a name and a deletion state, no writing. Entries edited elsewhere in that journal are separate records with their own conflicts and are parked as above, keeping the old `journalID`.

Why this shape: markers stay immutable tombstones, a client that predates this page receives only an ordinary new entry, and a second device that finds the same conflict derives the same record and does nothing.

### Journals

| Versions | Result |
| --- | --- |
| Renamed on two devices | L's name stays; R's name is kept in a note and R is kept in the record's history. The name that lost has no trail on the device that wrote it |
| Renamed on one, deleted on the other | Deleted, with L's name |
| Restored on one, renamed on the other | Deleted if either is deleted |
| Equal names, different `defaultTemplateID` | L's template, without a note |
| A name another journal now has | The [name rule](journal-lifecycle.md#journal-names) numbers the later journal, as an ordinary change and never a conflict |

`defaultTemplateID` is preserved and compared, though no screen shows it ([records.md](records.md#writing-a-journal-back)).

## Identities

A parked entry, and in a later revision a copy, has an identity that every device derives alike, so the same record is made once however many devices find the conflict. Let `text` be the exact plaintext UTF-8 text of the version being saved, as this device holds it (for R as received and decrypted; for a library without encryption the decoded payload). Let `label` be `conflict-park` for a parked entry and `conflict-copy` for a copy of the other version, so one version never gets the same identity for both.

1. `K` = HKDF-SHA-256 with an empty salt, the 32-byte vault key as input key material, info = the UTF-8 bytes of `journal:v1:conflict-copy-id` and 32 bytes of output. In a library without encryption there is no vault key: `K` = SHA-256 of that same info string (public by design; the server reads that library anyway).
2. `tag` = HMAC-SHA-256(`K`, UTF-8(`label` + LF + the record's lower-case hyphenated id + LF + the lower-case hex SHA-256 of `text`)). The record id is the conflicted record's, not the saved version's.
3. `b` = the first 16 bytes of `tag`. Set `b[6] = (b[6] & 0x0F) | 0x80` and `b[8] = (b[8] & 0x3F) | 0x80`.
4. The identity is the 32 lower-case hex digits of `b`, in that order, hyphenated 8-4-4-4-12. A .NET `Guid` built from these 16 bytes is mixed-endian: build the string from the bytes, not the `Guid`. Writers write it as they write any UUID; readers compare UUIDs case-insensitively and **must not validate version or variant bits** (these identities have version nibble 8; [Known issues](conformance/README.md#known-issues) already says so for derived block identities).

The keyed derivation hides the link between a parked entry and its source from a server, which sees record ids, kinds, times and the new id. What it can still see is that a record appeared at revision 0 right after a pull of the same record; [SECURITY.md](../SECURITY.md#what-the-server-can-see) lists it. Identities derived before encryption is turned on differ from those derived after, because the vault key is new; that transition is rare.

**A derived identity that already exists, in any state, means nothing is done.** If a record with the derived id exists locally, whatever its state (arrived from another device before this device settled, edited, deleted or permanently deleted since, or made earlier here), nothing is written, noted, revived or duplicated; the existing record is the parked entry. The record side of the settlement still proceeds.

**A parked entry that this device made and has not sent is replaced by an arriving version of the same record**, without a further entry: two clients may write the same entry with different bytes, and the one that reached the server first wins. If what arrives is a marker (another device deleted it for good first), the marker wins as well: **a parked entry never revives a marker**, and the local one is dropped, because its content is still in the other record.

## When it runs

1. **Working set.** A conflict is recorded where it is today ([README](README.md#sync-and-conflicts)): a pulled change for a record with unsent changes, a push refused with `revision_conflict`, a save over a stored version that changed, a restored or replaced server, an import. One row per record, replaced only by a higher revision, the replaced R going to history. While a conflict exists the record is not sent.
2. **Resolution points.** A client settles its conflicts: at the end of every completed pull, however many pages it took (the last page read and the position committed), also when a push failed for an unrelated record; when a library is opened, but only for conflicts an earlier version left and for those from an import, and for any conflict when no server is configured; after a local merge or import; and after a stale save when no server is configured.
3. **Never** while a reconciliation is in progress (its revisions and other versions are not final until the whole log is compared), for a record the person is writing, or for a held conflict.
4. **One transaction per record**: re-read the conflict and the record, compute the outcome, write the record (its revision becomes R's, it is queued on that revision, or R's bytes are adopted clean), remember R as the server's version at that revision, make the parked entry and note it, delete the conflict. If anything fails nothing is half done, the conflict stays and the next point repeats it; a conflict that fails, or whose versions cannot be opened, is counted with the held ones and never stops the others.
5. **Bound.** At most one settlement per record per round, so at most one parked entry per record per round. After settling, the round sends what it queued, so the person waits no extra interval.

## The pass over conflicts an earlier version left

A library that an earlier version left with conflicts is settled when this version first opens it, before any synchronization can start, so a pull cannot replace a conflict's R first. The pass takes only conflicts that existed before this client first opened the library (the sealed local setting records, once, which conflicts those are and when the pass has finished) and those from imports (revision 0), because their R is what the person last saw. It does not run during a reconciliation. A conflict made by this client and left by a crash in the middle of a paged catch-up is not settled at opening, since its R may be an intermediate revision; it waits for the next completed pull.

Rows are handled one at a time, each in its own transaction, by the same rules. A conflict whose record has already passed R's revision is out of date: R goes to the record's history and the conflict ends, unless R is a marker (nothing to keep) or a version this client cannot read (the conflict stays held). A conflict that fails, or that the caller is holding because the person's save of that record has failed, stays on the recorded list for the next call; the pass has finished when the list is empty, and conflicts made later are never added to it. This changes what an earlier version left pending only by answering it: both versions are kept, or, for a pending deletion, the deletion is kept and the edit parked. The first revision of this page settles journals and conflicts that involve a marker; the remaining kinds join it when row 3 does.

## What stays on the device

A client keeps, for the person only, a short list of what it settled (journal rename, edit against a permanent deletion, journal against a permanent deletion) for 30 days, journal rename notes until the person clears the list, and a record of the parked entries it made (their ids, the record, the origin device and revision of R, and the digest of the plaintext written). None of it is a synchronized record. The Apple client keeps both in one sealed settings key, `kept-notes`, which readers of an archive ignore if they do not know it ([archive.md](archive.md)). Notes are built from current titles at display time.

## Mixed clients

| Situation | Result |
| --- | --- |
| A client with this page settles; a client without it receives | It receives an ordinary revision, and the parked entry as an ordinary new entry. A client with its own unsent edit of that record shows its own review, with the settled version as the other device's |
| A permanent deletion against an edit, one client of each kind | The marker stays. A client without this page that restores the edited entry under the marker's identity sends an ordinary restoration ([permanent-deletion.md](permanent-deletion.md)); clients with this page apply it as they apply any change, and the parked entry stays as a separate entry |
| Both kinds of client find the same conflict | At worst two records for one edit, once. Nothing is lost on either side |

## Fixtures

New files under [conformance/](conformance/README.md); no existing file changes:

| File | Covers |
| --- | --- |
| [records/conflict-resolution-v1.json](conformance/records/README.md#settling-conflicts) | Cases for rows 1 to 7 with the exact plaintext of L and R and the outcome: strict equality (including metadata only), the deletion state as one unit, restore against delete, parked entries (identity, fields, an untitled entry), two markers, a journal against a marker |
| [records/conflict-copy-ids-v1.json](conformance/records/README.md#settling-conflicts) | The derivation key, the HMAC message, the tag and the final hyphenated identities, for libraries with and without encryption |
| [sync/conflict-scenarios-v1.json](conformance/sync/README.md#conflict-scenarios) | Devices changing the same records offline and what every device holds at the end, with page boundaries and a device that only receives |
| [records/journal-rewrite-v1.json](conformance/records/README.md#journal-rewrite) | A journal with a `defaultTemplateID` after a rename, a deletion and a restoration |

Apple's `Conformance*` tests read the records files; `ConflictScenarioTests` replays the scenarios against real stores. The server never interprets payloads and replays none of the scenarios, but its tests derive the identities again from this page alone (`ConflictIdentityConformanceTests`, in .NET), which is what a Windows client will do.
