# Public HTTPS server

This example runs on a Linux server or VPS with Docker Compose, persistent local storage, and a DNS name you control. The native apps use the same device pairing, encrypted sync, and recovery protocol as a Tailscale deployment. One running backend supports one owner; do not scale it to multiple replicas or put its SQLite volume on a network filesystem.

These commands build the checked-out source on your server. To run a published image instead, set `JOURNAL_IMAGE` as described in [self-hosting](README.md#updates).

## Install

1. Point a DNS A record (and an AAAA record only if IPv6 works) at the server. Use a hostname such as `journal.example.com`.
2. Allow inbound TCP ports 80 and 443. UDP 443 is optional for HTTP/3. Allow outbound DNS and HTTPS for certificate issuance and renewal. Port 80 serves certificate challenges and redirects ordinary HTTP requests to HTTPS.
3. From the project root on that server, set the hostname and start the stack:

   ```sh
   export JOURNAL_DOMAIN=journal.example.com
   docker compose -f deploy/compose.https.yaml up -d --build --wait
   curl --fail "https://$JOURNAL_DOMAIN/ready"
   docker compose -f deploy/compose.https.yaml exec journal setup-code
   ```

   Keep `JOURNAL_DOMAIN` in your deployment environment or a local `.env` file for future Compose commands. It is a hostname, without `https://` or a path. Do not combine this Compose file with the other deployment examples: each is a complete alternative.
4. In My Journal, open Settings > Sync, choose Connect to a Server… and enter `https://journal.example.com` with the one-time setup code the last command showed, such as `K7Q-M4X`. Add your other devices in Settings > Sync > Devices. The setup code is deleted after setup. Until then, anyone who can reach the server can try codes, slowed down after 10 wrong attempts an hour, so set it up right after it starts. Keep your master password separately; the app PIN does not replace it.

Caddy obtains and renews a publicly trusted certificate. Its persistent volumes retain the certificate and ACME account. Public certificate issuance generally records the hostname in public certificate-transparency logs. It does not publish journal contents.

The readiness request must succeed with normal certificate verification. Do not use an insecure certificate bypass as an installation workaround. If issuance fails, inspect `docker compose -f deploy/compose.https.yaml logs proxy`, then check DNS, firewall/NAT, and outbound connectivity before retrying. Public issuance is subject to the certificate authority’s limits.

## Isolation and authentication

Only the proxy publishes ports. The backend connects to a Docker internal network and has no host port mapping. Both containers run without root privileges, with a read-only root filesystem, dropped Linux capabilities, and separately persisted data. Caddy listens internally on 8080/8443, mapped to public 80/443. Its admin endpoint is disabled and HTTP request access logging is not enabled.

Device bearer-token authentication is required for journal data, even through HTTPS. Setup requires the one-time secret available only from server storage; recovery requires the recovery secret derived by the native app. Status and the recovery envelope's salt and format have deliberately public endpoints; the wrapped vault key is sent only after the recovery secret is verified, or to a connected device. A local PIN unlocks the app; it is not an internet-facing server password. The backend trusts `X-Forwarded-For` only from its internal network (`JOURNAL_BACKEND_SUBNET`, default `172.16.231.0/28`), where Caddy replaces the header with the address it received the request from. Each client therefore has its own rate limit, and a client can’t choose its address; see [reverse proxies and host names](README.md#reverse-proxies-and-host-names). Anyone who reaches this server can try to guess your master password through it, slowed down after 20 wrong attempts an hour, and anyone with its data or backups can guess offline, so use a strong password.

Use the app’s built-in authentication rather than adding a second HTTP Basic authentication layer, which would compete for the Authorization header used by device tokens. Hosting providers and server administrators can still observe traffic timing, sizes, and the metadata described in the protocol; TLS does not make a public service invisible. Tailscale remains the simpler option when only your devices need access.

## Back up and update

Use the consistent backup procedure in [self-hosting](README.md), substituting `-f deploy/compose.https.yaml`. Back up journal-data and preserve recovery material separately. The proxy volumes hold TLS account/certificate state; they are distinct from journal backups. Stop services with `docker compose -f deploy/compose.https.yaml down` without `--volumes`. Removing volumes deletes persistent state.

Before updating, create and copy a verified backup off the server. Then rebuild and restart from the intended source version. Native clients do not depend on Caddy; you can use another HTTPS proxy or a container host’s TLS ingress with the same backend image and persistent volume, provided the backend HTTP port stays private; set `Journal__TrustedProxies` to that proxy’s address or network.

## Implementation and verification

Caddy is the optional proxy dependency for this deployment example. Its version and immutable image digest are pinned in `deploy/caddy.Dockerfile`, and Dependabot proposes updates to the pin. The small derived image changes writable-volume ownership and removes the upstream executable’s low-port capability, which is unnecessary on the configured high ports and otherwise prevents execution with all capabilities dropped.

The configuration follows Caddy’s [automatic HTTPS](https://caddyserver.com/docs/automatic-https) and [internal HTTP/HTTPS port options](https://caddyserver.com/docs/caddyfile/options#https-port). No DNS-provider module, custom auth plugin, or new backend dependency is required.

`mise exec -- python3 scripts/test-https-deployment.py` checks the actual Compose stack using unique temporary volumes and randomly assigned loopback ports. It adds only a test-local CA directive to the real Caddyfile, validates the resulting certificate explicitly, proves that the CA is absent from normal machine trust, verifies HTTP redirection, denies missing/invalid device credentials, initializes synthetic server data over HTTPS, checks authenticated access and no-store headers, and verifies credentials survive backend restart. It also restores a live server backup into a new mounted Docker volume and creates a validated backup from the restored data. It also checks non-root/read-only containers and absence of published backend ports. Its finally block removes only its uniquely named test project and volumes.

That local test does not prove public DNS, firewall configuration, ACME issuance/renewal on a real host, or a cloud-provider installation. Those need verification on the chosen deployment. It does not install a certificate authority on your machine or create a public endpoint.
