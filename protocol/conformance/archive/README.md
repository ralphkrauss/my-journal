# archive

The library archive ([archive.md](../../archive.md)). The layout is versioned by folder so a later format slots in beside the others:

```
archive/
├── v1/                          directory archives, as My Journal 1.0 writes them
│   ├── expected.json
│   ├── encrypted/               header version 1: master password (recovery format 2)
│   ├── plaintext/               header version 2: no password (recovery format 4)
│   ├── unlisted-files-v1.json   what a reader ignores and the hostile folders it refuses
│   └── hostile/                 two folders with a readable header, for unlisted-files-v1.json
└── v2/                          file archives: one ZIP file
    ├── expected.json
    ├── encrypted.zip            recovery format 2: the library of v1/encrypted repackaged
    ├── encrypted-recovery-key.zip   recovery format 1: an empty library under a legacy recovery key
    ├── container-v2.json        the cases of container/
    ├── container/               archives that exercise the ZIP layer only (README.md there)
    ├── database-v2.json         the structure of the database, and the cases of database/
    └── database/                databases written by something other than GRDB
```

The encrypted archives use the envelope, password and vault key of the shared crypto corpora, so one secret opens every fixture: [../crypto/encryption-v2.json](../crypto/README.md) (`recovery.envelopes[0]`, `recovery.password`, `recovery.vaultKey`) for `v1/encrypted` and `v2/encrypted.zip`, and [../crypto/encryption-v1.json](../crypto/README.md) (`recovery.phrase`, `recovery.salt`, the `recovery` envelope item) for `v2/encrypted-recovery-key.zip`. The directory archives are plain folders (not named `.journalarchive`, which the repository ignores). A file archive is named `.zip` here, not `.journalbackup`, for the same reason; a reader treats it as an archive whatever its name. The database files are the only SQLite files the repository tracks. Nonces and the databases' own IDs are random, so the archives and databases are made once per version and never regenerated in place.

## v1: directory archives

Both hold the same small library: a journal with a default template, a template, an entry that refers to an image (with the image), an entry written on this device that has not been sent (an outbox row), an earlier version of the first entry (history), and the library record with a pin and a journal rank.

### `v1/expected.json`

`archives.encrypted` and `archives.plaintext` have:

- `headerVersion` (1 or 2), `formatVersion` of the recovery envelope in the header, and for the encrypted archive the `password` to open it;
- `manifest`: what the header's `manifest` holds once opened (the SHA-256 of `journal.sqlite` and of each file in `attachments/`). In the encrypted archive the header's `manifest` is base64 of AES-256-GCM combined bytes sealed with the vault key and the context `journal:v1:archive`; in the plaintext one it is base64 of the JSON;
- the database as another client reads it with SQLite: `records` (`id`, `kind`, `revision`, `dirty` and the decrypted `plaintext`; the payload column is base64 of the sealed record with the context `journal:v1:record:{kind}:{id}`, or of the plain record in the plaintext archive), `outbox`, `history`, `attachments` (the decrypted image's size and SHA-256 — the manifest's hash is of the stored, still encrypted file — and `uploaded`), `settings` (only `content-protection`; the table also holds device-local keys such as `library-changes`, see [archive.md](../../archive.md), which a reader keeps and doesn't compare) and the applied `migrations` in the order they were applied;
- `mutations` (once, at the top): damage and clutter applied to a copy of `encrypted/`. A reader must refuse a changed database or image, a missing image and a header version that doesn't match the envelope, and must restore after dot files in `attachments/` and other top-level files.

A client passes when it opens the header, recovers the vault key from the password, authenticates the manifest and checks every file against it, reads the database and decrypts every row to the `plaintext` listed, decrypts the image to the listed bytes, and refuses and accepts the `mutations` as stated. The server's `ArchiveConformanceTests` does this with .NET and SQLite; Swift `ConformanceArchiveTests` restores the archives and reads the database directly.

### `v1/unlisted-files-v1.json`

Added with the file archive, beside the files above, which are unchanged. It records the rule both archive kinds share: a reader reads exactly the files the manifest lists and ignores the rest.

- `mutations` apply to a copy of `encrypted/` (operations `add`, `symlink`, `symlinkFolder`, `sparse` and `delete`, described in the file) with the `password` of `expected.json`. `result` is `restores` (an unlisted file with any name, an unlisted UUID-named image, an upper-case UUID name, a folder in `attachments/`) or `damaged` (a link in place of `journal.sqlite`, of a listed image and of the `attachments/` folder, none of which a reader follows; a `journal.sqlite` of 33 GiB and an image of 26 MiB, both sparse files, which are refused before they are copied because they are over the limits).
- `packages` are folders in this directory whose header is readable. A reader refuses them as damaged **before it creates any file**, checked by asserting that nothing was created inside or beside the restore: `hostile/manifest-traversal` has a version 2 header whose readable manifest lists `../x` (a manifest key that is not a UUID must be refused before it is used as a file name), and `hostile/unpacked-file-archive` is a file archive's `archive.json` in a folder, which is not a directory archive.

The link and sparse-file cases need a file system that supports them (macOS and Linux do).

## v2: file archives

### `v2/expected.json`

`archives.encrypted` (`encrypted.zip`, recovery format 2) and `archives.encryptedRecoveryKey` (`encrypted-recovery-key.zip`, recovery format 1) have the `password` (the credential as typed: the second is a generated recovery key with surrounding whitespace and a non-ASCII letter, which format 1 trims), the `recoveryFormat`, the `titles` of the entries that restoring shows, and `entries`: for each ZIP entry its `name`, `localHeaderOffset`, `dataOffset`, `bytes`, `method` (0), `crc32` (little-endian hex, as the four bytes appear in the file) and `sha256`. In `encrypted.zip` the database and the image are the files of `v1/encrypted` byte for byte, so the database SHA-256 and the rows of `v1/expected.json` (`archives.encrypted`) are what a reader finds in either; only `archive.json` is new, with `archiveVersion: 2`, the same envelope and a manifest sealed under `journal:v2:archive`. `encrypted-recovery-key.zip` holds an empty library, so it stays small and covers the format 1 derivation (trim, no case folding, PBKDF2 over the UTF-8 text) for every reader.

`mutations` apply to a copy of `encrypted.zip`. Entries are stored, so a changed byte changes in place at its `dataOffset`, and the reader checks the CRC-32 first. Every mutation therefore lists its operations as `{"op": "set", "offset": N, "bytes": "<hex>"}` (absolute file offsets), including the **CRC-32 patches** (the entry's value in the local header, `localHeaderOffset + 14`, and in the central directory), so the check under test is the one that fires. `expect` is the message class: `damaged`, `newer` or `wrongPassword`; `password` overrides the archive's.

| Name | Change | Class |
| --- | --- | --- |
| `database-byte-changed`, `image-byte-changed` | One byte, CRC-32 patched: the manifest's SHA-256 differs | damaged |
| `database-byte-changed-stale-crc`, `image-byte-changed-stale-crc` | The same, CRC-32 left alone: the CRC-32 is checked | damaged |
| `manifest-byte-changed` | One character of the sealed manifest, CRC-32 patched: authentication fails | damaged |
| `archive-version-newer` | `archiveVersion` 3, CRC-32 patched | newer |
| `archive-version-newer-stale-crc` | The same, CRC-32 left alone: the CRC-32 is checked before `archive.json` is decoded, so a stale CRC-32 wins over "newer" | damaged |
| `recovery-format-4` | The envelope's `formatVersion` 4, CRC-32 patched: a file archive is always encrypted, refused before anything is read | damaged |
| `wrong-password` | A password that does not open the envelope | wrongPassword |
| `manifest-sealed-for-a-directory-archive` | The manifest sealed under `journal:v1:archive`, same length, CRC-32 patched | damaged |

A client passes when it restores both archives to the rows listed in `v1/expected.json` (and an empty library), and gives each mutation its class. Swift `ConformanceArchiveV2Tests` does this; `Journal.Api.Tests` reads the same files with .NET.

### `v2/container-v2.json` and `container/`

About a hundred tiny archives exercise the ZIP container layer alone: structure, the validation of entries, the limits, and the extraction of the entries a given manifest lists. [container/README.md](v2/container/README.md) describes them and how they are made. Each case has the manifest the reader is handed (so no case needs a key or a cipher), the expected outcome and a note. A reader passes when, for each case, it accepts and extracts exactly the listed entries with the manifest's bytes and hashes (`accept`), or refuses in the given class. Two readers may classify a defect differently inside the class, so only `accept`, `damaged` and `newer` are compared, never the reason words in the notes.

### `v2/database-v2.json` and `database/`

`structureAfter` lists the tables, columns, indexes, foreign keys and whether a table is `AUTOINCREMENT` after the first 1, 2, 3, 4 and 5 migrations (`migrations` names them in order); the `comparison` member says what is compared (`corpusVersion` 2). The files in `database/` are empty libraries written by Python's `sqlite3` module (`make-foreign-database.py`, not GRDB, not Apple code) in its own style: they prove that a reader compares structure and not the text of `CREATE` statements. `foreign.sqlite` is accepted as is, `foreign-older.sqlite` records and has only the first three migrations (a reader applies the other two), `foreign-small-pages.sqlite` is the same library on 512-byte pages (the schema table is a b-tree with interior pages, which a reader that counts its rows from the pages must walk) and `foreign-implicit-parent-key.sqlite` has a foreign key that names no parent column. The others must be refused (`damaged`, or `newer` for the unknown migration identifier) before anything is migrated:

- the objects: an extra trigger, view or table, and an FTS5 virtual table (`foreign-virtual-table`), which a reader must refuse from the schema table, before `PRAGMA quick_check` or any pragma would connect it;
- the clauses no pragma reports: a `CHECK` (`foreign-check-constraint`), a `COLLATE` (`foreign-collate`), `ON CONFLICT REPLACE` (`foreign-on-conflict-replace`) and a deferred foreign key (`foreign-deferred-foreign-key`);
- what the pragmas report and an earlier comparison skipped: a generated column that `table_info` leaves out (`foreign-generated-column`), a foreign key action (`foreign-foreign-key-action`), a `WITHOUT ROWID` table, a `STRICT` table, and a `history` table that is not `AUTOINCREMENT`;
- a column missing or nullable, a recorded migration without its objects, migrations that are not a prefix, and a file in write-ahead mode.

A reader passes when it gives each case its class, and, for the accepted ones, restores a file archive built around the file (Swift `ConformanceArchiveDatabaseTests`; the server's tests compare the structure with .NET's SQLite).

Databases that are too large to commit are built by the tests: a schema of 20,000 objects (and one statement of a megabyte) that must be refused from the file's pages before SQLite parses it, a `grdb_migrations` of 200,000 identifiers that must be read with a limit, and the limits on JSON values of a manifest (400,000). Swift `ArchiveDatabaseHostileTests` and `ArchiveJSONTests` and the server's `ArchiveHostileInputTests` do this; the Swift tests also record the statements the inspection ran and cancel it while it runs.

## Regenerating

`v1` is read-only: the app no longer writes a directory archive (My Journal 1.0 did), so the folders `v1/encrypted/` and `v1/plaintext/` and `v1/expected.json` are the 1.0 writer's own output and the Swift test only reads them. `v2/encrypted*.zip` contain random nonces: make new ones only for a new version. The Swift tests rewrite `v2/expected.json`, `v2/database-v2.json` and `v1/unlisted-files-v1.json` (and the archives and folders they describe) with `JOURNAL_CONFORMANCE_REGENERATE=1 mise exec -- swift test --package-path apps/apple/Packages/JournalCore --filter ConformanceArchiveV2` (and `ConformanceArchiveDatabase`, `ConformanceArchiveUnlisted`). The container cases and the foreign databases are made by their Python scripts, which say how to run them.
