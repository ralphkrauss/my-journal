# 1.1 server cleanup (simplification O) — 2026-10-09

Status: design for the owner and for the mandatory design gate in [AGENTS.md](../../AGENTS.md). Nothing is built. The independent review (appended below) approved it with changes; this body includes them, and [Changes after review](#changes-after-review) maps each finding to its change. Scope record: [release-1-1-scope.md](release-1-1-scope.md), item O. The archive half of the 1.1 protocol work is in [1-1-archive-v2.md](1-1-archive-v2.md).

Item O has four parts: capability flags become one protocol version, unused endpoints go, LAN discovery goes (the Bonjour announcer, the app's nearby-server suggestions and the permission they needed), and there is one setup path. The MCP agent access has to keep working. Version 1.0 (build 19) is in App Review and will be public before 1.1 ships, so every 1.0 app and every 1.0 server people run has to work with 1.1 ones in both directions.

## 1. What this record decides

| Part | Result |
| --- | --- |
| Capability flags | Replaced for new code by one integer, `protocolRevision`, on `/v1/status` and `/v1/server`. The 13-flag `features` list is frozen: 1.0 apps read it, so it stays on every server for as long as `/v1` exists, and it is never extended. A 1.1 app reads the revision, or derives revision 1 from a complete legacy list, and has no per-flag branches. 1.1 apps refuse a server below revision 1 (decided); the refusal changes and discards nothing, and clears when the server is updated. |
| Unused endpoints | Evidence below: every route is called by a 1.0 app or is documented infrastructure, except `GET /v1/server`, which no client calls but which is a documented part of `/v1` and a conformance step. Within wire major 1 a removal is a breaking change ([server/AGENTS.md](../../server/AGENTS.md)). So 1.1 removes no route: that is a consequence of the additive-only rule in [server/AGENTS.md](../../server/AGENTS.md), not a choice. It records which routes 1.1 apps stop calling and removes them with `/v2`. |
| LAN discovery | Removed everywhere: the `lan` Compose profile and `deploy/lan/`, `ServerBrowser`, the Servers on This Network section, `NSBonjourServices`, the Bonjour copy and docs. `NSLocalNetworkUsageDescription` stays, reworded, because connecting to a typed address on the local network still triggers the system prompt; a failed connection to a plausibly local host says where to turn Local Network on. |
| One setup path | Setting up means: Connect to a Server, enter the address (or scan a code), enter the setup code, choose a master password. The tolerated older paths go (eight-character setup codes, servers without `setup-check`, choosing a server from a list). |
| MCP agent access | Unaffected. It depends on `/v1/status` (`mcpUrl`, `agent-access-2`), `/v1/agents*`, `/v1/agent-requests*`, `/mcp`, `/oauth/*`, the well-known documents and `JOURNAL_URL`/`Journal:PublicUrl`. Nothing in this design touches them. |

## 2. Current state, with evidence

### 2.1 What agent access depends on (checked first)

| Dependency | Where | Kept? |
| --- | --- | --- |
| Capability `agent-access-2` read before listing or approving agent requests | `AgentCopyClient.swift` (`agentAccessFeature`, guard in `status().supports`, line ~114), `ServerAgentsController.swift:51` | Yes: still in the frozen list; the 1.1 app reads it as part of revision 1. |
| The MCP address `mcpUrl` / `mcpUnavailable` from `GET /v1/status` | `ServerAgentsController.swift:55`, `ServerClient.swift:20-23`, `AgentProbe.swift`; produced by `AccountEndpoints.cs` and `PublicOrigin.cs` | Yes, unchanged. |
| Device-authenticated agent endpoints | `GET /v1/agents/`, `PUT|DELETE /v1/agents/{id}`, `GET|POST /v1/agents/{id}/items`, `GET /v1/agents/{id}/activity`, `GET /v1/agent-requests/`, `GET /v1/agent-requests/{id}`, `POST …/approve|ready|decline`: all called from `AgentCopyClient.swift` lines 105-215 | Yes, unchanged. |
| Agent-facing surface | `POST /mcp`, `/.well-known/oauth-protected-resource/mcp`, `/.well-known/oauth-authorization-server`, `/oauth/register|authorize|authorize/wait|authorize/status|token|revoke` ([protocol/agent-access-server.md](../../protocol/agent-access-server.md)). `/oauth/authorize/wait` is the page's no-JavaScript refresh and `/oauth/authorize/status` the scripted poll (`AuthorizationPage.cs:22,94`) | Yes, unchanged. |
| The public origin | `Journal:PublicUrl`, else `JOURNAL_URL` (`PublicOrigin.cs:55-72`, [protocol/agent-access-server.md](../../protocol/agent-access-server.md) Addresses) | Yes. `JOURNAL_URL` stays in `deploy/compose.yaml` and `deploy/compose.tailscale.yaml` for the `journal` service; only the `lan` service's copy of it goes. |
| Anything using Bonjour, `sync-wait`, `/v1/server` or LAN discovery | Searched `server/src`, `apps/apple` (incl. `JournalProbe`), `protocol/` | None. The agent copy is published after a sync from synchronized state and never browses the network. |

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

### 2.4 LAN discovery

| Piece | Where |
| --- | --- |
| Announcer | `deploy/lan/` (`Dockerfile`, `announce.sh`, `avahi-daemon.conf`); `lan` service with profile `lan` in `deploy/compose.yaml:25-44` and `deploy/compose.tailscale.yaml:41-60`; `image: journal-lan:local` |
| Client browse | `apps/apple/JournalApp/Model/ServerBrowser.swift` (`NWBrowser`, `_myjournal._tcp`, TXT `v=1` and `url`), started and stopped by `ConnectionView.swift` (`choosing`, `browse`, `searchedLong`, the `Servers on This Network` section, `localNetworkDenied`, lines 21, 63, 93-100, 124-154, 177) |
| Permission and declarations | `apps/apple/project.yml:30-31` and `79-80` (`NSLocalNetworkUsageDescription`, `NSBonjourServices`), both targets |
| Screenshot tooling | `JournalScreenshots/Mac/SpecMacSyncStates.swift:43`, `JournalScreenshots/iOS/SpecCaptureCase.swift`, `SpecSyncCaptureTests.swift:25` (skip a capture when servers are found) |
| Docs and spec | `docs/self-hosting/README.md` (section Finding the server on your network, and a line in Running the server on a Mac), `docs/guide/sync.md` step 3, `README.md:91`, `PRIVACY.md:40`, `SECURITY.md` (paragraph on the `lan` profile and the spoofing remark in Hosting), `docs/app-store/app-privacy.md:32`, `docs/app-store/review-notes.md:47`, `docs/app-store/screenshots-plan.md:235`, `design/spec-screenshots/README.md:23`, `CHANGELOG.md`, spec pages (section 8) |
| Windows plan | `spec/platforms/windows/platform.md` section 32 (DNS-SD with `DnssdServiceWatcher`) and `screens/connect-to-server.md`: planned, not built |

Does anything else need the local network permission? Yes, one thing. `ServerClient.statusOnFirstContact()` exists because a connection to an address on the local network makes the system ask for permission and fail while it asks (TN3179; the comment at `ServerClient.swift:298-300`, the spec step "waits up to 20 seconds for the local network permission prompt"). A person whose server is on the local network (a host with a private address or a `.local` name, behind a certificate they can use) still triggers the prompt when they type its address. The prompt's text is `NSLocalNetworkUsageDescription`. So:

- `NSBonjourServices` goes. Without a browse nothing needs it.
- `NSLocalNetworkUsageDescription` stays, with text that no longer says "Find": **"Sync with your server on your local network."** (was "Find and sync with your server on your local network.").
- The prompt now appears only for people whose server is on their local network, when they first connect. Today it appears for everyone on first opening Connect to a Server, because the browse starts there, including people who use Tailscale or a public host. That is a privacy gain, and it is why the 1.0 review notes (`review-notes.md:47`) change.
- To verify on devices (not assumed): a Tailscale `.ts.net` address and a public host name do not show the prompt; a `192.168.x.x`-style address, or a name that resolves to one, does, on iPhone, iPad and a Mac.

### 2.5 Setup paths today

The ways to start syncing, from `flows/connect-to-server`:

1. Choose from Servers on This Network (goes).
2. Type the address (stays).
3. Scan a code from a connected device (stays; this is joining, not setup).
4. Setup code, three variants: six-character code checked by `setup-check`; an older eight-character code tolerated when the server cannot check (`CodeEntry.isOlderSetupCode`, `ConnectionFlow.swift:157-160`); the server regenerating an old-format code file at start (`SetupCode`, server only; harmless, stays).
5. Protect Your Journals with Encrypt or Don't Encrypt (goes with simplification G, designed elsewhere).
6. On the host: three Compose files (local, Tailscale, HTTPS) and the standalone package. These are hosting choices, not alternatives for the same step; each prints a setup code with `setup-code`.

"One setup path" is read here as: a person sets up a server one way in the app, and the repository documents one first route (the local container, then Tailscale or HTTPS as variations of where it runs). See owner decision 1.

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
| **1.0 app** | As today | Works exactly as today: same routes, same `protocolVersion: 1`, same flags; it ignores the new member (its `ServerStatus` is a Swift `Codable` that skips unknown keys). A 1.0 app browsing for `_myjournal._tcp` finds nothing when no announcer runs and shows "No servers found on this network." | As today (degrades per flag) |
| **1.1 app** | Works: revision 1 derived from the complete list | Works: reads `protocolRevision` | Refused (section 3.5). Changed from today, when the app degrades |
| **Windows/Android client written to 1.1** | Works | Works | Refused |

Other directions covered:

- **Server downgrade** (restoring a 1.0 backup into a 1.0 server, [server-backup.md](../../protocol/server-backup.md)): the list is the same, the field disappears, 1.1 apps derive revision 1.
- **Existing `lan` announcers.** Someone who started `--profile lan` from an older compose file keeps a working announcer container; 1.1 apps ignore it and 1.0 apps still list it. Nothing breaks. The 1.1 documentation says to remove the service.
- **Wire fixtures.** `exchanges-v1.json` replays unchanged against the 1.1 server (it asserts a subset). `status-v2.json` is additive.
- **Local libraries** never contain a flag or a discovered server. The one persisted item that depends on a flag, the `server-record-kinds` setting in the store, is no longer read or written by 1.1 and stays readable as an unknown key ([protocol/archive.md](../../protocol/archive.md) already says readers ignore keys they don't know).

### 3.4 What the server code does

- `AccountEndpoints.cs`: add a `ProtocolRevision = 1` constant next to `ProtocolVersions`; return it from both endpoints; keep `Features` as a literal list with a comment "frozen: 1.0 apps read these (protocol/README.md)". The per-feature constants `SyncEndpoints.ContinuityDigestFeature`, `ShortReceiptFeature`, `WaitFeature`, `RecordKindsFeature` and `EncryptionEndpoints.Feature` have no other use and fold into that literal.
- `deploy/`: remove `deploy/lan/` and the `lan` service in both Compose files; keep `JOURNAL_URL` on the `journal` service.
- No database change, no migration. A 1.1 server starts on a 1.0 database and a 1.0 server on a 1.1 database ([server/AGENTS.md](../../server/AGENTS.md)).

### 3.5 Refusing an old server: a gate, nothing else

Servers from builds 9 to 13 (decided: refused) are the only ones this touches. The refusal is evaluated on each status read and is a pure gate:

- **Nothing is changed or discarded.** Queued changes, pending images, the sync cursor and identity, the device credential, agent grants and the Devices list stay exactly as they are. Syncing, Add Device, Change Password and Agent Access resume with no other action as soon as a status read shows revision 1 or more, because the revision is never cached beyond a read.
- **One message from every entry point.** Connect to a Server (page 1), the sync state, Add Device, Change Password, Turn On Encryption (if it still exists) and Agent Access all show the same text rather than each hiding itself or saying something else: on page 1 and in the other places `messages.connection.serverNeedsUpdate` ("This server needs an update before this device can connect." — in the sync state the existing `messages.sync.serverUpdateNeeded` keeps its own wording, which already says changes are saved on the device).
- The changelog says in one line: owners of a server from before the first 1.0 candidates should update the server before the app.
- Test (section 6, item 3): a library with queued changes and pending images connected to a revision-0 server syncs nothing and loses nothing; the same library syncs normally after the fake server reports revision 1.

## 4. User-visible change and the design gate

The only screen that changes is page 1 of Connect to a Server. This section is the proposal the independent reviewer sees.

### 4.1 Requirements given to the reviewer

- A person with a Tailscale, public or local-network server must still be able to start syncing without help, by typing an address or, on an iPhone or iPad with a camera, scanning a code on a connected device.
- The page must not suggest unverified servers.
- The Local Network permission must not appear unless a connection needs it.
- Copy rules: [AGENTS.md](../../AGENTS.md) Copy (plain, no marketing, no exclamation marks, no technical details).
- Accessibility: Dynamic Type and accessibility sizes, VoiceOver, keyboard navigation on Mac and iPad, increased contrast.

### 4.2 Page 1 before and after

Today (all devices, abridged; Scan Code only where a camera exists):

```
Connect to a Server                  [Cancel]  [Continue]
 [ Scan Code ]    (iPhone, iPad)
   On a connected device, open Settings > Devices > Add Device, then scan the code it shows.
 SERVERS ON THIS NETWORK
   nas.example.com        My Journal on nas      (rows come and go)
   Looking for servers…   / No servers found on this network. / the denied sentence
 SERVER ADDRESS
   [ https://journal.example.ts.net ]
   For Tailscale, use your server’s HTTPS address while connected to your tailnet.
```

Proposed:

```
Connect to a Server                  [Cancel]  [Continue]
 [ Scan Code ]    (iPhone, iPad with a camera only)
   On a connected device, open Settings > Devices > Add Device, then scan the code it shows.
 SERVER ADDRESS
   [ https://journal.example.ts.net ]
   For Tailscale, use your server’s HTTPS address while connected to your tailnet.
```

The Servers on This Network section, its three status lines and the denied sentence are removed. Nothing is added.

### 4.3 Per device

| | iPhone | iPad | Mac |
| --- | --- | --- | --- |
| Page | Sheet with a grouped form: Scan Code section, then Server Address. Compact width, full-screen scanner as today. | Same form in a sheet; Scan Code on models with a camera. | Sheet about 480 pt wide; no scanner (`canScan` is false), so the page is the Server Address section alone. Return in the field continues, as today. The sheet's `minHeight` of 300 (`ConnectionView.swift`) is checked for a half-empty look; reduce it if needed. |
| Permission | No prompt when the sheet opens. A system prompt appears on the first connection to a local-network address, with the new text. | Same. | Same, on macOS versions that ask for Local Network access. |
| Denied permission | A failed connection to a plausibly local host shows `messages.connection.cannotConnectLocalNetwork` with the Settings path (4.5). | Same. | Same, with the System Settings path. |
| Screenshots | `connect-to-server-address` is captured without the "unless showing Servers on This Network" guard. | Same. | `SpecMacSyncStates` drops its `ServerBrowser` use. |

### 4.4 Copy

Exact strings; keys in `spec/copy/en.json`:

| Key | Change |
| --- | --- |
| `settings.connect.nearby.header`, `.looking`, `.none`, `.denied` | Removed |
| `settings.connect.address.footer` | Unchanged: "For Tailscale, use your server’s HTTPS address while connected to your tailnet." Review finding 7: the footer is now the only help on the page and it is Tailscale-specific. Proposed replacement, to be checked against the Mac sheet's height: "Use the HTTPS address your server shows when you set it up. For Tailscale, connect to your tailnet first." (`setup-code` prints that address when `JOURNAL_URL` is set.) |
| New `settings.permission.localNetwork` (an Info.plist value, which closes B42's local network half) | "Sync with your server on your local network." (Apple prefixes its own sentence; the alternative "Connect to your server on your local network to sync." is closer to Apple's examples; either is acceptable.) |
| New `messages.connection.cannotConnectLocalNetwork` (per-platform text, like the removed `settings.connect.nearby.denied`) | "Couldn’t connect to the server. If it’s on your local network, turn on Local Network for My Journal in Settings." Mac: "Couldn’t connect to the server. If it’s on your local network, allow My Journal in System Settings > Privacy & Security > Local Network." Shown instead of `messages.connection.cannotConnect` when the check fails and the host is plausibly local (4.5). |
| New `messages.connection.serverNeedsUpdate` | "This server needs an update before this device can connect." Shown on page 1 for a server below revision 1; replaces `messages.connection.serverNeedsUpdateForDevices` and the other flag-specific variants (section 7). Sync state keeps `messages.sync.serverUpdateNeeded`. |

### 4.5 States

- **Offline or unreachable:** unchanged (`messages.connection.cannotConnect`, `…Tailscale` for `.ts.net`).
- **Local Network denied:** the check fails after the wait (`statusOnFirstContact` waits up to 20 seconds). When the host is *plausibly local* the page shows `messages.connection.cannotConnectLocalNetwork` instead of `messages.connection.cannotConnect`. Plausibly local means: an IPv4 literal in 10/8, 172.16/12, 192.168/16 or 169.254/16, an IPv6 literal in fc00::/7 or fe80::/10, a name ending in `.local`, or a single-label name. A wrong guess costs one extra sentence; a name that resolves to a private address but looks public gets the plain error. This replaces the old banner, which was the only in-app path to the setting (1.0 asked for the permission of everyone who opened the sheet, so many people answered Don't Allow without knowing why), and `docs/guide/troubleshooting.md` repeats the instruction. The spec records, from the on-device check in 4.7, what URLSession reports when the permission is denied (TN3179) and whether the 20-second wait can be skipped once it is denied.
- **Server older than revision 1:** the new `serverNeedsUpdate` message on page 1 and the same text from every other entry point (3.5); the address stays for correcting. Nothing is discarded.
- **Loading:** the busy row "Checking…" is unchanged.

### 4.6 Accessibility

Fewer rows, no live-updating list, so no announcement of results appearing. The Scan Code button and address field keep their labels. Nothing else changes.

### 4.7 Verification before reporting done

The no-prompt checks for Tailscale and public addresses are the only evidence for the privacy gain claimed in 2.4. They are done **before** the App Store review notes and the App Privacy answers change, not after.

On iPhone, iPad and Mac (Release build), per the project's verification rules: open Connect to a Server with Local Network never granted and confirm no prompt; connect to a Tailscale address and to a local-network address and note when the prompt appears; deny it and confirm `messages.connection.cannotConnectLocalNetwork` appears for that host, writing down what URLSession reports when denied (TN3179) and whether the 20-second wait ends early; check at the largest text size and in dark mode; confirm the built Info.plist has `NSLocalNetworkUsageDescription` and no `NSBonjourServices` (`plutil -p` on the built app).

## 5. Spec changes (same change as the code)

Spec first ([spec/README.md](../../spec/README.md)); then `python3 spec/tools/check-spec.py`.

- `spec/screens/connect-to-server.md` (page 1: remove item 2, the rules at lines ~221-222 and 233, the sources list entry `ServerBrowser.swift`), `spec/flows/connect-to-server.md` (step 1: remove "Choose a server on this network"; the check table keeps the rest; the line about the 20-second wait keeps "local network permission" because typed addresses still use it), `spec/commands.md` row `connect-check-server` ("a nearby server row" goes), `spec/messages.md` and `spec/copy/en.json` (keys in 4.4, including `messages.connection.cannotConnectLocalNetwork`, with the plausibly-local rule and the recorded URLSession behaviour in `flows/connect-to-server`; remove the unreachable "needs an update before …" keys once code review confirms, section 7).
- `spec/parity.yaml`: `server-discovery` becomes `not-applicable` on every platform with reason "Removed in 1.1 (simplification O); servers are found by address or a scanned code" (the file keeps removed features so nobody rebuilds them); `server-setup`, `sync-connect` and `connect-to-server` front matter drop the feature id.
- `spec/platforms/apple/platform.md` section 32 (Discovery, Permission, Sandbox bullets), `spec/platforms/apple/screens/connect-to-server.md`, `spec/platforms/apple/flows/connect-to-server.md`; new screenshots from the capture script.
- `spec/platforms/windows/platform.md` section 32 and rows at lines ~430 and ~815, `screens/connect-to-server.md`, `commands.md`, `copy-proposals.md`: delete the DNS-SD plan and the nearby list.
- `spec/open-questions.md`: B42 is answered for the local network text; add an "Owner decisions of 2026-10-09/10" note for O.
- `protocol/README.md` (Versioning and capabilities, Setup and recovery wording for `setup-check`), `protocol/agent-access-server.md` (the capability name `agent-access-2` becomes "revision 1"), `protocol/conformance/README.md` and `sync/README.md` (new file), `docs/architecture.md` (Server).

Documentation outside spec: `docs/self-hosting/README.md`, `docs/guide/sync.md` (step 3 loses "Choose your server under Servers on This Network, or"), `docs/guide/troubleshooting.md` (above), `README.md`, `PRIVACY.md` (the sentence about Bonjour goes), `SECURITY.md` (the `lan` paragraph and the fake-announcement example in Hosting go), `docs/app-store/app-privacy.md`, `review-notes.md`, `screenshots-plan.md`, `design/spec-screenshots/README.md`, `CHANGELOG.md` (a 1.1 entry; the Unreleased paragraph that announces Connect to a Server listing nearby servers describes 1.0 and stays as history).

## 6. Tests worth adding ("Useful tests only")

Add:

1. **Server:** both `/v1/status` and `/v1/server` report `protocolRevision: 1`, `protocolVersion`/`protocolVersions` 1 and a `features` list containing all 13 names, checked against `status-v2.json`. This protects the one thing that would silently break 1.0 apps: a missing flag or a changed major. One test, no mocks.
2. **Swift core:** `status-v2.json` effective-revision cases through `ServerStatus`, table-driven, including 12 flags (refused) and protocol major 2 (update the app). One test file.
3. **Swift core / app model, the gate (3.5):** a library with queued changes and pending images, connected to a fake server below revision 1, syncs nothing and loses nothing (queue, cursor, identity, credential intact), shows the one message from the sync state, Add Device and Agent Access, and syncs normally on the next status read once the fake server reports revision 1. Connecting a new device to such a server stops on page 1 with `serverNeedsUpdate` and sends nothing.
4. **Swift core:** the plausibly-local host rule (the IP ranges, `.local`, single-label names, and hosts that must not match such as `journal.example.ts.net` and `example.com`) as a table-driven test of the function that chooses between the two connection errors.

**Shared status builder (review finding 8).** At least twelve Swift test files serve a healthy server as `{"protocolVersion":1,"initialized":true}` or with `"features":[]` (`SyncRecoveryTests`, `MergeJoinTests`, `MergeRetryTests`, `EraseLibraryTests`, `ConnectionRetryTests`, `ChangeWaitingTests`, `SupersededLibraryTests`, `SyncEngineTests`, `SyncHealthTests`, `JournalMeasurements/SyncFixtureServer` and others). After the gate each of those is a refused server. One shared builder returns a healthy status (revision 1, the 13 flags) and the tests migrate to it, so they keep protecting what they were written for; the flag list is not repeated in each file.

**Server:** item 1 also asserts that `agent-access-2` is in the list on both endpoints, so the equivalence "agent guard = revision at least 1" (revision 1 is defined by the full list) cannot erode.

Keep running unchanged as the compatibility proof: `SyncExchangeConformanceTests` against `exchanges-v1.json`, the agent suites, `scripts/test-sync.sh`.

Remove (they protect behaviour that no longer exists): `SyncEngineTests` parameters and cases for a server without continuity, digest, short receipts or waits; the `ServerEnvelopeTests` case for a server without `private-envelope`; the older-setup-code path in `CodeEntry` tests; the `lan` parts of any deployment script (none reference it today).

Not added: tests that Info.plist lacks a key, that a Compose file lacks a service, or that deleted views are gone.

## 7. Dead code and copy that goes with revision 1

Confirmed by the revision rule, to be re-checked by search at implementation time:

- `SyncEngine`: `confirmsContinuity`, `confirmsDigest`, `shortReceipts`, `waitFeature`, `recordKindsFeature`, `updateLibrarySync(available:)` and the store setting `server-record-kinds`; `ServerClient`: `setupCheckFeature`, `privateEnvelopeFeature` and the public-envelope fallback in `recoveryEnvelope()`, `shortReceiptFeature`; `Pairing.feature`, `PairingInvite.feature`, `agentAccessFeature`, `encryptionUpgradeFeature` and their guards (`ConnectionFlow`, `AddDeviceView`, `EncryptionOperations`, `ServerAgentsController`, `AgentCopyClient`).
- `CodeEntry.isOlderSetupCode` and the `.length where !checksCode` branch.
- `ServerBrowser.swift`; `ServerAddress` is defined there and used in nine other places, so it moves to its own file first.
- Messages reachable only from a missing flag: `messages.connection.serverNeedsUpdateForDevices`, "This server needs an update before you can add devices." (pairing), "…change your password.", "…turn on encryption.", "{host} needs an update before agents can connect.", "Pinned entries and journal order stay on this device until the server is updated." All become one message at the revision gate plus the existing sync state. A 404 or 405 on a route a revision-1 server must have means a proxy or another service answered, which the app already reports as `messages.connection.notJournalServer` or `messages.sync.serverUpdateNeeded`.
- `JournalProbe` probes that exercise a server without waits or record kinds.

## 8. Rollout order

1. Spec and protocol text (this record's section 5), `status-v2.json`, the `sync/README.md` row. Spec first.
2. Server: `protocolRevision`, the frozen list, the test. Ship in the 1.1 server image and the standalone package. 1.0 apps are unaffected, so the server can be released before or after the app.
3. Apple app: revision rule, remove branches and discovery, `project.yml`, permission text, screenshots. One change set so the app never has half the rule.
4. Deployment and docs: delete `deploy/lan/` and the `lan` services in the same release as the app change. Dependabot's `/deploy` entries need no change. Compose does not stop a service that was removed from the file: someone who started `--profile lan` keeps a host-network Avahi container announcing indefinitely. `docs/self-hosting/README.md` and the changelog therefore say `docker compose up -d --remove-orphans` (or `docker rm -f` the container and remove the `journal-lan:local` image). The self-hosting guide also names the one setup path: copy the address and the code from the same `setup-code` output (it prints `JOURNAL_URL` with the code) and type the address in the app; the Mac has no scanner, so typing is its only route.
5. App Store: update the review notes and the privacy answers (the app no longer browses the network) with the 1.1 submission.

Nothing here needs coordination with the archive work except that both edit `protocol/README.md` and `protocol/conformance/README.md`.

## 9. Owner decisions

Decided (not reopened): 1.1 apps refuse a server below revision 1; 1.1 removes no route from the wire (a consequence of the additive-only rule in [server/AGENTS.md](../../server/AGENTS.md), not a choice).

1. **Confirm what "one setup path" means.** The scope record is one line. This design reads it as section 2.5: remove the nearby list, the eight-character-code tolerance and (with G) the Don't Encrypt branch, and document one first deployment route with the address and code copied from the same `setup-code` output. If the owner meant something larger (dropping the Tailscale or HTTPS Compose files, or changing the setup code itself), say so before the spec is written. **Recommendation: as designed.**

## 10. Risks

- The Local Network behaviour on iOS and macOS is documented but not tested here; the claim that Tailscale and public hosts never prompt is an expectation to verify (4.7).
- The plausibly-local rule is a guess by host name. A name that resolves to a private address but looks public gets the plain error; the troubleshooting entry is the backstop.
- Servers from builds 9 to 13 stop syncing with 1.1 apps until updated; nothing is lost (3.5). Expected to be none outside the owner's own.
- The frozen list is a permanent commitment: a future server that drops a flag breaks 1.0 apps. The conformance file makes this visible.
- The Windows and Android plans assume the nearby list in several documents; they must not copy the removed section.

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
| 1 | Material: a denied Local Network permission is a silent dead end | 4.5 and 4.4: after a failed check to a plausibly local host (IP ranges, `.local`, single-label names) the page shows the new `messages.connection.cannotConnectLocalNetwork` with the Settings path (Mac wording separate). 4.7 records what URLSession reports when denied and whether the 20-second wait can end early, and requires the Tailscale and public no-prompt checks before the review notes and App Privacy answers change. Test 4 pins the host rule. |
| 2 | Material: refusing old servers must be a pure gate | New 3.5: nothing queued, no cursor, identity or credential changes; one message from every entry point; evaluated on each status read so it clears when the server is updated; changelog line; test 3 with a library that has queued changes and pending images. |
| 3 | Minor: tighten protocolRevision | 3.1: reason stated (every 1.1 client must contain the rule before revision 2 exists); malformed value counts as absent; gate on `revision >= N`, never on a flag, never drop a flag; re-read on every status read; `/v1/server` uses the maximum of `protocolVersions`; `status-v2.json` named as a file version, with a line in `sync/README.md`; `/v1/server`'s `mcpUrl` and `mcpUnavailable` recorded in the protocol README. New fixture cases for malformed values. |
| 4 | Minor: route audit; owner decision 3 is not a decision | Recorded as a consequence in section 1 and section 9. |
| 5 | Minor: discovery removal additions | Rollout step 4: `--remove-orphans` (or `docker rm -f` and removing the image) in the self-hosting guide and the changelog; the guide names the one setup path with the address and code from the same `setup-code` output, and notes the Mac's only route is typing. |
| 6 | Minor: agent access unaffected | Kept; test 1 asserts `agent-access-2` is in the list on both endpoints so the equivalence with "revision at least 1" cannot erode. |
| 7 | Minor: copy | 4.4: a footer proposal for the address field; both candidate strings for the Info.plist text, either acceptable. |
| 8 | Minor: test churn | Section 6: one shared healthy-status builder; the twelve-plus test files migrate to it rather than repeating the flag list. |
| 9 | Minor: owner decisions | Section 9: only the "one setup path" confirmation remains, recommended as designed. |
