# Review: sync protocol efficiency

Reviews of [sync-protocol-efficiency.md](sync-protocol-efficiency.md). Each round's reviewer was independent of the
author and received the requirements, the design and the code, not the author's defense.

## Round 1 (revision 1)

**Verdict: approved with required changes.** Short receipts are sound; long polling is mostly correct. No code yet.

| # | Required change | Resolution in revision 2 |
| --- | --- | --- |
| 1 | Last Synced would stop updating, because `syncActivity.synced()` runs only after a full sync | A wait answered `false` with nothing pending counts as a completed sync for Last Synced, dated when the wait was sent (§4.6). Stated as the only user-visible consideration (Summary) |
| 2 | Bounded load: one wait plus one sync every 3 s doubles today's rate. Endless `true` from a case-sensitive `serverId` comparison and from a cursor past the log end | `serverId` compared ignoring case, as Write does. The server answers `true` only when a sync would find something: a change after `after`, a continuity mismatch, another identity, or no vault. A `true` followed by a sync without progress counts toward the fallback. At least 3 s between any two requests the loop starts (§4.3, §4.5, §4.6) |
| 3 | Per-device limit: latest wins instead of 2 waits and a 429. A wait's 429 must not feed `retryAfter`. The rate limiter runs before authorization, so anonymous requests need an address partition | Latest wins: an older wait is answered `false`. `SyncWait` policy per device, and per address for anonymous requests. Waits have their own response handling; a 429 is `failed`, never `ServerRateLimited` (§4.5, §4.6) |
| 4 | Wait errors must stay out of sync health (401 through `refusal`, 404/405 to `serverUpdateNeeded`). Cancellations, network changes and Mac sleep or wake don't count toward the fallback. Read with a ~1 KB limit and accept only `{changed: bool}` | `waitForChange` returns `changed`, `unchanged` or `failed` and never throws a health-classified error. The watcher never records a health state. Network path changes, sleep and wake, and cancellations aren't counted. 1 KB limit; a boolean `changed` is required (§4.6) |
| 5 | Check continuity once at wait entry, as ReadPage does; answer `false` only when an empty page would have been returned | `afterRecord`, `afterRevision` and `afterDigest`, with ReadPage's validation and lookup, checked once at entry. `false` is defined as "an empty page from this position" (§4.2, §4.3) |
| 6 | Short-receipt decoding: verify both `payload` and `payloadDigest` when both are present; the server uses the existing `Digest` helper; `SyncServer.push` carries the capability; test that the cursor check still starts reconciliation | All adopted (§3.2, §3.3); test 7.2.3 |
| 7 | Fallback uses `nextSyncDelay` (30 s on an inactive Mac), not a flat 3 s. Client timers use `ContinuousClock`. The server deadline is a `CancellationTokenSource(timeout, TimeProvider)` | All adopted (§4.3, §4.6) |

**Optional notes:**

- **`Notify()` immediately after the commit**, so a request abort can't skip it, with the listed call sites; the wait
  never takes the WriteGate. Adopted (§4.3).
- **Answer `false` on shutdown.** Adopted, so a restart doesn't push every client into failure backoff (§4.3).
- **Low Data Mode: skip waits and poll.** Not adopted. A wait every 25 s uses roughly a tenth of the data of polling
  every 3 s (§6). Polling in Low Data Mode would raise data use in the mode meant to lower it. Left for round 2 to
  confirm or overrule.

**Open questions answered by the reviewer:**

1. The longest wait is 25 s.
2. Continuity is checked once, at entry.
3. The Mac waits while another app is active, and falls back to 30-second polling.
4. The safety sync runs every 10 minutes.

## Round 2 (revision 2)

**Verdict: approved with required changes.** The reviewer found no path that loses, duplicates or overwrites content.

Verified against the code:

- **Short receipts:** the client substitutes its own bytes after the digest check, and the flag is outside the
  request hash.
- **Long polling:** the signal is taken before the read, every check is level-triggered, and `Notify()` comes after
  the commit.
- **Rate limits:** authentication runs before the rate limiter, so the per-device partitions work.
- **Caching:** `Cache-Control: no-store` is already set globally.

The required changes concern the client state machine and the server's waiter bookkeeping.

| # | Required change | Resolution in revision 3 |
| --- | --- | --- |
| 1 | An answer arriving after a sync started could move Last Synced backwards (`synced(at:)` sets it unconditionally) or disturb the fallback count | Waits carry a generation, advanced by every sync start, lock, save failure, library replacement, connection change, path change, sleep and cancellation. Stale answers are discarded. `synced(at:)` only moves forward. Tests added (§4.6, §7.2) |
| 2 | Lock and other stop conditions didn't cancel a wait in flight (App Lock on the Mac doesn't cancel the loop); a `true` while locked would make `sync()` return false and count as a failure | A wait is cancelled at once when any waiting condition stops holding. A sync that `AppModel.sync()` declines counts neither as a failure nor as a strike (§4.6) |
| 3 | "Progress" was undefined, so legitimate races could score strikes | Progress: after the follow-up sync, the cursor, `cursor-change` or synced identity differs from what the wait sent. Stale answers never count. A failed follow-up sync counts in today's backoff instead (§4.6) |
| 4 | The waiter registry needed compare-and-remove semantics; an older wait's release could remove the newer one or double-decrement, and a device replacing its own wait shouldn't get 429 at the cap | Registrations are unique tokens; release removes only its own token; replacing one's own wait happens before the cap check. Tests assert the count returns to zero in any order (§4.3, §7.1) |

**Optional suggestions, all adopted:**

- **Continuity on every check.** Turning on encryption deletes the log without a restart, so the continuity lookup
  runs on every check, not only at entry. Clients send `serverId` whenever they have one.
- **Agents list cadence.** The list is re-read every 10 minutes (`listLifetime`), not every minute. §1, §4.6 and §6
  are corrected.
- **Retry times don't block waiting.** Records or images waiting only for a retry time no longer keep a device
  polling. The loop runs an ordinary sync at the earliest retry time.
- **Safety sync between waits.** It runs when the current wait ends, rather than cancelling it.
- **Protocol wording.**
  - `false` may come early (superseded, shutdown);
  - a `null` `payload` or `payloadDigest` counts as present and invalid;
  - the short receipt's required members are listed.
- **Test plan.**
  - The lost-wake-up test is deterministic, with a test hook.
  - The uncollected-pairing revocation case is dropped, along with `Notify()` in `RemoveExpired`: such a device has
    no credential.
  - The trivial capability-listing assertion is dropped.
- **App Nap.** The inactive Mac no longer claims changes arrive "at once".

**Questions:**

- **Does Tailscale Serve pass a client's cancellation on to Kestrel?** Added to the §7.3 checks, run only if a
  disposable tailnet is available. Latest wins covers it either way.
- **Should a `true` from an identity mismatch skip the strike count?** It's covered by the progress definition: a
  sync that adopts the new identity made progress, and one that can't ends in a stopped state, where nothing waits.

## Round 3 (revision 3)

**Verdict: approved with required changes.**

The reviewer confirmed the short receipts and the server side of long polling against the code:

- the request hash, `Receipt` and the digest helpers;
- taking the signal before the read, and level-triggered checks;
- rate limiting after authentication;
- the complete list of places that revoke a device or replace the identity.

The required changes concern client scheduling.

| # | Required change | Resolution in revision 4 |
| --- | --- | --- |
| 1 | Continuous typing wasn't sent while a wait was held. `syncWhenWritingPauses` only fires on a pause, and the 30 s longest wait is enforced by the loop's 3 s syncs, which waiting replaced | A live condition: any save, new outbox entry, added image or `pendingSync` turning true cancels the wait at once and returns the loop to `nextSyncDelay` until a sync is settled again (§4.6 condition 3). Test: typing during a wait is sent within 30 s |
| 2 | Last Synced froze with a refused item, because "nothing pending locally" was false while settled ignored refused items. Today's `sync()` calls `synced()` in that case | Last Synced from a `false` uses exactly the settled conditions. Refused items don't prevent it. Test added |
| 3 | The earliest retry time must leave out stale `retries` entries, or every sync schedules another at once and the device quietly polls | Only future times, and only for items still queued or missing. Test added |

**Optional suggestions:**

- **Forward-only Last Synced.** Adopted, but only for wait answers. Ordinary syncs keep `synced()` as it is, so Sync
  Now's check isn't affected by clock steps.
- **Generation inside `SyncEngine.synchronize`.** Adopted, covering the direct callers in EncryptionOperations and
  ServerJoining. Generations are read before the position.
- **`requestPublishing()` after `unchanged`.** Adopted.
- **Early `false`.** Adopted. An early `false` doesn't update Last Synced, and three in a row count as one strike. This
  also answers question 2: an answer at shutdown is early.
- **`AsNoTracking` reads.** Adopted. Test 9 also runs without continuity fields.
- **Fallback state in `SyncTiming`.** Adopted, so it survives a loop restart; it resets on a connection change.
- **Doc corrections.** All adopted:
  - the iOS background wording;
  - an automatic rename's bad receipt is swallowed, as today;
  - the impossible "no vault" branch and its test are removed;
  - the `after` validation difference is stated.
- **Red team additions.** Adopted.

**Questions:**

1. **The lost-wake-up test hook.** No production hook. The test is a `SyncSignal` unit test (a task taken before
   `Notify()` completes) plus the endpoint test. The handler's ordering is a red team item.
2. **Shutdown `false`.** It is early, so it neither updates Last Synced nor resets the count.
3. **One watcher per credential.** The contract now says clients run one wait at a time per device credential. Two
   would answer each other with early `false`, which leads to the fallback.

## Round 4 (revision 4)

**Verdict: approved with required changes.**

The reviewer confirmed against the code:

- the short-receipt hash and receipt paths;
- the bad-receipt behavior;
- the cursor check;
- that revocation paths are complete (`--restore` requires a stopped server);
- that the lost wake-up race is closed.

The open problems were in client scheduling.

| # | Required change | Resolution in revision 5 |
| --- | --- | --- |
| 1 | "Nothing queued locally" could miss edits. `enqueue` is `INSERT OR IGNORE`, `pendingSync` is already true with a refused entry, and "a save" had no defined source, missing non-editor mutations. On-time `false` would then mark Last Synced while an edit waited | A level-based `localChanges` counter in `JournalStore`. It advances after every transaction that marks a record changed, inserts or replaces an outbox row, or adds an image. It's checked before every wait and before any answer is used; live cancellation is the loop's 1-second tick. Tests: editing a refused entry and renaming a journal during a wait are sent, and Last Synced isn't updated first (§4.6, §7.2 items 8 and 9) |
| 2 | The sync generation was on `SyncEngine`, which is replaced and isn't the only engine using the store's gate; "no wait while a sync runs" had no mechanism | `syncGeneration` in `JournalStore` beside the gate, advanced on acquire and release (odd while a sync runs). Read before the position; answers also require the same store object (§4.6, §7.2 item 8) |
| 3 | Where decisions live was unclear for testing | `ChangeWatcher` is a pure state machine: events in, actions out, with an injected `ContinuousClock` and its state kept in `SyncTiming`. The app only translates and carries out actions (§4.6) |

**Optional suggestions, all adopted:**

- **Fewer counters.** The watcher generation is removed; a wait ID plus the store values decide whether an answer is
  current. Each early `false` is now one strike.
- **Retry times.** The engine reports retry times as a delay, so the watcher's timers stay on `ContinuousClock`.
- **Agents list.** The wording about re-reads is corrected, along with the stale comment.
- **Non-numeric parameters.** Documented: they get a model-binding 400, as GET /v1/sync/ does today.
- **Server cost.** Stated per wait cycle, not per write.
- **`Notify()` in EncryptionEndpoints.** It goes before `EncryptionPurge.Finish`, and each notify site gets a comment.

**Questions:**

1. **Which component emits "a save"?** Moot: the store counter covers every local write.
2. **Two waiters on one credential?** None in supported setups. JournalProbe and test lanes use their own
   credentials, and a shared one only degrades to polling.
3. **Diagnostics.** A rejected receipt is logged with its form and the failed check, without content, digests or IDs
   (§4.6).

## Round 5 (revision 5)

**Verdict: changes requested.**

The reviewer confirmed against the code:

- **Short receipts:** the hash, the mismatch handling, own-change acknowledgement and legacy receipts.
- **Server long polling:** the signal taken before the read, fresh reads, notify placement and latest-wins release.

The blocking problems were in the client's decision to wait.

| # | Required change | Resolution in revision 6 |
| --- | --- | --- |
| 1 | `localChanges` bumped call site by call site can't be complete. Re-encryption inserts outbox rows directly, merges set only `dirty`, review resolution and deletion write directly, adding an image touches no record, and `INSERT OR IGNORE` hides edits to already-queued records | A GRDB `TransactionObserver` advances `writes` after every commit touching `records`, `outbox`, `attachments` or `conflicts`, whatever code wrote. A sync's own writes come before its quiet mark, so they don't matter. `pendingItemCount()` is checked as a second level check before `markSynced`. Store tests cover each bypass path (§4.6, §7.2 item 8) |
| 2 | Discarded answers were described inconsistently, and nothing re-armed the watcher after syncs that never reach `syncFinished` (other engines, `sendWriting` while locked) | `endSynchronization` records a quiet mark `(syncGeneration, writes)` atomically. A wait starts only from a settled verdict whose mark is still quiet, checked with one atomic `quietPosition(since:)`. Any sync, any engine, any write or a discarded answer drops the verdict, and the loop polls until its own next settled sync re-arms it. The 1-second tick checks quietness and cancels a stale wait. Test: a sync through another engine during a wait |
| 3 | The wait's `URLSession` must keep the existing security configuration | Ephemeral, `urlCache = nil` and `NoRedirects`, with only the timeouts changed. Test: a 3xx becomes `failed` and isn't followed |

**Optional suggestions:**

- **"Settled" for each queued state.** Adopted, with a table covering lost images, records held back by refused or
  retrying images, and outbox rows that `takeForSending` skips.
- **One atomic store call.** Adopted (`quietPosition(since:)`).
- **The load claim for an inactive Mac.** Corrected.
- **A missing vault row.** It answers `true` instead of a 500.
- **Accuracy fixes.** The HTTP/1.1 connection limit is now "4 on iOS, 6 on macOS", and `RemoveExpired` is noted as
  also running at runtime.
- **The 100-wait total cap.** Dropped: one wait per enrolled device, and every wait needs a credential.
- **Protocol text.** It now says an early `false` proves nothing and that clients never follow redirects.

**Questions:**

1. **Do EncryptionOperations' syncs reach the watcher?** It no longer matters: the quiet mark detects any engine's
   sync.
2. **Can two waits run at once?** No. `startWait` always cancels a wait still in flight first.
3. **A device revoked outside the process.** The handler now runs its checks once more at the deadline, so such a
   device gets 401, not `false`. Test 7.1.7 is extended.

## Round 6 (revision 6)

**Verdict: approved with required changes.**

The reviewer confirmed against the code:

- **Short receipts:** they can't lose, duplicate or wrongly acknowledge content.
- **The server half of waiting:** the signal is taken before the reads, every read is fresh, there is a final check at
  the deadline, notify is placed right after each commit, and latest-wins holds.

| # | Required change | Resolution in revision 7 |
| --- | --- | --- |
| 1 | The quiet mark absorbed writes from other actor calls (a `commitMutation` rename) made between the engine's settled reads and `endSynchronization`, and the `pendingItemCount` baseline was undefined | The engine's last step is `store.settledFacts()`, one actor step returning the `writes` value with the outbox operation IDs, images to upload or verify, and the reconciliation flag. The engine classifies those against its own state. The mark uses that `writes` value, so any later write breaks quiet. The `pendingItemCount` check is removed. Test: a rename committed between `settledFacts()` and the gate release breaks quiet |
| 2 | The contract didn't define a confirming `false` for other clients; a server holding less than the timeout would look early forever | A confirming `false` MUST be held until the clamped timeout and re-checked there. Early answers carry `"early": true`. Clients also apply the timing check against caching proxies. To go into protocol/README.md |
| 3 | A wait cancelled from outside (`ServerClient.deinit` when the client is replaced) produced no event, so the watcher could stall, and the safety sync depended on the wait ending | Every wait task ends with `waitEnded`. An unrequested cancellation leads to a sync without a strike. The watcher has its own deadline per wait (45 s + 5 s), after which the wait is `failed`. The safety sync runs at the latest at that deadline |

**Optional suggestions, all adopted:**

- **The GRDB observer.** The counter is lock-protected and never actor state, the observer lives for the database's
  lifetime, and a rollback clears its note.
- **Network flaps.** A `failed` answer is a strike only when its follow-up sync succeeds, so flaps don't strike.
- **The server await.** It uses `WaitAsync` with one linked token.
- **Waits after shutdown begins.** A wait that arrives after stopping began answers early. Tested.
- **Binding `after`.** It is bound as optional, so a missing value is `invalid_cursor`.
- **Naming.** One event name, `quietBroken`.

**Questions:**

1. **When is the generation sampled for the mark?** After the release advance and before the hand-off advance, so a
   sync handed the gate breaks quiet. Tested.
2. **Who computes "settled"?** The engine, from `settledFacts()` and its own refused and retry state.
3. **Funnel's timeout.** Unverified, and now stated as an assumption. The fallback covers it.

## Round 7 (revision 7)

**Verdict: approved with required changes.**

The reviewer confirmed against the code:

- **The server side:** the digest and request hash, the signal and fresh reads, the deadline re-check, and the
  identity and revocation paths.
- **Content safety:** no path that loses or duplicates content, or acknowledges a change the server doesn't hold.

| # | Required change | Resolution in revision 8 |
| --- | --- | --- |
| 1 | An edit to a refused record made during a sync, after the re-queue pass and before `settledFacts()`, was folded into the quiet mark. `commitMutation` changes (delete, move, rename, an image description) start no sync, so the change would wait for the safety sync while Last Synced said "Just now" | Simplest option taken: nothing refused is part of "settled". While any record or image is refused, or a record is held back by a refused image, the device polls as today. Tests updated |
| 2 | Outbox rows under review weren't classified; counting them would silently disable waiting during long reviews | Classified as settled, using the set `pending()` returns. Resolving the review writes `conflicts` and breaks quiet. Test: an entry under review doesn't stop waiting |
| 3 | The confirming-`false` timing rule was ambiguous with a clamped timeout | Clients send at most 25. The rule is min(requested, 25) − 2 s, and goes into protocol/README.md |

**Optional suggestions, all adopted:**

- **Client replacement.** The wait task keeps the client alive, so `deinit` doesn't cancel it. A `clientReplaced`
  event now makes the watcher cancel its wait and sync.
- **Re-encryption writes.** They go to a copy through another `DatabaseQueue`. The "same store object" check is what
  protects there; §4.6 and the tests are corrected.
- **`automaticSyncStopped`.** It covers only My Journal needing an update; the other Update or fix needed cases are
  failures, as the text now says.
- **Automatic renames.** The first wait afterwards answers `true` at once. This is noted as expected in §7.4.
- **One event name.** `waitEnded(id, result, sentAt)`, including cancellations.
- **Path changes.** Defined as a change of status or interfaces, debounced by 1 s.
- **Red team case.** An aborted Revoke with a skipped `Notify()`.

**Questions:**

1. **Should a network change reset the fallback?** Yes: a path change resets the strike count and ends a fallback
   period.
2. **Is the kind check only for short receipts?** Yes, on purpose. Full receipts keep today's handling unchanged; a
   receipt with both `payload` and `payloadDigest` is checked as a short one.
3. **Which loop does the bandwidth run use?** The idle measurement now runs the Release app's real loop on the iOS
   simulator. JournalProbe measures only the writing session.

## Round 8 (revision 8)

**Verdict: approved with required changes.**

The reviewer confirmed the claims against the server, JournalCore and app code:

- **Short receipts:** the hash and retry path, the digest on both sides, and the acknowledgement checks.
- **Waiting:** rate-limiter placement, and every place that writes the log or revokes a device.
- **The store:** the gate is shared across engines, and all store writes go through the actor.

It found no way for short receipts to lose, duplicate or overwrite content, and no lost wake-up.

| # | Required change | Resolution in revision 9 |
| --- | --- | --- |
| 1 | A failed automatic rename push is swallowed, and renames never sit in the outbox, so the device could wait while a rename stayed unsent and Last Synced said "Just now" | `settledFacts()` also reports whether an automatic rename is outstanding. If one is, the sync isn't settled, and the device polls and retries as today. Table row and test added |
| 2 | HTTP/3 was missing: the shipped Caddy deployment publishes UDP 443, and QUIC idle timeouts (30 s in quic-go) and UDP NAT mappings leave a thin margin at 25 s | The client asks for 20 s (the server's maximum stays 25 s), leaving a 10 s margin. HTTP/3 is added to §4.7 and verified through the pinned Caddy image with UDP enabled, with the protocol confirmed by `URLSessionTaskMetrics`. If waits are still cut, the client falls back to polling, which is accepted. §6 estimates updated to 3 waits a minute |

**Optional suggestions:**

1. **A simpler fallback, without strikes, progress or the one-hour period.** Not adopted. Round 1 required a `true`
   without progress to count toward a fallback. Without one, an inactive Mac facing a faulty server, or a proxy that
   fails waits at once, would make a request every 3 s instead of today's 30. The strike rule is small and
   test-covered.
2. **Read `writes` inside the same `db.read` as the facts, and use a counter-only `isQuiet(mark)` on the tick.**
   Adopted.
3. **`Notify()` in a `finally` once the commit was attempted.** Adopted.
4. **A `loopStarted` event that clears a wait still marked in flight.** Adopted.
5. **Baseline from git.** The owner has since committed build 9 (9c6c83d), so the mixed-version baseline is a git
   worktree of that commit.
6. **The read-only rule as code comments** on each post-sync step. Adopted.

**Questions:**

1. **Should an outstanding rename block waiting?** Yes: the device polls, as today.
2. **Is a shorter timeout acceptable?** Yes: the client asks for 20 s.
3. **Is a stale in-flight wait cleared on purpose at loop restart?** Yes: `loopStarted` clears it.

## Round 9 (revision 9)

**Verdict: approved, with no required changes.** The reviewer checked the design's descriptions of today's code
against the source, and confirmed:

- **Short receipts:** they give the store the same bytes it receives today.
- **The long-poll server:** level-triggered, with the signal taken before reading and a final check at the deadline.
- **The quiet mark:** consistent with commits on the `DatabaseQueue`, and every write that needs sending creates an
  outbox row.
- **Last Synced:** a confirming `false` is sound evidence, because the log is append-only within one identity.

No path loses or duplicates content, acknowledges an unheld change, overwrites a conflicting edit, stops sync, or
breaks compatibility.

**Optional suggestions applied** (minor clarifications, no change to the approved behavior):

- **Wait timeouts.** The wait's request timeout is 30 s and its resource timeout 35 s; the watcher deadline is 40 s.
  A black-holed wait is noticed sooner.
- **Loop actions.** Only the running loop carries out actions. Events after its task ends are dropped, so iOS
  cancelling the loop never triggers a sync.
- **The classification table.** The `takeForSending` row is reworded as "record gone, or only a lost image".
- **The observer** stops observing until the next transaction after its first relevant change.
- **protocol/README.md** gets the list of client obligations and the proxy guidance.
- **§9** records why both `early` and the timing check exist, and that Last Synced keeps today's meaning.

**Not adopted:** not counting `early` answers as strikes during server restarts. Strikes only matter after three in
a row, and the 3-second floor bounds the rate either way.

**Questions:**

1. **Should a confirming `false` mark Last Synced when retries or lost images remain?** Today's meaning is kept,
   because today's syncs mark it in the same cases. Recorded in §9 for the owner.
2. **Does `configureSync` run on unlock?** Harmless either way; to be confirmed during implementation.
3. **Does URLSession's QUIC send keep-alives, or use its own idle timeout?** To be confirmed in §7.3.6. The fallback
   covers either answer.
