---
id: settings-devices
title: Settings ▸ Devices
features: [devices-list, revoke-device, add-device]
sources:
  - apps/apple/JournalApp/Views/DevicesView.swift
  - apps/apple/JournalApp/Model/DeviceOperations.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - docs/design/devices.md
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/sync-health-and-recovery.md
---

# Settings ▸ Devices

## Purpose

Lists the devices that can sync with this device's server, says how each was added, removes access for a lost or old device, and adds a new one.

## Entry points

- Settings ▸ Devices (`screens/settings`).

## Content

- **Not connected:** `settings.devices.notConnected` ("Connect to a server to add your other devices.") in secondary text, and the button `common.connectToServer` ("Connect to a Server…").
- **Connected**, in order:
  1. While loading: an indicator with `settings.devices.loading` ("Loading Devices…").
  2. One section per device with access (revoked devices aren't listed), in the server's order:
     - the device's name;
     - for this device, `common.thisDevice` ("This Device") in secondary text;
     - how and when it was added, in secondary text (see Rules);
     - for every other device, a destructive button `settings.devices.revoke` ("Revoke Access…"), disabled while a revoke is running. Its accessibility label is `settings.devices.revokeLabel` ("Revoke access for {name}"), with “, {how it was added}” appended when another device has the same name.
     The name and the lines below it are read as one element.
  3. An error line in secondary text, when there is one.
  4. When this device's access was refused: a button with the current sync state's reconnect action title (`messages.sync.action.setUpServerAgain`, `messages.sync.action.connectAgain` or `common.signIn`), or `messages.sync.action.connectAgain` when the state doesn't call for one. It opens Connect to a Server.
  5. Otherwise:
     - after an error, `common.tryAgain` (retries the failed revoke, or reloads), disabled while busy;
     - `settings.devices.add` ("Add Device…"), disabled while loading or busy. It opens `screens/add-device`.

### Revoke confirmation

A confirmation with a visible title:
- Title: `common.revokeAccessFor` ("Revoke access for {name}?"); `settings.devices.revoke.titleFallback` only while the confirmation closes.
- Message: `settings.devices.revoke.message` ("This stops future sync. Journals already downloaded to that device can’t be erased remotely."). When another device has the same name, it's preceded by how this one was added and “. ” (for example “Added by Alex’s MacBook Pro on 28 Sep 2026. This stops future sync. …”).
- Buttons: destructive `common.revokeAccess` ("Revoke Access"), `common.cancel`.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Revoke Access… | `revoke-device` | Not this device; not while busy | Confirmation, then the server removes the device's access; it disappears from the list. |
| Add Device… | `add-device` | Connected, loaded, not busy, access not refused | Opens Add Device; the list reloads when it closes. |
| Try Again | `devices-try-again` | After an error | Retries the failed revoke, or reloads. |
| Connect to a Server… / reconnect | `connect-to-server` / `sync-reconnect` | Not connected / access refused | Opens Connect to a Server. |

## States

- **Loading:** `settings.devices.loading`.
- **Couldn't load:** `settings.devices.error.load` ("Couldn’t load devices. Check your connection and try again.") and Try Again.
- **Couldn't revoke:** `common.couldntRevokeAccess` ("Couldn’t revoke access. Check your connection and try again.") and Try Again, which retries that revoke.
- **Access refused:** the reason, as the sync state's message: `messages.sync.signInNeeded`, `messages.sync.serverNotSetUp`, `messages.sync.serverReplaced`, or `messages.sync.accessRemoved` (the default when the reason can't be told), with the reconnect button. Add Device… isn't offered.
- **Locked:** the list is cleared and sheets close.

## Rules

- **How a device was added** (`settings.devices.added.*`):
  - approved by another device still known to the server (even if since revoked): `settings.devices.added.byDevice` ("Added by {device} on {when}");
  - with a pairing code whose approver isn't known: `settings.devices.added.pairingCode`;
  - when the server was set up: `settings.devices.added.setup` ("Added during server setup on {when}");
  - by signing in with the credential: `settings.devices.added.recoveryKey` (recovery key), `settings.devices.added.accessPassword` (access password), `settings.devices.added.recoveryCode` (one-time recovery code, servers without encryption), `settings.devices.added.masterPassword` (master password);
  - unknown: `settings.devices.added.unknown` ("Added on {when}").
- **{when}** is the abbreviated date (“28 Sep 2026”). When two listed devices would read exactly the same (same name and sentence), both add the time (“28 Sep 2026 at 14:05”); if still the same, both add the first eight characters of their identifier after “ · ”.
- This device can't revoke itself here; Stop Syncing in Settings ▸ Sync gives up its own access.
- Revoking stops future sync only; it can't erase what that device already downloaded.
- Device names are the names the devices reported (on iPhone and iPad often just “iPhone” or “iPad”, which is why the added line tells them apart).
- There is no rename: a device's name is what it reported when it was added.

## Accessibility

- Each device is one element: name, This Device, and how it was added.
- Revoke buttons name their device, and say how it was added when names repeat.

## Platform notes (Apple)

- iPhone and iPad: a pushed pane; the revoke confirmation is an action sheet with a visible title.
- Mac: the Devices tab; the confirmation is a dialog. Add Device opens as a sheet on the Settings window.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
