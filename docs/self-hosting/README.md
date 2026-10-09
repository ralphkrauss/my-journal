# Self-hosting

The server supports one owner and one running instance on persistent local storage. It does not require Tailscale. The same container runs on a home Linux server, a NAS, a VPS, a [Mac](#running-the-server-on-a-mac) or another suitable container host. The My Journal apps only connect to it; they don't run a server. Do not place the SQLite data directory on a network filesystem or run multiple replicas against it.

## First deployment

There is one route: start the [local container](#local-container), then, if your other devices need to reach it, run it with [Tailscale](#tailscale) or behind [public HTTPS](#public-hosting). Those are variations of where the same server runs; setting it up in the app is the same every time:

1. Start the server and run `setup-code`. It prints the one-time setup code and, when `JOURNAL_URL` is set, the HTTPS address devices use. Copy the address and the code from this one output.
2. In My Journal, choose **Connect to a Server…**. An iPhone or iPad lists a server announced on the network under **Servers on This Network** or scans a code from a device that already syncs; a Mac has no scanner, so it selects a nearby server or types the address.
3. Enter the setup code, then choose a master password.

My Journal 1.1 apps need a server that reports protocol revision 1 or later, which every server since the first My Journal 1.0 releases does. If you run a server built before those releases, update it before the app; the app refuses it with “This server needs an update before this device can connect” and changes nothing on the device.

## Local container

From the project root:

    docker compose -f deploy/compose.yaml up -d --build
    docker compose -f deploy/compose.yaml exec journal setup-code

The service binds to 127.0.0.1:8080 on the host and runs as a non-root user. The last command shows the server's one-time setup code, such as `Setup code: K7Q-M4X`; enter it in the app. Without Docker, run the server with `--setup-code` and the same configuration instead. The code stays the same until setup succeeds, then it's deleted. The server never writes it to its log; don't share it in public support reports either. The container image includes the license and third-party notices in `/app`.

### Setup code

The code has 6 characters, without look-alikes such as 0 and O, and you can type it in either case, with or without the hyphen. Anyone who can reach a server that isn't set up yet can try codes, so the server limits wrong codes from all addresses together: after 10 within an hour, each further attempt waits 30 seconds, then twice as long each time, up to 15 minutes. That allows about a hundred guesses a day, so set up the server before exposing it beyond your tailnet or network.

## Tailscale

The same container with a Tailscale sidecar, so it has a private HTTPS address on your tailnet.

    docker compose -f deploy/compose.tailscale.yaml up -d --build
    docker compose -f deploy/compose.tailscale.yaml exec tailscale tailscale up
    docker compose -f deploy/compose.tailscale.yaml exec tailscale tailscale status
    docker compose -f deploy/compose.tailscale.yaml exec journal setup-code

Follow Tailscale's sign-in URL to join your tailnet. Enable HTTPS certificates in the tailnet when prompted by Tailscale. Connect the app using the assigned HTTPS .ts.net address. Clients must join the same tailnet or be explicitly allowed by its sharing/access policy. Serve is private; Funnel is disabled. A Tailscale auth key can optionally be passed as TS_AUTHKEY for automated provisioning; treat it as a secret and remove it after enrollment. Tailnet policy remains under your control.

### Finding the server on your network

The optional `lan` Compose profile announces the server on your local network, so the app lists it under **Servers on This Network** when you connect a device. Set `JOURNAL_URL` to the HTTPS address your devices use (with Tailscale, `https://<JOURNAL_HOSTNAME>.<tailnet>.ts.net`; `tailscale status` shows the tailnet name), for example in `deploy/.env`, and start the profile:

    echo "JOURNAL_URL=https://journal.example.ts.net" > deploy/.env
    docker compose -f deploy/compose.tailscale.yaml --profile lan up -d

The announcer is a small Avahi container on the host network: it runs without root or capabilities, with a read-only file system and no D-Bus, and only uses the mDNS port 5353. `setup-code` also prints `JOURNAL_URL` with the code, so you can check you're setting up the server you meant. The profile announces that a My Journal server exists, the host's name and its HTTPS address, including a tailnet name, to everyone on that network. The announcement doesn't cross Tailscale. Leave the profile off if that isn't acceptable; you can always type the address instead. A discovered server is only a suggestion: check the address the app shows before you enter a setup code or password.

The Tailscale sidecar is pinned to an exact version and image digest in `deploy/compose.tailscale.yaml`, so the moving `stable` tag cannot change a deployment silently. Dependabot proposes updates to the pin; review them before deploying.

## Running the server on a Mac

The My Journal apps are only clients, so to sync through a Mac, run the container there with [Docker Desktop](https://www.docker.com/products/docker-desktop/) or [OrbStack](https://orbstack.dev). It runs on Apple silicon and Intel Macs. From the project root, use the Tailscale example above:

    docker compose -f deploy/compose.tailscale.yaml up -d --build
    docker compose -f deploy/compose.tailscale.yaml exec tailscale tailscale up
    docker compose -f deploy/compose.tailscale.yaml exec journal setup-code

The Tailscale container joins your tailnet as its own machine, named `journal` unless you set `JOURNAL_HOSTNAME`, and gives the server a private HTTPS address ending in `.ts.net`. Connect every device that syncs to that address, including this Mac if you also write on it; each needs Tailscale. To try the server on this Mac alone, `deploy/compose.yaml` is enough: connect My Journal on the Mac to `http://127.0.0.1:8080`, which other devices can't reach.

- Your devices sync only while the Mac is on and awake. Set it not to sleep automatically, and set Docker Desktop or OrbStack to open when you log in; the containers then start again by themselves.
- The server's data is in the `journal-data` volume, inside Docker Desktop's or OrbStack's storage, not in your user folder. Make [backups](#backups) as on any other host and copy them off the Mac.
- On a Mac, containers run in a virtual machine, so the `lan` profile's announcement doesn't reliably reach your network. Type the server's address instead.

## Public hosting

The same container behind a reverse proxy, so it has a public HTTPS address. Place the service behind an HTTPS reverse proxy that terminates TLS with a valid certificate. Do not publish the raw HTTP port or forward setup-code files. Set the server up before you make it reachable from the internet, so no one else can try setup codes. Device authentication remains required even inside a private network. Anyone who can reach the server can try to guess your master password through it, slowed down after 20 wrong attempts an hour, and anyone with its data or backups can guess offline, so a public server relies on a strong password. Prefer a private network such as Tailscale when you don’t need public reachability (see [SECURITY.md](../../SECURITY.md#password-guessing)). While the app is open, the server holds its sync requests for up to 25 seconds so new changes arrive at once; give your proxy a response and idle timeout of at least 30 seconds. Behind a shorter one, the apps still sync, by asking every few seconds.

Use the [public HTTPS deployment example](https.md) for a complete Caddy and Compose setup with a private backend network and automatic certificates.

## Reverse proxies and host names

Anonymous requests (setup, recovery, starting a pairing request) are rate-limited per client address, and device-authenticated requests per device, so strangers can’t use up the limits your devices rely on. Behind a reverse proxy, the server sees the proxy’s address. To limit each client separately, list the proxy in `Journal__TrustedProxies`: IP addresses or CIDR networks, separated by `;` or `,`. The server then takes the client address from the last entry of the proxy’s `X-Forwarded-For` header, and only for connections from those addresses. List only the proxy immediately in front of the server, and only an address nothing else can connect to the server from: the server can't tell another program at that address from the proxy, so such a program could claim any client address and escape the limits. The proxy must replace a client's X-Forwarded-For with the address it received the request from, not pass the client's value on or append to it. Caddy does this for clients it doesn't trust itself. With `deploy/compose.tailscale.yaml`, Tailscale Serve connects from 127.0.0.1 inside a network namespace only it and the server share, which is why that example can trust 127.0.0.1. Without the setting, everyone behind the proxy shares one limit, and a stranger can slow down new pairing requests. An invalid entry stops the server from starting.

- The [HTTPS example](https.md) trusts its internal backend network, `JOURNAL_BACKEND_SUBNET` (default `172.16.231.0/28`). Set that variable to another private range if the default overlaps a network on your host.
- The Tailscale example trusts Tailscale Serve on `127.0.0.1`.

A server that listens only on loopback, such as the standalone server package, accepts only the host names `localhost`, `127.0.0.1`, `[::1]` and `*.ts.net`, which blocks DNS rebinding attacks from web pages on the same machine; other host names get 400. `deploy/compose.yaml` applies the same list through `JOURNAL_ALLOWED_HOSTS`, because its port is published on loopback only. Tailscale Serve needs no change. If you put your own reverse proxy on the same machine in front of such a server and it forwards its own host name, such as `journal.example.com`, add that name to the `AllowedHosts` setting (or to `JOURNAL_ALLOWED_HOSTS` with compose.yaml). Entries are separated by `;`, and the setting replaces the default list, so keep the defaults you still use: for example `AllowedHosts="localhost;127.0.0.1;[::1];journal.example.com"`. A server listening on other interfaces, as in the HTTPS example, accepts any host name unless `AllowedHosts` is set.

## Backups

Do not copy a live SQLite file without its WAL. Use the server's maintenance command, which takes a consistent SQLite backup and copies immutable referenced attachments.

    docker compose -f deploy/compose.yaml exec journal dotnet Journal.Api.dll --backup /data/backups/backup-2026-09-20

Choose a new destination each time and copy it off the server. Store the password or recovery key separately. A backup directory is complete only when backup-version exists. Backup retains the library’s encryption choice and includes journals, attachments, device credential hashes and recovery material. With encryption off, journal content and images are readable. Treat every backup as private data.

To restore, stop the server and use --restore with an empty target data directory (set Journal__DataDirectory or pass --Journal:DataDirectory=<directory>; maintenance commands read the same configuration and options as the server). Then restart the service. Restoring signs out every device, because the backup may include access you revoked later; the command prints how many. Reconnect each device you still use: in My Journal, open Settings > Sync, choose Reconnect… and enter your master password or recovery key; for a library without a password, run --recovery-code once for each device. The restored server also gets a new identity, so reconnected devices re-read it and send back changes the backup doesn’t have; edits made elsewhere after the restore are offered for review instead of being overwritten. The command refuses to overwrite a nonempty data directory. It validates database integrity, supported schema, image hashes, and the version 2 database digest before committing. It rechecks staged copies and blocks server startup if a restore was interrupted. Preserve the original backup until recovered journals and images have been verified with the native client.

For a backup already stored in a server Docker volume, restore into a **new** named volume using the same server image (replace the example volume/image names):

```sh
docker run --rm --network none --read-only --tmpfs /tmp \
  --mount type=volume,source=YOUR_EXISTING_VOLUME,target=/source,readonly \
  --mount type=volume,source=journal-restored,target=/data \
  journal-server:local --restore /source/backups/backup-2026-09-20
```

Stop the old service before pointing its `journal-data` volume configuration at `journal-restored`. Keep the old volume and backup until recovery is verified. A failed restore may leave `restore-in-progress` and staging files in the new volume; use another empty target for the retry. Do not delete that marker to force the app to start. See [the server backup format](../../protocol/server-backup.md) for validation and compatibility boundaries.

## Updates

The Compose files build the checked-out source by default. To use a published image instead, set `JOURNAL_IMAGE` to its `ghcr.io/…@sha256:…` reference from the release notes, then run `docker compose … pull journal` and `docker compose … up -d --no-build`. Back up before updating. Database migrations run at startup: before migrating an existing database, the server copies it to `journal.pre-migration.db` in the data directory, replacing any earlier copy. If a migration fails, stop the server and restore that copy or a backup with the matching older version. The server refuses to start on a database written by a newer version and leaves it unchanged; install that version or later instead of downgrading. /health checks the process; /ready checks database connectivity. Container logs go to standard output and never intentionally include journal content or credentials.

## Recovering an unencrypted library

New unencrypted libraries have no master password. Add another device by approving its pairing code on a connected device. If no connected device remains, a server administrator can generate a one-time code:

```sh
docker compose -f deploy/compose.yaml exec journal dotnet Journal.Api.dll --recovery-code
```

In the app, connect to the server and choose **Use a Recovery Code**. The code works once, or until another code replaces it. Never paste it into support reports. This administrative command does not recover encrypted libraries; those need their master password. Restoring an unencrypted app archive requires no password, and sync must be connected again after restore.
