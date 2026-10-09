# Settling conflicts (conflicts v1)

When two devices change one record, each keeps its own version until they meet at the server ([Sync and conflicts](README.md#sync-and-conflicts)). A client that implements this page settles what it can without asking: it keeps both versions' content, readable, and tells the person afterwards. The design is in [docs/design/1-1-conflicts-and-reconnect.md](../docs/design/1-1-conflicts-and-reconnect.md).

The page has its own version, **conflicts v1**, because it is a client contract and changes no wire format: no endpoint, capability, record field, archive table or server release is involved, and the server never learns that a conflict happened. `/v1` and every existing fixture stay valid.

- A client that predates this page and shows review forms (Apple 1.0) remains conforming. Both kinds of client sync together; see [Mixed clients](#mixed-clients).
- A client that implements this page implements all of the rules marked in effect below, and nothing less. A rule applied differently makes devices disagree about which records exist.
- Titles and notes are catalog text. Clients never parse them, and the rules below decide sameness by identity and content, never by wording.

**Status of this revision.** All seven rows are in effect. Row 3 (entries and templates whose content differs) was added to this version before it shipped beyond testing, with copies, their replacement and their fixtures; a client that settles rows 1, 2 and 4 to 7 and still shows a review for row 3 does not implement this page.

## Words

- **L** is the version this device holds as the record: unsent, or just saved. **R** is the other version: the latest the server holds, or, when a save found a stored version it had not seen, that one. Only the latest R per record is used in a round; earlier ones go to the record's history.
- **Marker** is a canonical permanent-deletion marker ([permanent-deletion.md](permanent-deletion.md)).
- **Last** and **first** are the order in which the server accepted the versions, never a clock. The version that reached the server last stays the record; it is not "newest": a device offline for a week gives its stale text the record.
- **Copy**: the other version of an entry or template that differs, saved as a separate entry or template ([Copies](#copies)).
- **Parked**: saved as a new entry or template in Recently Deleted next to a permanent deletion.

## The rules

Given L and R of one record, the first row that matches decides. The function takes the two decoded versions and, for identities, their exact plaintext ([Identities](#identities)). It reads no clock and no database.

| # | Situation | Record | Other version | Note for the person |
| --- | --- | --- | --- | --- |
| 1 | Either version is not editable by this client, or carries content from a newer client | **Held** | none | held |
| 2 | Neither is a marker and the content is the same ([Same content](#same-content)) | L's content with the merged deletion state ([Deletion state](#deletion-state)); when that equals R in every field but the modified time, R's bytes are adopted and the record is clean (nothing is sent) | none | none |
| 3 | An entry or template, content differs, neither is a marker | L, unchanged: the same bytes | A **copy** of R ([Copies](#copies)) | kept both |
| 4 | An entry or template against a marker | **The marker** (final) | The edited version, **parked** ([Parking](#parking)) | edited and deleted |
| 5 | Two markers | R's marker; this device's marker is dropped | none | none |
| 6 | A journal, content differs, neither is a marker | L, with the merged deletion state; R is kept in the record's history | none | renamed, when the names differ |
| 7 | A journal against a marker | **The marker** (final) | none: a journal copy would not carry its entries | deleted |

Row 2 is for two versions that both have content. A marker is only ever the record (rows 4, 5 and 7), so a live entry whose fields happen to equal a marker's is not "the same".

**Moves, archiving and date changes.** Moving an entry to another journal, archiving or unarchiving it and changing its date are edits of `journalID`, `archivedAt` and `date`, which are part of the content ([Same content](#same-content)). One of them on one device against an edit of the text on another is therefore a row 3 conflict: the person gets an "(other version)" although only a field differs. This is as specified, and no client merges the fields.

**Held (row 1).** A client must not save over a record it cannot fully read ([records.md](records.md#reading-rules)). The conflict stays, the record stays unsent and nothing is created. At every resolution point the held conflicts are tried again, so they settle once both versions can be read. The person is told that a newer version of the app is needed, without a form.

### Same content

A false "same" would lose an edit silently and a false "different" only keeps another version, so equality is strict and field by field. Two versions have the same content when all of these are equal:

- **entries:** `title`, `document`, `date`, `journalID`, `archivedAt`;
- **templates:** `title`, `document`, `date`, `archivedAt`;
- **journals:** `title`, `defaultTemplateID`.

`document` is compared as a JSON value, so it covers the Markdown text and the whole of `metadata` (`blockIDs`, `segmentLengths`, `imageTypes`) of a version 2 document, and the blocks of a version 1 document: objects are unordered, arrays ordered, strings and member names compared by code points, and a member that is absent is not equal to one that is present. Values of different JSON types are different, which includes `true` and `1`, and an integer (written without a fraction or an exponent) and a number written with one: `1` and `1.0` are different. Numbers of the same kind are equal when their values are. `title` is compared the same way, so a composed and a decomposed é are different titles and nothing is normalized first. A version that differs only in `blockIDs`, `segmentLengths` or `imageTypes` is therefore different. Dates are compared as instants at whole-second resolution, rounded down.

`modifiedAt` and `restoredFromDeletionID` are not content (the first is informational, the second is marker bookkeeping), and neither is `deletedAt` or `deletedWithJournal`, which are the deletion state. Unknown members are not compared, because a version that has any is held. Comparison is of decoded values, never bytes: another device seals the same content differently, and writes members in another order.

### Deletion state

`(deletedAt, deletedWithJournal)` is one unit, and no clock chooses it:

- When only one version has a `deletedAt`, that version's pair is taken.
- When both have one, the pair with `deletedWithJournal` true if either has it, else R's pair.
- When neither has one, the pair is none.

`deletedWithJournal` is only set by writers before 1.0; current writers delete a journal by its own `deletedAt` and its entries follow by inheritance ([journal-lifecycle.md](journal-lifecycle.md)). The clause matters for legacy entries only. A deletion against a restoration therefore stays deleted: it is in Recently Deleted, one Restore from being back.

### Copies

Row 3 keeps this device's version as the record, byte for byte, so an editor that has it open sees nothing. The other version becomes a separate entry or template:

| Field | Value |
| --- | --- |
| Identity | Derived ([Identities](#identities), label `conflict-copy`, from R's exact text) |
| Title | `messages.conflict.copyTitle`: "{title} (other version)", where {title} is R's title or, when that is empty or has only White_Space characters (the Unicode property: spaces, tabs, line breaks and the like), the title the lists show for it: the first line of its text that is not empty (lines end at LF) cut at 60 extended grapheme clusters, or, when that line has only White_Space characters or the text has none, the catalog's name for an untitled entry or template. Always appended and never detected: a copy of a copy reads "X (other version) (other version)". The body is never touched |
| Document | R's, unchanged, with its images, image descriptions, links and block identities |
| Date, journal, `archivedAt` | R's: each version keeps its date and place |
| Deletion state | R's: a version that was in Recently Deleted is a copy in Recently Deleted |
| Modified time | R's: nothing reads a clock |
| `restoredFromDeletionID` | absent: it is bookkeeping of the record, not of a version |
| Images | The same attachment identities; no bytes are copied |

On the record's side nothing is stamped: its bytes stay, its revision becomes R's, it stays unsent and is queued on that revision (or R's bytes are adopted when the content is the same, row 2).

**A copy that exists, a copy to replace, a copy to make.** The device records, for each copy and parked entry it made, the copy's identity, the record, the device R came from, R's revision and the digest of the plaintext it wrote, whether it is a copy or a parked entry, and whether a later version has replaced the content first written. Only a copy is ever replaced, never a parked entry. When row 3 wants to make a copy it decides in this order:

1. **A record with the derived identity exists locally, in any state: do nothing.** No write, no note, no new copy. The existing record is the copy: it arrived from another device before this device settled (a page can end between the copy and the record's new revision), or it was edited, deleted or deleted permanently elsewhere, or this device made it earlier. Nothing is revived, overwritten or duplicated. The record's side of the settlement still proceeds.
2. **Otherwise replace the latest earlier copy** of the same record if **all** hold: R came from the same device as the copy's recorded origin and has a higher revision (it descends from that version), and the origin device is known (a version kept by a save on this device does not record its device, which is nil; a nil or unknown device never matches, so such a copy is never replaced and two different devices' copies are never replaced into each other); the copy's stored plaintext has exactly the recorded digest, so nobody, here or elsewhere, has changed it (a change from elsewhere would have been pulled and would differ; a deletion, a move or an edit differs too); no conflict waits on it; nothing queued for it differs from it; and it is not being written. The later content goes under the copy's identity (its title, document and the rest are R's), what it replaces goes to the copy's Version History, the record of what was written is updated, and an unsent copy's queued change is replaced; a sent copy's change is queued on the revision it has. If another device changed the copy and this device has not pulled that yet, the push gets a conflict of its own, which keeps both.
3. **Otherwise make the copy** with the derived identity, at revision 0, and record it.

A copy this device made and has not sent is replaced, without a further copy, by a version of the same identity that arrives first, and dropped when what arrives is a permanent deletion: an automatic copy never revives a marker. Both only while it holds the content this device first wrote: its plaintext still has the digest the device recorded **and** no later version has replaced it. One the person edited since, and one that a later version of the other device replaced (it holds that version's content, which exists nowhere else), go through the ordinary rules: against a version of the same identity both are kept, and against a marker the replaced content is parked.

**The one extra copy.** A replaced copy keeps the identity of the version that first made it, but a device that meets the replacing version without having made the earlier copy derives an identity from its text. If two devices meet the same R while one of them replaces an earlier copy, that content exists twice, once under each identity. The bound is exactly one extra copy of identical content per replacement, and nothing is lost. A client must not try to remove it.

**Bound.** Two devices typing in one entry: while a device types, its record is being written and is not settled; when it pauses, its round pulls the other device's latest version, makes or replaces one copy and sends. Each copy is the other's latest version. After any number of alternating pauses each device has at most one copy of the other, not one per exchange ([sync/conflict-scenarios-v1.json](conformance/sync/README.md#conflict-scenarios) alternates edits for 20 rounds).

**Three devices.** A, B and C hold an entry; each writes offline, and they reach the server in the order A, B, C. B's push is refused over A's version, so B settles with R = A's: B's text stays and A's is a copy. C's is refused over B's: C's text stays and B's is a copy. Every text exists once on every device. The invariant: the device that overwrites a server version it had not seen copies it, so no version needs a copy from a device that never saw it.

### Parking

Someone used Delete Permanently on one device while the item was edited on another. The deletion stays final and the edit is not discarded:

- The marker is the record on every device, exactly as a deletion with no conflict, and the record's earlier versions are removed whichever device's marker it is, including any a pull set aside meanwhile. Markers are never revived and no `restoredFromDeletionID` is written.
- The edited version is saved as a **new** entry or template: the identity is derived from the edited version ([Identities](#identities), label `conflict-park`); title, document, date, journal and `archivedAt` are the edited version's, unchanged; `modifiedAt` is the edited version's; `deletedAt` is the marker's `permanentlyDeletedAt`, the same on every device; `deletedWithJournal` is false; `restoredFromDeletionID` is absent. It is created at revision 0 like any new record.
- It is in Recently Deleted when its journal is in use. When its journal is gone, deleted permanently, or never arrived, it is under Unavailable Journals, and Restore brings it back into the Default Journal ([journal-lifecycle.md](journal-lifecycle.md)).
- A parked entry this device made and has not sent is replaced by a version of the same identity that arrives first, and dropped when it meets a marker (its content is in the other record), only while its plaintext still has the digest this device recorded. One the person edited since is kept by the ordinary rules: it is neither replaced nor dropped, and against a marker it is parked again from its edited text. A parked entry is never replaced by a later version of the record it came from: that rule is for copies.
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

A copy and a parked entry have an identity that every device derives alike, so the same record is made once however many devices find the conflict (apart from the extra copy a replacement can leave, [Copies](#copies)). Let `text` be the exact plaintext UTF-8 text of the version being saved, as this device holds it (for R as received and decrypted; for a library without encryption the decoded payload). Let `label` be `conflict-park` for a parked entry and `conflict-copy` for a copy of the other version, so one version never gets the same identity for both.

1. `K` = HKDF-SHA-256 with an empty salt, the 32-byte vault key as input key material, info = the UTF-8 bytes of `journal:v1:conflict-copy-id` and 32 bytes of output. In a library without encryption there is no vault key: `K` = SHA-256 of that same info string (public by design; the server reads that library anyway).
2. `tag` = HMAC-SHA-256(`K`, UTF-8(`label` + LF + the record's lower-case hyphenated id + LF + the lower-case hex SHA-256 of `text`)). The record id is the conflicted record's, not the saved version's.
3. `b` = the first 16 bytes of `tag`. Set `b[6] = (b[6] & 0x0F) | 0x80` and `b[8] = (b[8] & 0x3F) | 0x80`.
4. The identity is the 32 lower-case hex digits of `b`, in that order, hyphenated 8-4-4-4-12. A .NET `Guid` built from these 16 bytes is mixed-endian: build the string from the bytes, not the `Guid`. Writers write it as they write any UUID; readers compare UUIDs case-insensitively and **must not validate version or variant bits** (these identities have version nibble 8; [Known issues](conformance/README.md#known-issues) already says so for derived block identities).

The keyed derivation hides the link between a parked entry and its source from a server, which sees record ids, kinds, times and the new id. What it can still see is that a record appeared at revision 0 right after a pull of the same record; [SECURITY.md](../SECURITY.md#what-the-server-can-see) lists it. Identities derived before encryption is turned on differ from those derived after, because the vault key is new; that transition is rare.

**A derived identity that already exists, in any state, means nothing is done.** If a record with the derived id exists locally, whatever its state (arrived from another device before this device settled, edited, deleted or permanently deleted since, or made earlier here), nothing is written, noted, revived or duplicated; the existing record is the parked entry or the copy. The record side of the settlement still proceeds.

**A parked entry or copy that this device made and has not sent, and that still holds the content it first wrote, is replaced by an arriving version of the same record**, without a further entry: two clients may write the same entry with different bytes (other wording of the title, another key order), and the one that reached the server first wins. If what arrives is a marker (another device deleted it for good first), the marker wins as well: **a parked entry or copy never revives a marker**, and the local one is dropped, because its content is still in the other record.

## When it runs

1. **Working set.** A conflict is recorded where it is today ([README](README.md#sync-and-conflicts)): a pulled change for a record with unsent changes, a push refused with `revision_conflict`, a save over a stored version that changed, a restored or replaced server, an import. One row per record, replaced only by a higher revision, the replaced R going to history. While a conflict exists the record is not sent.
2. **Resolution points.** A client settles its conflicts: at the end of every completed pull, however many pages it took (the last page read and the position committed), also when a push failed for an unrelated record; when a library is opened, but only for conflicts an earlier version left and for those from an import, and for any conflict when no server is configured; after a local merge or import; and, whether or not a server is configured, once writing pauses after a stale save, for the conflict that save made. That conflict's other version is one this device already holds (a version kept by the save, with no device, at the revision the record has), so no pull can add to it and an unreachable server doesn't keep it waiting. A conflict that came from a pull waits for the end of a completed pull.
3. **Never** while a reconciliation is in progress (its revisions and other versions are not final until the whole log is compared), for a record the person is writing, or for a held conflict.
4. **One transaction per record**: re-read the conflict and the record, compute the outcome, write the record (its revision becomes R's, it is queued on that revision, or R's bytes are adopted clean), remember R as the server's version at that revision, make or replace the copy, or make the parked entry, and note it, delete the conflict. If anything fails nothing is half done, the conflict stays and the next point repeats it; a conflict that fails, or whose versions cannot be opened, is counted with the held ones and never stops the others.
5. **Bound.** At most one settlement per record per round, so at most one copy or parked entry per record per round. After settling, the round sends what it queued, so the person waits no extra interval.

## The pass over conflicts an earlier version left

A library that an earlier version left with conflicts, including the entries and templates a person left in 1.0's review, is settled when this version first opens it, before any synchronization can start, so a pull cannot replace a conflict's R first. The pass takes only conflicts that existed before this client first opened the library (the sealed local setting records, once, which conflicts those are and when the pass has finished) and those from imports (revision 0), because their R is what the person last saw. It does not run during a reconciliation. A conflict made by this client and left by a crash in the middle of a paged catch-up is not settled at opening, since its R may be an intermediate revision; it waits for the next completed pull. The pass is recorded even when it finds no conflicts, as soon as the library has been opened and read once (a client does not write to a library it cannot read), so a conflict made after that is never taken for one an earlier version left; the same holds for the second step, which a library that has run the first step runs at its next opening and which takes the conflicts present then, whoever made them.

Rows are handled one at a time, each in its own transaction, by the same rules. A conflict whose record has already passed R's revision is out of date: R goes to the record's history and the conflict ends, unless R is a marker (nothing to keep) or a version this client cannot read (the conflict stays held). A conflict that fails, or that the caller is holding because the person's save of that record has failed, stays on the recorded list for the next call; the pass has finished when the list is empty, and conflicts made later are never added to it. This changes what an earlier version left pending only by answering it: both versions are kept, or, for a pending deletion, the deletion is kept and the edit parked. The pass is recorded in two steps in the sealed local setting: journals and permanent deletions first, then every other kind, so a library that finished the first step settles its entries and templates the next time it opens.

## What stays on the device

A client keeps, for the person only, a short list of what it settled (an entry or template kept as two, a journal rename, an edit against a permanent deletion, a journal against a permanent deletion) for 30 days, journal rename notes until the person clears the list, and a record of the copies and parked entries it made (their ids, whether each is a copy or a parked entry, the record, the origin device and revision of R, the digest of the plaintext written and whether a later version has replaced the first content). A replaced copy updates its note instead of adding another. The record keeps the last 200 and forgets the oldest: a copy it no longer knows is neither replaced nor dropped, and a conflict on it is settled by the ordinary rules, which keep both versions. Whether the other version was modified later than this device's, by the clocks of the two devices, chooses the wording of the note ("that version is newer") and nothing else. None of it is a synchronized record. The Apple client keeps both in one sealed settings key, `kept-notes`, which readers of an archive ignore if they do not know it ([archive.md](archive.md)). Notes are built from current titles at display time.

## Mixed clients

| Situation | Result |
| --- | --- |
| A client with this page settles; a client without it receives | It receives an ordinary revision, and the copy or the parked entry as an ordinary new entry. A client with its own unsent edit of that record shows its own review, with the settled version as the other device's |
| A permanent deletion against an edit, one client of each kind | The marker stays. A client without this page that restores the edited entry under the marker's identity sends an ordinary restoration ([permanent-deletion.md](permanent-deletion.md)); clients with this page apply it as they apply any change, and the parked entry stays as a separate entry |
| Both kinds of client find the same conflict | At worst two records for one edit, once: a copy with a random identity and the title as it was, and one with the derived identity. Nothing is lost on either side |

## Fixtures

New files under [conformance/](conformance/README.md); no existing file changes:

| File | Covers |
| --- | --- |
| [records/conflict-resolution-v1.json](conformance/records/README.md#settling-conflicts) | Cases for rows 1 to 7 with the exact plaintext of L and R and the outcome: strict equality (including metadata only), the deletion state as one unit, restore against delete, copies (identity, fields, the title rule for an untitled version, a cut first line, a title that already ends in the suffix, a copy in Recently Deleted, an image), parked entries, two markers, a journal against a marker |
| [records/conflict-copy-ids-v1.json](conformance/records/README.md#settling-conflicts) | The derivation key, the HMAC message, the tag and the final hyphenated identities, for libraries with and without encryption |
| [sync/conflict-scenarios-v1.json](conformance/sync/README.md#conflict-scenarios) | Devices changing the same records offline and what every device holds at the end: three devices in two orders and across page boundaries, several versions arriving while one is unsent, twenty rounds of typing in one entry, a restored server, edits against permanent deletions, with page boundaries and a device that only receives |
| [records/journal-rewrite-v1.json](conformance/records/README.md#journal-rewrite) | A journal with a `defaultTemplateID` after a rename, a deletion and a restoration |

Apple's `Conformance*` tests read the records files; `ConflictScenarioTests` replays the scenarios against real stores. The server never interprets payloads and replays none of the scenarios, but its tests derive the identities again from this page alone, including the ones the resolution cases expect (`ConflictIdentityConformanceTests`, in .NET), which is what a Windows client will do.
