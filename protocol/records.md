# Portable records

A record is one journal, entry or template, or the library record, stored and synced as a UTF-8 JSON object. The same JSON is the plaintext of a sync payload, of a local database payload and of an archive. How it is encrypted, or base64-encoded in libraries without encryption, is in [README.md](README.md); [conformance/crypto/encryption-v2.json](conformance/crypto/README.md) has a complete current example, and [conformance/records/](conformance/records/README.md) has records of every kind and the cases a reader must handle.

## Record fields

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | UUID | yes | The record's identity. Must equal the ID in the sync path and in the record's encryption context. |
| `kind` | string | yes | `journal`, `entry` or `template`. Must equal the sync `kind`. |
| `title` | string | yes | Journal name, entry title (may be empty) or template name. |
| `document` | object | yes | The body; see [Documents](#documents). Journals carry an empty document. |
| `date` | timestamp | yes | For entries, the entry's date, shown in lists and changed with Change Date. For journals and templates, when they were created. |
| `modifiedAt` | timestamp | yes | When the writing device last changed the record. It never orders revisions; the server's revision numbers do. |
| `deletedWithJournal` | boolean | yes | Legacy: true on entries an earlier version deleted together with their journal. Writers write `false`. |
| `journalID` | UUID | entries | The journal an entry belongs to. Absent on journals and templates. An entry whose journal is missing is shown as unavailable, never moved. |
| `deletedAt` | timestamp | no | Set while the record is in Recently Deleted. On a journal it also hides the journal's entries ([journal lifecycle](journal-lifecycle.md)). |
| `defaultTemplateID` | UUID | no | Journals only. Legacy: the template new entries started from, written by versions up to 1.0. 1.1 and later neither show nor use it, and keep it unchanged ([Writing a journal back](#writing-a-journal-back)). May refer to a template that no longer exists. |
| `archivedAt` | timestamp | no | Entries only. Kept for compatibility ([entry archiving](entry-archiving.md)). |
| `permanentlyDeletedAt`, `permanentDeletionID`, `restoredFromDeletionID` | timestamp, UUID, UUID | no | Permanent-deletion markers and explicit restoration ([permanent deletion](permanent-deletion.md)). |

Types:

- **UUID**: a hyphenated UUID string. Compare UUIDs case-insensitively. The Apple app writes UUIDs in record JSON in upper case; where a UUID is part of authenticated data, a key derivation input, a file name or a JSON object key (`imageTypes`), it is always lower case.
- **timestamp**: an ISO 8601 date and time with `Z` or a numeric UTC offset, with or without fractional seconds (readers accept up to seven digits). It is an instant; clients show it in the viewer's time zone. The Apple app writes whole seconds in UTC (`2026-09-20T12:00:00Z`) and drops fractions when it reads a record.
- Optional fields are omitted or `null`. The Apple app omits them.

The Apple app writes keys in sorted order and escapes `/` as `\/`. Neither is required; a reader authenticates the bytes it received and parses them as ordinary JSON.

## Documents

Every document has an integer `version`.

**Version 2** (current). Fields:

- `markdown` (string, required): the body. See [Markdown](#markdown).
- `metadata` (object, optional), with optional members:
  - `blockIDs`: an array of UUIDs, one per block of the Markdown in order, which keeps paragraph identities stable across devices. A reader without them derives identities from each block's position and text.
  - `segmentLengths`: an array of integers, one per block, giving the UTF-8 byte length of each block together with the text that follows it up to the next block (the first segment also holds any text before the first block). They sum to the UTF-8 length of `markdown`. They keep native paragraph boundaries, such as empty paragraphs. A reader ignores them when the count or sum doesn't match.
  - `imageTypes`: an object mapping lower-case attachment UUIDs to media types, such as `image/png`.

A writer that doesn't track block identities may omit `metadata` or any of its members. A document without `markdown`, or with a metadata member of another type, is read-only for readers (see [Reading rules](#reading-rules)).

**Version 1** (legacy). `blocks` is an array of blocks with `id` (UUID), `kind` (string), `runs` (array) and optional `attachmentID` (UUID), `imageDescription` (string) and `mediaType` (string). A run has `text` (string), optional `bold`, `italic` and `underline` (booleans, default false) and optional `link` (string). Earlier versions wrote the block kinds `paragraph`, `heading`, `subheading`, `bullet`, `numbered` and `image`. A version-1 record stays version 1 until its body is edited; it is then written as version 2, with the earlier version kept in Version History.

## Reading rules

A record can authenticate and still be one this client can't fully read. Such a record is never rejected, rewritten or dropped:

- An unknown field in the record, document, metadata, block or run; an unknown `kind`; a document `version` other than 1 or 2; a version-2 document without `markdown` or with a malformed metadata member; or a version-1 document with malformed blocks or an unknown block kind: the record is shown as far as it can be, read-only, and its original bytes are kept and synced unchanged.
- A required field that is missing or has the wrong type, `archivedAt` on a journal or template, permanent-deletion fields that don't form a [canonical marker](permanent-deletion.md), or an `id` or `kind` that doesn't match its context: the record is kept byte for byte as an unreadable, read-only record with whatever title and dates can be read. It is never treated as a deletion marker. When it replaces a version this client could read, that version goes to Version History.

A newer app reads kept records again from their stored bytes. A client must not save over a record it can't fully read; an edit made from an older copy becomes a conflict.

## Writing a journal back

A client that saves a journal for another reason (a rename, Delete Journal, Restore Journal, settling a conflict, an import or a merge) keeps `defaultTemplateID` unchanged, even though no screen shows it. A device that still runs version 1.0 uses the setting, and a client that drops it on Rename silently breaks that device. Archive import and merge keep remapping the member to the template's new identity ([archive.md](archive.md)). A record with any member the reader does not know is read-only and never rewritten ([Reading rules](#reading-rules)), so this rule concerns members the reader knows. [conformance/records/journal-rewrite-v1.json](conformance/records/README.md#journal-rewrite) has the cases.

## The library record

One record per library holds small arrangement values shared across the library: pinned entries and journal order (docs/design/pinned-entries.md, docs/design/journal-order.md). Records that hold content are unchanged. [conformance/records/library-record-v1.json](conformance/records/README.md) has an example sealed with the corpus key, and [conformance/records/journal-ranks-v1.json](conformance/records/README.md) the rank vectors.

```json
{"id":"9F297F28-7D13-41B7-A7EA-83D06CAC6924","kind":"library","modifiedAt":"2026-10-03T12:00:00Z","title":"Pinned Entries and Journal Order","values":{"journal-rank/1b6f0e2a-4c8d-4e3f-a1b2-c3d4e5f60718":"Kf","pinned/2f1c7a54-8e0b-4d6a-9c3e-5b7d1f2a4c60":true},"version":1}
```

- **Identity:** always `9f297f28-7d13-41b7-a7ea-83d06cac6924`, in every library, so devices that create it separately create the same record and the server's revisions order their changes. Its kind is `library`, and it's encrypted like any record, with the AAD `journal:v1:record:library:9f297f28-7d13-41b7-a7ea-83d06cac6924`. Because every library has this identity, it never counts as evidence that two libraries are the same.
- **Members:** `id`, `kind`, `version` (integer, 1), `modifiedAt` (informational, never orders anything), `title` (always "Pinned Entries and Journal Order", only so that an older app that has to name the record shows something sensible) and `values`, an object whose keys have the form `‹namespace›/‹lower-case UUID or name›`. It has no `document`, `date` or `deletedWithJournal`, so older apps can't read it as a journal, entry or template.
- **Values:**
  - `pinned/‹entry id›`: writers write `true`. Readers treat any value other than `false` or `null` as pinned, so a later version can store more. A missing key means not pinned; unpinning removes the key.
  - `journal-rank/‹journal id›`: a rank string. The 62 ASCII characters `0-9`, `A-Z`, `a-z`, in ASCII order; 1 to 64 of them, not ending in `0`. Ranks compare byte by byte, never by locale. Journals in use with a valid rank are listed by (rank, lower-case ID), then the others by name, then by ID. A move writes one rank strictly between the new neighbours' ranks; any algorithm that produces one is allowed. Ranks of journals in Recently Deleted are kept, so a restored journal returns to its place.
- **Reading rules:**
  - Unknown namespaces, unknown top-level members, and values of the wrong type for a known namespace are kept and written back unchanged. They never make the record read-only; a wrong-type value is ignored for display.
  - A `version` above 1 is reserved for incompatible changes. Such a record, or one that isn't a library record a client can read, is kept byte for byte and never written; pins and order then fall back to none and to names. Adding a namespace never changes `version`.
  - Keys of records that don't exist, are in Recently Deleted, or are permanently deleted are ignored for display. A writer removes keys of records it has as permanent-deletion markers only together with a change of its own, and never removes keys of records it doesn't have: they may not have arrived yet.
- **Never in:** Version History, reviews, agent copies, search or counts.

### Merging instead of reviews

These values are arrangement, not content, so the record is a deliberate exception to keeping both versions for review. No text, title, date or image is ever merged this way, and the rule applies to the `library` kind only:

1. **Intents.** A device keeps the keys it changed that the server hasn't confirmed, each with its new value (or its removal), a strength (**set** for the person's own changes, **set if absent** for automatic ranks) and whether it was **sent**.
2. **Merging.** Wherever another record would become a review (a change arriving while one waits to be sent, a push refused with `revision_conflict` and `current`, another version at a revision the device has), the device takes the server's version and applies its intents on top: **set** always, **set if absent** only where the key is absent from the server's version (a present value of any type counts). If the result equals the server's version, the device adopts it and sends nothing; otherwise it sends the result as a new operation based on the server's revision.
3. **Clearing.** Whenever a device acknowledges or adopts a server version, it forgets **set** intents whose value that version has, and **set if absent** intents whose key it has any value for.
4. **Restores, rollbacks, forks and new servers.** When a device can't tell whether the server's version is newer than what it knows (reconciliation after a restore, another version at a known revision, the server lacking the record, signing in again after encryption was turned on elsewhere), intents that never left the device keep their strength; sent ones become **set if absent**, and sent removals are dropped. Every other key the device has and the server lacks becomes **set if absent**, unless the server's log contains the device's current version, which proves the server's version descends from it. Then it merges as in 2.
5. **Result.** For a key changed on two devices, the change synced last wins, even if it was made earlier; keys changed on one device always survive; device clocks are never used. After a restore, the worst case is a pin that comes back, or a move or unpin sent before the restore that is lost.

### Compatibility

Only servers that list `record-kinds` take the record ([README.md](README.md#sync-and-conflicts)); until then a client keeps it, and its intents, on the device, without counting it as waiting or reporting an error.

Clients that don't know the record read it under the [reading rules](#reading-rules) below as an unreadable record of an unknown kind: it's kept byte for byte, read-only, and invisible in lists. Such a client may still send it again after a server restore, when turning on encryption or from a restored archive, and may keep a differing server version of it for review; the next version that knows the record converts such a review into a merge when it opens the library, and removes any of its versions from Version History. An older client that joins a server without encryption may take the record's shared identity as a sign that two libraries are the same; this is a known limit of those versions.

## Markdown

The dialect is CommonMark with the GitHub Flavored Markdown tables, task lists and strikethrough. Underlining uses the inert `<u>…</u>` extension, and the inert comment `<!-- -->` may separate adjacent emphasis delimiters without adding visible text. Raw HTML is shown as its source text and never run, and remote images are never loaded. Markdown is authoritative; metadata never duplicates prose.

Editors keep the bytes of blocks the person didn't change, including reference definitions, list markers, line endings (LF, CR or CRLF) and other source details, and write new or changed blocks so that the Markdown reads back as the same blocks. Content an editor can't show natively stays unchanged and can be edited as source.

## Images

An image whose destination is exactly `attachments/` followed by a UUID refers to an attachment: no `./`, query, fragment, suffix or percent-encoding. This applies to every image, whether it stands alone, is inline, is inside a link or a table cell, or is reached through a reference definition. The image's alt text is its description; line breaks in it are written as spaces.

An attachment is an image file in any format the writing platform could read. The Apple app keeps image files as they came, with their metadata such as EXIF, except that it removes location (GPS coordinates and IPTC place names) when an image is added, copying the image data unchanged where ImageIO allows and otherwise encoding it again (without loss for formats such as PNG); a pasted picture that has no file of its own, or arrives as TIFF, is encoded as JPEG or PNG. `imageTypes` records the media type. A reader that can't decode a format shows a placeholder and never rewrites the file. Encrypted attachments are at most 25 MiB.

A document may refer to an attachment the reader doesn't have: it may not have been downloaded yet, or the server may have lost it. Readers show a placeholder, keep the reference unchanged, and don't fail a sync because of it; they try the download again later. Attachment discovery for sync, archives, history and cleanup covers current records, their earlier versions and versions awaiting review.
