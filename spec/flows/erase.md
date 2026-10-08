---
id: erase
title: Erase journals and settings
features: [erase-device, erase-unopened-library]
sources:
  - apps/apple/JournalApp/Views/EraseSection.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/UnopenedEraseButton.swift
  - apps/apple/JournalApp/Model/EraseOperations.swift
  - apps/apple/JournalApp/Model/LocalErasure.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - docs/design/erase-device-2026-10-04.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
  - docs/design/build-18-fixes-2026-10-06.md
---

# Erase journals and settings

## Purpose

Remove everything My Journal keeps on this device, as if it had just been installed, while warning clearly about anything that exists only here.

## Entry points

- `screens/settings-erase`.
- The library problem screen and the missing-device-key lock screen, when the journals can't be opened ([screens/unavailable-content](../screens/unavailable-content.md), [screens/lock-screen](../screens/lock-screen.md)): see Erasing journals that can't be opened.

## Steps

1. **Erase Journals and Settings…** The open entry is saved; the device counts what isn't on a server.
2. **Warning** (one of five):
   - **On server:** connected, the last sync succeeded, nothing waits. Journals stay on the server and come back on connecting again; the device will be signed out.
   - **Unsent:** connected, healthy, but {count} items haven't reached the server.
   - **Unconfirmed:** connected, but sync is failing, never completed, or needs sign-in.
   - **Not syncing:** not connected, with journals.
   - **Nothing written:** not connected, nothing written.
   The three cases that lose journals start with “Export an archive first…”, offer Export Archive…, and end with “You can’t undo this.”
3. **Export Archive…** (optional) opens the Export Archive sheet; the person can erase afterwards by choosing Erase Journals and Settings… again.
4. **Erase:**
   1. When App Lock is on, the device owner authenticates (`settings.erase.authReason` "Erase journals on this device"). Cancelled or failed: nothing happens.
   2. Writing and syncing pause; the open entry is saved again.
   3. The device counts again. If more would now be lost than the warning said (for example new unsent items, or sync started failing), nothing is erased and the warning appears again with the current case.
   4. **Commit:** the configuration is moved into a to-be-deleted folder in one step. If that fails: alert `settings.erase.failed.title` / `settings.erase.failed.message`; writing resumes; nothing was removed.
   5. The library's keys in the secure store are removed, then its files are moved into the to-be-deleted folder; preferences My Journal set (Format Markdown as You Type, the rating request's usage) are reset.
   6. Settings closes; the first-launch screen shows (on the computer, a journal window opens if none was open).
   7. In the background: the folder is deleted, and the server is asked to sign this device out (revoke its access) with the credential only this request still holds. Failures are ignored.
5. **Interrupted erase:** if the app stops after the commit, the next launch finishes deleting before reading anything; the current library's files and keys are never touched.

## Erasing journals that can't be opened

When the library can't be opened, nothing can be counted, exported or even read, so this variant reads nothing. It is the one way out for a person whose journals won't open and who has no archive, and it must work whatever state the files and the secure store are in.

1. **Erase Journals and Settings…** (`erase-unopened`), offered after one failed Try Again, or at once on the lock screen of a missing device key. Not offered for a newer version (update instead), and not while the phone's or tablet's protected data is unavailable.
2. When App Lock is on **or can't be known** (the settings couldn't be read), the device owner authenticates first (`settings.erase.authReason`). Cancelled or failed: nothing happens. A device without a passcode goes on.
3. **Warning** `settings.erase.alert.unopened`, with buttons `settings.erase.alert.erase` (destructive) and `common.cancel`. There is no Export Archive… button, because nothing can be exported. The message is built from `settings.erase.alert.unopened.reasonCantOpen` (or `.reasonNeedsKey` with the credential's name for a missing device key) and `settings.erase.alert.unopened.serverKnown` (the saved connection could be read and has an address) or `.serverUnknown` (every other case). It never says the journals will be lost or that the device isn't connected, because after restoring a device from a backup the connection is absent even though the library synced, and the warning must not discourage the right fix (erase, then connect).
4. **Erase** doesn't ask for authentication again. The settings file moves into the to-be-deleted folder as it is, even if it doesn't decode, and everything else the app stored goes by a list built first (the library folders and every other entry the app left in its data folder, every secure-store item of the app that can be listed, and its preferences). The server is signed out with the saved connection, read before the keys go, if there was one. Nothing else of this flow differs from steps 4.4 to 4.7 above.
5. **Failure** to start: alert `settings.erase.failed.title` / `settings.erase.failed.message`; nothing was removed.
6. The first-launch screen shows.

## What is removed and what stays

- Removed: everything the app stored, whatever could or couldn't be read: the library (journals, entries, templates, Recently Deleted, images, history), its keys, its server connection, App Lock and Lock when inactive, the default journal, the last-opened entry, earlier copies of the library, an unfinished encryption copy, leftovers of imports and exports, Format Markdown as You Type, and the rating request's usage.
- The secure-store sweep: both erase variants remove every secure-store item of the app that the platform can list, not only those the settings name, so keys orphaned by an earlier install don't stay behind. On the phone and tablet that is all of the app's items, because the data folder's path (and so the names derived from it) changes after a reinstall; on the computer only the items of this data folder and the earlier agent items, because development and preview copies share the team's key group. A listing that fails is logged and the erase goes on with the names it can derive.
- Stays: the server and everything on it, other devices, and (computer) the files of the server earlier versions ran on this computer (they may hold the only copy of other devices' changes; the footer says so).

## Rules

- Nothing is removed unless the commit succeeds; once it has, everything else follows, now or at the next launch.
- The person is never told less than what will be lost.
- The server isn't changed, apart from signing this device out.
- Every window closes what it showed of the journals while erasing.
- VoiceOver moves to the first-launch screen after Settings closes (phone/tablet).

## Accessibility

- The warning reads the action to take first.

## Platform notes (Apple)

- On the Mac, if no journal window is open when erasing finishes, one opens to show the first-launch screen.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
