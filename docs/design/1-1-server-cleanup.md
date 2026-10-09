# 1.1 server cleanup (simplification O) — 2026-10-09

Status: implemented in 1.1 phase 6 (2026-10-09); see [Implementation notes](#implementation-notes) for the few places the code differs from this text. Design for the owner and for the mandatory design gate in [AGENTS.md](../../AGENTS.md). The independent review (appended below) approved it with changes; this body includes them, and [Changes after review](#changes-after-review) maps each finding to its change. Scope record: [release-1-1-scope.md](release-1-1-scope.md), item O. The archive half of the 1.1 protocol work is in [1-1-archive-v2.md](1-1-archive-v2.md).

Item O had four parts: capability flags become one protocol version, unused endpoints go, LAN discovery goes, and there is one setup path. **The owner decided on 2026-10-09 to keep LAN discovery** (Servers on This Network, the Bonjour service `_myjournal._tcp` and its announcer), so the second part of this record is now only the protocol revision, the route audit and the setup path; discovery is left exactly as in 1.0. The MCP agent access has to keep working. Version 1.0 (build 19) is in App Review and will be public before 1.1 ships, so every 1.0 app and every 1.0 server people run has to work with 1.1 ones in both directions.

## 1. What this record decides

| Part | Result |
| --- | --- |
| Capability flags | Replaced for new code by one integer, `protocolRevision`, on `/v1/status` and `/v1/server`. The 13-flag `features` list is frozen: 1.0 apps read it, so it stays on every server for as long as `/v1` exists, and it is never extended. A 1.1 app reads the revision, or derives revision 1 from a complete legacy list, and has no per-flag branches. 1.1 apps refuse a server below revision 1 (decided); the refusal changes and discards nothing, and clears when the server is updated. |
| Unused endpoints | Evidence below: every route is called by a 1.0 app or is documented infrastructure, except `GET /v1/server`, which no client calls but which is a documented part of `/v1` and a conformance step. Within wire major 1 a removal is a breaking change ([server/AGENTS.md](../../server/AGENTS.md)). So 1.1 removes no route: that is a consequence of the additive-only rule in [server/AGENTS.md](../../server/AGENTS.md), not a choice. It records which routes 1.1 apps stop calling and removes them with `/v2`. |
| LAN discovery | **Kept (owner, 2026-10-09).** Servers on This Network, `ServerBrowser`, the `_myjournal._tcp` service, `NSBonjourServices`, `NSLocalNetworkUsageDescription` with its current wording, `deploy/lan/` and the `lan` Compose profile, and their docs and spec all stay as they are in 1.0. Nothing in this record changes them. |
| One setup path | Setting up means: Connect to a Server, choose the server (from Servers on This Network, by address, or by scanning a code), enter the setup code, choose a master password. The tolerated older paths go (eight-character setup codes, servers without `setup-check`, and with simplification G the Don't Encrypt branch). The repository documents one first deployment route: the local container, then Tailscale or HTTPS as variations of where it runs. |
| MCP agent access | Unaffected. It depends on `/v1/status` (`mcpUrl`, `agent-access-2`), `/v1/agents*`, `/v1/agent-requests*`, `/mcp`, `/oauth/*`, the well-known documents and `JOURNAL_URL`/`Journal:PublicUrl`. Nothing in this design touches them. |

## 2. Current state, with evidence

### 2.1 What agent access depends on (checked first)

| Dependency | Where | Kept? |
| --- | --- | --- |
| Capability `agent-access-2` read before listing or approving agent requests | `AgentCopyClient.swift` (`agentAccessFeature`, guard in `status().supports`, line ~114), `ServerAgentsController.swift:51` | Yes: still in the frozen list; the 1.1 app reads it as part of revision 1. |
| The MCP address `mcpUrl` / `mcpUnavailable` from `GET /v1/status` | `ServerAgentsController.swift:55`, `ServerClient.swift:20-23`, `AgentProbe.swift`; produced by `AccountEndpoints.cs` and `PublicOrigin.cs` | Yes, unchanged. |
| Device-authenticated agent endpoints | `GET /v1/agents/`, `PUT|DELETE /v1/agents/{id}`, `GET|POST /v1/agents/{id}/items`, `GET /v1/agents/{id}/activity`, `GET /v1/agent-requests/`, `GET /v1/agent-requests/{id}`, `POST …/approve|ready|decline`: all called from `AgentCopyClient.swift` lines 105-215 | Yes, unchanged. |
| Agent-facing surface | `POST /mcp`, `/.well-known/oauth-protected-resource/mcp`, `/.well-known/oauth-authorization-server`, `/oauth/register|authorize|authorize/wait|authorize/status|token|revoke` ([protocol/agent-access-server.md](../../protocol/agent-access-server.md)). `/oauth/authorize/wait` is the page's no-JavaScript refresh and `/oauth/authorize/status` the scripted poll (`AuthorizationPage.cs:22,94`) | Yes, unchanged. |
| The public origin | `Journal:PublicUrl`, else `JOURNAL_URL` (`PublicOrigin.cs:55-72`, [protocol/agent-access-server.md](../../protocol/agent-access-server.md) Addresses) | Yes. `JOURNAL_URL` stays in `deploy/compose.yaml` and `deploy/compose.tailscale.yaml` for the `journal` service (and for the optional `lan` service, unchanged). |
| Anything using Bonjour, `sync-wait`, `/v1/server` or LAN discovery | Searched `server/src`, `apps/apple` (incl. `JournalProbe`), `protocol/` | None, and discovery is unchanged anyway. The agent copy is published after a sync from synchronized state and never browses the network. |

Conclusion: every change below is outside this surface. The agent test suites (`AgentAccessTests`, `AgentApprovalTests`, `AgentHardeningTests`, `McpTransportTests`) and `AgentProbe` run unchanged and must stay green as the check.

### 2.2 Route inventory

"1.0 app" is Apple build 19 (`ServerClient.swift`, `Pairing.swift`, `ServerEncryption.swift`, `AgentCopyClient.swift`, `SyncWaiting.swift`; searched for every `"/v1/` literal). Tests are `server/tests/Journal.Api.Tests`.

| Route | Server | 1.0 app calls it | Other evidence | 1.1 |
| --- | --- | --- | --- | --- |
| `GET /health`, `GET /ready` | `Program.cs` | No (infrastructure) | Container health checks, `scripts/test-https-deployment.py`, `scripts/test-packaged-server.py`, self-hosting docs | Keep |
| `GET /v1/server` | `AccountEndpoints.cs:23` | **No** | Tests (`McpTransportTests`, `AgentAccessTests`, `SyncTests`, `RecoveryAccessTests`, `RequestBoundaryTests`); fixture step `server-capabilities` in `sync/exchanges-v1.json`; [protocol/README.md](../../protocol/README.md) Versioning; comments in `scripts/package-server.sh` and `server/Dockerfile` (the version it reports) | Keep, see 2.2.1 |
| `GET /v1/status` | `AccountEndpoints.cs:32` | Yes, first request of every sync and connect (`ServerClient.status()`) | Fixtures, scripts | Keep; gains `protocolRevision` |
| `POST /v1/setup`, `POST /v1/setup/check` | `AccountEndpoints.cs:47-48` | Yes (`initialize`, `checkSetupCode`) | `SyncTests` | Keep |
| `GET /v1/recovery`, `POST /v1/recovery`, `GET /v1/recovery/envelope` | lines 51-66 | Yes | `RecoveryAccessTests` | Keep |
| `POST /v1/recovery/password` | line 67 | Yes (`changePassword`) | `PasswordChangeTests` | Keep |
| `POST /v1/recovery/encrypt` | `EncryptionEndpoints.cs` | Yes (`ServerEncryption.swift:46`) | `EncryptionUpgradeTests` | Keep. A 1.1 app stops calling it if simplification G removes Turn On Encryption; the route stays for 1.0 apps (a 1.0 library without encryption can still turn it on against a 1.1 server). Removal candidate for `/v2`. |
| `GET /v1/devices/`, `DELETE /v1/devices/{id}` | lines 68-73 | Yes | `RevocationTests` | Keep |
| Pairing: `POST /v1/pairing`, `…/poll`, `…/reveal`, `…/cancel`, `…/lookup`, `GET …/{id}`, `…/challenge`, `…/decline`, `…/approve` | `PairingEndpoints.cs` | Yes, all nine (`Pairing.swift` 141-282) | `PairingSecurityTests`, `InvitePairingTests`, `PairingConformanceTests` | Keep |
| `GET /v1/sync/`, `PUT /v1/sync/{id}`, `GET /v1/sync/wait` | `SyncEndpoints.cs` | Yes (`ServerClient.swift:442,476`, `SyncWaiting.swift:126`) | `SyncTests`, `SyncEfficiencyTests`, fixtures | Keep |
| `PUT|HEAD|GET /v1/attachments/{id}` | `AttachmentEndpoints.cs` | Yes (`ServerClient.swift:581-601`) | `SyncTests` | Keep |
| Agent routes (section 2.1) | `AgentGrantEndpoints.cs`, `OAuthEndpoints.cs`, `McpEndpoint.cs` | Yes (device side); MCP clients (agent side) | Agent test suites | Keep |

Result: one route has no caller, and it is not removable under the compatibility rules. No endpoint becomes removable in 1.1 because 1.0 apps stay in use; that is the cost of shipping 1.0 first.

#### 2.2.1 `GET /v1/server`

Evidence of non-use: no Swift call site (`grep '/v1/server'` finds none; clients read `/v1/status`, which the protocol README already says: "the Apple app reads `/status`"). Evidence for keeping it:

- It is the only database-free, unauthenticated answer and the only place that reports `serverVersion` and the list of wire majors (`protocolVersions`). A Windows or Android client written after 1.1 can use it as a preflight before it knows whether the server is set up.
- Removing it breaks `sync/exchanges-v1.json` step `server-capabilities`. Fixtures are never edited in place ([conformance README](../../protocol/conformance/README.md)), and the server must keep passing the v1 files while 1.0 clients exist.
- It costs about ten lines.

So it stays and is documented as the preflight endpoint. It gains `protocolRevision` like `/v1/status`.

### 2.3 Capability flags

`AccountEndpoints.cs:15-17` lists 13 flags. The server never branches on them (`grep` of `Feature` in `server/src` finds only the list and the constants that feed it); they only describe the server. Who reads them:

| Flag | In repository history since | Read by the 1.0 app | What the 1.0 app does without it | Server tests |
| --- | --- | --- | --- | --- |
| `sync-identity` | Build 9 | Not read | Nothing | `RestoreIdentityTests` |
| `pairing-check-code` | Build 9 | `ConnectionFlow.swift:355` | `PairingError.serverOutdated` | `PairingSecurityTests` |
| `password-change` | Build 9 | Not read (404/405 means outdated, `ServerClient.swift:432-435`) | `PasswordChangeError.serverOutdated` | `PasswordChangeTests` |
| `sync-continuity` | Build 9 | `SyncEngine.swift:232` | Skips the continuity check; a rolled-back server is detected late | `RestoreIdentityTests` |
| `sync-continuity-digest` | Build 9 | `SyncEngine.swift:233` | Sends no `afterDigest` | `SyncEfficiencyTests` |
| `private-envelope` | Build 9 | `ServerClient.swift:359` | Reads the envelope from public `GET /v1/recovery` | `RecoveryAccessTests` |
| `pairing-invite` | Build 9 | `ConnectionFlow.swift:394`, `AddDeviceView.swift:288` | Hides scanning, refuses scanned codes | `InvitePairingTests` |
| `setup-check` | Build 9 | `ConnectionFlow.swift:155` | Accepts an eight-character setup code and skips the check | `SyncTests` |
| `encryption-upgrade` | Build 9 | `EncryptionOperations.swift:43` | `EncryptionFailure.serverOutdated` | `EncryptionUpgradeTests` |
| `agent-access-2` | Build 9 | `AgentCopyClient.swift:114`, `ServerAgentsController.swift:51` | No agent access | `AgentAccessTests` |
| `sync-short-receipt` | Build 10 | `SyncEngine.swift:234` | Full receipts | `SyncEfficiencyTests` |
| `sync-wait` | Build 10 | `SyncEngine.swift:272` | Polling | `SyncEfficiencyTests` |
| `record-kinds` | Build 14 | `SyncEngine.swift:239` (`updateLibrarySync`) | Pins and journal order stay on the device (`store` setting `server-record-kinds`) | `SyncTests` |

The history in this repository begins at build 9, so "since Build 9" means "from the start". Every server that has run 1.0 code, and every server since build 14, lists all 13. Servers from builds 9 to 13 were run by testers only. Scope item D already stops supporting TestFlight builds older than 16 on the client, so a server that lacks a flag is a server nobody should still have.

Two things follow:

1. **The flags cannot leave the wire.** 1.0 apps read eleven of them, and the 1.0 app checks `protocolVersion == 1` exactly (`SyncEngine.swift:212`, `ConnectionFlow.swift:118,391`: greater than 1 means "update the app"). So `protocolVersion` must stay `1` and the list must stay complete. The new number cannot reuse `protocolVersion`.
2. **The client branches can go.** Every "server lacks flag X" branch in the 1.1 app protects only servers older than build 14. They are dead once the app refuses such servers: continuity and digest optionality, short receipt optionality, `waitingSupported`, `server-record-kinds`, the eight-character setup-code path, the pairing and invite fallbacks and about six "needs an update before …" messages (section 7).

### 2.4 LAN discovery (kept, owner decision 2026-10-09)

For the record, what exists and stays untouched:

| Piece | Where |
| --- | --- |
| Announcer | `deploy/lan/` (`Dockerfile`, `announce.sh`, `avahi-daemon.conf`); `lan` service with profile `lan` in `deploy/compose.yaml` and `deploy/compose.tailscale.yaml`; `image: journal-lan:local` |
| Client browse | `apps/apple/JournalApp/Model/ServerBrowser.swift` (`NWBrowser`, `_myjournal._tcp`, TXT `v=1` and `url`), started and stopped by `ConnectionView.swift`; the Servers on This Network section and its denied, looking and none states |
| Permission and declarations | `apps/apple/project.yml` (`NSLocalNetworkUsageDescription`, "Find and sync with your server on your local network.", and `NSBonjourServices`), both targets |
| Docs and spec | `docs/self-hosting/README.md`, `docs/guide/sync.md`, `README.md`, `PRIVACY.md`, `SECURITY.md`, `docs/app-store/*`, the spec pages and the Windows plan (DNS-SD) |

Consequences for this design:

- **No change** to any of those files, to the App Store review notes or to the App Privacy answers because of this record.
- **The Local Network hint after a failed connection is dropped.** The review (finding 1) asked for it because removing the browse would have removed the only in-app path to the Local Network setting. With discovery kept, the browse still asks for the permission when Connect to a Server opens, and the existing denied sentence (`settings.connect.nearby.denied`) is shown on page 1, the same page where a failed connection reports its error. A guess by host name would add a second, less reliable signal for the same condition and a new key. The new key `messages.connection.cannotConnectLocalNetwork` and the plausibly-local rule are not added. If the on-device checks of section 4.7 show that the banner is missing in a case where a connection to a local host fails, the hint comes back as a follow-up.
- The 1.0 app and a 1.1 app behave the same against any announcer.
- `NSLocalNetworkUsageDescription` keeps its wording; B42 in `spec/open-questions.md` (no copy key for the system permission texts) stays open and is not part of this record.

### 2.5 Setup paths today

The ways to start syncing, from `flows/connect-to-server`:

1. Choose from Servers on This Network (stays; owner decision 2026-10-09).
2. Type the address (stays).
3. Scan a code from a connected device (stays; this is joining, not setup).
4. Setup code, three variants: six-character code checked by `setup-check`; an older eight-character code tolerated when the server cannot check (`CodeEntry.isOlderSetupCode`, `ConnectionFlow.swift:157-160`); the server regenerating an old-format code file at start (`SetupCode`, server only; harmless, stays).
5. Protect Your Journals with Encrypt or Don't Encrypt (goes with simplification G, designed elsewhere).
6. On the host: three Compose files (local, Tailscale, HTTPS) and the standalone package. These are hosting choices, not alternatives for the same step; each prints a setup code with `setup-code`.

"One setup path" is read here as: a person sets up a server one way in the app, and the repository documents one first route (the local container, then Tailscale or HTTPS as variations of where it runs). This reading is confirmed (owner, 2026-10-09, with LAN discovery kept); see section 9.

## 3. The new contract

### 3.1 Protocol revision

`GET /v1/status` and `GET /v1/server` gain one member:

```json
{ "protocolVersion": 1, "protocolRevision": 1, "features": [ …the same 13… ] }
```

(`/v1/server` has `protocolVersions: [1]` and no `protocolVersion`; it gains `protocolRevision` alongside.)

Rules, for [protocol/README.md](../../protocol/README.md) (section Versioning and capabilities is rewritten):

- `/v1` stays the wire major. `protocolVersion` stays `1` on every server that implements `/v1`.
- `protocolRevision` is an integer. A server at revision N implements everything of revisions 1 to N. A revision is additive: new endpoints, optional fields, response members, error codes. Revision 1 is exactly what a My Journal 1.0 server implements.
- The 1.1 server reports revision 1. It changes nothing a client can observe, which is the point: nothing needs to be negotiated, and no 1.0 behaviour moves. The reason to add the number now is that every 1.1 client, including Windows, must contain the rule before the first revision 2 exists; a client that ships without it cannot be told about revision 2 later.
- `features` is **frozen**: the 13 names above, still advertised, never extended, never shortened. New capabilities become revisions, with a paragraph in the protocol README saying what the revision adds. Existing prose that says "capability `x`" is rewritten as "revision 1" with the name kept in a table for 1.0 readers.
- `recoveryVersions` is not a capability; it describes data formats and stays.
- Effective revision, which every client computes the same way:
  1. `protocolVersion` greater than 1: a newer wire major, "Update My Journal".
  2. `protocolRevision` present and valid: that value. (`/v1/server` has no `protocolVersion`; it has `protocolVersions`, whose maximum plays the same part in step 1. Clients read `/v1/status`, which the 1.0 app already does; `/v1/server` is for preflight.)
  3. Otherwise 1 if `features` contains all 13 names, else 0.
  4. A revision below 1 is a server too old to sync with; revision 1 or more is used as is (a client that knows less than the server's revision simply doesn't use the newer parts).
- A client never reads an individual flag after this change. It gates each post-1.0 behaviour on `revision >= N`, never on a flag. A server release that wants a client to use a new behaviour raises the revision; it does not add a flag, and a server never drops a flag when it raises its revision.
- A client re-reads the revision on every status read and never caches it beyond that read: a server restored from an older backup or replaced may legitimately report a lower revision (3.3), and the gate then applies again.
- A `protocolRevision` that is not an integer, is 0 or negative, or is above 2^31 − 1 counts as absent, so a broken value can neither lock a client out nor let it skip the flag check.

New conformance file `protocol/conformance/sync/status-v2.json` (a new file; `exchanges-v1.json` is untouched). The "2" is the second file version of the status contract, as the folder rule numbers fixtures; it is not a protocol version, a recovery format or the archive's number, and `sync/README.md` says so in one line:

- `server`: the member set both endpoints must return (subset match): `protocolRevision: 1`, `protocolVersion`/`protocolVersions` 1, the 13 `features`, `recoveryVersions` `[1,2,3,4]`. The protocol README's Versioning list also records that `/v1/server` returns `mcpUrl` and `mcpUnavailable` (the code and [agent-access-server.md](../../protocol/agent-access-server.md) already say so).
- `effectiveRevision` cases a client must compute, table-driven: explicit `1`; explicit `7`; absent with 13 flags (`1`); absent with 12 flags missing `record-kinds` (`0`); absent with no `features` (`0`); `protocolVersion: 2` (`newer major`); a `features` list with unknown extra names (still `1`); a malformed `protocolRevision` (`"x"`, `0`, `-1`, `2147483648`) with the 13 flags (`1`) and without them (`0`).

### 3.2 Endpoints

- No route is removed from the 1.1 server. `GET /v1/server` stays (2.2.1).
- 1.1 apps no longer call: `POST /v1/recovery/encrypt` (if G removes Turn On Encryption; the G design decides), and the recovery-code and unencrypted-vault branches of the setup, recovery and pairing routes (format versions 3 and 4) once G removes creating them. These stay served because 1.0 apps and 1.0 libraries use them: a 1.0 app can create a version-4 vault on a 1.1 server and a 1.0 library without encryption can still turn it on.
- The protocol README gets a "Retired by 1.1 apps, removed in /v2" list so the removal is planned, not forgotten: `POST /v1/recovery/encrypt`, recovery formats 3 and 4, `private-envelope`'s fallback `wrappedKey` in `GET /v1/recovery`, and `GET /v1/server` if `/v2` has a better preflight.
- The audit of "no caller" is repeatable: `scripts/` gets no new tooling; the table in 2.2 is the record, and the protocol README's endpoint list gains a column "first revision".

### 3.3 Compatibility matrix

| | 1.0 server (no `protocolRevision`, 13 flags) | 1.1 server (revision 1, same 13 flags) | Server older than build 14 (flags missing) |
| --- | --- | --- | --- |
| **1.0 app** | As today | Works exactly as today: same routes, same `protocolVersion: 1`, same flags; it ignores the new member (its `ServerStatus` is a Swift `Codable` that skips unknown keys). | As today (degrades per flag) |
| **1.1 app** | Works: revision 1 derived from the complete list | Works: reads `protocolRevision` | Refused (section 3.5). Changed from today, when the app degrades |
| **Windows/Android client written to 1.1** | Works | Works | Refused |

Other directions covered:

- **Server downgrade** (restoring a 1.0 backup into a 1.0 server, [server-backup.md](../../protocol/server-backup.md)): the list is the same, the field disappears, 1.1 apps derive revision 1.
- **`lan` announcers.** The profile and `deploy/lan/` stay in 1.1, so 1.0 and 1.1 apps both find a server announced with them.
- **Wire fixtures.** `exchanges-v1.json` replays unchanged against the 1.1 server (it asserts a subset). `status-v2.json` is additive.
- **Local libraries** never contain a flag or a discovered server. The one persisted item that depends on a flag, the `server-record-kinds` setting in the store, is no longer read or written by 1.1 and stays readable as an unknown key ([protocol/archive.md](../../protocol/archive.md) already says readers ignore keys they don't know).

### 3.4 What the server code does

- `AccountEndpoints.cs`: add a `ProtocolRevision = 1` constant next to `ProtocolVersions`; return it from both endpoints; keep `Features` as a literal list with a comment "frozen: 1.0 apps read these (protocol/README.md)". The per-feature constants `SyncEndpoints.ContinuityDigestFeature`, `ShortReceiptFeature`, `WaitFeature`, `RecordKindsFeature` and `EncryptionEndpoints.Feature` have no other use and fold into that literal.
- `deploy/`: unchanged (`deploy/lan/`, the `lan` service and `JOURNAL_URL` stay).
- No database change, no migration. A 1.1 server starts on a 1.0 database and a 1.0 server on a 1.1 database ([server/AGENTS.md](../../server/AGENTS.md)).

### 3.5 Refusing an old server: a gate, nothing else

Servers from builds 9 to 13 (decided: refused) are the only ones this touches. The refusal is evaluated on each status read and is a pure gate:

- **Nothing is changed or discarded.** Queued changes, pending images, the sync cursor and identity, the device credential, agent grants and the Devices list stay exactly as they are. Syncing, Add Device, Change Password and Agent Access resume with no other action as soon as a status read shows revision 1 or more, because the revision is never cached beyond a read.
- **One message from every entry point.** Connect to a Server (page 1), the sync state, Add Device, Change Password, Turn On Encryption (if it still exists) and Agent Access all show the same text rather than each hiding itself or saying something else: on page 1 and in the other places `messages.connection.serverNeedsUpdate` ("This server needs an update before this device can connect." — in the sync state the existing `messages.sync.serverUpdateNeeded` keeps its own wording, which already says changes are saved on the device).
- The changelog says in one line: owners of a server from before the first 1.0 candidates should update the server before the app.
- Test (section 6, item 3): a library with queued changes and pending images connected to a revision-0 server syncs nothing and loses nothing; the same library syncs normally after the fake server reports revision 1.

## 4. User-visible change and the design gate

With LAN discovery kept, **page 1 of Connect to a Server does not change**: the Scan Code section, Servers on This Network and Server Address stay as in 1.0, with their copy, on iPhone, iPad and Mac. The earlier before/after sketches showed only the removal and are dropped. The only new user-visible text is the message for a server below revision 1, so the design gate applies to that message and to where it appears.

### 4.1 Requirements given to the reviewer

- A device connected to a server from builds 9 to 13 (revision 0) must stop syncing without losing or changing anything, with one clear message, and resume when the server is updated (3.5).
- A new device connecting to such a server is told on page 1 and nothing is sent.
- Copy rules: [AGENTS.md](../../AGENTS.md) Copy (plain, no marketing, no exclamation marks, no technical details).
- Accessibility: Dynamic Type and accessibility sizes, VoiceOver (the error on page 1 is announced as other page 1 errors are), keyboard navigation on Mac and iPad, increased contrast.

### 4.2 Copy

| Key | Change |
| --- | --- |
| New `messages.connection.serverNeedsUpdate` | "This server needs an update before this device can connect." Shown on page 1 for a server below revision 1, and from the other entry points of 3.5; replaces `messages.connection.serverNeedsUpdateForDevices` and the other flag-specific variants (section 7). The sync state keeps `messages.sync.serverUpdateNeeded`. |
| Everything on page 1, `settings.connect.nearby.*`, `settings.connect.address.footer`, the Info.plist text | Unchanged |

### 4.3 Per device

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Page 1 | Unchanged | Unchanged | Unchanged |
| Server below revision 1 | The red error row under the form shows `serverNeedsUpdate`; the address stays for correcting | Same | Same |
| A connected device whose server is below revision 1 | Sync Status and Settings > Sync show the existing "server needs an update" state; Add Device, Change Password and Agent Access show `serverNeedsUpdate` instead of hiding themselves | Same | Same |

### 4.4 States

- **Offline or unreachable, Local Network denied:** unchanged (the denied sentence in Servers on This Network, `messages.connection.cannotConnect`).
- **Server older than revision 1:** as above. Nothing is discarded (3.5).
- **Loading:** the busy row "Checking…" is unchanged.

### 4.5 Verification before reporting done

On iPhone, iPad and Mac (Release build), per the project's verification rules: connect a library that has queued changes and pending images to a fake server that reports revision 0 and confirm the message from each entry point and that nothing is lost; update the fake server to revision 1 and confirm syncing resumes with no other action; confirm a 1.0-era server (no `protocolRevision`, all 13 flags) connects, syncs and serves agent access as before; check the message at the largest text size and in dark mode.

## 5. Spec changes (same change as the code)

Spec first ([spec/README.md](../../spec/README.md)); then `python3 spec/tools/check-spec.py`. Discovery pages are not touched.

- `spec/screens/connect-to-server.md` and `spec/flows/connect-to-server.md`: the check table's rows for a server that is too old, the new message, and the removal of the eight-character setup-code tolerance and (with G) Protect Your Journals; `spec/messages.md` and `spec/copy/en.json`: the new key of 4.2 and removal of the unreachable "needs an update before …" keys once code review confirms (section 7).
- `protocol/README.md` (Versioning and capabilities rewritten around `protocolRevision` and the frozen list; Setup and recovery wording for `setup-check`), `protocol/agent-access-server.md` (the capability name `agent-access-2` becomes "revision 1"), `protocol/conformance/README.md` and `sync/README.md` (new `status-v2.json`), `docs/architecture.md` (Server).
- `spec/open-questions.md`: an "Owner decisions of 2026-10-09" note for O (LAN discovery kept; one setup path confirmed).

Documentation outside spec: `docs/self-hosting/README.md` (one first deployment route: the local container, then Tailscale or HTTPS as variations; copy the address and code from the same `setup-code` output; the Mac has no scanner, so it selects a nearby server or types the address), `CHANGELOG.md` (a 1.1 entry, including the one line for owners of servers from builds 9 to 13: update the server before the app).

## 6. Tests worth adding ("Useful tests only")

Add:

1. **Server:** both `/v1/status` and `/v1/server` report `protocolRevision: 1`, `protocolVersion`/`protocolVersions` 1 and a `features` list containing all 13 names, checked against `status-v2.json`. This protects the one thing that would silently break 1.0 apps: a missing flag or a changed major. One test, no mocks.
2. **Swift core:** `status-v2.json` effective-revision cases through `ServerStatus`, table-driven, including 12 flags (refused) and protocol major 2 (update the app). One test file.
3. **Swift core / app model, the gate (3.5):** a library with queued changes and pending images, connected to a fake server below revision 1, syncs nothing and loses nothing (queue, cursor, identity, credential intact), shows the one message from the sync state, Add Device and Agent Access, and syncs normally on the next status read once the fake server reports revision 1. Connecting a new device to such a server stops on page 1 with `serverNeedsUpdate` and sends nothing.

**Shared status builder (review finding 8).** At least twelve Swift test files serve a healthy server as `{"protocolVersion":1,"initialized":true}` or with `"features":[]` (`SyncRecoveryTests`, `MergeJoinTests`, `MergeRetryTests`, `EraseLibraryTests`, `ConnectionRetryTests`, `ChangeWaitingTests`, `SupersededLibraryTests`, `SyncEngineTests`, `SyncHealthTests`, `JournalMeasurements/SyncFixtureServer` and others). After the gate each of those is a refused server. One shared builder returns a healthy status (revision 1, the 13 flags) and the tests migrate to it, so they keep protecting what they were written for; the flag list is not repeated in each file.

**Server:** item 1 also asserts that `agent-access-2` is in the list on both endpoints, so the equivalence "agent guard = revision at least 1" (revision 1 is defined by the full list) cannot erode.

Keep running unchanged as the compatibility proof: `SyncExchangeConformanceTests` against `exchanges-v1.json`, the agent suites, `scripts/test-sync.sh`.

Remove (they protect behaviour that no longer exists): `SyncEngineTests` parameters and cases for a server without continuity, digest, short receipts or waits; the `ServerEnvelopeTests` case for a server without `private-envelope`; the older-setup-code path in `CodeEntry` tests.

Not added: tests that deleted code or copy is gone.

## 7. Dead code and copy that goes with revision 1

Confirmed by the revision rule, to be re-checked by search at implementation time:

- `SyncEngine`: `confirmsContinuity`, `confirmsDigest`, `shortReceipts`, `waitFeature`, `recordKindsFeature`, `updateLibrarySync(available:)` and the store setting `server-record-kinds`; `ServerClient`: `setupCheckFeature`, `privateEnvelopeFeature` and the public-envelope fallback in `recoveryEnvelope()`, `shortReceiptFeature`; `Pairing.feature`, `PairingInvite.feature`, `agentAccessFeature`, `encryptionUpgradeFeature` and their guards (`ConnectionFlow`, `AddDeviceView`, `EncryptionOperations`, `ServerAgentsController`, `AgentCopyClient`).
- `CodeEntry.isOlderSetupCode` and the `.length where !checksCode` branch.
- Messages reachable only from a missing flag: `messages.connection.serverNeedsUpdateForDevices`, "This server needs an update before you can add devices." (pairing), "…change your password.", "…turn on encryption.", "{host} needs an update before agents can connect.", "Pinned entries and journal order stay on this device until the server is updated." All become one message at the revision gate plus the existing sync state. A 404 or 405 on a route a revision-1 server must have means a proxy or another service answered, which the app already reports as `messages.connection.notJournalServer` or `messages.sync.serverUpdateNeeded`.
- `JournalProbe` probes that exercise a server without waits or record kinds.

## 8. Rollout order

1. Spec and protocol text (section 5), `status-v2.json`, the `sync/README.md` row. Spec first.
2. Server: `protocolRevision`, the frozen list, the test. Ship in the 1.1 server image and the standalone package. 1.0 apps are unaffected, so the server can be released before or after the app.
3. Apple app: revision rule, remove the flag branches and the older setup-code path, the one message. One change set so the app never has half the rule.
4. Documentation: the self-hosting route and the changelog line. The Compose files, `deploy/lan/`, `project.yml`, the App Store review notes and the App Privacy answers do not change.

Nothing here needs coordination with the archive work except that both edit `protocol/README.md` and `protocol/conformance/README.md`.

## 9. Owner decisions

Decided (not reopened): 1.1 apps refuse a server below revision 1; 1.1 removes no route from the wire (a consequence of the additive-only rule in [server/AGENTS.md](../../server/AGENTS.md), not a choice); LAN discovery stays; one setup path is as designed in section 2.5 (owner, 2026-10-09). No owner decision remains open in this record.

## 10. Risks

- Servers from builds 9 to 13 stop syncing with 1.1 apps until updated; nothing is lost (3.5). Expected to be none outside the owner's own.
- The frozen list is a permanent commitment: a future server that drops a flag breaks 1.0 apps. The conformance file makes this visible.
- The discovery announcement remains spoofable by anyone on the local network, as `SECURITY.md` already says; the app treats a discovered server as a suggestion only.

## Review log

The independent review of 2026-10-09 follows. The author's response and what changed are recorded after it.

## Independent review (2026-10-09)

Reviewer: an independent design and protocol reviewer, given the requirements and this proposal only. Checked against the code, not against this record's references: every `Map*` call in `server/src` (all routes are in the section 2.2 table; the nine pairing routes include `/challenge`, called at `Pairing.swift:221`), every `/v1/` literal in `apps/apple/JournalApp` and `Packages/JournalCore/Sources` (none for `/v1/server`), `ServerStatus` (a synthesized `Codable`, so unknown members are ignored), the exact `protocolVersion == 1` checks (`ConnectionFlow.swift:118,391`, `SyncEngine.swift:212`), `ServerBrowser.swift`, `deploy/compose.yaml`, `deploy/lan/announce.sh`, `ServerClient.statusOnFirstContact`, `protocol/conformance/sync/exchanges-v1.json`, and the agent surface (`agent-access-2`, `mcpUrl`, `JOURNAL_URL`). Nothing was built or run.

**Verdict: approve with changes.** There is no Blocker. The protocolRevision approach is sound and about as small as it can be, refusing servers older than build 14 is right, removing discovery is safe, and agent access is untouched. Two Material findings change the design (1 and 2); the rest are corrections or wording.

### Findings

1. **Material: a denied Local Network permission becomes a silent dead end for the people most likely to need the LAN.** In 1.0 the permission prompt appeared for every person who opened Connect to a Server, because the browse started there. Many will have chosen Don't Allow without knowing why, including people who later move a server onto the local network. In 1.1 their typed local address waits up to 20 seconds on "Checking…" (`statusOnFirstContact`: `waitsForConnectivity`, 20 s timeout) and then shows the generic `messages.connection.cannotConnect`. The old banner was the only in-app path to the fix, and a troubleshooting page nobody is sent to is not a replacement. The author's reason for no heuristic ("a name does not say whether it resolves to a private address") does not hold for a hint shown only after a failure, where a wrong guess costs one extra sentence. Fix: when the check fails and the host is plausibly local (an IP literal in 10/8, 172.16/12, 192.168/16, 169.254/16 or fc00::/7; a `.local` name; or a single-label name), show a variant of the error: "Couldn’t connect to the server. If it’s on your local network, turn on Local Network for My Journal in Settings." with the Mac wording "…allow My Journal in System Settings > Privacy & Security > Local Network." (new keys `messages.connection.cannotConnectLocalNetwork`, per-platform text like the old `settings.connect.nearby.denied`). Also record in the spec, from the section 4.7 device checks, what URLSession reports when the permission is denied (TN3179) and whether the 20-second wait can be skipped once denied. The 4.7 checks that Tailscale and public addresses never prompt are the only evidence for the privacy gain claimed in 2.4; they must be done before the review notes and App Privacy answers change, not after.

2. **Material: refusing servers without all 13 flags changes what already-connected devices do, and the record covers only page 1.** Today a device connected to a build 9 to 13 server degrades (polling, no short receipts, pins stay local). After the update it stops syncing. The record names the page 1 message and "sync state keeps `messages.sync.serverUpdateNeeded`" but does not say what happens to a device that is already paired, with queued changes, pending images, agents and a Devices list. Fix: state and test that (a) the refusal is a pure gate: nothing queued, cursor, identity or credential is changed or discarded, and syncing resumes unchanged when the server is updated; (b) the Add Device, Change Password and Agents entry points show the same one message rather than each hiding itself; (c) the refusal is evaluated per status read (the status is cached as `statusRead`), so it clears as soon as the server is updated. This is the test to add beside item 3 of section 6, with a library that has queued changes. Owners of build 9 to 13 servers should be told in the changelog, one line: update the server before the app.

3. **Minor: protocolRevision is sound. Keep it, and tighten five points.** It is additive within `/v1`, invisible to 1.0 apps (verified: they decode `ServerStatus` leniently and gate on `protocolVersion == 1`, which stays 1), and derivable from the frozen list for 1.0 servers. The honest justification is not that anything changes now (the 1.1 server reports 1 and nothing observable moves) but that every 1.1 client, including Windows, must contain the rule before the first revision 2 exists; say that in 3.1, because otherwise it reads as speculative. Then: (a) define a malformed `protocolRevision` (not an integer, 0, negative, above 2^31−1) as absent, so a broken value cannot lock a client out or let it skip the flag check; (b) say in the rules that a client gates each post-1.0 behaviour on `revision >= N` and never on a flag, and that a server never drops a flag when it raises its revision (the conformance file pins the flags; a lower revision after a server restore is legitimate, as the downgrade case in 3.3 says, so clients re-read it on every status read and never cache it); (c) `/v1/server` has no `protocolVersion`, so the effective-revision rule needs "if `protocolVersions` is present use its maximum" or a statement that clients read `/v1/status` only; (d) `status-v2.json` follows the folder rule (a new file beside the old), but the "2" collides with `/v2`, archive format 2 and recovery format 2; add a line to `sync/README.md` that it is the second file version for the status contract, not a protocol version; (e) record in the protocol README that `/v1/server` also returns `mcpUrl` and `mcpUnavailable` (the code and agent-access-server.md say so; the Versioning list does not).

4. **Minor: the route audit holds, and keeping every route is right.** I found no route in `server/src` that is not in the 2.2 table, and no Apple call site for a route that is not. `GET /v1/server` is the only route without a caller; removing it would break the `server-capabilities` step in `exchanges-v1.json`, which the conformance rules forbid editing. Owner decision 3 is not a decision: additive-only is a standing rule in `server/AGENTS.md`, so say it as a consequence.

5. **Minor: removing discovery is safe, with two additions.** The audience was always small: the announcer refuses a `JOURNAL_URL` that is not `https://` (`announce.sh`) and the app drops non-HTTPS results (`ServerBrowser.servers(in:)`), and the app accepts plain `http` only for loopback (`ServerClient.swift:171`), so everyone who used the list had a real certificate and a name they could type. 1.0 apps keep working against a 1.1 server whether or not an announcer runs. Additions: (a) Compose does not stop a service that was removed from the file; someone who started `--profile lan` keeps a host-network Avahi container announcing forever. The upgrade note in `docs/self-hosting/README.md` and the changelog must say `docker compose up -d --remove-orphans` (or `docker rm -f` the container, and the `journal-lan:local` image), not only "remove the service"; (b) the Mac has no scanner, so typing the address is its only route. `setup-code` already prints the address when `JOURNAL_URL` is set; make the self-hosting guide say to copy that address and code from the same output, as the one setup path.

6. **Minor: agent access is unaffected, as claimed.** Verified: the app reads `agent-access-2` and `mcpUrl` from `/v1/status` only; MCP clients use `/mcp`, `/.well-known/*` and `/oauth/*`, none of which read flags, the revision or anything discovery-related; nothing in `server/src` or `apps/apple` outside the browser uses Bonjour; `JOURNAL_URL` feeds `PublicOrigin` and stays on the `journal` service. One caution: the 1.1 app's agent guard changes from "has `agent-access-2`" to "revision at least 1", which is equivalent only because revision 1 is defined by the full 13-flag list; keep a server test that asserts `agent-access-2` is in the list on both endpoints (item 1 of section 6 covers it) so the equivalence cannot erode.

7. **Minor: copy and the one visible screen.** Removing the section and adding nothing is right, and the proposal's own conclusion that a first sentence like "Enter the HTTPS address of your server." is redundant is correct. The footer is now the only help on the page and it is Tailscale-specific; people with a public host or a local name get no hint of where the address comes from. Suggested footer, if the owner wants one line: "Use the HTTPS address your server shows when you set it up. For Tailscale, connect to your tailnet first." (check against the Mac sheet's height). `messages.connection.serverNeedsUpdate` ("This server needs an update before this device can connect.") fits the existing `messages.sync.serverUpdateNeeded` family and has no marketing language or exclamation mark; it does not say how to update, which is acceptable because only the server's owner sees it. For the Info.plist string, Apple prefixes its own sentence, so "Sync with your server on your local network." reads acceptably; "Connect to your server on your local network to sync." is closer to Apple's own examples. Either is fine.

8. **Minor: test churn is larger than section 6 says.** At least twelve Swift test files serve a healthy server as `{"protocolVersion":1,"initialized":true}` or with `"features":[]` (`SyncRecoveryTests`, `MergeJoinTests`, `MergeRetryTests`, `EraseLibraryTests`, `ConnectionRetryTests`, `ChangeWaitingTests`, `SupersededLibraryTests`, `SyncEngineTests`, `SyncHealthTests`, `JournalMeasurements/SyncFixtureServer` and others). After the revision gate every one of them is a refused server. Add one shared status builder that returns revision 1 with all 13 flags and migrate the tests to it, so they keep protecting the behaviour they were written for. Do not fix them by sprinkling the flag list.

9. **Minor: owner decisions.** 1 (what "one setup path" means) is the only real question, and the record's reading is the cautious one; recommend deciding it as designed and telling the owner in one line. 2 follows scope item D and the repository history (the flags exist from the first commit, build 9; only build 14 added `record-kinds`, so only TestFlight servers lack any): decide it. 3 is not a decision (finding 4).

Nothing else in the record needs to change before implementation. Re-review is not needed if findings 1 and 2 are adopted as written; if the author chooses another fix for 1, show it to a reviewer.

## Changes after review

Verdict of the review: approve with changes, no Blocker. Decided by the lead and not reopened: refusing servers below revision 1 (3.5), and no route removed from the 1.1 wire.

| # | Finding | Change |
| --- | --- | --- |
| 1 | Material: a denied Local Network permission is a silent dead end | Moot after the owner kept LAN discovery: the browse still asks for the permission and the existing denied sentence stays on page 1. The hint, its key and the host rule are not added (2.4); they return as a follow-up only if the device checks show a gap. |
| 2 | Material: refusing old servers must be a pure gate | New 3.5: nothing queued, no cursor, identity or credential changes; one message from every entry point; evaluated on each status read so it clears when the server is updated; changelog line; test 3 with a library that has queued changes and pending images. |
| 3 | Minor: tighten protocolRevision | 3.1: reason stated (every 1.1 client must contain the rule before revision 2 exists); malformed value counts as absent; gate on `revision >= N`, never on a flag, never drop a flag; re-read on every status read; `/v1/server` uses the maximum of `protocolVersions`; `status-v2.json` named as a file version, with a line in `sync/README.md`; `/v1/server`'s `mcpUrl` and `mcpUnavailable` recorded in the protocol README. New fixture cases for malformed values. |
| 4 | Minor: route audit; owner decision 3 is not a decision | Recorded as a consequence in section 1 and section 9. |
| 5 | Minor: discovery removal additions | Moot for removal (discovery stays). Kept: the guide names the one setup path with the address and code from the same `setup-code` output. |
| 6 | Minor: agent access unaffected | Kept; test 1 asserts `agent-access-2` is in the list on both endpoints so the equivalence with "revision at least 1" cannot erode. |
| 7 | Minor: copy | Moot: page 1 and the Info.plist text do not change. `serverNeedsUpdate` stands as reviewed. |
| 8 | Minor: test churn | Section 6: one shared healthy-status builder; the twelve-plus test files migrate to it rather than repeating the flag list. |
| 9 | Minor: owner decisions | Section 9: none open; the setup path is confirmed. |

Owner decision of 2026-10-09 after the review: **LAN discovery stays.** The record was revised accordingly (sections 1, 2.4, 3, 4, 5, 8, 10); everything else stands.

## Owner decisions (2026-10-09)

- **One setup path:** confirmed with LAN discovery kept (owner, 2026-10-09).
- **LAN discovery:** kept, unchanged (owner, 2026-10-09: "I love it").

## Implementation notes

Phase 6 (2026-10-09). Where the code differs from the text above:

- **Library record gate.** Section 3.1 says the store setting `server-record-kinds` is no longer read or written. The store still needs to tell a library that has never synchronized from one that has: a device with no server must not queue the library record (pins and journal order) as unsent work. The setting is kept under the same key with one meaning, "this library has synchronized with a server", written `1` at the start of every synchronization; a `0` left by 1.0 reads as "not yet" and is replaced at the next one. `waitingForServer` and its footer text are gone.
- **`waitingSupported`.** Removed from the sync report and the change watcher too: every revision 1 server holds waits, so the watcher owns the schedule after any settled synchronization.
- **Messages.** `messages.connection.serverNeedsUpdate` replaces `messages.connection.serverNeedsUpdateForDevices`, `messages.pairing.serverOutdated`, `messages.password.serverOutdated`, `messages.encryption.serverOutdated`, `settings.agents.connect.needsUpdate` and `messages.library.waitingForServer`. The sync state keeps `messages.sync.serverUpdateNeeded`. One typed error carries the gate in the core: `ServerRefusal`.
- **Fixtures.** `sync/status-v2.json` has a few more malformed-revision cases than listed in 3.1 (a decimal, a boolean, null, and the largest valid revision); the status that `exchanges-v1.json` records for the client check lists only some of the 13 names, so the Swift test no longer treats it as a healthy server.
- **Probes and scripts.** The `wait-old`, `library-held` and `library-released` probes exercised servers without waits or record kinds and are gone; `scripts/test-sync-efficiency.sh` still runs a 1.0 server against the new client when `JOURNAL_BASELINE_DIR` is set.
- **`--remove-orphans`.** Not needed: the `lan` service stays, so no service leaves the Compose files.
