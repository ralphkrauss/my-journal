---
id: encrypt-journals
title: Encrypt Your Journals (Windows)
spec: screens/encrypt-journals.md
features: [encrypt-existing-journals]
status: draft
---

# Encrypt Your Journals (Windows)

Windows never shows this screen. Behaviour and copy keys are the spec's [Encrypt Your Journals](../../../screens/encrypt-journals.md), which exists for libraries that earlier versions made without encryption. Windows has none of those libraries; the reasons and what it does instead are in [flows/encrypt-journals](../flows/encrypt-journals.md).

## Controls

Not applicable. The form, the working and unfinished notices, the Done sheet and the exits (Not Now, Cancel, Stop Syncing…) are not built on Windows, because no library on Windows can be unencrypted. `encrypt-existing-journals` is `not-applicable` for Windows in [parity.yaml](../../../parity.yaml). Settings ▸ Privacy never offers Turn On Encryption… ([settings-privacy](settings-privacy.md)).

## Layout at each window width

Not applicable: there is no screen.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `turn-on-encryption` | Not offered | — | No unencrypted library exists on Windows |
| `encrypt-journals` | Not offered | — | As above |
| `encrypt-journals-not-now` | Not offered | — | As above |
| `encrypt-journals-stop-syncing` | Not offered | — | As above |
| `encryption-finish` | Not offered | — | As above |
| `encryption-cancel` | Not offered | — | As above |
| `encryption-done` | Not offered | — | As above |

## Copy differences

None. None of the screen's copy keys is shown on Windows.

## Accessibility

Not applicable: there is no screen.

## Different by design

- **The screen does not exist on Windows.** Apple shows it at launch, and from Settings ▸ Privacy ▸ Turn On Encryption…, to libraries made before 1.1 without encryption and to unencrypted archives restored onto a device with no journals. Windows has no earlier unencrypted libraries to migrate. It never creates an unencrypted library, and it never reads the earlier directory archives that could be unencrypted. So it has no form, no Not Now, no Stop Syncing for this purpose and no sign-in variant.
- **A server whose recovery format is 3 or 4 is refused** with `messages.connection.encryptionOff`, shown where the connection fails ([screens/connect-to-server](connect-to-server.md)).

## Open questions

None.
