---
id: erase
title: Erase journals and settings (Windows)
spec: flows/erase.md
features: [erase-device]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.ui.userconsentverifier
---

# Erase journals and settings (Windows)

Removes everything My Journal keeps on this PC, as if it had just been installed, while warning clearly about anything that exists only here. The steps, the five warnings and the rules are the spec's [flow](../../../flows/erase.md); the card and dialogs are [settings-erase](../screens/settings-erase.md). Authentication is Windows Hello through [the gate](../screens/settings.md).

## Controls

| Spec step | Windows |
| --- | --- |
| 1 Erase journals and settings | The open entry is saved; the PC counts what is not on a server |
| 2 Warning | One of five dialogs; the three cases that lose journals start with "Export an archive first…", offer Export archive… (first and default) and end with "You can’t undo this." |
| 3 Export archive | Closes the warning, opens the export dialog; the person erases afterwards by choosing the Erase button again |
| 4.1 Authenticate | When App Lock is on, the dialog closes and Windows Hello is asked with `settings.erase.authReason`. Cancelled or failed: nothing happens. A PC without Hello continues |
| 4.2 Pause | Writing and syncing pause; the open entry is saved again |
| 4.3 Count again | If more would now be lost than the warning said, nothing is erased and the warning appears again |
| 4.4 Commit | The library's local folder contents and configuration are moved in one step, by renaming, into a new folder named for the purpose inside the app's local data folder. The rename is within one volume, so it is atomic or fails. Failure: `settings.erase.failed.title` with `settings.erase.failed.message`; writing resumes; nothing was removed |
| 4.5 Remove | See the list below |
| 4.6 Window | The library window shows the first-launch page; focus goes to its primary action |
| 4.7 Background | The to-be-deleted folder is deleted; the server is asked to sign this PC out (revoke its access) with the credential only this request still holds. Failures are ignored |
| 5 Interrupted erase | If the app stops after the commit, the next launch finishes deleting before reading anything; the current library's files and keys are never touched |

### What is removed on Windows

- **Removed:** the library (journals, entries, templates, Recently deleted, images, history) and its database with its write-ahead and shared-memory files (the database is closed before the rename); the configuration; the secrets file protected with the Windows Data Protection API (`ISecretStore`: the library's key and this PC's server credentials), by deleting it; App Lock and Lock when inactive; the default journal; the last open collection and entry; earlier copies of the library; an unfinished encryption copy; leftovers of imports and exports in the temporary folder; Format Markdown as you type; the rating request's usage; and the device-only window state in local settings: window position, size and maximised state, list width, Show editor only, zoom if stored.
- **Stays:** the server and everything on it; other devices; and files the person exported with the pickers (archives, Markdown folders, saved images), wherever they were saved, including OneDrive folders. Erase says nothing about them because the app does not track them; the spec's wording applies.
- **Not applicable:** files of the server earlier Mac versions ran (no such server exists on Windows), and the Mac's former-server footer.
- **Not touched:** the app's package itself, the Store entitlement and anything the Windows jump list holds (it holds only the New entry task, never journal names, [platform.md, 19](../platform.md#19-single-instance-and-activation)).

### Windows details

- **Files in use.** Antivirus, the search indexer or a backup tool may hold a file open and block deleting it. Moving the folder by rename is not blocked by a reader, and the background delete retries with a short back-off while the app runs and again at the next launch, in the first-launch state, so a locked file never shows journal content again. If the commit rename itself fails because a file is locked, the failure dialog shows and nothing was removed; trying again later normally works.
- **Windows Hello and the window.** The dialog is hidden before the prompt, and the inactivity timer is held while the prompt is in front ([app-lock](app-lock.md)).
- **After the erase** the app is as installed: no App Lock, so the first-launch page shows without a lock; the capture setting (D28) returns to its default.
- **No Credential Locker or registry entries are used** by the app, so there is nothing else to remove ([platform.md, 14](../platform.md#14-secure-storage)).

## Layout at each window width

Not applicable: the dialogs follow [settings-erase](../screens/settings-erase.md).

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `erase-device` | The button in the action card in General | — | A library exists and nothing else is changing it |
| `export-archive` | Warning dialog | — | Journals would be lost |
| `erase-confirm` | Warning dialog | none | Always in the dialog. No default button when nothing would be lost; when journals would be lost Export archive… is the default and Erase is the secondary button (D44) |

## Copy differences

As [settings-erase](../screens/settings-erase.md). The warnings keep the spec's words ("Export an archive first…" is the instruction before the loss); only the Mac-only footer is dropped.

## Accessibility

- The warning reads the action to take first. Focus after Windows Hello or the failure dialog returns to the Erase button; after the erase, to the first-launch page. Nothing announces the erase besides the page change.

## Different by design

- **The folder rename** replaces the Apple "move into a to-be-deleted folder": same atomic commit, using what Windows guarantees.
- **Device-only window state** is part of what is erased; Apple has no equivalent.
- **Exports are not tracked** and so are not mentioned; on Windows, they may be in a synced folder.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D44 (Erase warning buttons).
