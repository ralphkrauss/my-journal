# Cross-client conformance fixtures

These files are fixed, versioned test vectors for the [protocol](../README.md). Every client and the server reads them in its own test suite, so a client can't produce data another client can't read, and nobody needs another client's device to find out. They replace the earlier `protocol/fixtures` folder: the same corpora, in a layout by contract.

All keys, passwords, recovery text, codes, tokens, salts, nonces, names and content are synthetic and public. **Never use them to protect real data**, and never put real journal content, real secrets, personal names or paths into a fixture. Production code must generate fresh random nonces; the fixed nonces here exist only so the bytes can be reproduced.

## Layout

Each folder is one contract. A file or folder name ends in the version of that contract's fixtures (`-v1.json`, `v1/`). A folder's own README says what its files cover and how to use them.

| Folder | Covers | Contract |
| --- | --- | --- |
| [crypto/](crypto/README.md) | Key derivation, recovery envelopes of formats 1 to 4, record and image sealing, password normalization, pairing grants, and what must be refused | [README.md](../README.md#encrypted-content) |
| [records/](records/README.md) | Record JSON as plaintext: entries, journals, templates, deletion markers, legacy documents, unknown future fields; timestamps; the library record; journal ranks | [records.md](../records.md) |
| [markdown/](markdown/README.md) | Stored Markdown: how each supported construct reads and writes, and image references | [records.md](../records.md#markdown) |
| [markdown-export/](markdown-export/README.md) | Export as Markdown: safe names, numbering, escapes, dates and a whole exported folder | [markdown-export.md](../markdown-export.md) |
| [archive/](archive/README.md) | A small encrypted archive and a small one without a password (`archive/v1/`) | [archive.md](../archive.md) |
| [sync/](sync/README.md) | A conversation with the server's sync endpoints, and short receipts | [README.md](../README.md#sync-and-conflicts) |
| [pairing/](pairing/README.md) | The invite proof, invite codes, server origins and the check code | [README.md](../README.md#pairing) |
| [agent-copy/](agent-copy/README.md) | Agent access through the server: subkeys, item IDs, sealed items, key wraps | [agent-access-server.md](../agent-access-server.md) |

## How a client uses them

1. Read the files from this folder in the client's own test suite, from the repository, without copying them. Reading a file that a client doesn't implement yet is not needed; the contract a client implements is the contract it must pass.
2. For each case, run the client's own code (not a copy of the expected computation) on the input and compare with the expected value, byte for byte or value for value as the folder's README says.
3. A case is a rule, not an accident of one implementation. If the expected value surprises you, the contract in `protocol/` decides, and a disagreement is a finding to report, not a reason to change the fixture (see below).
4. Where a contract allows variation (key order, an optional field, whole or fractional seconds), the fixture says what a reader must accept and what only the Apple app happens to write.

Current checks:

| Where | Tests |
| --- | --- |
| Swift core (`apps/apple/Packages/JournalCore/Tests/JournalCoreTests`) | `Conformance*Tests`, `InteroperabilityTests`, `InteroperabilityV2Tests`, `SyncReceiptVectorTests`, `AgentCopyTests`, `LibrarySyncTests`, `JournalOrderTests`. `scripts/check.sh core` |
| .NET server (`server/tests/Journal.Api.Tests`) | `*ConformanceTests`, `ProtocolVectorTests`, `AgentAccessTests`, `SyncEfficiencyTests`. `scripts/check.sh backend` |

Windows (C#) and Android (Kotlin) clients add their own tests against the same files.

## Changing a contract

- **Never edit a fixture in place** to make a test pass or to follow a change. A published fixture is what existing clients were built and tested against.
- A change to a contract (a new field a reader must understand, a different name rule, a new archive layout) raises that contract's version: add new fixtures beside the old ones (`-v2.json`, `v2/`), keep the old ones passing for as long as clients must read old data, and describe the difference in the folder's README.
- Additive changes within a version, such as a new optional field, get new cases in a new version of the file; the old file still describes what old data looks like.
- The archive is versioned by folder (`archive/v1/`), so a later layout slots in as `archive/v2/` without touching `v1`.
- Correcting a fixture that contradicts its contract (a mistake in the fixture, not a change of contract) is allowed with a note under Known issues saying what was wrong.

## Regenerating

Fixtures whose expected values come from the Swift reference implementation are golden files. Their tests compute the expected values from the fixture's own inputs and compare them with the file; in that mode nothing is written. To regenerate after a deliberate change:

```sh
JOURNAL_CONFORMANCE_REGENERATE=1 mise exec -- swift test \
  --package-path apps/apple/Packages/JournalCore --filter Conformance
git diff protocol/conformance
```

The same tests then rewrite those files from the inputs in the test sources. Review every difference as a protocol change (see above). Files that aren't rewritten were not produced this way: `crypto/` and `agent-copy/` (made by .NET and the Apple app's code, with fixed nonces), `sync/` (written from the contract and replayed against the server), `records/journal-ranks-v1.json` (an independent implementation). The archives in `archive/v1/` contain random nonces, so regenerating them makes new files; commit them only for a new version.

## Known issues

Disagreements between the documents and the implementations that the fixtures deliberately leave unpinned. They are reported, not fixed here.

- **Timestamps.** The Swift reader accepts out-of-range calendar fields (`2026-02-30T08:00:00Z`, hour `25`). The documents say ISO 8601. `records/timestamps-v1.json` lists only texts every reader must refuse; writers must never produce impossible dates.
- **Archive, unlisted files.** [archive.md](../archive.md) says a name in `attachments/` that is not a lower-case UUID (or any file the manifest doesn't list) makes the archive invalid, and that restore checks the files against the manifest exactly. The Swift restore copies only the files the manifest lists and ignores the others, so an extra file doesn't make it refuse. `archive/v1/expected.json` pins neither behavior.
- **Heading text.** [markdown-export.md](../markdown-export.md) says the heading is one line. The Swift export turns a line feed into a space but a CRLF in a title into two. The fixtures avoid CRLF in titles.
- **Link destinations with spaces.** The Swift writer writes a destination with a space as `a%20b`, which reads back as a different destination. The Markdown fixtures avoid it; the stored text is never changed unless the block is edited.
- **Attachment references in capitals.** [records.md](../records.md#images) says an image refers to an attachment when its destination is exactly `attachments/` and a UUID, and that UUIDs compare case-insensitively but are written in lower case. The Swift reader accepts a UUID in any letter case. The image fixtures don't pin it.
- **Derived block identities.** When a record has no `blockIDs`, the Apple app derives identities that are well-formed UUID text but not RFC 4122 version 4 values (for example a version digit of 2). Readers must not validate UUID version or variant bits.
- **Unicode tables.** The unassigned-code-point rule and full case folding in the [export names](markdown-export/README.md) depend on a Unicode version. The fixtures use code points that are stable across versions; a reader on a very old platform may still differ.
