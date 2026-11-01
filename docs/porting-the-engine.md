# Porting the engine

How to build another client's engine (document model, Markdown fidelity, encryption, sync, conflicts, archives, local storage) so that it interoperates byte for byte with the Apple apps and the server. The Apple engine is `apps/apple/Packages/JournalCore`; the first port is the C# engine of the Windows app ([apps/windows/AGENTS.md](../apps/windows/AGENTS.md)).

**Baseline: Apple 1.1 (build 23, tag `v1.1.0`) and the server at the same tag.** Protocol revision 1, file archive (`.journalbackup`), encrypted libraries only, conflicts v1.

## How to use this page

1. The contracts in [protocol/](../protocol/README.md) and the fixtures in [protocol/conformance/](../protocol/conformance/README.md) decide what is correct. This page is a map from each behaviour to them, to the Swift that implements it and to the Swift tests that pin it. It does not repeat the rules; read the contract.
2. Where a contract is silent, the Swift is what the Apple apps do, not a rule. Do not copy it silently: ask the owner and fix the contract ([root AGENTS.md](../AGENTS.md), "Working across platforms"). "Not pinned" below marks behaviour that only Swift code or a Swift test defines.
3. Clients share no code. Port from the contract; use the Swift to understand a rule, not to translate it line by line (it relies on GRDB, swift-markdown, CryptoKit and Foundation behaviour that .NET does not share).
4. Sources are in `apps/apple/Packages/JournalCore/Sources/JournalCore/` (written `File.swift` below) and tests in `apps/apple/Packages/JournalCore/Tests/JournalCoreTests/` (written `FooTests`).
5. A C# engine already exists in part, as test code: `server/tests/Journal.Api.Tests/` has an independent .NET reader of the file archive written from `protocol/archive.md` (`ZipContainerReader.cs`, `FileArchiveReader.cs`, `ArchiveDatabaseInspector.cs`, `ArchiveSchemaScan.cs`, `ArchiveSchemaWords.cs`, `ArchiveStrictJson.cs`, `ArchiveHeaderAndManifest.cs`, `ArchiveCrypto.cs`), AES-GCM, timestamp and UUID helpers (`ConformanceFormats.cs`), and the conflict identity derivation (`ConflictIdentityConformanceTests.cs`). The classes are `internal` test helpers: copy and adapt what you need under the project license, do not reference the test project. The server itself (`server/src/Journal.Api`) is the reference for the other side of every request.

## Suggested order

Each step is done when its fixtures pass in the engine's own tests; nothing above a step relies on a guess about it.

1. Primitives and formats: base64 (canonical), UUID text, timestamps, AES-256-GCM sealing with contexts, PBKDF2/HKDF, recovery envelopes, password normalization (`crypto/`, `records/timestamps-v1.json`).
2. Records: reading rules, read-only and unreadable records, markers, the library record (`records/`).
3. Markdown text, attachments and the neutral block vocabulary (`markdown/`); the editor choice ([entry-editor](../spec/platforms/windows/screens/entry-editor.md), the spikes) decides the block model above this layer.
4. Local store with the archive schema (see Archives), then the file archive reader and writer (`archive/`).
5. Wire client and status gating (`sync/exchanges-v1.json`, `sync/status-v2.json`, `sync/sync-receipts-v1.json`), then the sync engine against a real server.
6. Conflicts (`records/conflict-resolution-v1.json`, `records/conflict-copy-ids-v1.json`, `sync/conflict-scenarios-v1.json`).
7. Lifecycle, journal names, permanent deletion, history, library record rules.
8. Pairing (`pairing/`, `crypto/encryption-v2.json`), then agent access ([protocol/agent-access-server.md](../protocol/agent-access-server.md), `agent-copy/`), which Windows ships later.

## Map

### Wire client and compatibility gate

- Contract: [protocol/README.md](../protocol/README.md) (wire conventions, Versioning and revisions, Sync and conflicts, Errors, Limits). Fixtures: `sync/exchanges-v1.json`, `sync/status-v2.json`, `sync/sync-receipts-v1.json`.
- Swift: `ServerClient.swift` (requests, `ServerStatus.compatibility`, short receipts, problem codes, wait), `SyncHealth.swift` (failure to person-visible state; spec: `flows/sync-recovery.md`). Tests: `ConformanceSyncTests`, `ServerRevisionTests`, `ServerRevisionGateTests`, `SyncReceiptVectorTests`, `ServerDeviceTests`, `SyncHealthTests`.
- Must not simplify:
  - The effective revision is computed from `protocolVersion`, `protocolRevision` and the 13 frozen `features`, on every status read, and never kept. A malformed `protocolRevision` counts as absent. A server below revision 1 changes and discards nothing on the device.
  - Branch on error `code`, never on text; no redirects; HTTPS except loopback.
  - UUIDs: lower case in paths, authenticated data and file names; Apple sends upper case in JSON bodies. Compare case-insensitively.
  - Receipts: accept a short receipt only if it names the record and kind sent, the next revision and the digest of exactly the payload sent.
  - Wait: one at a time, a `false` confirms only when it arrives late enough and not `early`, anything else becomes an ordinary sync.

### Cryptography, envelopes, passwords

- Contract: protocol/README.md (Encrypted content, Recovery formats, Setup and recovery). Fixtures: `crypto/encryption-v1.json`, `encryption-v2.json`, `negative-v1.json`.
- Swift: `Crypto.swift` (sealing, envelopes, derivations, `RecoveryDerivation`, password change), `CJournalCrypto`. Tests: `ConformanceCryptoTests`, `InteroperabilityTests`, `InteroperabilityV2Tests`, `PasswordProtectionTests`, `JournalCoreTests`, `PairingPasswordTests`.
- Must not simplify:
  - Authenticate the received bytes before parsing; contexts use the lower-case ID and the kind; an upper-case ID, another kind or no context must fail.
  - Password normalization: NFC first and, only when the typed text differs from its NFC form, the exact text second; format 1 trims and nothing else; the server gets the NFC-derived `recoverySecret` first and the exact one only after a 401.
  - A 1.1 client creates and opens recovery formats 1 and 2 only. Formats 3 and 4 (readable libraries, 1.0 only) are refused everywhere: library, server, directory archive. Never read an encryption failure as plaintext.
  - Check the envelope's parameters against what the person was shown (the client revokes a credential and stops if they changed).
  - Binary values are canonical padded base64; reject whitespace, missing padding, non-zero padding bits and the URL-safe alphabet.
- .NET: PBKDF2, HKDF, HMAC, SHA-256 and AES-GCM (12-byte nonce, 16-byte tag) are in `System.Security.Cryptography`. X25519 is not (see Pairing).

### Records, documents, reading rules

- Contract: [records.md](../protocol/records.md) (fields, Documents, Reading rules, Writing a journal back). Fixtures: `records/records-v1.json`, `records/timestamps-v1.json`, `records/journal-rewrite-v1.json`.
- Swift: `Models.swift` (`JournalItem`, `JournalDocument`, `isEditable`), `PortableRecord.swift` (decode, `knownRecord`, `unreadable`, encode), `StoreDecoding.swift`, `ArchiveJSON.swift` (strict JSON for archives). Tests: `ConformanceRecordsTests`, `ConformanceRecordCases`, `DecodedRecordTests`, `TimestampInteropTests`, `JournalSettingsPreservedTests`.
- Must not simplify:
  - Three classes: editable, read-only (authenticates and parses but has an unknown member, kind or document version) and unreadable. Keep the original bytes of the last two, sync them unchanged, never save over them; an edit made from an older copy becomes a conflict.
  - Write only the members the contract lists. Apple 1.1 treats a record with any other member (in the record, the document or `metadata`) as read-only.
  - Timestamps are read with offsets and up to seven fraction digits and kept to the whole second, rounded down; write whole seconds with `Z`. UUIDs in record JSON are compared without regard to case.
  - Marker rules: a canonical marker only; a record with marker fields that is not canonical is unreadable and never a marker.
  - Stale-save detection compares the stored payload text, not parsed content (`StoredVersion`, SHA-256 of the stored payload).
  - `defaultTemplateID` survives every journal rewrite.
  - `archivedAt` belongs to entries only (on a journal or template the record is unreadable); keep it unchanged, never set it ([entry-archiving.md](../protocol/entry-archiving.md)).

### Markdown fidelity

- Contract: records.md (Markdown, Images). Fixtures: `markdown/documents-v1.json` (24 bodies), `markdown/images-v1.json` (18), `markdown-export/`.
- Swift: `MarkdownDocument.swift` (document, segments, identities), `MarkdownReader.swift`, `MarkdownWriter.swift`, `MarkdownTasks.swift`, `MarkdownAttachments.swift`, `DocumentImages.swift`, `DocumentTable.swift`, `ImageDescriptions.swift`. Parser: swift-markdown 0.9.0 (cmark-gfm). Tests: `ConformanceMarkdownTests`, `ConformanceMarkdownCases`, `MarkdownFidelityTests`, `MarkdownTests`, `LongEntryEditTests`, `ImageDescriptionTests`.
- Must not simplify:
  - The stored text of an unchanged block is unchanged byte for byte: LF, CR and CRLF line endings, reference definitions, list markers and indentation, trailing spaces, blank lines. Only edited blocks are written again, with blank lines only where needed to keep blocks apart.
  - What the writer writes must read back as the same blocks (`canonicalReadsBackAsTheSameBlocks`). Not pinned beyond the 24 fixture bodies: escaping only where syntax would otherwise begin or end, edge spaces beside emphasis as character references, the inert `<!-- -->` separator between adjacent marks, table cells on one line with escaped pipes, an empty list item before a nested item, a table interrupting a paragraph. `MarkdownFidelityTests` and `MarkdownTests` are the only specification of these; read them before choosing a Markdown library and run the same inputs through the port.
  - Content the rich view cannot show (`requiresSource`) is kept exactly and edited as source; image descriptions are refused for such a document.
  - An image refers to an attachment only for the exact destination `attachments/<uuid>` (also inside links, tables, reference definitions); remapping on import changes only those occurrences, never text quoted in code.
  - `metadata`: `blockIDs` and `segmentLengths` are optional; ignore `segmentLengths` unless the counts and the byte sum match; `imageTypes` keys are lower-case UUIDs. Metadata is part of the content compared by conflicts, so unchanged text must keep unchanged metadata, or the person gets a needless "(other version)".
  - Identities derived when `blockIDs` are missing are local and not pinned; never validate UUID version or variant bits.

### Local store

- Contract: [archive.md](../protocol/archive.md) (Database: the tables and settings keys are normative), [docs/architecture.md](architecture.md) (Data on a device, Sync). Fixtures: `archive/v2/database-v2.json`, `archive/v2/database/`.
- Swift: `Store.swift` (open, migrations, save, acknowledge, apply, conflict rows), `StoreCheckpoints.swift`, `StoreHistory.swift`, `StoreAttachments.swift`, `StoreServerVersions.swift`, `StoreSameContent.swift`, `StorePendingCounts.swift`, `UnsentItems.swift`, `LocalDataFailure.swift`. Tests: `JournalCoreTests`, `StaleSaveTests`, `SyncEngineTests`, `ServerRestoreTests`, `VersionCheckpointTests`, `MoveTests`, `EntryDateTests`, `UnsentItemsTests`, `LocalDataFailureTests`.
- Not pinned by a fixture, defined only by `Store.swift` and these tests:
  - One outbox row per record (`INSERT OR IGNORE` on a unique record); a queued operation keeps its bytes until it is acknowledged or retired, and a later save is queued at the acknowledged revision. A record with a conflict row is saved but not queued.
  - A save names the stored version it was edited from; if the record changed meanwhile, the stored version becomes the conflict row (or goes to history when a conflict already waits) and the save proceeds.
  - Applying a pulled change: a lower revision is ignored; an equal revision with another payload is kept as the other version only when `server_versions` does not know that payload and the content differs; a change equal to the queued payload at base + 1 acknowledges it; a dirty record, a record with a conflict, or a marker replaced by an ordinary record (unless `restoredFromDeletionID` names that marker) records a conflict; an incoming canonical marker removes the record's history; an incoming version this client cannot read first copies the last readable version to history. A page and its cursor commit in one transaction after every change authenticates.
  - Version History checkpoints (`checkpoint = 1` rows): a new editing session starts after 10 minutes without a change and a version is kept at most every 10 minutes while editing continues, at most 50 per record (only checkpoints are pruned); the timing is in memory and checkpoints are never synchronized; design: `design/version-checkpoints.md`.
  - Keep the Apple schema for the local database (including `grdb_migrations`, with the five identifiers in order), so that an archive is a snapshot and a restored archive is opened in place.

### Sync engine

- Contract: protocol/README.md (Sync and conflicts, Server identity after restore, Waiting for changes), [architecture.md](architecture.md) (Sync). Fixtures: `sync/exchanges-v1.json`, `sync/conflict-scenarios-v1.json` (one restored-server scenario only).
- Swift: `SyncEngine.swift`, `SyncReconciliation.swift`, `StoreServerVersions.swift`, `SyncWaiting.swift`, `ServerClient.swift`. Design: `design/sync-protocol-efficiency.md`, `design/sync-health-and-recovery.md`. Tests: `SyncEngineTests`, `ServerRestoreTests`, `SyncEfficiencyTests`, `SynchronizationGateTests`, `ConflictScenarioTests`, `JournalCoreTests`. The Swift probe (`JournalProbe`, run by `scripts/test-sync.sh`) is an end-to-end client against a real server; there is no C# equivalent yet.
- Must not simplify:
  - Order of one round: status gate; reconcile if the server identity changed; images before the records that use them; push each pending operation with its base revision; pull pages until `hasMore` is false (a page that does not advance, or has changes outside `(after, cursor]`, is an error); settle conflicts; push what settlement queued; number duplicate journals (up to three rounds); download images (time-boxed per pass, the open entry's first).
  - Before sending, confirm the server still has the change last read (`afterRecord`, `afterRevision`, `afterDigest`, `limit=1`) and the newest accepted write when it is past the cursor.
  - `revision_ahead`, `server_changed` and a push accepted at an already seen cursor start reconciliation; a version at a revision the device holds with another digest is a conflict. Nothing is discarded.
  - Failure handling: a record or image the server refuses (400, 413, `operation_reused`) stays on the device with an explanation until edited or Sync Now; other per-item failures wait 15 s doubling to 10 min; three server errors in a row for one record refuse it; connection errors delay nothing. One item never holds up the rest.
  - Writing is sent after a 2 s pause (30 s at most while typing); one synchronization at a time per library, a request during a pass runs after it.
  - A library never syncs with a server whose recovery format implies readable journals.

### Conflicts (conflicts v1)

- Contract: [conflicts.md](../protocol/conflicts.md); [permanent-deletion.md](../protocol/permanent-deletion.md) (Receiving and saving; ignore the review forms, which only 1.0 shows). Fixtures: `records/conflict-resolution-v1.json` (46 cases), `records/conflict-copy-ids-v1.json`, `sync/conflict-scenarios-v1.json` (14 scenarios).
- Swift: `ConflictResolution.swift` (the pure rules), `StoreConflictResolution.swift` (resolution points, one transaction per record, the pass over earlier rows), `StoreConflictCopies.swift`, `KeptNotes.swift`, `StoreSameContent.swift`. Tests: `ConformanceConflictTests`, `ConformanceConflictCases`, `ConflictScenarioTests`, `ConflictConvergenceTests`, `ConflictResolutionTests`, `ConflictResolutionPointsTests`, `ConflictSafetyTests`, `ConflictSettlementSafetyTests`, `StoreConflictResolutionTests`, `StoreKeepBothTests`, `StoreKeepBothReplacedCopyTests`, `StoreSameContentTests`, `ImportLifecycleTests`.
- Must not simplify:
  - There is no review screen. Implement all seven rows; a rule applied differently makes devices disagree about which records exist. Row 1 holds a record this client cannot fully read.
  - "Same content" is strict and field by field: document compared as a JSON value (strings by code points, `1` is not `1.0`, absent is not present), dates as whole-second instants. Do not normalize Unicode. In .NET keep the original number text; `JsonElement` equality is not enough.
  - Copy and parked identities: HKDF key, HMAC tag, version and variant bits set, built from the bytes, not from a `Guid` (mixed endian). Hash the exact plaintext received.
  - Copy decision order: a record with the derived identity in any state means do nothing; else replace the latest untouched earlier copy from the same known device; else make it. Never revive a marker. A device that wrote a copy remembers its digest, origin device and revision (last 200).
  - Never settle during a reconciliation, for a record being written (2 s pause), or a held conflict. Resolution points: end of a completed pull, library opening (rows an earlier version left, and everything when no server is configured), after a merge or import, after a stale save once writing pauses.
  - The title of a copy of an untitled version uses "the title the lists show": the first non-empty line of the document's rendered text (the blocks' text joined by LF, so heading markers and emphasis marks are not in it; the Markdown source only for a document that requires source), cut at 60 grapheme clusters. The contract says "its text" without saying this and the fixtures use plain paragraphs only, so it is not pinned (`ConflictResolution.copyTitle`, `JournalDocument.firstLine`). Ask the owner before choosing.
  - Notes for the person are not synchronized; keep them 30 days.

### Lifecycle, names, deletion, history

- Contract: [journal-lifecycle.md](../protocol/journal-lifecycle.md) (including Journal names), permanent-deletion.md, [entry-archiving.md](../protocol/entry-archiving.md), [history-recovery.md](../protocol/history-recovery.md). Fixtures: none of their own (markers: `records/records-v1.json`; deletion against edits: conflict rows 4, 5, 7 and scenarios).
- Swift: `JournalLifecycle.swift` (snapshot, entry location), `Store.swift` (delete and restore journal, move), `StoreRestoreEntry.swift`, `PermanentDeletion.swift`, `StoreDeletion.swift`, `JournalNames.swift`, `StoreHistory.swift`, `HistoryRecovery.swift`, `EntryArchiving.swift`, `EntryDate.swift`. Tests: `JournalLifecycleTests`, `RestoreEntryTests`, `MoveTests`, `TemplateDeletionTests`, `PermanentDeletionMarkerTests`, `PermanentDeletionPlanTests`, `PermanentDeletionTransactionTests`, `JournalNameTests`, `JournalNameSyncTests`, `HistoryRecoveryTests`, `VersionCheckpointTests`, `EntryArchivingTests`, `EntryDateTests`.
- Must not simplify:
  - An entry's location comes from one snapshot of records and conflicts, in the contract's order; deleting a journal changes only the journal record.
  - Restore puts an entry in its own journal when usable, else the fallback, decided inside one transaction; it clears only the entry's own tombstone.
  - Permanent deletion revalidates its captured scope inside the write and replaces records with canonical markers at their current revision; history of those records goes.
  - Journal names: receiving never refuses or renames on arrival; after a full read the oldest by (`date`, ID) keeps a name and the others get "name 2", the smallest free number, sent as ordinary changes and dropped when refused as stale. Every device must compute the same names. Not pinned: Apple compares names with Foundation's `trimmingCharacters(in: .whitespacesAndNewlines)` and `folding(options: [.caseInsensitive], locale: nil)`; .NET's invariant or ordinal casing differs for some characters. No fixture; ask the owner before choosing.

### Library record: pins and journal order

- Contract: records.md (The library record). Fixtures: `records/library-record-v1.json`, `records/journal-ranks-v1.json`.
- Swift: `LibraryRecord.swift`, `StoreLibrary.swift`, `JournalRanks.swift`. Tests: `LibrarySyncTests`, `LibraryCompatibilityTests`, `JournalOrderTests`.
- Must not simplify: the merge rules (intents with strengths, clearing, restores and forks) replace reviews for this kind only; unknown namespaces and members survive; ranks compare byte by byte; the record is never in history, search or counts. The merge rules themselves have no fixture.

### Archives, import and merge

- Contract: [archive.md](../protocol/archive.md). Fixtures: `archive/v2/` (real archives, over a hundred container cases, database structure and foreign databases); `archive/v1/` only for Apple (directory archives); Windows never reads or writes those.
- Swift: `Archive.swift`, `FileArchive.swift`, `ArchiveContainer.swift`, `ZipReading.swift`, `ZipExtraction.swift`, `ZipWriting.swift`, `ArchiveJSON.swift`, `ArchiveLimits.swift`, `ArchiveDatabaseInspection.swift`, `ArchiveSchemaScan.swift`, `ArchiveSchemaWords.swift`, `StoreArchiveSnapshot.swift`, `ContentImport.swift`, `Store.swift` (`importAsNewJournals`), `MergePlan.swift`, `StoreMerge.swift`. Tests: `ConformanceArchiveTests`, `ConformanceArchiveV2Tests`, `ConformanceArchiveUnlistedTests`, `ConformanceContainerTests`, `ConformanceArchiveDatabaseTests`, `ArchiveSweepTests`, `ArchiveReaderHardeningTests`, `ArchiveDatabaseHostileTests`, `ArchiveJSONTests`, `FileArchiveTests`, `ArchiveTests`, `ArchiveHistoryTests`, `ArchiveIndependentToolsTests` (with `Tests/check-archive-with-tools.sh`), `ImportTests`, `MergeTests`, `MergeRuleTests`.
- Must not simplify:
  - Read exactly the files the manifest lists; ZIP rules (end record, ZIP64, duplicates, overlaps, CRC-32 before SHA-256, expansion limit) are the reader's job because .NET `ZipArchive` hides them; enforce the central directory limits before asking for the password.
  - The database inside is the library's own schema; structure is compared, not `CREATE` text; extra objects, write-ahead mode and unknown migrations are refused. Open it in place after the check; do not copy rows.
  - The writer: SQLite online backup in `DELETE` mode, exclusive creation, stored entries, fixed 1980 time, the header last with the sealed manifest (`journal:v2:archive`).
  - Import uses new random identities and the destination's key; remapping applies to current, historical and conflicting versions and to every reference, including missing targets. Records this client cannot read cannot be remapped.
  - Merging a device library into a server (joining with local journals) derives identities as `UUID(SHA-256("myjournal-merge-1" ‖ server identity ‖ original ID))` so a retry is idempotent. This is only in [design/join-with-local-journals.md](design/join-with-local-journals.md); no fixture pins it.

### Pairing

- Contract: protocol/README.md (Pairing, Invite pairing). Fixtures: `pairing/pairing-v1.json`, `crypto/encryption-v2.json` (`pairing`, with the RFC 7748 section 6.1 keys).
- Swift: `Pairing.swift`, `PairingInvite.swift`, `CodeEntry.swift`. Tests: `ConformancePairingTests`, `PairingGrantBindingTests`, `PairingInviteTests`, `PairingPasswordTests`.
- X25519: .NET has no portable X25519 (`protocol/conformance/crypto/README.md`; the server never performs the key agreement). The Windows engine needs a library or a platform API that exists for x64 and Arm64; a new dependency needs a documented reason ([root AGENTS.md](../AGENTS.md)). Check it with the RFC 7748 vectors in `encryption-v2.json`. The hash, HKDF, HMAC and AES-GCM steps after the shared secret are plain .NET.
- Must not simplify: commitment before approver key, approver key fixed before reveal; confirm the check code before sending or opening a grant; the grant's first 32 bytes must equal the approver key the code was computed from; the invite proof binds the origin; never fall back from an invite to a plain request.

### Markdown export

- Contract: [markdown-export.md](../protocol/markdown-export.md). Fixtures: `markdown-export/names-v1.json`, `library-v1.json`.
- Swift: `MarkdownExport.swift`, `MarkdownExportPlan.swift`. Tests: `MarkdownExportTests`, `ConformanceExportNamesTests`, `ConformanceExportLibraryTests`. Needs Unicode normalization, full case folding and grapheme clusters; see Known issues in the fixtures index.

### Agent access

- Contract: [agent-access-server.md](../protocol/agent-access-server.md). Fixtures: `agent-copy/agent-copy-v1.json` (crypto only). Swift: `AgentCopy.swift`, `AgentCopyClient.swift`, `AgentCopyPublisher.swift`, `StoreAgentCopy.swift`. Tests: `AgentCopyTests`; server: `AgentAccessTests`, `AgentApprovalTests`. Windows status: planned (`spec/parity.yaml`). Read-only, journal-scoped, enforced in code.

### Apple-only, not part of the port

`Keychain.swift` (Windows uses its own secret storage, [platform.md](../spec/platforms/windows/platform.md) section on secrets), `ChangeWatcher.swift`, `EntrySearch.swift` (local search is specified in `spec/screens/search.md`), `JournalProbe` and `JournalMeasure` (tools), `SyncSchedule` and the app model (in the app, not in JournalCore).

## .NET traps the documents already call out

- `Guid` is mixed endian and `Guid.TryParse` is permissive: build identity strings from bytes; check the exact lower-case pattern for names.
- `ZipArchive` and Microsoft.Data.Sqlite hide what the archive rules require you to check (duplicates, overlap, CRC-32, schema objects); parse the ZIP layer yourself.
- Compare JSON member names and strings ordinally, as bytes or code points; never with culture or canonical equivalence.
- `Convert.FromBase64String` accepts whitespace; check canonical form yourself.
- Order of ranks and names of export files: ordinal, never culture.
- Record bytes: authenticate and keep the received bytes; a serializer's key order and escaping need not match Apple's.

## Rules without fixtures

[protocol/conformance/README.md](../protocol/conformance/README.md#rules-without-fixtures) lists them, ranked by interoperability risk. A port should write its own tests from the Swift tests named above for each of them and report any disagreement with the Apple behaviour to the owner.
