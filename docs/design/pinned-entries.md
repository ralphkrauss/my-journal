# Pinned entries

Status: current, built 2026-10-03; implementation notes at the end. Reviewed proposal, 2026-10-03. It includes the shared **library record** that [journal-order.md](journal-order.md) also uses. The independent review is recorded at the end.

## Request

Owner: "Need to be able to pin entries in a journal. For the design: use the building blocks that we already have. Apple Notes does this by using 'Pinned' as a subtitle instead of the date. Use the same design that we already have within a journal entry list."

How this reads the request: in Notes the list's sections are named after dates ("Today", "September"), and pinned notes sit in a first section named "Pinned". Our list has month sections ("October 2026"). A **Pinned** section goes above them, with the same header style and the same rows. Rows keep their date line, because dates belong in the list (AGENTS.md). Open decision D1 covers the other reading, where a pinned row shows "Pinned" in place of its date.

## The list today

The list is in `RootView.swift`, and its sections come from `AppModel.entryGroups`.

- **Sections:** one per month, "LLLL yyyy" ("October 2026"), newest first. Entries are sorted by entry date, newest first, then by ID.
- **Row:** a date line (day and short month, caption, secondary), the journal label in All Entries, the conflict indicator, the title (medium weight, one line), and a one-line preview ("No additional text" when there is none). At accessibility sizes the date and journal stack and the title wraps.
- **Trailing swipe:** Delete. **Leading swipe:** Restore, in Recently Deleted only.
- **Context menu and Entry Actions** (the iPhone and iPad editor's "…" and the Mac toolbar's Entry Actions) share `entryActionCatalog`: Change Date…, Move Entry…, Save as Template…, Image Descriptions…, Version History…, —, Delete Entry.
- **Mac menu bar File menu:** New Entry, New Blank Entry, New Entry from Template…, New Journal…, —, Import Archive…, Export Archive…. The iPad has the same menu bar.

## Design

### Where the Pinned section appears

| Collection | Pinned section | Why |
| --- | --- | --- |
| A journal | Yes: that journal's pinned entries | The request. |
| All Entries | Yes: pinned entries from every journal, with their journal labels as usual | Notes shows pinned notes in "All iCloud" too. A pin marks an entry as important wherever it is listed, so it shouldn't depend on which view is open. All Entries is a common starting view on the Mac and iPad. |
| Recently Deleted, Unavailable Journals | No | Deleted and unavailable entries can't be pinned or unpinned. A deleted pinned entry is listed with the other deleted entries under its month. |
| Templates | No | Templates can't be pinned. |

- The section is titled **Pinned**. It uses the same section header as the months: plain on the Mac (`.inset`) and inset grouped on iOS. It has no icon and no count.
- It contains each pinned entry in the collection, newest entry date first, then by ID: the list's own order. A pinned entry appears only there, never also under its month.
- There is no Pinned section when nothing in the collection is pinned. The month sections follow it unchanged. A journal whose entries are all pinned shows only the Pinned section.
- Rows are unchanged. There's no pin badge, because the section header already says it. For VoiceOver, a pinned row's accessibility value is "Pinned", so the state is announced even when the header is skipped, for example with the rotor.
- The section can't be collapsed. Notes on iOS can collapse it; that can come later if wanted.

### Searching

The search field filters the list it is in, and the sections stay as they are: pinned matches stay under **Pinned**, and other matches stay under their months. This is how the month sections already behave, so the list looks the same, only with fewer rows. The iPhone Journals screen's search ("Search All Entries") is a flat list of results sorted by date, with no sections; it stays that way.

### Pin and Unpin

| Place | Not pinned | Pinned | Symbol |
| --- | --- | --- | --- |
| Leading swipe (iPhone, iPad, Mac trackpad) | **Pin** | **Unpin** | `pin` / `pin.slash`, accent tint (as Restore uses); a full swipe performs it |
| Row context menu | **Pin Entry** | **Unpin Entry** | `pin` / `pin.slash` |
| Entry Actions ("…" in the iPhone and iPad editor, Entry Actions in the Mac toolbar) | **Pin Entry** | **Unpin Entry** | the same |
| Mac and iPad menu bar, File menu | **Pin Entry** | **Unpin Entry** | — |

- **Position in the menus:** Pin Entry is the first item of the entry group, before Change Date…: [Pin Entry, Change Date…, Move Entry…, Save as Template…]. In Notes, Pin Note is at the top of a note's menu. The labels match "Delete Entry" and "Move Entry…", and have no ellipsis because they act at once.
- **File menu:** after New Journal…, in its own group: New Entry, New Blank Entry, New Entry from Template…, New Journal…, —, **Pin Entry**, —, Import Archive…, Export Archive…, then on the Mac —, Delete All in Recently Deleted… (added by ios-delete-all-and-settings-2026-10-03.md). It acts on the selected entry. It is disabled when no entry is selected or the selected entry can't be pinned. There is no shortcut, as in Notes.
- **Undo (Mac and iPad):** Edit ▸ **Undo Pin Entry** or **Undo Unpin Entry**, registered with the window's undo manager as Undo Delete Entry already is.
- **Who can be pinned:** an entry listed in a live journal (`EntryLocation.journal`), while My Journal is unlocked and not replacing its library. That includes an entry this version can only read, or an entry with changes to review: pinning doesn't change the entry's record (see the data design), so it can't conflict with its content. Entries in Recently Deleted or Unavailable Journals, and templates, have no Pin action.
- **No confirmation and no message.** The row moves into or out of the Pinned section with the list's usual animation, or none with Reduce Motion, as deletion does.
- **Selection:** a row's actions don't change the selection, as for the other row actions. When the selected entry moves, it stays selected and the list scrolls just enough to keep it visible. Pinning another row from its context menu doesn't scroll. On iPhone, pinning from the editor's "…" leaves the entry open; going back shows it under Pinned.
- **Previous Entry and Next Entry** (⌥⌘↑, ⌥⌘↓) and choosing the next entry after a deletion follow the order on screen, so Pinned comes first. Both use the list's order (`listedIDs`), which includes the Pinned section.

### What a pin does over an entry's life

| Event | Pin |
| --- | --- |
| Edit, Change Date, Image Descriptions | Kept. A new date reorders the entry within Pinned. |
| Move Entry to another journal | Kept: the entry is pinned in its new journal. As in Notes, a pin belongs to the entry. |
| Delete (to Recently Deleted) | Kept but not shown. The entry is listed under its month in Recently Deleted. |
| Restore, Restore and Move, or restoring its journal | It comes back pinned, in its journal's Pinned section. Restoring returns an entry as it was. |
| Delete Permanently, including emptying with Delete All | No longer shown (keys for permanently deleted records are ignored). The key is removed by the next change to pins or order (see the data design). |
| Save as Template, New Entry from Template, a copy from Version History, Keep Entry as Copy | The new entry or template isn't pinned. Copies are new items. |
| Version History: restoring an earlier version | Unchanged. A pin is not part of an entry's versions. |
| Export Archive, then restore it on an empty device | Kept. |
| Import Archive into a library that already has journals | Kept for the imported entries; their new identities are pinned. |
| Merging a journal into another (Merge Into…) | Kept: merged entries keep their identities. |
| Agent access | Not exposed. Agents receive entries as today. Exposing it is a later decision. |

### Mockups

iPhone, a journal's list:

```
‹ Journals          Work                   (…)
┌──────────────────────────────────────────┐
  PINNED
  3 Oct
  Quarterly goals
  Ship the sync release, then …
  ──────────────────────────────────────
  12 Aug
  Interview notes
  Three questions to ask next …
  OCTOBER 2026
  2 Oct
  Standup
  Nothing blocking today …
  SEPTEMBER 2026
  …
└──────────────────────────────────────────┘
 [ Search Work                    ] [ ✎ ]
```

Leading swipe on an unpinned row: `[ 📌 Pin ]` in the accent tint. On a pinned row: `[ Unpin ]` with `pin.slash`.

On the Mac and iPad the content column has the same sections, and the editor's detail column doesn't change.

## Accessibility

- **VoiceOver:** the section header "Pinned" is a heading, as month headers are. A pinned row's value is "Pinned". Swipe actions are exposed as the row's actions ("Pin", "Unpin"), as Delete is today. After Pin or Unpin from a row action, VoiceOver focus stays on the moved row, and the app announces "Pinned" or "Unpinned". Without the announcement, focus would silently land on another row. The row moves to another section, so its view is recreated: focus must be set again (with the existing `returnedRow` binding) after the list has updated. Verify this on a device.
- **Keyboard:** on the Mac, File ▸ Pin Entry acts on the selected row, and the context menu opens with the keyboard as usual. On the iPad with a keyboard, the File menu command appears in the ⌘ overlay.
- **Dynamic Type:** the header and rows use the existing styles, and rows wrap at accessibility sizes as they do now.
- **Increase Contrast, Reduce Transparency:** system section headers and the swipe tint adapt. No new colors.
- **Reduce Motion:** no movement animation, as deletion already does.

## Empty, offline and error states

- **Empty:** no Pinned section. Collections keep their existing empty states ("No Entries", "No Results").
- **Offline:** pinning is stored on the device at once and synced later, quietly, as edits are.
- **Server too old to sync pins** (it doesn't list the capability; see the data design): pins work on this device. While such a server is connected *and* this device has pins or order changes it couldn't send, Settings ▸ Sync shows the footer **"Pinned entries and journal order stay on this device until the server is updated."** There is no sync error, no Sync Status indicator and no "Not on Server Yet" count: nothing has failed, and only the server's administrator can act on it.
- **Saving fails:** the existing error alert says **"Couldn’t pin the entry."** or **"Couldn’t unpin the entry."**, and the row stays where it was.
- **Another device pins or unpins at the same time:** no message and no review. See "Conflicts".
- **A library record written by a newer version** that this one can't read (a higher `version`): pins aren't shown, the order falls back to names, and Pin and Unpin, dragging and the Move Up and Move Down actions are hidden rather than shown disabled without an explanation. The Settings ▸ Sync footer reads **"Update My Journal to use pinned entries and journal order."** This is rare.

## Data and sync design

### What the current format allows

- **The record format is closed.** `PortableRecord.decode` checks every top-level key against a fixed list (`knownRecord`). A record with any other key is kept byte for byte, but its document version is set to `Int.max`, which makes it read-only ([records.md, Reading rules](../../protocol/records.md#reading-rules)). Nothing is discarded, but the record can no longer be edited.
- **Read-only journals hide their entries.** `JournalLifecycleSnapshot.location(of:)` returns `.unavailable(.unsupported)` for every entry whose journal isn't editable.

So, for a device on build 12 or earlier:

- a `pinned` field on an entry would make every pinned entry read-only there ("Update My Journal to edit this entry.");
- an order field on journals (journal-order.md) would make every reordered journal unsupported, and all of its entries would move to Unavailable Journals.

**Content conflicts.** The sync contract turns any two changes to one record into a review: the save of a stale copy, a refused push, or an incoming change while a local change waits. If pinning wrote the entry record, pinning on the iPhone while the Mac sent a typing pause for the same entry would ask the person to review "changes from another device" for a pin. Avoiding that would mean adding a field-level automatic merge to the content conflict path, which is the part of the app with the strictest rules ("Never silently … overwrite conflicting edits").

**History noise.** An entry write can create a Version History checkpoint, and `modifiedAt` means "when the writing device last changed the record".

### Proposal: one library record

Pins and journal order live in a new record kind, **`library`**: one record per library that holds small arrangement values shared across the library. The record types that hold content stay unchanged.

```json
{
  "id": "<the fixed library-record UUID>",
  "kind": "library",
  "modifiedAt": "2026-10-03T12:00:00Z",
  "title": "Pinned Entries and Journal Order",
  "values": {
    "journal-rank/0f8e…": "V",
    "journal-rank/5a21…": "k",
    "pinned/9c3d…": true
  },
  "version": 1
}
```

- **Identity:** one fixed UUID, written into records.md, the same in every library. Because every library has it, it must never count as evidence that two libraries are the same: `SyncLineage` (`syncedRecordIDs()` and the lineage scan used by `ServerJoining` for servers without encryption) ignores kind `library`. Build 12 doesn't know this, so a build 12 device joining such a server may misjudge two libraries as one; this is documented in the protocol as a known limit of older versions.
- **Why one fixed ID:** Each library's records are separate on its server, so two devices that create the record independently create the same record, and the server's revisions order their changes. A random ID per device would create several library records that would then need merging rules of their own. The ID and the kind are visible to the server; see "Encryption and metadata".
- **Members:**
  - `id`, `kind`, and `version` (integer, 1).
  - `modifiedAt`: informational; it never orders anything.
  - `title`: a fixed, harmless name. It's there only so that an older app that ever has to name this record (see "Older apps") shows "Pinned Entries and Journal Order" rather than "New Entry". Current apps ignore it.
  - `values`: an object whose keys are strings of the form `‹namespace›/‹lower-case UUID or name›`.
  - The record has no `document`, `date` or `deletedWithJournal`, so older apps can't read it as a journal, entry or template. records.md gets a section for this kind.
- **Values defined now:**
  - `pinned/‹entry id›`: writers write `true`. Readers treat any value other than `false` or `null` as pinned, so a later version can store, for example, a pin time without hiding pins on this one. A missing key means not pinned; unpinning removes the key.
  - `journal-rank/‹journal id›`: a rank string (journal-order.md).
- **Reading rules (forward compatibility built in):**
  - Unknown namespaces, unknown top-level members, and values of the wrong type for a known namespace are kept and written back unchanged. They never make the record read-only. A wrong-type value is ignored for display.
  - A `version` above 1 is reserved for incompatible changes. Such a record is kept byte for byte and is read-only (pins and order fall back as described above). Adding a namespace never changes `version`.
  - Keys for records that don't exist, are in Recently Deleted, or are permanently deleted are ignored for display.
- **Never in:** Version History (no checkpoints), the conflicts table, the agent copy and `agentCopyFingerprint` (so a pin doesn't trigger agent-copy checks), search, list counts, `LibraryContents` (whose "nothing written" check must ignore it; otherwise connecting a new device would stop replacing an untouched library), or the counts of items waiting to sync while the server can't take it (see "Older apps and servers").

### Conflicts: per key, the change synced last wins

Pins and order are cheap to redo and visible at once. A review screen for "pinned here, unpinned there" would cost more than it protects. The record therefore merges automatically, key by key, and never creates a review.

1. **Local intents.** A device keeps the keys it changed that the server hasn't confirmed yet, each with its new value (null for a removed key) and a strength:
   - **set**: the person's own change (a pin, an unpin, the moved journal's rank, a new journal's rank, a rebalance);
   - **set if absent**: ranks the device assigns automatically to unranked journals (journal-order.md).

   Each intent also records whether it has been **sent** in an operation (rule 4 relies on this).

   The intents are stored in the existing `settings` table under the key **`library-changes`**, as a value sealed like a record payload: AES-GCM with the vault key, AAD `journal:v1:local:library-changes`, or base64 JSON in a library without encryption. Using the existing table needs no database migration, so build 12 can still open a library or archive written by the new version. The intents travel with archives together with the outbox, so restoring an archive on an empty device keeps unsent pins. archive.md documents the key (readers ignore settings keys they don't know), and archive export authenticates it with the records in encrypted libraries.

   - **Turning on encryption** re-seals the value explicitly; `Reencryption` copies only payload tables, so this is an added step. A plaintext value left by build 12 turning on encryption is accepted and re-sealed.
   - **A value that can't be opened** (damaged, or sealed under another key) never blocks opening or syncing. Its bytes are kept, and the next merge treats this device's differing keys as of unknown lineage (rule 4).

   Every local change updates the stored record and the intents in one transaction.
2. **Merging.** A merge is the server's version with the intents applied on top: **set** intents always, **set if absent** intents only where the key is literally absent from the server's version (a present value of any type, valid or not, is kept). It replaces every place where a content record would become a review:
   - an incoming change while the local copy has intents;
   - a push refused with `revision_conflict`/`current`;
   - a different version at a known revision (`keepIfOtherVersion`).

   Every merge first records the server's version (`rememberServerVersion`), so the same server version is never merged twice. If the merged values equal the server's, the device adopts the server's version, explicitly retires any queued library operation, clears the intents and sends nothing. If the queued operation already has this base and these values, it is kept as it is. Otherwise the merged record is stored at the server's revision and queued with a **new operation ID** at that base, the way `rebaseQueuedChange` replaces an operation, so an operation ID is never reused with other bytes.
3. **Clearing intents.** Whenever this device acknowledges or adopts a server version (a full or short receipt, reading its own change back with `readOwnChange`, an incoming change, a reconciliation that matches):
   - a **set** intent whose value equals that version's value for its key is removed; a key changed again since then stays;
   - a **set if absent** intent is removed when that version has *any* value for its key, so a leftover automatic rank can never re-rank a journal later.
4. **Server restore, rollback, a fork or a fresh server.** This covers `SyncReconciliation` and its `reconcileMissing`, `keepIfOtherVersion`, and signing in again after encryption was turned on elsewhere (`Reencryption.restart`). In these cases the device can't tell whether the server's version is newer or older than its own knowledge of other devices' changes. The library record never takes the "conflict for review" branch; instead:
   - **First,** if reconciliation staged a server payload this device saw (`seen_payload`), that payload is acknowledged under rule 3, which clears every intent it already contains.
   - **Each intent records whether it has been sent:**
     - an intent that **never left this device** keeps its strength: the person's own unsent pin, unpin or move always survives, as rule 6 promises;
     - an intent that **was sent but not confirmed** becomes **set if absent**, and a removal of this kind is dropped.
   - **Every other key** where this device's version has a value the server's version lacks becomes **set if absent**. No present value is overridden and nothing else is removed.
   - **The device then merges** under rule 2.

   **Worst case:** a pin comes back, or a move or unpin that had already been sent before the restore is lost. A device that was behind, or on another branch after a rollback, can never undo newer changes or silently remove a pin. This applies to every branch (descending, server lost versions, fork at a known revision, missing record, unknown lineage), so the lineage branches need no library-specific mapping beyond "never a review".

   **Every path that writes the conflicts table** checks for kind `library` and merges instead: `apply` (its `dirty || hasConflict` check), `keepOtherVersion`, `reconcile`'s branch for an existing review and its final `else`, and the review branch of `reconcileMissing`. Library writes never go through `save()`, whose `keepChangedVersion` would create a review for a copy that is out of date.
5. **Leftover reviews and history from build 12.** Build 12 can create a review row for the library record (in its reconciliation or `keepIfOtherVersion`), and it can write library versions to `history`. Both survive an update to the new version, or a TestFlight downgrade and upgrade. When the store opens, before any sync or reconciliation and in one transaction, the new version converts them:
   - **A review at a revision above 0:** the review's remote version is taken as the server's version. This device's differing keys are handled as in rule 4. The row is removed, and any held operation is retired.
   - **A review at revision 0** (from `reconcileMissing` or `Reencryption.restart`; the remote version isn't on the server): the keys of both versions become **set if absent** intents, and the record is queued at base 0. The server's version isn't recorded.
   - **Intents already stored** (left by a downgrade) keep their strength and their sent flag.
   - **Library rows in `history`** are deleted. The library record never gets Version History or checkpoints: `keepLastReadableVersion`, `keepCheckpointIfDue`, `keepOtherVersion` and `preserveSupersededConflict` skip kind `library`.
   - **A library version this client can't read** (a `version` above 1, or unreadable): the newer record is adopted byte for byte. The intents stay stored but are held, neither applied nor sent, so the record is never rewritten.
6. **Result.** For a key changed on two devices, **the change synced last wins**, even if it was made earlier: a device that was offline for a week and pinned something then overrides an unpin made since, when it reconnects. Keys changed on only one device always survive. Device clocks are never used. Every device ends with the server's latest version once its intents are cleared, so all devices converge.

This is a deliberate exception to "Never silently … overwrite conflicting edits", justified because these values are arrangement, not content: no text, title, date or image is ever merged this way. It is written into the protocol as a rule of the `library` kind only.

### Older apps and servers

**Apps on build 12 or earlier** receive a record kind they don't know.

- `PortableRecord.decode` fails on the missing required fields, so `unreadable(...)` keeps the record byte for byte as a read-only item. Lists, counts, search and agent copies all filter by kind, so in normal use it is invisible and never written.
- Those devices show journals by name and no Pinned section. Nothing on them becomes read-only or unavailable.
- They do touch it in these cases, all through generic paths that keep its bytes:
  - **After a server `--restore` or a detected rollback,** build 12's reconciliation may upload its copy again, when the server lost a later version this device has. It may also keep a differing server version "for review". That review appears under Settings ▸ Sync ▸ Changes to Review as "Pinned Entries and Journal Order", with the existing "Update My Journal to review these changes." It stays until the device is updated, and nothing is lost.
  - **Turning on encryption** from a build 12 device sends its copy again at base revision 0, like every record; other devices match it by content.
  - **Restoring an archive** that has the record queued sends it as queued.
  - **A library restored from an archive and then switched to encryption against a server without the capability** (from build 12) sends the record, and that server refuses it with its usual "didn't accept" message on that device. The message clears once the server is updated. This is the one case where an older device shows an error for the record.
- Such a device can't *import* an archive made by a newer version as new journals, or merge local journals that came from one. It refuses with its existing message ("Update My Journal to import this archive as new journals…"), as it would for any record from a newer version. Restoring the archive on an empty device works.

**Servers** accept only the kinds `journal`, `entry` and `template` (`SyncEndpoints.cs`: `request.Kind is not ("journal" or "entry" or "template")` returns 400 `invalid_record`). An older server would refuse the record. Therefore:

- **Server change:** accept the new kind and advertise a capability. Recommended: accept any kind of 1–32 characters from `a-z`, `0-9` and `-`, and advertise **`record-kinds`**, so later kinds need no server change. The server never interprets payloads. The kind is already bound into the encryption's AAD (`journal:v1:record:{kind}:{id}`), and `kind_is_immutable` still applies. The alternative is to allow `library` only, with the capability `library-record`.
- **Client gate, at one choke point:**
  - The last capability seen from the connected server is stored in `settings`.
  - While it is missing, `enqueue` refuses kind `library`, and `pending()`, sending, `pendingItemCount`, `hasPendingChanges` and `settledFacts` skip any library operation that is already queued. This covers every path that queues records: ordinary saves, the re-queue in `acknowledge`, `rebaseQueuedChange`, `requeue`, `resolve`, `reupload`, `reconcileMissing`, and `Reencryption.restart`. The record stays dirty with its intents, so nothing counts it as waiting: not "Not on Server Yet", not the Stop Syncing message.
  - The first sync that sees the capability queues it, at the revision it has (0 if never sent). Every device sends its own copy then. The first creates the record; the others are refused and merge.
  - **If the capability disappears** (the server was downgraded, or the device moved to another server), a queued library operation is held, not sent. The record keeps its intents, and the footer appears.
  - A library without a server keeps the record dirty in the same way until it connects.
- **Protocol version:** stays v1. The change is additive (a new kind behind a capability), as the versioning rules require. protocol/README.md's "Kinds: journal, entry, template" and records.md are updated.

### Encryption and metadata

- The record is encrypted like any other record, with the AAD `journal:v1:record:library:{lower-case id}`. In libraries without encryption it is readable JSON, like everything else. The local intents are sealed the same way.
- **The server additionally learns:**
  - that the library uses pins or a custom journal order (the record exists);
  - when either changes (a revision each time). Its timing can be correlated with entry revisions, for example a pin right after an entry was written.
  - Payloads aren't padded (SECURITY.md already says "size follows length"), so the size shows roughly how many pins and ranked journals there are. Size changes show whether a change was probably a pin (about 50 bytes more), an unpin (fewer) or a move (about the same).
- **The server no longer learns:** with a field on entries, each pin would produce a revision of that particular entry, showing which entry was touched and when. The library record names no entry to the server.
- SECURITY.md's list of what the server sees gains the kind `library` and these points.
- Optional hardening, not proposed by default: padding this record's plaintext to a multiple of 1 KiB with JSON whitespace would hide counts and the kind of change. Content records aren't padded either, so this would be inconsistent unless it is done everywhere.

### Migration and other paths

- There is nothing to migrate and no database schema change. Libraries without the record behave as today: no pins, and journals by name. The record is created by the first pin or the first journal move.
- **Archives:** the `records` table holds the new kind like any other, and the `settings` table holds `library-changes`. Restoring on an empty device keeps both.
- **Importing into an existing library** (archive import, and Merge Journals when connecting a device that has journals):
  - `ContentImport` and `MergePlan` must leave the library record out of the items they copy. Otherwise it would be refused as unreadable, or given a new identity and uploaded as a second library record.
  - Instead, the source's keys for the imported entries are remapped to their new identities and added to the destination's record as **set** intents.
  - Journal ranks: if the destination has no custom order, its existing journals first get **set if absent** ranks in their shown order, so imported journals don't jump above them. Imported journals are then ranked after the last valid rank, in their relative order.
  - Journals that are combined with a server journal of the same name (`MergePlan.skipped`) get no rank intent, so they don't move the server's journal.
- **Turning on encryption:** generic for the record, plus the explicit re-sealing of the intents described above.
- **Delete Permanently** doesn't touch the library record. Keys for permanently deleted records are ignored for display. The next local change to pins or order also removes keys whose record exists on this device as a canonical permanent-deletion marker (as **set** removals). Keys for records this device doesn't have are **never** removed, only ignored: the record may simply not have arrived yet, for example an entry still waiting for its images while its pin has already synced. This keeps the deletion transaction unchanged, and doesn't produce a library revision at the moment of the deletion.
- **List caches:** the keys of `DerivedLists.entries` and `groups` include the library record's version, and `journals` is invalidated when it changes, so pins and moves from sync appear at once.

### Server

- `SyncEndpoints.cs`: allow the new kind (or any well-formed kind) and add `record-kinds` (or `library-record`) to `features`. Document both in protocol/README.md.
- No database migration; `Kind` is already a free text column.
- Agent tools: no change. Agent copies are built on devices from journals and entries only.

## Tests that protect this

Sync and compatibility tests first, as AGENTS.md asks. They use real isolated stores and the in-process receipt harness, plus `scripts/test-sync.sh` for the real transport.

1. **Concurrent pins of different entries** on two stores, pushed in either order: both entries are pinned on both stores, and there are no conflict rows.
2. **The same key, opposite values** (pinned on A, unpinned on B): the value synced last wins on all three replicas. The refused push is replaced with a new operation ID, and `operation_reused` never occurs. A merge equal to the server's version sends nothing.
3. **Lost response:** the push is accepted but its answer is lost, then the device reads its own change. It is acknowledged, not merged twice, and the intents are cleared. The same holds with short receipts.
4. **Forward compatibility:** a record with an unknown namespace key and an unknown top-level member survives a local pin, a merge and a re-push byte-equal for those members. A `version: 2` record is kept byte for byte and never written.
5. **Unknown-kind compatibility:** a record of an arbitrary kind the decoder doesn't know (the generic path build 12 uses for `library`) yields an invisible, read-only item. It is synced, archived and reconciled after a server restore without being changed. Lists, counts and the lifecycle snapshot are unaffected. A fixture in `protocol/fixtures/` has the library record's plaintext and ciphertext. Once, by hand: a build 12 (3bd25c8) device synced with a library that has the record.
6. **Capability gate:** against a server without the capability, nothing of kind `library` is sent, including after turning on encryption (`Reencryption.restart`) and after a server downgrade with a library operation already queued. The pending counts and the settled state ignore it, and no error is shown. After the capability appears, it is queued and converges across two devices that both changed it meanwhile. A .NET test checks that the server accepts the new kind (or any well-formed kind), keeps rejecting a malformed kind, and keeps `kind_is_immutable`.
7. **Archive restore with unsent pins:** restore on an empty device, connect, and the pins reach the server.
8. **Server restore that lost an acknowledged pin:** the device sends the pin again. No review is created, and the result converges on a second device.
   - **Device that was behind at restore time:** an iPad that last read library revision 5 reconciles against a restored revision-9 backup. It adopts revision 9 and doesn't revert revisions 6–9.
   - **Signing in again after encryption was turned on elsewhere:** an offline device's differing pins come back only as additions (set if absent), and the other device's unpins and moves stand. Its never-sent unpin still applies.
   - **Fork after a rollback:** after another device writes at the same revision, the device that sees the other version doesn't unpin the other device's new pin.
   - **Sent but unconfirmed, then reconciled:** a pin whose answer was lost doesn't undo a later unpin from another device.
   - **A leftover review** created by the generic path (build 12's behaviour) is converted into a merge when the store opens, at a revision above 0 and at revision 0, and no review or history row remains.
9. **Import and joining:** importing an archive into a library with its own record produces one library record with the imported entries' pins and the imported journals ranked last, without moving the existing journals. Joining a server with local journals doesn't upload a second library record. `nothingWritten` ignores the record. Two different libraries that both have a library record aren't judged the same library by `SyncLineage`.
10. **Lifecycle:** delete, restore, Restore and Move, and Move Entry keep the pin. A permanently deleted entry's key is ignored and removed by the next pin change. A pin for an entry this device hasn't received yet survives another pin change on this device.
11. **Sealed intents:** turning on encryption re-seals them, and a value that can't be opened doesn't block opening or syncing.
12. **A leftover set-if-absent intent** is cleared when the server's version has any value for its key, and doesn't re-rank the journal after that key is later removed.

No tests for menu composition or the section header's text.

## Open decisions

- **D1 — Row date in Pinned.** (a) Keep the date line in pinned rows; the section header reads "Pinned". *Recommended:* this is how Notes looks, and dates belong in the list. (b) Replace the row's date line with "Pinned".
- **D2 — Pinned in All Entries.** (a) Show it. *Recommended.* (b) Only inside journals.
- **D3 — Order within Pinned.** (a) By entry date, like the rest of the list. *Recommended.* (b) Most recently pinned first. This would need a timestamp per pin.
- **D4 — Server kinds.** (a) Accept any well-formed kind (`record-kinds`). *Recommended.* (b) Accept `library` only.

## Review outcome

The design was reviewed three times by independent design agents, which got the requirements and the proposals, not the author's reasoning.

**First review: revise and re-review the data and sync design; the UI was approved once its required changes were made.**

Changes made:
- **Intents storage (blocker).** The merge intents were planned for a new local table. Archives don't carry it, and a new table needs a database migration that build 12 would refuse. They now live in the existing `settings` table as a sealed value.
- **Capability gate.** An unsent library record no longer counts as waiting to sync.
- **Older apps.** The text now states honestly when they upload the record again or show it for review. The record gained a harmless `title`.
- **Server restore.** Reconciliation can no longer silently lose acknowledged pins.
- **Other changes:**
  - Places that must skip the record: `MergePlan`, `ContentImport`, `nothingWritten`, list caches and the agent-copy fingerprint.
  - "The change synced last wins" is now said in plain words.
  - Delete Permanently no longer writes the library record in its transaction.
  - The metadata the server can see is described fully.
  - The File menu listing is current.
  - Undo Pin Entry and Undo Unpin Entry were added.
  - VoiceOver focus is set again after a row moves.

**Second review: approve with required changes; the UI was approved as written.** It found these major problems, now fixed:
- **One choke point for the gate.** Encryption upgrade, reconciliation, `acknowledge` and rebasing also queued the record.
- **Lineage.** Turning every differing key into an intent during reconciliation let a device that was behind undo newer changes.
- **The fixed record ID.** It could make two different libraries look like the same one to `SyncLineage`.
- **Lazy pruning.** Removing keys of records that are only *missing* here, not deleted, could drop pins.
- **Leftover reviews.** A review row created by build 12 survives the update.

Also fixed:
- re-sealing the intents when encryption is turned on, and what happens when they can't be opened;
- "set if absent" only for absent keys, cleared when the server has any value;
- import ranks that no longer jump above existing journals;
- "pinned" read as any value other than `false`/`null`;
- consistent copy for a library record from a newer version.

**Third look, at the reconciliation rule only: required changes, now applied.**
- Intents now record whether they were sent.
- In every reconciliation branch, only never-sent intents keep their strength. Everything else is "set if absent", and removals that were sent aren't asserted again.
- The staged `seen_payload` is acknowledged first.
- Every path that writes the conflicts table is listed with a `library` guard.
- Leftover reviews at revision 0, history rows, and unreadable or newer library versions are handled.

The accepted worst case is a pin that comes back, or a move or unpin made before a server restore that is lost. A device can never undo newer changes or silently remove a pin.

**Remaining before implementation:**
- the drag prototype (journal-order.md);
- the protecting tests above, which carry the sync rules;
- the owner's open decisions.

## Owner decisions (3 October 2026)

The owner accepted the recommendations:
- "Pinned" is a section header styled like the month headers, and pinned rows keep their date line.
- Pinned appears in All Entries as well as in journals.
- Pinned entries are ordered by entry date, newest first.
- The server accepts any well-formed record type and advertises it.

## Implementation notes (3 October 2026)

Built as designed, with these refinements, each found while writing the protecting tests:

- **Rule 4 and proven lineage.** When reconciliation finds this device's current version in the server's log (`seen_payload`), the server's version descends from it. Only the intents not contained in that version survive; "every other key this device has and the server lacks" is *not* turned into set-if-absent then, because those keys were removed by newer changes the device never read. Without this, an iPad that was behind at a restore would re-pin entries unpinned after it last synchronized (test "A device that was behind at a restore does not revert newer changes").
- **A damaged intents value** is recorded as "unknown lineage" (`unknownLineage` in the stored value), kept through local changes, and applied once by the next merge or reconciliation (rule 4 for this device's differing keys).
- **Archives.** The intents value is not authenticated separately on export: in encrypted archives the sealed manifest already covers the whole database file. Turning on encryption seals a readable value under the new key and leaves out a value that can't be read.
- **Counts.** While the server takes the library record, an unsent change of it counts as one item in "Not on Server Yet", like any record; while it doesn't, it isn't counted (as designed).
- **Capability changes.** A synchronization that only receives reuses the server status for up to a minute, so a server that gains or loses `record-kinds` is noticed within a minute, or at once with Sync Now.
- **Pinned in the list.** Keys of entries deleted permanently on this device are left out of the pinned set the lists use; keys of entries not on this device yet are kept.
- **Pin and Unpin** in the File menu act on the open entry. Undo uses the window's undo manager, for row actions and for the menu bar command.
