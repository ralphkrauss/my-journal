# archive

The `.journalarchive` package ([archive.md](../../archive.md)). The layout is versioned by folder so a later format slots in beside it:

```
archive/v1/
├── expected.json
├── encrypted/          archive header version 1: master password (recovery format 2)
│   ├── archive.json
│   ├── journal.sqlite
│   └── attachments/01234567-89ab-4cde-8fab-0123456789ab
└── plaintext/          archive header version 2: no password (recovery format 4)
```

The encrypted archive uses the format 2 envelope, the password and the vault key of [../crypto/encryption-v2.json](../crypto/README.md) (`recovery.envelopes[0]`, `recovery.password`, `recovery.vaultKey`), so one secret opens every fixture. The folders are plain directories (not named `.journalarchive`, which the repository ignores); the database files are the only SQLite files the repository tracks. Nonces and the database's own IDs are random, so these files are made once per version and never regenerated in place.

Both hold the same small library: a journal with a default template, a template, an entry that refers to an image (with the image), an entry written on this device that has not been sent (an outbox row), an earlier version of the first entry (history), and the library record with a pin and a journal rank.

## `expected.json`

`archives.encrypted` and `archives.plaintext` have:

- `headerVersion` (1 or 2), `formatVersion` of the recovery envelope in the header, and for the encrypted archive the `password` to open it;
- `manifest`: what the header's `manifest` holds once opened (the SHA-256 of `journal.sqlite` and of each file in `attachments/`). In the encrypted archive the header's `manifest` is base64 of AES-256-GCM combined bytes sealed with the vault key and the context `journal:v1:archive`; in the plaintext one it is base64 of the JSON;
- the database as another client reads it with SQLite: `records` (`id`, `kind`, `revision`, `dirty` and the decrypted `plaintext`; the payload column is base64 of the sealed record with the context `journal:v1:record:{kind}:{id}`, or of the plain record in the plaintext archive), `outbox`, `history`, `attachments` (the decrypted image's size and SHA-256 — the manifest's hash is of the stored, still encrypted file — and `uploaded`), `settings` (only `content-protection`; the table also holds device-local keys such as `library-changes`, see [archive.md](../../archive.md), which a reader keeps and doesn't compare) and the applied `migrations` in the order they were applied;
- `mutations` (once, at the top): damage and clutter applied to a copy of `encrypted/`. A reader must refuse a changed database or image, a missing image and a header version that doesn't match the envelope, and must restore after dot files in `attachments/` and other top-level files.

A client passes when it opens the header, recovers the vault key from the password, authenticates the manifest and checks every file against it, reads the database and decrypts every row to the `plaintext` listed, decrypts the image to the listed bytes, and refuses and accepts the `mutations` as stated. The server's `ArchiveConformanceTests` does this with .NET and SQLite; Swift `ConformanceArchiveTests` restores the archives and reads the database directly.

Extra files that the manifest doesn't list are not part of the mutations (see Known issues in the [folder index](../README.md)).
