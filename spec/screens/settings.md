---
id: settings
title: Settings
features: [settings, about-links, erase-device]
sources:
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Views/SettingsPresenter.swift
  - apps/apple/JournalApp/Views/JournalSidebarView.swift
  - apps/apple/JournalApp/Views/CompactJournalNavigation.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/SyncHealthOperations.swift
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/ios-delete-all-and-settings-2026-10-03.md
  - docs/design/erase-device-2026-10-04.md
  - docs/design/about-and-ratings-2026-10-05.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
---

# Settings

## Purpose

One place for everything that isn't writing: where new entries go, sync with its server and the devices on that server, encryption and passwords, App Lock, backups, agents, and (on phones and tablets) the project's pages and erasing this device.

## Entry points

- **Phone (stacked navigation):** a Settings button at the top left of the Journals screen (`open-settings`).
- **Tablet (three columns):** a Settings row at the end of the journals sidebar (`open-settings`). While the sidebar is in edit mode (reordering journals) the row stays visible but is dimmed and does nothing.
- **Computer:** the application menu's standard Settings… item and its standard shortcut (`open-settings`). Settings is a separate, standard settings window, not a sheet.
- From elsewhere, opening Settings at a given pane:
  - Sync Status ▸ Sync Settings… opens Settings at **Sync** (see `screens/sync-status`).
  - The computer's journal-window notice "Show Connection" (connecting) opens Settings at **Sync**, where the Connect to a Server sheet it brings to the front belongs.

## Content

### Phone and tablet

A sheet titled `settings.title`, with a confirming Done button (`common.done`) that closes it. Its content is a grouped list:

1. A section of five rows, in this order on every device, each opening a pane by pushing it, each with a leading icon:
   - `settings.pane.general` → `screens/settings-general`
   - `settings.pane.sync` → `screens/settings-sync` (which holds the devices: `screens/settings-devices`)
   - `settings.pane.privacy` → `screens/settings-privacy`
   - `settings.pane.backup` → `screens/settings-backup`
   - `settings.pane.agents` → `screens/settings-agent-access`
   The pushed pane's title is the row's name.
2. The About section → `screens/settings-about`.
3. A last section of its own with the destructive Erase Journals and Settings… action → `screens/settings-erase`.

### Computer

A standard settings window with a tab bar of five tabs, each with an icon, in the same order as the phone's rows; the window title is the selected tab's name:

1. `settings.pane.general`
2. `settings.pane.sync`
3. `settings.pane.privacy`
4. `settings.pane.backup`
5. `settings.pane.agents`

Each tab's content is a grouped form, 560 points wide. The window resizes to each tab's content, up to the screen's usable height (less room for the title bar and tabs); longer content scrolls. Every tab except General keeps a minimum height of 440 points so the sheets it presents fit inside the window. The Sync tab has one height, the smaller of 640 points and the room the screen allows, and scrolls inside it, because it gains and loses sections (Devices, Changed on Two Devices) as the connection changes and the device list arrives, and the window must not jump. A tab whose content fits doesn't rubber-band when scrolled.

There is no About section and no Done button: About is in the Help menu (`screens/settings-about`), and Erase Journals and Settings… is the last group of General (`screens/settings-general`).

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Open a pane | `settings-open-pane` | Pushes the pane (phone/tablet) or selects the tab (computer). |
| Done | `settings-done` | Closes the Settings sheet (phone/tablet only). |

## States

- **Locked** (App Lock on and My Journal locked): the whole of Settings shows only `settings.locked`, in secondary text. Locking while Settings is open closes the Settings sheet on phone and tablet (every window's presentations close when the app locks); on the computer the window shows the locked text.
- **Library problem** (the journals can't be opened, so there is no library to set up): the whole of Settings shows only `settings.libraryProblem`, in secondary text, in place of its panes, on every device ([screens/unavailable-content](unavailable-content.md)). Every sheet closes when a problem appears.
- **No library** (just after Erase Journals and Settings, while Settings closes): Privacy shows nothing; Settings then closes by itself.
- **Requested pane:** when another screen asks for a pane (Sync Status, Show Connection), Settings opens on that pane. On phone and tablet the pane is pushed on top of the list; on the computer that tab is selected.

## Rules

- The computer's settings window remembers the selected tab for the session. Its initial tab when the app starts is **Sync** (the model's default), not General. See [open-questions.md](../open-questions.md), A30.
- On the computer, Settings opens independently of the journal window; it can be open while no journal window is.
- After Erase Journals and Settings: on the computer, if no journal window is open, one opens (showing the first-launch screen) and the settings window closes; on phone and tablet the sheet closes and, about 0.6 seconds later, VoiceOver is told the screen changed so its focus moves to the first-launch screen.
- Settings never shows journal content while locked.

## Accessibility

- Each pane row and tab has a text label and an icon; the icon is decorative.
- The Settings button on the phone and the sidebar row are labelled `settings.title`.
- Panes are grouped forms with section headers read as headers.
- Escape (computer) closes sheets presented from Settings, never Settings itself.

## Platform notes (Apple)

- iPhone: Settings is a sheet over the Journals screen, opened from its top-left toolbar button.
- iPad: Settings is a sheet, opened from the sidebar's last row. On an iPad with a menu bar, the Help menu is also present.
- Mac: a standard Settings window (⌘,) with toolbar tabs, as in Apple's own apps. Labels use sentence case for controls inside forms on the Mac (for example "Default journal", "Format Markdown as you type", "Lock when inactive"), as macOS System Settings does; iPhone and iPad use title case. Copy keys carry `{"default": …, "mac": …}` variants for these.
- The first pane is **General** on every device. Erase Journals and Settings… is the last group of General on the Mac, whose window has no list level, and its own last section of the list on iPhone and iPad (the owner's decision after build 15: it is a function of its own, not part of a pane).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
