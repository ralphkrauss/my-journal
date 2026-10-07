---
id: settings-erase
title: Erase Journals and Settings (section and alerts)
features: [erase-device]
sources:
  - apps/apple/JournalApp/Views/EraseSection.swift
  - apps/apple/JournalApp/Model/EraseOperations.swift
  - apps/apple/JournalApp/Model/LocalErasure.swift
  - apps/apple/JournalApp/Model/FormerMacServer.swift
  - docs/design/erase-device-2026-10-04.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---

# Erase Journals and Settings

## Purpose

Returns this device to a fresh install: removes its journals, settings and server connection. The server and other devices aren't changed (this device is only signed out). Flow: `flows/erase`.

## Entry points

- Phone/tablet: the last section of Settings, on its own.
- Computer: the last group of Settings ▸ General.

## Content

A section with:
- a destructive button `settings.erase.button` ("Erase Journals and Settings…"). On the computer it's drawn in red when enabled and in secondary colour when disabled (a computer form doesn't colour destructive buttons itself).
- Footer:
  - connected: `settings.erase.footerConnected`;
  - not connected: `settings.erase.footerLocal`;
  - computer only, when files of the server earlier versions ran on this computer remain: followed by a space and `settings.erase.footerFormerServer`.

### Warning alert

Title `settings.erase.alert.title` ("Erase Journals and Settings?"). Message, by what erasing would lose (`flows/erase`):

| Case | Message |
| --- | --- |
| Connected, syncing normally, nothing waiting | `settings.erase.alert.onServer` |
| Connected, items not on the server yet | `settings.erase.alert.unsent` (plural) |
| Connected, but the last sync failed or never completed | `settings.erase.alert.unconfirmed` |
| Not syncing, journals written | `settings.erase.alert.notSyncing` |
| Not syncing, nothing written | `settings.erase.alert.nothingWritten` |

Buttons, in order: `common.exportArchive` ("Export Archive…", only when journals would be lost), destructive `settings.erase.alert.erase` ("Erase"), `common.cancel`.

### Failure alert

Title `settings.erase.failed.title` ("Couldn’t Erase"), message `settings.erase.failed.message` ("Nothing was removed from this device. Try again."), button `common.ok`.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Erase Journals and Settings… | `erase-device` | A library exists; nothing else is changing it (connecting, importing, encrypting, Delete All running, a failed save, another erase); not while checking | Saves the open entry, counts what would be lost, shows the warning. |
| Export Archive… (alert) | `export-archive` | When journals would be lost | Closes the alert and opens the Export Archive sheet. |
| Erase | `erase-confirm` | — | Authenticates (App Lock on), then erases (`flows/erase`). |
| Cancel | — | — | Nothing. |

## States

- **Busy elsewhere:** the button is disabled.
- **Checking:** disabled until the warning appears.
- **More would be lost than the warning said:** the warning appears again with the current case.
- **Failed:** the failure alert; nothing was removed.
- **Locked:** the warning and the Export Archive sheet close; checking stops.
- **Erased:** Settings closes and the first-launch screen shows.

## Rules

- See `flows/erase`.

## Accessibility

- The button is announced as destructive. The warning's message starts with what to do when something would be lost.

## Platform notes (Apple)

- Placement follows each platform's own settings: iOS ends Settings ▸ General with Transfer or Reset iPhone; macOS ends System Settings ▸ General with Transfer or Reset.

## Open questions

- None.
