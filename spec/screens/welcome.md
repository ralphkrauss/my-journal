---
id: welcome
title: Welcome (first launch)
features: [create-library, connect-from-welcome, import-archive-from-welcome, launch-states]
sources:
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/JournalApp/JournalApp.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - docs/design/markdown-writing-revision.md
  - docs/guide/getting-started.md
---

# Welcome

## Purpose

The first screen on a device without a library. It offers three ways in: start a new library here (always encrypted, with a master password), join an existing one through a server, or start from a backup archive.

## Entry points

- First launch, when the device has no library.
- After **Erase Journals and Settings…** (screens/settings-*), which returns the device to this screen.

What the window shows at launch, in order of precedence (the same rule after every change of state):

1. Reading the configuration: a progress indicator with `library.app.loading`.
2. A library exists and is locked: the lock screen ([screens/lock-screen](lock-screen.md)).
3. The library can't be opened, or its settings can't be read, or a newer version wrote it, or it was made without encryption by version 1.0: the library problem screen ([screens/unavailable-content](unavailable-content.md)). An unreadable settings file is never treated as a first launch, and this screen never starts a new library over it.
4. No library: this screen.
5. A library from an early build whose recovery key isn't confirmed yet: screens/recovery-key.
6. Otherwise the library window (screens/library-window).

## Content

Centered column, scrolling when the text is large:

1. Decorative closed-book symbol (hidden from assistive technologies).
2. Large title: `library.welcome.title`.
3. Secondary text: `library.welcome.message`.
4. Primary action, large and prominent: `library.welcome.start`.
5. Secondary action, styled as a link in the accent color: `common.connectToServer`.
6. Plain action: `common.importArchive`.

## Actions

| Action | Result |
| --- | --- |
| `library.welcome.start` | Opens the create-library sheet: Choose a Master Password ([flows/create-library](../flows/create-library.md)). |
| `common.connectToServer` | Opens the connection sheet ([flows/connect-to-server](../flows/connect-to-server.md)). |
| `common.importArchive` (command `import-archive`) | Opens the system file picker limited to journal archives; the chosen archive opens the import sheet (Settings ▸ Backup, screens/settings-backup). |

Opening a `.journalarchive` file from the system (Files, Finder, Mail) while this screen shows also starts the import.

## States

- **Loading:** `library.app.loading` with a progress indicator, before anything else.
- **Error:** a failure while opening the settings no longer reaches this screen: it shows the library problem screen. An error from an action started here (Start a Journal, Connect to a Server, Import Archive…) shows the general error alert (`common.alertTitle`, message, `common.ok`).

## Rules

- Nothing is created until the person chooses an action; this screen writes nothing.
- The menu bar commands that need a library (New Entry, New Journal…, Export Archive…, Export Journals as Markdown…, Search Entries) are disabled here; Import Archive… stays enabled.

## Accessibility

- The symbol is decorative. Reading order: title, message, Start a Journal, Connect to a Server…, Import Archive….
- The column scrolls at the largest text sizes, so every action stays reachable.

## Platform notes (Apple)

- Identical on iPhone, iPad and Mac. On the Mac it fills the journal window (minimum 801 × 420 points).

## Open questions

- None.
