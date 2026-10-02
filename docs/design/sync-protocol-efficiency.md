# Sync protocol efficiency: short push receipts and waiting for changes

Status: **revision 7, design only. Nothing is implemented.**

- Rounds 1 to 4 and 6 approved with required changes; round 5 requested changes. All are applied here. The rounds are recorded in
  [sync-protocol-efficiency-review.md](sync-protocol-efficiency-review.md).
- Waiting for: the next independent review round, a red team, the tests in §7 and the owner's approval.
- Target: build 10.

Builds on [protocol/README.md](../../protocol/README.md) (Sync and conflicts, Server identity after restore, Rate
limits), [sync-health-and-recovery.md](sync-health-and-recovery.md) §2 (states and when automatic sync stops) and
the performance work in [docs/performance.md](../performance.md).

## Owner request (2026-10-02)

> I want you to implement and test these two improvements. But because they are touching the critical protocol we
> should be more careful here and get it properly reviewed and do enough testing on it, including a red team agent.
> Only then we can be certain that the fix is stable enough to be included in the next build (10)

The two improvements, from a bandwidth audit:

1. **Short push receipt.** When the server accepts a record, it returns the whole encrypted record. Return a compact
   receipt instead (record ID, new revision, cursor, payload digest) when the client asks for it.
2. **Waiting for changes instead of polling.** The server tells connected clients when its change log advances, so
   idle traffic in the foreground drops to near zero while new changes still arrive at once. Polling stays as the
   fallback.

## Summary

| | Short push receipt | Waiting for changes |
| --- | --- | --- |
| Capability | `sync-short-receipt` | `sync-wait` |
| Wire | PUT /v1/sync/{id} gains optional `shortReceipt: true`; the 200 receipt then has `payloadDigest` instead of `payload` | New GET /v1/sync/wait?after=&afterRecord=&afterRevision=&afterDigest=&serverId=&timeout= returning `{changed: true\|false}` |
| Stored server state | None. No migration | None. No migration; in-memory waiters only |
| Client change | ServerClient checks the digest and rebuilds the full receipt from what it sent; SyncEngine and the store are unchanged | A watcher waits only while sync is healthy and has nothing left to do; any doubt runs an ordinary sync |
| Content on the new path | None (a digest of the device's own payload) | None (one boolean) |
| Off when | Either side lacks it: full receipts, as today | Either side lacks it, or waits keep failing: polling at today's pace |

**User-visible effects: none intended.** Sync health states, messages and actions stay as they are, so the frontend
design gate doesn't apply. The one thing that could have changed is Last Synced. It updates only after a full sync
today (`syncActivity.synced()`, AppModel.swift), and waits replace most idle syncs. So a wait answered `false`, on
time and while settled, counts as a completed sync for Last Synced (§4.6). Last Synced therefore keeps reading "Just
now" while idle, as today, including when a refused entry or image stays behind.

## 1. What happens today (from the code)

**Push.** `SyncEndpoints.Write` stores the change and answers with `JsonSerializer.Serialize(change)`: cursor,
recordId, revision, kind, **payload**, deviceId, modifiedAt. A retry of the same operation returns the same receipt,
read again from the change log (`Receipt`, via `AppliedOperation.ChangeCursor`; older operations keep `ResponseJson`).
The client (`ServerClient.push`) decodes it as a `RemoteChange` with a 16 MiB response limit.

What the client uses from that receipt:

- `JournalStore.acknowledge` checks `recordId == pending.recordID`, `payload == pending.payload` and
  `revision == baseRevision + 1`, otherwise `invalidData`.
- `acknowledgeSent` uses `revision` (outbox, records, `settleAcknowledged`, `server_versions` digest of the payload),
  and `LoggedChange(receipt)`: recordId, revision and SHA-256 of the payload, for `sent-change` and, with
  `readingOn`, the `cursor-change` that `sync-continuity-digest` confirms later.
- `SyncEngine.push` uses `cursor`: an accepted cursor at or below what this device saw means the server lost changes,
  and it starts reconciliation.
- `adoptAutomaticRename` checks the same three fields and stores `receipt.payload`, equal to what was sent.
- `kind`, `deviceId` and `modifiedAt` are decoded but not used.

So the payload in the receipt only ever has to equal what the client sent; the server echoes back up to 4 MiB
(about 5.3 MiB as base64) that the client already holds.

**Idle polling.** `synchronizeAutomatically` (SyncSchedule.swift) runs a sync every 3 s while My Journal is the active
app, and every 30 s while it's open but another app is active (Mac). Both pauses come from `nextSyncDelay`. An idle
sync reuses the status for 60 s and makes one GET /v1/sync/ page request (with `afterRecord`, `afterRevision`,
`afterDigest`) that returns an empty page. After each successful sync, `AgentCopyPublisher.publishAll` re-reads
GET /v1/agents/ at most every 10 minutes (`listLifetime`; the comment beside it saying "every minute" is stale), and
`syncActivity.synced()` updates Last Synced. The loop stops in the
background, while locked, and in the stopped health states.

## 2. Capabilities, negotiation and compatibility

Both capabilities are added to the existing `features` list (GET /v1/server and /v1/status). The Apple app reads
`/status` at the start of every sync, or reuses it for up to 60 s.

- A client sends `shortReceipt` only to a server listing `sync-short-receipt`, and calls /v1/sync/wait only on a
  server listing `sync-wait`.
- A server returns a short receipt only when the request asks for one, and holds a wait only when asked.
- A client that asked for a short receipt still accepts a full one. A server could stop listing the capability between
  the status read and the push (a downgrade), and older receipts kept as `ResponseJson` are returned whole.
- No database migration and nothing persisted, so a server can be upgraded or downgraded in either direction
  ([server-backup.md](../../protocol/server-backup.md)) without a format change.

| | Server without the capabilities (today, and any older) | New server |
| --- | --- | --- |
| **App build 9 or older, other clients** | As today | As today: `shortReceipt` is never sent, so receipts are full; /v1/sync/wait is never called |
| **New app** | As today: the capabilities are absent, so the app sends no flag, never waits and polls | Short receipts; waits while idle |

Unknown request fields are already ignored (protocol/README.md, Versioning), so even a flag sent to an old server by
mistake would only produce a full receipt, which the new client accepts. Gating on the capability keeps the rule
"behavior switches on only when both sides advertise it" and lets the server's list stay the single switch.

## 3. Short push receipt

### 3.1 Wire

PUT /v1/sync/{recordId}: request as today, plus optional `shortReceipt` (boolean, default false).

200 response with `shortReceipt: true`:

```json
{
  "cursor": 4812,
  "recordId": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
  "revision": 7,
  "kind": "entry",
  "deviceId": "8c5e2f0a-1b6d-4c84-9f3e-2a7d1e0b9c41",
  "modifiedAt": "2026-10-02T09:14:03.1234567+00:00",
  "payloadDigest": "<64 lower-case hexadecimal characters>"
}
```

The full receipt minus `payload`, plus `payloadDigest`: the lower-case hex SHA-256 of the stored payload text's UTF-8
bytes. That is the same definition as `afterDigest` (`sync-continuity-digest`) and `JournalStore.payloadDigest`. The
receipt is about 300 bytes, whatever the record's size.

Everything else is unchanged:

- 409 `revision_conflict` and `revision_ahead` still carry `current` with the server's whole payload. The client needs
  it to keep both versions for review.
- 409 `operation_reused`, `server_changed`, 400, 413 and 401 are unchanged.
- Without the flag, or with `false`, the receipt is the full one.

### 3.2 Server

- `PutRecord` gains `bool? ShortReceipt = null`. It is **not** part of the operation's request hash, like `serverId`.
  An operation is the same operation whichever receipt form a retry asks for: a request that first asked for a full
  receipt and is retried by an updated app asking for a short one gets the short form of the same change, and the
  other way round.
- The first answer and every retry (`Receipt`) serialize the same stored change, either whole or short.
  `payloadDigest` comes from the existing `SyncEndpoints.Digest` helper over the stored `Change.Payload`, the same
  function the continuity check uses. Nothing new is stored.
- An operation kept only as legacy `ResponseJson` (applied before `ChangeCursor` existed) is returned whole, as today.
- One serializer for both forms, so the field names and date format can't drift from the full receipt.

### 3.3 Client

- **Passing the capability.** `SyncServer.push` (SyncEngine.swift) and `ServerClient.push` gain a `shortReceipt`
  parameter. `SyncEngine` sets it from `status.supports("sync-short-receipt")` for this sync, as it does for the
  continuity capabilities, for both queued records and automatic renames.
- **Decoding a 200 by shape.** A member set to `null` counts as present and invalid, so it is rejected.
  - `payload` present and `payloadDigest` absent: a full receipt, handled as today.
  - `payload` absent and `payloadDigest` present: a short receipt.
  - Both present: both are checked. `payload` must equal what was sent, and `payloadDigest` must equal its digest.
    Any disagreement is rejected.
  - Neither present: rejected.
- **Required members of a short receipt**: `cursor`, `recordId`, `revision`, `kind`, `deviceId`, `modifiedAt` and
  `payloadDigest`, with the same types as the full receipt. `payloadDigest` is 64 lower-case hexadecimal characters.
- **Accepting a short receipt** (including the both-present case) needs every one of these:
  - `recordId` equals the record sent;
  - `kind` equals the kind sent;
  - `revision` equals `baseRevision + 1`;
  - `payloadDigest` equals `JournalStore.payloadDigest(pending.payload)`.

  The client then builds the same `RemoteChange` a full receipt would have given, with `payload = pending.payload`.
- **Rejection**: `JournalError.invalidData`, exactly as a full receipt with another payload is treated today.
- **Response limit**: stays at 16 MiB (`pushResponseLimit`), because a full receipt is still possible.

Everything after `ServerClient.push` receives an identical `RemoteChange` and doesn't change:

- the cursor check and reconciliation in `SyncEngine.push`;
- `numberDuplicateJournals`;
- `JournalStore.acknowledge` and `adoptAutomaticRename`;
- `server_versions`, `sent-change` and `cursor-change`.

That is deliberate: the critical acknowledgement and rebase logic isn't touched.

### 3.4 Why nothing can be lost, duplicated or overwritten

- **What the client stores is identical.** The server stores exactly the request's payload; the full receipt echoes
  that stored payload. A short receipt proves it with its digest, and the client substitutes the bytes it sent, which
  the digest matches. Every value the store derives (revision, `server_versions` digest, `LoggedChange` digest,
  `readOwnChange`'s cursor move) is computed from the same bytes as before.
- **Assurance is the same.** Against an honest server, the digest identifies the stored version exactly (SHA-256
  collision resistance). A dishonest server could already echo a payload it didn't store. The echo never proved
  storage, and neither does the digest.
- **A mismatch never acknowledges.** A wrong digest, record, kind or revision, or a disagreeing payload and digest,
  throws `invalidData` before the store is touched. The outbox row stays, local content stays, and the sync ends as
  Unexpected, as a corrupt full receipt does today.
- **Retries stay idempotent.** The operation ID and request hash are unchanged, so a lost response retried with the
  same `PendingChange` returns the original change's receipt; it never writes a second revision. Because the flag isn't
  hashed, toggling it between attempts can't turn a retry into `operation_reused`.
- **A retry after newer revisions** returns the original change (revision r). `acknowledge` already ignores a revision
  below the record's (`row.revision <= revision`), as today.
- **Lost changes on the server** (rollback, restore) are detected exactly as today. The cursor check in
  `SyncEngine.push`, `revision_ahead`, and `sync-continuity-digest` on reads all use fields the short receipt keeps; a
  test protects the cursor check (§7.2).
- **Conflicts are unchanged**: 409 bodies still carry the server's version in full.

### 3.5 Savings

The downlink of every accepted push shrinks from the record's size to about 300 bytes. Typical entries (300–1,500
words, encrypted and base64 encoded) are about 3–14 KB per push. A 50,000-word entry is about 400 KB per push. With
one push per writing pause, an hour of writing in a long entry (about 120 pauses) saves on the order of 50 MB of
downlink; a normal entry saves about 1 MB. The server also stops serializing the payload a second time. Uplink is
unchanged: each revision still sends the whole record. Delta or compressed uploads would change the record format
and are out of scope.

## 4. Waiting for changes

### 4.1 Long polling, not Server-Sent Events

| Concern | Long polling (chosen) | Server-Sent Events |
| --- | --- | --- |
| Proxy buffering (nginx `proxy_buffering`, response compression, corporate proxies) | Irrelevant: each response is tiny and complete | Events can sit in buffers until flushed; needs `X-Accel-Buffering: no` and no compression |
| Idle timeouts (nginx 60 s, AWS ALB 60 s, Cloudflare 100 s, typical HAProxy 30–50 s) | Each request ends within 25 s, below all of them | Needs heartbeats under the shortest timeout, which cost traffic comparable to a long-poll cycle |
| Half-open connections (Wi-Fi to cellular, NAT expiry) | The request's own timeout ends it within 40 s | Needs heartbeat-based detection on the client |
| Revocation | Every cycle re-authenticates; a waiting request is also woken and refused (§4.4) | A stream authenticated once must be found and closed by extra code |
| Reconnection and missed events | None needed: each request compares the database with the client's position (level-triggered) | Needs `Last-Event-ID` semantics or a resync on every reconnect |
| Tailscale Serve and Funnel, Caddy | Ordinary request and response; the existing reverse proxies need no settings | Works in Caddy and Serve, but behind other proxies depends on their settings |
| HTTP/2 | One stream for up to 25 s | One stream held indefinitely |
| Consistency with the server | Same request/response style as every endpoint; the MCP endpoint already chose no SSE | A second streaming style to maintain |

SSE would save a few hundred bytes per 25 s. Long polling is simpler, works through any proxy that passes ordinary
requests, and can't miss a change, because each wait compares the database itself. That robustness is worth more than
the bytes.

### 4.2 Wire

GET /v1/sync/wait, device-authenticated, capability `sync-wait`. Query parameters:

| Parameter | Required | Meaning |
| --- | --- | --- |
| `after` | yes, ≥ 0 | The cursor this device has read (`JournalStore.cursor()`). Bound as an optional number, so a missing value is `invalid_cursor` |
| `afterRecord`, `afterRevision` | optional, together | The change this device applied at `after`, exactly as on GET /v1/sync/ (`sync-continuity`) |
| `afterDigest` | optional, only with them | That change's payload digest (`sync-continuity-digest`) |
| `serverId` | optional | The identity this library last synchronized with (`syncedServerID()`); omitted when it has none |
| `timeout` | optional, whole seconds 1–25, default 25 | The longest the server holds the request; clamped, not refused. Keeps tests fast and lets a client choose shorter |

The client sends `afterRecord`, `afterRevision` and `afterDigest` under the same rules as its page requests (the
change it applied at a cursor above 0; the digest only to a server listing `sync-continuity-digest`). It uses the
`LoggedChange` that `JournalStore.syncPosition()` returns.

Invalid values return 400 `invalid_cursor`. The validation is GET /v1/sync/'s, except that `after` is required here
(GET defaults it to 0). As there, a value that isn't a number fails model binding and returns 400 without a `code`:

- `after` missing or negative;
- only one of `afterRecord` and `afterRevision`;
- `afterDigest` without them, or not 64 lower-case hexadecimal characters;
- a `serverId` longer than 64 characters.

The response is 200 with one of:

- `{"changed": true}`;
- `{"changed": false}`;
- `{"changed": false, "early": true}`.

Nothing else is sent: no cursor, no record IDs, no content.

- **A confirming `false`** (`changed: false` without `early`): the server MUST hold it until the clamped timeout and
  check once more at that deadline. It means exactly what an empty GET /v1/sync/ page from the same position would
  mean at that moment: no change after `after`, the change at `after` is the one named, and the identity is the one
  named.
- **An early `false`** (`early: true`): a newer wait from the same device replaced this one, or the server is
  stopping. It proves nothing about the position.
- **Clients** treat a `false` as confirming only when it has no `early` member and arrives no sooner than the
  requested timeout minus 2 s after the request was sent. A caching proxy could replay an old body at once.
- `true` means something differs: run an ordinary sync. A `true` that turns out to be wrong is harmless.
- Clients send `serverId` whenever they have one, and run one wait at a time per device credential. Two waits with one
  credential would answer each other `false` early (latest wins), which the client counts toward its fallback (§4.6).

Errors: 401 `unauthorized` (missing, unknown or revoked credential, also while waiting), 429 `rate_limited` (§4.5),
400 `invalid_cursor`. A server without the endpoint answers 404 or 405, but the client never calls one that doesn't
list the capability. Clients never follow redirects on this endpoint, as on every other.

### 4.3 Server behavior

**The signal.** A singleton `SyncSignal` holds a `TaskCompletionSource` that is replaced and completed on every
`Notify()`. It is created with `RunContinuationsAsynchronously`, so a writer never runs waiters' code.

**The waiter registry** is also in `SyncSignal`, under one lock. It maps each device to its current registration:

- Each registration is a unique token with its own "superseded" signal.
- `Register(device)` replaces the device's current registration, if any: its superseded signal fires, and the new
  token takes its place.
- `Release(token)` removes the entry only if the device's entry is still that token. A superseded registration's
  release changes nothing, so an older wait's `finally` can't remove the newer one.

So there is at most one held wait per enrolled, unrevoked device. There is no server-wide cap: every wait needs a
device credential, and a single-person server has a handful of devices.

**The handler** (`SyncEndpoints.Wait`, mapped outside the `/v1/sync` group so it gets its own rate-limit policy). It
never takes the WriteGate:

```
validate parameters                                         -> 400 invalid_cursor
token = Register(device)
try:
  using deadline = new CancellationTokenSource(clamp(timeout, 1, 25) s, TimeProvider)
  loop:
    signal = SyncSignal.Current          (taken BEFORE reading the database: no lost wake-up)
    if the credential is no longer valid (IsStillAuthorized's check)    -> 401
    vault = the vault row's SyncId
    if the vault row is missing (not expected: setup creates it with the first device) -> {changed: true}
    if serverId given and not equal to vault.SyncId, ignoring case     -> {changed: true}
        (the same comparison as Write: StringComparison.OrdinalIgnoreCase)
    if after > 0 and afterRecord/afterRevision given:
        same lookup as ReadPage: the change at `after` with that record and revision,
        and, with afterDigest, Digest(payload) == afterDigest
        missing or different                                            -> {changed: true}
    if any change has Cursor > after                                    -> {changed: true}
    if the deadline has passed                                          -> {changed: false}
    if superseded or application stopping                               -> {changed: false, early: true}
    await signal.WaitAsync(token linked from: deadline, superseded, request aborted, application stopping)
        signal, or the deadline                                         -> loop again (the checks run once more)
        superseded or application stopping                              -> loop again, which answers early
        request aborted                                                 -> end without a body
finally: Release(token)
```

The continuity lookup runs on every check, not only at entry. A change at a cursor never changes within one
identity, but turning on encryption deletes every change without a restart. It is one indexed row read.

Every read in the loop is a fresh query (`AsNoTracking`), so nothing cached in the request's `JournalDb` hides a change
of identity, credential or log.

**When the server answers.** `true` exactly when the ordinary sync would find something: a change after `after`, a
continuity mismatch (which the sync turns into reconciliation through 409 `server_changed`), or another identity. Otherwise the wait holds, and ends with `false`.

That includes a client whose cursor is past the end of the log but which sends no continuity fields. The sync's page
there would be empty, with the cursor unchanged, so answering `true` would make the client sync and wait forever
without progress. With continuity fields, the continuity check catches that case as a lost change, as the page
request does.

**Level-triggered.** Each check reads the database. A signal sent before the waiter subscribed, a missed signal, or a
code path that forgets to call `Notify()` costs at most one timeout (25 s), never a lost change.

**Who calls `Notify()`.** Always immediately after the commit (or `SaveChangesAsync`) returns, with no awaited call
that takes the request's cancellation token in between, so an aborted request can't skip it:

| Path | Code |
| --- | --- |
| A new change | `SyncEndpoints.Write` |
| Device revocation | `AccountEndpoints.Revoke`, and the pairing cancel path, which revokes a device that may have collected its grant |
| POST /recovery/encrypt (new identity, other devices revoked) | `EncryptionEndpoints`, right after the transaction commits and before `EncryptionPurge.Finish`, which can be slow |

Each call site gets a short comment saying why it must stay right after the commit.

Restores (`--restore`) and data-directory replacements need a restart, which ends every wait (below).

These don't notify:

- `PairingEndpoints.RemoveExpired` revokes only devices whose grant was never collected, which have no credential to
  wait with. It runs at startup and also at runtime (when a pairing starts), and needs no notification in either case.
- Agent-copy uploads, pairing and agent requests don't touch the change log.

**Cost.** A waiter answers `true` on its first wake after a new change, so a burst of writes costs each waiter one
check per wait cycle, not one per write. A check is up to four indexed single-row reads: the device by primary key,
the vault row, the change at `after`, and the first change after `after`. The `JournalDb` scope lives for the
request, but EF opens a pooled SQLite connection only per query, so a waiting request holds no database connection.

Awaiting the signal with one linked cancellation token (`WaitAsync`) keeps a write burst from piling continuations
onto long-lived tasks.

**Shutdown.** On `ApplicationStopping` every waiter answers `{changed: false, early: true}` at once, and so does a
wait that arrives after stopping began. Container stops (10 s grace)
and the Mac app's local server then never wait on held requests, and a restart doesn't send every client to an
ordinary sync during the restart. The client's next wait reaches the restarted server, or fails and leads to an
ordinary sync (§4.6).

**Logging.** The endpoint logs nothing per request (Microsoft.AspNetCore stays at Warning).

### 4.4 Authentication, revocation and identity changes

- The endpoint requires authorization, so a missing, unknown or revoked credential gets 401 before anything waits, as
  for every device endpoint.
- **Revocation while waiting**: the revoking request calls `Notify()` after it commits; every waiter re-checks its
  credential and the revoked device's wait answers 401 within milliseconds. The device's next request is refused at
  authentication. A revoked device learns nothing beyond the 401.
- **Encryption turned on elsewhere**: the same transaction revokes the other devices and replaces the identity; they get
  401, and the requesting device gets `changed: true` (its `serverId` differs). Their next sync classifies the state as
  today (Needs you, or Server changed).
- **Restore, reset, replaced data, server upgrade or downgrade**: all need a restart. The connection ends (or a proxy
  answers 502/503), the client's wait fails, and an ordinary sync reads `/status` and classifies the state.
- **Information exposed**: one boolean to a device that can already read the whole log. The server learns that the
  device is in the foreground, which it already learns from 3-second polling today.

### 4.5 Resource limits and fairness

- **One wait per device, latest wins.** A new wait from a device answers that device's older wait with `false` and
  takes its place, through the registry's tokens (§4.3). A client's next wait can therefore overlap one the server
  hasn't yet noticed was cancelled, for example because a proxy didn't pass the cancellation on, without a refusal. Two processes sharing a credential (a copied or stolen one) would answer each other's waits. Each is still
  held to one wait per 3 s by its own client (§4.6), and the server's rate limit below bounds a hostile one.
- **Rate limit.** A new `SyncWait` policy. The rate limiter runs before authorization (Program.cs), so it partitions
  like the `Sync` policy:
  - authenticated requests: per device, a fixed window of 60 a minute (a well-behaved client makes at most 20);
  - anonymous ones, and ones with an invalid credential: per client address, 60 a minute.

  Beyond either: 429 `rate_limited` with Retry-After.
- **Sync requests aren't affected**: the endpoint isn't in the `Sync` policy, so a wait never uses one of the 8
  concurrent sync slots a device has.
- **Fairness**: `Notify()` wakes every waiter at once; each answers independently, and none is queued behind another.
  Writers aren't slowed: notifying is one atomic swap, and waiters continue on the thread pool.
- **Bounded load**: the loop leaves at least 3 s between any two requests it starts, waits and syncs together (§4.6).
  A faulty or hostile server, or a busy writer on another device, can't make a device's automatic requests more
  frequent than one every 3 s. That is today's rate for the active app. A Mac whose window is behind other apps
  polls every 30 s today; while another device writes, it now syncs up to every 3 s, so it follows changes promptly
  (owner-review answer). Answers that don't lead to progress also count toward the fallback.
- **Kestrel**: a waiting request holds one HTTP/1.1 connection or one HTTP/2 stream and a few KB of memory. Kestrel's
  defaults (no connection limit, 130 s keep-alive, 100 streams per HTTP/2 connection) need no changes.
  `MinResponseDataRate` only applies while a body is being written.

### 4.6 Client behavior

#### Where the decisions live

**`ChangeWatcher`** (JournalCore) is a pure state machine with no I/O, driven by an injected `ContinuousClock`
instant:

- `handle(_ event:, at:) -> [Action]`;
- its state is a value the app keeps in `SyncTiming`, so it survives a restart of the loop on returning to the
  foreground and is reset when the library's connection changes.

**The app** only translates events into calls and carries out the returned actions. It never decides. Tests drive the
state machine directly; JournalProbe drives it with real requests.

| Events (in) | Actions (out) |
| --- | --- |
| `syncFinished(outcome, progress, earliestRetry, quiet)` | `startWait(id, timeout)`, which always cancels any wait still in flight first |
| `waitAnswered(id, answer, sentAt)`: answer is `changed`, `unchanged` or `failed` | `cancelWait` |
| `stateChanged(canWait)`: the app's conditions 4 and 5 below, and the capability | `syncNow` |
| `quietBroken` (the store is no longer quiet, seen on a tick or a check), `networkPathChanged`, `sleep`, `wake`, `becameActive`, `tick` | `syncAt(instant)` |
| | `markSynced(sentAt)` (Last Synced), `publishAgentCopies` |

`syncFinished`'s arguments:

- `outcome`: `settled`, `unsettled`, `failed`, or `declined` (`AppModel.sync()` didn't run: locked, replacing the
  library, save failure);
- `progress`: as defined under Fallback below;
- `earliestRetry`: a delay, or none;
- `quiet`: the store's quiet mark when this sync ended, below.

Every timer (minimum spacing, safety sync, retry times, fallback period) is a `ContinuousClock` instant inside the
state, so a change to the wall clock can't shorten or stretch it. `SyncEngine`'s retry times use `Date`; the engine
reports the earliest one as a delay from now, which the watcher turns into an instant.

**The store's quiet mark.** `JournalStore` keeps two in-memory values next to its synchronization gate
(`beginSynchronization`/`endSynchronization`), which is per store, whichever engine holds it:

- **`syncGeneration`** advances whenever a synchronization gets the gate (including when the gate is handed to a
  waiting one) and when one releases it.
- **`writes`** is advanced by a GRDB `TransactionObserver` after every commit that touched the `records`, `outbox`,
  `attachments` or `conflicts` tables, whatever code made the write. No call site can bypass it, including:
  - re-encryption's direct outbox inserts;
  - merges that only set `dirty`;
  - review resolution and deletion;
  - an image added without a record change;
  - an edit to a record whose outbox row already exists (`INSERT OR IGNORE`).

  The observer's callbacks run on the `DatabaseQueue`'s dispatch queue, not on the store actor. So:
  - `writes` is a lock-protected counter (`OSAllocatedUnfairLock`), read by the actor and never part of actor state;
  - the observer is registered for the database's lifetime (`extent: .databaseLifetime`);
  - it notes a relevant change in `databaseDidChange` and advances the counter only in `databaseDidCommit`;
  - `databaseDidRollback` clears the note.

**The settled facts and the mark are read in one actor step.** As the engine's last action before it releases the
gate, it calls `store.settledFacts()`. That call returns, together:

- the `writes` value;
- the outbox operation IDs;
- the images still to upload or verify;
- whether reconciliation is pending.

The engine classifies those IDs against its own `rejectedChanges` and `retries` to decide `settled`. Any write after
that step, including a rename, move, delete, review resolution or image add that arrives while the sync still holds
the gate, moves `writes` past the snapshot. So it breaks quiet instead of being folded into the mark.

`endSynchronization` then advances `syncGeneration` for the release, and records the **quiet mark**: that generation
and the `writes` value from `settledFacts()`. It does this before the gate is handed to a waiting sync, whose
acquisition advances the generation again and so breaks quiet. The engine's report carries the mark.

One store call, `quietPosition(since mark:)`, answers atomically on the store actor. When both values still equal the
mark, it returns the position (cursor and the change applied there) and `syncedServerID()`. Otherwise it returns nil.
Nil means another sync ran (any engine: `sendWriting` while locked, EncryptionOperations, ServerJoining) or something
was written locally since the settled sync.

#### When the watcher waits

A wait starts only when all of these hold. Otherwise the loop runs exactly as today, with `nextSyncDelay`:

1. The server listed `sync-wait` in the status of the last sync.
2. **Settled.** The last sync succeeded, and:
   - no queued record is ready to send or being written;
   - no image is waiting to upload or verify, and none is waiting to download, except ones waiting for a retry time;
   - no reconciliation is pending.

   Records and images the server refused don't count, since they wait for an edit or Sync Now.

   Records and images only **waiting for a retry time** (SyncEngine's `retries`, 15 s to 10 minutes) don't block
   waiting either. The report gives the earliest such delay, counting only entries still in the future and only for
   items still queued or missing. The watcher schedules an ordinary sync then (`syncAt`), which ends the wait. An image
   that stays unavailable therefore doesn't keep a device polling every 3 s. Leftover entries (an operation that a
   conflict or reconciliation removed, an image no longer missing) schedule nothing.

   How each queued state is classified:

   | State | Classified as | Why |
   | --- | --- | --- |
   | Lost images (`lostImages`) | Settled | Never sent, and nothing waits for them |
   | Records held back by a refused image | Refused | They wait for the image's next chance (a start or Sync Now) |
   | Records held back by an image waiting for a retry | Waiting for a retry time | Scheduled |
   | An outbox row `takeForSending` returns nil for | Settled | Nothing to send |
3. **Quiet.** `quietPosition(since:)` with that sync's mark returns a position. This is level-based:
   - it is checked before every wait starts, before any answer is used, and on the loop's 1-second tick, where a
     failed check cancels a wait in flight (`quietBroken`).

   Typing that starts during a wait therefore returns the loop to its 3-second syncs with `waitingForWritingPause`,
   which send continuous writing at least every 30 s (`longestWritingWait`), as today.
4. Not locked, no save failure, not replacing the library, and automatic sync isn't stopped. `automaticSyncStopped`
   covers the Needs you, Server changed, No access and Update needed states. In the Temporary and Unexpected states the
   existing backoff runs instead. There is no waiting while sync is stopped or retrying.
5. Waiting isn't turned off by the fallback (below).

When a condition stops holding, the wait in flight is cancelled at once. App Lock on the Mac, for example, locks
without cancelling the loop.

**What re-arms the watcher.** A wait starts only from a settled verdict whose mark is still quiet. Once the store is
no longer quiet, the verdict is dropped. That happens after a sync through any engine, or a local write. The loop then
runs with `nextSyncDelay` until one of its own syncs is settled again, and that sync's mark re-arms the watcher. There
is no other path back to waiting.

Nothing the app does after a successful idle sync may write to the observed tables. Otherwise no device would ever
wait. §7.2 item 10 and §7.4 check that an idle app reaches waiting after one sync.

#### A wait

The app reads the position and identity with `quietPosition(since:)`, in one atomic store call. It happens outside
the sync gate, so a wait never blocks Sync Now, writing or quitting. The app then calls
`ServerClient.waitForChange(after:applied:serverID:timeout: 25)` in a child task tagged with the wait's ID.

- **Its own `URLSession`**, configured like the existing ones (`ServerClient.init`): ephemeral, `urlCache = nil` and
  the `NoRedirects` delegate. Only the timeouts differ: 40 s per request and 45 s per resource. A 3xx is `failed`,
  and the bearer token is never sent anywhere else. The 20-second idle timeout of ordinary requests is unchanged.
- **Its own response handling**, not `ServerClient.request`'s mapping. A wait's 401 doesn't go through `refusal`, a 429
  isn't a `ServerRateLimited` (so it never sets `syncTiming.retryAfter`), and a 404 or 405 isn't
  `serverUpdateNeeded`.
- **The body** is read with a 1 KB limit and must be a JSON object whose `changed` member is a boolean; `early`, if
  present, must be a boolean too. Other members are ignored, as clients ignore unknown response fields (protocol/README.md, Versioning). Anything else is `failed`.
- **The result** is `changed`, `unchanged` or `failed`; it never throws a health-classified error.

**An answer is used only if it is current.** All of these must hold:

- its ID is the watcher's current wait;
- `quietPosition(since:)` still returns a position for the same mark, so no sync ran meanwhile and nothing was written;
- the app's store is the same object the wait read from.

Anything else is discarded. It doesn't run a sync by itself, doesn't update Last Synced, and isn't a strike.

- If the store is no longer quiet, the re-arm rule above applies.
- If only the ID is old (a cancelled wait's late result), nothing else happens; the current wait, or the sync that
  cancelled it, continues.

**The watcher never records a sync health state.** Only ordinary syncs do, through `AppModel.sync`, exactly as today.

#### Answers

- **`unchanged`, confirming.** It is confirming when it has no `early` member and arrives at least the requested
  timeout minus 2 s after the wait was sent (§4.2). The device was settled, and nothing changed locally, so the server confirmed there was nothing to
  exchange.
  - `markSynced(sentAt)` updates Last Synced with the time the wait was sent, since every check the server made was at
    or after that time. A wait answer is applied only when it is later than the date shown. Ordinary syncs keep
    today's `synced()`, so Sync Now's check (`lastSynced != before`) is unaffected by clock steps.
  - Refused items don't prevent this, just as today's `sync()` calls `synced()` when a refused entry or image stays
    behind. Any edit to one is a write, so the store is no longer quiet, the answer is discarded, and the loop's next
    sync sends it.
  - `publishAgentCopies` calls `requestPublishing()`. It costs nothing when nothing changed: `publishAll` returns early
    unless the fingerprint changed or the agents list is older than `listLifetime`. An agent copy that failed is then
    retried as often as today.
  - The watcher waits again.
- **`unchanged`, not confirming** (`early: true`, or too soon: shutdown, a duplicate waiter on the same credential, a
  caching proxy, a hostile server):
  - not marked as synced;
  - counts as one strike toward the fallback;
  - the watcher waits again.
- **`changed`**: `syncNow`.
- **`failed`**: `syncNow`. The ordinary sync classifies any real problem into the existing health states and backoff.
  It also forgets the reused status, so a downgraded server is noticed at once.

**Every wait ends with an event.** The app reports `waitEnded(id, result)` for every wait task, whatever ended it:

- An answer is handled as above.
- A cancellation the watcher asked for (`cancelWait`, or `startWait` replacing it) needs nothing more.
- Any other cancellation becomes `syncNow`, without a strike. One example is `ServerClient.deinit` cancelling its
  session's tasks when `configureSync` replaces the client.

The watcher also keeps its own deadline for each wait in flight: the 45 s resource timeout plus 5 s. If no event has
arrived by then, it treats the wait as `failed`. A wait can't leave the watcher stuck.

A sync the watcher asks for but `AppModel.sync()` declines (`declined`) counts neither as a sync failure (the loop's
`failures`) nor toward the fallback.

#### Pace

- The loop leaves at least 3 s between any two requests it starts, waits and syncs together, measured from the start
  of the previous one. This is a floor: `nextSyncDelay`'s longer pauses still apply where they do today.
- Syncs the person or writing starts (Sync Now, Try Again, a writing pause, leaving an entry, locking) aren't delayed
  by this, as today. They advance `syncGeneration`, which cancels the wait.
- The watcher starts again only after a sync that leaves the conditions above true, with the new position. A device's
  own push therefore never wakes its own wait.

**Safety sync.** While waiting, the loop also runs an ordinary sync once 10 minutes have passed since the last one.
After that instant, no new wait starts. The sync runs when the current wait ends, or at its watcher deadline,
whichever comes first, so it never depends on the wait ending and rarely costs a reconnect. It covers anything outside
the change log (status) and bounds the effect of an unknown fault.

#### Fallback to polling

Strikes:

- a `failed` answer whose follow-up sync succeeds. If that sync fails too, the network or server is the problem, and
  today's backoff handles it. A network flap that fails a wait before `NWPathMonitor` reports the change is therefore
  not a strike;
- a non-confirming `unchanged`;
- a `changed` whose follow-up sync made **no progress**. Progress means that, after the follow-up sync succeeded, the
  store's cursor, the change applied there (`cursor-change`) or the synced identity differs from what the wait sent.
  A `true` from another identity is therefore never a strike once the sync adopts the new identity, and leads to a
  stopped state otherwise, where nothing waits.

A follow-up sync that fails counts in today's backoff instead.

After 3 strikes in a row, waiting is off for 1 hour, and the loop polls with `nextSyncDelay`: 3 s while active, 30 s
on the Mac while another app is active. Two cases this covers:

- a proxy that cuts held requests;
- a server that keeps answering `true` without anything to read.

An on-time `unchanged`, or a `changed` whose sync made progress, resets the count.

These cancel the wait and lead to an ordinary sync, but are never strikes:

- a network path change (`NWPathMonitor` reports any change, not just a return);
- the Mac going to sleep (the wait is cancelled) and waking (the ordinary sync runs);
- the app becoming active.

Discarded answers aren't strikes either; they follow the re-arm rule.

#### Platforms

- **iOS and iPadOS**: waits run only while the scene isn't in the background. Leaving it cancels the loop's task
  (`.task(id: scenePhase == .background)`), and with it the wait; it also locks the journals when App Lock is on.
  Returning restarts the loop, which syncs at once and then waits. No background sessions, background modes or push
  notifications. Holding an idle request lets the cellular radio drop to low power between answers, unlike a request
  every 3 s. **Low Data Mode** keeps waiting: a wait every 25 s uses far less data than polling every 3 s (§6), so it
  is the lower-data choice (see the review record).
- **macOS**: waits also run while another app is active, replacing today's 30-second inactive polling (owner-review
  answer). A Mac window behind others then usually gets changes within seconds, though App Nap may stretch the
  3-second floor while My Journal is in the background. If waiting falls back, the inactive Mac polls every 30 s as
  today.
- **One wait per credential.** Each device's app runs one loop: the Mac has one journal window, and iOS doesn't
  enable multiple scenes. JournalProbe and test lanes create their own device credentials. A credential shared by two
  waiters only degrades to polling, through early answers.

#### Agent copies and diagnostics

**Agent-copy publishing** follows every successful ordinary sync, as today, and every on-time `unchanged`. It publishes
only when its fingerprint changed. The agents list is re-read whenever publishing runs and `listLifetime` (10 minutes)
has passed. The comment beside it that says "every minute" is corrected. An agent approved or changed on another
device is published by that device, as today. Agent requests waiting for approval aren't part of the change log;
Settings > Agents keeps refreshing them while it's shown.

**Diagnostics.** A rejected receipt is logged, without content, digests or IDs:

- the receipt form (full or short);
- which check failed (record, kind, revision, payload, digest, or shape).

A fault that keeps recurring can then be told apart: a client bug or a server bug.

### 4.7 Reverse proxies and networks

- **Tailscale Serve** (deploy/tailscale-serve.json) **and Funnel**: plain HTTP reverse proxying from tailscaled. No
  response timeout below 25 s is known, but none is documented either: this is **assumed, not verified**, especially
  for Funnel's relay. It's verified in §7.3 with Serve in a disposable tailnet only if one is available. Otherwise
  it's an owner check on their next deployment, not on the owner's server now. If the assumption is wrong, waits fail
  and the client falls back to polling, as behind any short-timeout proxy.
- **Caddy** (deploy/Caddyfile): `reverse_proxy` has no response timeout by default and flushes complete responses. It's
  verified through the pinned Caddy image with HTTP/2 (§7.3).
- **Other proxies**: anything with a response or idle timeout of 30 s or more works. Behind a shorter one, waits fail
  and the client falls back to polling (§4.6). docs/self-hosting gets one sentence: the server holds sync requests for
  up to 25 seconds; set proxy timeouts to at least 30 seconds.
- **HTTP/2**: the wait session multiplexes on one connection per session; ordinary requests use their own session's
  connection. Under HTTP/1.1 a wait holds one of URLSession's few connections per host (4 on iOS, 6 on macOS), which ordinary requests don't
  share.
- **Mobile NAT and carrier idle limits** are above 25 s in practice. A shorter one looks like a failing proxy and falls
  back.

## 5. Failure handling

| Situation | Server | Client |
| --- | --- | --- |
| Short receipt with a wrong digest, record, kind or revision, or `payload` and `payloadDigest` that disagree | (a fault) | `invalidData`; nothing acknowledged; outbox kept; Unexpected. For an automatic rename the error is swallowed, as any rename failure is today (`numberDuplicateJournals`), and the rename is worked out again next sync |
| Push response lost after commit | Change stored once | Same `PendingChange` retried; original receipt; one revision |
| Short-receipt push accepted at a cursor at or below one already seen | (lost changes) | Reconciliation, as today |
| Server stops listing a capability (downgrade) | Ignores the flag; no endpoint | Full receipts accepted; the wait fails, the sync re-reads status and waiting stops |
| Wait cut by a proxy (502/504) or connection reset | Slot released on abort | Ordinary sync; after 3 in a row, polling for an hour |
| Half-open connection | Slot released when Kestrel notices, superseded by the next wait, or at the timeout | Request timeout (40 s); ordinary sync |
| Server restart | Waiters answered `{changed: false, early: true}` on shutdown | The next wait reaches the new server, or fails and leads to an ordinary sync |
| Restore or reset (restart) | As restart | The ordinary sync classifies it, as today |
| Server rolled back below the device's position | Continuity check: `true` | Sync gets 409 `server_changed`; reconciliation, as today |
| Cursor past the log end without continuity fields | Held; `false` | Same result as today's empty page |
| Device revoked while waiting | 401 on the next wake | Ordinary sync; No access, as today |
| Encryption turned on elsewhere | 401 to others; `true` to the requester | Ordinary sync; Needs you, as today |
| Server answers `true` or `false` instantly, forever | (faulty or hostile) | At most one request per 3 s; `true` without progress falls back after 3 |
| Second wait from the same device | Older one answered `{changed: false, early: true}` | No refusal; one wait per 3 s anyway |
| `Notify()` missing on some path | Level check at the next wait | Change seen within 25 s, or by the safety sync |
| The wait rate limit | 429 | `failed`, never `retryAfter`; ordinary sync; counts toward the fallback |
| Network change, Mac sleep or wake, app becoming active | — | Wait restarted after an ordinary sync; not counted |
| Locked, background, stopped state, save failure | — | No wait; a wait in flight is cancelled at once; loop as today |
| An answer arrives after a sync (any engine) or a local write, or after the wait was cancelled | — | Not current (old wait ID, or the store no longer quiet): discarded; no Last Synced, no strike; the loop polls until a sync settles again |
| A device revoked from outside the process reaches its deadline | Final check: 401 | Ordinary sync; No access, as today |
| An image or record waiting for a retry time | — | Waiting continues; an ordinary sync runs at the retry time (future times of items still queued or missing only) |
| Typing starts during a wait | — | Wait cancelled; the loop's 3 s syncs send the writing at least every 30 s, as today |
| A refused entry or image stays behind | — | Waiting continues; on-time `false` answers keep Last Synced current, as today's syncs do |
| Non-confirming `false` answers (`early: true` or too soon: shutdown, a shared credential, a caching proxy, a hostile server) | — | Last Synced not updated; each is a strike toward the fallback |
| An edit to a refused entry, or any non-editor change (rename, move, review resolution, merge, re-encryption), during a wait | — | A write to an observed table: the store isn't quiet, the wait is cancelled, an ordinary sync sends it |

## 6. Expected traffic

These are estimates from the code paths; §7.4 measures them. A request and its response here, idle and over TLS with
HTTP/2 header compression and TCP acknowledgements, is about 0.6–1.5 KB.

| Foreground, nothing changing | Today | With waiting |
| --- | --- | --- |
| Requests per minute, active app | 20 empty pages, about 1 status, an agents list every 10 min: **about 21** | 2.4 waits, plus a safety sync every 10 min (about 3 requests): **about 2.7** |
| Bytes per hour, active app | about 0.8–2 MB | about 0.1–0.25 MB (**about 85–90 % less**) |
| Radio wake-ups per minute (iOS) | about 20 | about 2.4 |
| Mac, another app active | about 3 requests/min; changes arrive within 30 s | about 2.7 requests/min; changes usually arrive within seconds (App Nap can stretch the 3 s floor) |
| Delay before a change from another device shows | 0–3 s | Under 1 s, plus that sync's own time (3 s at most when a previous request started within 3 s) |
| Worst case against a faulty server | — | One request per 3 s (today's rate) until the fallback |

Writing: each accepted push's downlink drops from the record's size to about 300 bytes (§3.5).

## 7. Test plan

Only tests that protect a behavior or a plausible failure (AGENTS.md). Servers use real isolated SQLite databases.

### 7.1 Server (xUnit, `JournalFactory`)

Short receipt:

1. An accepted write with `shortReceipt` returns every receipt field except `payload`, and a `payloadDigest` equal to
   the `Digest` of the stored payload.
2. Retries return the short or full form as each retry asks, with one change in the log, and no `operation_reused`
   whichever form the first request asked for.
3. A legacy `ResponseJson` operation retried with the flag returns its full receipt.
4. 409 `revision_conflict` with the flag still carries `current` with the full payload.

Waiting:

5. Answers `true` at once in each of these cases:
   - a change exists after `after`;
   - the change at `after` has another record, revision or digest;
   - `after` is past the log end and continuity fields are given;
   - `serverId` differs.

   `serverId` differing only in letter case doesn't answer `true`. `after` past the end without continuity fields is
   held and ends `false`.
6. No lost wake-up, without a test-only path in production code:
   - a unit test of `SyncSignal`: a task taken from `Current` before `Notify()` completes, and one taken after doesn't;
   - through the endpoint: a held wait answers `true` within 1 s when another device's write commits.

   Together with the handler taking the signal before it reads (red team item), these cover the race.
7. `false` after `timeout=1` with no change. A device revoked directly in the database (no `Notify()`) gets 401 at
   the deadline, not `false`.
8. A revoked credential gets 401 before waiting. A waiting device revoked by another gets 401 within 1 s, through each
   revocation path that can affect a device with a credential: Revoke, and a cancelled pairing whose grant was
   collected.
9. Turning on encryption: the requester's wait answers `true`, the others 401. This runs both with and without
   continuity fields, so the identity comparison alone is shown to catch it (fresh reads, not a cached vault).
10. Limits:
    - a second wait from the same device answers the first `false`;
    - the per-device and per-address rate limits answer 429;
    - a cancelled wait frees its slot;
    - the registry is empty after supersede, cancel, timeout and shutdown in any order, and an older wait's release
      never removes the newer registration.
11. Stopping the host with waiters outstanding completes in under 2 s, and they answer `{changed: false, early:
    true}`. So does a wait that arrives after stopping began. A confirming `false` is never answered before the
    clamped timeout.
12. Invalid parameters give 400, with the same validation as GET /v1/sync/.

### 7.2 JournalCore (Swift, fake `SyncServer` and the real store)

1. Acknowledging a short receipt leaves the store byte-for-byte as acknowledging the equivalent full receipt does:
   records, outbox, `server_versions`, `sent-change`, `cursor`, `cursor-change`.
2. Each bad receipt throws `invalidData` and leaves the outbox and record unchanged; the next sync with a correct
   receipt acknowledges:
   - a short receipt with a wrong digest, record, kind or revision;
   - a receipt with both `payload` and `payloadDigest` that disagree;
   - a receipt with neither.
3. A short receipt accepted at a cursor at or below one already seen still starts reconciliation (the cursor check in
   `SyncEngine.push`).
4. The flag is sent only when the capability is listed, for records and automatic renames. A full receipt answering it
   is accepted.
5. Automatic renames are acknowledged from a short receipt.
6. `waitForChange` response handling:
   - a 401, 429, 404, oversized or malformed body becomes `failed`;
   - a 3xx becomes `failed`, and the redirect isn't followed;
   - it never becomes `JournalError.unauthorized`, `ServerRateLimited` or `SyncFailure`.
7. `ChangeWatcher` decisions, driven as a state machine with a test clock (events in, actions out):
   - it waits only when settled, unchanged locally and healthy; none while locked, stopped, a sync is running, or
     images are waiting that aren't waiting for a retry;
   - records or images waiting only for a retry time don't block waiting, and `syncAt` follows the earliest one;
     leftover retry entries (an operation removed by a conflict, an image no longer missing, a past time) schedule
     nothing;
   - `quietBroken` cancels a held wait, and continuous typing is then sent within 30 s;
   - a wait task cancelled from outside (the client replaced) leads to a sync without a strike; a wait with no event
     by its watcher deadline is treated as `failed`;
   - the safety sync runs at the latest at the watcher deadline of the wait in flight;
   - a `failed` wait whose follow-up sync also fails isn't a strike;
   - a `false` with `early: true`, or one arriving too soon, isn't confirming;
   - `declined` syncs count neither as failures nor as strikes;
   - an answer with an old ID is discarded: no sync, no Last Synced, no strike;
   - an on-time `unchanged` marks Last Synced with the wait's start time, never earlier than the date shown; an early
     one doesn't, and is a strike;
   - at least 3 s between any two loop requests against a server that answers `true` or `false` instantly;
   - a `true` whose follow-up sync left the cursor, `cursor-change` and identity as the wait sent them is a strike, and
     one whose sync moved any of them isn't;
   - after 3 strikes it polls with `nextSyncDelay` (3 s active, 30 s inactive Mac) and waits again after an hour; the
     state survives a loop restart and resets on a connection change;
   - the safety sync every 10 minutes, at the end of a wait;
   - path changes, sleep and wake, and becoming active aren't strikes;
   - a sync through another engine on the same store during a wait discards the answer, and waiting resumes only
     after the loop's next settled sync;
   - `startWait` cancels a wait still in flight;
   - a `failed` answer forgets the reused status.
8. The quiet mark, with the real store:
   - `quietPosition(since:)` returns nil after a sync through another `SyncEngine` on the same store (as ServerJoining
     and EncryptionOperations run), including one handed the gate by a waiting sync;
   - it returns nil after each of these local writes:
     - an editor save;
     - an edit to a record whose outbox row already exists;
     - a journal rename, move and delete (`commitMutation`);
     - resolving a review;
     - a merge that only sets `dirty`;
     - re-encryption's direct outbox inserts;
     - deleting an entry;
     - adding an image without a record change;
   - a `commitMutation` write (a rename) committed after `settledFacts()` but before the gate is released breaks
     quiet;
   - a sync handed the gate by `endSynchronization` breaks quiet;
   - a rolled-back transaction doesn't advance `writes`.
9. End to end with a fake server holding a wait, and a refused entry present:
   - editing that entry during the wait is sent;
   - renaming a journal during the wait is sent;
   - in both cases, Last Synced isn't updated before the change is sent.
10. An idle app, with the real `AppModel.sync()` path, reaches waiting after one sync. Nothing it does after a
    successful sync (list refresh, pending count, agent publishing, removing superseded libraries) writes to the
    observed tables.

### 7.3 Real servers (JournalProbe and scripts, disposable loopback servers)

1. **Two devices**: A waits, B pushes; A's wait returns, A syncs and has B's change within 1 s. Then B revokes A: A's
   wait gets 401 and A's sync reports No access.
2. **Mixed versions.** Before implementation, copy the current server and JournalCore sources to the scratchpad and
   build them as the baseline. The repository isn't under version control, so a copy is the only baseline.
   - Baseline probe with the new server: full receipts, no waits, the existing probes (`test-sync.sh`,
     `test-sync-health.sh`) all pass.
   - New probe with the baseline server: no flag sent, no waits, polling; the same probes pass.
   - New with new: the same probes pass, with short receipts and waits.
3. **Restarts and identity**: kill the server during a wait; restart; the client resumes waiting without entering a
   health state when the restart is quick. `--restore` during a wait leads to Server changed. A rollback by copying the
   data directory is detected as today (RollbackProbe and RestoreProbe), with waits on, including through the wait's
   continuity check.
4. **Lost push responses**: a loopback fault proxy drops the response to a committed PUT. The retry gets the short
   receipt; the server log has exactly one change per operation; the client's store matches the server's.
5. **Fault proxy** (a small Python script on loopback, in scripts/):
   - one that answers 504 to held requests after 10 s: the client falls back to polling after 3;
   - one that stops forwarding without closing (half-open): the wait times out within 45 s and sync continues;
   - one that resets mid-wait;
   - one that buffers whole responses: waits survive it;
   - one that answers every wait `true` at once: at most one request per 3 s, then the fallback.
   - one that replays a cached `false` at once (a proxy ignoring `no-store`): Last Synced isn't updated by it, and the
     client falls back to polling.
6. **Through Caddy with HTTP/2**: reuse `scripts/test-https-deployment.py`'s disposable Caddy setup. Waits are held,
   woken and completed. A cancelled wait is either released on the server or replaced by the next one (latest wins).
   Tailscale Serve, if a disposable tailnet is available, gets the same check (§4.7). That includes whether it passes
   a client's cancellation on to Kestrel; if it doesn't, latest wins covers it.
7. **Many devices**: 20 device credentials waiting, one writer pushing 100 changes. Every device converges; server
   memory and CPU are sampled.

### 7.4 Bandwidth, measured again

A loopback counting proxy records requests and bytes in each direction:

- 10 idle minutes, run by JournalProbe with the real `ChangeWatcher` and loop timings: baseline client and server,
  then new.
- A writing session of 60 pushes of a 50,000-word entry and of a normal entry.

The results replace the estimates in §6 and are added to docs/performance.md. The Release app on the iOS simulator
confirms the request rate once: an idle minute shows waits instead of pages, and Last Synced keeps reading "Just now".
The owner's Mac and devices aren't used.

### 7.5 Red team brief

An independent agent attacks the implementation with the server and client sources. The goal is lost or duplicated
content, an overwritten edit, an acknowledged change that the server doesn't hold, a revoked device keeping access, a
request storm or a stuck client, or resource exhaustion. Suggested attacks:

- Forged or replayed short receipts: wrong digest, other record, revision + 2, kind change, digest of another
  revision, a short receipt to a request that didn't ask for one, `payload` and `payloadDigest` that disagree.
- Toggling `shortReceipt` across retries of one operation; the same operation from two devices.
- Lost wake-ups: a write committing between the check and the await; a signal storm during a long write burst; an
  aborted write request around `Notify()`.
- Waits as a denial of service:
  - many credentials, held connections, slow clients;
  - cancelling and re-issuing quickly;
  - two processes sharing a credential;
  - `timeout` values at the limits;
  - HTTP/2 stream floods;
  - anonymous floods against the address partition.
- Endless `true`: identity case, cursor past the end, continuity fields that never match.
- Local edits during a held wait: continuous typing, pasting, adding images, a save failure.
- Last Synced: with refused items, with early or replayed `false`, with a caching proxy that ignores `no-store`, and
  with the wall clock stepped back.
- Revocation races: revoking during a wait, during the following sync, and during encryption turn-on.
- Shutdown with waiters; restart loops; a downgraded server mid-session.
- A hostile server: instant `true` or `false`, slow drip, an endless body, 200 with garbage, 401 or 429 on waits only.
  The goal is a request storm, a stuck client, a wrong health state, or a Last Synced that claims a sync that didn't
  happen.
- Information exposure: anything in a wait response or log beyond one boolean.

## 8. Changes outside the code

- protocol/README.md:
  - capabilities `sync-short-receipt` and `sync-wait`;
  - the receipt form under Sync and conflicts;
  - GET /sync/wait, with its parameters, the confirming and early `false`, and the rule that a confirming `false` is
    held until the timeout;
  - its limits under Rate limits.
  No new error codes.
- protocol/fixtures: a short receipt and its digest for another client to check against.
- docs/self-hosting: the proxy-timeout sentence (§4.7).
- SECURITY.md: no change to what the server can see. The wait reveals foreground presence, as polling already does.
- docs/performance.md: the measurements in §7.4.

## 9. Decisions from review

- The longest wait is 25 s (round 1).
- The wait checks continuity on every check (round 1 asked for once at entry; round 2 noted encryption turn-on
  deletes the log without a restart, so it's repeated; one indexed row read).
- The Mac waits while another app is active, and falls back to 30-second polling.
- The safety sync runs every 10 minutes.
