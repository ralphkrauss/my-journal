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

## Steps

1. The person chooses Stop Syncing….
2. A confirmation: title `settings.sync.stopSyncing.title` ("Stop syncing with {host}?"), message `settings.sync.stopSyncing.message` plus, when items haven't reached the server, `settings.sync.stopSyncing.messageUnsent`; buttons `settings.sync.stopSyncing.confirm` and `common.cancel`.
3. Stop Syncing:
   1. This device forgets its connection credential and stops syncing at once.
   2. Pending changes stay, marked as not yet sent; Not on Server Yet disappears with the connection.
   3. The server is asked to revoke this device's access, in the background; if it doesn't answer, nothing more is done (the device may stay listed on other devices, where it can be revoked).
4. Settings ▸ Sync shows the not-connected state: Connect to a Server… and `settings.sync.footer.notConnected`.

## Rules

- Nothing is deleted. The library keeps the identity it last synced with, so connecting to the same server later continues by identity and sends what waited.
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
