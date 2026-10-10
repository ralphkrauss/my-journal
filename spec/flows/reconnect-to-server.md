---
id: reconnect-to-server
title: Reconnect after the server changed
features: [sync-recovery]
sources:
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/ConnectionFlow.swift
  - apps/apple/JournalApp/Model/ServerJoining.swift
  - apps/apple/JournalApp/Views/ConnectionView.swift
  - apps/apple/JournalApp/Views/ConnectionSteps.swift
  - apps/apple/JournalApp/Views/DevicesSection.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/SyncHealth.swift
  - docs/design/sync-health-and-recovery.md
  - docs/design/1-1-conflicts-and-reconnect.md
  - docs/design/1-1-encryption-and-passwords.md
---

# Reconnect after the server changed

## Purpose

When sync stops because of the server, not the network, the person takes one action and this device continues with its journals intact: the server was reset and needs setting up again; it was restored or replaced and doesn't know this device; or this device's access was removed. One action, Reconnect…, covers all three.

## Entry points

The state's single action, **Reconnect…** (`common.reconnect`, command `sync-reconnect`), shown in Settings ▸ Sync (the Server section, once) and in Sync Status ([sync-recovery.md](sync-recovery.md), step 2, which owns the states, their messages and when automatic sync stops). The state decides what follows, not the label:

- the server was reset and waits for a setup code;
- the server was restored or replaced and doesn't recognise this device, or this device's access was removed (revoked, or its credential no longer works).

Also: Settings ▸ Agent Access shows Reconnect… with `settings.agents.connect.noAccess` when the server refuses this device. Settings ▸ Sync ▸ Devices has no reconnect button: while the server refuses this device the Devices section is absent.

## Steps

1. The action opens the sheet titled `settings.connect.reconnect.title` ("Reconnect") with this device's server address filled in, and checks the server at once (no Continue needed). Opened by Connect to a Server… the same sheet is titled `settings.connect.title`. The title is fixed when the sheet opens.
2. What follows depends on the server:

### Server was reset

1. The server isn't set up, so the flow goes straight to the setup-code step. A setup code from the server is always required: the person types the new one.
2. Enter {credential} (the server's recovery secret is derived from it).
3. Setting Up…: the server is set up from this device: its journals are uploaded as they are, with their identities and encryption, and the library keeps its password. Server Is Ready. Other devices then use Reconnect….
4. The old connection's keychain item is removed once the new one is saved. The new server identity makes the first sync compare everything, so the whole library is sent and every image checked.
5. If another device set the server up meanwhile: `messages.connection.setUpElsewhere`, and the flow returns to the address. Continuing then takes the path below.

### Server restored or replaced, or access removed

1. The server is set up, so this device signs in: Enter {credential} (Sign In); Use a Connected Device Instead… is also available. A server without encryption is refused with `messages.connection.encryptionOff`.
2. On access:
   - if the server holds this same library (it holds a record this library synced before, or is empty, and for an encrypted server the same key): this device continues by identity, keeping its pending changes; nothing is merged. Identical records are adopted, different ones keep both versions ([flows/resolve-conflict.md](resolve-conflict.md)), missing ones are sent;
   - if the server holds another library: **Merge Journals** appears before anything is sent ("Merge only if {host} is your server."). Merge continues; Cancel leaves everything as it was.
3. The sheet closes; sync resumes. Cancel or Back from Merge Journals gives up the access just granted, and nothing was sent (owner decision, 2026-10-06; the landing steps are in [flows/connect-to-server](connect-to-server.md), Merge Journals).

## Errors

As in `flows/connect-to-server` (steps 6, 8, 9, 10), and additionally:
- `messages.connection.reconnectSameServer` ("Reconnect to the same server to keep your journals together.") if the address now points to a different server than the one this device was connected to;
- `messages.connection.alreadyConnected` ("This device is already connected to this server.") if the server still accepts this device (nothing to reconnect).

## Rules

- Reconnecting never discards local changes: journals, unsent changes and the identity they last synced with are kept until the new connection has synchronised.
- A connected library facing another library merges only after Merge Journals; nothing is sent first.
- After reconnecting, the Devices section appears again in Settings ▸ Sync and lists this device with how it was added (for example “Added with your master password on …”), without reopening the pane.
- **Access removed says what signing in again needs.** The device was removed on purpose, so the message names it: `messages.sync.accessRemoved` (“…you need your password or a connected device.”).

## Accessibility

As `flows/connect-to-server`.

## Platform notes (Apple)

- Reconnect… from a sync message (outside Settings) opens the sheet over the journal window.

## Open questions

- None beyond `flows/connect-to-server`.
