---
id: settings-devices
title: Settings ▸ Sync ▸ Devices (Windows)
spec: screens/settings-devices.md
features: [devices-list, revoke-device, add-device]
status: draft
sources:
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
---

# Settings ▸ Sync ▸ Devices (Windows)

The devices that can sync with this server, how each was added, revoking access and adding a device. Since 1.1 this is a section of Settings ▸ Sync, not a pane of its own, and on Windows a group of the [Sync page](settings-sync.md#devices-group-connected-and-the-server-accepts-this-pc). Behaviour and copy keys are the spec's [Settings ▸ Sync ▸ Devices](../../../screens/settings-devices.md); the shell and patterns are in [settings](settings.md#card-patterns).

## Controls

A group of the Sync page under the heading `settings.sync.devices.header` (a `TextBlock`, level 2). It has no breadcrumb or page of its own. A text that sends the person here ("Settings > Sync > Devices > Add device") names the group.

| Spec element | Control | Notes |
| --- | --- | --- |
| Not connected | The group is absent (the Sync page's server card offers Connect to a server…) | The spec: absent, not dimmed |
| Add Device… | The first card of the group: an [action card](settings.md#card-patterns), `Header` `settings.devices.add` and an accent `Button` `settings.devices.add` in its content, icon Add (E710) | The spec puts it first because it is the frequent task after connecting and should not sit below a long list. Disabled while loading or busy. Opens [add-device](add-device.md); the list reloads when the dialog closes |
| Loading | A card with a small indeterminate `ProgressBar` and `settings.devices.loading` (the page stays usable, so not a ring) | Replaced by the list |
| One section per device | One `SettingsCard` per device with access, in the server's order. `Header` the device's name; `Description` two `Caption` lines: `common.thisDevice` (this device only) and how and when it was added; trailing, for every other device, a `Button` `settings.devices.revoke` | Revoked devices are not listed. This device has no button. The card is one UI Automation element named "{name}, {this device}, {how added}"; its button is a child with its own name |
| How a device was added | `settings.devices.added.byDevice`, `settings.devices.added.pairingCode`, `settings.devices.added.setup`, `settings.devices.added.recoveryKey`, `settings.devices.added.masterPassword`, `settings.devices.added.unknown` | Chosen by the spec's rules. {when} is the abbreviated date in the user's regional format (`DateTimeFormatter`, "day month.abbreviated year"); the spec's disambiguation (time, then the first eight characters of the identifier after " · ") applies unchanged |
| Revoke button label for Narrator | `AutomationProperties.Name` `settings.devices.revokeLabel`, with ", {how it was added}" appended when another device has the same name | The visible label is `settings.devices.revoke` |
| Error line | An `InfoBar` (Error) under the list: `settings.devices.error.load` or `common.couldntRevokeAccess`, `ActionButton` `common.tryAgain` (retries the revoke or reloads; disabled while busy) | |
| Access refused | The group is absent; the Sync page's status bar shows the sync state's message with `ActionButton` `common.reconnect` | Add device is not offered; the group never carries a reconnect button of its own |
| The PC's name | A `TextBlock` in `CaptionTextBlockStyle`, secondary, under the list: a new sentence that says this PC shares its name, as the system reports it (D45), with the server and the person's other devices (new copy, D45) | The disclosure that goes with D45's default of sending the PC's name: a PC name can include a person's name or a work asset tag |

### Revoke confirmation

`ContentDialog`: `Title` `common.revokeAccessFor`; content `settings.devices.revoke.message`, preceded when another device has the same name by how this one was added and ". " (the spec's example); Primary `common.revokeAccess`; Close `common.cancel`; `DefaultButton` None ([Dialog patterns, 7](settings.md#dialog-patterns)). While it runs, the revoke button is disabled and the card shows a small indeterminate `ProgressBar`. `settings.devices.revoke.titleFallback` is not used: a Windows dialog does not blank its title while it closes.

On success the card leaves the list and focus moves to the next card, or to Add device when it was the last (the first card of the group). The result is not announced (nothing was lost on screen that the person did not cause), apart from errors.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Cards in the column; the revoke button at the trailing edge | Mac Sync tab |
| Small and text size 200% or more | The revoke button moves under the two lines at full width; Add device full width | iPhone pushed pane |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `revoke-device` | Button in the device's card | — | Not this device; not while busy |
| `add-device` | Accent button in the first card of the group | — | Connected, loaded, not busy, access not refused |
| `devices-try-again` | Action button of the error bar | — | After an error; disabled while busy |

The page has no device shortcuts. Delete does not revoke: revoking always asks, and a list key that can remove a person's other devices would be too close to a slip.

## Copy differences

Sentence case applies ("Loading devices…", "This device"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.devices.revoke` | Revoke Access… | Revoke access | ellipsis: it only asks for confirmation (platform.md, 12.2) |
| A new note under the list: this PC's name is shared with the server and the person's other devices | none | In [copy-proposals.md](../copy-proposals.md) | new, D45 |

## Accessibility

- Each device card is one element with its name, whether it is this device and how it was added; its Revoke button names the device (`settings.devices.revokeLabel`) and says how it was added when names repeat.
- Loading is a progress bar with the name `settings.devices.loading`. Errors are read when the bar opens.
- Focus order: Add device, then the list top to bottom, each card then its button, then the error bar. After Try again focus stays on the button; after the confirmation closes it returns to the Revoke button, or to the next card when that one has left.
- Contrast themes and 225% text: card text wraps; the bar keeps its icon.

## Different by design

- **Cards, not a form.** Apple shows a section per device with a destructive button row. Windows shows a card per device with a trailing button that is not coloured red: the dialog that follows carries the warning ([platform.md, 8.1, rule 3](../platform.md#81-rules)).
- **No title fallback** (see above).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D9 (device rename), D45 (device name a PC sends).
