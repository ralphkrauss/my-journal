---
id: stop-syncing
title: Stop syncing
features: [stop-syncing]
sources:
  - apps/apple/JournalApp/Views/SyncNowRows.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - apps/apple/JournalApp/Model/FormerMacServer.swift
  - docs/design/sync-health-and-recovery.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---

# Stop syncing

## Purpose

This device stops using its server and keeps everything it has, for example before moving to another server or when the server is gone for good.

## Entry points

- Settings ▸ Sync ▸ Stop Syncing… (`screens/settings-sync`), shown while connected; disabled while the journals are being replaced.
- Encrypt Your Journals ▸ Stop Syncing… (`screens/encrypt-journals`), for a library that isn't encrypted and whose server this device has no access to, whose server is too old, or whose access password is wrong or limited. It has its own message and consequence (below).
- The unfinished notice of Encrypt Your Journals ▸ Stop Syncing…, which adopts the encrypted copy (below).

## Steps

1. The person chooses Stop Syncing….
2. A confirmation: title `settings.sync.stopSyncing.title` ("Stop syncing with {host}?"), message `settings.sync.stopSyncing.message` plus, when items haven't reached the server, `settings.sync.stopSyncing.messageUnsent`; buttons `settings.sync.stopSyncing.confirm` and `common.cancel`.
3. Stop Syncing:
   1. This device forgets its connection credential and stops syncing at once.
   2. Pending changes stay, marked as not yet sent; Not on Server Yet disappears with the connection.
   3. The server is asked to revoke this device's access, in the background; if it doesn't answer, nothing more is done (the device may stay listed on other devices, where it can be revoked).
4. Settings ▸ Sync shows the not-connected state: Connect to a Server… and `settings.sync.footer.notConnected`.

### From Encrypt Your Journals

The same confirmation (`settings.sync.stopSyncing.title`, `settings.sync.stopSyncing.confirm`, `common.cancel`, and `settings.sync.stopSyncing.messageUnsent` when items haven't reached the server) with the message `library.encrypt.stopSyncing.message` in place of `settings.sync.stopSyncing.message`. The consequence differs from the ordinary entry point: this device **can't sync with that server again**, because its library is encrypted next and a server without encryption refuses an encrypted library (`messages.connection.encryptionOff`). The other devices keep using the server and won't get changes made here. The journals stay on this device and are encrypted next; the form becomes variant A. Nothing is deleted anywhere.

### From the unfinished notice

When the server switched to the encrypted copy but this device couldn't finish, Stop Syncing… is not the ordinary operation (which refuses while the journals are being replaced). The confirmation shows `library.encrypt.adopt.message` and the operation checks once, within a bound, what the server did: if it switched, or can't answer, the verified encrypted copy becomes this device's library and the connection is dropped; if it did not switch, the original library is kept, the copy discarded and the connection dropped. See `flows/encrypt-journals`.

## Rules

- Nothing is deleted. From Settings ▸ Sync, the library keeps the identity it last synced with, so connecting to the same server later continues by identity and sends what waited. This is not true for the Encrypt Your Journals entry points: there the library is encrypted next, and a server without encryption refuses an encrypted library, so this device can't rejoin that server.
- Stop Syncing isn't a destructive action and has no destructive styling.
- Cancel changes nothing.

### Former Mac server (computer only)

Once, when the library opens: if the computer's library was connected to the server earlier versions of the Mac app ran on itself (address `http://127.0.0.1:46371`), it stops syncing as above without asking the server (nothing answers there), and Settings ▸ Sync shows `settings.sync.footer.formerMacServer` with Learn More until the library connects to a server. The old server's files are kept, even by Erase, because they may hold the only copy of other devices' changes. This happens only once per data folder, so reconnecting to that address later never stops syncing again.

## Accessibility

- The confirmation's title is visible and read first.

## Platform notes (Apple)

- The former-server step exists only on the Mac.

## Open questions

- None.
