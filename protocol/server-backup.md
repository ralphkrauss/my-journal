# Server backup directory

This is the backend maintenance format, separate from the native `.journalarchive` format. It retains the encrypted server vault, revision log, device credential hashes, recovery envelope, and immutable uploaded attachment bytes. For encrypted libraries, the server does not possess the keys needed to authenticate/decrypt journal payloads; libraries created without encryption are stored readable.

New backups use version 2:

- `journal.db`: a SQLite online-backup snapshot, checkpointed into a self-contained database with DELETE journal mode.
- `attachments/<UUID>`: each attachment referenced by the snapshot's Attachments table, copied without modifying ciphertext.
- `database-sha256`: hexadecimal SHA256 of the snapshot database.
- `backup-version`: `2`, written only after snapshot, image validation, and database digest creation succeed.

Backup creation streams file hashes and attachment metadata instead of loading image contents into memory. It snapshots SQLite before copying images, so concurrent new uploads do not produce missing references in the snapshot. Referenced image files are immutable. Incomplete output directories have no completion marker and must not be treated as backups.

Restore supports versions 1 and 2, including databases from before later schema migrations: columns and tables added by migrations the backup has not applied are not required, and the server adds them when it first starts. It rejects links at the archive/database/attachment-directory/file boundaries, unsupported migration histories or missing required tables/columns, invalid SQLite integrity checks, missing/altered referenced images, and live database WAL/journal sidecars. It also rejects any schema object Journal does not create: triggers, views, unknown tables or indexes, and table or index definitions with anything beyond plain column types, NOT NULL, defaults and primary keys (for example CHECK, ON CONFLICT, REFERENCES, generated columns, or partial and expression indexes). Such objects could run or alter writes, for example re-enabling devices that restore or a later revocation signs out. Backup databases are opened with SQLite's `trusted_schema` off. It reads completed snapshots using SQLite's immutable read-only mode, avoiding changes to the backup. Version 2 also checks the database digest before publication. Version 1 has no database digest, so its database validation is structural; legacy WAL-mode database headers are supported when the snapshot is self-contained.

The checksum is corruption detection, not a signature or keyed authentication: someone able to replace both a database and its digest can create another structurally valid backup. Clients still authenticate encrypted journal payloads when decrypting. Keep a trusted original backup and recovery key and verify recovered entries/images before discarding older copies.

Restore requires a stopped server and an empty data directory. It validates the source, writes `restore-in-progress` in the target, copies only expected files into an owned staging directory within that target, revalidates the copied database/images/digest, and publishes them without overwriting existing files. It removes the marker only after publication and staging cleanup finish. Server startup refuses a directory containing this marker. An interruption/failure may leave staging or some published files; preserve them and restore from the original backup into another empty directory. Do not remove the marker to force startup or back up an unfinished restore.

After validation and before publication, restore changes only the staged copy: it revokes every device credential (the backup may predate revocations; devices reconnect with the library's password, recovery key or an administrator recovery code), deletes pending pairing requests, and replaces the sync identity (`serverId`, see the protocol) with a new random value, recording the newest restored change cursor as `serverIdCursor`. A backup from before identities existed receives one when the server first starts. Clients that see the new identity re-read the server and upload what it lost. The command prints how many devices were signed out.

This design works when the target itself is a mounted container volume, which cannot be replaced by an ordinary directory rename. It does not remove the need for reliable storage and off-device backups, nor claim protection against simultaneous hostile filesystem modification or every possible storage/power failure.

## Upgrades and downgrades

When the server starts and its database needs migrations, it first copies the database with SQLite's online backup to `journal.pre-migration.db` in the data directory (self-contained, DELETE journal mode), replacing any earlier copy, and then migrates. If a migration fails, stop the server and restore that copy (or a backup) with the matching older server version. A new data directory needs no copy.

The server refuses to start, logs the unknown migration and exits with status 1 without changing the database when the database was migrated by a newer server version. Install that version or later, or restore a backup made by this version into an empty data directory. Older releases without this check must not be run against a newer database.
