---
id: settings-devices
title: Settings ▸ Sync ▸ Devices
features: [devices-list, revoke-device, add-device]
sources:
  - apps/apple/JournalApp/Views/DevicesSection.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Model/DeviceOperations.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - docs/design/devices.md
  - docs/design/pre-release-ui-2026-09-27.md
  - docs/design/sync-health-and-recovery.md
  - docs/design/1-1-settings-messages-editor.md
---

# Settings ▸ Sync ▸ Devices

## Purpose

Lists the devices that can sync with this device's server, says how each was added, removes access for a lost or old device, and adds a new one. It is a section of Settings ▸ Sync ([screens/settings-sync](settings-sync.md)), not a pane of its own.

## Entry points

- Settings ▸ Sync ▸ Devices (`screens/settings-sync`). Text that sends the person here for the device task reads “Settings ▸ Sync ▸ Devices ▸ Add Device”.

## Content

One section with one header, `settings.sync.devices.header` ("Devices"), shown only while this device is connected and the server accepts it. Not connected: the section is absent (Connect to a Server… is in the Server section). Access refused (any sync state that stops automatic sync because the server doesn't accept this device): the section is absent, because the Server section already says why and offers Reconnect…. The section never carries a reconnect button of its own.

In order:
1. `settings.devices.add` ("Add Device…"), the first row, because it is the frequent task after connecting and should not sit below a long list. Disabled while loading or busy. It opens `screens/add-device`.
2. While loading: an indicator with `settings.devices.loading` ("Loading Devices…").
3. One row per device with access (revoked devices aren't listed), in the server's order:
   - the device's name;
   - for this device, `common.thisDevice` ("This Device") in secondary text;
   - how and when it was added, in secondary text (see Rules);
   - for every other device, a trailing destructive button `settings.devices.revoke` ("Revoke Access…"), disabled while a revoke is running. Its accessibility label is `settings.devices.revokeLabel` ("Revoke access for {name}"), with “, {how it was added}” appended when another device has the same name. At accessibility text sizes the button sits under the text.
   The name and the lines below it are read as one element; the button is its own element.
4. An error line in secondary text, when there is one, followed by `common.tryAgain` (retries the failed revoke, or reloads), disabled while busy.

### Revoke confirmation

A confirmation with a visible title:
- Title: `common.revokeAccessFor` ("Revoke access for {name}?"); `settings.devices.revoke.titleFallback` only while the confirmation closes.
- Message: `settings.devices.revoke.message` ("This stops future sync. Journals already downloaded to that device can’t be erased remotely."). When another device has the same name, it's preceded by how this one was added and “. ” (for example “Added by Alex’s MacBook Pro on 28 Sep 2026. This stops future sync. …”).
- Buttons: destructive `common.revokeAccess` ("Revoke Access"), `common.cancel`.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Add Device… | `add-device` | Connected, loaded, not busy | Opens Add Device; the list reloads when it closes. |
| Revoke Access… | `revoke-device` | Not this device; not while busy | Confirmation, then the server removes the device's access; it disappears from the list. |
| Try Again | `devices-try-again` | After an error | Retries the failed revoke, or reloads. |

## States

- **Not connected:** the section is absent.
- **Access refused:** the section is absent; the Server section shows the sync state's message and Reconnect… (`screens/settings-sync`).
- **Loading:** `settings.devices.loading`; Add Device… is dimmed.
- **Couldn't load:** `settings.devices.error.load` ("Couldn’t load devices. Check your connection and try again.") and Try Again. Offline: the last list stays when there is one.
- **Couldn't revoke:** `common.couldntRevokeAccess` ("Couldn’t revoke access. Check your connection and try again.") and Try Again, which retries that revoke.
- **Locked:** Settings shows only its locked text; the list is cleared and sheets close.

## Rules

- **How a device was added** (`settings.devices.added.*`):
  - approved by another device still known to the server (even if since revoked): `settings.devices.added.byDevice` ("Added by {device} on {when}");
  - with a pairing code whose approver isn't known: `settings.devices.added.pairingCode`;
  - when the server was set up: `settings.devices.added.setup` ("Added during server setup on {when}");
  - by signing in with the credential: `settings.devices.added.recoveryKey` (recovery key), `settings.devices.added.masterPassword` (master password);
  - unknown: `settings.devices.added.unknown` ("Added on {when}").
- **{when}** is the abbreviated date (“28 Sep 2026”). When two listed devices would read exactly the same (same name and sentence), both add the time (“28 Sep 2026 at 14:05”); if still the same, both add the first eight characters of their identifier after “ · ”.
- This device can't revoke itself here; Stop Syncing in Settings ▸ Sync gives up its own access.
- **When the list is read:** when the Sync pane appears, when Add Device closes, and when a Reconnect or Connect sheet opened from the pane closes. A revoke takes that device out of the list without reading it again. The list is not read on every background sync.
- A load that the server refuses as unauthorised makes the device learn why with a sync; the result appears in the Server section and the Devices section disappears.
- Revoking stops future sync only; it can't erase what that device already downloaded.
- Device names are the names the devices reported (on iPhone and iPad often just “iPhone” or “iPad”, which is why the added line tells them apart).
- There is no rename: a device's name is what it reported when it was added.

## Accessibility

- The header is the section's one heading, followed by Add Device… and one row per device. Each device is one element (name, This Device, how it was added); its Revoke Access… button names the device, and says how it was added when names repeat.
- A list that loads or reloads is silent. An error is announced when it first appears; Try Again keeps focus when pressed. After Add Device closes, focus returns to the button.

## Platform notes (Apple)

- iPhone and iPad: a section of the pushed Sync pane; the revoke confirmation is an action sheet with a visible title.
- Mac: a section of the Sync tab; the confirmation is a dialog. Add Device opens as a sheet on the Settings window.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
