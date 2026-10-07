---
id: settings-general
title: Settings ▸ Writing (General on the computer)
features: [default-journal, markdown-as-you-type, erase-device]
sources:
  - apps/apple/JournalApp/Views/SettingsView.swift
  - apps/apple/JournalApp/Model/JournalNavigation.swift
  - apps/apple/JournalApp/Editor/MarkdownShortcuts.swift
  - docs/design/default-journal.md
  - docs/design/owner-decisions-2026-09-25.md
  - docs/design/erase-device-2026-10-04.md
---

# Settings ▸ Writing / General

## Purpose

Choose where new entries go when they're created outside a journal, and whether Markdown typed at the start of a line formats itself.

## Entry points

- Settings ▸ Writing (phone, tablet) or the General tab (computer). See `screens/settings`.

## Content

1. **Default journal section** (only when at least one journal exists):
   - A pop-up choice labelled `settings.general.defaultJournal` listing every journal in use, in the Journals list's order, by name; a journal without a name shows `common.untitledJournal`.
   - Footer: `settings.general.defaultJournal.footer`.
2. **Formatting section:**
   - A switch labelled `settings.general.formatAsYouType`, on by default.
   - Footer: `settings.general.formatAsYouType.footer`.
3. **Computer only:** the Erase Journals and Settings… group, last, in a group of its own (`screens/settings-erase`).

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Choose the default journal | `choose-default-journal` | Saved at once for this device. New Entry outside a journal (All Entries, Templates, Recently Deleted, Unavailable Journals, nothing selected, the phone's Journals screen) files the entry there. |
| Format Markdown as You Type | `toggle-format-as-you-type` | Saved at once for this device. When on, Markdown typed at the start of a line (such as “- ”, “1. ”, “# ” or “> ”, and the other markers the editor specification lists) becomes formatting; pressing Delete right after gives back exactly what was typed. When off, these are kept as typed. |

## States

- **No journals:** the default journal section isn't shown.
- **Saving the default journal failed:** the choice reverts and the app's general error alert (titled “Journal”, specified with the journal window) shows `messages.generic.defaultJournalFailed`.

## Rules

- The default journal is a per-device setting, never synced.
- Until a journal is chosen, or when the chosen journal is deleted or no longer in use, the default is the oldest journal in use (by creation date, then by identifier).
- The chosen journal is shown selected; a deleted choice silently falls back to the oldest journal.
- Format Markdown as You Type is a per-device preference, on by default. Erase Journals and Settings resets it to on.
- Both settings take effect immediately; there is no Save button.

## Accessibility

- The picker and switch are labelled by their text; the footers are read after them.
- Journal names in the picker are read as written.

## Platform notes (Apple)

- Mac labels are in sentence case: `settings.general.defaultJournal` → "Default journal", `settings.general.formatAsYouType` → "Format Markdown as you type". iPhone and iPad use title case.
- On the Mac, the tab is called General because Erase Journals and Settings… is its last group (as System Settings ▸ General ends with Transfer or Reset). On iPhone and iPad the pane is called Writing and Erase has its own last section in the Settings list.

## Open questions

- None.
