---
id: stop-syncing
title: Stop syncing (Windows)
spec: flows/stop-syncing.md
features: [stop-syncing]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Stop syncing (Windows)

This PC stops using its server and keeps everything it has, for example before moving to another server or when the server is gone for good. Steps and rules are the spec's [stop-syncing](../../../flows/stop-syncing.md); the Sync page is [settings-sync](../../../screens/settings-sync.md).

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Entry point | A card with a Stop syncing `Button` in its own group on the Sync page ([settings-sync](../screens/settings-sync.md)), `settings.sync.stopSyncing` ("Stop syncing", no ellipsis, [12.2](../platform.md#122-ellipsis)); disabled while the library is being replaced | Shown only while connected |
| Confirmation | A `ContentDialog`. Title `settings.sync.stopSyncing.title` (a question naming the host); content `settings.sync.stopSyncing.message` and, when items have not reached the server, `settings.sync.stopSyncing.messageUnsent` (plural); Primary `settings.sync.stopSyncing.confirm`; Close `common.cancel`. **No default button** | Platform.md 8.1 lists Stop syncing among the confirmations whose Enter never chooses. It is not destructive (nothing is deleted), so the Primary button has the normal style, not a warning colour or icon, as the spec says |
| After Stop syncing | The dialog closes; this PC forgets its connection credential (removed from the secret store, [14](../platform.md#14-secure-storage)) and stops syncing at once; pending changes stay, marked as not yet sent; the Sync page shows the not-connected state with Connect to a server… and `settings.sync.footer.notConnected`; the Sync status button and any sync bar go | The server is asked in the background to revoke this device; if it does not answer nothing more is done |
| Former Mac server | Not applicable | `settings.sync.footer.formerMacServer` and its Learn more link exist only on the Mac ([12.3](../platform.md#123-vocabulary)) |

Rules of the spec kept: nothing is deleted; the library keeps the identity it last synced with, so connecting to the same server later continues by identity and sends what waited; Cancel changes nothing. To follow a server that moved, Stop syncing and then connect to the new address ([sync-recovery](sync-recovery.md)).

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Default-width dialog, up to 548 epx | Mac alert |
| Small | Fills the window width | iPhone alert |
| 200% text size or more | The message wraps and the dialog scrolls | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `stop-syncing` | The Sync page's button | none | Connected and the journals are not being replaced |

Esc is Cancel. Enter chooses nothing until a button has focus; focus starts on Cancel.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)):

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.sync.stopSyncing` | Stop Syncing… | Stop syncing | ellipsis (platform.md, 12.2) |
| `settings.sync.stopSyncing.confirm` | Stop Syncing | Stop syncing | casing |
| `settings.sync.stopSyncing.message` | … choose Connect to a Server in Settings > Sync. | … select Connect to a server in Settings > Sync. | vocabulary (platform.md, 12.3) |

## Accessibility

- The title, a question, is read first, then the content; the Primary button is named by its text. Focus starts on Cancel and returns to the Stop syncing button's place (now Connect to a server…) after the dialog.
- The result is the Sync page changing; nothing is announced separately. In contrast themes and at 225% text size the dialog follows the standard dialog behaviour.

## Different by design

- **No default button** although the action is not destructive, so a stray Enter cannot end the connection ([8.1](../platform.md#81-rules)).
- **The Mac-only former-server notice is not offered.**
- **The button has no ellipsis**: it asks only for confirmation.

## Open questions

None.
