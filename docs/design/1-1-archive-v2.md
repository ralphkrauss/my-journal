# 1.1 single-file archive (file archive) — 2026-10-09, revised after review

Status: design for the owner and for the mandatory design gate in [AGENTS.md](../../AGENTS.md). Nothing is built. The first independent review said "revise and re-review"; the second approved with changes. This body includes both, and [Changes after review](#changes-after-review) maps every finding to what changed. The file type spike (section 6.2) and the reader code (the ship gate in 4.4) still need review; this record does not. Scope record: [release-1-1-scope.md](release-1-1-scope.md) ("Single-file archive"). Answers open question D29 in [spec/open-questions.md](../../spec/open-questions.md). The server half of the 1.1 protocol work is in [1-1-server-cleanup.md](1-1-server-cleanup.md); encryption is in [1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md).

The archive becomes one file: a ZIP container holding the same SQLite snapshot and the same image files as today, plus a header and an inventory. The record formats, the encryption of records and images, and the database schema do not change. The Apple app keeps reading the 1.0 directory package. A Windows (or later Android) client builds on the single file directly.

Decided before this design (not reopened here): 1.1 writes only the file archive and keeps reading the directory archive; 1.1 always exports encrypted archives ([1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md), section 3.5).

## 1. Naming

The 1.0 protocol document already uses "version" twice: the header's `version` is 1 (libraries with a password, recovery formats 1 to 3) or 2 (libraries without one, format 4), and the recovery envelope has its own `formatVersion`. To avoid more numbers meaning more things, this design uses words, not numbers, in prose and specs:

- **Directory archive**: the 1.0 package (`archive.json`, `journal.sqlite`, `attachments/`). Its header keeps `version` 1 or 2 exactly as documented.
- **File archive**: the single file of this design. Its header member is `archiveVersion: 2`. It has no `version`, no second copy of the number in the manifest, and no pairing with the recovery format.
- Fixtures: `protocol/conformance/archive/v1/` (directory archives, unchanged) and `archive/v2/` (file archives; the folder name follows the fixture-version rule, not a new prose term).

## 2. Current state, with evidence

| Piece | Where | What it does today |
| --- | --- | --- |
| Format | [protocol/archive.md](../../protocol/archive.md); `apps/apple/Packages/JournalCore/Sources/JournalCore/Archive.swift` (`VaultArchive`) | A directory with `archive.json`, `journal.sqlite` and `attachments/<lower-case uuid>`. The header holds the recovery envelope and the manifest, sealed with AAD `journal:v1:archive` for recovery formats 1 to 3 and plain for format 4. The manifest lists the SHA-256 of the database and of every image. |
| Export | `Store.swift:834-874` (`snapshot`, `copySnapshot`), `Archive.swift` (`export`, `inventory`), `Model/DocumentTransferOperations.swift:49-70` (`prepareArchive`) | Copies the database by SQLite backup, copies **every image file** into a new directory, hashes them all again (four at a time), writes `archive.json` last. The save dialog then copies the whole package once more. |
| Import | `Archive.swift` (`restore`, `requiresPassword`), `DocumentTransferOperations.swift:16-35` (`inspectArchive`) | Reads `archive.json` (at most 16 MiB), recovers the key, copies the listed files into a staging directory under the app's data folder, hashes the copies, opens the database, then checks schema, integrity and that every record, history row, conflict and image authenticates. |
| File type | `apps/apple/project.yml:36-46` and `96-106`; `Views/ExportView.swift:5-7`; `RootView.swift:150,223`; `ArchiveView.swift:83-88` | Exported type `org.privatejournal.archive`, extension `journalarchive`, `UTTypeConformsTo: [com.apple.package]`, document role Viewer, rank Owner, on iOS and Mac. `JournalFile` wraps the directory with `FileWrapper(url:)` for `fileExporter`. The type is frozen: [apps/apple/AGENTS.md](../../apps/apple/AGENTS.md), [docs/architecture.md](../architecture.md) Compatibility rules. |
| Cleanup of leftovers | `DocumentTransferOperations.swift` (`ArchiveExportLeftovers`) | Removes `export-<uuid>.journalarchive` and the save dialog's dated copies, but only when the item is a **directory** ("never files"). |
| Tests | `JournalCoreTests`: `ArchiveTests`, `ArchivePackageTests`, `ArchiveHistoryTests`, `ImportLifecycleTests`, `ConformanceArchiveTests`; `JournalTests/ArchiveLifecycleTests`; `JournalFileTests/ArchiveFileUITests` (real save and pick round trip); server: `ArchiveConformanceTests` (an independent .NET reader) | |
| Windows plan | `spec/platforms/windows/flows/export-archive.md`, `import-archive.md`, `platform.md` 16 and 19 | Written for one file (the D29 draft default); blocked on this protocol change. |

Why a file: `FileSavePicker` cannot create a directory, `FileOpenPicker` cannot pick one and a folder cannot carry a file association on Windows; a folder is also easy to copy half-way or sync half-way, and cannot be sent as one object ([D29](../../spec/open-questions.md)). On Apple, a package cannot be attached to a message or shared by AirDrop without being zipped first. The current export also writes the library's images twice before the person has saved anything.

### 2.1 Path traversal in the directory reader: fixed on main (review Blocker 1)

The review found that `VaultArchive.restore` used each manifest key as a path component before checking it. For a version 2 header the manifest is plain JSON anyone can write, so a key such as `../x` reached outside the staging folder. **This is fixed in commit 6ca3ba2**: `restore` refuses any manifest key that is not a lower-case UUID before any file operation, with a test in `ArchiveTests`, and [protocol/archive.md](../../protocol/archive.md) (Reading an archive) says that a key that isn't a lower-case UUID makes the archive invalid and that a reader checks every key before using it as a file name. This record treats that as done and adds only what the fix leaves open:

- A conformance case in `archive/v1/unlisted-files-v1.json` (section 8.2) pins it for every reader, including Windows: a version 2 header whose plain manifest lists `../x` must be refused before any file is created, checked by asserting that nothing was created.
- The retained directory reader also checks that `journal.sqlite` and each source it copies are regular files, not links, and that `attachments/` is a real folder (the code still calls `copyItem` on all of them without checking, reading from the source first). This is **part of the change**, not a promise, and 4.6 gives the directory reader the same limits as the file reader.
- 1.0 shipped the flaw. Whether a 1.0.x carries the one-line fix is outside this record.

### 2.2 The directory archive's documentation and code disagree on unlisted files

[protocol/archive.md](../../protocol/archive.md) (Reading an archive) says any name in `attachments/` that is not a lower-case UUID, a symbolic link or a non-regular file makes the archive invalid, and that restore "checks that the files in `attachments/` and the database match [the manifest] exactly". The code differs:

- The Swift restore copies only the files the manifest lists, then hashes the copy (`Archive.swift` `restore` and `verify`). A file the manifest doesn't list is never read, so an extra file doesn't make it refuse (the [conformance README](../../protocol/conformance/README.md) Known issues records this).
- Only the Swift *writer's* inventory refuses a non-UUID name, in its own freshly written directory.
- The .NET reader in `ArchiveConformanceTests.FilesDiffer` follows the document: it compares the files found with the files listed and refuses a difference.

So two implementations already disagree, and a Windows reader written from the document would refuse archives that the Apple app restores. Section 4.5 resolves it for both archive kinds; AGENTS.md reserves the choice to the owner, so it comes back as a short confirmation (section 11).

## 3. The container

A file archive is a ZIP file (APPNOTE 6.3.x) restricted to a narrow profile. The profile is deliberately small so that a reader can be strict about hostile input and so that .NET's `System.IO.Compression.ZipArchive`, Android's `ZipFile` and a short Swift implementation all handle it.

**Only password-protected libraries have file archives.** A file archive carries recovery format 1 or 2 (a library protected by a master password or a legacy recovery key), and its manifest is always sealed. 1.1 always exports encrypted archives, so no 1.1 writer produces recovery format 3 or 4, and a reader that sees one in a file archive refuses it as damaged. The plain-manifest reader exists only for directory archives made by 1.0. Windows and Android never handle an unauthenticated manifest.

### 3.1 Layout

Entries, in the order the Apple writer writes them (readers must not depend on the order):

| Entry | Content |
| --- | --- |
| `journal.sqlite` | A consistent SQLite online-backup snapshot of the library in rollback-journal (`DELETE`) mode, exactly as in a directory archive. |
| `attachments/<lower-case UUID>` | Each image file exactly as the library stores it (already encrypted), one entry per file, sorted by name. |
| `archive.json` | The header, last: it holds the manifest, which needs every hash. |

No other names are produced: no directory entries, no extra files, no comment. There is deliberately no marker entry; a tool recognizes a file archive by its extension and by `archive.json` carrying `archiveVersion`.

### 3.2 ZIP profile

This section and 3.3 to 4.7 are written to go into [protocol/archive.md](../../protocol/archive.md) nearly word for word, because a Windows reader is written from that document alone.

**Writers**

- One disk; no spanning; no ZIP-level encryption or encrypted central directory; the Apple writer uses no data descriptors.
- Compression method 0 (stored) in the Apple writer. Records and images are already ciphertext or compressed image data; deflating them saves almost nothing. A writer may deflate `journal.sqlite` only, and **only if the compressed size is at least `bytes / 4`; otherwise it stores the entry**. The reader refuses an entry that expands more than 8 times (4.6); a database with large zero-filled regions (freed pages, preallocated pages) deflates far beyond that, so a writer that compressed it blindly would produce an archive the Apple reader calls damaged.
- General-purpose flags 0 (names are ASCII).
- CRC-32 and sizes in the local header and the central directory; the writer fills in the local header after streaming the entry's data.
- Modification time fixed at 1980-01-01 00:00:00 (DOS date `0x0021`, time `0`), so the archive carries no per-file times and the container bytes are reproducible. (The sealed manifest uses a random nonce, so the whole file is not.)
- "Version made by" 20 with host system 0 (MS-DOS) and external attributes 0: no Unix permissions, no symbolic link bits.
- ZIP64: whenever a size or offset is 2^32 − 1 or more, or there are 65,535 entries or more, use the ZIP64 end-of-central-directory record, its locator and the `0x0001` extra field. A writer may use ZIP64 for smaller archives. A library with a thousand or two photos can exceed 4 GiB, so ZIP64 is part of the normal profile.

**Readers must accept:** methods 0 and 8 (deflate); flag bit 3 (data descriptor; the reader never scans for a descriptor signature) and bit 11 (UTF-8); ZIP64 structures also when not needed; unknown extra fields and an archive comment (ignored); any entry order.

**Local and central headers.** The central directory is authoritative for sizes, CRC-32, method and offsets. A local header must have the same name bytes and the same method; **its sizes and CRC-32 are always ignored**, whether or not flag bit 3 is set and whether or not they are saturated with a ZIP64 extra field. (A reader that compared them would refuse what .NET or Info-ZIP writes.) The data offset is the local header offset + 30 + the **local** name length + the **local** extra length, which may differ from the central ones.

**End records.**

- The end record must be the last `22 + commentLength` bytes of the file. The reader scans backward only to find candidates whose comment length reaches the end of the file; it considers exactly one. If a second candidate also reaches the end of the file (an end record forged inside a comment, even an internally consistent one), the archive is refused as invalid structure; no reader picks between them.
- The entry count in the end record must equal the number of entries parsed from the central directory; the central directory must start inside the file and end exactly where the end record (or the ZIP64 end record) begins.
- If a ZIP64 locator exists, the ZIP64 end record is used, and **every field of the ordinary end record that is not saturated must equal the ZIP64 value**; a disagreement is invalid structure. The ZIP64 extra field of an entry carries only the members whose 32-bit field is saturated, in the order uncompressed size, compressed size, local header offset, disk number; a short or missing value is invalid.
- The disk number and the central directory's disk are 0.

**Entry data.**

- A stored entry (method 0) requires `compressedSize == bytes`. A deflate entry (method 8) with a compressed size of 0 is invalid; the empty stream (two bytes) with `bytes == 0` is valid, and a zero-length stored entry is valid.
- **Deflate must end exactly at the declared compressed size** (no unused bytes after the final block, no early end) and must produce exactly `bytes` bytes of output. Refuse when `bytes > 8 * compressedSize`.
- The CRC-32 of the output must equal the central directory's; a mismatch is damaged, and **it is checked before the SHA-256**, and for `archive.json` before decoding. The SHA-256 in the manifest is the authority; the CRC-32 only catches damage early.

**Refuse as damaged:** a *listed* entry that uses encryption (flag bits 0 or 6; method 99) or a method other than 0 or 8; central-directory encryption (flag bit 13 on any entry); the whole archive when the end record, ZIP64 records or central directory are missing, inconsistent or overlapping (5.2). Unlisted entries, whatever their flags or method, are never opened and are ignored.

**Names and UUIDs.** Names are compared as bytes. A UUID anywhere in this format (an entry name, a manifest key) matches exactly `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`; "parse, then lower-case" is not equivalent (`Guid.TryParse` accepts braces, no hyphens and upper case). No version or variant bits are checked.

### 3.3 `archive.json`

UTF-8 JSON, at most 16 MiB (the directory archive's limit: about 100,000 images, far beyond a real library). Duplicate member names, in the header or the manifest, make the file invalid (parsers disagree about which duplicate wins; a duplicate `recovery` would give two readers two envelopes).

```json
{
  "archiveVersion": 2,
  "recovery": { "salt": "…", "wrappedKey": "…", "iterations": 600000, "formatVersion": 2 },
  "manifest": "<base64>"
}
```

- `archiveVersion` is 2. A greater value is "newer": the reader stops with the existing newer-version error. Unknown members are ignored.
- `recovery` is the library's recovery envelope exactly as in a directory archive. Its bounds are the CPU limit before the password prompt and every reader enforces them: `salt` 16 bytes, `iterations` 100,000 to 2,000,000, `formatVersion` 1 or 2 (the same bounds the Apple reader uses when deriving).
- `manifest` is base64 of the AES-256-GCM combined bytes (nonce, ciphertext, tag) of the manifest JSON, sealed with the vault key and AAD **`journal:v{archiveVersion}:archive`**, that is `journal:v2:archive` (the directory archive used `journal:v1:archive`). See 3.4 for what this binds.
- The header holds only the wrapped key, never a vault key, password, recovery key, App Lock secret or device credential.

The manifest JSON has no format number:

```json
{
  "database": { "sha256": "<lower-case hex>", "bytes": 86016 },
  "attachments": { "<lower-case UUID>": { "sha256": "<lower-case hex>", "bytes": 70 } }
}
```

It lists `journal.sqlite` and every image the library holds, including images used only by earlier versions or deleted entries. `bytes` is the entry's uncompressed length and must equal the central directory's. It is a non-negative JSON integer of at most 2^53 − 1, so .NET `long`, JavaScript and Swift agree; a float, a negative number or an exponent form is invalid. A key that doesn't match the UUID expression of 3.2 makes the archive invalid. **Unknown members of the manifest are ignored** (so it can grow), as the header's are.

### 3.4 What the integrity mechanism protects, and what is exposed

The sealed manifest, under the vault key, authenticates: the database's hash and size, the set of images, their hashes and sizes. Unwrapping the vault key authenticates the envelope's salt, iterations and `formatVersion`, which are in the wrapping's AAD. It does **not** authenticate the ZIP structure, `archive.json`'s own members other than through those two, unlisted entries, or any library identity or time: a genuine older archive of the same library restores, so rollback is undetectable, as in a directory archive. Truncation is caught by a missing end record, a missing central directory or a missing listed entry. The AAD string `journal:v{archiveVersion}:archive` is also the version binding: the manifest of a future `archiveVersion` 3 is sealed under another string, so editing the unauthenticated `archiveVersion` digit downward cannot make a version 2 reader accept a version 3 manifest, and editing it upward cannot make a version 3 reader skip checks. That is why each archive version uses its own string. Moving authenticated bytes between containers gains an attacker nothing else; the control against weaker validation is that a file archive refuses any recovery format other than 1 or 2.

What each layer shows to anyone holding the file:

| Layer | Protected by | Visible |
| --- | --- | --- |
| ZIP structure, entry names, sizes | Nothing | That it is a My Journal archive, how many images, each image's UUID and size, the database size |
| `archive.json` `recovery` | Wrapped key under the password (PBKDF2, 600,000 iterations) | Salt, iterations, `formatVersion` and the wrapped key: **offline password guessing material**, so the master password's strength is the protection ([protocol/README.md](../../protocol/README.md) Recovery formats) |
| Manifest | AES-256-GCM with the vault key | Nothing |
| `journal.sqlite` as a file | Nothing: SQLite readable | Schema; per record: ID, kind, revision, whether it has an unsent change (`dirty`), conflict rows, history rows with their `saved` times and checkpoint flag, outbox operation IDs, the settings table (`content-protection`, `cursor`, `server-id`, and the sealed keys below), the number and size of records |
| Record `payload` columns | AES-256-GCM, AAD `journal:v1:record:{kind}:{id}` | Nothing |
| Image files | AES-256-GCM, AAD `journal:v1:attachment:{id}` | Size only |

The metadata exposed is the same as in a directory archive and is what the library's own sync log would show a server ([SECURITY.md](../../SECURITY.md)). Sealing the database as a whole would stop a reader from querying it without extracting it first; closing that is later work.

**Settings keys paragraph of `protocol/archive.md` (carries a sentence from the conflicts design).** The paragraph keeps "Readers ignore keys they don't know", and gains: "`kept-notes`: local notes and automatic copies, sealed like `library-changes`" — i.e. base64 text of JSON, sealed in encrypted libraries with AAD `journal:v1:local:kept-notes`, a value that can't be opened is ignored and blocks nothing ([1-1-conflicts-and-reconnect.md](1-1-conflicts-and-reconnect.md)). It adds no table, migration or archive number; 1.0 opens archives that carry it, and a restore on an empty device keeps it with the library. The list of settings keys also notes that `server-record-kinds` is no longer written by 1.1 and is ignored when present ([1-1-server-cleanup.md](1-1-server-cleanup.md), section 3.3).

### 3.4.1 The database contract is normative (`grdb_migrations`)

A file archive makes cross-platform restore the headline, so the database inside it is part of the contract, not an Apple implementation detail. `protocol/archive.md` already lists the tables; this makes the following normative, for both archive kinds:

- The database has a table `grdb_migrations` with one column, `identifier` (text, primary key), holding the identifiers of the migrations that built the schema: `v1`, `sync-reconciliation`, `history-record-index`, `history-checkpoints`, `server-versions`. The name belongs to the format, whatever library a client uses.
- **A non-Apple writer records every migration its schema includes**, and writes exactly the objects those migrations create. A reader applies only the migrations that are not recorded, in order. An identifier this reader doesn't know is the existing "newer" case; a recorded migration whose objects are missing is a refusal.
- The file's header read and write versions (bytes 18 and 19) are 1: the database is in rollback-journal mode (the snapshot has `journal_mode = DELETE`).
- The structure check compares **structure, not `CREATE` text**: tables, columns (name, declared type, not-null, default, primary key position), indexes and their uniqueness and columns, from `PRAGMA table_info`, `index_list` and `index_xinfo`, because EF Core, Microsoft.Data.Sqlite and GRDB write different text for the same table. Extra tables, indexes, triggers and views are refused.
- Fixtures: `archive/v2/database/foreign.sqlite`, an empty library built by a non-GRDB writer (a short Python `sqlite3` script, not Apple code), which the Swift and .NET readers must both accept, with negative variants (an extra trigger, a missing column, an unknown migration, header versions 2). It has no records, because Python cannot seal records; restoring a Windows-written database with records is proven by the first real Windows archive (section 12).

### 3.5 Compression: decision note

The Apple writer stores everything. If a 1.1 measurement on a text-heavy library shows `journal.sqlite` dominating the archive, a later writer may deflate that one entry without any contract change, because readers already accept method 8.

## 4. Reading and writing

### 4.1 Telling the kinds apart

The picker or the system hands over a URL. A directory is a directory archive (`archive.json` inside). A regular file is read as a file archive. A file that is not a ZIP, or whose `archive.json` has no `archiveVersion`, is "not an archive" and reported as damaged. A directory without `archive.json` is the same. There is no sniffing by extension.

A directory whose `archive.json` has `archiveVersion` (what Archive Utility or Windows Explorer produces if someone unpacks a file archive) is not a directory archive: the directory reader's existing header check refuses it as damaged, and that outcome is tested, not accidental. A symbolic link in place of `archive.json`, `journal.sqlite` or `attachments/` is refused, and the reader never follows one.

### 4.2 Reader order (file archive)

All offset, size and count arithmetic uses unsigned 64-bit integers with overflow-reporting operations; any overflow is "damaged". Swift traps on overflow, and a trap on a hostile file is a crash.

1. Open the file once and keep the handle. Find the end record (3.2): scan back at most 65,557 bytes for candidates whose comment length reaches the end of the file; exactly one is considered. Follow the ZIP64 locator if present and check the ordinary record against it. Require that the central directory starts inside the file, ends exactly where the end record (or ZIP64 record) begins, and holds the entry count the end record gives.
   **Windows and Android readers** read the end record first, check the central directory size (64 MiB) and entry count (300,000) from it, and only then open `ZipArchive` or `ZipFile`, which materialize every entry; otherwise the pre-prompt limits cannot be enforced there.
2. Read the central directory (at most **64 MiB and 300,000 entries**). Keep in memory only entries whose name matches the profile (`archive.json`, `journal.sqlite`, `attachments/<UUID>` by the expression of 3.2), compared as bytes; any other name (including one that differs from a profile name only by case, or contains NUL, backslash or `..`) is skipped as it streams past and never stored. **A duplicate of any profile name, including a UUID-named entry the manifest later turns out not to list, refuses the archive**: the reader stores all profile-shaped names before the manifest is open, and two readers that stored only listed names would disagree.
3. Read `archive.json` (declared size at most 16 MiB; CRC-32 checked before decoding; expansion limit in 4.6). Refuse duplicate member names. Check `archiveVersion` and the envelope bounds of 3.3.
   `requiresPassword(at:)` stops here, so the sheet asks for a password before any large read. Nothing proportional to the library has been read.
4. Recover the vault key from the typed password or recovery key (existing rules), open the manifest with AAD `journal:v2:archive`, require successful authentication, parse it.
5. Validate the manifest: every attachment key matches the UUID expression, every `bytes` is within 4.6 and equal to the central directory's, every listed entry is present.
6. Check data ranges: the range of `archive.json` and of each listed entry (local header start through the end of its data) lies inside the file before the central directory and overlaps no other such range.
7. Check free space (4.6) before any write; if short, fail with the existing "couldn't open … enough space" error.
8. Create the staging directory (named `import-<uuid>`, see 6.3) and extract only the listed entries, `journal.sqlite` first. For each: seek to its local header, check signature, name bytes and method against the central directory, read in chunks of 256 KiB (inflating if the method is 8), write to a file whose name the reader builds from the validated UUID (never from the entry name), and update SHA-256, CRC-32 and a byte count as it goes. Stop at the first byte beyond the declared size; for deflate require the stream to end exactly at the compressed size. At the end require byte count, CRC-32 and then SHA-256 to match. Check for cancellation between chunks.
9. **Inspect the database before opening it as a store** (a separate function, run on the staged file before `JournalStore` is created, because `JournalStore.init` runs `PRAGMA journal_mode = WAL` and the migrations): open it read-only with `trusted_schema = OFF` and `SQLITE_DBCONFIG_DEFENSIVE`; run `PRAGMA quick_check` so migrations never run `ALTER TABLE` on a malformed file; require header read and write versions 1; read `grdb_migrations` and compare the structure with what the recorded migrations create (3.4.1); refuse any trigger or view they do not create. Only then create the store, apply missing migrations, refuse a newer database, and run the existing schema check, integrity check and authentication of every record, history row, conflict and image. The same function runs for the directory archive.

One pass over each file replaces the directory archive's copy followed by hashing the copy. The bytes hashed are the bytes written.

### 4.3 Writer order (file archive)

1. Save the open entry and run the existing preflight (`validateSnapshot` with `requireComplete`), as today. Check free space on the data volume (4.6): at least the database size plus the sum of the image sizes plus 256 MiB. If short, stop with the existing "not enough space" message.
2. Back up the database to a temporary file (SQLite online backup, then `journal_mode = DELETE`), as `copySnapshot` does now.
3. Create the **staged archive** `export-<uuid>.journalarchive` in the app's data folder, exclusively with owner-only permissions. Write `journal.sqlite` (hashing as it streams), then each image listed in the snapshot's `attachments` table from the library's own file, sorted by UUID, in chunks of 256 KiB. Images never change once written, so reading them from the library while the snapshot is archived is safe; a file missing or changed in size is an error reported as `messages.export.archiveFailed` as today (open question A29 asks for a more specific message; unchanged here). Delete the temporary database as soon as its entry is written.
4. Build and seal the manifest, write `archive.json`, the central directory and the end records.
5. On any error or cancellation remove the staged archive and the temporary database.
6. **Hand the staged file to the system's save step** (6.2). A move is a rename only when the destination is on the same volume as the app's data folder (On My iPhone, the Mac's boot volume). For iCloud Drive, an external drive, another Mac volume or any file provider it is a copy followed by a delete, so the peak is the staged archive plus the destination copy, and the free-space check above does not cover the destination. If the destination fills, the failure is mapped to `messages.export.archiveNoSpace` (when the system reports no space) or `messages.export.archiveSaveFailed`; the staged file is removed and the person is told nothing was saved. The spike records the peak on both volumes (6.2 criterion 1).

Memory is bounded by the chunk size, the central directory and the manifest.

### 4.4 Implementation approach, and conditions

A small purpose-built reader and writer in JournalCore (`ArchiveContainer.swift`, no dependency), using `Compression` for inflate (`COMPRESSION_ZLIB` is raw deflate) and the system `crc32`. Reasons, as [AGENTS.md](../../AGENTS.md) asks for new dependencies: the profile is narrow; a general ZIP library (ZIPFoundation, minizip) would still need the same validation layer on top (overlap, duplicate names, local and central agreement, declared-size and ratio caps, manifest binding), none of which they provide; every accepted feature is attack surface for a reader of hostile input; and JournalCore has only two external dependencies (GRDB and swift-markdown). The container code is behind `VaultArchive`, whose public functions keep their signatures.

Conditions on shipping it (from review finding 6):

1. **Reader review is a ship gate**: a security-focused review of the reader code by someone who did not write it.
2. **Mutation sweep test**: on a tiny archive, flip each byte of the local headers, central directory and end records, truncate at every header boundary, duplicate and shuffle entries; assert only termination, bounded memory and a clean `invalidData` (or acceptance where the profile allows). Runs in seconds.
3. **Independent tools read the writer's output** in a script (not only the .NET test): `unzip -t` and `zipinfo`, Python `zipfile`, and `bsdtar` or 7-Zip where installed. The script lives with the Apple tests, is not part of the default lane, and is run before each release.
4. **Overflow-safe arithmetic** as in 4.2, with no force unwraps.
5. **CRC-32 and inflate performance**: use the system `crc32` (a byte-at-a-time table does about 0.3 to 0.5 GB/s in Swift); keep the raw-deflate decoder behind the declared-size and expansion caps of 4.6.

### 4.5 Unknown and extra entries (resolves the directory archive conflict too)

The rule for both archive kinds: **a reader processes exactly the entries or files the manifest lists, reads nothing else, and ignores everything else.** Listed means `journal.sqlite` and each `attachments/<UUID>` in the manifest.

- Ignored without comment: `__MACOSX/…`, `.DS_Store`, AppleDouble `._*` files, directory entries, any other unlisted entry or file including a UUID-named image the manifest doesn't list (once, see below), and any unlisted entry with an unknown flag or method.
- Errors: a listed entry that is missing, differs in size, CRC-32 or hash, uses an unsupported method or encryption, or has a mismatched local header; **a duplicate of any profile name in a file archive, including an unlisted UUID-named one** (4.2 step 2); overlapping data ranges; a central directory that doesn't fit; a manifest key that doesn't match the UUID expression (the fix in 2.1) or is duplicated; and, in a **directory archive**, a listed name that is a symbolic link or not a regular file.
- Nothing unlisted is ever extracted, and the file names on disk come from UUIDs the reader parsed, not from entry names, so there is no path traversal.

Reasons for ignoring rather than refusing: refusing turns clutter that a file manager or sync service adds into an archive nobody can restore; ignoring cannot lose library data, because anything the library needs is in the manifest and the database check fails if a referenced image is missing; and it is what the Apple reader has always done. For directory archives this changes the document, not the code: [protocol/archive.md](../../protocol/archive.md) says the same, and the .NET test reader in `ArchiveConformanceTests.FilesDiffer` compares only the listed files.

### 4.6 Limits a reader enforces

The container limits below apply to the file archive reader, and the **size limits (25 MiB per image, 32 GiB database, free space, byte counts while copying instead of a bare `copyItem`) apply to the directory reader as well**, because it is reachable on every 1.1 install from any folder someone hands over, and its plain version 2 manifest is attacker-written.

| Item | Limit |
| --- | --- |
| `archive.json` | 16 MiB (about 100,000 images; the image count needs no separate limit) |
| Central directory | 64 MiB, 300,000 entries |
| One image | 25 MiB (`JournalStore.maximumAttachmentBytes`, also the server's attachment limit) |
| `journal.sqlite` | 32 GiB |
| Expansion | refuse an entry when `bytes > 8 * compressedSize` (integer arithmetic). Payloads are ciphertext and images are compressed, so a real entry is near 1; stored entries are exactly 1. Checked against the central directory before reading, and again by stopping at the declared size |
| Free space on restore or import | the volume holding the staging folder must have at least **2 × the sum of the declared `bytes` + 256 MiB** (the staging copy plus the install, which writes the images again), checked before any write and ceilinged by 1 TiB total declared |
| Free space on export | at least the database size + the sum of the image sizes + 256 MiB on the data volume (the database copy is deleted once written, so this is conservative); the destination volume is not checked in advance (4.3 step 6) |
| Read per entry | the declared size, never more |
| Chunk | 256 KiB |
| Memory before the password prompt | the header (16 MiB, three to four times that while decoding) and the profile-named central-directory entries; nothing else |

A limit hit is reported as damaged (5.1), except free space, which uses the existing space messages. The free-space numbers are reader-local, not interoperability rules, and a test with a stubbed free-space value covers them. The expansion cap matters because even a sealed manifest is only as trustworthy as the person who chose the password: a person who is sent a file and "the password is X" controls every declared size.

### 4.7 Hostile input

| Threat | Defense |
| --- | --- |
| Path traversal, absolute or backslash names | Entry names are only compared to the fixed names and to manifest UUIDs; they never reach the file system. In the directory archive, manifest keys are checked before use (2.1) |
| Zip bomb (small file, huge output) | Declared sizes in the authenticated manifest, an 8× expansion cap in integer arithmetic, exact deflate consumption, a free-space check that counts the install, extraction that stops at the declared size, no nested archives |
| Overlapping entries | Data ranges of `archive.json` and the listed entries are sorted and must not overlap each other or the central directory |
| Duplicate profile names, a second end record, an end record forged inside a comment | Duplicates are an error; exactly one end-record candidate may reach the end of the file; counts must match the parsed directory |
| Memory exhaustion before the prompt | 16 MiB header, 64 MiB / 300,000-entry directory, unknown names never stored; Windows and Android check the directory size before opening a library |
| Symbolic links, devices | ZIP attributes are ignored and no entry is created by name; the directory reader refuses links in place of `archive.json`, `journal.sqlite` and `attachments/` and for listed files |
| Truncation, a half copy, damaged media | Central directory missing, CRC-32, SHA-256 and byte counts all fail |
| A swapped or altered listed file | The manifest is authenticated; every listed file is hashed against it |
| An older genuine archive | Not detectable (3.4); the person chose the file |
| A hostile database | In a file archive the database is bound by the sealed manifest, so only someone who knows the password can craft one. The unauthenticated path is the **directory archive** (plain manifest). Both: inspected read-only before any store is created, with `trusted_schema = OFF`, defensive mode, `quick_check`, header versions and the structural comparison (4.2 step 9) |
| A folder that holds an unpacked file archive | Refused as damaged by the directory reader's header check (4.1) |
| Overflowing offsets and sizes | `UInt64` with overflow-reporting arithmetic |

## 5. Limits and failures in the app

### 5.1 Error mapping (no new copy)

The app already maps core errors to existing messages (`ArchiveView.swift:273-282`):

| Reader result | Core error | Message key |
| --- | --- | --- |
| Not a ZIP, no `archiveVersion`, structure invalid, entry or size or hash mismatch, listed entry missing, unsupported method or encryption, recovery format 3 or 4, over limits | `invalidData` | `settings.archiveImport.error.damaged` |
| `archiveVersion` greater than 2, or a database written by a newer app | `unsupportedFormat` / `newerVersion` | `settings.archiveImport.error.newerVersion` |
| Wrong password or recovery key | existing | `settings.archiveImport.error.wrongPassword` |
| Out of space, file unavailable, cancelled while a cloud file downloads, anything else | other | `settings.archiveImport.error.couldntOpen` |

### 5.2 Structure checks, exact

An archive is structurally invalid when: no end record, or more than one candidate reaches the end of the file; the end record, the ZIP64 records or the entry count don't agree with the central directory; a ZIP64 field is saturated without its extra value, or the extra field is short; an entry's local header is outside the file, has a bad signature or a different name or method; a data range crosses the central directory or another listed range (including `archive.json`); a profile name occurs twice; disk numbers are not 0; a central directory entry's name, extra or comment length runs past the directory; a listed compressed size exceeds the file; or any arithmetic overflows.

### 5.3 Progress and cloud files

The existing indicators are enough: Preparing Archive… (after 0.3 s) on export, Opening Archive… on import. An archive on iCloud Drive that is not downloaded can take minutes to read through its security-scoped URL with no determinate progress; cancelling during the wait must work (checked in the spike). If a large-library measurement shows import taking minutes, a determinate progress bar is a separate small design.

## 6. User-visible change and the design gate

The change is almost entirely below the interface. There are no new strings, screens, controls or settings.

### 6.1 What the person notices

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Export Archive… | Same sheet row, same indicator; the system save dialog now saves one file. Files shows a document icon and a size instead of a package. The file can be shared by AirDrop, Messages or Mail without zipping it first. | Same as iPhone. | Same panel and suggested name `Journal Archive {yyyy-MM-dd}.journalarchive`; Finder shows a file with a size. It can be attached to a message. |
| Import Archive… | The Files picker selects the file; the Import Archive sheet is unchanged. | Same. | Same open panel. |
| Open from outside | Tapping the file in Files, Mail or AirDrop opens My Journal and the sheet (`RootView.swift:223` matches by extension, unchanged). | Same. | Double-click in Finder; drag onto the Dock icon. |
| Disk during export | The database copy, then one staged archive that is moved (on the same volume) or copied and deleted (iCloud Drive, an external drive, another volume) to the chosen place. The export checks free space on the device first and says "There isn’t enough space to export the archive…" if short; a destination that fills says the same, or "Couldn’t save the archive…", and nothing is saved. | Same. | Same. |
| An archive made by 1.0 (a package) | Still selectable and importable, with the same preview. | Same. | Same. |
| A 1.1 archive opened in 1.0 | 1.0 reads `archive.json` inside the path and finds none, and shows its generic "Couldn’t open this archive…". Whether a 1.0.x says "Update My Journal to open this archive." is decided after the spike, and only if rung (a) or (b) is taken (6.2). | Same. | Same. |

No existing string changes: `settings.backup.archiveFilename`, the footers, `messages.export.*` and `settings.archiveImport.*` still read correctly. The spec words "package" (in `flows/export-archive.md`: "Temporary package", "iPhone and iPad suggest the package's own name") become "file".

### 6.2 The file type: spike first, one owner decision for the whole ladder

The risky part of this design is what the operating system does with a regular file. Today the type conforms to `com.apple.package` (a directory type) and `JournalFile.fileWrapper` returns a directory wrapper. A regular file under a package content type is unusual and untested: `fileExporter`, document-based save, Files, iCloud Drive and the share sheet may each treat "package" as a directory. The declaration is frozen and the extension is a permanent public contract, so the spike runs before the container is built into the app. It runs on **the oldest supported iOS and macOS (the deployment targets) and the newest**, because file-provider and `fileExporter` behaviour for package types has changed between releases, on iPhone, iPad and Mac (Release build, real devices where the check needs one), using the existing `ArchiveFileUITests` round trip and by hand.

**Pass criteria with the declaration left exactly as it is** (`org.privatejournal.archive`, `com.apple.package`, extension `journalarchive`):

1. **Export.** `fileExporter` (and, on the Mac, document save and the save panel) with `contentType: .journalArchive` and a regular-file wrapper saves a file with the suggested name, for a 2 GiB test file, without holding it in memory. **Record the peak disk use on the data volume and on the destination for four destinations**: On My iPhone, iCloud Drive, an external drive, and a second Mac volume. A move is a rename only on one volume (4.3 step 6); the dialog's temporary copy (if any) must be known and cleaned. A full destination must end with the staged file removed and the message of 4.3 step 6.
2. **Import.** `fileImporter(allowedContentTypes: [.journalArchive])` lets the person select the file on iOS (Files: On My iPhone, iCloud Drive, an external drive) and macOS.
3. **Sharing.** The share sheet to Mail, Messages and AirDrop sends it as a file; receiving it offers My Journal.
4. **Opening.** From Files, Mail and AirDrop, and double-click in Finder, launches My Journal with the URL; Get Info and Quick Look say "Journal Archive"; Spotlight indexes the name.
5. **iCloud Drive.** Upload and download of a multi-gigabyte regular file typed as a package (iCloud synchronizes packages as bundles); an evicted file downloads when selected, and cancelling during the wait works. A Time Machine backup and a Finder copy of the same file behave as for a file.
6. **What the person sees.** After a successful export, Files and the Finder show a file with a size and a document icon. A "package" type on a regular file can show **Show Package Contents** in the Finder or a folder icon in Files; that is a failure and a rung (c) trigger, not a nuisance.
7. **Not claimed by archive tools.** Archive Utility, Safari's "open safe files after download" and Files' Uncompress do not offer to unpack it.
8. **A file written by another stack.** A regular `.journalarchive` ZIP produced on Windows, by .NET on any machine, or by Python `zipfile` (the `accept` samples of 8.1) opens on Apple through import: Windows-written archives are the point of the change.
9. **1.0 packages** still pass 2, 4 and 6 (a directory still shows as one item).

**Fallback ladder** (decision 1 asks the owner to approve all three rungs now, with the exact strings of rung (c), so a failed spike does not stall the release):

- **(a) Leave the declaration unchanged.** Taken if criteria 1 to 9 pass. Nothing else is needed.
- **(b) Stream through the system differently.** If criterion 1 fails because `FileDocument` buffers the file or copies it twice: on iOS `UIDocumentPickerViewController(forExporting: [url], asCopy: false)` of the staged file, on the Mac `NSSavePanel` then `moveItem` (a copy across volumes). The label of the iOS button for a move ("Move" rather than "Save") is checked and, if it reads badly, reported to the owner. If import criterion 2 fails, the importer also accepts `.data` and checks the extension (`JournalFile.readableContentTypes` already includes `.data`).
- **(c) A new exported type with its own extension for the file, declared next to the old package type.** Taken if criterion 3 to 7 or 8 fails and cannot be solved in (b). **The exact strings, approved now and permanent once shipped: type identifier `org.privatejournal.archive.file`, conforming to `public.data`, extension `journalbackup`, description "Journal Archive".** The old package type `org.privatejournal.archive` stays declared, unchanged, so 1.0 directories still open; the importer accepts both types; the suggested file name (`Journal Archive {yyyy-MM-dd}.journalbackup`), the Windows association, the Android intent filter and the fixtures' extension use the new string; the directory archive keeps `journalarchive`. This edits something [apps/apple/AGENTS.md](../../apps/apple/AGENTS.md) calls frozen only by *adding* a type, and it needs updates to that rule and to `docs/architecture.md`.
- **Rejected: making the existing type also conform to `public.zip-archive`.** It would make one type both a directory and data, and it invites archive tools to unpack a file meant to be kept whole (criterion 7). **Also rejected: retyping the old identifier to `public.data`**, which would turn every 1.0 package into a plain folder in Files and the Finder.

**Spike outcome, recorded here before the reader is built:** the rung taken, the peak disk numbers, and the decision on a 1.0.x. A 1.0.x that says "Update My Journal to open this archive." when it meets a regular file where it expected a directory is worth shipping only on rungs (a) and (b), where the 1.1 file has the extension 1.0 already registers. On rung (c) a 1.0 install neither registers nor lets the person pick the new extension, so the message could never appear. It is decided after the spike, and nothing is shipped for it before then.

### 6.3 Export flow: staged file, cleanup and hand-over

- **Cleaner.** `ArchiveExportLeftovers` today removes only directories ("never files"). It gets: a rule for directories (1.0 leftovers); a rule for **regular files** with the exact staged name `export-<uuid>.journalarchive` in the data folder and the exact dialog names `Journal Archive <yyyy-MM-dd>.journalarchive` (and the same with the extension of rung (c)) in the app's temporary folder; and a **directory rule for the restore and import staging directory**, which has the fixed name `import-<uuid>` (what `inspectArchive` creates today) and is removed at launch unless it is the current library's folder. Never links; nothing else. A killed restore therefore leaves nothing for good.
- **Hand-over.** One staged file, given to the system's save step (4.3 step 6; rung (b) if the spike needs it).
- **Free space** is checked before the export starts (4.3 step 1, 4.6).
- **Failure ownership.** The existing ownership rules (a failed or cancelled export removes only its own staged archive and temporary database; a destination that already existed is never treated as owned) stay and get the file tests of section 10.

### 6.4 Other platforms

- **Windows.** The extension is `.journalarchive` (or `.journalbackup` if rung (c) is taken, the string approved in decision 1), shown as "My Journal archive". `FileSavePicker` with one file type choice and `FileOpenPicker` filtered to it; the app writes with `System.IO.Compression.ZipArchive` in `ZipArchiveMode.Create` over a seekable temporary file, entry times set to 1980-01-01, then copies it to the picked file. Whether `CompressionLevel.NoCompression` writes method 0 or 8 must be confirmed per runtime (the profile accepts both). `ZipArchive` does **not** verify CRC-32 on read, check duplicate names or overlap, or compare sizes with a manifest, so the Windows reader must stream-hash and apply 4.2 and 4.5 itself, and read the end record and check the central directory size and entry count before it opens a `ZipArchive` (4.2 step 1). It writes entries with method 8 only if the compressed size is at least a quarter of the size (3.2). Explorer will not offer Extract All because the extension is not `.zip`. File type association in the MSIX manifest; the first instance receives the file activation ([platform.md](../../spec/platforms/windows/platform.md) 19).
- **Media type** for anywhere one is needed (Android intent filters, a web upload): `application/x-journalarchive+zip` (unregistered). Not `application/zip`, which would offer the file to every archive app.
- **Android** (later): `ZipFile` reads it and has the same duplicate-name and no-overlap blind spots as `ZipArchive`; SAF create/open document with that media type.
- Windows and Android never write or read a directory archive.

## 7. Compatibility matrix

| | Directory archive (from 1.0) | File archive (from 1.1) |
| --- | --- | --- |
| **Apple 1.0** | Writes and reads | Cannot read: generic "Couldn’t open this archive"; a 1.0.x with "Update My Journal…" is decided after the spike, rungs (a) and (b) only (6.2) |
| **Apple 1.1** | Reads (restore and import), never writes | Writes and reads; only recovery formats 1 and 2 |
| **Windows / Android** | Not supported, deliberately | Writes and reads |

Notes:

- A person with 1.0 on one device and 1.1 on another can move 1.0 archives to the new device but not the reverse. Most people update all their devices within days, so this is short-lived; the changelog says so in one line. There is no export-as-old-format option.
- An unencrypted 1.0 archive (recovery format 3 or 4, a directory archive) still restores in 1.1; the library is then encrypted by the required screen of [1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md). No 1.1 export produces one.
- The database inside an archive is the same on both kinds and on every platform. A Windows-made archive must use the same schema, including the `grdb_migrations` table, which this design makes normative (3.4.1) with a structural check and a non-GRDB fixture database.
- Server backups ([protocol/server-backup.md](../../protocol/server-backup.md)) are unaffected.
- The `Header` type, `inventory`, `verify` and `regularFile` in `Archive.swift` become the directory reader only; the directory writer is deleted (the app no longer writes directory archives), and its tests are rewritten for the file archive.

## 8. Conformance

Per [conformance README](../../protocol/conformance/README.md): new files beside the old; nothing existing edited in place.

### 8.1 `archive/v2/` (new)

Files whose extension would be `.journalarchive` are named `.zip` (the repository ignores `*.journalarchive`); a reader treats them as archives regardless of name.

| File | Content | Produced by |
| --- | --- | --- |
| `encrypted.zip` | The same small library as `archive/v1/encrypted` (recovery format 2), repackaged: `journal.sqlite` and the image are the v1 files byte for byte (so the database SHA-256 and the database content in `expected.json` are cross-checkable), `archive.json` is new with `archiveVersion: 2`, the envelope and a manifest sealed under `journal:v2:archive`. **No plaintext variant.** | Swift, once (random nonce), like v1 |
| `encrypted-recovery-key.zip` | A second sealed archive whose envelope is recovery format 1 (the legacy recovery key, its trimming and case rules; the envelope and key of `crypto/encryption-v1.json`), with an empty library so it stays small. Covers `derive` for format 1 in a file archive for every reader, not only Apple | Swift, once |
| `expected.json` | `archiveVersion`, the entry list with `dataOffset`, `bytes`, `method`, CRC-32 and SHA-256, the decoded manifest, the database as in v1 (`records`, `outbox`, `history`, `attachments`, `settings`, `migrations`) by reference to v1's file plus its hashes, the password, and `mutations` (below) | Swift |
| `database/foreign.sqlite` and `database-v2.json` | The empty-library database built by a **non-GRDB writer** (3.4.1) and the structural cases: accepted as is; refused with an extra trigger, a missing column, an unknown migration identifier, a recorded migration with its objects missing, and header versions 2 | A Python `sqlite3` script `database/make-foreign-database.py`, committed with the files |
| `container/*.zip` and `container-v2.json` | About 50 tiny archives that exercise the **container layer** only: ZIP structure plus extraction of the entries a given manifest lists. Each case supplies its manifest as plain JSON in `container-v2.json` (the container layer takes a manifest as input; header parsing and sealing are covered by `encrypted.zip`), so no case needs a key or a cipher. Each zip holds stand-in `journal.sqlite` and attachment bytes and an opaque `archive.json`. Real-tool samples are listed below | `container/make-container-cases.py`, deterministic, committed with the files. It assembles the bytes with `struct` (the invalid cases are forgeries `zipfile` cannot write) and uses Python `zipfile` only to read each `accept` case as a cross-check |
| README rows in `archive/README.md` and `container/README.md` | Layout, how to run, and for each real-tool sample the tool and version that wrote it | |

**Compared outcome.** A case's expectation is `accept`, or refusal with the message class of 5.1 (`damaged`, `newer`, `wrongPassword`, `couldntOpen`), never the reason words. Each case carries a non-normative `note` naming the defect; two readers may validly classify, for example, a forged end record differently inside the class and must not fail the fixture for it.

**`expected.json` mutations** apply to a copy of `encrypted.zip` (stored entries, so bytes change in place at the listed `dataOffset`). Because the reader checks the CRC-32 before anything else, each mutation lists its **CRC patches** (offset in the local header, offset in the central directory, new value) so the harness applies a consistent change and the check under test is the one that fires:

- one byte of an image or of `journal.sqlite`, with CRC patched → `damaged` (SHA-256 mismatch);
- the same two changes with the **CRC left stale** → `damaged` (CRC mismatch; proves the CRC is checked);
- one byte of the sealed manifest, CRC patched → `damaged` (authentication fails);
- the `archiveVersion` digit changed to 3, CRC of `archive.json` patched → `newer`; the same with the CRC stale → `damaged` (the CRC is checked before decoding, so a stale CRC always wins over "newer");
- the envelope's `formatVersion` digit changed to 4, CRC patched → `damaged` (refused before anything is read);
- the wrong password → `wrongPassword`; a manifest sealed under the directory archive's string → `damaged`.

**`container-v2.json` cases.**

- **Accepted:** stored entries; all entries deflated; data descriptors (sizes in the central directory only); a local header with flag bit 3 set and non-zero sizes; a local ZIP64 extra field while the central sizes are not saturated; ZIP64 structures on a small file; unknown extra fields and a comment; unlisted noise (`__MACOSX/._journal.sqlite`, `.DS_Store`, a `notes.txt`, a directory entry, an unlisted UUID-named file once, an unlisted entry with an unknown flag and method); entries in another order; an empty `attachments` map; a zero-length listed entry (stored) and an empty deflate stream; local name and extra lengths that differ from the central ones; names that differ from a profile name only by case (unlisted); a deflated entry of about 6× expansion; unknown members in the manifest.
- **Damaged, structure:** random bytes; a truncated file; central directory offset out of range; an end record whose comment length doesn't match; **two end-record candidates reaching the end of the file (a forgery inside a comment)**; an end record whose count differs from the parsed directory; an end record with a non-zero disk number; **ZIP64 and ordinary end records that disagree**; a size or offset near 2^64; a saturated ZIP64 field with no extra value; a ZIP64 extra field with too few values; a central directory entry whose extra or comment length runs past the directory; a listed compressed size larger than the file; a duplicate `journal.sqlite`; a duplicate **unlisted** UUID-named name; a local-header name or method that differs from the central directory's; two listed entries whose data overlap; a listed entry whose data range covers the central directory; `archive.json` overlapping a listed entry.
- **Damaged, entry:** encryption flag on a listed entry; method 12 and method 99 on a listed entry; central-directory-encryption flag (bit 13); a listed entry missing; size differs from the manifest or from the central directory; a stored entry whose compressed size isn't `bytes`; method 8 with compressed size 0; **stale CRC-32**; SHA-256 differs; a deflate stream that expands past its declared size (small file, large output; the reader must stop at the declared size and not write the surplus); deflate that ends before `bytes`; deflate with trailing bytes inside the compressed size; an expansion just over 8×; a manifest with duplicate JSON keys, a `bytes` that is a float, negative or above 2^53 − 1, or a key that isn't the UUID expression (upper case, braces, no hyphens, `../x`); `archive.json` with a duplicate `recovery` member or an envelope outside the bounds (iterations 99,999, salt of 15 bytes).
- **Too large:** an `archive.json` entry declaring more than 16 MiB (`damaged` class).
- **Real-tool `accept` samples**, each committed with the tool and version in `container/README.md`: .NET `ZipArchive` in `Create` mode over a seekable stream and over a non-seekable stream (data descriptors appear); Python `zipfile`; Info-ZIP `zip` (extended timestamp and Unix extra fields); macOS `ditto -c -k --sequesterRsrc` (the `__MACOSX` and `._` entries).

Every reader's own test reads each case through its own code and compares the outcome; for `accept` it checks the extracted bytes against the manifest. The .NET `ArchiveConformanceTests` gains a file archive reader in tests (using `ZipArchive` for entries and its own checks for the rest); that doubles as proof that a standard library reads what the Apple writer writes.

### 8.2 `archive/v1/` (existing, additions)

`unlisted-files-v1.json`: mutations a reader must accept for the encrypted directory archive (a non-dot, non-UUID file in `attachments/`, an unlisted UUID-named file), and the hostile cases of 2.1, 4.1 and 4.6:

- a directory archive with a plain (version 2) header whose manifest lists `../x` is refused before any file is created, checked by asserting that nothing was created outside or inside the destination (the fix of commit 6ca3ba2);
- a symbolic link in place of `journal.sqlite`, of a listed image and of `attachments/`: refused, nothing followed;
- a sparse `journal.sqlite` or image larger than the limits of 4.6: refused before it is copied;
- a folder holding an unpacked file archive (`archive.json` with `archiveVersion`): refused as damaged.

The plain-header packages for these cases are new small directories beside the others (no database is needed where the manifest check comes first). `expected.json` and the packages are untouched.

### 8.3 Other known issues (separate changes)

The [conformance README](../../protocol/conformance/README.md) lists seven. Those that touch archives or records are conformance fixes the scope allows, but each alters what records are accepted or written, so **each is its own small change with its own review and does not hold the archive release**. Fixtures keep their own versions. Proposals (each needs the owner's choice of which side is wrong; recommendations given):

| Issue | Touches | Proposal |
| --- | --- | --- |
| Timestamps: Swift accepts `2026-02-30T08:00:00Z` and hour 25; the docs say ISO 8601 | Records | Fix the Swift reader to reject impossible calendar fields. Other readers, including .NET's, already refuse them, so such a record would be readable on one platform and not another. Add `records/timestamps-v2.json` (invalid: 30 February, 29 February 2025, hour 25, minute 60, 31 April; valid: 29 February 2024; the leap second `:60` stays unpinned). A record whose date can't be read is already handled as unreadable and kept unchanged. |
| Directory archive, unlisted files | Archives | Section 4.5: ignore; edit the document and the .NET test reader, not the Swift code. |
| Attachment references in capitals | Records (Markdown); archive import remaps references | Write down what the code does: readers accept any letter case in the UUID, writers write lower case. Add `markdown/images-v2.json` and one import test that an entry with an upper-case reference keeps its image after an archive import. |
| Derived block identities that aren't version 4 UUIDs | Records | Documentation: [records.md](../../protocol/records.md) says readers must not validate UUID version or variant bits, plus a `records-v2.json` record that carries such an ID and must read as editable. |
| Link destinations with spaces: the Swift writer writes `a%20b`, which reads back differently | Records (stored Markdown) | Fix the writer: write a destination with spaces in the angle-bracket form (`[text](<a b>)`) and read both; stored text changes only when the block is edited. Cases in `markdown/documents-v2.json`. Changes stored text, so it gets its own review. |
| Heading text (CRLF), Unicode tables | Markdown export only | Out of scope. |

## 9. Spec and documentation changes (same change as the code)

- [protocol/archive.md](../../protocol/archive.md): take sections 3.2 to 3.4.1 and 4.1 to 4.7 nearly word for word (the interoperability rules there are normative text, each with a container case), and restructure as: the two kinds and how to tell them apart; directory archive (as today, with the unlisted-files rule and the already-fixed manifest-key rule); file archive (sections 3 and 4 here); the database, restore and import sections shared; the settings keys paragraph with the `kept-notes` sentence (3.4); file type and media type. Version note in [protocol/README.md](../../protocol/README.md) ("V4 archives use archive header version 2" says which kind); [docs/architecture.md](../architecture.md) line 64 and the Compatibility rules (a new file type only if rung (c) is taken).
- [protocol/conformance/README.md](../../protocol/conformance/README.md) layout table, Known issues (mark resolved with the version of the fixture that pins it), and `archive/README.md`.
- `spec/flows/export-archive.md`, `flows/import-archive.md`, `screens/archive-import.md`, `screens/settings-backup.md`: "package" becomes "file". `spec/parity.yaml`: new feature `archive-directory-read` (Apple shipped; Windows and Android `not-applicable`, reason "never wrote the directory archive"); `export-archive` and `import-archive` notes say "one file". `spec/platforms/apple/` notes for the file type and the export document; `spec/platforms/windows/flows/*archive*.md` and `platform.md` 16 and 19 lose the "draft default, needs a protocol change" wording; `spec/open-questions.md` D29 and B36 are marked resolved by this design (B36's two folder-fallback strings are dropped). `python3 spec/tools/check-spec.py` after.
- `docs/guide/backups.md` ("in one file" is now literally true; 1.0 archives still import; 1.1 archives need 1.1), `CHANGELOG.md` (one line on the 1.0 / 1.1 archive direction), `docs/guide/troubleshooting.md` if it mentions packages.
- `apps/apple/AGENTS.md` and `docs/architecture.md` only if rung (c) is taken.

## 10. Tests worth adding ("Useful tests only")

1. **Container conformance** (Swift, .NET): every case in `container-v2.json`, comparing the outcome class. Protects against hostile and damaged files and keeps two implementations in agreement. Highest value.
2. **Mutation sweep** (4.4 condition 2): termination, bounded memory, clean error, on a tiny archive.
3. **Round trip:** export a library with images, unsent edits, history and a conflict, restore it, and compare database rows and image bytes (adapts `ArchiveTests`); `encrypted-recovery-key.zip` restores for the legacy recovery key.
4. **Real fixtures:** `archive/v2/encrypted.zip` restores to the content in `expected.json`; every mutation, with its CRC patches, gives the stated outcome, and the stale-CRC variants are damaged; directory archive fixtures still restore (the existing tests, unchanged, prove 1.0 archives still import); the hostile directory cases of 8.2.
5. **Database inspection:** `foreign.sqlite` is accepted by the Swift reader (and by the .NET reader in `ArchiveConformanceTests`), and each negative variant is refused before any migration runs, for both archive kinds; a staged database with a trigger or view is refused before the store is created.
6. **Chunk boundaries and ZIP64:** the writer and reader take the chunk size and a "force ZIP64" switch as internal parameters; one test uses a 1-byte-small chunk on a few entries and forced ZIP64 and round trips.
7. **Failure ownership on files and directories:** a cancelled or failed export leaves no staged file or temporary database; relaunch removes a staged export, the dialog's dated copy **and an `import-<uuid>` staging directory left by a restore killed mid-extraction**, leaves links and the current library alone (real files); a failed restore removes only its staging directory.
8. **Free space:** with a stubbed free-space value, export refuses below database + images + 256 MiB and restore refuses below 2 × declared + 256 MiB, before writing anything.
9. **Import with upper-case attachment references** (8.3).
10. **UI:** the existing `ArchiveFileUITests` round trip with the file; it is the check for the spike.

Not added: tests of the SHA-256 or AES-GCM primitives, of `Data` handling, or one test per rejected flag combination outside the shared table.

### 10.1 Verification before reporting done

- The independent-tools script on a writer-produced archive (4.4 condition 3).
- A Release build on a real device and a Mac, with a library of several thousand images (a few GiB) built the way a long-lived library is, per the project's verification rules: export, check memory, time and disk, import on an empty device and as new journals, restore a 1.0 package, open the file from Files and Finder, repeat with App Lock on, and compare Settings, entry counts and a sample of images.
- The first archive written by a real Windows client restores on Apple, and the reverse (section 12).
- ZIP64 meets real sizes by hand once before release: one sparse entry above 4 GiB written and read back (the 2 GiB spike files cannot reach it; forced ZIP64 is the CI test).

## 11. Owner decisions

Decided before this record (not reopened): 1.1 writes only file archives and keeps reading directory archives; 1.1 always exports encrypted archives. Decided after the spike, not by the owner now: whether a 1.0.x says "Update My Journal to open this archive." (6.2, rungs (a) and (b) only).

1. **Approve the file type ladder's three rungs now**, so a failed spike does not stall the release. (a) Leave the declaration unchanged; (b) stream through the system differently and broaden the importer; (c) add a new exported type with the **exact strings: type identifier `org.privatejournal.archive.file`, conforming to `public.data`, extension `journalbackup`**, beside the unchanged old package type. Both strings of rung (c) are permanent once shipped and appear in fixtures and in the Windows association. Each rung is taken only when the one before cannot meet the criteria of 6.2. The zip-conformance idea and retyping the old identifier are rejected and not offered. **Recommendation: approve all three.**
2. **Unlisted files are ignored** in both archive kinds (4.5), with the exceptions stated there: manifest keys that aren't lower-case UUIDs, a listed link or non-regular file in a directory archive, and a duplicate profile name in a file archive are invalid. AGENTS.md reserves contract choices to the owner. **Recommendation: confirm.** The alternative, refusing extra files in the Swift reader, makes archives that have always restored stop restoring.
3. **`grdb_migrations` becomes normative, and the 8.3 conformance fixes ship as separate changes.** The migration table, its five identifiers, the header versions and the structural check become part of the format (3.4.1), proven by a non-GRDB fixture database now rather than discovered when Windows ships; the alternative, a `user_version`-based number, is a contract change not worth making for 1.1. The six known-issue proposals of 8.3 each get their own change and review and do not hold the archive release. **Recommendation: confirm both.**

## 12. Risks

- **File type behaviour on three operating systems is untested here.** The spike (6.2) comes first, before the container is built into the app; its criteria include the oldest supported OS versions, iCloud, a Windows-written file and what the Finder and Files show.
- **Our own ZIP code parses hostile input.** Mitigated by the narrow profile, normative interoperability rules each pinned by a container case, the manifest-bounded reads, the expansion cap, section 4.7, the mutation sweep and the shared cases; the cost is real code to maintain. The separate reader review is a ship gate.
- **Disk peaks on other volumes.** A move to iCloud Drive or an external drive is a copy; the export checks the device but cannot check the destination in advance. The spike measures it; a full destination ends cleanly with nothing saved.
- **`FileDocument` may buffer or copy a large file.** Rung (b) is specified.
- **.NET and other writers.** `ZipArchive` may write method 8 and data descriptors and stamps local times; the profile accepts all of those and the real-tool samples cover them, but the whole path is only proven when a real Windows-written archive restores on Apple. The first Windows archive is a cross-platform test.
- **A Windows-written database with records is not covered by a fixture.** `foreign.sqlite` proves the structure rule with an empty library, because the fixture script cannot seal records; the first real archive proves the rest.
- **Time to restore** a multi-gigabyte archive is unmeasured; extraction is sequential disk I/O plus SHA-256 and CRC-32, expected to be bound by storage.
- **1.0 apps** show a misleading message for a 1.1 archive until (and unless) a 1.0.x ships.

## Review log

The independent review of 2026-10-09 follows. The author's response and what changed are recorded after it. The container itself (sections 3 to 5) still needs a separate security-focused review of the reader code before it ships (finding 6).

## Independent review (2026-10-09)

Reviewer: an independent design and protocol reviewer, given the requirements and this proposal only. Checked against the code and documents, not against this record's references: `protocol/archive.md`, `Archive.swift` (all of it), `Store.swift` (`init`, `snapshot`, `copySnapshot`, `validateSchema`), `DocumentTransferOperations.swift` (`prepareArchive`, `ArchiveExportLeftovers`), `ExportView.swift` (`JournalFile`), the `UTExportedTypeDeclarations` in `apps/apple/project.yml`, `Crypto.swift` (`derive` bounds), the .NET reader in `ArchiveConformanceTests.FilesDiffer`, `protocol/conformance/README.md`, and [1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md) (simplification G). Nothing was built or run.

**Verdict: revise and re-review.** The container profile is narrow and mostly well chosen, the reader order is right (authenticate the manifest, bound every read by it, never build a path from an entry name), and a hand-written reader is defensible. But there is one Blocker in code this change keeps, several Material gaps that change the fixtures and the export flow, and the file-type question that decides whether the whole design works is still unanswered. Re-review after the spike result (finding 2) and the revisions to findings 1 and 3 to 5; the reader code needs its own review as the record says.

### Findings

1. **Blocker: the format 1 reader that 1.1 keeps has a path traversal through manifest keys, and the design leaves its code unchanged.** `VaultArchive.restore` copies `source/attachments/<key>` to `staging/attachments/<key>` for every key of the manifest, using the key as a path component, and checks that the keys look like UUIDs only afterwards (`verify` runs after `copyItem`; it also fails the restore but too late). For a version 2 header (libraries without a password) the manifest is plain JSON that anyone can write, so a key such as `../../x` makes `copyItem` read and create files outside the staging folder, anywhere in the app's sandbox that exists. For encrypted archives the manifest is authenticated, so only someone holding the vault key or the password can craft it. Section 4.5 says "no zip slip because names come from UUIDs the reader parsed" for format 2 only, and 7 says the format 1 reader stays as it is, so the claim does not cover the code that will keep running for years. 1.0 ships the same flaw. Fix: in the retained format 1 `restore`, before any file operation, require every manifest key to be a lower-case UUID that round-trips (`UUID(uuidString:)` and equal to its lower-cased form) and the database file and each source to be regular files; add a case to the new `unlisted-files-v1.json` (a manifest, plain version 2, with `../x` as a key must be refused before anything is copied, checked by asserting nothing was created); say in `protocol/archive.md` that manifest keys must be lower-case UUIDs, because the Windows reader is written from that document; and decide with the owner whether a 1.0.x should carry the one-line fix (it is in review now). It is a Blocker for implementation because the change cannot truthfully claim defence against hostile archives while retaining this.

2. **Material: the file-type spike is the whole feasibility question, and the fallback ladder is weaker than it looks.** Verified: `org.privatejournal.archive` conforms to `com.apple.package` (a directory type), and `JournalFile.fileWrapper` returns a directory wrapper today. Writing a regular-file wrapper under a package content type is unusual and untested: `fileExporter`, document-based save (macOS), Files, iCloud Drive and the share sheet may each treat "package" as a directory. Do the spike first and before the rest is built, as 6.2 says, and extend it: share sheet to Mail, Messages and AirDrop (not only Files and Finder); iCloud Drive with an evicted file (it will be the default place people keep backups); Quick Look and Spotlight; and the macOS save panel through `fileExporter` with a regular-file wrapper. Fallback (b) is a poor choice: a type conforming to both `com.apple.package` (a directory) and `public.zip-archive` (data) is contradictory, and a type that conforms to zip invites Archive Utility, Safari's "open safe files after download" and Files' Uncompress, which is exactly the opposite of what a single file for people to keep is for. Add before approval a decision, since the extension is a permanent public contract: if the spike fails, the ladder includes (c) a new exported type with its own extension for the file, declared next to the old package type, which stays so 1.0 directories still open; the importer accepts both. Ask the owner now, once, to approve the whole ladder including (c) in advance, so a failed spike does not stall the release. If the spike passes unchanged, nothing is needed.

3. **Material: the export flow does not do what 6.1 and 4.3 say about disk, and leftover files would never be cleaned.** (a) `ArchiveExportLeftovers.removePackages` removes only directories (`values?.isDirectory == true`; its comment says "never files"). The staged export `export-<uuid>.journalarchive` and the save dialog's copy in the temporary folder become regular files in format 2, so after a cancelled dialog, a crash or a quit during export a multi-gigabyte file stays forever. The record says the cleaner "keeps matching it"; it matches the name but then skips the item. (b) `removeDialogCopy` and the leftover rule for "the save dialog's copies in the app's own temporary folder" indicate that `fileExporter` makes a second copy there (to be confirmed in the spike), so the peak is the staged archive plus the dialog copy plus the saved file, three times the images, not "roughly one library plus the database copy". On a phone with a few gigabytes of photos that fails with a generic error. Fix: split the cleaner into a rule for directories (1.0 leftovers) and one for regular files with the exact staged and dialog names, never links, with a test on real files; stage once and hand the file over by move, not copy (`UIDocumentPickerViewController(forExporting:asCopy: false)` on iOS, save panel then `moveItem` on the same volume on the Mac), or write straight to a file the exporter then owns; check free space (database copy plus archive) before the export starts and map failure to the existing "couldn’t" message; correct the 6.1 sentence. Add the failure-ownership test for the file case (cancel, kill and relaunch leaves nothing).

4. **Material: format 2 should not have a plaintext variant.** Simplification G ([1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md): "1.1 always exports encrypted archives"; an unencrypted archive "can only come from 1.0 or earlier") means no 1.1 writer will ever produce recovery format 3 or 4 inside a format 2 file. As written, the reader accepts a plain manifest, the fixtures include `plaintext.zip`, section 3.4 and the hostile-input table carry the "not detected beyond accidents" rows, and, worst, declared sizes and hashes of such a file are attacker-controlled, which undermines the bomb defence in 4.7. Fix: define format 2 as recovery formats 1 and 2 only with a sealed manifest; a header whose envelope is format 3 or 4 is `unsupportedFormat`; drop `plaintext.zip` and its cases; keep the plain-manifest reader only for format 1 packages. Windows then never has to handle an unauthenticated manifest. If the owner would rather keep format 3 and 4 open for some later reason, say so, but record that it re-opens this finding and finding 5.

5. **Material: the bomb and memory limits rely on declared sizes and are too loose for a phone.** (a) Even a sealed manifest is only as trustworthy as the person who chose the password: an attacker who sends a file and "the password is X" controls every declared size. A deflate stream of a few kilobytes can expand about a thousandfold, so a small file can declare and then write up to the free space of the device (and take minutes of CPU) before the final hash check fails or, if the attacker computed the hash of zeros, passes. Fix: limit expansion, not only size. Because journal payloads are ciphertext or base64 of ciphertext and images are already compressed, any entry with `bytes` more than 8 times its compressed size is hostile; refuse it as damaged. Replace the 1 TiB total with `min(1 TiB, free space minus a reserve)`, count the staged copy and the later install (restore or import as new journals writes the images again) in the check, and keep the check before any write. (b) The central directory is read in full, up to 256 MiB and a million entries, and `archive.json` up to 64 MiB, before the password prompt (`requiresPassword` stops after step 4, so these reads happen first). AES-GCM needs the whole sealed manifest in memory, with base64 decode, plaintext and a parsed tree on top, roughly three to four times its size. A hostile file can push an iPhone over its memory limit before the person types anything. Fix: keep `archive.json` at 16 MiB (v1's limit, about 100,000 images at roughly 150 bytes of manifest each, far beyond a real library), limit the central directory to 64 MiB and 300,000 entries, and keep in memory only the entries the profile knows (`format`, `archive.json`, `journal.sqlite`, `attachments/<uuid>`) plus a hash set for duplicate detection of those; unlisted names are skipped as they stream past, never stored. The 250,000-image limit then follows from the 16 MiB header limit and can go.

6. **Material: a custom ZIP reader and writer is a reasonable choice, on conditions.** Agree with the reasoning in 4.4 for a stored-only writer and a narrow reader, and with the dependency rule: a general library (ZIPFoundation, minizip) would still need the same validation layer on top (overlap, duplicate names, local and central agreement, declared-size and ratio caps, manifest binding), none of which they provide, and would add a pinned dependency to a package that has two. The cost is that the reader parses hostile input and is written by the person who wrote the writer. Conditions: (a) the separate reader review in the record is a ship gate, by someone who did not write it; (b) a fast mutation sweep over the v2 fixture and a few container cases (flip each byte of the local headers, central directory and end records, truncate at every header boundary, duplicate and shuffle entries) asserting only termination, bounded memory and a clean `invalidData`; this is the test that protects hostile input and runs in seconds on a tiny archive; (c) the writer's output is read by independent tools in a script, not only the .NET test: `unzip -t` and `zipinfo`, Python `zipfile`, and 7-Zip or `bsdtar` if available; (d) all offset, size and count arithmetic in `UInt64` with overflow-reporting operations, because Swift traps on overflow and a trap is a crash on opening a hostile file (and AGENTS.md forbids force unwraps); (e) use the system zlib `crc32` rather than a byte-at-a-time table (about 0.3 to 0.5 GB/s in Swift, not the 1 GB/s assumed in section 12), and keep `Compression`'s raw-deflate decoder (`COMPRESSION_ZLIB`) behind the declared-size and ratio caps.

7. **Minor: reader details the record should pin, each as a container case.** Take the end record only when its comment length equals the bytes that follow it, and when the entry counts equal the parsed central directory (the "last valid" rule alone lets a comment end with a forged end record). ZIP64: the extra field carries only the members whose 32-bit field is saturated, in the order uncompressed size, compressed size, offset, disk; a short or missing value is invalid. The data offset is local header offset + 30 + the *local* name and extra lengths (they may differ from the central ones). Sizes never come from a data descriptor, and the reader never scans for its signature. Names are compared as bytes; a listed name that differs only in case, or contains NUL, backslash or `..`, is just an unlisted name. Manifest: duplicate JSON keys are invalid (Foundation keeps the last, Windows may keep the first), keys must be lower-case UUIDs, and `bytes` must equal the central directory's uncompressed size. Also refuse method 99 and bit 13 (central directory encryption) and ignore unlisted entries with any unknown flag or method. Add cases for each, plus a size and offset near 2^64, an entry whose data range covers the central directory, and a saturated ZIP64 field with no extra value.

8. **Minor: say plainly what the integrity mechanism protects, and drop two over-claims.** The sealed manifest, under the vault key, authenticates the database hash and size, the set of images, their hashes and sizes, and the manifest format. It does not authenticate the ZIP structure, the `format` entry, unlisted entries, or the envelope except indirectly (unwrapping the key authenticates the envelope's salt, iterations and `formatVersion`, which are in the AAD). It is not bound to a library identity or a time, so a genuine older archive of the same library restores: rollback is undetectable, as in format 1. Truncation is caught by the missing end record or central directory, or by a missing listed entry. The new AAD `journal:v2:archive` is harmless but buys nothing against downgrade: moving the same authenticated bytes between containers changes nothing the attacker can use. The real downgrade control, the check that the envelope's format matches the manifest rule, becomes unnecessary once finding 4 is adopted. Rewrite the "Downgrade or replay" row of 4.7 accordingly. Also, "writing the same inputs gives the same bytes" (3.2) is false for sealed manifests (random nonce); restrict it to the container.

9. **Minor: SQLite is opened before the schema is checked.** `JournalStore.init` runs `PRAGMA journal_mode = WAL` and the migrations; `validateSchema()` runs after. A hostile database (format 1 or 2) can carry triggers or views that fire during the migrations or the first reads. This exists in 1.0, but format 2 is the moment to close it: open the staged database with `PRAGMA trusted_schema = OFF`, compare `sqlite_master` with the expected schema (or require it to be a subset of what the known migrations create) before migrating, and reject on any difference. Keep the existing check afterwards.

10. **Minor: naming will confuse the Windows implementer.** The header's `format: 2` sits next to `recovery.formatVersion: 2`, the prose says "recovery format 4" and "archive format 2" in the same sentence, v1's header `version` is still a third number, and the same value appears three times (the `format` entry, the header, the manifest), each a separate mismatch case. Use "directory archive" and "file archive" in prose and specs, give the member an unambiguous name (for example `archiveVersion`), drop the manifest's copy of the number (the AAD and the header already bind it), and keep the `format` entry only if the fixed-offset sniff is wanted by a tool that will actually use it. Rename before the fixtures are cut; they are permanent.

11. **Minor: 1.0 cannot open 1.1 archives; accept, and consider one cheap mitigation.** Verified: 1.0 reads `archive.json` below the path and shows its generic message. That is acceptable as the design says, but 1.0 is still in review, so a 1.0.1 that recognizes a regular file starting with `PK` and says "Update My Journal" (scope item C) costs little and removes the one confusing failure. This is the one genuine owner choice in decision 3. Also tell Windows and Android implementers explicitly that format 1 is never written or read by them (the record does).

12. **Minor: platform and other notes.** Windows: confirm per runtime whether `CompressionLevel.NoCompression` writes method 0 or 8 and that `ZipArchive` does not verify CRC-32 on read; the reader must stream-hash and apply the profile itself, as 6.3 says; Explorer will not offer Extract All because the extension is not `.zip`. Android: `ZipFile` has the same duplicate-name and no-overlap blind spots. The media type `application/x-journalarchive+zip` is reasonable. iCloud: reading through a security-scoped URL for an evicted file can take minutes with no determinate progress; add it to the spike and make sure cancellation works during the wait. The ZIP64 path cannot be reached by 2 GiB spike files; the forced-ZIP64 switch is the right CI test, and one sparse entry above 4 GiB should be run by hand before release (10.1).

13. **Minor: scope of section 8.3.** The six other known issues are conformance fixes the scope allows, but the link-destination writer change alters stored text and the timestamp fix changes what records are accepted. Each deserves its own small change and review, not a ride-along that holds the archive release. Keep the fixtures with their own versions as proposed.

### On the owner decisions

- **Unlisted files (decision 1).** Genuine only because AGENTS.md says the owner, not the author, decides which of spec and code is wrong. Ignoring unlisted entries is the right answer: it matches shipped behaviour, cannot lose library data (the database check fails if it needs an image the manifest does not list), and keeps clutter from a file manager or sync service from making a backup unrestorable. Record it as decided once the owner agrees, together with the stricter rule from finding 1 (manifest keys must be lower-case UUIDs).
- **File-type declaration (decision 2).** Genuine, and better asked now with the whole ladder (finding 2) than after a failed spike.
- **1.1 writes only format 2 (decision 3).** Not a decision: the scope record already says the archive becomes one file and the Apple app keeps reading the directory. Record it as a consequence, with the changelog line. The only open choice is the 1.0.x mitigation in finding 11.

## Changes after review

Author's response, in the order of the findings. The first review's verdict was "revise and re-review"; a second review follows the file type spike.

| # | Finding | Change |
| --- | --- | --- |
| 1 | Blocker: path traversal through manifest keys in the directory reader | Already fixed on main in commit 6ca3ba2 (keys checked as lower-case UUIDs before any file operation; test; `protocol/archive.md` says so). Recorded as done in 2.1. Added: a conformance case in `archive/v1/unlisted-files-v1.json` (plain version 2 header, manifest key `../x`, nothing may be created), regular-file checks on the sources, the key rule restated in 4.5, and the 1.0.x question reduced to the message in decision 3. |
| 2 | Material: the file type spike is the feasibility question; fallback (b) is poor | 6.2 extends the spike (share sheet to Mail, Messages and AirDrop; iCloud Drive with an evicted file and cancellation; Quick Look and Spotlight; the save panel through `fileExporter` with a regular-file wrapper; archive tools must not claim the file). The zip-conformance rung is rejected. The ladder is (a) unchanged, (b) different streaming and a broader importer, (c) a new type with its own extension beside the old one. One owner decision (11.1) approves the whole ladder in advance, recommended. |
| 3 | Material: leftovers are never cleaned, and the export makes too many copies | 6.3 and 4.3: `ArchiveExportLeftovers` gets a regular-file rule with exact names, never links, with a real-file test; one staged file handed over by move; free-space check before the export; the 6.1 disk sentence corrected; failure-ownership test for files (section 10, item 6). |
| 4 | Material: no plaintext file archive | Section 3: file archives carry recovery formats 1 and 2 only, the manifest is always sealed, a format 3 or 4 envelope is refused as damaged; `plaintext.zip` and its cases are dropped; the plain-manifest reader stays for directory archives only. Container cases take the manifest as input so they need no key (8.1). |
| 5 | Material: bomb and memory limits too loose for a phone | 4.6 and 4.2: header 16 MiB, central directory 64 MiB and 300,000 entries, only known entries kept, unknown names skipped; an 8× expansion cap; total is `min(1 TiB, free space minus a reserve)` counting the staging copy and the install; the 250,000-image limit removed (it follows from 16 MiB). |
| 6 | Material: custom ZIP code on conditions | 4.4 lists the five conditions: reader review as a ship gate, a mutation sweep, independent tools reading the writer's output, `UInt64` overflow-reporting arithmetic, system `crc32` and the capped inflate. Corrected the throughput assumption. |
| 7 | Minor: reader details | Pinned in 3.2, 4.2 and 8.1 as container cases: end record comment length and counts; ZIP64 extra field order and short values; data offset from the local lengths; no data descriptor scanning; byte comparison of names; duplicate manifest keys; `bytes` equal to the central directory's; method 99 and bit 13; near-2^64 sizes; a range covering the central directory. |
| 8 | Minor: say what integrity protects; drop over-claims | 3.4 rewritten (what the manifest authenticates, what it does not, rollback undetectable, the AAD is domain separation, not a downgrade control); the "Downgrade or replay" row removed from 4.7; "same bytes" restricted to the container (3.2). |
| 9 | Minor: SQLite opened before the schema is checked | 4.2 step 9 and test 7: `PRAGMA trusted_schema = OFF` and `sqlite_master` compared with the known migrations before any migration, for both archive kinds. |
| 10 | Minor: naming | Section 1: "directory archive" and "file archive" in prose; the header member is `archiveVersion`; the manifest has no number; the `format` marker entry is dropped (identification by extension and `archiveVersion`); renamed before fixtures are cut. |
| 11 | Minor: 1.0 cannot open 1.1 archives | Accepted as a consequence (1.1 writes only file archives is decided). The one open choice, a 1.0.x that says "Update My Journal to open this archive.", is decision 3, recommended. |
| 12 | Minor: platform notes | 6.4: `ZipArchive` and `ZipFile` caveats, `NoCompression` to confirm, Explorer; 5.3 and the spike: iCloud wait and cancellation; 10.1: one sparse entry above 4 GiB by hand. |
| 13 | Minor: scope of the known issues | 8.3: each is its own change with its own review and does not hold the archive release. |

Also from the lead: the settings keys paragraph of `protocol/archive.md` carries the `kept-notes` sentence from the conflicts design (3.4); the conflicts design needs no archive number.

## Second independent review (2026-10-09)

Reviewer: an independent design and security reviewer, given the requirements, the revised record and the first review. Checked against commit 6ca3ba2, `protocol/archive.md`, `Archive.swift` (`restore`, `requiresPassword`), `Crypto.swift` (`derive` bounds), `DocumentTransferOperations.swift` (`ArchiveExportLeftovers`), `ArchiveInstalling.swift`, `apps/apple/project.yml` (type declarations), `protocol/conformance/archive/` and [1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md) section 3.5. Nothing was built or run.

**Verdict: approve with changes.** There is no Blocker. The first review's Blocker is fixed on main and pinned by a test and by `protocol/archive.md`; the container profile, the reader order and the bounds are now sound, and a file archive cannot be downgraded to weaker validation (its manifest is always sealed, recovery formats 3 and 4 are refused, and the AAD differs from the directory archive's). The file type spike (6.2) may start now. The container reader should not be built into the app until the spike result is recorded and findings 1 to 4 below are folded into the body. A further review is needed only for the spike result and the reader code (the existing ship gate), not for this record again.

### First-review findings, checked against the body

| # | Status | Note |
| --- | --- | --- |
| 1 Blocker (traversal) | Resolved | Commit 6ca3ba2 rejects any manifest key that is not a lower-case UUID before the first file operation (`restore`, before `fileExists` and `copyItem`), with a test, and `protocol/archive.md` says so. Still open from the original finding and now only promised in 2.1: the regular-file checks on `journal.sqlite` and the sources (the code still calls `copyItem` on both without checking). Covered by finding 9 below. |
| 2 Spike and ladder | Partly | Criteria and ladder are now right (rung (c) is the correct last resort; retyping the old UTI to `public.data` would turn every 1.0 package into a plain folder in Files and Finder, so do not add it). Open: see findings 5 and 6. |
| 3 Leftovers and copies | Partly | The cleaner rule is specified, but the disk arithmetic is still understated (finding 1) and a killed restore is not covered. |
| 4 No plaintext file archive | Resolved | Sections 3 and 8.1. Consistent with [1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md) 3.5. |
| 5 Limits | Mostly | Header, directory, entry count, 8x cap, free space: resolved. The "reserve" is a name without a number (finding 1). |
| 6 Custom ZIP code | Resolved | Five conditions in 4.4 are right. |
| 7 Reader details | Mostly | Pinned in 3.2 and 4.2, but several points are still ambiguous between readers (finding 2). |
| 8 What integrity protects | Resolved | One point understated: finding 10. |
| 9 SQLite before schema check | Mostly | Specified; the implementation and the interoperable meaning of the check are not (findings 3 and 8). |
| 10 Naming | Resolved | |
| 11 to 13 | Resolved | |

### Findings

1. **Material: the free-space and cleanup rules still understate the peak and leave a hole.**
   (a) 4.3 step 6 and the "Disk during export" row say the staged file "moves", so only one copy exists after hand-over. That holds only when the destination is on the same volume as the app's data folder (On My iPhone, the Mac's boot volume). For iCloud Drive, an external drive, another volume on the Mac or any file provider, a move is a copy followed by a delete, so the peak is the staged archive plus the destination copy, and the free-space check in 4.3 step 1 (database copy plus archive, on the data volume) does not cover the destination at all. Fix: say in 4.3 and 6.1 that a move is a rename only on one volume; make the spike (criterion 1) record peak disk use on the data volume and on the destination for four destinations (On My iPhone, iCloud Drive, an external drive, a second Mac volume); and map a destination-full failure to the existing `messages.export.archiveFailed` or the "not enough space" message, with the staged file removed and the person told nothing was saved.
   (b) 4.6 says "free space minus a reserve" and never gives the reserve. Fix: state numbers. For export: free space on the data volume must be at least the database size plus the sum of the image sizes plus 256 MiB (the database copy is deleted once written, so this is conservative). For restore: at least twice the sum of the declared `bytes` plus 256 MiB (staging plus install). These are reader-local, not interoperability rules, but they need a test that uses a stubbed free-space value.
   (c) The launch cleaner removes staged exports and dialog copies, but I found no launch-time cleanup for the restore and import staging directory (`ArchiveInstalling.swift` discards it on failure only). Killing the app during a multi-gigabyte extraction leaves it behind for good. Fix: name the staging directory with a fixed prefix plus a UUID, add it to `ArchiveExportLeftovers` as a directory rule (never links, never a directory that is the current library), and extend test 6 of section 10 to "killed during restore, then relaunch".

2. **Material: a Windows implementer still cannot interoperate from `protocol/archive.md` alone, because several rules are ambiguous or missing. They must be in the protocol text, each with a container case.** The record is the design; the protocol document is what the other reader is written from, so these must be resolved in the words that go there.
   - Local header: say which flags decide whether the local sizes and CRC are ignored (the local header's flag bit 3). Say that a local header with saturated sizes and a ZIP64 extra field is read as "ignore local sizes" (the central directory is authoritative), not as "must match". Without this, a reader that compares them refuses what .NET or Info-ZIP writes, and a reader that ignores them accepts what another refuses. Simplest rule: always ignore local sizes and CRC; require equal name bytes and method only.
   - ZIP64 versus the end record: if a ZIP64 locator exists, the ZIP64 end record is used and every non-saturated field in the ordinary end record must equal it; a disagreement is invalid structure. Say that ZIP64 structures are accepted when not needed (3.2 does) and add a "disagreeing ZIP64 and ordinary end records" case.
   - Trailing bytes after the comment, a comment longer than the file's remainder, and "last end record wins": 4.2 step 1 refuses any file with bytes after the end record's comment and accepts a forged but internally consistent end record placed inside a comment (it is the last candidate whose comment length matches). Both are safe here because the sealed manifest binds the content, but other readers differ. State the rule as: the end record must be the last 22 + commentLength bytes of the file, scanning backward only to find the candidate whose comment length reaches the end of the file; the first such candidate from the end is the only one considered. Add a forged-end-record-in-comment case with an internally consistent forgery and say the expected outcome (accept the outer, or refuse; pick one).
   - Numbers: `bytes` is a non-negative JSON integer at most 2^53 - 1 (so .NET `long`, JavaScript and Swift agree); a float, a negative, an exponent form or a leading zero is invalid. Say whether unknown members in the manifest are ignored (the header's are; the manifest's are not stated; recommend: ignored, so the manifest can grow). The 8x rule in integer form: refuse when `bytes > 8 * compressedSize`; a stored entry requires `compressedSize == bytes`; method 8 with compressed size 0 is invalid; the empty stream is accepted.
   - Deflate: the stream must end exactly at the declared compressed size (no unused trailing bytes, no early end before `bytes` are produced), and output equal to `bytes`. 4.2 step 8 says "stop at the first byte beyond the declared size" and checks the count but not the compressed-size consumption. Add cases for both.
   - CRC-32 mismatch is "damaged", checked before SHA-256 (see finding 4 for why this matters to the fixtures).
   - UUID: give the regular expression `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`; `Guid.TryParse` accepts braces, no hyphens and upper case, so "parse then lower-case" (the Swift rule) is not portable. No version or variant bits are checked.
   - Envelope: state the bounds the Apple reader enforces and the Windows reader must too, because they are the CPU limit before the password prompt: salt 16 bytes, iterations 100,000 to 2,000,000 (`Crypto.swift` `derive`), `formatVersion` 1 or 2.
   - `archive.json` duplicate member names are invalid, as the manifest's are (a duplicate `recovery` gives different readers different envelopes).
   - Central directory memory: .NET `ZipArchive` in read mode and Android `ZipFile` materialize every entry. 6.4 should say the Windows reader reads the end record, checks the central directory size (64 MiB) and entry count (300,000) from it, and only then opens a `ZipArchive`; otherwise the pre-prompt limits are not enforceable there.
   - The archive.json entry takes part in the overlap check of 4.2 step 6 (it is read like the listed entries); say so.

3. **Material: the `grdb_migrations` and schema contract decides whether a Windows-made archive restores, and the record leaves it open.** The file archive makes cross-platform restore the headline (section 12 says so), and `encrypted.zip` reuses the Apple database byte for byte, so nothing in the fixtures proves a database written by another SQLite stack restores. Two things must be settled before the fixtures are cut: (a) `protocol/archive.md` already treats `grdb_migrations` and its five identifiers as part of the format; make that normative in the file archive section, with the table's columns (`identifier` text primary key), the rule that a non-Apple writer records every migration its schema includes, and that a reader applies only the migrations after the last recorded one; (b) the pre-migration `sqlite_master` check of 4.2 step 9 must compare tables, columns, indexes and their uniqueness by structure (the results of `PRAGMA table_info`, `index_list`, `index_xinfo`), not by the `CREATE` text, because EF Core, Microsoft.Data.Sqlite and GRDB write different text for the same table. State the expected objects in `protocol/archive.md` (its table section is nearly that already) and add a fixture database built by a non-GRDB writer (a short script with the Python `sqlite3` module is enough) that the Swift and .NET readers both accept. Recommend deciding now, as an owner decision, that the migration table is normative; the alternative (a `user_version`-based format number) is a contract change and not worth it for 1.1.

4. **Material: the `expected.json` mutations cannot test what they say, because the CRC-32 is checked.** 8.1 applies a one-byte change in place (an `archiveVersion` digit to 3, a `formatVersion` digit to 4, a byte of the sealed manifest, a byte of the database). Every one of those also changes the entry's CRC-32 in the local and central headers, and the reader compares the CRC (4.2 step 8, and finding 2), so each mutation would end as "damaged" at the CRC, never reaching the newer-version check, the format check, the AES-GCM authentication or the SHA-256 comparison. A reader with a broken newer-version check or a broken hash comparison would still pass. Fix: each mutation in `expected.json` lists the CRC-32 patch (offset in the local header, offset in the central directory, new value) so the test harness applies a consistent change, and add for the database and one image a second variant with the CRC left stale (expected: damaged) to prove the CRC is checked. State the order: for `archive.json` the CRC is checked before decoding, so a stale CRC always wins over "newer".

5. **Minor: rung (c) and decision 3 contradict each other.** Decision 3 asks for a 1.0.x that says "Update My Journal to open this archive." when it meets a regular file named `*.journalarchive`. If the spike forces rung (c) (extension `journalbackup`), a 1.0 install neither registers nor lets the person pick that extension, so the message can never appear and the 1.0.x release buys nothing. Fix: record in 11.3 that the recommendation applies only on rungs (a) and (b), and decide it after the spike; do not ship a 1.0.x for it before then. Also, if rung (c) is approved, the owner approves the exact extension and type identifier now (both are permanent and appear in fixtures and in the Windows association); the Windows and Android sections of 6.4 then follow that string.

6. **Minor: the spike has four gaps.** (a) Run it on the oldest supported iOS and macOS as well as the newest (the deployment targets), since `fileExporter` and file-provider behaviour for package types has changed between releases. (b) Add a file written by another stack: a `.journalarchive` regular file produced on Windows (or by .NET on any machine, or Python `zipfile`) must open on Apple, because Windows-written archives are the point. (c) Add iCloud Drive upload and download of a multi-gigabyte regular file typed as a package, which iCloud treats specially (packages are synchronised as bundles), and a Time Machine or Finder copy of the same. (d) Record in the criteria what the person sees on a successful export in Files and the Finder: a "package" type used for a regular file can show "Show Package Contents" in the Finder, which would be wrong for a file. Any failure there is a rung (c) trigger, not a nuisance.

7. **Minor: the expansion cap is a reader rule, but writers must obey it.** A Windows writer that deflates `journal.sqlite` (the profile allows it; 3.5 expects it for a later Apple writer) can produce a file with more than 8x expansion for a database with large zero-filled regions (freed pages, a freshly created file with preallocated pages), and the Apple reader then refuses it as damaged. Fix: add to 3.2 a writer rule: use method 8 for an entry only if the compressed size is at least `bytes / 4`, otherwise store it; add a fixture case (`accept`) with a deflated entry at about 6x and one `damaged` entry just over 8x.

8. **Minor: the pre-migration check must be a separate step in code, and more than `sqlite_master`.** `JournalStore.init` runs `PRAGMA journal_mode = WAL` and the migrations when it opens a database, then `validateSchema` runs afterwards (`Archive.swift` `restore`). Step 9 needs an inspection function that opens the staged file read-only, before that init, with `trusted_schema = OFF` and `SQLITE_DBCONFIG_DEFENSIVE`; runs `PRAGMA quick_check` (so migrations never run `ALTER TABLE` on a malformed file); requires the file header's read and write versions (bytes 18 and 19) to be 1, as a rollback-journal file archive's database is; and then applies the structural comparison of finding 3. A list of the migration identifiers in `grdb_migrations` that this build does not know is the existing "newer" case; one that names a migration but lacks its objects is a refusal. Add the header-version check to the "database" paragraph of the protocol. The practical exposure is the directory archive's unauthenticated path (the file archive's database is bound by the sealed manifest, so only someone who knows the password can craft a hostile one); say so in the hostile-input table.

9. **Minor: the retained directory reader is still the weakest path and is chosen by the filesystem.** 4.1 picks the kind by whether the picked item is a directory, so anyone can hand over a folder (or a zipped folder the person unzips) with a plain version 2 header and a manifest they wrote: hashes and sizes are theirs. File archives cannot be downgraded to this, but the directory reader is reachable on every 1.1 install. Fix: say in 4.6 that its limits apply to the directory reader as well (25 MiB per image, 32 GiB database, the free-space check, byte counts while copying instead of a bare `copyItem`), make the regular-file checks of 2.1 part of the change instead of "also", and add a hostile-directory case for a link in place of `journal.sqlite` and a sparse oversized file. Also decide what the directory reader does with a folder that holds a file archive's layout (`archive.json` with `archiveVersion`, which is what Archive Utility or Windows Explorer produces if someone unpacks one): the plain answer is "damaged" through the existing version check; say so in 4.1 so it is tested, not accidental. Lastly the reader must not treat an attachments folder that is a link as a folder (`inventory` checks the staged copy but `copyItem` reads from the source first).

10. **Minor: 3.4 understates the AAD.** `journal:v2:archive` is also the version binding: the manifest of any future `archiveVersion` 3 will be sealed under another string, so editing the unauthenticated `archiveVersion` digit downward cannot make a v2 reader accept a v3 manifest, and editing it upward cannot make a v3 reader skip checks. Say that; it is the reason to keep a different string per archive version in the protocol ("the AAD is `journal:v{archiveVersion}:archive`") and it is a cheap rule for Windows.

11. **Minor: 4.2 step 2 and 4.5 disagree about duplicate unlisted names.** 4.2 makes a duplicate of any known name an error, and "known" includes `attachments/<uuid>` for every UUID; 4.5 says unlisted UUID-named entries are ignored and "errors" include a "duplicate known name". The practical rule is: a duplicate of any profile name (including an unlisted UUID) refuses the archive, since the reader stores all profile-shaped names before the manifest is open. Say that in 4.5 and add the case; otherwise two readers (one that stores only listed names after the manifest is read) will disagree.

12. **Minor: the conformance plan is good; four additions would make it catch real divergence.** (a) The only archives written by something other than the repository's own code are none. Add small `accept` samples written by real tools, committed with the tool and version noted in `container/README`: .NET `ZipArchive` (`Create` over a seekable and over a non-seekable stream, so data descriptors appear), Python `zipfile`, Info-ZIP `zip` (extended timestamp and Unix extra fields), and macOS Archive Utility or `ditto -c -k --sequesterRsrc` (the `__MACOSX` and `._` entries). (b) State that the compared outcome is accept, or refuse with the 5.1 message class (damaged, newer, wrong password, couldn't open), not the reason words in `container-v2.json` (`not-zip`, `invalid-structure`, `unsupported-entry`); two readers will validly classify "a forged end record" differently and should not fail the fixture for it. (c) The `container/make-container-cases.py` script cannot use `zipfile` for most of the invalid cases (forged records, overlap, bit 13, saturated fields); say it assembles the bytes with `struct`, and that `zipfile` reads each `accept` case as a cross-check. (d) Add a second sealed fixture with a recovery format 1 envelope (the legacy recovery key, trimmed and case rules of `derive`), or one `mutations` case that swaps the envelope, because only format 2 is covered and test 3 of section 10 mentions format 1 for Apple only. The record states ZIP64 is exercised only on small files and by one manual 4 GiB run; that is acceptable.

13. **Minor: cases to add to `container-v2.json`** (beyond finding 2): an end record with a non-zero disk number; a central directory entry whose extra or comment length runs past the directory; a listed entry whose compressed size exceeds the file; a stored entry with compressed size not equal to `bytes`; deflate that ends before `bytes`; deflate with trailing bytes inside the compressed size; a zero-length listed entry; a local header with bit 3 set and non-zero local sizes (accepted); a local ZIP64 extra with the central sizes unsaturated (accepted); an unlisted duplicate UUID name (finding 11); and `archive.json` listed in the overlap check.

### On the owner decisions

The record lists three decisions in section 11 (ladder, unlisted files, the 1.0.x message); the fourth open item is the `grdb_migrations` risk of section 12 and the section 8.3 list, which also need the owner's choice.

1. **Ladder: approve (a), (b) and (c) in advance, with two amendments.** Agree the order and the rejection of the zip-conformance idea; agree with not offering a retyped `public.data` rung (it breaks every 1.0 package in Files and the Finder). Amendments: the owner approves the exact extension and type identifier now if (c) is ever taken (finding 5), and the spike gets the gaps of finding 6.
2. **Unlisted files ignored in both archive kinds: confirm.** The reasons in 4.5 stand. Keep two exceptions explicit in the protocol text: a listed name that is a symbolic link or not a regular file is invalid in a directory archive, and a duplicate profile name in a file archive is invalid (finding 11).
3. **1.0.x "Update My Journal" message: confirm, but only on rungs (a) and (b).** It is a 1.0.x release that must ship before any 1.1 file archive exists, and it is moot on rung (c) (finding 5). Decide after the spike.
4. **`grdb_migrations` as normative, and 8.3 as separate changes: confirm.** Make the migration table normative now (finding 3) rather than before Windows ships; the 8.3 proposals stay separate changes, as proposed, with their own review.

### Order of work after this review

Fold findings 1 to 4 and 11 into the body (they change the protocol text and the fixtures); take the rest as notes on the sections they name; run the spike (with finding 6); then build the container reader, the mutation sweep and the independent-tools script; send the reader for its ship-gate review before release.

## Changes after the second review

The second review approved with changes and no Blocker. Its Material findings 1 to 4 and the Minor ones are folded into the body above.

| # | Finding | Change |
| --- | --- | --- |
| 1a | Material: a move is a rename only on one volume | 4.3 step 6 and 6.1: copy plus delete for other volumes; a full destination maps to the existing no-space or save-failed message with the staged file removed; 6.2 criterion 1 records peak disk on the data volume and the destination for four destinations. |
| 1b | Material: the reserve had no number | 4.6: export needs database + images + 256 MiB on the data volume; restore needs 2 × declared bytes + 256 MiB; a stubbed free-space test (test 8). |
| 1c | Material: no cleanup for the restore staging directory | 6.3: a directory rule for `import-<uuid>` in `ArchiveExportLeftovers` (never links, never the current library); test 7 includes a restore killed mid-extraction. |
| 2 | Material: interoperability rules missing from the protocol text | 3.2, 3.3, 4.2, 4.5, 4.6 now state, as normative wording: local sizes and CRC always ignored; ZIP64 versus ordinary end record agreement; the single end-record candidate rule with a forged candidate refused; JSON integers up to 2^53 − 1 and unknown manifest members ignored; the 8× rule in integer form and stored/deflate size rules; exact deflate consumption; CRC-32 before SHA-256; the UUID expression; envelope bounds; duplicate member names in `archive.json`; the Windows reader's directory-size check before opening `ZipArchive`; `archive.json` in the overlap check. Each has a case in 8.1. |
| 3 | Material: `grdb_migrations` and the schema contract | New 3.4.1: the table, its identifiers, header versions and the structural comparison (`table_info`, `index_list`, `index_xinfo`, not `CREATE` text) are normative; a non-GRDB fixture database `foreign.sqlite` with negative variants; owner decision 3. |
| 4 | Material: mutations could not test what they say | 8.1: each mutation lists CRC patches; stale-CRC variants for the database, an image and `archive.json`; order stated (CRC before decoding, so a stale CRC beats "newer"). |
| 5 | Minor: rung (c) and the 1.0.x message contradict each other | 6.2 spike outcome: the 1.0.x is decided after the spike and only on rungs (a) and (b); the exact extension `journalbackup` and type identifier `org.privatejournal.archive.file` are approved now (decision 1); 6.4 follows. |
| 6 | Minor: spike gaps | 6.2: oldest and newest OS; a file written by another stack; iCloud multi-gigabyte upload and download, Time Machine and Finder copy; what Files and the Finder show (a package indication is a rung (c) trigger). |
| 7 | Minor: writers must obey the expansion cap | 3.2: deflate only if the compressed size is at least `bytes / 4`; cases at about 6× (accept) and just over 8× (damaged). |
| 8 | Minor: pre-migration check as a separate step | 4.2 step 9: a function run before the store exists, read-only, `trusted_schema = OFF`, defensive mode, `quick_check`, header versions 1, structural comparison; 3.4.1 for the protocol; 4.7 says the unauthenticated path is the directory archive. |
| 9 | Minor: the directory reader is the weakest path | 2.1 (regular-file checks part of the change), 4.1 (a folder with `archiveVersion` is damaged, tested; links never followed), 4.6 (size limits apply to the directory reader), 8.2 (hostile directory cases). |
| 10 | Minor: the AAD is also the version binding | 3.3 and 3.4: `journal:v{archiveVersion}:archive`, with the reason. |
| 11 | Minor: duplicate unlisted names | 4.2 step 2, 4.5: a duplicate of any profile name, including an unlisted UUID, refuses a file archive; case in 8.1. |
| 12 | Minor: conformance additions | 8.1: real-tool samples (.NET seekable and non-seekable, Python, Info-ZIP, `ditto`); outcomes compared by message class, reasons non-normative; the script assembles bytes with `struct` and cross-checks `accept` cases with `zipfile`; a second sealed fixture with a recovery format 1 envelope. |
| 13 | Minor: more container cases | 8.1 lists each (disk number, directory entry lengths, compressed size beyond the file, stored size mismatch, early-ending and trailing deflate, zero-length entry, bit 3 with non-zero local sizes, local ZIP64 extra, unlisted duplicate, `archive.json` overlap). |

Owner list set to exactly three (section 11): the ladder with the exact strings of rung (c); unlisted files ignored; `grdb_migrations` normative with the 8.3 fixes as separate changes.
