---
id: recovery-key
title: Keep Your Recovery Key (early libraries)
features: [legacy-recovery-key]
sources:
  - apps/apple/JournalApp/Views/RecoveryView.swift
  - apps/apple/JournalApp/Views/ExportView.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/SensitivePasteboard.swift
---

# Keep Your Recovery Key

## Purpose

Libraries created by early versions were protected by a generated recovery key instead of a master password. Until the person confirms they saved it, the window shows the key instead of the journals.

## Entry points

- The journal window, when the library is open and unlocked and has a generated recovery key that hasn't been confirmed. The window decides what to show in this order: opening progress, the lock screen, the library problem screen, the first-launch screen, the encryption notice or Encrypt Your Journals, this screen, the journals (`screens/welcome`). Current versions create libraries with a master password, so new libraries never show this.

## Content

Scrolling, at most 520 points wide, centred:
1. Heading `settings.recoveryKey.title` ("Keep Your Recovery Key").
2. `settings.recoveryKey.warning`.
3. The key in monospaced type on a tinted background, selectable.
4. Button `settings.recoveryKey.copy` ("Copy Recovery Key").
5. Button `settings.recoveryKey.save` ("Save Recovery Key…"), which opens the system's save dialog for a plain-text file named `settings.recoveryKey.filename` ("Journal Recovery Key.txt") containing the key and a line break.
6. After copying: `settings.recoveryKey.copiedNote` ("The copied key is removed from the clipboard after 2 minutes."), in secondary text.
7. `settings.recoveryKey.notBackup` in secondary text.
8. A switch `settings.recoveryKey.saved` ("I’ve saved my recovery key").
9. A text field with placeholder `settings.recoveryKey.confirmField` ("Enter the last group to confirm").
10. A prominent button `common.continue`.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Copy Recovery Key | `copy-recovery-key` | Copies the key; it is removed from the clipboard after two minutes; the first copy announces the note. |
| Save Recovery Key… | `save-recovery-key` | Saves the key as a text file. A failure shows the alert `settings.recoveryKey.saveFailed` ("Couldn’t Save Recovery Key") with the system's message and `common.ok`. |
| Continue | `confirm-recovery-key` | Enabled when the switch is on and the field, with leading and trailing spaces and line breaks ignored, equals the key's last group (after the last “-”; case matters). Records the confirmation and shows the journals. |

## States

- **Couldn't record the confirmation:** the app's error alert shows the error's message.

## Rules

- The copied key is marked sensitive and cleared from the clipboard after two minutes.
- The confirmation is stored with the library.
- While the key is unconfirmed, each time the library is opened and unlocked the app creates a new recovery key and shows that one: a key shown, copied or saved earlier stops working. Only the key confirmed here is valid.
- The field has no automatic capitalisation or correction.

## Accessibility

- The note about the clipboard is announced on the first copy.

## Platform notes (Apple)

- None.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
