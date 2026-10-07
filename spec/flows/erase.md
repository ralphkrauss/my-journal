---
id: erase
title: Erase journals and settings
features: [erase-device]
sources:
  - apps/apple/JournalApp/Views/EraseSection.swift
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Model/EraseOperations.swift
  - apps/apple/JournalApp/Model/LocalErasure.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - docs/design/erase-device-2026-10-04.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---

# Erase journals and settings

## Purpose

Remove everything My Journal keeps on this device, as if it had just been installed, while warning clearly about anything that exists only here.

## Entry points

- `screens/settings-erase`.

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

## What is removed and what stays

- Removed: the library (journals, entries, templates, Recently Deleted, images, history), its keys, its server connection, App Lock and Lock when inactive, the default journal, the last-opened entry, earlier copies of the library, an unfinished encryption copy, leftovers of imports and exports, Format Markdown as You Type, and the rating request's usage.
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
