# Sync health and recovery (revision 2)

Status: **revision 2, approved with required changes by an independent review (see Review), which are all applied
here. Approved by the owner on 2026-10-01 with both recommendations: Check Connection is left out, and Not on Server
Yet counts items.**

Builds on:

- [connection-onboarding.md](connection-onboarding.md)
- [join-with-local-journals.md](join-with-local-journals.md)
- [sync-now-and-done.md](sync-now-and-done.md)
- [enable-encryption.md](enable-encryption.md)
- the protocol's `sync-identity` and `sync-continuity` capabilities ([protocol/README.md](../../protocol/README.md))

## Owner request (2026-10-01)

**What happened.** After the owner's server was reset (data wiped, waiting for a setup code), the connected app showed
"Couldn’t complete the server request. Try again." on every sync. Retrying can never work.

**What the owner asked for:** "what is the real fix here? not just for this scenario but in general if this sync is
broken".

**Principle.** Local-first: each device always holds a complete copy of its own writing. The server is replaceable. A
broken connection never strands the person and never loses anything.

## What the owner will see

Each state has exactly one message and at most one action. The message shows in Settings > Sync, under the server.
It also shows in Sync Status: the toolbar cloud button on the Mac, and the entry's … menu on iPhone and iPad.

| Situation | Message | Action |
|---|---|---|
| Syncing normally | none | Sync Now |
| Offline | "You’re offline. Your changes are saved on this device and will sync when you’re back online." | Try Again |
| Server unreachable | "Can’t reach the server right now. Your changes are saved on this device and will sync automatically." | Try Again |
| Server busy | "The server isn’t available right now. Your changes are saved on this device and will sync automatically." | Try Again |
| Server reset, waiting for setup | "The server isn’t set up. Your journals are still on this device." | Set Up Server Again… |
| Server restored or replaced | "The server was restored or replaced and doesn’t recognize this device. Your journals are still on this device." | Connect Again… |
| This device was removed | "This device no longer has access to the server. Your journals are still on this device." | Connect Again… |
| Encryption turned on elsewhere, or the server was replaced by an encrypted one | "The server now uses encryption or was replaced. Sign in to keep syncing." | Sign In… |
| App or server needs an update, or a broken certificate | For example: "The server needs an update before this device can sync. Your changes are saved on this device." | Check Again |
| Something unexpected | "Couldn’t sync because of an unexpected problem. Your changes are saved on this device." | Try Again |
| This device's own data can't be read | "My Journal couldn’t read its data on this device. Your journals haven’t been changed. To keep a copy, choose Export Archive in Settings > Backup." | Try Again |

- **Quiet.** While syncing normally or retrying by itself, Sync Status doesn't show, however many changes wait
  (amended 2026-10-02, [quiet-sync-and-title-alignment.md](quiet-sync-and-title-alignment.md); before, a plain cloud
  showed while changes waited).
- **Problems.** It shows a cloud with an exclamation mark when the person must act, or when changes have waited more
  than about a day while sync fails.
- **Automatic retries stop** where retrying can't help: a server that isn't set up, restored or replaced; this device
  removed; sign-in needed; My Journal needing an update.

**Settings > Sync** (iPhone and iPad; the Mac's Sync tab is the same, with the message below the buttons):

```
SERVER
┌──────────────────────────────────────────────┐
│ https://journal.example.ts.net               │
│ Last Synced               Yesterday at 21:14 │
│ Not on Server Yet                    3 items │
│ Set Up Server Again…                         │   ← the state's single action
└──────────────────────────────────────────────┘
The server isn’t set up. Your journals are still on this device.

┌──────────────────────────────────────────────┐
│ Stop Syncing…                                │
└──────────────────────────────────────────────┘
```

**Owner decisions (2026-10-01): both recommendations accepted.**

1. **Check Connection: left out.** A screen that checks the server's reachability, its certificate, this device's access and
   whether the server still holds the same journals.
   Sync Now, Try Again and Check Again already run the full check, and the message says what it found. Section 4.3
   is kept only as a record of what was considered.
2. **Not on Server Yet counts items** (entries, journals and templates), including ones waiting only on an image.
   Worded "1 item", "3 items". "Entries" would be wrong whenever a journal or template is waiting.

## 1. Inventory: what the client does today

Evidence from the code. "Toolbar" is Sync Status (Mac toolbar cloud button; iPhone and iPad: the entry's … menu).
"Settings" is Settings > Sync. Backoff is `AppModel.syncDelay` (SyncSchedule.swift:17): 3 s doubling to 5 minutes.
`syncWhenWritingPauses` and `sendWriting` sync outside that backoff, after every pause in writing and on leaving an
entry.

| # | Failure | What the client sees | Message today | Behavior today |
|---|---|---|---|---|
| 1 | Offline | `URLError.notConnectedToInternet` | "Couldn’t connect to the server. Your changes are saved on this device." (SyncSchedule.swift:152) | Toolbar shows the error icon at once; Try Again; backoff; no retry when the network returns until the backoff ends |
| 2 | Timeout | `URLError.timedOut` | Same as 1 | `affectsOnlyThisItem` (SyncEngine.swift:446) treats a timeout as a problem with one record: each queued record then waits its own 20 s timeout and 15 s+ retry |
| 3 | Server down, 5xx, proxy 502/503/504 | Connection refused, or HTTP 5xx | Refused: as 1. 5xx: "Couldn’t complete the server request. Try again." (ServerClient.swift:276, 432), "Couldn’t sync. Your changes are saved on this device." (push, :463) or "Couldn’t upload an image. Try again." (:504) | Backoff; three wordings for one situation |
| 4 | TLS or certificate problem | `URLError.serverCertificate…`, `.secureConnectionFailed` | The system's text, for example "The certificate for this server is invalid. You might be connecting to a server that is pretending to be …" | Backoff; Try Again |
| 5 | Address doesn't resolve | `.cannotFindHost`, `.dnsLookupFailed` | As 1 (Tailscale variant for `.ts.net`) | Backoff |
| 6 | Incompatible server | Sync never checks `protocolVersion` (SyncEngine.swift:127). A non-JSON page (captive portal, wrong proxy) fails decoding | Decoding: "The data couldn’t be read because it isn’t in the correct format." Missing endpoint: "Couldn’t complete the server request. Try again." | Backoff; Try Again |
| 7 | **Server not set up (reset)** | `/v1/status` says `initialized: false`; the identity check (`confirmSameProtection`, SyncEngine.swift:169) reads `/v1/recovery`, which answers 404 `not_initialized` (AccountEndpoints.cs:54) | **"Couldn’t complete the server request. Try again."** (the owner's report) | Backoff and every writing pause, forever; Try Again can never work; Settings offers no way forward |
| 8 | Data folder rolled back (an older copy put in place; credentials survive) | `sync-continuity`: 409 `server_changed`, or a push answered with `revision_ahead` | None | **Heals automatically:** everything is compared again and what the server lost is sent back (SyncEngine.swift:398, 227; rollback probes in scripts/test-sync.sh) |
| 9 | Server restored with `--restore` | Restoring signs out every device (BackupArchive.cs:135) and gives the server a new identity, so every request is 401 | "This device no longer has access." (Models.swift:14) | Toolbar offers Try Again, which can't work; backoff forever. Only Settings > Devices offers Connect Again…. After signing in, the existing identity-keeping path compares everything and loses nothing (RestoreProbe) |
| 10 | Server replaced by another library | 401, and `serverId` differs from the one this library last synced with | As 9. If this library isn't encrypted and the new one is: "Encryption was turned on from another device. Sign in to keep syncing." (`lostAccess`, EncryptionOperations.swift:313), which can be wrong. No protocol record links a new server identity to the one it replaced, so the client can't tell the two apart | As 9. Connect Again… then skips Merge Journals, because `joinsByMerging` requires no connection (ServerJoining.swift:160) |
| 11 | This device revoked | 401, same identity (DeviceAuthentication.cs:33 answers alike for unknown and revoked) | As 9 | As 9 |
| 12 | Credential no longer accepted for another reason | 401, same identity | As 9 | As 9 |
| 13 | Password changed on another device | Nothing: the vault key is unchanged | None | Keeps syncing; the new password unlocks through `recoverKey` (PasswordOperations.swift:33) |
| 14 | Encryption turned on elsewhere | Identity changes; the server's format is encrypted and this library isn't | "Encryption was turned on from another device. Sign in to keep syncing." | Toolbar and Settings offer Sign In… (`offersSignIn`); identity-keeping rejoin |
| 15 | Recovery format mismatch (a format this app doesn't know) | `contentProtection` throws `unsupportedFormat` | "Update My Journal to edit this entry." (Models.swift:8, an entry message) | Backoff |
| 16 | A record or image refused | `SyncRejection` | "“‹title›” is too large to sync…", "Your server didn’t accept “‹title›”…" and the image equivalents (SyncEngine.swift:256, 456) | Item-level: the rest syncs. Works as designed |
| 17 | Rate limited | 429, `ServerRateLimited` | "Too many attempts. Try again in a few minutes." | Shown as an error; `Retry-After` ignored by the schedule |
| 18 | Local store can't be read or written | GRDB `DatabaseError` | The database's own text, for example "SQLite error 11: database disk image is malformed - while executing …", which can include SQL | Backoff. (A save failure already pauses syncing with its own notice.) |
| 19 | The server's identity changes twice within one sync | `ServerChanged` twice | "Couldn’t sync. Your changes are saved on this device." (SyncEngine.swift:121) | The next sync compares everything. Works as designed |
| 20 | Anything else | `invalidData` (a faulty server's page), `ResponseTooLarge`, other errors | "This data couldn’t be read.", "The server sent more data than expected.", or the error's own text | Backoff |

**Also found**

- In every state the toolbar offers **Try Again**, unless encryption was turned on elsewhere. Settings > Sync has no
  action besides Sync Now.
- [docs/guide/troubleshooting.md](../guide/troubleshooting.md) quotes "Couldn’t sync…" for an unreachable server. The
  app says "Couldn’t connect to the server…".
- Setting up a reset server from a connected device already works through Connect to a Server, if the person finds
  it. But `commitConnection` (ServerJoining.swift:48) leaves the old connection's Keychain item behind.
- **A library without a password** joining a server after it stopped being connected takes the merge path. That's
  because `retainedKey` (ServerJoining.swift:89) requires a connection. Nothing removes a connection today, but Stop
  Syncing (4.4) would. Section 3.3 replaces the key test with lineage.
- **Connecting to another address** is refused while connected (`checkReconnection`, ServerJoining.swift:379): "Reconnect
  to the same server to keep your journals together."

## 2. States

Every sync failure maps to exactly one state. A problem with one record or image (16) and changes to review aren't
connection states. They keep today's behavior and copy.

| State | Cases | Primary action | Automatic sync |
|---|---|---|---|
| **Syncing normally** | none | Sync Now | Every 3 s; every 30 s while another app is active, and at once on becoming active |
| **Temporary** | 1, 2, 3, 5, 17, 19 | Try Again | Backoff; `Retry-After` honored; at once when the network returns (`NWPathMonitor`) or the app becomes active |
| **Needs you** | 14, and 10 when this library isn't encrypted and the server is | Sign In… | Stops |
| **Server changed** | 8 (no UI); 7; 9, and 10 otherwise | 7: Set Up Server Again…; 9, 10: Connect Again… | Stops, except 8 |
| **No access** | 11, 12 | Connect Again… | Stops |
| **Update or fix needed** | 4, 6, 15 | Check Again | Every 5 minutes. Stops when My Journal itself needs the update |
| **Unexpected** | 20; 18 with its own message | Try Again | Backoff |

**Telling the states apart** is done in JournalCore, so it can be tested without the UI.

1. The sync engine reads `/v1/status` first, as today. A pass with nothing to send within a minute of a successful read
   reuses that status (each page still names the server's identity); any failure reads it again before it's classified,
   so the states below are the same as if it had been read first.
   - `initialized: false` is **Server changed (not set up)**. Nothing else is requested.
   - A `protocolVersion` other than 1 is **Update or fix needed (update My Journal)**.
   - A response that isn't a status (HTML, a 404) is **Update or fix needed (not a My Journal server)**.
2. A 401 later in the same sync is classified by the identity it read:
   - `serverId` differs from the one this library last synced with:
     - **Needs you** when this library isn't encrypted and the server is, since it may be encryption turned on
       elsewhere or a replaced server, and the copy covers both;
     - **Server changed (restored or replaced)** otherwise;
   - the same identity, or no identity on either side (older servers): **No access**.
3. **Connection failures:**
   - lost connections, timeouts while sending or reading records, 5xx on status or on reading changes, and 429 end the
     sync as **Temporary**;
   - image transfers that time out stay per image, as today, so one slow image doesn't hold up records.
4. **A 5xx on one record's push** retries with that record's backoff. After 3 such failures in a row, while other
   requests succeed, the record is refused at item level, with the existing "Your server didn’t accept “‹title›”. It’s
   saved on this device. Edit it to try again." Sync Now and Try Again send it again, as for any refused record.
5. TLS errors and an unknown recovery format are **Update or fix needed**.
6. GRDB `DatabaseError` from this device's store is **Unexpected** with its own message. Everything else is
   **Unexpected**.

**When automatic sync stops,** it starts again:

- after the state's action succeeds;
- after Sync Now, Try Again or Check Again finds the problem gone. Each of them runs the full sync, which reads the
  status, this device's access and the identity first;
- at launch;
- when the app becomes active again, with one status check at most every 10 minutes.

Writing never waits for any of this.

**Long waits.** When changes have waited for more than about 24 hours while sync fails, Sync Status shows with
`exclamationmark.icloud` in any state, with the same message (amended 2026-10-02: only while the last sync failed, and
measured from the first failure when this connection hasn't synced yet). This isn't a new state. The wait is measured from Last Synced while items wait
(implementation note: outbox rows carry no time, and a last successful sync more than a day old with items waiting
means they have waited at least that long or sync has been failing that long; both deserve the mark).

## 3. Self-healing, and what can't heal

### 3.1 Heals with no action

- **Temporary failures** retry until they succeed, and at once when the network comes back. What's queued is kept in
  the store's outbox, so nothing depends on the app staying open.
- **A rolled-back data folder** (8) is compared again and the lost changes are sent back. This is existing behavior,
  with tests. Differing versions become changes to review.
- **A server that lost revisions** (`revision_ahead`) is treated the same way.
- **A server that lost images** checks each image again (`uploaded = 2`) and receives it again.
- **A password changed elsewhere** (13) needs nothing.

### 3.2 Needs a secret: one guided action

A setup code, a password, a recovery code or a connected device's approval can't be supplied by the app. Each of
these states has one action, which reuses existing flows.

**Set Up Server Again…** (the server isn't set up)

- Opens Connect to a Server with the address filled in and checks it at once.
- The server isn't set up, so the flow goes straight to **Set Up Server**, the existing setup-code step. A setup code
  is still required.
- Then, as today for a library with journals: Enter Master Password when the library has one, then Setting Up….
- The library keeps its encryption and password. Its envelope is the one sent.
- The old connection's Keychain item is removed once the new one is saved (`commitConnection`).
- The new identity makes the first sync compare everything (`reconcileMissing`). Every item is queued again and every
  image checked, so the server receives the whole library.
- If another device set the server up meanwhile, the existing message applies: "This server has just been set up.
  Choose it again to sign in." Continuing then takes the Connect Again path.

**Connect Again…** (restored or replaced, or no access)

- Opens Connect to a Server with the address filled in and checks it at once.
- Then Enter Master Password, Add This Device or Use a Recovery Code, as for any device signing in.
- After access is granted, and before anything is sent, lineage decides the path (3.3):
  - **Same library:** joins by identity, with no Merge Journals step. This is the case for a revoked device, a
    restored server, or a server another of this library's devices set up again.
  - **Different library:** **Merge Journals** appears now, with the grant held as for Try Again
    ([join-with-local-journals.md](join-with-local-journals.md) §2.7). Merge continues; Back or Cancel revokes the
    grant, and nothing was sent.
- On the merge path, the busy labels are "Checking…" while the server's records are read, then "Merging…".

**Sign In…** (Needs you)

- The existing flow, with the same lineage check.
- Encryption turned on elsewhere is the same library, so it takes the existing identity-keeping re-encryption.
- A replaced server is a different library, so it takes Merge Journals.

**Unconnected libraries** (first connection, or after Stop Syncing) keep today's order: Merge Journals before signing
in.

- When lineage then finds the same library, the merge rules still join it by identity, so Merge Journals only asks
  for consent. It sends nothing extra.

### 3.3 Lineage: why nothing is lost or duplicated

**The rule.** After access is granted, the staged copy reads the server's records, as merging already does (step 1).
If the server holds any record ID that this library synced before (a record with a server revision), it's the
**same library**. For an encrypted server, the vault key must also be the same. Otherwise it's a **different
library**.

Implementation note: when this library and the server are both encrypted, the vault key alone decides, since the same
key is the same library and no records need to be read (`AppModel.joinPlan`). Lineage reads the server
(`SyncLineage.serverHoldsLibrary`: the identity this library last synced with, then the server's log until a known
record turns up) when either side has no encryption. An empty server is the same library for a library that synced
before: it combines nothing, and turning on encryption elsewhere empties the server until that device sends its copy,
which keeps this library's identities.

**Same library: joins by identity**, the existing identity-keeping path (`snapshot` and reconciliation), for libraries
with or without a password.

- An identical record is adopted.
- A different one becomes a change to review.
- One the server lacks is sent.
- Built-in templates keep their IDs, which are random per library (Models.swift:237), so they aren't added again.

**Different library: merges** with derived identities ([join-with-local-journals.md](join-with-local-journals.md)
§2.1).

- Unedited built-ins are skipped when the server has a template of their name, and added otherwise (amended by
  [no-built-in-templates-2026-10-04.md](no-built-in-templates-2026-10-04.md)).
- Same-name journals are combined.
- Retries are idempotent.

**This replaces the key comparison** (`masterKey != key`, ServerJoining.swift:222), which can't tell libraries without
a password apart. Revision 1 proposed "a library without a password that has synced before keeps its key". That would
have added another library's built-in templates under their own random IDs, a second copy of each.

**Other cases**

- **Two devices racing to set up a reset server.** The setup code lets only one succeed. The other is told the server
  was just set up, and takes Connect Again, which finds the same library.
- **Offline edits on other devices** are queued in their outboxes. After Connect Again they're sent, or reviewed when
  the same record changed on the server.

## 4. Settings > Sync: one place to understand and fix it

### 4.1 Layout

On iPhone and iPad, Settings > Sync has the section **Server**:

1. The address (unchanged).
2. **Last Synced** (unchanged). It keeps the last successful time in every state.
3. **Not on Server Yet**, a `LabeledContent` shown only while items are waiting: "1 item" or "‹N› items" (decision 2).
4. **The state's single action** (section 2). The separate Sign In… row (`EncryptionSignInButton`) becomes this
   action.

The footer holds the state's message, and nothing while syncing normally.

A section without a header ends the pane: **Stop Syncing…**.

The Mac's remote-server layout is the same, with the message as secondary text below the buttons, as today. The Mac's
own server ("This Mac") gets the classification and copy but keeps its controls. Stop Server covers Stop Syncing there.

### 4.2 Toolbar and Sync Status: quiet, pointing to Settings

**Amended 2026-10-02 (owner decision, [quiet-sync-and-title-alignment.md](quiet-sync-and-title-alignment.md)):**
Sync Status shows only when the person must act: when the state isn't Syncing normally or Temporary, for a refused
record or image, or after a long wait (2). Changes waiting alone never show it, so writing never changes the toolbar.
The icon is always `exclamationmark.icloud`. On the Mac the toolbar keeps its place while the library syncs, so it
appearing never moves another item.

~~**When it shows:** while items are waiting, or when the state isn't Syncing normally or Temporary.~~

~~**Icon:** `icloud` for Syncing normally and Temporary; `exclamationmark.icloud` for the other states, and after a long
wait (2).~~

The help text is "Sync Status".

**Menu:**

1. the state's message;
2. the state's action, when it has one;
3. **Sync Settings…**, which opens Settings at Sync. On the Mac it selects the Sync tab; on iPhone and iPad it presents
   Settings pushed to Sync.

### 4.3 Check Connection… (left out by the owner's decision; not implemented)

A sheet titled **Check Connection** runs these checks in order, once each. A check that can't run because an earlier
one failed shows "Not Checked".

| Row | Passes | Fails |
|---|---|---|
| Server | "Reachable" | "Offline", "Not Found", "Not Responding", "Not a My Journal Server", "Needs an Update", "Not Set Up" |
| Secure Connection | "Valid" ("Not Used" for this Mac's own address) | "Certificate Not Valid" |
| This Device | "Has Access" | "No Access" |
| Your Journals | "Same as Last Sync" | "Server Changed" |

- **While running:** the current row shows "Checking…" with a small spinner, and later rows show "Waiting".
- **Each result** is a symbol and a word: `checkmark.circle` or `xmark.circle`, never color alone.
- **When done:** the footer shows the state's message, the state's action appears below the rows, and **Done**
  closes the sheet.
- **The result updates the sync state.**

### 4.4 Stop Syncing…

**The dialog.**

- Title: "Stop syncing with ‹host›?"
- Message: "Your journals stay on this device. To sync again later, choose Connect to a Server in Settings > Sync."
  - When items are waiting, it adds: "‹N› items that aren’t on the server yet will stay only on this device until
    then."
- Buttons: **Stop Syncing** and Cancel. Stop Syncing isn't red: nothing is deleted.

**What it does.**

- If the server still accepts this device, it revokes this device's own access, so it leaves the Devices list. A
  failure is ignored.
- It removes the connection and its Keychain item, and clears Last Synced.
- It keeps the library unchanged: record identities, sync position, waiting items and the server identity.

**Afterwards.**

- Settings > Sync shows "Connect to a Server…" and "Your journals are saved on this device."
- Agents keep reading what's already on the server until their access is revoked in Settings > Agent Access on a
  connected device.
- Reconnecting goes through Connect to a Server. Lineage (3.3) then joins the same library by identity and merges a
  different one; a reset server goes to Set Up Server.

**A server that moved to a new address.** Connecting to another address is refused while connected
(`checkReconnection`). So the steps are: Stop Syncing, then Connect to a Server with the new address. Lineage joins the
same library by identity. The guide says so.

## 5. Invariants

1. Writing is never blocked by a sync state. (A failed save is a separate, existing pause.)
2. Local content is never discarded. No state, action or Stop Syncing deletes a record, an image, an outbox row or a
   version.
3. Automatic retries stop in the states where retrying can't help: Needs you, Server changed (except 8), No access,
   and My Journal needing an update. Writing pauses send no requests then.
4. There's exactly one state at a time, with at most one primary action. The toolbar never offers an action that can't
   work in that state.
5. No message shows implementation details: no status codes, SQL, error domains or "request".
6. A setup code is always needed to claim a server, and a secret or a connected device's approval to rejoin one.
7. Merge Journals appears only when journals will actually be combined, before anything is sent.
8. Every state has a test (section 6).

## 6. Test plan

### 6.1 Real disposable servers

- **Server.** The published binary (`mise exec -- scripts/package-server.sh osx-arm64 <scratch>`) on a fixed loopback
  port between 18950 and 18959, so a reset or restore keeps the address the devices know. It runs as a new
  `scripts/test-sync-health.sh` lane, outside the default `test-sync.sh` run.
- **Devices.** `JournalProbe` phases drive two or three of them, each a real `JournalStore` with `SyncEngine`, as the
  merge and restore probes do. The same lineage and join code is used.
- **No fault proxy.**

**Convergence check after each row,** once every device has synced:

- every device holds the same records;
- every entry written anywhere exists exactly once;
- every template exists exactly once;
- no journal name repeats;
- no outbox row or pending image is left;
- the server's record count equals the union.

| # | Fault | Devices | Expected state | Recovery |
|---|---|---|---|---|
| 1 | Server stopped while A writes, then restarted | A, B | Temporary | Automatic; B receives A's entries |
| 3 | **Reset**: stop, wipe the data folder, restart. A and B each have offline edits | A, B, then C | A and B: Server changed (not set up) | A sets up again with the new setup code. B: Server changed (restored or replaced), then Connect Again: password, same library, **no Merge step**; B's offline edits are sent. C joins and receives everything |
| 4 | Reset, then B sets the server up with a different library | A, B | A: Server changed (restored or replaced) | A: Connect Again, password, then **Merge Journals**; same-name journals combined, unedited built-ins once each (no-built-in-templates-2026-10-04.md) |
| 5 | `--restore` from an older backup | A, B | Server changed (restored or replaced) | Both Connect Again with no Merge step; edits made after the backup are sent back; differing versions reviewed |
| 7 | B revokes A | A, B | A: No access | A: Connect Again, password, no Merge step; A's waiting edits sent |
| 10 | Stop Syncing on A, write on A, reconnect to the same server: once with a password, once without | A, B | | Same library by lineage; no duplicate entries or templates; A's new entries arrive at B |
| 11 | Stop Syncing on A, server reset, reconnect | A | | Set Up Server; everything uploaded |

**Rows from revision 1 that moved**

- Row 6 (rollback) stays covered by the existing rollback probes in `test-sync.sh`.
- Row 8 (encryption turned on elsewhere) stays covered by `EncryptionSwitchProbe`.
- Rows 2 and 9 moved to 6.2.

### 6.2 Smaller tests

- **Classification** (JournalCore unit test with an injected clock): one table from (status, identity before and
  after, error, attempts) to state. It covers:
  - the 401 split and the Needs you case;
  - `initialized: false`;
  - `protocolVersion: 2` and a non-status page;
  - a record timeout ending the pass while an image timeout stays per image;
  - a 5xx on one record becoming an item refusal after 3 attempts;
  - 503 and 429 with `Retry-After`;
  - TLS codes and a database error.
- **Automatic retries stop** (app test with `FakeJournalServer`):
  - in No access and Server changed, neither the schedule nor writing pauses send requests;
  - Sync Now sends one;
  - becoming active checks once, at most every 10 minutes;
  - a network change triggers a sync at once in Temporary.
- **Long wait** (app test): changes waiting more than 24 hours while sync fails show Sync Status with the state's own
  message; waiting alone doesn't (amended 2026-10-02).
- **The action opens the right step** (app test):
  - Set Up Server Again… goes to the setup-code step;
  - Connect Again… goes to sign-in;
  - Merge Journals appears after the grant only for a different library, and Cancel revokes the grant.
- **Stop Syncing keeps everything** (app test): the store and outbox are unchanged, the connection's Keychain item is
  gone, and Set Up Server Again leaves no old connection item.

Not tested: copy, labels, view composition.

**UI verification.** Screenshots of each state on a dedicated iPhone simulator and on the Mac, in light and dark and
at the largest text size: Settings > Sync, Sync Status, the Stop Syncing dialog, and Merge Journals after sign-in.

## 7. Copy

### 7.1 Messages

Sync status messages say "the server", as today. ‹host› appears only where the person confirms something about a
specific server. Each message shows in full in Settings > Sync and in Sync Status.

| State | Message | Action |
|---|---|---|
| Temporary: offline | "You’re offline. Your changes are saved on this device and will sync when you’re back online." | Try Again |
| Temporary: can't reach | "Can’t reach the server right now. Your changes are saved on this device and will sync automatically." For `.ts.net`, before the last sentence: "If it uses Tailscale, turn on Tailscale on this device." | Try Again |
| Temporary: busy or rate-limited | "The server isn’t available right now. Your changes are saved on this device and will sync automatically." | Try Again |
| Needs you | "The server now uses encryption or was replaced. Sign in to keep syncing." | Sign In… |
| Server changed: not set up | "The server isn’t set up. Your journals are still on this device." | Set Up Server Again… |
| Server changed: restored or replaced | "The server was restored or replaced and doesn’t recognize this device. Your journals are still on this device." | Connect Again… |
| No access | "This device no longer has access to the server. Your journals are still on this device." | Connect Again… |
| Update: My Journal | "Update My Journal to sync with this server. Your changes are saved on this device." | Check Again |
| Update: server | "The server needs an update before this device can sync. Your changes are saved on this device." | Check Again |
| Fix: certificate | "Can’t connect securely to the server because its certificate isn’t valid. Your changes are saved on this device." | Check Again |
| Fix: not a My Journal server | "The server address doesn’t lead to a My Journal server. Your changes are saved on this device." | Check Again |
| Unexpected | "Couldn’t sync because of an unexpected problem. Your changes are saved on this device." | Try Again |
| Unexpected: this device's data | "My Journal couldn’t read its data on this device. Your journals haven’t been changed. To keep a copy, choose Export Archive in Settings > Backup." | Try Again |

### 7.2 Other copy

- **Not on Server Yet:** "1 item" or "‹N› items" (decision 2).
- **Sync Status:** the menu item "Sync Settings…".
- **Settings > Devices:** the No access text becomes the No access message above. Its button stays Connect Again….
- **The guide.**
  - [troubleshooting.md](../guide/troubleshooting.md), "Sync isn’t working": list these messages and actions, and add
    "Your server moved to a new address: choose Stop Syncing…, then Connect to a Server with the new address."
  - [sync.md](../guide/sync.md): describe Stop Syncing.
  - Mention that agents need access again after a reset or restore.

### 7.3 Accessibility

- **VoiceOver announcements** come only from the result of an action the person started: Sync Now, Try Again, Check
  Again, Check Connection, or the guided actions. Background state changes aren't announced. They're read where
  they're shown.
- **Not on Server Yet** reads as one element, for example "Not on Server Yet, 3 items".
- **Check Connection rows**, if kept, read as one element each, such as "Server, Reachable". Their symbols are hidden
  from VoiceOver.
- **Dynamic Type:** `LabeledContent` wraps at accessibility sizes, and footers use
  `fixedSize(horizontal: false, vertical: true)`.
- **Reduce Motion:** only the system spinner moves.
- **Increase Contrast and Reduce Transparency** need nothing extra.
- **Keyboard:** Full Keyboard Access reaches everything on the Mac and iPad.
- **Ellipses:** actions that open a flow end in "…".

## 8. Out of scope

- **Following a server to a new address automatically.** Stop Syncing, then connecting to the new address, handles it
  (4.4). Until then the old address shows Temporary "Can’t reach".
- **Notifications for long-unsynced changes.** The symbol after a day, and Not on Server Yet, are enough for now.
- **Agent access after a reset or restore.** Agents need access again from Settings > Agent Access. The guide says so,
  and there's no new UI.
- **The Mac's own server** keeps its controls (4.1).
- **Repairing a corrupt local store.** The Unexpected message points to exporting an archive. Restoring uses the
  existing Backup pane.
- **A protocol link from a new server identity to the one it replaced.** It's not needed: the Needs you copy is true
  either way.

## Review

**Revision 1: approved with required changes (independent design review, 2026-10-01).** All are applied in revision 2:

1. **Merge Journals only when journals will be combined.** Lineage decides after access is granted and before
   anything is sent (3.2, 3.3). Row 3 now expects no Merge step.
2. **Lineage replaces the key rule** for libraries without a password, because built-ins have random IDs (3.3). The
   convergence check adds "every template exactly once".
3. **Case 10:** copy that's true whether encryption was turned on or the server was replaced. That was simpler than a
   protocol link (2, 7.1).
4. **Timeouts:** record timeouts end the pass, and image transfers stay per item. A 5xx that repeats on one record
   becomes an item refusal after 3 attempts (2).
5. **Long waits** of more than about 24 hours show the exclamation symbol (2, 4.2).
6. **Update or fix needed** gets Check Again.
7. **Section 8 is corrected:** a moved server needs Stop Syncing first. The guide says so (4.4, 7.2).
8. **The real-server matrix** is cut to rows 1, 3, 4, 5, 7, 10 and 11, without a fault proxy. Rows 2 and 9 moved to
   smaller tests, and row 6 refers to the existing rollback probe.
9. **Set Up Server Again** removes the old connection's Keychain item.

**Optional notes adopted:**

- this device's data errors have their own Unexpected message, which points to backups;
- `NWPathMonitor` retries as soon as the network returns;
- the single sentence "Your journals are still on this device." and "isn’t set up";
- VoiceOver announces only the results of actions the person started;
- Stop Syncing stays non-red.

**Open questions:**

- Merge Journals for a restored server: answered no (change 1).
- Check Connection and the Not on Server Yet unit: now owner decisions 1 and 2, with recommendations.

## Implementation (2026-10-01)

**JournalCore**

- `SyncHealth` (SyncHealth.swift) is the classification of §2 with the copy of §7.1. `SyncFailure` carries what only
  the server's status or identity can tell; `ServerUnavailable` is any 5xx.
- `SyncEngine` reads the status first and stops for a server that isn't set up, speaks another protocol or isn't a
  journal server; a 401 is classified by the identity read (§2, step 2). A record that times out ends the pass; an
  image transfer stays per image. A 5xx on one record's push counts against it after a pass whose other requests
  succeeded, and the third is refused at item level.
- `SyncLineage.serverHoldsLibrary`, `JournalStore.syncedRecordIDs` and `pendingItemCount`.

**App (iPhone, iPad, Mac)**

- `AppModel.syncHealth`, `syncStatusAction`, `stopSyncing`, `openSyncSettings` (SyncHealthOperations.swift); automatic
  sync and writing pauses don't sync in states that stop it, except one check when the app becomes active after 10
  minutes; `Retry-After`, the 5-minute check for Update or fix needed, and `NWPathMonitor` (`NetworkReturn`) set the
  wait (SyncSchedule.swift).
- Settings > Sync: Last Synced, Not on Server Yet, the single action, and Stop Syncing… (SyncNowRows.swift). The
  separate Sign In… row was removed; the action covers it. Sync Status: the message, the action and Sync Settings…, with
  the exclamation mark only when the person must act or after a long wait (iOS menu and the Mac toolbar).
- Connect to a Server opens at this device's server and checks it at once for every reconnecting state. A connected
  library that turns out, after access was granted, to face another library stops with `MergeConsentNeeded` before
  anything is staged or sent; its password access is revoked, Merge Journals appears, and Merge signs in again (a
  recovery code's or pairing's access is kept for it, as for Try Again). `joinPlan` replaces the key comparison.
- `commitConnection` removes the Keychain item of the connection it replaces. Settings > Devices shows the classified
  message for a refused device.
- Found while testing every case, and fixed:
  - A connection committed by Connect Again… or Sign In… kept the old state, so automatic sync stayed stopped and Last
    Synced stayed empty. A new library or connection now starts from a clean state, and joining syncs once more at
    the end.
  - After encryption is turned on elsewhere, the server holds no records until that device sends its copy, so lineage
    found nothing and would have merged (duplicating the journals once the copy arrived). An empty server is now the
    same library for a library that synced before (§3.3), and joining it by identity encrypts the library with the
    server's key whether or not it's still connected (before, a library that stopped syncing would have joined an
    encrypted server empty).
  - The Sign In step's intro said "Encryption was turned on from another device…", which isn't true for a replaced
    server; it's now "The server now uses encryption. Enter its master password."

## Coverage (2026-10-01)

Every case of the inventory (§1), every state (§2) and every action, with the test that checks it. "Real" means a real
disposable server, network or device in `scripts/test-sync-health.sh` (HealthProbe*.swift); "UI" means
`scripts/test-sync-recovery-ui.sh` (SyncRecoveryUITests, Release, a dedicated iPhone 17 simulator, the published
server, which the script stops, wipes, restores and replaces on request). In-memory and FakeJournalServer tests are used
only where a real server can't produce the case. Each state's retry behavior is asserted with its case.

| # | Case | State, message and retries | Recovery: nothing lost or duplicated |
|---|---|---|---|
| 1 | Offline | Classification table (SyncHealthTests); the network returning ends the wait (SyncRecoveryTests, `NetworkReturn`). No real way to take the test Mac offline | Row 1 below |
| 2 | Timeout | Record timeout ends the pass and is sent again without waiting; image timeout stays per image (SyncHealthTests, in memory: a real server can't be made to stall) | Next sync |
| 3 | Server down, 5xx | Real: server stopped → Temporary, retries continue (row 1). 5xx → Temporary, 6 s wait (SyncRecoveryTests table, FakeJournalServer) | Real row 1: A and B converge. UI: Try Again after the server is back, nothing left waiting |
| 4 | Certificate | Real: `openssl s_server` with a self-signed certificate → Update or fix needed, retries continue | UI: Check Again (case 6's journey) |
| 5 | Address doesn't resolve | Real: `journal.invalid` → Temporary | As 3 |
| 6 | Incompatible server | Real: another web server → "doesn't lead to a My Journal server", 5-minute checks. Newer protocol (stops), missing endpoint (server update), unknown recovery format (stops) in the SyncRecoveryTests table (only a fake server can send them) | UI: another web server at the address, then Check Again once the journal server is back; SyncRecoveryTests `testCheckAgainSyncsOnceTheJournalServerIsBack` |
| 7 | Server not set up (reset) | Real rows 3, 11 and UI: "The server isn't set up…"; automatic sync and writing send nothing, one check after 10 minutes (SyncRecoveryTests) | Real row 3: Set Up Server Again, B connects again without Merge, C joins; UI: Set Up Server Again… with the new code |
| 8 | Data folder rolled back | Never leaves Syncing normally (rollback probes in `scripts/test-sync.sh`) | Rollback probes |
| 9 | Restored with `--restore` | Real row 5 and UI: "restored or replaced…", stops | Real row 5: both connect again, later edits sent back; UI: Connect Again… after a restore, every entry once |
| 10 | Replaced by another library | Real row 4: "restored or replaced…"; real plain row: an encrypted library replacing a library without encryption → "The server now uses encryption or was replaced…" (Needs you) | Real rows 4 and plain: Merge Journals after access, one Default, each template once; app: Merge asked after the grant, the grant revoked when cancelled (SyncRecoveryTests) |
| 11 | Device revoked | Real row 7 and UI: "This device no longer has access…", stops | Real row 7 and UI: Connect Again…, no Merge, waiting edits sent |
| 12 | Credential not accepted | Real: a token the server doesn't know → No access | As 11 |
| 13 | Password changed elsewhere | Real: B changes it; A keeps syncing (no state) | Real: a new device signs in with the new password |
| 14 | Encryption turned on elsewhere | Real: EncryptionSwitchProbe (`scripts/test-sync.sh`) → Needs you; UI: "The server now uses encryption or was replaced…" | UI: Sign In… with the new password, every entry once |
| 15 | Unknown recovery format | SyncRecoveryTests table → Update My Journal, stops | Updating the app |
| 16 | Refused record or image | Real: an entry too large to sync is explained and the rest syncs; an image the server refuses (413, which this app's own size limit keeps a real server from sending) in SyncRecoveryTests | Shorten or edit; Try Again sends it again |
| 17 | Rate limited | Real: the server's limit reached → Temporary, its `Retry-After` kept (60 s); the wait follows it (SyncRecoveryTests) | Next sync after the wait |
| 18 | Local store unreadable | Real: the records table's page overwritten in a copy of a device's library → "My Journal couldn't read its data on this device…", retries continue | Export Archive (existing) |
| 19 | Identity changes twice in one sync | SyncHealthTests (in memory; a real server can't change identity twice within one request sequence on demand) → Temporary | Next sync compares everything |
| 20 | Anything else | A page that goes back → Unexpected, 6 s wait (SyncRecoveryTests table); classification table | Try Again |

| Action | End to end |
|---|---|
| Set Up Server Again… | UI after a real reset; real row 3; SyncRecoveryServerTests (the app's `initializeServer` on a wiped real server); SyncRecoveryTests (goes straight to the setup-code step; the old connection leaves nothing) |
| Connect Again… | UI after a removal and after a restore; real rows 4, 5, 7; SyncRecoveryServerTests (the app's `recoverServer` and `joinPlan` after a removal, a `--restore` and another library, which merges only after Merge Journals) |
| Sign In… | UI after encryption was turned on from another device; real plain row; SyncRecoveryServerTests (an encrypted library replaced the server of one without encryption) |
| Try Again | UI with the server down, then back |
| Check Again | UI with another web server at the address, then the journal server back |
| Stop Syncing…, then connecting again | UI (Merge Journals asks, then the same library joins by identity, every entry once); real row 10 with and without a password; SyncRecoveryServerTests (the app's `stopSyncing`, then the same server by identity, or another library by merging: one Default, each template once); SyncRecoveryTests (the library and its waiting items are kept, access given up) |
| The action follows the state | SyncRecoveryTests `testTheActionFollowsOnlyTheCurrentState`: Sign In… gives way to Set Up Server Again…, Connect Again… and Sync Now as the server changes; `testOnlyStatesThatNeedThePersonAskForAttention` for the symbol in every state |
| Sync Settings… | Not automated; opens Settings at Sync (code review) |
| Long wait | UI: the last sync moved two days back shows "29 Sep at …" with 1 item waiting; SyncRecoveryTests (the exclamation mark after a day) |

`SyncRecoveryServerTests` runs in `scripts/test-local-server.sh`, so the app's own join, merge and Stop Syncing code
is what's tested against the real server; the probes check the same scenarios through JournalCore.

**Verifier round (2026-10-02), fixed with a test that fails without the fix:**

- Sign In… stayed after the state changed (a reset or a working server): the action now follows the current state
  only, and the encryption sign-in flag follows each sync.
- Joining by Connect Again… or Sign In… didn't sync again once writing resumed, so the last entries waited for the
  next automatic sync and Last Synced stayed empty (found by SyncRecoveryServerTests).
- "Couldn’t complete the server request. Try again." in connecting, pairing and Devices: a server error now says
  "The server isn’t available right now. Try again in a moment.", anything else "Couldn’t reach the server. Check the
  address and your connection, then try again."
- A tap on an action that opens Connect to a Server could be lost after a presentation failed, leaving the sheet's
  flag set; each tap now makes a new request (`ConnectionRequest`). This was the likely cause of the verifier's
  15 seconds without a sheet; it couldn't be reproduced, so it has no test.

**Not covered by an automated test:** the Mac toolbar menu and Settings tab (built and unit tested, not driven, as the
owner may be using the Mac), the exclamation mark in the iPhone menu (its rule is unit tested), and VoiceOver
announcements.
