# sync

The sync endpoints ([Sync and conflicts](../../README.md#sync-and-conflicts) in the protocol README).

| File | Covers | Produced by |
| --- | --- | --- |
| `exchanges-v1.json` | A conversation of 29 requests and the exact responses: create, retry, reused operation, short receipt, stale and ahead base revisions, immutable kind, payload limits and checks, other server identity, paging, continuity checks, waits, no credential, capabilities and status | Written from the contract; replayed against the server |
| `conflict-scenarios-v1.json` | Devices that change the same records offline and meet at a server, with what every device must hold at the end ([conflicts.md](../../conflicts.md)) | Written from the contract; replayed against real clients' stores |
| `sync-receipts-v1.json` | A push, its full receipt and the equivalent short receipt (capability `sync-short-receipt`, `payloadDigest` = lower-case hex SHA-256 of the payload text), and the three wait answers ([README.md](../../README.md#waiting-for-changes)) | Python's hashlib; checked by the server's serializer and the Apple client's decoder |

## The conversation (`exchanges-v1.json`)

`preconditions` and `matching` in the file define how it is run; in short:

- Run the `steps` in order against one new server whose vault is set up in recovery format 1 or 2, with one device sending its bearer credential on every request unless a step's request says `"authenticated": false`.
- A request has a `method`, a `path` (with its query) and, for PUT, a JSON `body`.
- A response has a `status`, optionally a `contentType` and `headers` (lower-case names; a value is a prefix), and a `body`. With `"match": "subset"` the server's body may have more members. Error responses are `application/problem+json`.
- `volatile` lists JSON pointers to values the server chooses (device IDs, timestamps, the server identity): compare their format (`uuid`, `timestamp`), not their value. `identicalTo` names an earlier step whose actual body this one must repeat exactly.
- `client` says how a client reads the response: `receipt` (an accepted push, full or short), `conflict` (stale base revision: keep the local version and review the server's `current`), `serverBehind` (the base is ahead: the server lost revisions), `serverChanged` (reconcile), `rejected` (not applied; keep the record on the device and go on), `page`, `wait`, `problem`, `status`, `capabilities`.

The server's `SyncExchangeConformanceTests` replays the file. Swift `ConformanceSyncTests` reads every response with the client's own decoders (`ServerClient.receipt`, `pushConflict`, `SyncPage`, `problemCode`, `waitAnswer`). A new client's transport layer should do the same.

Payloads in the file are synthetic bytes of at least 29 bytes, not real ciphertexts; the server never interprets them. The one exception is a step that sends a readable JSON document to an encrypted vault, which must be refused with `unencrypted_record`.

## Conflict scenarios

`conflict-scenarios-v1.json` is a list of scripted conversations. Each scenario names its `devices`, an optional `pageSize` (changes per page, to put page boundaries inside the log), `steps` and what to `expect`. A step is one device doing one thing (`createJournal`, `createEntry`, `editEntry`, `renameJournal`, `deleteJournal`, `deleteEntry`, `deleteForGood`) or one synchronization round (`sync`), or all devices synchronizing in turn until nothing changes (`settleAll`). `operations` in the file says what each takes; `record` names are labels the runner maps to fresh identities. Between steps a person pauses for a moment, so no record counts as being written.

A runner builds one library for every device, with the vault key of `../crypto/encryption-v2.json` (`recovery.vaultKey`), runs the steps against a server that follows the sync contract, and checks `expect`: every device holds the same records, with `total` records in all (markers included); each entry of `records` matches exactly `count` (default 1) records by `record` label or by `kind`, `title` and `text`, in the given `state` (entries: `live`, `recentlyDeleted`, `unavailable`, `permanentlyDeleted`; journals: `live`, `recentlyDeleted`, `permanentlyDeleted`); `notes` lists the kinds of note each device made for the person (`journalRenamed`, `journalDeleted`, `deletedAndChanged`), none for the others; `reviewRows` conflicts are left to review on every device; and nothing is left to send. Identities of parked entries are not pinned, because they hash the exact bytes a device wrote; the runner checks that every device derived the same ones.

The pure rules are in `../records/conflict-resolution-v1.json`; these scenarios are what shows that two clients interoperate. The server never interprets payloads and replays none of this.
