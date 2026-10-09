# 1.1: conflicts keep both versions, and one Reconnect action (simplifications H and I)

Status: **design proposal, revision 2 (2026-10-09), revised after the independent review that follows the body of this record; to be re-reviewed before implementation.** Step 1 of the mandatory design gate in [AGENTS.md](../../AGENTS.md): nothing implemented. Scope and owner approval of the simplifications: [release-1-1-scope.md](release-1-1-scope.md), rows H and I (approved 2026-10-07). What changed in this revision, finding by finding: "Changes after review" at the end.

Builds on: [sync-health-and-recovery.md](sync-health-and-recovery.md), [journal-conflicts.md](journal-conflicts.md), [permanent-deletion.md](permanent-deletion.md), [stale-conflict-recovery.md](stale-conflict-recovery.md), [protocol/README.md](../../protocol/README.md) (Sync and conflicts), [protocol/records.md](../../protocol/records.md) (The library record: the one place that already merges instead of reviewing), [protocol/permanent-deletion.md](../../protocol/permanent-deletion.md), [protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md) (Journal names: the precedent for a rule every client computes alike) and, for the archive, [protocol/archive.md](../../protocol/archive.md) with its 1.1 rewrite in [1-1-archive-v2.md](1-1-archive-v2.md) (owned by another author; this record only coordinates with it, section 5.2). Spec pages that change: section 9.

## 0. Summary

- **H.** Today a conflict becomes a row in a local table, stops that record from syncing, and waits for the person to open one of four review forms. In 1.1 the `conflicts` table stays as the working set, but the device resolves each row itself at a defined point (the end of a sync round, for a record that is not being written), keeps both versions, and tells the person quietly afterwards. No form asks "which one?".
- **The rule, in one sentence.** The version that reached the server last stays the record; the version that reached it first is kept as well: as a separate entry or template for text, as a name in a note for a journal, and, when someone deleted the item permanently, as a separate entry parked in Recently Deleted while the deletion stays final.
- **Bounded.** One resolution per record per round, using only the latest other version; earlier ones go to history as today. A copy is replaced by a later version from the same device only when nothing else has touched it, so two devices typing in one entry end with at most one copy per other device (plus, in one rare race, one identical extra), not a storm (section 3.8 has a worked three-device example). A derived id that already exists locally, in any state, means nothing is done (3.3.2).
- **Two steps, shippable on their own.** Step 1 removes the journal and deletion review forms and the Can't Be Deleted alert (6.1). Step 2 removes the entry and template review, the Changes to Review list, the notice and the list symbol (6.2). Each step lands its rules in `protocol/` with scripted conformance scenarios.
- **Discoverable, not loud.** A copy is an ordinary entry whose title ends in "(other version)" (a requirement, not a choice: otherwise other devices, and 1.0, show indistinguishable duplicates). The device that resolved shows a dismissible notice; Settings ▸ Sync gets a list "Changed on Two Devices" (30 days, clearable) whose rows open the item.
- **Compatible.** No endpoint, capability, record field, wire format, database table or archive-format change. The server and 1.0 devices see ordinary records and never a restoration or marker change. The notes live in one sealed settings key, like `library-changes`. The rules, the identity derivation and the multi-device orchestration are written as a new client contract (`protocol/conflicts.md`, version 1) with scripted scenarios, so Windows and Android build the final behaviour and never the forms.
- **I.** One action, **Reconnect…** (`common.reconnect`), replaces Set Up Server Again…, Connect Again… and Sign In… everywhere. The flow behind it already decides by what the server says. State messages stay, except where they named the old verbs or a path simplification E removes.
- **Genuine owner decision:** one, in section 12, with a recommendation. When step 2 ships is decided by its gates (6.2).

## 1. Constraints this design keeps

1. **Version 1.0 (build 19) is in App Review and will be public before 1.1 ships.** 1.1 never discards, rewrites or silently changes anything 1.0 wrote. 1.0 and 1.1 devices on one server keep syncing, whichever resolves a conflict first.
2. **AGENTS.md: "Never silently discard content or overwrite conflicting edits."** Every automatic outcome keeps both versions' content readable by the person: as an entry, in Recently Deleted or Unavailable Journals, or, for a journal name only, in a note that the sealed settings key holds for 30 days.
3. **No clocks decide.** Device clocks never order revisions ([records.md](../../protocol/records.md)). "Last" means the order the server accepted the versions, the library record's rule ("the change synced last wins"). Modified times are shown as a hint only (4.2) and never choose a result or limit a rule.
4. **Every device must reach the same result without talking to the others.** Two parts, both specified for other clients to implement: a pure function from the two decoded versions to the outcome (3.2), and the orchestration around it: when it runs, which revision is used, how a copy that exists is recognised, how markers interact (3.8). Neither uses time.
5. **The editor must not feel it.** Resolving never runs for a record that is being written. Row 3 does not change the bytes of the version the person has open. Rows 2 and 4 to 7 can change the open record (it becomes deleted, or a marker); for row 4 the open editor is moved to the parked entry without losing the text or the cursor (3.4), so typing continues into one entry.
6. **Local-first and offline.** Resolution happens when versions meet and needs no server round trip of its own.
7. **No new database object.** 1.0 refuses an archive whose database has schema objects its migrations don't create ([protocol/archive.md](../../protocol/archive.md)). The existing `conflicts` table and one new sealed key in `settings` (readers ignore keys they don't know) are all that is stored.

## 2. Current behaviour (what H replaces)

All paths are under `apps/apple/` unless they start with `spec/` or `protocol/`.

**How a conflict exists.** A local table `conflicts` (one row per record: the other version's payload, the server revision, the device id, a time; `Packages/JournalCore/Sources/JournalCore/Store.swift:130`) is filled by:

- `JournalStore.apply` (`Store.swift:572`, the branch at `:602`): a change arrives for a record that is dirty here, or already has a row, or that is a permanent-deletion marker being replaced by live content. Also `recordConflict(_ change:)` (`:555`) after the server refused a push with `revision_conflict`.
- `keepChangedVersion` (`Store.swift:468`): this device saves over a version that changed since the saved copy was read (typing over a change that had not been shown; `StaleDraftTests`, `StaleSaveTests`).
- `keepOtherVersion` (`StoreServerVersions.swift:88`): the server holds another version at a revision this device has (server data rolled back).
- Reconciliation after a server restore or a join by identity (`SyncReconciliation.swift:154,181`) and merging libraries or importing an archive (`StoreMerge.swift:170,241`, `Store.swift:796`).

While a row exists the record is edited locally but **not sent** (`Store.pending()` joins `conflicts`, `Store.swift:492`), a journal is unavailable (its entries move to Unavailable Journals, `JournalLifecycle.swift`), and Rename, Default Template, Merge Into… and Delete are dimmed or refused.

**How the person resolves it** (`ConflictReview`, `Views/ConflictRouting.swift`; [spec/screens/conflict-review.md](../../spec/screens/conflict-review.md), [spec/flows/resolve-conflict.md](../../spec/flows/resolve-conflict.md)):

| Form | File | Choices |
| --- | --- | --- |
| Entry or template | `Views/EntryConflictReview.swift` | Keep Both, or keep one version (menu, confirmation, outcome sentences for place and date). `JournalStore.resolve` (`Store.swift:679`): both originals to Version History; this device's version stays the record; for Keep Both the other version becomes a new record with a fresh random id, queued at revision 0, stamped with the current time. |
| Journal | `Views/JournalConflictView.swift` | Keep Version… of name, default template and location. No Keep Both (a copy of a journal record would not copy or reparent its entries). |
| Deletion (a permanent-deletion marker against an edit, or two markers) | `Views/DeletionConflictView.swift`, `Views/PermanentDeletionView.swift` (`DeletionSheet`), `Model/PermanentDeletionOperations.swift`, `StoreDeletion.swift:80-190` | Keep Entry…, Keep Entry as Copy…, Keep Template, Keep Journal, or Keep Deletion… with a destructive second confirmation. |
| Unsupported (a version from a newer app) | the `DeletionSheet` in `ConflictRouting.swift` | Nothing can be resolved; Export Archive…. |

**Where it is signalled** (spec/screens/conflict-review.md, Entry points): the notice above the open entry (`ConflictNotice`, `Views/SettingsView.swift:237`, shown from `Views/RootView.swift:820,837`); an exclamation-mark symbol on the list row (`RootView.entryConflictIndicator`, `:560`); Settings ▸ Sync ▸ Changes to Review (`ConflictSettingsSection`); a journal's settings (unreachable since the Journals pane was removed, open question C2); a deleted journal (`Views/DeletedJournalView.swift`); the notice on entries of a journal with changes (`Views/EntryRecoveryNotice.swift:90`); journal Version History; nested Review Changes buttons in Move Entry, Merge Into… and the journal lifecycle sheets; the `Can't Be Deleted` alert for Delete Journal and Delete Permanently (`Views/DeletionConflictAlert.swift`).

**Known problems this removes:** open questions A15 (Review Changes does nothing visible when the save fails), A16, A17, A49, B3, B11 (in part), D14 and D18.

**What does not change:** the in-editor merge for text composition (`Editor/ExternalEdits.swift`: block-wise rebase while an input method is composing; overlapping blocks keep the editor's version and the other stays in the entry's Version History) is a different, narrower mechanism and stays as it is. Entry-level Version History stays.

## 3. The rule: what "keep both" produces

### 3.1 Words

- **L**: the version this device holds as the record (unsent, or just saved). **R**: the other version: the latest the server holds, or, from a stale save, the stored one it found. Only the **latest** R per record is ever used in a round.
- **Marker**: a canonical permanent-deletion marker ([protocol/permanent-deletion.md](../../protocol/permanent-deletion.md)).
- **Last** and **first**: the order in which the server accepted the versions. On the device that finds the conflict, L is nearly always the later one (it is rebased on top of R), so "L stays the record" is the same as "last stays the record". This is the server's order, not recency: a device offline for a week gives its stale text the main entry, and the newer text becomes the copy. 4.2 therefore tells the person when the other version is newer.
- **Copy**: a new record made from a version. **Automatic copy**: one this rule made, recorded in the sealed key (5.2).

### 3.2 One pure function

`ConflictResolution.resolve(local: L, other: R, kind) -> Outcome` lives in JournalCore beside the store and takes decoded items only. The first row that matches wins:

| # | Situation | Record | Other version | Note |
| --- | --- | --- | --- | --- |
| 1 | Either version is not editable or carries preserved content from a newer app | **Held**: 3.7 | none | held |
| 2 | Same content (3.2.1) | The merged deletion state (3.2.2) on L's content; if that equals R in every field but the modified time, R's bytes are adopted and the record is clean (nothing is sent) | none | none |
| 3 | Entry or template, content differs, neither is a marker | L, unchanged | A copy of R (3.3) | entry note |
| 4 | An entry or template against a marker | **The marker** (final) | The edited version, **parked** as a new entry or template (3.4) | deletion note |
| 5 | Two markers | R's marker; this device's marker is dropped and the record's local history is removed, as Keep Deletion does today | none | none |
| 6 | A journal, content differs, neither is a marker | L (name, template), deletion state as in 3.2.2; R is kept in the record's history | none | rename note when the names differ |
| 7 | A journal against a marker | **The marker** (final) | none: a journal copy would not carry entries | deletion note with the journal's name |

Row 2 matters: **a conflict that is only "deleted on one device, untouched on the other" is not a conflict.** The item ends up in Recently Deleted once, with its content, and no copy is made. If one device restored an item and the other deleted it, the deletion state of 3.2.2 wins: the item is in Recently Deleted, one Restore from being back.

**3.2.1 Same content, field by field.** A false "equal" loses an edit silently and a false "different" only makes a copy, so equality is strict and the contract lists it. Two versions have the same content when all of these are equal:

- entries: `title`, the whole `document` (the Markdown text, and `metadata`: `blockIDs`, `segmentLengths`, `imageTypes`; a version-1 document compares its blocks, runs and image descriptions), `date`, `journalID`, `archivedAt`;
- templates: `title`, the whole `document`, `date`, `archivedAt`;
- journals: `title`, `defaultTemplateID`.

`modifiedAt` and `restoredFromDeletionID` are not content (the first is informational, the second is marker bookkeeping; the record keeps L's). `deletedAt` and `deletedWithJournal` are not content either: they are the deletion state and are merged as a unit (3.2.2). Unknown fields are not compared because a version that has any is held (row 1). Comparison is of decoded values, not bytes, because another device seals the same content differently.

**3.2.2 Deletion state.** `(deletedAt, deletedWithJournal)` is one unit and the rule uses no clock. When only one version has a `deletedAt`, that version's pair is taken. When both have one, the pair with `deletedWithJournal` true is taken if either has it, else R's pair. When neither has one, the pair is none. `deletedWithJournal` is only ever set by writers before 1.0 (current writers delete a journal by its own `deletedAt` and its entries follow by inheritance), so the clause matters only for legacy entries; it keeps "live against deleted with its journal" from giving a live-flag entry with a `deletedAt`.

### 3.3 Entries and templates (row 3)

The record stays exactly as this device has it (same bytes, so the open editor sees nothing). R becomes a **separate entry (or template)**:

| Field | Value | Why |
| --- | --- | --- |
| Identity | Derived, not random (3.3.1) | The same copy is made once however many devices find the conflict |
| Title | `messages.conflict.copyTitle`: "{title} (other version)", where {title} is R's title, or when empty the title the lists show for it (its first line, cut at 60 extended grapheme clusters, or `library.entryList.untitledEntry`). Always appended, never detected: a copy of a copy reads "X (other version) (other version)" | **A requirement.** Without it a copy is indistinguishable from the original on every other device, 1.0 included, and the device that resolved is the only one that could explain it. The body is never touched. Clients never parse the wording and may localize it; sameness is decided by the id and the sealed key, not by the title |
| Document | R's, unchanged, with images, image descriptions, links and block identities | Nothing is merged or rewritten |
| Date | R's | "Each version keeps its date" (today's rule) |
| Place | R's journal, R's deletion state | "Each version stays where it is": a version in Recently Deleted stays there. A copy whose journal is gone is Unavailable, and Restore brings it to the Default Journal if it is deleted (3.4) |
| Modified time | R's | Deterministic; today the store stamps the current time (open question C24) |
| Pin, journal order | none | Pins belong to the library record |
| Images | The same attachment ids (3.3.3) | Attachments are immutable and shared by id |

On the **record** side nothing is stamped: its payload bytes are unchanged, its revision becomes R's server revision, it stays dirty, and its outbox row is replaced by one based on R's revision, as `resolve` does today minus the new modification time.

**3.3.1 Copy identity, exactly (a cross-client contract).** Let `text` be the exact plaintext UTF-8 text of the version being copied, as this device holds it (for R: as received, decrypted; for a library without encryption: the base64-decoded payload). Let `label` be `conflict-copy` for a copy of the other version (3.3) and `conflict-park` for a parked entry (3.4), so a parked entry and a copy of the same version never collide.

1. `K` = HKDF-SHA-256 (empty salt, input key = the 32-byte vault key, info = the UTF-8 bytes of `journal:v1:conflict-copy-id`, 32 bytes of output). In a library without encryption there is no vault key, and `K` = SHA-256 of that same info string (public by design: the server reads plaintext there anyway).
2. `tag` = HMAC-SHA-256(`K`, UTF-8(`label` + LF + lower-case hyphenated record id + LF + lower-case hex SHA-256 of `text`)).
3. `b` = the first 16 bytes of `tag`. Set `b[6] = (b[6] & 0x0F) | 0x80` and `b[8] = (b[8] & 0x3F) | 0x80`.
4. The id is the 32 lower-case hex digits of `b` in that order, hyphenated 8-4-4-4-12. (A .NET `Guid` built from these 16 bytes is mixed-endian: build the string, not the `Guid`, from the bytes.) Writers write it as they write any UUID; readers compare UUIDs case-insensitively and **must not validate version or variant bits** (the page says so; the fixture has an id with version nibble 8).

The keyed derivation hides the link between a copy and its source from a server, which sees record ids, kinds, times and ids, and would otherwise be able to test a guess of short plaintext. What a server can still see is that a base-0 record appeared right after a pull of the same record; that is a metadata fact for [SECURITY.md](../../SECURITY.md#what-the-server-can-see).

**3.3.2 A copy that exists, replacing a copy, and markers (no clock, no overwrite).** The sealed key (5.2) records, for each automatic copy this device made (copies and parked entries alike): the copy id, the record id, the origin device of R, R's revision, and the SHA-256 of the copy's plaintext exactly as this device wrote it. When a resolution wants to make a copy, it decides in this order:

1. **The derived id already exists locally, in any state: do nothing.** No write, no note, no new copy. The existing record is the copy. This covers: the copy arrived from another device before this device resolved (a page can end between the copy and the record's new revision); it was edited, deleted (a normal deletion keeps the record) or permanently deleted (a marker) on another device and pulled here; or this device made it earlier. Nothing is revived, overwritten or duplicated. The record side of the resolution still proceeds.
2. **Otherwise, replace an earlier copy** of the same record if **all** hold: the later R has the same origin device as the copy's recorded one and a higher revision (it descends from that version), **and the origin device is known** (a nil or unknown device, which is what a stale save records, never matches, so such a copy is never replaced); the copy record's stored plaintext is byte-identical to what this device wrote (nobody, here or elsewhere, has changed it since: a change from elsewhere would have been pulled and would differ); the copy is not dirty from a local edit and is not being written. The replaced content goes to the copy's Version History; the copy keeps its id and the sealed key's entry is updated; an unsent copy's outbox row is replaced. If another device edited the copy and we have not pulled that yet, our push gets 409, which is an ordinary conflict on the copy that keeps both.
3. **Otherwise make a new copy** with the derived id.

A copy this device made and has not yet sent is replaced, without a further copy, by a version of the same record that arrives first (two clients may write the same copy with different title wording or key order): the arriving version wins and the local one is dropped. An automatic copy or parked entry never revives a marker: when an unsent one meets a marker as R, the marker wins and it is dropped (its content is still in the other record).

**The one exception to "one copy however many devices find it."** A replaced copy keeps the id of the version that first made it, but a different device meeting the replacing version derives an id from its text. If two devices meet the same R while one has replaced an earlier copy, that content exists twice, once under each id. The bound is exactly one extra identical-content copy per replacement, lossless; scenarios 3 and 5 of section 10 assert this bound and not zero.

**3.3.3 Images.** The copy lists R's attachment ids; no bytes are copied. The images R refers to are queued for download as for any received record (`apply` already returns them), so the copy shows placeholders until they arrive and is readable in text offline. Images L is still uploading are untouched. Attachment discovery for sync, archive, history and cleanup counts every record, every history row and every conflict row, so a shared image is never cleaned up while any of them refers to it, and permanent deletion keeps image files ([protocol/permanent-deletion.md](../../protocol/permanent-deletion.md)). Export Archive and Export as Markdown include both entries, each referring to the shared image once.

### 3.4 Permanent deletion against an edit (rows 4 and 7)

Someone used Delete Permanently on one device while the item was edited, or restored, on another. The deletion stays final; the edit is not discarded.

- **Entries and templates (row 4):** the marker is the record on every device, exactly as a deletion with no conflict. The edited version is **parked as a new entry or template**: a derived id (3.3.1 with label `conflict-park`, from the edited version's text; if that id exists, 3.3.2 applies), its own content, date and journal, title unchanged (it is not "the other version" of anything), `deletedAt` = the marker's `permanentlyDeletedAt` (the same on every device) and `deletedWithJournal` false, `restoredFromDeletionID` empty. It is in Recently Deleted when its journal is live, from where one Restore brings it back (simplification N). If its journal was also deleted permanently or is missing, it is in Unavailable Journals, and **Restore** brings it back too: Move Entry refuses a deleted entry, so the recovery is Restore, whose destination in that case is the Default Journal. That fallback is a row of the restore rules that the library design [1-1-library-simplifications.md](1-1-library-simplifications.md) (owner of simplification N and of `restoreEntry(_:fallback:)`) adds ("own tombstone, journal missing or permanently deleted"). Step 1 does not ship until that row exists (6.1 gate). The list row's action opens the entry where it is. A second Delete Permanently on it is an ordinary marker.
- **The open entry.** When the resolved record is the entry open in the editor, the app moves the editor to the parked entry as part of the resolution: same text, same draft and cursor, the deletion note shown there. The editor's draft is re-targeted, not reloaded, so typing continues into one entry and the next save does not hit the "saved over a marker" rule again. If the editor is the first responder, the visible change (the note) follows the terms of 4.2; the re-targeting itself is immediate, so the draft saves into the parked entry from then on.
- **Journals (row 7):** the marker is final and no journal is created. A journal holds a name and a deletion state, no writing. The note names the journal and says it stays deleted. Entries edited elsewhere in that journal are separate records and are parked as above; they keep the old `journalID`, so they are in Unavailable Journals and Restore brings them to the Default Journal.
- **Why this shape:** markers stay immutable tombstones; 1.0 devices need no `explicitRevival` rule and never review (they receive an ordinary new entry), so the compatibility table has no exception; a second device that finds the same conflict derives the same parked entry, a no-op; and the deletion keeps its promise ("You can't undo this") for that identity. The cost: the edit loses its original identity (its history was already removed by the marker) and the parked entry's journal-level pins do not follow.
- **The pass on 1.0's pending rows** applies the same rule to rows the person left pending in 1.0, including a deletion they had meant to confirm with Keep Deletion. The deletion is made final and the edit parked, never the reverse. Each such outcome is listed in Changed on Two Devices as for the live path and named in the release notes.

### 3.5 Journals (rows 6 and 7)

A journal record is its name, a default template (preserved unchanged; 1.1 no longer edits it) and a deletion state. A copy would not carry entries, so a journal never gets one. Row 6 gives:

| Versions | Result |
| --- | --- |
| Renamed on two devices | L's name stays; R's name is in the note, and R is in the record's history. The device whose name lost has no trail of its own on that device: its person sees the other name arrive (decided here as the designer: "later name stays" is consistent with the library record; stated in the risks) |
| Renamed on one, deleted on the other | Deleted (3.2.2) with L's name: in Recently Deleted, one Restore away |
| Restored on one, renamed on the other | Deleted if either is deleted, as above |
| Same name as another journal after resolution | The existing name rule ([protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md), Journal names) numbers the later one, as an ordinary change, never a review |
| Journal merged into another on one device (Merge Into… in 1.0), entry added to it on another | Not a record conflict, unchanged: the entry is in Recently Deleted with the deleted source journal. Simplification L removes Merge Into… |

Current writers delete a journal by setting only the journal's `deletedAt`; its entries are in Recently Deleted by inheritance ([protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md)), so a rename against a deletion meets no entry conflicts of its own, and an entry edited elsewhere in it is an ordinary record with an ordinary conflict if it was also edited here. Only legacy entries with `deletedWithJournal` exercise that flag (3.2.2). When equal names meet unequal `defaultTemplateID`, row 6 takes L's template and a 1.0 device's different choice is overwritten without a note, because no 1.1 screen shows the field.

### 3.6 Entry edited on one device, deleted on another (rows 2 and 3)

An ordinary deletion is `deletedAt` on the record. If the contents are equal, row 2 applies. If they differ, row 3 applies and **each version stays where it is**: the edited text stays in its journal, the other in Recently Deleted. This is today's Keep Both outcome without the question. Known cost: if the deleting device held the unedited original, Recently Deleted gets an older copy of text that also exists, edited, in the journal. Skipping a copy because its content is in this device's own Version History would differ between devices and is not part of the contract; an implementation may not do it. A deletion against a restoration is resolved by 3.2.2: it stays deleted.

### 3.7 What stays held, and what is not covered

- **Held (row 1): a version this app cannot read** (preserved content from a newer app, unsupported document). A client must not save over a record it cannot fully read ([protocol/records.md](../../protocol/records.md), Reading rules). The `conflicts` row stays for these only, the record stays unsent, nothing is created. At each resolution point the held rows are tried again, so they resolve when the app can read both versions. The person is told with the existing update wording: the Settings ▸ Sync footer `messages.conflict.kept.updateNeeded` and, on the entry, `messages.conflict.kept.noticeUpdate`. There is no sheet; Export Archive stays in Settings ▸ Backup.
- **The library record** (pins, journal order) already merges by its own rule and is untouched.
- **Merging libraries (Merge Journals) and importing an archive as new journals** go through the same function where they find the same record in two versions (`StoreMerge.swift`, `Store.importHistory`). Unresolved conflicts that a 1.0 archive carries are rows with revision 0 and are resolved by the same pass when imported.
- **Version History** of entries is unchanged. Resolution adds a history row only where the rules say (journals, replaced copies, superseded versions).
- **Moved on one device, edited on another** gives two entries (the moved one is the other version, with the old text). The store keeps no common ancestor, so it cannot tell which fields changed. Considered and not adopted: a sealed copy of the last synced payload per dirty record would allow independent-field merges and remove most such copies; it is a larger change to the store and archive and can follow in 1.2 without changing any rule above.

### 3.8 When and how it runs

1. **Working set.** The `conflicts` table stays and is filled at the same sites as today (section 2), with the same rule: one row per record, replaced only by a higher revision, the replaced R going to history (`preserveSupersededConflict`). A pull that delivers revisions r1 to rn of a record therefore leaves one row, with rn. While the row exists the record is not sent (`Store.pending()` joins it), as today.
2. **Resolution point.** `resolveConflicts()` runs (a) at the end of every completed pull, however many pages it took (`hasMore` false, cursor committed), also when a push failed for an unrelated record; (b) at store opening, only for rows 1.0 left and rows from imports, and for any row when no server is configured (the pass, 3.9); (c) after a local merge or import; and (d) after a stale save when no server is configured. It never runs while a reconciliation is in progress (`settings.reconcile` is present), because a row's revision and R are not final until the whole restored log is compared. It skips a record that is being written (`isBeingWritten`) or while a save has failed, and held rows. Nothing changes under a person who is typing, so the notice needs no delay. After it, the round pushes what it queued, so the person waits no extra interval (confirmed in implementation).
3. **One transaction per record.** In it: re-read the row and the record and check, as `resolve` and `deletionConflict` do today, that the revision and payloads are those just read (otherwise leave the row for the next round); compute the outcome with 3.2; write the record (revision := the row's revision, dirty, outbox row replaced by one based on that revision, or adopt R clean for row 2); remember R as the server's version at that revision; create or replace the copy and record it in the sealed key; add the note; delete the row. If anything fails the transaction rolls back, the row stays, the cursor is unaffected, and the next round repeats it. Nothing is half done.
4. **Bound.** At most one resolution per record per round, so at most one new copy per record per round, whatever the page boundaries. Across rounds, 3.3.2 lets a later version from the same device replace an untouched copy, so a record ends with at most one automatic copy per other device that is still being typed in, not one per exchange; the single exception is the identical extra copy of 3.3.2.

**Worked example, three devices converge.** A, B and C all hold entry E at revision 5 (text `t`). Offline, A writes `a`, B writes `b`, C writes `c`.

- A syncs first: E r6 = `a`.
- B syncs: its push (base 5) gets 409 with `current` = r6; B's row has R = `a`. At the end of the round B resolves: E stays `b`, revision 6, queued at base 6; copy cA = id(E, text of r6), content `a`, queued at base 0. Server: E r7 = `b`, cA r1.
- C syncs: its push is refused with `current` = r7, so its row has R = `b`; the pull then delivers r6, which is lower than the row's revision and is dropped on C (it is not placed in history; nothing is lost, because B's copy cA holds it). C resolves: E stays `c` at base 7; copy cB = id(E, text of r7), content `b`. Server: E r8 = `c`, cB r1.
- A and B pull: A's and B's copies of E are clean (acknowledged), so they apply r8; cA and cB arrive as new entries.
- Result on every device: E = `c`; cA = `a (other version)`; cB = `b (other version)`. All three texts are present, once. The invariant: the device that overwrites a server version it had not seen copies it, so no version needs a copy from a device that never saw it. Had C pulled only r6 before B pushed, it would have derived cA too: the same id, so if cA has already arrived the derived id exists and C does nothing (3.3.2, step 1); if not, C's creation (base 0) gets 409, finds the same record and adopts it; no duplicate.

**Co-editing cannot storm.** Two devices both typing in one entry: while a device is typing, its record is being written and is not resolved; when it pauses, its round pulls the other device's latest version, makes one copy of it, and pushes. The other device does the same at its pause. Each copy is the other's latest version, and a later version from the same device replaces the untouched copy (3.3.2). After N alternating pauses each device holds at most one automatic copy of the other, not N. A scripted scenario (section 10) alternates edits for 20 rounds and checks every text is present and the copies are bounded by two.

### 3.9 The one-time pass for rows 1.0 left

A library that 1.0 left with `conflicts` rows is resolved when 1.1 opens it, inside store opening and before any sync can start, so a pull cannot replace a row's R first. The pass takes only rows that existed before this 1.1 install first opened the library (the sealed key records that the pass has run) and rows from imports (revision 0), because their R is what the person last saw. A row made by 1.1 and left by a crash in the middle of a paged catch-up is **not** resolved at opening, since its R may be an intermediate revision; it waits for the next completed pull (3.8). A library with no server has no pull to wait for, so its rows are resolved at opening. Rows are handled one at a time, each in its own transaction, by the same function. The preconditions of today's `resolve` and `deletionConflict` hold (the row's revision equals its stored R's, `localRevision <= revision`); a row that fails them is a superseded review: its R goes to history and the row is dropped, with a note. A failure leaves that row for the next open. Each outcome appears in Changed on Two Devices. The person is not asked, because the outcome keeps both versions; this changes what 1.0 left pending only by answering it "keep both" (or, for a pending deletion, "keep the deletion, park the edit"). Step 1 runs the pass for journal and marker rows, step 2 for the rest.

## 4. How the person notices

Quiet means no alert, no badge, no sound, no Sync Status, no hold on syncing, no effect on the rating request (kept notes are not a problem). Discoverable means the person who looks finds out what happened, in three places that are already where they look.

### 4.1 The copy itself

It is an entry in the journal, next to the original, with the title "{title} (other version)" and its own date. On another device, including 1.0, it arrives like any entry. Search, pins, Move Entry, Delete and Restore work on it. Agents with access to the journal see it as one more entry (read-only, as everything).

### 4.2 The notice above the open entry (the device that resolved)

Replaces `ConflictNotice`, in the same place (above the title on iPhone, above the writing in the detail column on iPad and Mac) and the same style (callout text on the quaternary fill, no animation, wraps).

- Text: `messages.conflict.kept.notice.entry` or `.template` ("This entry was also changed on another device. The other version is saved as a separate entry."), or the `Newer` variant when the other version's modified time is later than this one's ("This entry was also changed on another device, and that version is newer. It is saved as a separate entry."). The comparison uses device clocks and only chooses the wording. Buttons: **Show Other Version** (`messages.conflict.kept.showOther`) and **Dismiss** (`common.dismiss`). At accessibility text sizes the text stacks above the buttons.
- **When it appears.** Resolution never runs while the record is being written, so nothing arrives mid-keystroke. If the editor is not the first responder it appears in place. If it is (the cursor rests in the text after a pause), it appears the next time the entry is shown, or when the editor resigns first responder, so the text under a resting cursor does not move.
- Show Other Version opens the copy (journal selected, search cleared, Recently Deleted or Templates opened when that is where it is) and marks the note seen. Dismiss marks it seen. Seen notes stay in the list below until they expire.
- VoiceOver: no announcement is posted (UIKit has no polite priority and an announcement would talk over typing echo); the notice is read when focus reaches it, as a normal static text with two buttons. Voice Control: "Show Other Version", "Dismiss". Return and Escape are not bound.
- The notice is local, from the sealed key (5.2). It is not on the other devices, which see the copy's title instead. On the device whose entry text just changed because the other device's version came in as the record, nothing explains the change except the copy beside it (stated in the risks).
- A held entry shows `messages.conflict.kept.noticeUpdate` instead, with no buttons.

### 4.3 Settings ▸ Sync ▸ Changed on Two Devices

Replaces the Changes to Review section, in the same place (last section of the Sync pane). Shown only unlocked and only with rows: the 20 most recent, expiring after 30 days (**journal rename notes do not expire**: with no journal history screen they are the only trail of the losing name, and only Clear List removes them; when the cap is reached the oldest other note goes first), `messages.conflict.kept.footer` as the footer, and a **Clear List** button (`messages.conflict.kept.clear`) as the last row, no confirmation (it only forgets notes).

**Each row is one control.** A row that has something to show is a single tappable row with a disclosure indicator (a button on the Mac), not text with a second button inside it, so there is one target and VoiceOver reaches it. Its accessibility label is the title, the sentence and the date and time, read in that order; its hint is `messages.conflict.kept.rowHint` ("Opens it."). Activating it opens the item (Settings closes first on iPhone and iPad; on the Mac the library window comes forward and selects it). A row with nothing to show (a journal rename) is plain text.

| Case | Sentence |
| --- | --- |
| Entry or template, both versions kept | `messages.conflict.kept.entry`: "Changed on two devices. Both versions are kept." or `messages.conflict.kept.entryNewer`: "Changed on two devices. The other version is newer. Both versions are kept." The row opens the copy |
| Journal renamed on two devices | `messages.conflict.kept.journalRenamed`: "Renamed on two devices. The name is now “{name}”; the other was “{otherName}”." Plain text |
| An edit against a permanent deletion (entry or template) | `messages.conflict.kept.deletedAndChanged`: "Deleted permanently on one device and changed on another. The changed version is saved separately." The row opens the saved version wherever it is |
| A journal against a permanent deletion | `messages.conflict.kept.journalDeleted`: "Deleted permanently on one device and changed on another. It stays deleted." Plain text |

"Deleted permanently" follows the catalog's Delete Permanently. Text is built from current titles at display time. A row whose item no longer exists is removed silently. Held records add one line to the Sync pane's footer (`messages.conflict.kept.updateNeeded`), not a row.

### 4.4 Per device

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Copy | In the entries list of its journal | Same | Same |
| Notice | Above the title, full width, 16 pt side gutter, stacked buttons at accessibility sizes | Above the writing in the detail column | Same, in the detail column |
| List | Settings sheet ▸ Sync, grouped form, rows with disclosure | Same | Settings window ▸ Sync tab, grouped form; the row is a button |
| Open | Closes Settings, then navigates (compact: pushes the item) | Closes the Settings sheet, selects the item | Selects the item in the library window |

No behaviour differs; only the container does, as today.

### 4.5 States

| State | Behaviour |
| --- | --- |
| Offline | Nothing to show or do. Resolution happens at the points of 3.8: a completed pull, store opening for old rows, a local merge or import, and, when no server is configured, after a stale save. With a server configured but unreachable, a stale-save row waits for the next completed pull |
| Loading | A copy's images show placeholders until downloaded; its text is there at once |
| Error | A resolution that cannot be stored rolls back and fails the round like any local-data failure (`messages.sync.localDataUnavailable`, temporary) and is repeated. Opening an item that was removed removes the row. No new error text |
| Locked | Sync does not run while locked; the list and the notice are hidden; titles are not read |
| Library being replaced | No resolution runs; the list is hidden |
| Empty | The section is absent |
| Increase Contrast, Reduce Transparency, Reduce Motion, Dynamic Type | The notice uses the quaternary fill with system text, appears without animation, wraps; rows wrap at every size. Nothing is told by colour alone |

## 5. Compatibility with 1.0, storage and the protocol

### 5.1 Mixed devices

| Situation | Result |
| --- | --- |
| 1.1 resolves; 1.0 receives | The record arrives as an ordinary revision, the copy as a new entry. A 1.0 device with its own unsent edit to that record gets its own review form, with 1.1's version as Other Device, as it would from a 1.0 peer |
| 1.0 resolves with Keep Both (random copy id, no title suffix); 1.1 receives | An ordinary revision and an ordinary new entry |
| 1.0 and 1.1 both find the same conflict | Two copies at worst (random id on one side, derived on the other). Only in a mixed fleet, only once |
| Permanent deletion against an edit | The marker stays; 1.1 adds an ordinary new entry. 1.0 devices need no special rule. (A 1.0 device that resolves the same conflict with Keep Entry sends the existing marker restoration; 1.1 devices apply it as they do today, and the parked entry stays as a separate entry) |
| A 1.0 device holds an unresolved review for a record while 1.1 devices keep editing it | As today: its row follows the newer versions; the replaced version goes to its history. Its edits are sent when its person resolves |

### 5.2 What the wire, the server and the archive see

- **Wire and server:** no change: `PUT /sync/{id}` with `baseRevision`, 409 `revision_conflict` with `current`, creation at base 0, short receipts, markers. No capability, record kind, field or server release. The server never learns that a conflict happened. A copy shows to it as a base-0 record created right after a pull of the same record (a metadata fact, noted in SECURITY.md).
- **Database and archive:** **no table, migration or schema object is added.** `conflicts` already exists and is already in archives. Everything else is one new key in the existing `settings` table, `kept-notes`: base64 text of JSON `{"version": 1, "copies": [{copy id, record id, origin device, origin revision, written-payload digest}], "notes": [{kind, record id, other id, name, other name, seen, created}]}`, sealed in encrypted libraries like `library-changes` with AAD `journal:v1:local:kept-notes`, so a name in a note is not in clear text. `copies` holds the copies and the parked entries this device made, with the digest of the plaintext it wrote (so it survives re-sealing and any change of protection); it is pruned when an entry's record is gone or no longer matches, and kept to 200 entries. Ids derived before a library is encrypted differ from ids derived after (the vault key is new); that transition is rare and simplification G removes it. The key also records that the one-time pass has run (3.9). A value that cannot be opened is ignored and blocks nothing. `protocol/archive.md` already says "Readers ignore keys they don't know", so an older reader opens a 1.1 archive; a restore on an empty device carries the key with the library. `Reencryption` re-seals it where it re-seals `library-changes` (`StoreReencryption.swift`), and the schema check needs no change.
- **Coordination with the archive design.** [1-1-archive-v2.md](1-1-archive-v2.md) rewrites `protocol/archive.md`; its authors must carry one added sentence in the Settings keys paragraph ("`kept-notes`: local notes and automatic copies, sealed like `library-changes`") and keep the rule that a reader ignores unknown settings keys. Neither design depends on the other beyond that sentence; this record needs no archive format number.
- I considered carrying a copy marker in the library record's `values`: rejected, because it would be a wire addition to keep a cosmetic note in sync, and the title already says it.

### 5.3 What does change in `protocol/`

1. **New contract page `protocol/conflicts.md`, with its own version line (conflicts v1) in the README table.** It contains: the table in 3.2 and the equality of 3.2.1 and 3.2.2; the copy fields and the exact identity construction of 3.3.1 (including that readers must not validate version or variant bits); replacement and arrival rules of 3.3.2; parking in 3.4; the journal rules of 3.5; what is held; and the orchestration of 3.8 (latest R only, resolution at the end of a round and not for a record being written, one resolution per record per round). It says: a client that predates the page and shows review forms (1.0) remains conforming; a client that implements automatic resolution implements all of the page and nothing less; titles are catalog text that clients never parse; the server never sees a conflict.
2. **Wording in [protocol/README.md](../../protocol/README.md), Sync and conflicts:** the sentence "The client retains its local version until an explicit resolution" stays as the baseline behaviour, and one sentence is added: "A client that implements [conflicts.md](../../protocol/conflicts.md) resolves automatically instead." The same addition where reconciliation says "a normal conflict for review". This keeps the change additive and 1.0 conforming without relying on a carve-out. Same addition in [protocol/conformance/sync/README.md](../../protocol/conformance/sync/README.md) (`client: conflict`).
3. **Fixtures** (new files, never editing existing ones; [protocol/conformance/README.md](../../protocol/conformance/README.md), Changing a contract):
   - `records/conflict-resolution-v1.json`: cases for rows 2 to 7 with the **exact plaintext text** of L and R (not decoded values), the expected record and copy as plaintext text (title excepted: it is checked as "starts with R's title or the displayed title", marked localized), and notes. Includes: collapse of delete against untouched, deletion state as a unit (live against deleted with journal), restore against delete, a copy in Recently Deleted, an untitled entry, a title already ending in "(other version)", an entry against a marker, two markers, a journal against a marker, an unreadable version (held), versions that differ only in `blockIDs`, `segmentLengths` or `imageTypes` (different, strictly: a copy is made, so every client agrees), a stale-save origin (nil device: never replaced), and a parked entry and a copy of the same version (different ids by label).
   - `records/conflict-copy-ids-v1.json`: the vault key, the info string, `K`, the text, the final hyphenated ids (not `Guid`s), one with version nibble 8 and one library without encryption.
   - `sync/conflict-scenarios-v1.json`: **scripted multi-device scenarios** (event lists: device, edit, go offline, sync round with page size, expected records on every device at the end). They cover the three-device example of 3.8, a page boundary inside the log, the same conflict found by two devices after a server restore, co-editing for 20 rounds, **the derived copy id existing locally in each state** (the copy arrived before the record's revision; the copy was edited, deleted, or permanently deleted on another device, parked entries included; this device made it earlier), a replacement meeting a second device's copy (asserting the single identical extra copy of 3.3.2), an automatic copy meeting a marker, a held record in a mixed page, a crash in the middle of a paged catch-up (not resolved at opening), and the marker cases of 3.4 including the open editor. This is what shows two clients interoperate; the pure function alone does not.
4. **Version.** This adds a contract and changes no existing one; `/v1` and every existing fixture stay valid, so the protocol major stays 1. The new page carries its own version; AGENTS.md's rule is met by versioning the new contract and updating the fixtures, and the reviewer confirms that reading. Swift `Conformance*` tests read the new fixtures; the .NET server has nothing to read for the first two files (it never interprets payloads) and replays nothing from the third, whose scenarios are clients' (Windows adds its own runner).

## 6. The two steps

### 6.1 Step 1: journals and deletions resolve themselves

Ships alone. After it, only entries and templates still show the review sheet.

**Core:** `ConflictResolution` and `resolveConflicts()` for rows 2, 4, 5, 6, 7 (entries and templates against markers included), the `hold` policy; the one-time pass for journal and marker rows; the sealed `kept-notes` key; `protocol/conflicts.md` and the journal and deletion fixtures and scenarios.

**UI removed:** `Views/JournalConflictView.swift`; `Views/DeletionConflictView.swift`; `Views/DeletionConflictAlert.swift`; the journal and deletion branches of `ConflictRouting.swift` (the sheet keeps the entry form and the unsupported form); the journal review buttons in `Views/DeletedJournalView.swift`, `Views/EntryRecoveryNotice.swift` (the `.conflict` case), `Views/JournalHistoryView.swift`, `Views/MoveEntryView.swift`, `Views/MergeJournalView.swift`, `Views/JournalLifecycleView.swift`; the dimming of Rename…, Default Template and Merge Into… for conflicts (`Model/JournalOperations.swift`, `Views/JournalMoreMenu.swift`, `Views/JournalSidebarView.swift`); the delete refusal alert (Delete Journal and Delete Permanently on a record with a held conflict show the existing newer-version messages); `JournalSettingsView.swift` is already dead code (simplification A). The Unavailable Journals reason `.conflict` becomes `.unsupported` for held journals.

**UI added:** the Changed on Two Devices section (journal and deletion rows only at this step) beside the still-present Changes to Review section (entries, templates, held).

**Copy:** removed `messages.conflict.journal.*` (15 keys), `messages.conflict.deletion.*` (40), `messages.deleteConflict.*` (3), `messages.conflict.updatedReviewAgain`, `common.journalNeedsReview`, `library.deleteAll.held.review`, `library.deleteAll.nothing.review`, `messages.save.before.reviewChanges`, `messages.save.before.exportArchiveForConflict`; `messages.history.chooseJournal` changes to the update wording or is removed if unreferenced; `messages.lifecycle.needsReview` is removed by H (it is [1-1-library-simplifications.md](1-1-library-simplifications.md)'s to name: held conflicts use the existing update messages instead), as are `common.defaultTemplate` and `common.blankEntry` by whichever of H step 1 and M lands first (the journal review form is their other user); `common.reviewChanges` stays until step 2; added the list keys (section 8).

**Gate to ship:** the one-time pass resolves a library full of 1.0 journal and marker rows; mixed-fleet sync test; **an entry conflict inside a journal that auto-resolves**, because step 1 ships with entries still using the review sheet; a journal renamed on one device and deleted on another with an entry edited inside it; **the Default Journal fallback of Restore from [1-1-library-simplifications.md](1-1-library-simplifications.md) exists** (a parked entry whose journal is gone must be recoverable).

### 6.2 Step 2: entries and templates keep both

Ships after step 1 has been in a TestFlight build. After it there is no review sheet at all.

**Core:** rows 3 and 6's remaining parts for entries and templates; copy identity and replacement; stale-save rows; reconciliation and merge sites; the one-time pass for the remaining rows; held rows keep the policy `hold`.

**UI removed:** `Views/EntryConflictReview.swift`, `Views/ConflictRouting.swift` and the `DeletionSheet` use for it (`PermanentDeletionView.swift` keeps `DeletionSheet` for permanent deletion only), `ConflictNotice` and `ConflictSettingsSection` (`SettingsView.swift`), the list symbol (`RootView.entryConflictIndicator`), the nested review buttons in Move Entry and Version History, `AppModel.conflicts` as a published list for the UI (held ids only), the `reviewRequests.noteProblem()` call for conflicts, `messages.generic.templateNeedsReview` (shared removal: M deletes its caller, H step 2 deletes the key, as the library record says) and `messages.entry.moveNeedsReview` (held records show the existing update messages), the command `review-changes`, and the screenshots `conflict-review-*` and `resolve-conflict-*`.

**UI added:** the notice (4.2) with Show Other Version and Dismiss; Settings ▸ Sync rows for entries and templates.

**Copy:** the remaining `messages.conflict.*` review keys, `common.reviewChanges`, `common.reviewChangesFor`, `common.version`, `messages.save.before.resolveEntryConflict` are removed; the notice, copy-title and row keys are added.

**Gate to ship, and the decision.** Step 2 ships in the release whose build first passes these gates: the convergence and scenario tests of section 10, and a soak with two devices on the owner's real library, as TestFlight, with the list reviewed. It is not an owner question: if the gates are not met by the 1.1 build, step 2 goes in the next release and 1.1 keeps the entry review sheet for entries and templates.

### 6.3 Interaction with the other simplifications

- **K** (no journal Version History) and **L** (no Merge Into…) remove entry points; step 1 does not depend on them. Journal history rows are still stored (3.5).
- **M** (no default template) leaves `defaultTemplateID` in records; resolution preserves and compares it (3.2.1).
- **E** (Settings tabs) moves Devices into Sync; the section goes in whichever pane is called Sync.
- **G** (every library encrypted) is independent. The function works on decoded items and the id derivation covers both protections.
- **N** (Restore only) makes "one tap to bring it back" true for the parked case in 3.4, but only with its fallback row (a parked entry whose journal is gone restores into the Default Journal); that row belongs to [1-1-library-simplifications.md](1-1-library-simplifications.md) and is a precondition of step 1.

## 7. I: one Reconnect action

### 7.1 Current behaviour

One sheet, three labels. `SyncStatusAction` has six cases, three of which connect (`Model/SyncHealthOperations.swift:6-22`, `syncStatusAction` `:29-39`, `perform` `:121-128`, `reconnectsOnConnect` `:131-133`). The labels are the sync state's single action, shown by `Views/SyncNowRows.swift:32` (Settings ▸ Sync), `Views/RootView+Toolbar.swift:70` (iPhone and iPad Sync Status menu), `Views/Mac/RootView+MacWindow.swift:45,69` (Mac toolbar menu) and `Views/DevicesView.swift:43` (a refused device: the state's title, or a literal "Connect Again…"). Other literals: `Views/TurnOnEncryptionView.swift:20,256` and Settings ▸ Privacy ("Sign In…" when encryption was turned on elsewhere) and `Views/ServerAgentsView.swift:67` ("Connect Again…" when agent access has no device access). The flow is `ConnectionView` ("Connect to a Server", `:42`), which on `onAppear` checks this device's server at once when `reconnectsOnConnect` (`:83`) and then follows what the server says (spec/flows/connect-to-server.md, spec/flows/reconnect-to-server.md). The state decides the label only (`SyncHealth.kind`, `Packages/JournalCore/Sources/JournalCore/SyncHealth.swift`):

| State | Label today |
| --- | --- |
| Server not set up | Set Up Server Again… |
| Restored or replaced; access removed | Connect Again… |
| Needs you (encryption turned on elsewhere, or replaced by an encrypted server) | Sign In… |

Problems: three words for one task; Settings ▸ Devices can show a label that disagrees with Settings ▸ Sync (open question A14); messages name Settings ▸ Devices, which simplification E removes (`messages.encryption.accessLost`, B4, B17); "Sign In…" in two more places.

### 7.2 New behaviour

- **One action, `Reconnect…`** (`common.reconnect`, command id `sync-reconnect`, one title). It replaces the three labels in every place above, in Settings ▸ Privacy and Turn On Encryption (until simplification G removes those), in Agent Access, and in Devices. The ellipsis stays: it opens a sheet that needs input (the spec's rule for such actions).
- **Not changed:** "Connect to a Server…" (no server yet) is a different task and keeps its label. Try Again, Check Again and Sync Now are not reconnecting and keep theirs.
- **The flow does not change.** It already asks the server. The sheet is titled **Reconnect** (`settings.connect.reconnect.title`) when opened by this action and still "Connect to a Server" otherwise. Behaviour by what the server says is as in spec/flows/reconnect-to-server.md (not set up: setup code; set up: sign in with the master password, Use a Connected Device Instead…; encrypted since: rejoin and encrypt with the server's key; same library: continues by identity; another library: Merge Journals first). Nothing is sent before Merge Journals; Cancel changes nothing.
- **State messages stay**; they say what happened and keep the "Your journals are still on this device" reassurance. Three texts change so they do not tell the person to do something the button no longer says:
  - `messages.sync.signInNeeded` → "The server now uses encryption or was replaced. Reconnect to keep syncing."
  - `messages.encryption.turnedOnElsewhere` → "Encryption was turned on from another device. Reconnect to keep syncing."
  - `messages.encryption.accessLost` → "This device no longer has access to {host}. Reconnect in Settings ▸ Sync, then try again." (also fixes the stale path and the ">" form, B4, B17).
  If simplification G ships first, the first two states cannot occur for a 1.1 library and the keys go; this record does not depend on G.
- **Access removed says what signing in again needs, by library mode.** The device was removed on purpose, so the button alone invites a loop of failed attempts. `messages.sync.accessRemoved` (library with a password) → "This device no longer has access to the server. Your journals are still on this device. To reconnect, you need your password or a connected device." A library without a password (still possible in 1.1 until G ships) has none, so `messages.sync.accessRemovedNoPassword` → "This device no longer has access to the server. Your journals are still on this device. To reconnect, you need a connected device or a recovery code." The state picks the key from the library's mode; with G both modes collapse to the first.
- **Server not set up.** The first page after Reconnect is the existing Set Up Server step, whose footer already says what is asked (`settings.connect.setUp.footer`: "Enter the code your server shows when it starts. To see it again, run setup-code on the server."). The sheet keeps the title Reconnect around it and the step keeps its own title; the state's message says what happened. No new text.
- **Devices.** The refused-device row shows the sync state's own message (the sync it runs to find out already sets it) and Reconnect…; it falls back to `messages.sync.accessRemoved` only when the sync cannot say. This resolves A14 without waiting for E.
- **Code.** `SyncStatusAction` becomes `syncNow, tryAgain, checkAgain, reconnect`. `connects` is `self == .reconnect`. `syncStatusAction` returns `.reconnect` for `needsYou`, `serverChanged` and `noAccess`. `reconnectsOnConnect` is unchanged. The title and the sheet title come from the catalog.

### 7.3 Layout and interaction per device

No layout changes: the button takes the place of the old one.

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Settings ▸ Sync | Last row of the Server section, after Last Synced and Not on Server Yet, under the state's message | Same | Same, message below the section |
| Sync Status | Item in the Sync Status submenu of the entry's More menu, with Sync Settings… | Same | Item in the toolbar Sync Status menu, with Sync Settings… |
| Devices (until E) | The sync state's message and Reconnect… in place of Add Device… when access is refused | Same | Same |
| Agent Access | Message "This device no longer has access to {host}." and Reconnect… | Same | Same |
| Sheet | Navigation title Reconnect, Cancel at the leading end | Same, card sheet | Sheet with title and Cancel (Escape) |

### 7.4 States

| State | Behaviour |
| --- | --- |
| Loading | The sheet opens on the server address and checks it at once (`settings.connect.busy.checking`), as now |
| Offline or unreachable | The existing page-1 error (`messages.connection.cannotConnect` / `cannotConnectTailscale`) with the address; the state's message in Settings stays. Reconnect… is not disabled for being offline |
| Error | Existing `messages.connection.*` texts, unchanged; `messages.connection.reconnectSameServer` already says "Reconnect" |
| Locked, library being replaced | The button is disabled, as Connect is |
| Writing paused (a save failed) | The sheet refuses with `messages.connection.saveBeforeConnecting`, as now |

### 7.5 Accessibility

The button reads "Reconnect" with the usual button trait; the sheet title is announced as the heading on opening; errors are announced as now. The sync-result announcements (Sync Now, Try Again, Check Again) are unchanged. Voice Control: "Reconnect". Because the three old labels become one, a screen-reader user hears the same word in Settings, in the Sync Status menu and in Devices.

## 8. Copy catalog changes

Texts are exact. Keys follow spec/README.md (one key per text and role; notices and labels that share wording are listed in `copy/same-wording.json`).

**Added**

| Key | Text | Step |
| --- | --- | --- |
| `common.dismiss` | Dismiss | 2 |
| `common.reconnect` | Reconnect… | I |
| `settings.connect.reconnect.title` | Reconnect | I |
| `messages.conflict.kept.section` | Changed on Two Devices | 1 |
| `messages.conflict.kept.footer` | Both versions are kept. This list clears after 30 days. | 1 |
| `messages.conflict.kept.entry` | Changed on two devices. Both versions are kept. | 2 |
| `messages.conflict.kept.entryNewer` | Changed on two devices. The other version is newer. Both versions are kept. | 2 |
| `messages.conflict.kept.journalRenamed` | Renamed on two devices. The name is now “{name}”; the other was “{otherName}”. | 1 |
| `messages.conflict.kept.deletedAndChanged` | Deleted permanently on one device and changed on another. The changed version is saved separately. | 1 |
| `messages.conflict.kept.journalDeleted` | Deleted permanently on one device and changed on another. It stays deleted. | 1 |
| `messages.conflict.kept.rowHint` | Opens it. | 1 |
| `messages.sync.accessRemovedNoPassword` | This device no longer has access to the server. Your journals are still on this device. To reconnect, you need a connected device or a recovery code. | I |
| `messages.conflict.kept.clear` | Clear List | 1 |
| `messages.conflict.kept.updateNeeded` | Some changes from another device need a newer version of My Journal. Update My Journal to combine them. | 1 |
| `messages.conflict.kept.noticeUpdate` | This entry has a version from a newer My Journal. Update My Journal to combine them. | 2 |
| `messages.conflict.kept.notice.entry` | This entry was also changed on another device. The other version is saved as a separate entry. | 2 |
| `messages.conflict.kept.notice.entryNewer` | This entry was also changed on another device, and that version is newer. It is saved as a separate entry. | 2 |
| `messages.conflict.kept.notice.template` | This template was also changed on another device. The other version is saved as a separate template. | 2 |
| `messages.conflict.kept.notice.templateNewer` | This template was also changed on another device, and that version is newer. It is saved as a separate template. | 2 |
| `messages.conflict.kept.showOther` | Show Other Version | 2 |
| `messages.conflict.copyTitle` | {title} (other version) | 2 |

**Changed:** `messages.sync.signInNeeded`, `messages.encryption.turnedOnElsewhere`, `messages.encryption.accessLost` (7.2); `messages.sync.accessRemoved` (7.2: "…To reconnect, you need your password or a connected device."; the no-password variant is added); the context of `messages.sync.action.*` entries in `messages.md`.

**Removed:** `messages.sync.action.setUpServerAgain`, `messages.sync.action.connectAgain`, `common.signIn` (I); the step 1 and step 2 lists in section 6; plus any other key no spec file references after the rewrite (`python3 spec/tools/check-spec.py` warns about each). `common.restoredAsRenamed` stays: Restore Journal uses it. Shared removals follow [1-1-library-simplifications.md](1-1-library-simplifications.md): H removes `common.journalNeedsReview`, `messages.lifecycle.needsReview` and `common.reviewChanges` (steps 1 and 2), `messages.generic.templateNeedsReview` in step 2, `messages.conflict.journal.value.unavailableTemplate` in step 1 with `messages.conflict.journal.*`; `common.defaultTemplate` and `common.blankEntry` go with whichever of H step 1 and M lands first; N removes the `library.restore*` and `messages.restore.*` keys it lists. No key is listed as removed by two records without that note. The earlier proposals `messages.conflict.kept.show`, `.showFor` and `.announce` are not added (whole-row control; no announcement).

**Unchanged on purpose:** `common.thisDevice` (Devices), `messages.sync.serverReplaced`, `messages.sync.serverNotSetUp`, `messages.connection.reconnectSameServer`, every `settings.connect.*` step text.

## 9. Spec and documentation changes the implementation makes

In the same change as each step, per [spec/README.md](../../spec/README.md):

- **Rewritten:** `flows/resolve-conflict.md` becomes "Changes made on two devices" (the rule in section 3, the orchestration, the pass, held); `screens/conflict-review.md` becomes the notice, the list and the held line, or is folded into the flow and the screen id retired with its Apple page; `screens/entry-conflict.md` is removed in step 2 (and the journal and deletion forms in step 1). IDs, sources, `features:` and every link are updated.
- **Edited:** `flows/delete-and-restore.md` (States: the Changes to review paragraph goes; a note on an edit against a permanent deletion is added), `flows/sync-recovery.md` (table, step 3, Rules: "Changes to review count as a problem for the rating request" goes), `flows/reconnect-to-server.md` (title, entry points, one action, access removed), `screens/connect-to-server.md`, `screens/settings-sync.md` (action table, the new section), `screens/settings-devices.md`, `screens/settings-privacy.md`, `screens/turn-on-encryption.md`, `screens/sync-status.md`, `screens/settings-agent-access.md`, `screens/journals.md`, `screens/recently-deleted.md`, `screens/unavailable-content.md`, `screens/entry-editor.md` (the notice), `messages.md`, `commands.md` (`review-changes` removed; `sync-reconnect` one title; new `show-other-version`, `dismiss-kept-notice`, `clear-kept-notes`, `open-kept-note`), `copy/en.json`, `copy/same-wording.json`.
- **`parity.yaml`:** `conflict-review-journal`, `conflict-review-deletion`, `deletion-conflict-alert` (step 1), `conflict-review-entry`, `conflict-review-unsupported`, `conflict-notice`, `changes-to-review-list` (step 2) become `not-applicable` on every platform with the reason "removed in 1.1 by simplification H"; new features `conflict-kept-both`, `kept-both-notice`, `changed-on-two-devices-list`; `sync-recovery`'s title drops the three labels and gains Reconnect.
- **`open-questions.md`:** mark A14, A15, A16, A17, A49, B3, D14, D18 and the conflict part of B11, B4 and B17 resolved with the build; C24 resolved (the copy's modified time); add the risks that are product questions (3.6 older copy in Recently Deleted; moved against edited; the lost name).
- **Apple platform pages under `spec/platforms/apple/`:** the same pages, `index.md`, `commands.md`, `messages.md`, implementation notes, source files, and new screenshots from `design/spec-screenshots/capture.sh` (seed a sample library with one kept-both entry and one journal note; the old `conflict-review-*` and `resolve-conflict-*` images go with their pages).
- **Windows mapping pages** (`spec/platforms/windows/`): the conflict pages, D50 and D52 and the reconnect flow become mappings of the new notice, list and single Reconnect action; Windows never builds the review forms. Their copy proposals drop the removed keys.
- **Protocol:** section 5.3, including the one sentence for the Settings keys paragraph of `protocol/archive.md`, which [1-1-archive-v2.md](1-1-archive-v2.md) rewrites (coordination only; that record is not edited here).
- **Other documents:** `docs/guide/troubleshooting.md` (Review Changes steps; the three reconnect actions), `docs/guide/sync.md`, `docs/self-hosting/README.md` (action names), `docs/architecture.md` (the conflict paragraphs and the tables line), `SECURITY.md` (the metadata sentence of 3.3.1), `docs/design/README.md` (an index row for this record and its review). Older design records are history and stay as they are.

## 10. Tests worth adding

By [AGENTS.md](../../AGENTS.md) "Useful tests only": real isolated SQLite stores and the in-process sync harness used by `LibrarySyncTests` and `ServerRestoreTests`, not mocks. Delete or rewrite the tests of the removed forms with them (`DeletionConflictTests`, `JournalConflictLifecycleTests`, the review parts of `ConflictSafetyTests`).

**JournalCore, in priority order**

1. **Several revisions of one record while L is dirty make one copy.** A pull of r1 to r4 (across a page boundary) with L unsent leaves one row with r4, earlier ones in history, and exactly one copy after the round.
2. **Convergence of an entry edited on two devices, and of three** (`ConflictResolutionTests`): the worked example of 3.8 in both sync orders; all devices end with the same records, every text present once, and no further revisions after two more rounds. Also with a page boundary inside the log. Assert the invariant of 3.8: every version written after the common one appears in the final state as a record or a copy.
3. **Alternating edits cannot storm:** two stores alternately edit the same entry for N rounds (and pause between): the copies stay bounded by the number of devices plus the single identical extra of 3.3.2 (asserted as exactly that bound), and every text written is somewhere (record, copy or history).
4. **A remote edit of a copy is never replaced:** device X edits an automatic copy and syncs; a later conflict on device Y with a descendant of the same origin does not overwrite it (a new copy or an ordinary conflict on the copy), and no content is lost.
5. **One copy however many devices find it:** three replicas reconnect to a restored server that holds a fourth version; exactly one copy exists everywhere, with the id from the conformance vectors. The same run with one replacement in it asserts at most one identical extra copy, not zero.
   - **A derived id that exists locally means nothing is done:** one test per state (clean, edited elsewhere, deleted, permanently deleted, parked, made by this device earlier, arrived before the record's revision): no write, no note, no revival, and the record side still resolves.
   - **A nil or unknown origin never matches** in the replacement rule: two stale-save copies from different real devices are never replaced into each other.
6. **The editor cannot tell (row 3), and follows (row 4):** after resolution the record's payload bytes and `storedVersion` are unchanged and an open draft is not stale (`StaleDraftTests`, `StaleSaveTests` extended); a record being written is not resolved until it pauses; the stale-save path ends with the draft as the record and the arrived text as the copy. For a marker against the open entry, typing continues across the resolution into the one parked entry, with the cursor kept and no second parked entry.
   - **Trigger points:** a stale-save row with no server configured resolves after the save; a row made by 1.1 and left by a crash mid catch-up is not resolved at opening; nothing resolves while `settings.reconcile` is present; an old 1.0 row resolves at opening.
7. **Permanent deletion against an edit:** the marker stays the record on both devices; the edited entry is parked with a derived id and `deletedAt` = the marker's time; a second device derives the same entry; a 1.0 stand-in (policy `hold`) receives only an ordinary new entry; **a deliberately deleted automatic copy is not revived by a late device**; two markers keep one; a journal against a marker creates no journal; **a journal permanently deleted while an entry in it is edited elsewhere** leaves the parked entry in Unavailable Journals.
8. **Equality and deletion state:** each field of 3.2.1 alone makes versions differ (so a copy is made), including a difference in only `blockIDs`, `segmentLengths` or `imageTypes`; `modifiedAt` alone does not; **a legacy delete-with-journal entry against live** gives a deleted-with-journal entry, with no clock involved; restore against delete stays deleted; an outcome equal to R adopts R's bytes and sends nothing.
9. **Journals:** rename against rename (note, R in history), rename against delete, restore against rename, and the name rule afterwards giving a numbered name without a conflict; a journal renamed on one device and deleted on another with an entry edited inside it (the entry resolves by its own row; the journal deletion sets only the journal's `deletedAt`).
10. **The one-time pass:** a library file produced by the current code with a row of every kind (entry, template, journal, a marker against an edit, **a Keep Deletion row left pending**, two markers, one unsupported, one superseded with a failing precondition, one with revision 0 from an archive) opens in 1.1; every readable row is resolved exactly once; interrupting between rows and reopening finishes the rest without a duplicate copy; the unsupported row stays and nothing is sent for it.
11. **A mixed page:** one pull holding a held record (newer-version content) and a normal conflict resolves the normal one and leaves the held one, nothing sent for it, and resolves it once readable.
12. **A failed transaction repeats cleanly:** an injected failure inside the resolution leaves cursor, records, outbox and row as before; the retry produces the same outcome.
13. **Images:** the copy refers to R's attachment ids, those are queued for download, and cleanup and archive export keep one file for both entries.
14. **The sealed key:** a value that cannot be opened is ignored; an older reader opens an archive that has the key (the schema check passes); the key is re-sealed on password-protection changes like `library-changes`.
15. **Fixtures and scenarios:** `Conformance*` tests read `conflict-resolution-v1.json` and `conflict-copy-ids-v1.json` and run the real function; a scenario runner replays `sync/conflict-scenarios-v1.json` against stores and compares every device's final records.

**End to end (few, separate):** one `scripts/test-sync.sh` scenario with the real server and two clients: divergent edits, a journal rename on both, a permanent deletion against an edit; convergence and no held records. The existing server-restore, sync-health and sync-recovery scripts keep running and are updated for the single label.

**App (`JournalTests`):** `KeptNotesTests`: the notice appears once for the open entry after a resolution, in place only when the editor is not the first responder, Dismiss and opening mark it seen, the list drops rows whose item is gone and rows older than 30 days, wording uses the newer variant only when the other version's modified time is later, and nothing shows while locked. No test of layout or of the removed forms.

**Reconnect:** a table test that every state with kind `needsYou`, `serverChanged` and `noAccess` returns `.reconnect` and that only `.reconnect` connects; the existing journeys (`SyncRecoveryUITests` via `scripts/test-sync-recovery-ui.sh`: server reset, restored, access removed) updated for the label and the sheet title and still ending with pending changes sent. Devices shows the sync state's message rather than a fixed one: one model test with the device removed and one with the server replaced.

**Manual, before each step ships (the design gate's last step):** run the app on iPhone, iPad and Mac with a library holding 1.0 conflict rows of every kind; screenshot the notice, the list, the Reconnect menu item and the sheet on all three; inspect each deviation; Release build; a mixed-fleet check with a TestFlight 1.0 device for at least one of each conflict kind.

## 11. Risks

1. **The pass changes what 1.0 left pending.** Existing review rows are resolved without asking, including a deletion the person meant to confirm (it becomes final and the edit is parked). Mitigation: both versions are always kept, the pass is idempotent and per row, the notes list every outcome, the release notes say it, and step 1 runs it first on the small journal-and-deletion population.
2. **Copy clutter.** Two devices being edited at once, a server restore, a moved-against-edited entry, an old copy in Recently Deleted (3.6), or a journal renamed on one device and deleted on another with entries edited inside (3.5) can produce extra entries. The bounds (one resolution per record per round, derived ids, replacement of untouched copies, equal-content collapse, the history check) limit it; they do not remove the cases only a common ancestor could.
3. **"Last" is not "newest".** The text that reached the server last becomes the entry on every device, including a stale one from a device that was offline for a week, and on the other device the open entry changes text with no explanation beyond the copy beside it. The notice and the row say when the other version is newer (from device clocks, as a hint only); the limit is stated here and in the spec.
4. **A losing journal name has no trail on the device that wrote it**; the device that resolved keeps a note until the person clears it (rename notes do not expire), the other sees the name change.
5. **A title is data.** "(other version)" is written into the copy's title in English only (the catalog is English), is editable, and clients may word it differently; the derived id and the replacement rule make the wording irrelevant to convergence.
6. **Mixed fleets** can show review forms on the 1.0 side for a while after 1.1 ships, and make one extra copy. Nothing is lost on either side.
7. **Transaction size and time:** resolution is one transaction per record at the end of a round, so a restore with many conflicts does many small transactions. Measure with `JournalMeasure` on the synthetic library before step 2.
8. **Window of regret:** with no confirmation, a person who would have chosen "keep only mine" must delete the copy (an ordinary delete, undoable). This is the intended trade of simplification H.
9. **Agents** read the copy as an entry; the title makes it recognisable to them too. Journal contents remain untrusted data, as always.
10. **I** depends on the sheet deciding by server state, which already holds; the risk is only copy: messages that still say "Sign in" somewhere (search the catalog for "sign in" and "Connect Again" when implementing).

## 12. Owner decision (one, with a recommendation)

1. **Where the edit of a permanently deleted item goes.** Decided as the designer: the deletion stays final and the edit is saved as a separate entry, so nothing is discarded (AGENTS.md) and no marker is revived. Open for the owner: **where that entry sits.** Recommended: **Recently Deleted** (the same place, Restore recovers it, to the Default Journal when its journal is gone), so nothing reappears in the person's journals and one Restore brings it back. Alternative: **in its own journal as a normal entry**, which is where the writer left it but puts something the other device's person deleted permanently back in view. The rest of the design does not change with the choice.

Not owner decisions: when step 2 ships is decided by its gates (6.2); the label `Reconnect…`, the list name `Changed on Two Devices` and its 30-day, 20-row limit, "later name stays" for journals and the title suffix (a requirement) are the designer's, open to review.

## Independent review (2026-10-09)

**Verdict: revise and re-review** (sections 3.3.1, 3.4, 3.8, 5.2 and 5.3 and the test list; the rest is approved with the changes below). The direction is right: derived copy ids, "L stays the record" so the editor feels nothing, row 2 collapsing delete-versus-untouched, and keeping the wire unchanged are sound and the 1.0 compatibility argument holds for the paths I checked. But the coalescing rule can overwrite another device's edit, the design does not say what happens when a pull delivers several revisions of one record, and the new local tables are an archive-format change that the record says is not one.

Method: I read the proposal against `Store.swift` (`apply`, `recordConflict`, `keepChangedVersion`, `resolve`, `save`), `StoreServerVersions.swift`, `SyncReconciliation.swift`, `SyncEngine.swift` (`synchronizeOnce`, `push`), `StoreDeletion.swift`, `PermanentDeletion.swift`, `JournalLifecycle.swift`, `StoreReencryption.swift`, the server's `SyncEndpoints.cs`, `protocol/README.md`, `protocol/permanent-deletion.md`, `protocol/archive.md` and the conformance README. The file and line references in section 2 are accurate. I did not run anything.

### Blockers

**1. Several revisions of one record, and the coalescing rule (3.3.1, 3.8). Blocker.**
- The server's log keeps every revision and `GET /sync` returns them in cursor order (`SyncEndpoints.ReadPage`; `apply` is called once per change inside one `db.write`). Today a device that is dirty and pulls r1..rn keeps one conflict row: `recordConflict` replaces it only with a higher revision and `preserveSupersededConflict` moves the earlier ones to history. `keepBoth` inside `apply` as written (3.8) makes one copy per revision, each with a different derived id (the id hashes R). The usual path hides this, because `synchronizeOnce` pushes first and a 409 carries only `current`. It does not hide it when L waits for the writing pause (`writingPause` 2 s, `longestWritingWait` 30 s), for an image upload or for a retry time while a pull runs, or when `hasMore` splits a long catch-up over pages.
- The 10-minute coalescing is the only mitigation, and it is unsafe. (a) It uses the wall clock, so two devices that resolve the same conflict at different times get different results; this contradicts the claim in constraint 4 that the outcome is a pure function. (b) "Unedited" is defined by membership in the local `kept_copies` table, which leaves the table only when the person edits the copy on this device. Another device can edit the copy and sync the edit; this device then replaces the copy's content with a newer R under the same id, as a new revision over that edit. The replaced content goes to this device's local history only. That overwrites a concurrent edit, which AGENTS.md forbids. (c) It rewrites a record other devices have already pulled and may have open.
- Without coalescing there is a storm. Two devices typing in one entry: every push (after each 2 s pause) arrives at the other device, whose L is dirty, so each exchange makes a copy on each side. Several dozen "(other version)" entries in a few minutes is plausible, and nothing in 3.3.1 other than the unsafe rule bounds it.
- Fix: (i) Keep `conflicts` as the working set and resolve automatically at a defined point instead of inside `apply`: the end of a pull (`hasMore` false) and only when the record is not being written (`isBeingWritten`). Within the round only the latest R per record is used; earlier revisions go to the record's history as today. This gives one copy per record per round whatever the page boundaries, makes held rows (row 1) the same mechanism, and removes the need for the notice delay in 4.2, since nothing changes while the person writes. (ii) Drop the clock. If a copy from the previous round may be superseded by a descendant of the same R (same `deviceId`, higher revision), allow it only when the copy's stored payload is byte-identical to what this device wrote and nothing else has touched it; otherwise make a new copy. (iii) State the bound in the record (copies per record per round: at most one) and add tests (finding 7).

### Material

**2. Permanent deletion (3.4, 3.3.1, 3.7). Material, three separate points.**
- The recommended outcome revives the marked identity (`restoredFromDeletionID` + `deletedAt` = the marker's time). A simpler outcome exists that the record does not consider: keep the marker final and park the edited version as a new entry with a derived identity (derived from the record id and the edited version's bytes), `deletedAt` set, in Recently Deleted: today's Keep Entry as Copy, parked. Advantages: markers stay immutable tombstones; 1.0 devices need no `explicitRevival` rule and no review (they just receive a new entry), so the 1.0/1.1 table in 5.1 loses its only exception; the rule "a restoration naming an earlier deletion becomes a conflict" cannot bite; a second Delete Permanently on the parked entry is an ordinary marker. The cost is the loss of the original identity (its history was already removed by the marker). Put both outcomes in D1; as written the owner chooses between "revive" and "destroy the edit", and the second is already ruled out by AGENTS.md.
- A deliberate permanent deletion of an automatic copy is undone by the derivation. Copy C (id derived from R) is deleted for good on device A (marker). Device D, which never saw the marker, finds the same conflict later, derives C and creates it at base 0; the push gets 409 with the marker as `current`; row 4 then applies D1 and revives C everywhere. Fix: in rows 4 and 7, when the local version is an unsent automatic copy (it is in `kept_copies` and has base 0), the marker wins and the local copy is dropped; its content is R, which is still in the other record's history.
- 3.4 says the restored item "sits in Recently Deleted". `JournalLifecycleSnapshot` filters markers out of `parents`, so for an entry whose journal was also deleted for good, `location(of:)` returns `.unavailable(.missing)`, not Recently Deleted. The row text `deletedAndChanged` and the Show action then point to the wrong place. Say so in 3.4, give the Unavailable case its own sentence or put it in the journal's restored case (row 7 restores the journal too when it was edited), and test deletion of a journal with an entry edited elsewhere. Also: `availableTitle(db, for:)` depends on this device's other journal names, so "both devices compute identical bytes" is not true for journals; either define a deterministic number or drop the claim.
- The one-time pass (3.8) applies D1 to rows the person left pending in 1.0, including a deliberate Keep Deletion that was never confirmed. That reverses a pending deletion at upgrade time with nobody present. Acceptable if D1 is decided that way, but say it, list each such outcome in Changed on Two Devices as for the live path, and put it in the release note.

**3. "Same content" (row 2) is under-specified and partly wrong (3.2). Material.**
- A false "equal" loses an edit silently, and a false "different" only makes a copy. The contract must define equality field by field (title, document including block identities and image descriptions, date, journal, template reference, `archivedAt`, unknown fields). 3.1 lists only title, document, date and journal. `archivedAt`, `defaultTemplateID` and `restoredFromDeletionID` are neither compared nor merged.
- Row 2 merges `deletedAt` but takes `deletedWithJournal` from L. L live and R "deleted with the journal" gives a live-flag entry with `deletedAt` set and `deletedWithJournal` false, which later behaves as independently deleted and stays deleted when the journal is restored. Treat `(deletedAt, deletedWithJournal)` as one unit and take the pair from the version whose `deletedAt` is earlier.
- When the outcome equals R in content, adopt R's bytes and become clean (as `adoptSameContent` does) instead of re-pushing L with a new revision; today's `sameContent` paths do this and the proposal drops it.
- Restore on one device against delete on the other is resolved as "deleted wins" (row 2, "the one that is set"). That is recoverable and consistent, but say it in 3.6.

**4. The conformance fixtures do not pin the interoperable part (5.3). Material.**
- `conflict-resolution-v1.json` is described as pairs of decoded L and R. The copy id hashes R's plaintext bytes, so the vectors need R's exact plaintext text, not a decoded value. Also pin: UUID construction (a .NET `Guid` built from 16 bytes is mixed-endian; the fixture must give the final hyphenated string and Windows must test it), lower-case hex, the UTF-8 prefix, and that `records.md` already tells readers not to validate UUID version or variant bits (cite it, so Windows and Android do not reject version 8 ids).
- The pure function is the easy half. What diverges between clients is the orchestration: when resolution runs (finding 1), which revision the record is rebased on, replacing an unsent copy by an arriving one, base 0 pushes of a copy that exists on the server, marker interplay. Add scripted multi-device scenarios to `protocol/conformance/sync/` (event lists with expected final records per device), not only function vectors. Swift passing its own vectors does not show interoperability.
- Versioning: a new page `conflicts.md` v1 plus new fixtures, with `/v1` and existing fixtures untouched, is the right reading of AGENTS.md; no capability is needed because the server never sees a conflict. But the README sentence "The client retains its local version until an explicit resolution" and the reconciliation sentence are normative today. Say in `conflicts.md` that review-style handling (1.0) remains conforming for a client that predates it, that a client implementing automatic resolution must implement all of the page (equality, ids, restoration shape) and nothing less, and give the page its own version line in the README table. Do not claim "no bump" without that.
- The title wording is catalog text and may be localized; the contract must say that clients never parse it and that the replacement rule (not the title) decides sameness. Define what happens when R's title already ends with the suffix (the fixture is listed, the expected result is not).

**5. The new local tables are an archive-format change, and `kept_both` stores plaintext (5.2, 9). Material.**
- `protocol/archive.md` (Database): "A new migration is a change to the archive format and must keep older archives readable", and restore refuses extra schema objects. `kept_both` and `kept_copies` are new migrations in `journal.sqlite`, which Export Archive snapshots. Section 5.2 calls them local tables and section 9 does not list `archive.md` (nor the 1.1 archive record `1-1-archive-v2.md`). A 1.1 archive would be refused by 1.0 and by any reader built from the current page.
- `kept_both` keeps "name" (the other journal name) in clear text in a database whose payloads are otherwise sealed, and it would be copied into archives. `Reencryption.verifiedTables` and the schema check also need to know the tables.
- Fix: avoid tables. Keep what must persist in sealed `settings` keys or derive it: a `kept_copies` set is derivable as "records whose id equals the derivation of a stored R" only with R, so keep a sealed record of (copy id, record id) in `settings`; notes can store ids plus a history row id and read names at display time. If tables stay, list the migration in `archive.md`, coordinate with archive v2, exclude them from archives and from `validateSchema` complaints, and seal their content.

**6. Which version becomes the record (3.1, 3.3, 4). Material (usability).**
- "L stays" is the server's order, not recency. A device that was offline for a week with a stale edit becomes the main entry on every device, and the newer text is the "(other version)". On the other device the entry open on screen changes text with no explanation; the note and notice exist only on the device that resolved. The copy is in the list, titled, so nothing is lost, but the person sees recent work vanish from the entry they wrote it in.
- The design rejects clocks for ordering (correct), but the information is available for display: the copy keeps R's `modifiedAt` and the record keeps L's. Show it. The notice and list row should say when the other version was last changed when it is newer ("The other version is newer"), and the spec should state this limit plainly under Risks (it is currently only implied by 3.7).
- Optional, not required: for moved-versus-edited (3.7) the store keeps no ancestor. A sealed copy of the last synced payload per dirty record would allow independent-field merges (journal or date against text) and remove most "moved then edited" copies. State that it was considered.

**7. Tests (10). Material.** Add: a pull of several revisions of one record while L is dirty makes one copy; two stores alternately editing the same entry for N rounds end with a bounded number of copies and every text present; a remote edit of a copy is never replaced by a later conflict on this device; a deliberately deleted automatic copy is not revived by a late device (finding 2); delete-with-journal against live (finding 3); the pass with a Keep Deletion row; a mixed page of changes with a held record (row 1) and a normal one. Test 2 ("three replicas reconnect to a restored server") should also run with a page boundary inside the log.

### Minor

**8. Copy id privacy (3.3.1). Minor.** `SHA-256(prefix + recordID + SHA-256(plaintext))` lets a server (which sees record ids, kinds, times and the new id) test a guess of a short, template-like plaintext. The exact JSON includes block identities and timestamps, so a practical attack is unlikely, but a keyed derivation costs nothing: `HMAC-SHA-256(subkey, ...)` with a subkey derived from the library key (HKDF, a fixed info label) is the same for every device and every client, and hides the relation. In an unencrypted library the server reads plaintext anyway, so this changes nothing there. Also record in the metadata section that a conflict becomes visible to the server as a base-0 record created right after a pull.

**9. The one-time pass details (3.8). Minor.** Run it inside store opening before any sync can start, so a pull cannot replace a row's R first. Keep the existing preconditions from `resolve` and `deletionConflict` (revision match, payload match, `localRevision <= revision`) and say what happens to rows that fail them (they are a superseded review: move R to history, drop the row). Rows from imported archives have revision 0; say so. Idempotence across interruption is covered by test 7.

**10. The notice while writing (4.2). Minor.** Inserting a header above the title two seconds after a pause, with scroll compensation that "is checked in implementation", shifts layout under a person who is writing and may talk over VoiceOver typing echo. With finding 1's fix (resolve after writing pauses) show the notice when the entry is next shown or in place only if the editor is not first responder; drop the polite-announcement claim (UIKit has no polite priority; use `.announcement` with `accessibilitySpeechQueueAnnouncement` and the Mac's announcement priority, or none). Do not rely on a combined row element in Settings: a "Show" button inside a row read as one element is unreachable by VoiceOver unless exposed as a custom action; better, make the whole row the control (a tappable row with a disclosure), which is also the native pattern and drops the second tap target.

**11. Settings list and copy (4.3, 8). Minor.** "Deleted for good" is plain but differs from the Delete Permanently label used elsewhere; check the catalog and keep one phrase. The footer "Both versions are kept. This list clears after 30 days." is fine. The row sentence for journals should include the new name ("Renamed on two devices. The name is now “X”; the other was “Y”.") so it is readable without the title. The device whose name lost has no trail at all (D3 below). `messages.conflict.copyTitle` with "{title} (other version)" is acceptable; say that the 60-character cut counts extended grapheme clusters.

**12. Journals on step 1 (3.5, 6.1). Minor.** Row 7 and row 6 ("deleted if either is deleted") hide that a journal deletion cascades `deletedWithJournal` to entries, so a rename on A against a delete on B also meets edited-versus-deleted entries and gives "(other version)" entries in Recently Deleted. Mention it in the risks and test it with a journal that has entries. Step 1 ships with entries still using the review sheet, so the step-1 gate must include an entry conflict inside a journal that auto-resolves.

**13. Reconnect (7). Minor.**
- The label is acceptable: one word, familiar, same in all five places. For "server not set up" the first screen asks for a setup code, which is setting up again, not reconnecting. Keep the sheet title Reconnect but make the first-page text say what is asked ("Enter the setup code from your server" or the existing step text) so the person is not surprised; the states' messages already say what happened.
- For "No access" the device was removed on purpose: say in `accessRemoved` or on the first page that signing in again needs the master password or a connected device, otherwise the button invites a loop of failed attempts.
- The changed `accessLost` message "Reconnect in Settings ▸ Sync, then try again" is fine; `signInNeeded` and `turnedOnElsewhere` will disappear with G, as the record says; do not spend a review cycle on them.
- Devices showing the sync state's own message resolves A14; test it with the device removed and with the server replaced.

**14. Owner decisions (12). Minor.**
- D1 is genuine but mis-framed: add the parked-new-identity option (finding 2) and say which AGENTS.md rule the second alternative breaks, so the owner can accept it knowingly or not at all.
- D2 is not an owner decision. Without the suffix, other devices (and 1.0) show indistinguishable duplicates, and marking only on the resolving device leaves the other device with no explanation. Record it as a design decision with the reason and leave only the wording to the owner.
- D3 is genuine but low stakes; the real question is whether a rename that loses has any trail on the device that wrote it (today: none). Decide it as designer; "later name stays" is consistent with the library record. Mention the lost trail in the risks.
- Items "decided here": `Reconnect…`, `Changed on Two Devices`, 30 days and 20 rows are fine. The two-second pause goes away with finding 1. Step 2 may slip to 1.1.1, as the record says.

### What I checked and found sound

- Constraint 5 (the record's bytes unchanged, so the open editor and `storedVersion` do not see the resolution) matches `save`, which compares stored versions by payload; and the editor already adopts external changes through `EditorSession`/`ExternalEdits`, so the stale-save path is narrow.
- Reencryption keeps exact plaintext bytes (verified in `verify(copy:)`), so hashing R's plaintext is stable across protection changes. Retried operations keep immutable bytes; `rebaseQueuedChange` already replaces an outbox row with a new operation; a copy created at base 0 whose id exists on the server gets a 409 and `adoptSameContent` or the replacement rule handles it.
- Images: sharing attachment ids is safe; `referencedAttachmentIDs` counts every record, history row and conflict, and permanent deletion keeps files.
- 1.0 compatibility: restoration naming the marker is already accepted by a 1.0 device with the marker and no local change (`explicitRevival` in `apply`); a 1.0 device with a local change keeps its review; nothing on the wire changes.

### Resolution

Not yet resolved. Items to carry into the revision: 1 (resolve once per round, no clock, safe replacement), 2 to 7 (decide and write), 8 to 14 as listed. The revised record is re-reviewed before implementation, limited to sections 3.2 to 3.4, 3.8, 5 and 10.

## Changes after review

Revision 2 of the body (2026-10-09). The review above is kept unchanged; each finding and what happened to it.

| # | Finding | What changed |
| --- | --- | --- |
| 1 | Blocker: several revisions of one record; unsafe wall-clock coalescing | Adopted the reviewer's direction. The `conflicts` table stays the working set and keeps only the latest R per record (earlier ones to history); resolution runs once per record, at the end of a sync round after the pull (any page count), at store opening, and never for a record being written or with a failed save (3.8). The 10-minute rule is gone. A copy is replaced only by a later version from the same origin device when its stored payload is byte-identical to what this device wrote and nothing touched it (3.3.2); a copy edited elsewhere gives an ordinary conflict, never an overwrite. The bound and a worked three-device example are in 3.8, the co-editing argument and its scenario in 3.8 and section 10. Constraint 4 now says both the function and the orchestration are specified, without time. Finding 10's notice delay disappears with this. |
| 2 | Permanent deletion: parked new identity; revival of a deleted copy; Recently Deleted location; `availableTitle`; the pass | Evaluated the parked option and adopted it: no concrete flaw, fewer special rules (markers stay final, no restoration rule, no 1.0 exception, the same conflict on two devices is a no-op). Entries and templates are parked with a derived id and the marker's time; journals against a marker create nothing and say so in a note (3.4). An unsent automatic copy never revives a marker (3.3.2). The location is stated correctly: Recently Deleted when the journal is live, Unavailable Journals when it is gone (revised in the second review: Restore, not Move Entry); the row text no longer names a place. The claim of identical bytes for journals is dropped with the journal restoration. The pass makes pending deletions final and parks the edit, lists each outcome and names it in the release notes (3.4, 3.9, risks). |
| 3 | "Same content" under-specified; deletion unit; adopt R; restore against delete | Field-by-field equality for each kind, strict by design (3.2.1); `(deletedAt, deletedWithJournal)` merged as one unit from the earlier deletion (3.2.2); an outcome equal to R adopts R's bytes and sends nothing (row 2); restore against delete stays deleted and is stated (3.2, 3.6). Journals compare `title` and `defaultTemplateID`. |
| 4 | Fixtures did not pin the interoperable part | Plaintext text of L and R in the vectors; exact UUID construction, lower-case hex, UTF-8, the `Guid` trap, and that readers must not validate version or variant bits (the page states it; `records.md` does not, so the earlier "already says" claim is not made) (3.3.1, 5.3). Scripted multi-device scenarios in `protocol/conformance/sync/conflict-scenarios-v1.json`. `conflicts.md` states that review-style clients stay conforming, that automatic clients implement all of it, and has its own version line. Titles are catalog text that clients never parse; the suffix is always appended, a copy of a copy reads twice, which is deterministic. |
| 5 | New tables are an archive change; plaintext names | Rejected tables. Only the existing `conflicts` table plus one sealed `settings` key `kept-notes` (AAD `journal:v1:local:kept-notes`, re-sealed like `library-changes`); readers already ignore unknown keys, so 1.0 opens 1.1 archives; no migration, no archive format number (constraint 7, 5.2). Coordination with `1-1-archive-v2.md` in prose: it carries one sentence in the Settings keys paragraph and keeps the ignore-unknown-keys rule; that record is not edited. The notes sealed key also seals the journal names. |
| 6 | Which version becomes the record | Stated plainly as the server's order, not recency (3.1, risks 3). The notice and the list row use "newer" wording when the other version's modified time is later, as a clock hint that never decides anything (4.2, 4.3, section 8). The ancestor-copy idea is described and deferred (3.7). |
| 7 | Missing tests | Added: several revisions in one pull; alternating-edit bound; remote edit of a copy never replaced; deliberately deleted copy not revived; delete-with-journal against live; the pass with a Keep Deletion row and with superseded and revision-0 rows; a mixed page with a held record; the three-device test also across a page boundary; the journal cascade; the sealed key (section 10). |
| 8 | Copy id privacy | Keyed derivation: HKDF subkey from the vault key and HMAC-SHA-256; public key constant in unencrypted libraries; the base-0 visibility noted for SECURITY.md (3.3.1). |
| 9 | Pass details | Runs inside store opening before any sync; keeps the `resolve` and `deletionConflict` preconditions; failing rows are superseded reviews (R to history, row dropped, note); archive rows have revision 0 (3.9). |
| 10 | Notice while writing; announcement; row as one element | Resolution never happens while writing; the notice appears in place only if the editor is not the first responder, otherwise on next show or resignation; no announcement; each Settings row is one control with a disclosure, label and hint, plain text when there is nothing to open; `showFor` and `announce` keys dropped (4.2, 4.3, section 8). |
| 11 | Settings list and copy | "Deleted permanently" matches the catalog; the journal sentence has the new name; the grapheme-cluster cut is stated (3.3, 4.3, section 8). |
| 12 | Journals on step 1 | The cascade is in 3.5, the risks and the tests; the step 1 gate includes an entry conflict inside a journal that auto-resolves (6.1). |
| 13 | Reconnect | Label kept. The server-not-set-up first page is the existing Set Up Server step whose footer already says what is asked (no new text). `messages.sync.accessRemoved` now says what signing in again needs. The reviewer's advice to leave `signInNeeded` and `turnedOnElsewhere` alone is followed (they stay as changed, and go with G). Devices tests added for both cases (7.2, section 10). |
| 14 | Owner decisions | The suffix is a requirement, no longer a decision. The journal name is decided by the designer and stated as a risk. The permanent-deletion question is decided as parked-and-final, leaving only where the parked entry sits. Two decisions remain (section 12). The two-second pause is gone. |

## Second independent review (2026-10-09)

**Verdict: approve with changes.** No Blocker. Every finding of the first review is resolved in the body, not only claimed: the working-set and end-of-round resolution (3.8), no clock in the copy rules (3.3.2), the parked marker outcome (3.4), field-by-field equality and the deletion unit (3.2.1, 3.2.2), the exact id construction (3.3.1), no new table (5.2, verified below), scripted scenarios (5.3, 10), the pass details (3.9), the notice and list behaviour (4), and the Reconnect copy (7.2). The revision introduced four Material gaps, all in rules that 3.3.2, 3.4 and 3.8 do not yet state; each is a sentence or two in `protocol/conflicts.md` plus a scenario, not a redesign. They must be written into the body (or the contract page and its scenarios) before step 2 is implemented, and the library record needs one matching edit (finding 4). No full third review is needed; the owner of this record should confirm the edits against findings 1 to 4.

Method: I read the revised body against `Store.swift` (`apply`, `recordConflict`, `preserveSupersededConflict`, `keepChangedVersion`, `moveEntry`, `restoreAndMoveEntry`, `pending`, `validateSchema`), `SyncEngine.swift` (`push`, `readyToSend`), `SyncReconciliation.swift` (`isBeingWritten`), `StoreReencryption.swift` (`adoptSameContent`, `sameContent`, `sealLibraryChanges`, `restart`), `JournalLifecycle.swift` (`location(of:)`), `AgentCopyPublisher.swift`, `protocol/README.md`, `records.md`, `permanent-deletion.md`, `journal-lifecycle.md`, `archive.md` and `1-1-archive-v2.md`. I did not run anything.

### Convergence, bound, id, parking, pass, archive: what I re-checked

- **Three devices with offline edits and the worked example (3.8).** Traced in both sync orders and with C resolving against r6 instead of r7: E ends as the last pusher's text on every device; every overwritten version is copied by the device that overwrote it (it sees the current version as R through the 409 or the pull); a second creation of the same derived copy gets 409 and is adopted by the existing `adoptSameContent` when the plaintext is identical, and by the "arriving version wins" rule of 3.3.2 otherwise. A page boundary does not matter because resolution waits for `hasMore` false. The restored-server case also converges (a device whose clean record differs from the restored server's becomes the record, the server's text becomes the copy). Defects found: findings 1, 2 and 6 below.
- **Bound.** "One resolution per record per round" holds. The alternating co-editing argument holds as long as every copy is replaced under its own id and the replacement conditions of 3.3.2 hold; but the replacement rule has a side effect on identity (finding 2) that the "one copy however many devices find it" claim does not account for.
- **Keyed id (3.3.1).** HKDF with an empty salt, the info string, HMAC over a fixed prefix, record id and text digest, version and variant bits forced, string built from bytes: complete and portable. Password change keeps the vault key (`protocol/README.md`, `/recovery/password`), so ids are stable across it. Turning encryption on creates a new key (and is removed by G), so the same R would derive a different id before and after; harmless but worth one sentence (finding 9). `records.md` says UUIDs compare case-insensitively and does not say version bits are unvalidated: the design now says so itself, correctly.
- **No archive-format change.** Verified: `validateSchema` compares only `sqlite_master` against a freshly migrated database, so a settings row cannot fail it; `protocol/archive.md` already says "Readers ignore keys they don't know"; `1-1-archive-v2.md` carries the `kept-notes` sentence (its line 135 and 473). `library-changes` is the working precedent, including re-sealing in `StoreReencryption`. The claim stands.
- **Parking and the pass.** Marker final, edit parked with a derived id: sound, and an unsent automatic copy meeting a marker is dropped. The pass at store opening with the old preconditions is sound for rows 1.0 left (qualified in finding 8).

### Material

**1. The derived copy id may already exist locally, and 3.3.2 does not say what then (3.3.2, 3.8). Material.** A copy created by another device can reach this device before this device resolves: a page that ends between the copy and the new record revision (the pusher sends the copy before or after the record in outbox order), or a device that resolves after pulling a copy of R that it also derives. The design covers an unsent local copy meeting an arriving one, and a copy this device wrote itself, but not "the derived id exists as a clean, edited, deleted or permanently deleted record that this device did not make". An implementation that writes the copy under that id replaces another device's edit of the copy, or revives a copy the person deleted (a normal deletion keeps the record, so the id exists) or permanently deleted (the marker). Fix: add to 3.3.2 and the contract: if a record with the derived id exists locally in any state, do nothing (no write, no note); the existing record is the copy. Add scenarios: the copy arrives before the record revision; the copy was deleted on another device; the copy was permanently deleted on another device (parked entries too); the copy was edited on another device.

**2. Replacing a copy under its old id breaks "id = f(R's text)", and a stale-save origin is the nil device (3.3.2, 3.8). Material.**
- After B replaces cA's content (a to a2) under cA's id, another device C that resolves against the same R (a2) before B's push lands derives a different id (from the text a2), so a2 exists twice, once as cA and once as the new copy. This contradicts "the same copy is made once however many devices find the conflict" and test 5 for any run that includes a replacement, and it is not caught by the three-device example because it has no replacement. Bounded and lossless, but it breaks the interop promise (and the number of copies in the scenario files depends on timing). Fix: either (a) state the exception ("at most one extra identical-content copy when two devices meet the same R while one replaces an earlier copy"), assert exactly that bound in scenarios 3 and 5, and keep the rule; or (b) derive the id of a copy from the record id and the origin device (one copy per other device per record) and let a later R from that device always replace an untouched copy; then a second device creating the same id gets 409 and the "arriving version wins" rule decides. (b) removes the duplicate and the need for the text in the id; pick one and write it into the contract.
- `keepChangedVersion` stores the nil UUID as the device ("Stored versions don't record their device", `Store.swift`). 3.3.2's "same origin device" would match nil to nil across different real devices. Fix: a nil or unknown origin never matches; such a copy is never replaced, a new one is made.

**3. The editor under an entry that becomes a marker (4.2, constraint 5, 3.4). Material.** Constraint 5 says resolution never changes what the editor holds. That is true for row 3, not for row 4: the open entry's record becomes the marker and the edit is parked as another entry. The design shows no notice for this case (4.2 covers only the "other version" notice) and says nothing about the open editor. Keep typing and the next save hits the "a save made from a copy read before a marker arrived becomes a conflict" rule, which now resolves at the next round into another parked entry per pause. Fix: state in 3.4 that when the resolved record is the open one, the app moves the open editor to the parked entry (same text, no loss of the cursor or draft) and shows the deletion note there; if the editor is the first responder, do it on the same terms as 4.2 (not under a resting cursor mid-typing: queue it, and until then the draft saves into the parked entry). Test: typing continues across the resolution and produces one parked entry. Also say in constraint 5 that rows 2 and 4 to 7 can change the open record.

**4. A parked entry in Unavailable Journals cannot be recovered with Move Entry (3.4, cross-record with N). Material.** 3.4 sends a parked entry whose journal is gone to Unavailable Journals "from where Move Entry brings it into a journal". `moveEntry` refuses a deleted entry (`guard entry.deletedAt == nil, !entry.deletedWithJournal`, `Store.swift:263`), and the parked entry has `deletedAt` set; today the only way out is `restoreAndMoveEntry`, which [1-1-library-simplifications.md](1-1-library-simplifications.md) (N) deletes in favour of `restoreEntry(_:fallback:)`, whose rule table has no row for "own tombstone, journal missing or permanently deleted" (and `protocol/journal-lifecycle.md` says ordinary missing-parent entries are read-only). Result: a parked entry whose journal was permanently deleted would be stuck. Fix here: say the entry is recovered with Restore and name the destination, then fix the library record (its second-review finding 1). Alternative here: when the journal is gone, park the entry live (no `deletedAt`) so Move Entry works; I prefer Restore because the entry then stays "deleted" consistently.

### Minor

**5. Trigger points for resolution without a server round, and during reconciliation (3.8, 4.5). Minor.** 4.5 says a stale-save row "resolves at the next round, offline too if the other version is already local", which is contradictory, and a library with no server never runs a round. Say: resolution runs at store opening, at the end of a completed pull (also when a push failed for an unrelated record), after a local merge or import, and after a stale save when no server is configured; it never runs while a reconciliation is in progress (`settings.reconcile` present), because the row's revision and R are not final until the whole restored log is compared.

**6. The worked example's history claim does not match the code order (3.8). Minor.** C's push is refused first (row R = r7), then the pull delivers r6; `recordConflict` only replaces with a higher revision and `preserveSupersededConflict` moves the previous row to history only when the new change is higher, so r6 is dropped on C, not placed in history. Nothing is lost (B's copy holds it) but the sentence is wrong. State the real invariant instead: the device that overwrites a server version copies it, so no version needs a copy from a device that never saw it; add it to test 2 as an assertion that every version in the server log is in some record, copy or history of the final state.

**7. Two rules that are not deterministic across devices (3.2.2, 3.6). Minor.** 3.2.2 chooses the deletion pair by the earlier `deletedAt`, which is a device clock value and contradicts constraint 3; use a rule without a clock (for example deleted-with-journal wins, else R's pair, and say it only matters for legacy `deletedWithJournal`). 3.6 skips the copy "when this device already holds the content in the record's Version History": history is local, so two devices make different copies, and it cannot be a conformance scenario. Drop it, or move it out of the contract as a local optimization that scenarios do not cover. Also decide whether a conflict where only `blockIDs`, `segmentLengths` or `imageTypes` differ is "different" (a copy with identical visible text); strictness is defensible, but add a case to the fixture so every client agrees.

**8. Open-time pass versus rows made by 1.1 (3.8, 3.9). Minor.** 3.8 runs `resolveConflicts()` at every store opening, so a 1.1 row left by a crash in the middle of a paged catch-up resolves against an intermediate R and makes a copy of a superseded version. The "before any sync" reason applies to rows 1.0 left (their R is what the person saw). Restrict the open-time pass to rows from 1.0 and imports, or to libraries with no server; leave 1.1 rows to the next completed pull.

**9. Sealed key hygiene and ids across modes (5.2, 3.3.1). Minor.** Say that the digest in `copies` is of the plaintext written (so it survives re-sealing and turning encryption on), that parked entries are recorded in `copies` too (the marker rule needs it), that `copies` is pruned (drop an entry when its record is gone, no longer matches, or after a bound such as 200 entries), and that ids of copies made before turning encryption on differ from those derived after it (rare, G removes the transition). Use a distinct label for parked ids (`conflict-park`) so a parked entry and a copy of the same version never collide with different fields.

**10. Journal rename: the losing name's trail (3.5, 4.3, risks 4). Minor.** With K the history rows nothing shows, so the 30-day note on the resolving device is the only trail of the losing name, and Clear List erases it without confirmation. Keep journal-rename notes until the person clears them, or exempt them from the 30-day expiry (the list is capped at 20 rows). Also row 6 silently takes L's `defaultTemplateID` when names are equal and templates differ (a 1.0 device's choice is overwritten with no note); say so in 3.5, since no 1.1 UI shows the field.

**11. Stale statement about journal deletion (3.5, risks 2, test 9). Minor.** The code and the library record agree that deleting a journal sets only the journal's `deletedAt`; its entries are deleted by inheritance (`location(of:)`), and `deletedWithJournal` is only set by earlier versions. So "a journal deletion cascades `deletedWithJournal` to entries" and the derived "(other version)" entries in Recently Deleted do not arise from current writers. Keep the test (journal renamed against deleted, entries edited in it) but correct the text; only legacy `deletedWithJournal` entries exercise 3.2.2.

**12. Protocol wording (5.3). Minor.** Do not replace the README sentence "The client retains its local version until an explicit resolution" outright. Keep it as the baseline behaviour and add: "A client that implements conflicts.md resolves automatically instead." That keeps 1.0 conforming without relying on the carve-out alone, and it makes the contract change additive, which fits the AGENTS.md rule better than editing a normative sentence under an unchanged version.

**13. Reconnect copy (7.2). Minor.** `messages.sync.accessRemoved` says "you need your password or a connected device". For an unencrypted library (still possible in 1.1 until G ships) there is no master password; the way back is the server's recovery code. Either word the sentence by library mode or accept it only if G ships in the same release. Also `messages.conflict.kept.rowHint` "Shows it." is vague as a VoiceOver hint; "Opens it." matches the platform pattern.

### Owner decisions: are they genuine?

- **Where the parked entry sits** is genuine (product placement, with a real cost either way); the recommendation is right and finding 4 does not change it.
- **Step 2 in 1.1 or 1.1.1** is a schedule decision with explicit gates; it is acceptable as an owner decision because it changes what 1.1 shows people (the entry review sheet stays). It could also be decided by the gates alone; if the owner wants fewer questions, say "step 2 ships when its gates pass".

### Resolution

First-review findings: all resolved in the body. New: findings 1 to 4 (Material) must be written into the body or the contract page before step 2; step 1 (journals, markers) can start once finding 3 and 4 are decided, since they affect row 4 and 7. Re-review limited to 3.3.2, 3.4 and 3.8 after the edits.

### Second review: findings and what changed

| # | Finding | What changed |
| --- | --- | --- |
| 1 | The derived copy id may already exist locally | 3.3.2 step 1: if the derived id exists locally in any state, do nothing (no write, no note, no revival); the record side still resolves. Scenarios for each state (arrived before the record's revision; edited, deleted, permanently deleted elsewhere, parked entries included; made earlier here) in 5.3 and section 10. |
| 2 | Replacement vs id derivation; nil origin | Kept text-derived ids and stated the bound (3.3.2): one identical extra copy per replacement, lossless, asserted by scenarios 3 and 5 rather than claiming zero. A nil or unknown origin never matches and is never replaced; a test and a fixture case cover it. Rejected deriving from record plus origin device because an edited or deleted copy of an earlier version would then block the later version's content from being saved. |
| 3 | Open editor under a marker | 3.4 and constraint 5: the open editor is re-targeted to the parked entry within the resolution (text, draft and cursor kept), the note follows 4.2's terms, and a test covers typing across it with one parked entry. Constraint 5 says rows 2 and 4 to 7 can change the open record. |
| 4 | Parked entry in Unavailable Journals | Recovered with Restore into the Default Journal, not Move Entry (3.4, 3.2 table, 6.3). The fallback row belongs to 1-1-library-simplifications.md; step 1's gate requires it. |
| 5 | Trigger points; reconciliation | 3.8 step 2 lists them (completed pull, also after an unrelated push failure; opening for old and imported rows; local merge or import; stale save with no server) and forbids resolving while `settings.reconcile` is present; 4.5 corrected. |
| 6 | Worked example history claim | Corrected (r6 is dropped on C, held by B's copy); the invariant is stated and asserted in test 2. |
| 7 | Clock in deletion pair; local-history check; strictness | 3.2.2 uses `deletedWithJournal` true else R's pair, and notes it matters only for legacy entries; the local-history skip is removed from 3.6; a blockIDs/segmentLengths/imageTypes-only difference is "different", with a fixture case. |
| 8 | Open-time pass vs rows made by 1.1 | 3.9: the pass takes only rows from before the 1.1 install (flag in the sealed key) and imports, plus any row when no server is configured; a 1.1 row left by a crash waits for the next completed pull. |
| 9 | Sealed key hygiene; ids across modes | 5.2: digest of plaintext, parked entries in `copies`, pruning at 200, ids differ before and after turning encryption on (G removes it), distinct label `conflict-park` (3.3.1). |
| 10 | Rename trail; template overwrite | Rename notes do not expire (4.3, risks); 3.5 states that row 6 takes L's template without a note. |
| 11 | Stale cascade claim | Corrected in 3.5, 3.2.2, the risks and tests: deleting a journal sets only its `deletedAt`; `deletedWithJournal` is legacy. |
| 12 | Protocol wording | 5.3 keeps the README sentence and adds "A client that implements conflicts.md resolves automatically instead." |
| 13 | Reconnect copy | `messages.sync.accessRemoved` for libraries with a password; new `messages.sync.accessRemovedNoPassword` (connected device or recovery code); hint reads "Opens it." |
| Owners | Decisions | Only "where the parked edit sits" remains (recommended: Recently Deleted). Step 2's release is decided by its gates (6.2). |
| Lead | Key ownership; Restore | Key lists follow the library record's ownership (section 8, 6.1, 6.2); every parked-entry recovery says Restore. |
