# My Journal protocol v1

This contract is implemented by the ASP.NET Core server and the shared Swift core, and is what other clients implement. It has not been independently audited. No Apple object archives are used as the shared format.

| Document | Contents |
| --- | --- |
| This page | Wire conventions, encryption and recovery formats, pairing, sync, limits and errors |
| [records.md](records.md) | The record JSON, documents, Markdown and image references |
| [archive.md](archive.md) | The `.journalarchive` package and its database |
| [markdown-export.md](markdown-export.md) | Export as Markdown: the folder of Markdown files with front matter and images, for other apps |
| [journal-lifecycle.md](journal-lifecycle.md), [permanent-deletion.md](permanent-deletion.md), [entry-archiving.md](entry-archiving.md), [history-recovery.md](history-recovery.md) | Deletion, restoration and history rules |
| [conflicts.md](conflicts.md) | Settling a record changed on two devices without asking (conflicts v1): the rules, identities of parked entries, when they run, and the pass over conflicts an earlier version left |
| [server-backup.md](server-backup.md) | The server's backup directory, upgrades and downgrades |
| [agent-access-server.md](agent-access-server.md) | Agent access through the server's MCP endpoint: transport, authorization, keys and the agent's copy |
| [conformance/](conformance/README.md) | Fixed, versioned test vectors every client and the server must read and produce |

All endpoints use UTF-8 JSON with camelCase keys. Required request fields must be present and non-null; malformed request bodies return HTTP 400. Errors use the problem details format described under [Errors](#errors). Binary values in JSON (payloads, keys, salts, grants) are canonical padded base64 (RFC 4648 section 4): no whitespace or line breaks, and zero padding bits; the server rejects anything else with 400. HTTPS is required except for loopback connections. API paths are prefixed /v1. Device bearer credentials are 32 random bytes encoded as 64 hexadecimal characters, stored only as SHA-256 hashes on the server. Device-authenticated requests with a missing, unknown or revoked credential are rejected with 401 (`WWW-Authenticate: Bearer`) before the request body is read. Clients don't follow redirects.

UUIDs are hyphenated strings; compare them case-insensitively. Writers must use lower case wherever a UUID is part of authenticated data, a key derivation input, a file name or a JSON object key. The server writes lower case everywhere, and the Apple app uses lower case in URL paths but upper case in JSON request bodies (such as `operationId`) and inside record JSON. Dates are ISO 8601 instants with `Z` or a numeric offset; readers accept fractional seconds (up to seven digits). The server writes an offset and fractional seconds; the Apple app writes whole seconds with `Z`.

Outside /v1, GET /health answers while the process runs and GET /ready (`{status, instanceId}`, or 503) once the database is reachable. They are for monitoring and container health checks.

## Versioning and revisions

`/v1` is the wire major version. Within v1, changes are additive only: new endpoints, new optional request fields, new response fields and new error codes. Breaking changes use a new path prefix (`/v2`); a server lists every major version it implements. Servers ignore unknown request fields, so a new request field or record kind whose loss would change meaning is used only after the server's protocol revision says it is understood. Clients ignore unknown response fields.

Contracts that only clients implement are versioned on their own and change no wire format: **conflicts v1** ([conflicts.md](conflicts.md)) is the first. A client without it remains conforming; the server never learns whether a client has it.

| Version | Where | Now |
| --- | --- | --- |
| Wire major | The `/v1` path prefix; `protocolVersion` in GET /status, `protocolVersions` in GET /server | 1 |
| Protocol revision | `protocolRevision` in GET /status and GET /server | 1 |
| Recovery format | `formatVersion` of the envelope; `recoveryVersions` in both endpoints | 1 to 4 (2 for new libraries) |
| Archive header | `version` in `archive.json` ([archive.md](archive.md)) | 1 and 2 |
| Conflicts | [conflicts.md](conflicts.md); client only | 1 |
| Status fixtures | [conformance/sync/status-v2.json](conformance/sync/README.md#the-status-contract-status-v2json): the second file version of the status contract, not a protocol version | 2 |

### Protocol revision

`protocolRevision` is an integer. A server at revision N implements everything of revisions 1 to N. A revision is additive: new endpoints, optional fields, response members and error codes. **Revision 1 is exactly what a My Journal 1.0 server implements**, and every endpoint on this page belongs to it. The 1.1 server reports revision 1, so nothing a client can observe changes. The number exists so that every client contains the rule below before the first revision 2 does: a client shipped without it could not be told about revision 2 later.

- GET /status (unauthenticated): `protocolVersion` (1), `protocolRevision`, `features`, `recoveryVersions`, `initialized`, `serverId`, `mcpUrl` and `mcpUnavailable`.
- GET /server (unauthenticated, no database access, the preflight before a client knows whether the server is set up): `protocolVersions` (supported major versions, currently `[1]`), `protocolRevision`, `serverVersion` (the server build, for display and diagnostics only: the release version, or `0.0.0-dev` for development builds), `features`, `recoveryVersions`, and `mcpUrl` and `mcpUnavailable` as GET /status has them ([agent-access-server.md](agent-access-server.md)). No My Journal 1.0 app calls it. Servers from before this endpoint return 404.

**The effective revision**, which every client computes the same way ([conformance/sync/status-v2.json](conformance/sync/README.md#the-status-contract-status-v2json) has the cases):

1. A `protocolVersion` greater than 1 is a newer wire major: the client is too old ("Update My Journal"). On GET /server, the maximum of `protocolVersions` plays the same part.
2. A `protocolRevision` that is an integer from 1 to 2<sup>31</sup> − 1 is the revision.
3. Otherwise the revision is 1 if `features` lists all 13 names below, else 0. A `protocolRevision` that is not an integer, is 0 or negative, or is larger than 2<sup>31</sup> − 1 counts as absent, so a broken value can neither lock a client out nor let it skip the check of the list.
4. A revision below 1 is a server too old to sync with. A client refuses it with one message from every place that needs the server, changes and discards nothing, and works again as soon as a later status read reports revision 1 or more. A revision above what the client knows is used as is: the client does not use the newer parts.

A client gates each behavior newer than 1.0 on `revision >= N` and never on a name in `features`. It reads the revision again on every status read and does not keep it beyond that read: a server restored from an older backup or replaced may report less, and the gate then applies again. A server never drops a name from `features` when it raises its revision.

**`features` is frozen.** The 13 names below are advertised on every server that implements `/v1`, in any order, and are never extended or shortened: My Journal 1.0 apps read them and check `protocolVersion` against 1 exactly. A capability added after revision 1 is a revision with a paragraph here that says what it adds, not a name. The names are what revision 1 consists of:

| Name | Revision 1 includes |
| --- | --- |
| `sync-identity` | The server identity after a restore ([Server identity after restore](#server-identity-after-restore)) |
| `pairing-check-code` | Check-code pairing ([Pairing](#pairing)) |
| `password-change` | POST /recovery/password |
| `sync-continuity` | The `afterRecord`/`afterRevision` check on GET /sync |
| `sync-continuity-digest` | The `afterDigest` check with it |
| `private-envelope` | The wrapped vault key only after the recovery secret is verified, or to a connected device ([Setup and recovery](#setup-and-recovery)) |
| `pairing-invite` | Pairing with a code scanned from the connected device ([Invite pairing](#invite-pairing)) |
| `setup-check` | POST /setup/check |
| `encryption-upgrade` | POST /recovery/encrypt ([Turning on encryption](#turning-on-encryption)) |
| `agent-access-2` | The MCP endpoint and `/agent-requests`, `/agents` ([agent-access-server.md](agent-access-server.md)) |
| `sync-short-receipt` | Short push receipts ([Sync and conflicts](#sync-and-conflicts)) |
| `sync-wait` | GET /sync/wait ([Waiting for changes](#waiting-for-changes)) |
| `record-kinds` | PUT /sync accepts records of any well-formed kind, such as the [library record](records.md#the-library-record) |

`recoveryVersions` is not a capability: it lists the recovery-envelope formats the server stores, and stays.

**Retired by 1.1 apps, removed in `/v2`.** My Journal 1.1 apps no longer call these, and 1.1 removes no route because 1.0 apps still use them: POST /recovery/encrypt (a 1.1 library is encrypted from the start), recovery formats 3 and 4 (a 1.1 app creates neither), the `wrappedKey` that servers before `private-envelope` returned from GET /recovery, and GET /server if `/v2` has a better preflight. Nothing in this list is removed from `/v1`.

## Encrypted content

A vault has one random 256-bit key. Records use AES-256-GCM with fresh random 96-bit nonces; combined encoding is nonce || ciphertext || 128-bit tag, base64 encoded in JSON. AAD is UTF-8 journal:v1:record:{kind}:{lower-case UUID}. Kinds: journal, entry, template and, on servers with `record-kinds`, library ([records.md](records.md#the-library-record)); a client sends another kind only to a server that lists `record-kinds`. Attachments use the same construction with AAD journal:v1:attachment:{lower-case UUID} and raw binary transport. The record plaintext is described in [records.md](records.md). With encryption on, the server can't read journal names, titles, entry dates, text, images, image descriptions or templates; [SECURITY.md](../SECURITY.md#what-the-server-can-see) lists the metadata it does see.

## Recovery formats

The vault key is wrapped in a recovery envelope (`salt`, `wrappedKey`, `iterations`, `formatVersion`) that the server stores, so that another device can recover the key. The wrapping key is PBKDF2-HMAC-SHA256(credential UTF-8, random 16-byte salt, 600,000 iterations, 32 bytes), and the vault key is wrapped with AES-256-GCM (60 bytes: nonce, key, tag) using AAD `journal:v{formatVersion}:recovery`, which binds the content mode so an altered version fails authentication. Recovery authentication is HKDF-SHA256(derived wrapping key, empty salt, info journal:v1:recovery-auth, 32 bytes), encoded as lower-case hex and sent as `recoverySecret`; the server stores only its SHA-256 hash. New envelopes use 600,000 iterations; clients accept 100,000 to 2,000,000 and a 16-byte salt.

Anyone may read the envelope's `salt`, `iterations` and `formatVersion`, which is all that deriving `recoverySecret` needs. A revision 1 server sends `wrappedKey` only with a new device credential after verifying that secret (POST /recovery), or to a connected device (GET /recovery/envelope), so a password guess can be checked only online, against the server's limits. Anyone with the server's database, a server backup or an archive has the whole envelope and can guess offline, so the credential's strength still protects the vault. Servers from before revision 1 also returned `wrappedKey` from GET /recovery; a 1.1 client refuses them as too old.

The API protocol remains v1; recovery `formatVersion` selects an explicit protection contract:

| Version | Credential | Content |
| --- | --- | --- |
| 1 | Legacy generated recovery key (192 random bits in hexadecimal groups); surrounding whitespace trimmed | AES-256-GCM |
| 2 | Master password chosen by the person: UTF-8 of its Unicode NFC form, including whitespace | AES-256-GCM |
| 3 | Legacy access password: UTF-8 of its Unicode NFC form, including whitespace | Plaintext |
| 4 | No password; device grants and administrator recovery codes | Plaintext |

New encrypted libraries use version 2. Only version 1 trims credentials. Clients reject unknown versions.

Passwords (versions 2 and 3) are normalized to Unicode NFC (canonical composition only: no trimming, case folding or compatibility mapping) before derivation, so a password typed or pasted with composed or decomposed characters opens the same envelope. Envelopes created before this rule used the exact typed UTF-8. To open an envelope, a client derives from the NFC form first and, only when the typed text's UTF-8 differs from its NFC form, from the exact typed text; against a server it sends the NFC-derived `recoverySecret` first and the exact one only after that is refused with 401. Password changes always create an NFC envelope. Version 1 recovery keys are generated ASCII and aren't normalized. [conformance/crypto/encryption-v2.json](conformance/crypto/README.md) has a vector. Before setting up v2/v3, clients require an explicit matching entry in `recoveryVersions` from `/status`; an older server must not silently discard the version. The server persists and returns the selected version and rejects unsupported versions without initializing.

For v3 and v4, each record payload is base64 of the record's UTF-8 JSON, not ciphertext. Attachments are raw bytes (1 byte minimum; encrypted versions retain the 29-byte minimum). All existing size limits, device authorization, immutable-attachment rules, revisions, conflicts and retry semantics apply. Journals, templates, history, outbox and conflicts use the same protection mode. A local store records its mode and refuses mismatched reopening; an unmarked nonempty legacy store is encrypted. Archives preserve mode through the recovery envelope; their authenticated manifest remains encrypted, but v3 database payloads and image files are readable. Password possession remains required for app-managed restore and server recovery, not for reading v3 content files. Pairing transports a secret grant under encryption in all modes and includes recoveryVersion inside the authenticated encrypted grant. The receiving client requires the server envelope to match that grant version (a missing legacy grant version means 1).

New unencrypted libraries use v4: `salt` and `wrappedKey` are empty strings, `iterations` is zero. There is no public or fixed encryption key. Setup still requires the server setup code and a random 32-byte recovery secret; the client discards this initial secret after setup. Device bearer authentication and pairing are required in every mode. A server administrator with filesystem access can run `Journal.Api --recovery-code` (with the same configuration as the server, for example `Journal__DataDirectory` or `--Journal:DataDirectory=<directory>`) to rotate the recovery verifier and issue a one-use code. Recovery consumes that code while creating the new device grant under the server write gate. Codes remain valid until used or replaced. They cannot unlock an encrypted vault. Public `/recovery` metadata contains no usable authorization secret.

V4 archives use [archive header version 2](archive.md), a plaintext inventory with SHA-256 file hashes, and readable data. Hashes detect accidental corruption, not malicious edits by someone with file access. Restore requires no password and does not restore server credentials. Older v1–v3 archives remain readable under their existing password contracts.

Cross-language vectors for formats 2–4 (exact password bytes, derived keys, recovery secrets and the server's verifier hashes, wrapped keys) are in [conformance/crypto/encryption-v2.json](conformance/crypto/README.md); format 1 is in `conformance/crypto/encryption-v1.json`.

A vault's mode is never converted in place; a client can replace an unencrypted vault with an encrypted one ([Turning on encryption](#turning-on-encryption)). Journals imported into another library, including local journals uploaded when a device joins a server, take that library's mode. Clients must not add encrypted journals to a library without encryption as a side effect of connecting; the Apple app refuses before sending anything. A client uses the envelope parameters it showed the person to decide whether typed text is a password (only the derived `recoverySecret` is sent) or a version-4 recovery code (sent trimmed and in lower case, and only if it is 64 hexadecimal characters); if the server's parameters changed in between, it stops. The envelope the server then sends with the new device credential must have those parameters and open with the derived key; otherwise the client revokes that credential and stops. After pairing, the envelope read with the new credential must match the parameters shown and the grant's `recoveryVersion`. Never interpret an encryption failure as plaintext or retry with a public or fixed key.

## Turning on encryption

A library created without encryption (version 3 or 4) can be encrypted later. The mode of an existing vault never changes: the client builds a new encrypted vault and replaces the old one.

1. The client finishes synchronizing, including every image, because the server removes everything it holds.
2. It creates a new random vault key and a version-2 envelope for the chosen master password.
3. It makes a local copy of its whole store, sealing each stored payload's exact bytes under the new key with the record's usual AAD. This covers records, history, conflicts and queued changes, and each image with its attachment AAD. Record and image IDs, history and reviews are kept, so nothing is renumbered or duplicated.
4. The client verifies that every row and image of the copy decrypts to the original bytes.
5. When synced, it then calls POST /recovery/encrypt (revision 1).
6. It switches to the copy with one atomic configuration write.
7. Every record is queued at base revision 0, and every image is checked (HEAD) before it's uploaded. Nothing from the old server state (cursor, identity, revisions) is kept. Another device may sign in again and upload the same journals first, so the copy is also marked for reconciliation with the new server identity, as a device that signs in again is (below): records the server already has with the same decrypted content are matched, not shown for review. A write refused with `revision_conflict` whose `current` decrypts to the same bytes adopts the server's revision in the same way.

No synchronization of the unencrypted library may run across the switch: the client lets one that is running finish before step 3 and starts none until it has switched to the copy. A client also never synchronizes a library with a server whose recovery format (GET /recovery) implies the other protection mode; it checks whenever the server's `serverId` isn't the one it last synchronized with, and stops as if signed out. A version-1 or version-2 vault refuses a record payload that is a JSON document, readable content, with 400 `unencrypted_record`.

A crash before the switch leaves the old library, and the copy is removed at the next launch. If the server call's answer is lost, the client compares the server's public envelope (GET /recovery) with the one it sent: the same salt means the server switched and the client finishes, and the old format means nothing changed.

POST /recovery/encrypt (device-authenticated, `password` rate limit):

- **Request:** `salt`, `wrappedKey`, `iterations`, `recoverySecret`, `formatVersion` (must be 2), `afterCursor`, optional `afterRecord`/`afterRevision` (the change the client last applied at `afterCursor`), and `currentRecoverySecret` for a version-3 vault.
- **Checks,** under the write gate:
  - 409 `unsupported_format` unless the vault is version 3 or 4.
  - 403 `wrong_password` for a version-3 vault without the matching current secret. A version-4 vault has no password; the device credential, which already grants full access, is the authorization.
  - 409 `server_changed` unless `afterCursor` is the newest change, and, when `afterRecord`/`afterRevision` are given, that change is the one there. Nothing is changed then; the client synchronizes and tries again.
- **Effect,** in one transaction:
  - The envelope and verifier are replaced, and the version becomes 2.
  - Every record, change, operation receipt, attachment row and pairing request is deleted, along with any agent access granted through the server.
  - Every other device is revoked.
  - The server takes a new `serverId`.
- **After the commit:**
  - The server deletes image files, the pre-migration database copy, and free database pages (VACUUM), and truncates the write-ahead log.
  - A marker file naming the new identity is written before the transaction. It lets a server stopped part way finish at its next start, while a marker from a request that never committed removes nothing.
- **Response:** 200 with `serverId`. The same request again, with the same salt, wrapped key and secret, returns 200 with the same `serverId`, so a lost answer can be retried.

Other devices get 401 afterwards. A client that finds the public envelope at version 1 or 2, while its own library is version 3 or 4, tells the person that encryption was turned on from another device and asks them to sign in. It signs in with the master password (POST /recovery) or by pairing, receiving the new vault key. It then:

1. Makes the same encrypted copy of its own store, keeping revisions and queued changes.
2. Marks the copy for reconciliation with the new server identity ([Server identity after restore](#server-identity-after-restore)). Reconciliation compares content by decrypted bytes, because two devices' ciphertexts of the same content differ. Records the server has are matched rather than duplicated, and edits made offline that differ become conflicts for review.
3. Checks images it had uploaded before (HEAD) instead of uploading them again. The server's copy came from the device that turned on encryption.

The server can't remove what it doesn't hold: earlier server backups (`--backup`), archives, device backups and filesystem snapshots keep the readable content. Encryption can't be turned off.

## Setup and recovery

- GET /status: protocolVersion, protocolRevision, initialized, recoveryVersions (supported recovery-envelope versions), features (frozen, see [Versioning and revisions](#versioning-and-revisions)), serverId (see below), mcpUrl and mcpUnavailable.
- POST /setup: setupCode, salt, wrappedKey, iterations, recoverySecret, deviceName, formatVersion (optional, defaults to 1 for legacy clients). The one-time setup code comes from the protected data/setup-code file: 6 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (no 0, O, 1 or I; 30 bits, uniformly random), shown as `XXX-XXX`. The file holds the code in that form followed by a line break; a server also accepts the file without the hyphen. A file from an older server with 8-character codes isn't valid and is replaced when the server next starts without a vault; clients accept only 6-character codes. The administrator sees it with `Journal.Api --setup-code` (`setup-code` in the server image); the server never logs it. The server normalizes the request's code (ASCII letters to upper case; hyphens, spaces, tabs and line breaks removed) and rejects anything that isn't then 6 alphabet characters with 400 `invalid_setup_code`, without counting it as an attempt. Creates the only vault and returns deviceId/token. Later setup calls cannot replace it (409 `already_initialized`). A missing, empty or damaged setup-code file never matches: setup returns 503 `setup_code_missing`, and the server writes a new code when it next starts without a vault. A wrong code returns 401 `invalid_setup_code`; an invalid envelope or device name returns 400 `invalid_setup`. Wrong codes from all client addresses together form one budget: after 10 within an hour, each further attempt waits 30 seconds, twice as long as the previous wait, up to 15 minutes, and is refused meanwhile with 429 `rate_limited` and Retry-After, whatever its code. That caps guessing at about a hundred codes a day. The code stays the same until setup succeeds, which deletes it. Someone who can reach a server that isn't set up can still try codes, so set it up before exposing it beyond a tailnet or local network.
- POST /setup/check: setupCode. Checks a setup code before the client asks for a password, exactly as POST /setup checks it first, in the same order and with the same responses: 409 `already_initialized`, 400 `invalid_setup_code` (malformed, not counted), 503 `setup_code_missing`, 429 `rate_limited` with Retry-After, 401 `invalid_setup_code`. Wrong codes count toward the same budget as POST /setup. Returns 204 when the code matches. It changes nothing: the code stays valid for POST /setup, which checks it again.
- GET /recovery: salt, iterations, formatVersion; servers from before revision 1 also returned wrappedKey. 404 `not_initialized` before setup.
- GET /recovery/envelope (device-authenticated): the whole envelope (salt, wrappedKey, iterations, formatVersion), for password changes, for a new device after pairing, and for a device that needs the password to open its library again. 404 `not_initialized` before setup.
- POST /recovery: recoverySecret, deviceName. Returns a new deviceId and token and `envelope`: the whole envelope as GET /recovery/envelope returns it. A wrong secret returns 401 `invalid_recovery_secret`; an empty or over-long device name returns 400 `invalid_device_name`. Wrong secrets from all client addresses together form one budget: after 20 within an hour, each further attempt waits 30 seconds, twice as long as the previous wait, up to 15 minutes, and is refused meanwhile with 429 `rate_limited` and Retry-After, whatever its secret. Device-authenticated requests, including pairing and password changes, are never limited by it.
- GET /devices/: every device record, including revoked ones: id, name, createdAt, revoked, `createdVia` and `approvedByDeviceId`. `createdVia` is `setup`, `recovery` or `pairing` (clients treat other values as unknown); it is absent for devices added before the server recorded it. `approvedByDeviceId` is the ID of the device that approved a pairing, and null otherwise.
- POST /recovery/password (device-authenticated): currentRecoverySecret, salt, wrappedKey, iterations, recoverySecret, formatVersion. Changes the master password of a version-2 library by atomically replacing the whole envelope and recovery verifier under the write gate, and returns 204. The current password's recovery secret must match (403 `wrong_password` otherwise), formatVersion must equal the vault's (no mode conversion), and other versions return 409 `unsupported_format`. The wrapped vault key itself is unchanged, so content, device credentials and other devices are unaffected. Clients verify the current password against the server's envelope (GET /recovery/envelope) and unwrap the same key before sending. Other devices keep their device keys; one that later needs the password (for example after losing its device key) tries its saved envelope, then the server's, read with its device credential, accepting the server's only if the unwrapped key opens its existing records. Earlier server backups and archives keep the password they were made with. Because the vault key doesn't change, anyone with the old password and an old envelope can still unwrap it ([SECURITY.md](../SECURITY.md#changing-the-password-and-revoking-devices)).
- DELETE /devices/{id}: revoke future API access. Protected mutations recheck device authorization while holding the shared write gate, so a previously authenticated upload or queued write cannot commit after revocation has completed. Already-started reads may finish, and revocation cannot erase prior downloads.

## Pairing

Pairing is part of revision 1 (`pairing-check-code`). Both devices show a six-digit check code derived from both devices' keys, and both ask the person to confirm that the codes match. The approving device confirms before it sends the vault key, so a server that relays a substituted key is detected there and receives nothing; the new device confirms before it uses a grant, whichever confirmation comes first.

1. New device: POST /pairing with deviceName and keyCommitment = base64(SHA-256(UTF-8 `journal:v2:pairing-commitment` || its raw 32-byte Curve25519 public key)). Returns id, a nine-digit code, pollToken, expiresAt. Five-minute lifetime. A request without keyCommitment returns 400. With `pairing-invite`, the request may also carry `invite` and `inviteProof` ([Invite pairing](#invite-pairing)). When 200 requests are pending, the server returns 429 `pairing_capacity` with Retry-After (seconds until the oldest pending request expires).
2. Approving device (device-authenticated): POST /pairing/lookup with code returns id, deviceName, keyCommitment, approverKey, publicKey (null until revealed), inviteProof (null unless the request carried an invite; `pairing-invite` servers), expiresAt. It then generates a one-time Curve25519 key and sends POST /pairing/{id}/challenge with approverKey (base64 public key). The server accepts it once; only an identical retry succeeds afterwards.
3. New device: POST /pairing/{id}/poll with pollToken returns approved, encryptedGrant, deviceId, approverKey, declined. Once approverKey is present it sends POST /pairing/{id}/reveal with pollToken and publicKey. The server accepts a reveal only after the challenge (409 `pairing_not_challenged` before it, 409 `pairing_declined` after a decline) and only if it matches the commitment (400 `commitment_mismatch`).
4. Approving device: GET /pairing/{id} (the same fields as lookup) until publicKey is present, then checks the commitment itself.
5. Both devices compute the check code: the first four bytes (big-endian unsigned) of SHA-256(UTF-8 `journal:v2:pairing-check:{lower-case pairing UUID}:` || device public key || approver public key), modulo 1,000,000, as six digits with leading zeros, displayed as "123 456".
6. After the person confirms matching codes, the approving device seals the grant with its one-time key: POST /pairing/{id}/approve with deviceToken and encryptedGrant. Returns `{id}` (the new device ID). The server requires a revealed key and the grant's first 32 bytes to equal the challenge key (409 `grant_key_mismatch`); a second approval returns 409 `pairing_already_approved`. The new device opens a grant only after it has revealed its key and shown the check code, only once the person has confirmed the code there, and only if the grant's first 32 bytes equal the approverKey its displayed code was computed from (and the poll reports the same key). A new device that is cancelled after the approval revokes the credential it received.
7. Cancelling on the approving device sends POST /pairing/{id}/decline (device-authenticated); the new device's poll then reports declined and approval is refused. POST /pairing/{id}/cancel with pollToken withdraws a request from the new device, revoking any device already created for it.

Expiry: the server refuses an approval with less than 30 seconds left (404 `pairing_expired`) instead of creating a credential the new device may never collect. An approved grant stays readable by poll for two more minutes after `expiresAt`, for devices whose clocks run behind or whose last poll is late, so a new device keeps polling until the server answers 404, at most two minutes past `expiresAt`; a request that wasn't approved returns 404 as soon as it expires. A request is removed after that grace period; if its grant was never collected, the device created for it is revoked. Unknown, expired and cancelled requests return 404 `pairing_not_found`.

The commitment is published before the approver's key exists and the approver's key is fixed before the new device's key is revealed. A server relaying substituted keys therefore cannot search for keys that produce matching codes; each attempt matches with probability one in a million and a mismatch is visible to the person. Test vector: device key 32 bytes of 0x07, approver key 32 bytes of 0x09, pairing ID 3f2504e0-4f89-41d3-9a0c-0305e82c3301: commitment `2kHrWMfI9jssNr6LMzi1CnMfO8j59ftEu0NEGULOHFY=`, check code `479111`. [conformance/crypto/encryption-v2.json](conformance/crypto/README.md) has a complete vector with real X25519 keys (and [conformance/pairing/](conformance/pairing/README.md) the invite proof and check codes): commitment, check code, shared secret, grant key and sealed grant.

Grant encryption: ECDH between the approver's one-time key and the new device's key, then HKDF-SHA256 with salt equal to the UTF-8 lowercase pairing UUID and info journal:v1:pairing. The sealed grant is the approver public key (32 bytes) followed by AES-GCM combined ciphertext with AAD journal:v1:pairing:{UUID}. Plaintext JSON contains masterKey (base64), token and recoveryVersion. The server sees the device token only as the approving client's request for hashing. With confirmed check codes, the server cannot obtain the vault key through pairing. A person who confirms without comparing codes, or a compromised device, is outside this protection. Pending requests expire and can be approved only once.

The new device installs a grant only after the person confirms the check code there, so a server that acts as the approving device itself, with its own approverKey, is detected on the new device too.

Pairing without a check code (the new device sending its key instead of a commitment) is not supported: the server rejects it, current clients neither send nor approve it, and a new device refuses a server below revision 1.

### Invite pairing

Part of revision 1 (`pairing-invite`). Instead of typing a nine-digit code, the new device scans a code shown by the connected device. The steps above are unchanged (commitment, challenge, reveal, sealed grant); only how the devices authenticate each other differs, and no check code is shown.

1. Connected device: creates, in memory only, an invite handle `t` (16 random bytes), a secret `s` (32 random bytes, never sent to the server) and its one-time Curve25519 key `A`. It shows a QR code whose text is `MYJOURNAL1.` followed by base64url without padding of `t` ‖ `A` (32 bytes) ‖ `s` ‖ the UTF-8 server address. The text has no colon, so no app can register it as a URL scheme and receive it; only the app's own scanner reads it. The code is shown for at most two minutes.
2. New device: creates its key `N` and commitment `C` as in step 1 above, and computes

   `inviteProof = HMAC-SHA256(key: s, message: "journal:v2:pairing-invite" ‖ 0x00 ‖ t ‖ A ‖ C ‖ u16be(len(origin)) ‖ origin ‖ u16be(len(name)) ‖ name)`

   where `C` is the raw 32-byte commitment, `origin` is the UTF-8 of the server's lower-case `https://host`, with `:port` only when the port isn't 443, and `name` the exact UTF-8 bytes of the deviceName it sends; u16be is a two-byte big-endian length. It sends POST /pairing with deviceName, keyCommitment, `invite` (`t` as 32 lower-case hexadecimal characters) and `inviteProof` (base64 of the 32-byte HMAC).
3. Server: requires both `invite` and `inviteProof` or neither (400 `invalid_pairing_request` otherwise, also for an invite that isn't 32 lower-case hexadecimal characters or a proof that isn't 32 bytes). It stores the request with the invite as its code and returns code = `invite`. While any request with that invite still exists, pending, approved or declined, another request for it returns 409 `invite_used`.
4. Connected device: polls POST /pairing/lookup with its own `t` (every 3 seconds, within the lookup limit). Before it shows anything, it verifies `inviteProof` over its own `t`, `A`, `s` and origin and the candidate's keyCommitment and deviceName, comparing in constant time. It accepts exactly one candidate per code: a request with a missing or wrong proof is declined and the code ends. It then challenges with `A` and continues as above, asking the person to add the named device and sealing the grant with `A`.
5. New device: accepts the challenge only if approverKey equals `A` from the scanned code, then reveals `N`. It opens only a grant whose first 32 bytes are `A`, and installs it without a check code. If the server doesn't list `pairing-invite`, or refuses the invite, it never falls back to sending the request without the invite.

Test vector: `t` 16 bytes of 0x01, `A` 32 bytes of 0x02, `C` 32 bytes of 0x03, `s` 32 bytes of 0x04, origin `https://journal.example.ts.net`, name `iPad`: inviteProof `xVcRQajP8P9JRb9Q527FO/+5SpxXKy3XXhgAxdoRgvY=`.

Security properties: the server never sees `s`, so it can't make a request the connected device accepts or change the name the person is asked about. It can't substitute the approver's key, because the new device knows `A` from the code. Nothing short is involved, so nothing can be guessed offline. The proof binds the server's origin, so a request relayed to another server fails. Residual risk: someone who photographs the code while it's shown and can reach the server could use it first. The person would still have to add a device with that device's name, and the real device then reports that the code was already used. Clients offer scanning only on devices without journals, so a code shown by someone else can't make a device upload existing journals to a server that person controls.

## Server identity after restore

Part of revision 1 (`sync-identity`). Each server database has a random `serverId` (UUID string), assigned at setup, when an older server first starts after upgrading, and replaced on every `--restore`. `/status` and every GET /sync page return `serverId`; sync pages also return `serverIdCursor`, the newest change cursor that existed when the identity was assigned (changes above it were written afterwards). PUT /sync accepts an optional `serverId`; a mismatch returns 409 `server_changed` without applying the write. The identity is not part of an operation's idempotency hash, so earlier receipts stay retryable.

A restored server's change cursors and revisions restart from the backup. Clients store the identity they last synchronized with. When `/status` reports a different identity (or a store with sync history first sees one), the client re-reads the whole log before pushing and compares each record by exact payload:
- equal payload: adopt the server revision;
- the local payload appears earlier in the server's log for that record: apply the server version (it descends from local content);
- the server version predates the identity (cursor ≤ serverIdCursor) and its revision is not newer than the local revision: the server lost later versions this device has; re-upload the local version based on the server revision;
- a server version that predates the identity with a newer revision: normal rules (apply, or conflict if edited locally);
- otherwise, including versions written after a restore: a normal conflict for review (a client that implements [conflicts.md](conflicts.md) settles it there, once the whole log is compared);
- records the server lacks: upload again from revision 0; pending conflicts are kept and rebased onto the server's revision.
Images are then checked with HEAD /attachments/{id} (200 present, 404 missing) and uploaded again if missing. Nothing is discarded silently and no conflicting edit is overwritten.

A base revision ahead of the server's record returns 409 `revision_ahead` (older servers return `revision_conflict` with an older or null `current`). Clients treat both as a server that lost revisions and reconcile as above instead of failing; with an older server that has no identity, every differing record whose history can't be proven becomes a conflict. Old servers without `serverId` keep working unchanged.

Restoring by copying a data directory, rolling back a volume snapshot or restoring a Time Machine backup of the data (anything but `--restore`) is unsupported: it keeps the old identity, and new changes reuse the cursor and revision numbers of changes the server lost. Clients detect it in these cases:
- a write whose base revision is ahead of the server (409 `revision_ahead`);
- a write the server accepts at a cursor at or below the newest cursor the client has received;
- a page request that names the change the client last applied: GET /sync accepts `afterRecord` and `afterRevision` (both or neither), the record ID and revision of the change at cursor `after`. If this server has no such change at that cursor, it returns 409 `server_changed`.
  - The request may also give `afterDigest`, the lower-case hex SHA-256 of that change's payload text as the client received or sent it (64 characters; only with `afterRecord`/`afterRevision`, otherwise 400 `invalid_cursor`). A different payload there also returns 409 `server_changed`. Without it, a copy that lost a change can give its position, record and revision to another device's version of the same record, which the check can't tell apart.

In each case the client reconciles as after a restore. Clients should store the record ID, revision and payload digest of the change at their cursor, send them on every page request, and, before sending writes, confirm them with a one-change page (`limit=1`). A write the server accepted can be past that cursor when the client hasn't read on yet, for example because the connection dropped; before sending more, clients should confirm the newest such receipt the same way (`after` its cursor). The Apple app does all of this. A change at a revision the client already has, with another payload than the one it sent or received there, also means the server lost a version: the Apple app keeps both for review. Without this check, a device that only reads keeps its stored cursor and misses changes written into the reused range, and a write accepted before detection can replace another device's version of that record, which then remains only in the server's log. Detection relies on the server's answers, so a malicious server can hide a rollback.

## Rate limits

Anonymous setup and recovery attempts are limited per client address (IPv6 addresses by /64; 30 per minute), and wrong setup codes and recovery secrets also by the server-wide budgets described under POST /setup (10 an hour, then waits from 30 seconds up to 15 minutes) and POST /recovery (20 an hour, then the same waits); fetching the recovery envelope is limited separately (60 per minute), starting a pairing request separately (10 per minute), and poll, reveal and cancel together (240 per minute; request IDs are chosen by the caller, so they do not form separate limits). A server holds at most 200 pending pairing requests. Authenticated requests are limited per device rather than per address (device endpoints 300 per minute, pairing lookup 30, password changes 10), so anonymous traffic cannot exhaust an owner's limits; requests with an invalid credential count against their address. Sync and attachment requests are limited only in concurrency per device (8 at a time, then a short queue), which sequential clients never reach. Waits (GET /sync/wait) are outside that limit; they are limited to 60 a minute per device, and per address for requests without a valid credential. Rejections return 429 `rate_limited`, with Retry-After for rate (not concurrency) limits; polling clients wait longer and continue.

The client address is the connecting address. X-Forwarded-For is used only when the connection comes from a proxy the operator listed in the server setting `Journal:TrustedProxies` (IP addresses or CIDR networks separated by `;` or `,`; an invalid entry stops the server from starting), and then only its last entry; without that setting every client behind a reverse proxy shares the proxy's address and limits. The container examples configure it for their Caddy and Tailscale Serve proxies. List only the immediate proxy, at an address nothing else connects from, and have it replace a client's X-Forwarded-For rather than pass it on: anything connecting from a trusted address can claim any client address.

A server whose configured addresses are all loopback (or unset, which means Kestrel's `localhost:5000`) accepts only the host names `localhost`, `127.0.0.1`, `[::1]` and `*.ts.net` (Tailscale Serve) unless the `AllowedHosts` setting lists others, which blocks DNS rebinding from local web pages; other host names receive 400 before any endpoint runs. Servers listening on other interfaces accept any host name unless `AllowedHosts` is set.

## Sync and conflicts

PUT /sync/{recordId}: operationId, baseRevision, kind, payload, and optionally `shortReceipt`. Creation uses baseRevision 0. `kind` is `journal`, `entry` or `template`; a server accepts any kind of 1 to 32 characters from `a-z`, `0-9` and `-`, and stores it without interpreting the payload. Servers from before revision 1 refused other kinds with 400 `invalid_record`; a 1.1 client does not sync with them. The kind of a record never changes ([records.md](records.md#the-library-record)). Successful response is an immutable change receipt: cursor, recordId, revision, kind, payload, deviceId, modifiedAt.

A client may send `shortReceipt: true`; the receipt then leaves out `payload` and has `payloadDigest` instead: the lower-case hex SHA-256 of the stored payload text's UTF-8 bytes (as `afterDigest`). Its members are cursor, recordId, revision, kind, deviceId, modifiedAt and payloadDigest. `shortReceipt` is not part of the operation: a retry returns the same change in the form that retry asks for, and toggling it never causes `operation_reused`. Receipts of operations kept whole by older servers are returned whole, so a client that asks for a short receipt still accepts a full one. A client accepts a short receipt only if it names the record and kind it sent and the next revision, and its digest is that of exactly the payload it sent; a receipt with both members must have both agree, and a member that is null counts as present and invalid. It then completes the change with the payload it sent. Errors, including 409 conflicts with `current`, are unchanged.

Each operation UUID identifies an immutable request. Retrying it returns the original receipt even after newer revisions exist. Reusing it with different content returns 409 `operation_reused`. A stale baseRevision returns 409 `revision_conflict` with `current`, the server's record (id, revision, kind, payload, deviceId, modifiedAt). The client retains its local version until an explicit resolution. A client that implements [conflicts.md](conflicts.md) resolves automatically instead. Conflict resolution creates a new revision based on the reviewed remote revision and can itself conflict if another edit arrives.

Record payloads are 29 bytes to 4 MiB after base64 decoding in every protection mode; other values return 400 `invalid_record`. A rejected write (400, 413 or 409 `operation_reused`) was not applied; clients keep that record on the device, check the size limit before sending, and continue with other records instead of stopping sync. Changing a record's kind returns 400 `kind_is_immutable`. A base ahead of the server returns 409 `revision_ahead` with `current` (null when the server has no record).

GET /sync/?after={cursor}&limit={1..200}: changes, cursor, hasMore, serverId, serverIdCursor. `after` defaults to 0 (a negative value returns 400 `invalid_cursor`); `limit` defaults to 100 and is clamped to 1..200. A page may hold fewer than `limit` changes: the server stops before the base64 payloads of a page total more than 8 MiB, but always includes at least one change, so a single large record still makes progress. `hasMore` is true whenever changes remain, and then `cursor` is greater than `after`; clients continue from `cursor` until it is false, and treat a page that doesn't advance, or whose changes lie outside (`after`, `cursor`], as an error. An empty page returns `cursor = after`. Each change includes its complete immutable ciphertext. The client authenticates every change in encrypted modes and commits the page and cursor atomically. A change that fails authentication stops the page and nothing is committed. A change that authenticates but can't be read is kept as described in [records.md](records.md#reading-rules) and doesn't stop the log. IDs and tombstones are retained; local clocks do not determine precedence. Entries deleted by users remain encrypted tombstones rather than disappearing from the sync log.

### Waiting for changes

Part of revision 1 (`sync-wait`). GET /sync/wait (device-authenticated) holds a request until the log has something for the client, so a client in the foreground needn't poll. Query: `after` (required, the client's cursor), `afterRecord`/`afterRevision`/`afterDigest` (the change it applied at `after`, as on GET /sync/), `serverId` (the identity it last synchronized with; clients send it whenever they have one), `timeout` (seconds, clamped to 1–25, default 25; clients send at most 25). Validation is GET /sync/'s, except that `after` is required (400 `invalid_cursor`; a value that isn't a number fails model binding with 400).

The answer is 200 with `{"changed": true}`, `{"changed": false}` or `{"changed": false, "early": true}`, and never any content:

- `true` when an ordinary sync from that position would find something: a change after `after`, another change (or none) at `after` than the one named, or another identity (compared ignoring case). Run an ordinary sync; a `true` that finds nothing is harmless.
- A confirming `false` (without `early`) is held until the clamped timeout and checked once more then: it means what an empty page from that position would mean at that moment.
- An early `false` (`early: true`): a newer wait from the same device replaced this one, the server already holds its maximum of 64 waits, or the server is stopping. It proves nothing; a client may poll instead.

Every check reads the database, so a change can't be missed; a wait is woken when a change is written, a device revoked (it then gets 401) or encryption turned on. One wait is held per device: a newer one answers the older one early. Clients must:

- run one wait at a time per device credential;
- treat a `false` as confirming only without `early` and when it arrives no sooner than min(requested timeout, 25) − 2 s after sending (a cache could replay an old answer);
- turn any `true`, error or unreadable answer into an ordinary sync, never into a sync state of its own;
- keep a periodic full sync while waiting, and never follow redirects (as everywhere).

The server holds waits for up to 25 s, so reverse proxies need response and idle timeouts of at least 30 s; behind a shorter one, waits fail and clients poll.

PUT /attachments/{id}: immutable encrypted binary, at most 25 MiB including encryption overhead (413 `attachment_too_large`), at least 29 bytes in encrypted modes (400 `invalid_ciphertext`). Returns `{id, sha256}`. Identical retries succeed; changing bytes under an existing ID returns 409 `attachment_is_immutable`. If the server still records an image whose file was lost, HEAD reports 404 and GET 503 `attachment_unavailable`; uploading the identical bytes again restores the file. GET downloads bytes (range requests supported); an unknown ID returns 404 `attachment_not_found`. Clients upload attachments before publishing records that refer to them. Clients must still tolerate references to attachments they can't get (not uploaded, lost by the server, or a download that fails): they keep the reference, show a placeholder and retry later without failing the sync.

## Limits

Request bodies are limited before they are read: 8 MiB for PUT /sync/{id}, 25 MiB for PUT /attachments/{id}, and 64 KiB for every other request. Larger bodies return 413 `request_too_large` (or `attachment_too_large`). Device names are 1–100 UTF-16 code units and not only whitespace; pairing grants are at most 4096 bytes; pairing codes are nine digits, or an invite of 32 lower-case hexadecimal characters; setup codes are 6 characters (after normalization); poll tokens and device tokens are 64 hexadecimal characters.

## Errors

Every error response is an RFC 9457 problem details object (`application/problem+json`) with `type`, `title`, `status`, and two extension members: `code`, a stable machine-readable reason, and `error`, the same value, kept for clients written before problem details. Clients branch on `code`, never on `title` or `detail`. 409 revision errors also carry `current`. New codes may be added within v1; clients treat an unknown code like its HTTP status. Transport-level rejections (a malformed request, or a host name the server does not accept) may have no problem body.

| Status | Codes |
| --- | --- |
| 400 | `bad_request` (malformed JSON or missing fields), `invalid_setup`, `invalid_setup_code` (not 6 setup-code characters), `invalid_device_name`, `invalid_password_change`, `invalid_encryption_request`, `invalid_pairing_request`, `commitment_mismatch`, `invalid_cursor`, `invalid_record`, `unencrypted_record`, `kind_is_immutable`, `invalid_attachment`, `invalid_ciphertext`, `invalid_agent`, `invalid_agent_item` |
| 401 | `unauthorized` (device credential missing, unknown or revoked), `invalid_setup_code`, `invalid_recovery_secret` |
| 403 | `wrong_password` |
| 404 | `not_found`, `not_initialized`, `device_not_found`, `pairing_not_found`, `pairing_expired`, `attachment_not_found`, `agent_request_not_found`, `agent_not_found` |
| 405 | `method_not_allowed` |
| 415 | `unsupported_media_type` (a JSON body without a JSON content type) |
| 409 | `already_initialized`, `not_initialized` (pairing before setup), `unsupported_format`, `approver_key_fixed`, `pairing_not_challenged`, `pairing_declined`, `pairing_already_approved`, `invite_used`, `grant_key_mismatch`, `operation_reused`, `server_changed`, `revision_conflict`, `revision_ahead`, `attachment_is_immutable`, `agent_not_reconnectable`, `agent_limit`, `agent_expired`, `agent_quota`, `agent_request_mismatch`, `agent_settings_changed` |
| 413 | `request_too_large`, `attachment_too_large` |
| 429 | `rate_limited`, `pairing_capacity` |
| 500 | `internal_error` |
| 503 | `setup_code_missing`, `attachment_unavailable`, `unavailable` (GET /ready) |

## Portable content

The record JSON, documents, Markdown and image references are specified in [records.md](records.md). The protocol is the shared contract; native clients may use different languages, database libraries and platform text systems.
