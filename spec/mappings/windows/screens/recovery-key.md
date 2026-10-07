---
id: recovery-key
title: Keep your recovery key, early libraries (Windows)
spec: screens/recovery-key.md
features: [legacy-recovery-key]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboardcontentoptions
---

# Keep your recovery key, early libraries (Windows)

Libraries made by early Apple versions were protected by a generated recovery key instead of a master password, and the window shows that key until the person confirms they saved it. The spec's [recovery-key](../../../screens/recovery-key.md) describes it. **Not offered on Windows.** `parity.yaml` already marks `legacy-recovery-key` not applicable: current versions create libraries with a master password or without encryption, and early libraries exist only on Apple devices. This file records what Windows does instead so nobody builds the screen by accident, and what to do if the owner decides otherwise (D11 in [open-questions.md](../../../open-questions.md)).

## Controls

Not applicable. The launch precedence of [welcome](welcome.md) skips this step: after the lock page and the first-launch page, the library window opens.

| Question | Windows answer |
| --- | --- |
| Can a Windows PC have a library with an unconfirmed generated recovery key? | Not through its own creation: [create-library](../flows/create-library.md) makes a master password or no encryption. It could arrive only by importing or restoring an archive from an early Apple build, and an archive restores the library with its password or recovery key, which the person already has |
| What if such a library does arrive? | The spec says restoring an archive makes the archive's library this device's library with the archive's password, which then counts as checked, so the unconfirmed state is not expected to arrive. If it did, Windows would need the screen after all: that is D11, and this file is the place to design it |
| Where would a key be copied or saved if the screen were ever added? | Copy through the clipboard options that keep it out of Windows clipboard history and cloud clipboard and clear it after two minutes ([15](../platform.md#15-clipboard)); save through the save picker as a text file named `settings.recoveryKey.filename`; failure shown as an error dialog titled `settings.recoveryKey.saveFailed` |

## Layout at each window width

Not applicable: no screen. A future version would be a page of the content area, at most 520 epx wide and centred, scrolling at large text sizes.

## Commands and shortcuts

Not applicable. `copy-recovery-key`, `save-recovery-key` and `confirm-recovery-key` are "Not offered" in [commands.md](../commands.md).

## Copy differences

Not applicable. The strings `settings.recoveryKey.*` are not shown on Windows.

## Accessibility

Not applicable.

## Different by design

- **The screen does not exist.** Early libraries are an Apple-only state ([parity.yaml](../../../parity.yaml)), and a Windows PC reaches such a library only through an archive that carries its own password or key.
- **If it were added**, the clipboard handling would follow [15](../platform.md#15-clipboard) (history and roaming off, cleared after two minutes), which is stricter than Apple's.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D11 (recovery key screen).
