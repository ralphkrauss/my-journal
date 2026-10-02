# Portable records

A record is one journal, entry or template, stored and synced as a UTF-8 JSON object. The same JSON is the plaintext of a sync payload, of a local database payload and of an archive. How it is encrypted, or base64-encoded in libraries without encryption, is in [README.md](README.md); [fixtures/encryption-v2.json](fixtures/README.md) has a complete current example.

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
| `defaultTemplateID` | UUID | no | Journals only: the template for new entries. May refer to a template that no longer exists. |
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

## Markdown

The dialect is CommonMark with the GitHub Flavored Markdown tables, task lists and strikethrough. Underlining uses the inert `<u>…</u>` extension, and the inert comment `<!-- -->` may separate adjacent emphasis delimiters without adding visible text. Raw HTML is shown as its source text and never run, and remote images are never loaded. Markdown is authoritative; metadata never duplicates prose.

Editors keep the bytes of blocks the person didn't change, including reference definitions, list markers, line endings (LF, CR or CRLF) and other source details, and write new or changed blocks so that the Markdown reads back as the same blocks. Content an editor can't show natively stays unchanged and can be edited as source.

## Images

An image whose destination is exactly `attachments/` followed by a UUID refers to an attachment: no `./`, query, fragment, suffix or percent-encoding. This applies to every image, whether it stands alone, is inline, is inside a link or a table cell, or is reached through a reference definition. The image's alt text is its description; line breaks in it are written as spaces.

An attachment is an image file in any format the writing platform could read. The Apple app keeps image files as they came, with their metadata such as EXIF, except that it removes location (GPS coordinates and IPTC place names) when an image is added, copying the image data unchanged where ImageIO allows and otherwise encoding it again (without loss for formats such as PNG); a pasted picture that has no file of its own, or arrives as TIFF, is encoded as JPEG or PNG. `imageTypes` records the media type. A reader that can't decode a format shows a placeholder and never rewrites the file. Encrypted attachments are at most 25 MiB.

A document may refer to an attachment the reader doesn't have: it may not have been downloaded yet, or the server may have lost it. Readers show a placeholder, keep the reference unchanged, and don't fail a sync because of it; they try the download again later. Attachment discovery for sync, archives, history and cleanup covers current records, their earlier versions and versions awaiting review.
