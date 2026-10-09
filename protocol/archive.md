# Journal archive

A `.journalarchive` (file type `org.privatejournal.archive`) is a directory package made by Export Archive. It holds a SQLite database and the image files, never an Apple-only format, so another client can read it with the record format in [records.md](records.md). A package may be carried inside a ZIP file by other tools, but ZIP isn't the reader's input format.

## Files

- `archive.json`: a UTF-8 JSON header, at most 16 MiB.
- `journal.sqlite`: a consistent SQLite online-backup snapshot of the library, in rollback-journal (`DELETE`) mode: one self-contained file with no `-wal` or `-shm` files.
- `attachments/<lower-case UUID>`: each image file exactly as the library stores it, copied rather than re-encrypted.

The header has three members:

| Member | Meaning |
| --- | --- |
| `version` | 1 for libraries with a password or recovery key (recovery formats 1–3), 2 for libraries without a password (format 4). A reader rejects a version that doesn't match the envelope's format, and unknown versions. |
| `recovery` | The library's recovery envelope, exactly as GET /v1/recovery returns it. |
| `manifest` | Base64. In version 1, the AES-256-GCM combined bytes (nonce, ciphertext, tag) of the manifest JSON, sealed with the vault key and AAD `journal:v1:archive`. In version 2, the manifest JSON itself. |

The manifest JSON is `{"database": "<SHA-256 of journal.sqlite, lower-case hex>", "attachments": {"<lower-case UUID>": "<SHA-256 lower-case hex>"}}`. It lists every file in `attachments/`, including images used only by earlier versions or deleted entries. The header holds only the wrapped key, never a vault key, password, recovery key, app PIN or device credential.

In version 1 the authenticated manifest protects the whole package against changes; recovering the vault key needs the password or recovery key. In version 2 the checksums detect accidental damage, not deliberate changes, and restoring needs no password. In formats 3 and 4 the database payloads and image files are readable.

## Reading an archive

A reader ignores names in `attachments/` that start with `.`, such as `.DS_Store` and the AppleDouble `._` files that appear when a package is copied between volumes, and it ignores other top-level files. Any other name in `attachments/` that isn't a lower-case UUID, a symbolic link or a file that isn't a regular file makes the archive invalid. The same holds for the manifest: a key in `attachments` that isn't a lower-case UUID makes the archive invalid, and a reader checks every key before it uses one as a file name. In version 2 the manifest isn't authenticated, so a name such as `../x` would otherwise reach outside the folder being restored.

Restore recovers the vault key (version 1), authenticates or decodes the manifest, and checks that the files in `attachments/` and the database match it exactly. It copies only `journal.sqlite` and the listed images into a new directory and checks the copies again, so a package changed during copying is refused. It then opens the database, applying any migrations it is missing, and refuses:

- a database written by a newer version (one with migrations the reader doesn't know);
- any schema object the migrations don't create, such as triggers, views or extra tables and indexes;
- a failed SQLite integrity check, a record, history row, conflict or image that doesn't authenticate, or a referenced image that is missing.

Before it writes anything, export checks the library's integrity, authenticates every record, history row and conflict, and checks that every referenced image is present. It writes `archive.json` last, after every file was copied and hashed.

## Database

The database is the library's own store, versioned by the migrations recorded in `grdb_migrations`: `v1`, `sync-reconciliation`, `history-record-index`, `history-checkpoints` and `server-versions`. A new migration is a change to the archive format and must keep older archives readable. IDs are lower-case UUID text. Payloads are the base64 sync payloads: encrypted records in formats 1 and 2, base64 of the record JSON in formats 3 and 4. Local timestamps are whole-second UTC ISO 8601 text, such as `2026-09-27T10:00:00Z`.

| Table | Columns |
| --- | --- |
| `records` | `id` (primary key), `kind`, `payload` (current version), `revision` (the server revision it is based on; 0 if never synced), `dirty` (1 while a local change isn't acknowledged by the server) |
| `outbox` | `operation` (operation UUID, primary key), `record` (unique, references `records`), `kind`, `payload`, `base` (base revision): the pending request, sent unchanged until acknowledged |
| `conflicts` | `record` (primary key, references `records`), `payload`, `revision`, `device`, `modified`: the other version of a record awaiting review; the local version is in `records` |
| `history` | `id` (integer primary key), `record`, `kind`, `payload`, `saved`, `checkpoint`: earlier versions shown in Version History. `checkpoint` is 1 for a version kept automatically from ordinary changes ([version checkpoints](../docs/design/version-checkpoints.md)) and 0 otherwise. Only checkpoints are removed to keep at most 50 per record. A row may have no current record. Indexed by `record`. |
| `settings` | `key` (primary key), `value` (UTF-8 text in a BLOB column) |
| `attachments` | `id` (primary key), `uploaded`: 0 not yet on the server, 1 on the server, 2 to be checked after a server restore |
| `reconcile_heads` | `record` (primary key), `kind`, `payload`, `revision`, `cursor`, `device`, `modified`, `seen_payload`: the server's latest version of each record while re-reading a restored server |
| `server_versions` | `record` (primary key), `revision`, `digest` (lower-case hex SHA-256 of the payload text): the version the server holds at that revision of the record, as this device last sent or received it. A change at that revision with another payload means the server lost a version it accepted, and becomes a review. |

Settings keys: `content-protection` (`encrypted` or `plaintext`, fixed when the library is created), `cursor` (the last applied server cursor, as decimal text), `cursor-change` (JSON `{"recordId", "revision", "digest"}` of the change at that cursor, when known; `digest` is the lower-case hex SHA-256 of its payload text and may be missing), `sent-change` (JSON `{"serverID", "cursor", "change"}`: the newest change this device sent that the server accepted, with `change` as in `cursor-change`), `server-id` (the server identity last synchronized with), `reconcile` (JSON state while re-reading a restored server) `merge-queued` (JSON object from derived record ID to digests of what a merge into a server queued for sending: of each payload, and of its record content without deletion state and modification time; see [join-with-local-journals.md](../docs/design/join-with-local-journals.md) §2.1), `library-changes` (this device's unconfirmed changes to the [library record](records.md#the-library-record): base64 text of the JSON `{"version": 1, "changes": {key: {"value", "removes", "ifAbsent", "sent"}}}`, with `"unknownLineage": true` while the device's earlier changes are unknown because a stored value couldn't be read, sealed in encrypted libraries like a record payload with AAD `journal:v1:local:library-changes`; a value that can't be opened is ignored and blocks nothing) `kept-notes` (local notes and automatic copies of [conflicts.md](conflicts.md): base64 text of the JSON `{"version": 1, "copies": [...], "notes": [...], "passStep": n}`, sealed in encrypted libraries like `library-changes` with AAD `journal:v1:local:kept-notes`; a value that can't be opened is ignored and blocks nothing) and `server-record-kinds` (`1` when the server last synchronized with takes the library record, `0` when it doesn't). Readers ignore keys they don't know. The library record is a row of `records` like any other; restoring an archive on an empty device keeps it, its unsent changes and its queued operation.

## Restoring and importing

Restoring into an empty device recreates the library exactly, including its sync baseline and pending requests. It doesn't authorize the device with a server; that needs pairing, the password or a recovery code. An archive holds what the exporting device had; changes that exist only on another, offline device aren't included.

Importing into an existing library adds the archive's journals as new ones:

- Records and images get new identities and are encrypted under the destination's key, in the destination's protection mode. The destination keeps its recovery, lock and connection settings; the archive's sync baseline and settings aren't used.
- The existing library is copied to a staging directory first, and only the configuration pointer commits the result. Imported records start at revision 0, and imported conflicts still block upload until resolved.
- The same mapping applies to current, historical and conflicting versions and to every `journalID` and `defaultTemplateID`, including references to records that don't exist: the same missing target always maps to the same new missing identity, and distinct targets stay distinct. Import doesn't create placeholder journals or templates, drop references, or bind to destination records that happen to share a source UUID. Such entries stay Unavailable, and missing default templates stay unavailable, until the person recovers or replaces them.
- Deletion state, legacy `deletedWithJournal` markers and permanent-deletion markers keep their meaning. Restoring an imported deleted journal brings back only its otherwise live entries.
- History rows without a current record are imported with new identities and destination encryption, but no current entry is created for them and they aren't queued for sync.
- Records this client can't fully read can't be remapped, so a library that contains them can only be restored exactly into an empty device.
- The library record isn't copied. The pins of imported entries are added to the destination's own library record under the entries' new identities. When either library has arranged its journals, the imported journals are ranked after the destination's, which first get ranks in the order shown if they had none.

## Failures and ownership

A restore refuses an existing destination. If copying, checking or opening fails, or the restore is cancelled, it closes the database and removes only the directory it created; the archive and other directories are untouched. A restore that fails validation never returns a usable library.

Export owns its new directory only after the snapshot succeeds; a failed snapshot, inventory or header write removes the partial archive, and a destination that already existed is never treated as its own. Cancellation is checked before work, between image copies and before completion; a single SQLite backup or file copy can't be interrupted.

Importing into an existing library owns its staging directory and new Keychain entry until the configuration pointer is saved. A failure before then removes both and keeps the current library and the inspected archive for another attempt. After the pointer is saved, cleanup never removes the installed library.
