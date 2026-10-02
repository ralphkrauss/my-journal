# Security model

My Journal is in development and has no supported release yet. Passing the project's checks is not a security audit.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Do not open a public issue. Never include journal content, passwords, recovery keys or codes, connection files or real credentials in a report or its attachments.

## What encryption protects

With encryption on (the default), journal names, entries, templates, image descriptions and images are encrypted on the device with AES-256-GCM under a random 256-bit vault key before they are stored or synced. Record payloads in the local database are encrypted the same way; the database's record IDs and sync bookkeeping are not, and this is not whole-device encryption. The [protocol](protocol/README.md) specifies the formats.

The vault key is wrapped with a key derived from the master password (PBKDF2-HMAC-SHA256, 600,000 iterations), and this password envelope is stored on the server so another device can recover the key. The app sends the server only a value derived from the password, never the password itself, and a server that follows the protocol never receives the vault key or readable content. The sections below describe what a server operator, a compromised server, or someone with a copy of the data can still learn or do.

### Password guessing

The server gives out the wrapped vault key only to a device that proves it knows the password, by sending the value derived from it, or to a device that is already connected. Anyone else who can reach the server can check a guess only by asking the server, which limits guesses from all network addresses together: after 20 wrong attempts within an hour, each further attempt waits longer, up to 15 minutes. Connected devices, pairing and password changes are not affected by this limit. Only someone with the server's database or a backup can guess offline, as fast as their hardware allows, and so can anyone with an archive. A correct guess, together with a copy of the encrypted data, reveals every journal. The app accepts a password of any length, so a short one is your choice and easier to guess this way. Use a long, generated password from a password manager, and prefer a server that only your devices can reach, such as one on Tailscale or another private network, over one on the public internet. A server from before this protection (without the `private-envelope` capability) gives the envelope to anyone who asks, so it can be guessed offline.

A server checks a password by the value derived from it, so when you recover your journals it also receives that value for a mistyped password, never the typed text. A password is normalized to Unicode NFC before it's used, so it works however its accented characters were typed or pasted.

### Changing the password and revoking devices

The vault key never changes. Changing the master password wraps the same key again and replaces the server's envelope, but earlier server backups and archives keep the old envelope, and anyone with an old copy of it can still unwrap the vault key with the old password. A password change therefore doesn't help if the old password was exposed: whoever has it and an old envelope can decrypt all current and future data they obtain. Revoking a device stops its server access, but the device keeps the vault key and everything it downloaded. There is currently no way to replace the vault key.

### What the server can see

With encryption on, the server, and anyone with its data or backups, can see:

- each record's ID and kind (journal, entry or template), and so how many of each exist;
- every revision of every record, kept permanently: its size (text isn't padded, so size follows length), when the server received it, and which device wrote it, which usually shows when entries were written and edited;
- which records were probably deleted permanently, because their final revisions are small, content-free markers;
- each image's ID, exact size (the original plus 28 bytes), the SHA-256 of its encrypted file and when it was uploaded, but not which entry uses it;
- each device's name, when and how it was added (setup, recovery with the password or a recovery code, or pairing, and which device approved it) and whether it was revoked. On a Mac the name is the computer name from System Settings; on iPhone and iPad it's the name iOS provides to apps, usually the model name;
- the password envelope and its format, which shows whether the library uses encryption;
- network addresses, and when and how often each device connects. Devices sync every few seconds while the app is open and unlocked, so this shows when the app is in use.

It can't see journal names, titles, entry dates, text, image content, image descriptions or templates.

### What a malicious server can do

A server operator can deny service, delete data or roll the server back. A restore made with `--restore` gives the server a new identity, and devices then re-read it, upload what it lost and offer differing edits for review. A rollback made by copying files, from a volume snapshot or from a Time Machine backup keeps the old identity. Current apps notice it at their next sync, before sending anything, by asking the server to confirm the last change they read, and then compare everything the same way; see [server identity after restore](protocol/README.md#server-identity-after-restore). This relies on the server's answers, so a malicious server can hide a rollback.

A server can also present an earlier encrypted version of a record as its newest revision. Devices without unsaved or conflicting edits to that record accept it, and the version it replaces isn't kept in Version History.

When you add a device, both devices show a six-digit check code, and both ask you to confirm that the codes match. The approving device sends the vault key only to the device whose code you confirmed there, so a server can't obtain your vault key through pairing. The new device uses nothing it receives until you choose Connect, and then accepts a key only from the approving key behind the code it shows, so a server can't pose as your other device and have the new device join a library whose key the server knows. Compare the codes on both devices before you choose Approve and Connect. If you cancel on the new device after the other device approved, the new device gives up the access it received; if it can't reach the server to do so, revoke it in the other device's Devices list.

When the new device scans a code shown by your other device instead, no check code is needed. The scanned code contains a secret the server never sees and your other device's one-time key, so the server can't make a request your other device accepts, change the device name it asks you about, or substitute its own key ([invite pairing](protocol/README.md#invite-pairing)). Someone who photographs the code while it's shown and can reach your server could use it first; you would still be asked to add a device with their device's name, and your new device reports that the code was already used. Only add a device whose name you expect.

Keep independent backups and your master password: encryption doesn't guarantee availability or detect every rollback.

## Libraries without encryption

Encryption can be turned off when creating a library. Records, including history and conflicts, are then stored and synced as base64-encoded readable JSON, and images as readable bytes, locally, on the server and in archives. Base64 is not encryption. Anyone with access to the files, the server or a backup can read and change the content, and plaintext records have no cryptographic integrity protection. New libraries without encryption have no master password (recovery format 4). Devices still need authenticated server access, through pairing or a one-time recovery code generated by the server administrator. Restoring an archive needs no password; its checksums detect accidental damage, not deliberate changes. Older format-3 libraries keep their access password. App Lock doesn't encrypt anything.

Journals imported from an archive, or added from this device when connecting to a server, take the mode of the library they join. The app refuses to add encrypted journals to a server without encryption.

### Turning on encryption later

A library created without encryption can be encrypted later in Settings > Privacy (docs/design/enable-encryption.md, [protocol](protocol/README.md#turning-on-encryption)). Encryption can't be turned off again. The app:

1. encrypts a complete copy of the library under a new vault key, with the same records, earlier versions, reviews and images, beside the library;
2. checks that every record and image decrypts to the original;
3. switches to the copy with one configuration write. The unencrypted copy is removed once the new one opens and, when synced, has uploaded.

When the library is synced:

- The server deletes every record, revision, receipt and image it held, its pre-migration database copy, and its free database pages.
- The server signs out every other device, removes agent access granted through it, and takes a new identity.
- Other devices sign in again with the master password. They encrypt their own copy the same way, and edits they hadn't synced become reviews.

A library with an access password (format 3) needs it to turn on encryption. A format-4 library has no password, so a device's credential is enough. Someone who stole a device credential could therefore encrypt the server under a password of their own and sign out the other devices, though each device keeps its own copy. That credential could already read and change everything.

What was stored before stays readable wherever it was copied. This includes earlier archives, server backups made with `--backup`, device backups such as Time Machine or iCloud, filesystem snapshots, and deleted blocks on disks. The app says so when it finishes. Make a new archive and delete the old ones, and replace server backups.

## Devices and keys

The app and the OS account it runs in are trusted with readable content and keys. Keys are kept in the Keychain: the data protection keychain on iPhone and iPad and in Mac builds signed with the team's provisioning profile, and otherwise the Mac login keychain. A Mac key found in the login keychain is copied to the data protection keychain the first time an entitled build reads it, and the old item is removed only after the copy succeeds. Unit tests that run inside the app keep keys in memory; an app launched by UI tests, like any development build, uses the Keychain of the account or simulator it runs in. Use the OS screen lock, disk encryption and account protections.

App Lock uses the system's device owner authentication (Face ID, Touch ID or Optic ID, with the device passcode or Mac login password as the fallback) to hide the interface. It isn't an encryption key, the vault key is not bound to it, and it doesn't protect against malware, someone with access to the same account, or someone who knows the device passcode. The app stores no PIN or verifier of its own; an earlier App Lock PIN's verifier is removed from the configuration file at the first launch of this version. While App Lock is on, iPhone and iPad cover the app's windows when it isn't active, so the app switcher doesn't show journal content. The app can keep the vault key and an unsaved draft in memory while locked.

When the app joins an existing server (by pairing, or with the password or a recovery code) or imports an archive, it builds a new copy of the library. It deletes the previous copy and its Keychain items once the new copy has opened and, when connected, synchronized; if the app quits first, it finishes after the next launch. Until then, permanent deletion doesn't reach the previous copy, and it never reaches older server revisions, backups, archives or copies held by others. See [deletion semantics](protocol/permanent-deletion.md).

When you add an image from Photos, the camera or Files, or by pasting or dropping it, the app removes where it was taken: GPS coordinates and place names. Other metadata, such as the capture time and camera details, stays inside the image, encrypted with it in encrypted libraries and readable in libraries without encryption. Stored images are never changed, so images added by earlier versions of the app keep their location.

## Agent access through MCP

A sync server is also a Model Context Protocol server ([contract](protocol/agent-access-server.md)). An MCP client authorizes with OAuth 2.1 (PKCE, audience-bound tokens, rotating refresh tokens), and the owner allows it in the app, where the client's request appears, by entering the two-digit number its authorization page shows and choosing its journals. Access is read-only and limited to those journals; the server accepts only tokens it issued for its own MCP address, forwards no token anywhere, and treats device and agent credentials as separate.

**How the server reads only what you shared.** For each agent, your devices keep a copy of the chosen journals on the server, encrypted with a key of its own (AES-256-GCM, keys derived with HKDF), and update it from what has synced. The copy's key is sealed under your vault key for your devices. The server never stores it in the clear: each of the agent's tokens carries a secret, and the server keeps the key wrapped under that secret only while the token lives. When the agent calls a tool, the server unwraps the key, decrypts the entries it answers with, and discards both. Your other journals stay end-to-end encrypted; no token, key or wrap covers them. The server deletes wraps with their tokens, overwrites deleted database content (`secure_delete`) and checkpoints its write-ahead log.

**What that means:**

- **Every live token is key material.** Someone with one of an agent's live tokens and a copy of the server's database, or the server itself while it answers the agent, can read that agent's journals. Expired, rotated and revoked tokens have no wrap left; a database backup made while a token was live still works with that token.
- **When you allow an agent,** your device sends the server a one-time secret, which the server keeps in memory until the agent collects its tokens (minutes at most). **Anyone who controls the server could read the journals you shared while that agent has access** — this is the trade-off of an MCP endpoint on the server, and Agent Access says so under the server's MCP address.
- **Where tokens are kept:** by the agent's app. Cloud connectors (custom connectors in the Claude apps and claude.ai, ChatGPT) keep them at their providers, which can use them until access ends or you revoke it. A proxy that logs `Authorization` headers stores key material; the shipped Caddy configuration logs no requests.
- **What the server sees:** for each agent, the name the client gave, its client ID and redirect host, when it was allowed and by which device, when access ends, when it was last used and which tools it called when (never arguments or results), and its copy's number of items, sizes, update times and whether an item returned to earlier content. Timing and sizes can show which records are probably shared. Registered clients' names and redirect addresses.
- **Revoking** deletes the agent's access, tokens, key wraps, copy and activity at once. It can't take back what the agent read, or what its provider stored.
- **Libraries without encryption:** the copy's key is readable on the server, like everything else there.
- **Consent.** Requests appear on your devices, but approving one needs the number shown on its authorization page, so a request you didn't start (a stranger's, or an old one) can't be approved by mistake; a wrong number declines the request. The app shows which app is asking and where access goes; client names are shown without control or formatting characters and shortened. Only allow a request you just started from your agent. A client that returns to `localhost` can't be verified, even when it presents a well-known app's identity document.
- **Scope.** Access is per journal. **All Journals** also covers journals created later, and is shown as such. Turning a journal off removes it from the agent's copy in the same step, and devices can only publish with the agent's current settings.
- **Transport:** MCP and OAuth need HTTPS, except for loopback addresses. The server validates `Origin` headers, the MCP headers against the request, PKCE, redirect URIs (HTTPS or loopback only), the `resource` of every token, and fetches client metadata documents only from public addresses, without redirects.
- **Restores and encryption.** Restoring a server backup removes every agent. Turning on encryption removes every agent too; earlier backups of the unencrypted server keep their readable settings.

Journal text is returned to agents as untrusted data, never as instructions, but this doesn't replace an agent's own defenses against prompt injection.

## Hosting

Follow the [self-hosting instructions](docs/self-hosting/README.md): HTTPS for every connection except loopback, persistent local storage, and one server instance per database. Protect setup codes, recovery codes and backups. Tailscale limits who can reach the server but doesn't replace device authentication or trust in your devices. Check the [distribution status](docs/distribution.md) before installing or sharing a build.

A server that isn't set up yet accepts whoever first enters its setup code. The code has 6 characters (30 bits, about 1.07 billion possible codes); see it with `docker compose exec journal setup-code`, or by running the server with `--setup-code`. The server never logs it. Wrong codes from all addresses together are limited: after 10 within an hour, each further attempt waits 30 seconds, then twice as long each time, up to 15 minutes, which allows about a hundred guesses a day. Set up the server before exposing it beyond your tailnet or network.

Signing in on a new device with the master password sends a secret derived from the password (never the password itself) to the server the person chose, as recovery always has. If someone tricks a person into signing in to their own server, for example with a fake announcement on the local network, and that server can reach the real one, it could pass the secret on and get a device credential there. The app names the server above the password field and the real server's Devices list shows "Added with your master password"; pairing with a scanned or typed code never sends anything a server could reuse. A challenge-response bound to the server's address is a possible later protocol change.

The optional `lan` Compose profile announces the server on the local network so the app can find it. Everyone on that network can then see that a My Journal server exists, the host's name and its HTTPS address, including the tailnet name when the address is on Tailscale. The announcement doesn't cross Tailscale. Anyone on the local network can also announce a server; the app treats a discovered server only as a suggestion and keeps its address visible, so check that address before entering a setup code or password.
