---
id: settings-devices
title: Settings ▸ Devices (Windows)
spec: screens/settings-devices.md
features: [devices-list, revoke-device, add-device]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
---

# Settings ▸ Devices (Windows)

The devices that can sync with this server, how each was added, revoking access and adding a device. Behaviour and copy keys are the spec's [Settings ▸ Devices](../../../screens/settings-devices.md); the shell and patterns are in [settings](settings.md#card-patterns).

## Controls

Page title: breadcrumb "Settings > Devices".

| Spec element | Control | Notes |
| --- | --- | --- |
| Not connected | In the spec Devices is a section of Sync that is absent when not connected (open question C27); until this page is mapped to that, an accent `Button` `common.connectToServer` | |
| Loading | A card with a small indeterminate `ProgressBar` and `settings.devices.loading` (the page stays usable, so not a ring) | Replaced by the list |
| One section per device | One `SettingsCard` per device with access, in the server's order. `Header` the device's name; `Description` two `Caption` lines: `common.thisDevice` (this device only) and how and when it was added; trailing, for every other device, a `Button` `settings.devices.revoke` | Revoked devices are not listed. This device has no button. The card is one UI Automation element named "{name}, {this device}, {how added}"; its button is a child with its own name |
| How a device was added | `settings.devices.added.byDevice`, `settings.devices.added.pairingCode`, `settings.devices.added.setup`, `settings.devices.added.recoveryKey`, `settings.devices.added.accessPassword`, `settings.devices.added.recoveryCode`, `settings.devices.added.masterPassword`, `settings.devices.added.unknown` | Chosen by the spec's rules. {when} is the abbreviated date in the user's regional format (`DateTimeFormatter`, "day month.abbreviated year"); the spec's disambiguation (time, then the first eight characters of the identifier after " · ") applies unchanged |
| Revoke button label for Narrator | `AutomationProperties.Name` `settings.devices.revokeLabel`, with ", {how it was added}" appended when another device has the same name | The visible label is `settings.devices.revoke` |
| Error line | An `InfoBar` (Error) under the list: `settings.devices.error.load` or `common.couldntRevokeAccess`, `ActionButton` `common.tryAgain` (retries the revoke or reloads; disabled while busy) | |
| Access refused | In the spec the Devices section is absent and the Sync page's bar shows the sync state's message with `ActionButton` `common.reconnect` (open question C27); until this page is mapped, the same `InfoBar` here | Add device is not offered |
| The PC's name | A `TextBlock` in `CaptionTextBlockStyle`, secondary, under the list: a new sentence that says this PC shares its name, as the system reports it (D45), with the server and the person's other devices (new copy, D45) | The disclosure that goes with D45's default of sending the PC's name: a PC name can include a person's name or a work asset tag |
| Add Device… | An accent `Button` below the list, left-aligned, `settings.devices.add`, icon Add (E710) | Disabled while loading or busy. Opens [add-device](add-device.md); the list reloads when the dialog closes |

### Revoke confirmation

`ContentDialog`: `Title` `common.revokeAccessFor`; content `settings.devices.revoke.message`, preceded when another device has the same name by how this one was added and ". " (the spec's example); Primary `common.revokeAccess`; Close `common.cancel`; `DefaultButton` None ([Dialog patterns, 7](settings.md#dialog-patterns)). While it runs, the revoke button is disabled and the card shows a small indeterminate `ProgressBar`. `settings.devices.revoke.titleFallback` is not used: a Windows dialog does not blank its title while it closes.

On success the card leaves the list and focus moves to the next card, or to Add device when it was the last. The result is not announced (nothing was lost on screen that the person did not cause), apart from errors.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Cards in the column; the revoke button at the trailing edge | Mac Devices tab |
| Small and text size 200% or more | The revoke button moves under the two lines at full width; Add device full width | iPhone pushed pane |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `revoke-device` | Button in the device's card | — | Not this device; not while busy |
| `add-device` | Accent button below the list | — | Connected, loaded, not busy, access not refused |
| `devices-try-again` | Action button of the error bar | — | After an error; disabled while busy |
| `connect-to-server`, `sync-reconnect` | Card button; action of the access bar | as in commands.md | Not connected; access refused |

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
- Focus order: the list top to bottom, each card then its button, then the error bar, then Add device. After Try again focus stays on the button; after the confirmation closes it returns to the Revoke button, or to the next card when that one has left.
- Contrast themes and 225% text: card text wraps; the bar keeps its icon.

## Different by design

- **Cards, not a form.** Apple shows a section per device with a destructive button row. Windows shows a card per device with a trailing button that is not coloured red: the dialog that follows carries the warning ([platform.md, 8.1, rule 3](../platform.md#81-rules)).
- **No title fallback** (see above).

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D9 (device rename), D45 (device name a PC sends).
