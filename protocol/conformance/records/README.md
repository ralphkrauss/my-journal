# records

Records as plaintext JSON ([records.md](../../records.md)): what a client must read from each, what it must keep when it writes it back, timestamps, the library record and journal ranks.

| File | Covers | Produced by |
| --- | --- | --- |
| `records-v1.json` | 25 records: entries, journals, templates, permanent-deletion markers, a restored entry, legacy block documents, records from other clients (lower-case IDs, offsets, fractions, escapes), records with unknown future members, and records that can't be read | The Apple app's writer for its own records; hand-written plaintext for the rest; expected values from the Swift reader |
| `timestamps-v1.json` | Instants a reader must accept (offsets, fractions up to seven digits, leap day) as whole epoch seconds, and texts it must refuse | Swift |
| `library-record-v1.json` | The [library record](../../records.md#the-library-record) (pins and journal ranks) as the Apple app writes it, sealed with `recovery.vaultKey` of `../crypto/encryption-v2.json` and a fixed nonce, with the values a reader must obtain | CryptoKit with a fixed nonce; checked by .NET's AES-GCM and the Apple app's reader |
| `journal-ranks-v1.json` | Journal ranks: valid and invalid ranks, byte order, the reference algorithm's rank between two bounds (null where none fits in 64 characters or the bounds are out of order) and automatic spacing for 1 to 62 journals | An independent Python implementation; checked by the Apple app's ranks |

## Record plaintexts (`records-v1.json`)

Each item of `records` has a `name`, a `note`, the `id` and `kind` the record is stored and sealed under (the sync path and kind), its exact `plaintext` (UTF-8 JSON, as authenticated, never re-serialized) and `expected`:

- `reading`:
  - `editable`: every member is known and well formed, the kind is `journal`, `entry` or `template`, and the document is version 1 with well-formed blocks or version 2 with Markdown and well-formed metadata;
  - `readOnly`: the record authenticates and parses and has this ID and kind, but has an unknown member (in the record, document or metadata), an unknown kind or document version, a version 2 document without Markdown or with malformed metadata, or an unknown version 1 block kind. It is shown as far as it can be;
  - `unreadable`: a required member missing or of the wrong type, an ID or kind that differs from the stored one (compare UUIDs without regard to case), `archivedAt` on a journal or template, permanent-deletion members that aren't a canonical marker, or text that isn't a JSON object.
- `rewrite`: `unchanged` for `readOnly` and `unreadable` records: a client writes the exact original bytes back and never saves over them. `rewritten` for `editable` ones, with `appleWrites` the Apple app's bytes (sorted keys, `\/` for `/`, whole-second UTC dates, upper-case UUIDs, optional members omitted). Another client may write its own JSON; it must read back as the same values.
- `id`, `kind`, `title`, `date`, `modifiedAt`, `journalID`, `deletedAt`, `archivedAt`, `defaultTemplateID`, `deletedWithJournal`, `permanentlyDeletedAt`, `permanentDeletionID`, `restoredFromDeletionID`: the values to show. Instants are whole epoch seconds, rounded down; UUIDs are lower case; absent members are `null`. For `unreadable` records these are only what the Swift reader could recover and are advisory: only `reading` is required.
- `documentVersion` and `markdown` (version 2) or `legacyBlockTexts` (version 1: each block's text) for `editable` records.

A client passes when it classifies each record as `reading` says, shows the required values and never rewrites a `readOnly` or `unreadable` record.

## Timestamps (`timestamps-v1.json`)

`valid` items give a `text` and its `epochSeconds`: a reader accepts `Z` and numeric offsets, with or without fractional seconds up to seven digits, and keeps the instant's whole second (rounded down). `invalid` texts (no offset, a space instead of `T`, a month 13, a date only, a bare number) must be refused. See Known issues in the [folder index](../README.md) about impossible calendar dates.

## The library record and ranks

- `record.combined` is nonce (12) || AES-256-GCM(vault key, `record.plaintext`) || tag (16) with `record.context` (`journal:v1:record:library:{id}`). Opening it as another kind fails. `expected` lists the pinned entries, the valid ranks and every key of `values`.
- A client that doesn't know the record must keep it as an unreadable record of an unknown kind ([records.md](../../records.md#reading-rules)); Swift `LibrarySyncTests` checks this with the decoding rules versions without the record used.
- `journal-ranks-v1.json`: `between` gives the reference algorithm's result (base-62 midpoint, adding a digit only when the bounds are adjacent; `null` lower and upper bounds are the start and the end). `spaced` lists the automatic ranks of `count` journals: with `w` digits, the smallest such that 62^(w−1) ≥ count + 1, position `i` (from 0) gets ⌊(i + 1) · 62^w / (count + 1)⌋ written as `w` base-62 digits without trailing zeros. Swift `JournalOrderTests` checks both.
