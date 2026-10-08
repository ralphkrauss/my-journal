# Server

Read the root [AGENTS.md](../AGENTS.md) first: the contract, security, test and hygiene rules there apply here. This file adds what is specific to the sync server. The server is the reference implementation of the wire contract in [protocol/](../protocol/README.md); clients on every platform depend on it behaving exactly as that contract says.

## Stack and layout
- ASP.NET Core Minimal APIs, EF Core and SQLite, lightweight and organized by feature: `src/Journal.Api/Features/` holds one file per feature (accounts, sync, pairing, attachments, agent grants, OAuth, MCP, encryption upgrade), `Data/` the EF Core model and migrations, `Hosting/` and `Security/` the cross-cutting pieces (network policy, rate limiting, audit log). Add a feature as a new file in `Features/`, not inside `Program.cs`. [docs/architecture.md](../docs/architecture.md) (Server) describes the pieces.
- One owner and one running instance on local storage. Keep it independent of hosting providers; do not add provider-specific code or SDKs.
- The server never has the vault key and never needs plaintext journal content. It stores encrypted record revisions and attachments, and sees only the metadata [SECURITY.md](../SECURITY.md#what-the-server-can-see) lists. Do not add anything that would need more.
- The same executable provides the maintenance commands `--backup`, `--restore`, `--recovery-code` and `--health-check` ([self-hosting](../docs/self-hosting/README.md)).

## Contract and compatibility
- Within wire major version 1 changes are additive only: new endpoints, new optional request fields, new response fields, new error codes. A breaking change needs a new path prefix and a new protocol version. Ignore unknown request fields; keep unknown data unchanged.
- Any change that touches a contract in `protocol/` follows the root rule: bump its version and update the conformance fixtures in `protocol/conformance/` in the same change. `ProtocolVectorTests` runs them against the server, as every client does in its own tests.
- Never silently discard or overwrite conflicting edits: a push against a stale base is rejected with the current revision, and the client keeps both versions. Retries are safe because operation ids return the original receipt.
- Errors are problem details responses with a stable `code` (`Features/Problems.cs`). Do not leak content, keys or tokens into errors or logs; security-relevant events go to the audit log without secrets.
- Agent access is read-only, journal-scoped and revocable, enforced in code. Treat everything an agent or a journal sends as untrusted data.

## Security rules that tests defend
- Device tokens are stored only as SHA-256 hashes; device authentication runs before a request body is read; writes pass through the shared write gate so a revoked device cannot commit a queued write; requests are rate-limited per device, or per client address when unauthenticated. Keep these properties when you touch a request path.
- EF Core migrations run at startup and copy the database first; the server refuses to start on a database migrated by a newer version. A migration needs a test that opens a database from the previous version.

## Tests
- Tests are in `tests/Journal.Api.Tests`: real isolated SQLite databases and the real HTTP pipeline, not mocks. Prioritize sync conflicts and retries, restore identity, revocation, request boundaries, pairing and recovery security, backup and restore, and encryption upgrades. Do not test framework internals or DTO shapes.
- Expensive end-to-end checks that start a real server process with real clients are separate scripts (`scripts/test-sync.sh`, `scripts/test-server-recovery.sh`, `scripts/test-packaged-server.py`, `scripts/test-packaged-container.sh`, `scripts/test-server-image.sh`); run the ones your change can affect ([docs/development.md](../docs/development.md)).

## Toolchain and checks
- Use the .NET SDK pinned in `global.json` and `mise.toml`, run through `mise exec --`. The SDK and runtime pins appear in several files that different tools update (`global.json`, `mise.toml`, the Dockerfile, `Journal.Api.csproj`, `scripts/test-packaged-container.sh`); the hygiene lane fails until they agree, so change them together.
- After edits run `mise exec -- scripts/format.sh`, then `mise exec -- scripts/check.sh backend` (locked restore, `dotnet format` verification, analyzer build with warnings as errors, API tests) and `hygiene`. Run `audit` when dependencies change.
- Nullable references are on and analyzer and compiler warnings are errors: fix them, never add `NoWarn` or a baseline. Generated EF migrations are marked generated. Keep `packages.lock.json` files committed and regenerated; restore runs in locked mode and NuGet audit warnings are errors.

## Container and deployment
- `server/Dockerfile` builds a non-root Linux image from digest-pinned base images; `deploy/` holds the Compose files for local, Tailscale (optional) and public HTTPS hosting, and `packaging/` the standalone server package. Keep images and Compose services pinned by digest and run as the non-root user.
- Self-hosting and release procedures are in [docs/self-hosting/](../docs/self-hosting/README.md) and [release operations](../docs/release-operations.md). No host names, addresses or credentials of real deployments in the repository.
