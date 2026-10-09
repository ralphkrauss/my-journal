---
id: encrypt-journals
title: Encrypt Your Journals (Windows)
spec: flows/encrypt-journals.md
features: [encrypt-existing-journals]
status: draft
---

# Encrypt Your Journals (Windows)

Windows never runs this flow. The spec's [flow](../../../flows/encrypt-journals.md) encrypts the journals of a library that an earlier version made without encryption, on the device and on its server. Windows has no such library: it never creates an unencrypted one, so nothing exists to migrate.

## Controls

Not applicable. There is no form, no working or unfinished notice, no Done sheet, no Not Now, no Stop Syncing for this purpose and no sign-in variant on Windows. The spec's steps (the free-space check, the access password, the encrypted copy, the server switch, Finish) are not built. The screen's mapping is [screens/encrypt-journals](../screens/encrypt-journals.md).

What Windows does instead:

| Situation | Windows |
| --- | --- |
| A new library | Created with a master password in one step ([create-library](create-library.md)) |
| Restoring an archive | Windows never reads the earlier directory archives that could be unencrypted, so a restore never produces an unencrypted library ([import-archive](import-archive.md)) |
| Connecting to a server whose recovery format is 3 or 4 (a library without encryption) | Refused with `messages.connection.encryptionOff`; nothing is changed on the PC or the server ([screens/connect-to-server](../screens/connect-to-server.md)) |

## Layout at each window width

Not applicable.

## Commands and shortcuts

None. The commands `turn-on-encryption`, `encrypt-journals`, `encrypt-journals-not-now`, `encrypt-journals-stop-syncing`, `encryption-finish`, `encryption-cancel` and `encryption-done` are not offered; [commands.md](../commands.md) has one row for each.

## Copy differences

None.

## Accessibility

Not applicable.

## Different by design

- **The flow does not exist on Windows.** Apple runs it for libraries made before 1.1 without encryption. Windows never creates such a library and never reads the earlier directory archives that could be unencrypted, so there is nothing to encrypt, and no machinery for pausing writing, keeping the PC awake or finishing after an interruption is needed.
- **No exits.** There is no form to leave, so there is no Not Now, no Stop Syncing for this purpose and no sign-in variant.
- **A server without encryption is refused** with `messages.connection.encryptionOff` rather than encrypted from the PC.

## Open questions

None.
