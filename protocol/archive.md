# Journal archive

An archive is a copy of a whole library: a SQLite snapshot of its database, the image files exactly as the library stores them, a header and an inventory. It never uses an Apple-only format, so another client can read it with the record format in [records.md](records.md).

There are two kinds, and prose and specs call them by these words, never by numbers (the header of each has a number, and the recovery envelope has another):

| | File archive | Directory archive |
| --- | --- | --- |
| What it is | One ZIP file (the profile below) | A folder: `archive.json`, `journal.sqlite`, `attachments/` |
| Made by | My Journal 1.1 and later, every client | My Journal 1.0 only |
| Header member | `archiveVersion`: 2 | `version`: 1 or 2 |
| Libraries | With a password: recovery formats 1 and 2 only. The manifest is always sealed | Any recovery format 1 to 4. The manifest is sealed for formats 1 to 3 and readable for format 4 |
| Clients read it | All | Apple clients, so 1.0 archives still import. Windows and Android never write or read one |

Note, 2026-10-10 (documentation only, no contract change): My Journal 1.1 clients do not support recovery formats 3 and 4, so they refuse a directory archive whose recovery format is 3 or 4 (the manifest is readable for format 4 and sealed for format 3). The formats stay defined for 1.0 clients and for the conformance fixtures, which are unchanged.

A reader tells the kinds apart by what it is handed: a folder is a directory archive and a regular file is a file archive. There is no sniffing by name or extension. A file that is not a ZIP file, or whose `archive.json` has no `archiveVersion`, is damaged. A folder without `archive.json` is damaged, and so is a folder whose `archive.json` has `archiveVersion` (what a person gets from unpacking a file archive with an archive tool). A symbolic link in place of `archive.json`, `journal.sqlite` or `attachments/` inside a folder is damaged, and a reader never follows one.

[Conformance fixtures](conformance/archive/README.md) pin every rule below that says "damaged" or "ignored".

## Rules for both kinds

- **Names.** A UUID anywhere in this format (an entry name, a manifest key, a file name) matches exactly `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`. Parsing a UUID and lower-casing it is not equivalent: `Guid.TryParse` accepts braces, missing hyphens and capitals. Version and variant bits are not checked. A reader never builds a file name from an entry name; it builds it from a UUID it checked.
- **Listed files.** A reader reads exactly the files the manifest lists (`journal.sqlite` and `attachments/<UUID>` for each key), reads nothing else, and ignores everything else: `__MACOSX/…`, `.DS_Store`, AppleDouble `._*` files, folders, any other unlisted file, and an unlisted UUID-named image. Ignoring cannot lose library data, because anything the library needs is listed and the database check fails if a referenced image is missing. These are errors: a listed file that is missing, differs in size, CRC-32 or SHA-256, or cannot be read; a manifest key that is not a UUID (checked before any key is used as a name); and, in a directory archive, a listed name that is a symbolic link or not a regular file.
- **JSON.** `archive.json` and the manifest are UTF-8 JSON without a byte order mark, comments or trailing commas. Member names are compared as UTF-8 bytes, not as Unicode text: `K` and the Kelvin sign (U+212A), or a composed and a decomposed `é`, are different names, although a language that compares strings by canonical equivalence would call them equal. A repeated member name, at any depth in the header or in the manifest, makes the file invalid (parsers disagree about which duplicate wins; two readers would see two envelopes). Nesting is limited to 32 levels, the outermost object or array being the first: 32 are valid, 33 are not. A header holds at most 1,000 JSON values and a manifest at most 400,000, every object, array, string, number, `true`, `false` and `null` counting one (a manifest of 100,000 images has about 300,000). Unknown members are ignored: a reader checks them against these rules and need not build them. A size (`bytes`) is a JSON integer written without sign, fraction, exponent or leading zero, at most 2^53 − 1.
- **Hashes.** SHA-256 values are 64 lower-case hexadecimal characters.
- **Failures** fall into four classes that clients report with their existing messages: damaged (anything below that says damaged, invalid or refused, including every limit), newer (`archiveVersion` greater than 2, or a database with a migration the reader does not know), wrong password (the credential does not open the recovery envelope), and couldn't open (the file is unavailable, the disk is full, or anything else). Conformance fixtures compare the class, never the reason.

## Limits

A reader enforces these on both kinds. A limit hit is damaged, except free space.

| Item | Limit |
| --- | --- |
| `archive.json` | 16 MiB (about 100,000 images) |
| Central directory (file archive) | 64 MiB and 300,000 entries |
| One image file | 25 MiB (the server's attachment limit) |
| `journal.sqlite` | 32 GiB |
| Schema table of `journal.sqlite` (`sqlite_master`) | 64 objects and 256 KiB of rows (the library has about 30 objects and under 6 KiB), checked on the file's pages before SQLite parses the schema ([Database](#database)) |
| JSON values | 1,000 in the header, 400,000 in the manifest |
| Expansion (file archive) | An entry is refused when `bytes > 8 × compressed size` (integer arithmetic) |
| Sum of the listed sizes | 1 TiB |
| Memory before the password is asked | The header: 16 MiB read, and about 48 MiB more while its manifest member is decoded (measured; about four times in all), because the parser keeps the bytes it reads, the decoded text and the text as a string. A member the reader does not use is checked and never built, and at most 1,000 values are read, so a header of millions of numbers costs no more than one of text. Plus the central directory entries the profile names; nothing else |
| Memory after the password is given | The manifest (up to 12 MiB of text) as a tree: about 80 MiB for 99,000 images (measured) |
| Free space on restore or import | At least 2 × the sum of the listed sizes + 256 MiB on the volume that holds the staging folder (the staging copy and the install, which writes the images again), checked before anything is written; short is "couldn't open" |
| Free space on export | At least the database size + the sum of the image sizes + 256 MiB on the volume that holds the staged archive. The destination volume cannot be checked in advance |
| Chunk | 256 KiB |
| Time to inspect the database | Local to a reader, like free space: the Apple reader refuses the file as damaged when a step other than `PRAGMA quick_check` (which reads the whole file and is bounded by cancellation) takes more than 10 seconds, and every step can be cancelled |

The free-space numbers are local to a reader, not interoperability rules.

## File archive

### Layout

The Apple writer writes the entries in this order; readers must not depend on it.

| Entry | Content |
| --- | --- |
| `journal.sqlite` | A consistent SQLite online-backup snapshot of the library in rollback-journal (`DELETE`) mode, as described under [Database](#database) |
| `attachments/<UUID>` | Each image file exactly as the library stores it (already encrypted), one entry per file, in name order |
| `archive.json` | The header, last: it holds the manifest, which needs every hash |

A writer produces no other names: no folder entries, no extra files, no comment, no marker entry. A tool recognizes a file archive by `archive.json` carrying `archiveVersion`. A file archive is saved with the extension `.journalarchive`; if the Apple file type decision ([the archive design](../docs/design/1-1-archive-v2.md), 6.2) ends at its last rung, the extension becomes `.journalbackup` and this document and the fixtures say so then. A reader never decides by extension. The media type, where one is needed (an Android intent filter, a web upload), is `application/x-journalarchive+zip` (unregistered), not `application/zip`, which would offer the file to every archive tool.

### ZIP profile: writers

- One disk; no spanning; no ZIP-level encryption and no encrypted central directory. The Apple writer uses no data descriptors.
- Compression method 0 (stored). Records and images are already ciphertext or compressed data. A writer may deflate `journal.sqlite` only, and only if the compressed size is at least `bytes / 4`; otherwise it stores the entry. A database with large zero-filled regions deflates far beyond the expansion limit, and a reader refuses such an archive as damaged.
- General-purpose flags 0 (names are ASCII).
- CRC-32 and sizes in the local header and the central directory; the writer fills in the local header after streaming the entry's data.
- Modification time fixed at 1980-01-01 00:00:00 (DOS date `0x0021`, time `0`), so the container carries no per-file times. The sealed manifest has a random nonce, so the whole file is not reproducible.
- "Version made by" 20 with host system 0 (MS-DOS), external attributes 0: no Unix permissions, no symbolic link bits.
- ZIP64: whenever a size or an offset is 2^32 − 1 or more, or there are 65,535 entries or more, use the ZIP64 end-of-central-directory record, its locator and the `0x0001` extra field. A writer may use ZIP64 for smaller archives. A library with a thousand or two photos can exceed 4 GiB, so ZIP64 is part of the normal profile.

### ZIP profile: readers

A reader accepts: methods 0 (stored) and 8 (deflate, raw); flag bit 3 (data descriptor; the reader never scans for a descriptor signature) and bit 11 (UTF-8); ZIP64 structures also when they are not needed; unknown extra fields and an archive comment (ignored); any entry order; any times, attributes and "version" fields (ignored).

**Local and central headers.** The central directory is authoritative for sizes, CRC-32, method and offsets. A local header must have the signature `PK\3\4`, the same name bytes and the same method as the central entry. Its sizes and CRC-32 are always ignored, whether or not flag bit 3 is set and whether or not they are saturated with a ZIP64 extra field (a reader that compared them would refuse what .NET or Info-ZIP writes). The data starts at the local header offset + 30 + the local name length + the local extra length, which may differ from the central lengths.

**End records.**

- The end record is the last `22 + commentLength` bytes of the file. The reader scans backward (at most 65,557 bytes) only for candidates whose comment length reaches the end of the file, and considers exactly one. If a second candidate also reaches the end of the file (an end record forged inside a comment, even an internally consistent one), the archive is damaged; no reader picks between them. Bytes after the comment leave no candidate and are damaged too.
- The disk number and the central directory's disk are 0. The entry count of the end record equals the number of entries parsed from the central directory, and the entries account for every byte of the directory. The central directory starts inside the file and ends exactly where the end record (or the ZIP64 end record) begins.
- If a ZIP64 locator (`PK\6\7`) immediately precedes the end record, the ZIP64 end record it names is used. Every field of the ordinary end record that is not saturated (`0xFFFF`, `0xFFFFFFFF`) must equal the ZIP64 value; a disagreement is damaged. The ZIP64 record's size is at least 44, it lies before the locator, and its disk numbers are 0. Without a locator, a saturated field in the end record is damaged.
- The ZIP64 extra field of an entry carries only the members whose 32-bit field is saturated, in the order uncompressed size, compressed size, local header offset, disk number; a short or missing value is damaged, and so are two ZIP64 extra fields on one entry whose field is consulted (readers disagree about which counts). When no field is saturated the extra fields are not consulted at all.
- Central directory encryption (flag bit 13 on any entry) is damaged, as is any entry whose name, extra field or comment runs past the end of the directory.

**Entries the profile names.** The reader keeps in memory only entries named `archive.json`, `journal.sqlite` or `attachments/<UUID>`, compared as bytes. Every other name (including one that differs from a profile name only by case, or that contains NUL, a backslash or `..`) is skipped as it streams past and is never stored. A duplicate of any profile name, including a UUID-named entry the manifest does not list, is damaged: the reader stores all profile-shaped names before it has opened the manifest, and two readers that stored only listed names would disagree.

**Entry data.**

- A stored entry requires `compressedSize == bytes`. A deflate entry with a compressed size of 0 is damaged; the two-byte empty deflate stream with `bytes == 0` is valid, and so is a zero-length stored entry. Refuse when `bytes > 8 × compressedSize`.
- A deflate stream must end exactly at the declared compressed size (no early end, no unused bytes after the final block) and must produce exactly `bytes` bytes. A reader stops at the declared size and never writes more.
- The CRC-32 of the output must equal the central directory's. It is checked before the SHA-256 and, for `archive.json`, before the file is decoded, so a stale CRC-32 is damaged even where the content would say newer. The SHA-256 in the manifest is the authority; the CRC-32 only catches damage early.
- A listed entry that uses encryption (flag bit 0 or 6; method 99) or a method other than 0 or 8 is damaged. Unlisted entries, whatever their flags or method, are never opened.
- The data range of `archive.json` and of each listed entry (from its local header's first byte to the end of its data) lies inside the file before the central directory and overlaps no other such range.

All offset, size and count arithmetic uses unsigned 64-bit integers with overflow detection; an overflow is damaged.

A reader on a platform whose ZIP library reads every entry when it opens an archive (.NET `ZipArchive`, Android `ZipFile`) reads the end record first, checks the central directory size (64 MiB) and entry count (300,000), and only then opens the library: otherwise the limits cannot be enforced before the password is asked. Such a library also neither checks CRC-32, duplicate names or overlap, nor compares sizes with the manifest, so the reader applies the rules above itself.

### `archive.json`

```json
{
  "archiveVersion": 2,
  "recovery": { "salt": "…", "wrappedKey": "…", "iterations": 600000, "formatVersion": 2 },
  "manifest": "<base64>"
}
```

- `archiveVersion` is 2. A greater value is newer: the reader stops with the newer-version message. A missing, non-integer or smaller value is damaged.
- `recovery` is the library's recovery envelope, exactly as GET /v1/recovery returns it. Its bounds are the CPU limit before the password is asked, and every reader enforces them: `salt` is 16 bytes (base64), `iterations` 100,000 to 2,000,000, `formatVersion` 1 or 2. A file archive is always encrypted, so recovery format 3 or 4 is damaged here.
- `manifest` is base64 of the AES-256-GCM combined bytes (nonce, ciphertext, tag) of the manifest JSON, sealed with the vault key and the additional authenticated data **`journal:v{archiveVersion}:archive`**, that is `journal:v2:archive`. The directory archive used `journal:v1:archive`. A manifest that does not authenticate is damaged.
- The header holds only the wrapped key, never a vault key, password, recovery key, App Lock secret or device credential.

The manifest has no format number:

```json
{
  "database": { "sha256": "<lower-case hex>", "bytes": 86016 },
  "attachments": { "<UUID>": { "sha256": "<lower-case hex>", "bytes": 70 } }
}
```

It lists `journal.sqlite` and every image file the library holds, including images used only by earlier versions or deleted entries. `bytes` is the entry's uncompressed length and must equal the central directory's. Unknown members are ignored.

### What the integrity mechanism protects

The sealed manifest, under the vault key, authenticates the database's hash and size and the set of images with their hashes and sizes. Unwrapping the vault key authenticates the envelope's salt, iterations and `formatVersion`, which are in the wrapping's additional authenticated data. It does not authenticate the ZIP structure, the members of `archive.json` other than through those two, unlisted entries, or any library identity or time: a genuine older archive of the same library restores, so rollback is undetectable. Truncation is caught by a missing end record, a missing central directory or a missing listed entry. The string `journal:v{archiveVersion}:archive` also binds the version: the manifest of a future `archiveVersion` 3 is sealed under another string, so editing the unauthenticated digit downward cannot make a version 2 reader accept a version 3 manifest, and editing it upward cannot make a version 3 reader skip checks. A file archive never has an unauthenticated manifest, so weaker validation cannot be forced by moving authenticated bytes between containers.

What anyone holding the file sees:

| Layer | Protected by | Visible |
| --- | --- | --- |
| ZIP structure, entry names, sizes | Nothing | That it is a My Journal archive, how many images, each image's UUID and size, the database size |
| `recovery` | Wrapped key under the password (PBKDF2, 600,000 iterations) | Salt, iterations, `formatVersion` and the wrapped key: **offline password guessing material**, so the password's strength is the protection ([README.md](README.md#recovery-formats)) |
| Manifest | AES-256-GCM with the vault key | Nothing |
| `journal.sqlite` as a file | Nothing: SQLite is readable | Schema; per record its ID, kind, revision, whether it has an unsent change (`dirty`), conflict rows, history rows with their `saved` times and checkpoint flag, outbox operation IDs, the settings table (`content-protection`, `cursor`, `server-id` and the sealed keys below), the number and size of records |
| Record `payload` columns | AES-256-GCM, additional authenticated data `journal:v1:record:{kind}:{id}` | Nothing |
| Image files | AES-256-GCM, additional authenticated data `journal:v1:attachment:{id}` | Size only |

The metadata exposed is what the library's own sync log would show a server ([SECURITY.md](../SECURITY.md)).

### Reading a file archive

1. Open the file once and keep the handle. Find the end records, check the central directory size and entry count, and read the central directory keeping only the profile names.
2. Read `archive.json` (declared size at most 16 MiB, CRC-32 checked before decoding). Check `archiveVersion` and the envelope bounds. Asking the person for a password happens here, before anything proportional to the library is read.
3. Recover the vault key from the typed credential (the existing rules of [README.md](README.md#recovery-formats)), open the manifest, require authentication, parse it.
4. Validate the manifest: every key is a UUID, every `bytes` is within the limits and equal to the central directory's, every listed entry is present and readable.
5. Check the data ranges, then free space, then create the staging folder.
6. Extract only the listed entries, `journal.sqlite` first, in chunks, into files whose names the reader builds from the validated UUIDs. SHA-256, CRC-32 and a byte count are updated as the bytes are written, and the three must match (count, CRC-32, then SHA-256) at the end. Cancellation is checked between chunks.
7. Inspect the database before it is opened as a library ([Database](#database)), then open it, apply any migrations it is missing, refuse a database written by a newer version, and check the schema, integrity and the authentication of every record, history row, conflict and image.

One pass over each file replaces copying and then hashing: the bytes hashed are the bytes written.

### Writing a file archive

1. Save the open entry and check the library: integrity, the authentication of every record, history row and conflict, and that every referenced image is present. Check free space.
2. Back up the database to a temporary file (SQLite online backup, then `journal_mode = DELETE`).
3. Create the archive file exclusively with owner-only permissions. Write `journal.sqlite` (hashing as it streams), then each image listed in the snapshot's `attachments` table from the library's own file, in name order, in chunks. Images never change once written, so reading them from the library while the snapshot is archived is safe; a file that is missing or changes size is an error. The temporary database is deleted as soon as its entry is written.
4. Build and seal the manifest, write `archive.json`, the central directory and the end records.
5. On any error or cancellation remove the archive file and the temporary database; a destination that already existed is never removed.

Memory is bounded by the chunk size, the central directory and the manifest.

## Directory archive

Made by My Journal 1.0 and read by later Apple versions; no other client writes or reads it.

- `archive.json`: a UTF-8 JSON header, at most 16 MiB.
- `journal.sqlite`: a consistent SQLite online-backup snapshot in rollback-journal (`DELETE`) mode: one self-contained file with no `-wal` or `-shm` files.
- `attachments/<UUID>`: each image file exactly as the library stores it.

The header has three members:

| Member | Meaning |
| --- | --- |
| `version` | 1 for libraries with a password or recovery key (recovery formats 1–3), 2 for libraries without a password (format 4). A reader rejects a version that doesn't match the envelope's format, and unknown versions |
| `recovery` | The library's recovery envelope, exactly as GET /v1/recovery returns it |
| `manifest` | Base64. In version 1, the AES-256-GCM combined bytes of the manifest JSON, sealed with the vault key and additional authenticated data `journal:v1:archive`. In version 2, the manifest JSON itself |

The manifest JSON is `{"database": "<SHA-256 of journal.sqlite>", "attachments": {"<UUID>": "<SHA-256>"}}`. It lists every image in `attachments/`. In version 1 the authenticated manifest protects the whole folder against changes; recovering the vault key needs the password or recovery key. In version 2 the checksums detect accidental damage, not deliberate changes, restoring needs no password, and the manifest is attacker-written when someone hands over a folder: a key such as `../x` would otherwise reach outside the folder being restored.

A reader of a directory archive applies the [rules for both kinds](#rules-for-both-kinds) and the [limits](#limits): it checks every manifest key before any file operation; checks that `journal.sqlite`, `attachments/` and each listed image are what they should be (regular files, a real folder, no links) and within the size limits before copying; checks free space; and copies each listed file once, counting bytes and hashing as it writes, refusing a file that grows past its limit. It copies only `journal.sqlite` and the listed images into a new folder, so a folder changed during copying is refused, and ignores everything else (a name in `attachments/` that is not a UUID, an unlisted image, dot files such as `.DS_Store` and the AppleDouble `._` files that appear when a folder is copied between volumes, and other top-level files). It then continues as for a file archive from [step 7](#reading-a-file-archive).

## Database

The database is the library's own store. A file archive makes cross-platform restore the headline, so its structure is part of the contract and not an Apple implementation detail. The following is normative for both kinds.

- **Migrations.** The table `grdb_migrations` has one column, `identifier` (text, primary key), and holds the identifiers of the migrations that built the schema, in this order: `v1`, `sync-reconciliation`, `history-record-index`, `history-checkpoints`, `server-versions`. The name belongs to the format, whatever library a client uses. A new migration is a change to the archive format and must keep older archives readable. A writer that is not the Apple app records every migration its schema includes, as the first ones in this order, and writes exactly the objects those migrations create. A reader applies the migrations that are not recorded, in order, so the recorded ones must be a prefix of the list: an identifier the reader does not know is newer, and a recorded migration whose objects are missing, or recorded ones that are not a prefix, are damaged.
- **File header.** The SQLite file's read and write format versions (bytes 18 and 19) are 1: the snapshot has `journal_mode = DELETE`, and a database in write-ahead logging mode (2 and 2) is damaged.
- **Structure check.** Before the database is opened as a library, a reader inspects it, read-only, with `trusted_schema` off and SQLite's defensive mode on, in this order. Each step must be safe given the ones before it, because the file is attacker-written, and opening it costs whatever it was built to cost:
  1. **The schema table's size, from the file's pages, before any SQL runs.** SQLite parses every row of `sqlite_master` the first time a statement is prepared, so a file with a million `CREATE VIEW` rows would take minutes and hundreds of megabytes to open. The reader walks the b-tree of the schema table from page 1 (the page size is at bytes 16 and 17 of the file; table b-tree pages are type 0x05, interior, and 0x0D, leaf; the SQLite file format document describes them) and refuses a file with more than 64 cells, more than 256 KiB of cell payload (the size each cell declares, overflow pages included), more than 256 pages visited, a page visited twice, a tree deeper than 20, a page that is not a table b-tree page, or a cell outside its page. Only then does it open the file with SQLite.
  2. **The objects the schema lists.** Only tables and indexes, each with pages of its own (`rootpage` above 0, which a virtual table, a view and a trigger never have) and a statement (except the index SQLite makes for a primary key or a `UNIQUE` constraint, named `sqlite_autoindex_…`), each named like one the migrations create (`sqlite_sequence` included), and no statement containing, outside quotes and comments, one of the words `AS`, `CHECK`, `COLLATE`, `CONFLICT`, `DEFERRABLE`, `GENERATED` or `VIRTUAL`. These are the clauses no pragma reports that change what a table does: a `CHECK` that rejects writes, a `COLLATE` that changes what is equal, `ON CONFLICT` that turns an insert into a replace, constraints checked at commit, a generated column written without `GENERATED`, and a virtual table. A *word* is a run of ASCII letters, digits, `_` and `$` and of bytes of 0x80 or more (SQLite reads those as one identifier), compared in upper case; quoted text is `'…'`, `"…"`, `` `…` `` and `[…]`, and comments are `-- …` to the end of the line and `/* … */`; an unterminated quote or comment runs to the end. A virtual table connects, which runs its module's code, the first time a statement or a pragma refers to it, and `PRAGMA quick_check` refers to every table, so this step comes first.
  3. `PRAGMA quick_check` must report `ok`, so no migration runs `ALTER TABLE` on a malformed file and nothing below reads one. It reads every page of the file, which the reader has already extracted and hashed, so it is bounded by cancellation and not by a clock.
  4. The recorded migrations (`SELECT identifier FROM grdb_migrations ORDER BY rowid`, at most as many rows as there are known migrations plus one: more is a repeated or unknown identifier) and the structure, which must equal what the recorded migrations create. The check compares **structure, not `CREATE` text**, because EF Core, Microsoft.Data.Sqlite and GRDB write different text for the same table: tables (ordinary ones: not virtual, not `WITHOUT ROWID`, not `STRICT`, from `PRAGMA table_list`); columns (name, declared type in upper case, NOT NULL, default value with outer parentheses ignored, primary key position) from `PRAGMA table_xinfo`, where a hidden or generated column (`hidden` not 0) is refused, since `table_info` leaves those out; indexes (the name for one made with `CREATE INDEX`; uniqueness; whether partial; key columns) from `PRAGMA index_list` and `index_xinfo`; foreign keys (parent table, the columns, `ON UPDATE`, `ON DELETE`, `MATCH`, upper case) from `PRAGMA foreign_key_list`, where a key that names no parent column means the parent's primary key and is read as that column; and whether the statement says `AUTOINCREMENT` (`history.id` does, so `sqlite_sequence` exists). A primary key column counts as NOT NULL whether or not it says so. `grdb_migrations` is compared by its column and primary key only, and `sqlite_sequence` is ignored. Extra tables, indexes, triggers and views are damaged: triggers and views would act on later writes.

  The reader does not run migrations, switch the file to write-ahead logging or write to it until the check has passed, and the connections it then keeps to the restored library also have `trusted_schema` off and defensive mode on. After the migrations the same comparison runs again against the full structure. Restoring opens the extracted file in place and does not copy its rows into a freshly migrated database; the reasons are in [the archive design](../docs/design/1-1-archive-v2.md) (implementation notes).
- [conformance/archive/v2/database-v2.json](conformance/archive/README.md) lists the structure after each migration, and `database/foreign.sqlite` is an empty library written by Python's `sqlite3` module, not by GRDB, which every reader must accept, as must the same library on small pages and with a foreign key that names no parent column; its variants (an extra trigger, view or table, a virtual table, a missing or nullable column, a generated column, a `CHECK`, a `COLLATE`, a foreign key action or deferral, `ON CONFLICT`, `WITHOUT ROWID`, `STRICT`, no `AUTOINCREMENT`, an unknown migration, a recorded migration without its objects, migrations out of order, write-ahead logging) must be refused. They hold no records, because a script cannot seal records; restoring a database with records that another client wrote is proven by the first real archive from that client.

IDs are lower-case UUID text. Payloads are the base64 sync payloads: encrypted records in formats 1 and 2, base64 of the record JSON in formats 3 and 4. Local timestamps are whole-second UTC ISO 8601 text, such as `2026-09-27T10:00:00Z`.

| Table | Columns |
| --- | --- |
| `records` | `id` (TEXT, primary key), `kind` (TEXT NOT NULL), `payload` (TEXT NOT NULL, current version), `revision` (INTEGER NOT NULL DEFAULT 0, the server revision it is based on), `dirty` (INTEGER NOT NULL DEFAULT 1, 1 while a local change isn't acknowledged by the server) |
| `outbox` | `operation` (TEXT, primary key; operation UUID), `record` (TEXT NOT NULL, unique, references `records`), `kind` (TEXT NOT NULL), `payload` (TEXT NOT NULL), `base` (INTEGER NOT NULL; base revision): the pending request, sent unchanged until acknowledged |
| `conflicts` | `record` (TEXT, primary key, references `records`), `payload` (TEXT NOT NULL), `revision` (INTEGER NOT NULL), `device` (TEXT NOT NULL), `modified` (TEXT NOT NULL): the other version of a record awaiting review; the local version is in `records` |
| `history` | `id` (INTEGER, primary key), `record` (TEXT NOT NULL), `kind` (TEXT NOT NULL), `payload` (TEXT NOT NULL), `saved` (TEXT NOT NULL), `checkpoint` (INTEGER NOT NULL DEFAULT 0): earlier versions shown in Version History. `checkpoint` is 1 for a version kept automatically from ordinary changes ([version checkpoints](../docs/design/version-checkpoints.md)) and 0 otherwise. Only checkpoints are removed to keep at most 50 per record. A row may have no current record. Indexed by `record` (`history_record`) |
| `settings` | `key` (TEXT, primary key), `value` (BLOB NOT NULL; UTF-8 text) |
| `attachments` | `id` (TEXT, primary key), `uploaded` (INTEGER NOT NULL DEFAULT 0): 0 not yet on the server, 1 on the server, 2 to be checked after a server restore |
| `reconcile_heads` | `record` (TEXT, primary key), `kind` (TEXT NOT NULL), `payload` (TEXT NOT NULL), `revision` (INTEGER NOT NULL), `cursor` (INTEGER NOT NULL), `device` (TEXT NOT NULL), `modified` (TEXT NOT NULL), `seen_payload` (TEXT): the server's latest version of each record while re-reading a restored server |
| `server_versions` | `record` (TEXT, primary key), `revision` (INTEGER NOT NULL), `digest` (TEXT NOT NULL; lower-case hex SHA-256 of the payload text): the version the server holds at that revision of the record, as this device last sent or received it. A change at that revision with another payload means the server lost a version it accepted, and becomes a review |

Settings keys: `content-protection` (`encrypted` or `plaintext`, fixed when the library is created), `cursor` (the last applied server cursor, as decimal text), `cursor-change` (JSON `{"recordId", "revision", "digest"}` of the change at that cursor, when known; `digest` is the lower-case hex SHA-256 of its payload text and may be missing), `sent-change` (JSON `{"serverID", "cursor", "change"}`: the newest change this device sent that the server accepted, with `change` as in `cursor-change`), `server-id` (the server identity last synchronized with), `reconcile` (JSON state while re-reading a restored server), `merge-queued` (JSON object from derived record ID to digests of what a merge into a server queued for sending: of each payload, and of its record content without deletion state and modification time; see [join-with-local-journals.md](../docs/design/join-with-local-journals.md) §2.1), `library-changes` (this device's unconfirmed changes to the [library record](records.md#the-library-record): base64 text of the JSON `{"version": 1, "changes": {key: {"value", "removes", "ifAbsent", "sent"}}}`, with `"unknownLineage": true` while the device's earlier changes are unknown because a stored value couldn't be read, sealed in encrypted libraries like a record payload with additional authenticated data `journal:v1:local:library-changes`; a value that can't be opened is ignored and blocks nothing), `kept-notes` (local notes and automatic copies of [conflicts.md](conflicts.md): base64 text of the JSON `{"version": 1, "copies": [...], "notes": [...], "passStep": n}`, sealed in encrypted libraries like `library-changes` with additional authenticated data `journal:v1:local:kept-notes`; a value that can't be opened is ignored and blocks nothing; it adds no table or migration, and 1.0 opens archives that carry it) and `server-record-kinds` (`1` when the server last synchronized with takes the library record, `0` when it doesn't; 1.1 no longer writes it and ignores it when present). Readers ignore keys they don't know. The library record is a row of `records` like any other; restoring an archive on an empty device keeps it, its unsent changes and its queued operation.

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

A restore refuses an existing destination. It extracts into a new staging folder named with a fixed prefix and a UUID, which it creates exclusively: the folder is made without its parents, and a folder that is there already (or appears between a check and the creation) is an error, never taken over. If copying, checking or opening fails, or the restore is cancelled, it closes the database and removes only the folder it created; the archive and other folders are untouched. A restore that fails validation never returns a usable library. A staging folder left behind when the app was killed is removed the next time the app starts, unless a library the configuration names uses it.

Export owns its new file or folder only once it has created it: a failed snapshot, inventory or header write removes the partial archive and any temporary copy of the database, and a destination that already existed is never treated as its own. Cancellation is checked before work, between chunks and before completion; a single SQLite backup can't be interrupted. A file archive is written once to a staged file in the app's own storage and then handed to the system's save step; when that step is a copy to another volume the peak is two archives, which the export cannot check in advance, and a destination that fills is reported with nothing saved and the staged file removed.

Importing into an existing library owns its staging folder and new Keychain entry until the configuration pointer is saved. A failure before then removes both and keeps the current library and the inspected archive for another attempt. After the pointer is saved, cleanup never removes the installed library.
