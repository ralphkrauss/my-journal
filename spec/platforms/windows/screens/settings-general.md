---
id: settings-general
title: Settings ▸ General (Windows)
spec: screens/settings-general.md
features: [default-journal, markdown-as-you-type, erase-device]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/combo-box
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/toggles
---

# Settings ▸ General (Windows)

The General page: where new entries go, Markdown as you type, and the Erase group. Behaviour and copy keys are the spec's [Writing / General](../../../screens/settings-general.md); the page shell and card patterns are in [settings](settings.md).

## Controls

Page title: breadcrumb "Settings > General" (`settings.title`, `settings.pane.general`).

| Spec element | Control | Notes |
| --- | --- | --- |
| Default journal section (only when a journal exists) | A [choice card](settings.md#card-patterns): `Header` `settings.general.defaultJournal`, `Description` `settings.general.defaultJournal.footer`, a `ComboBox` as content | Items are the journals in use, in the Journals list's order, by name (`common.untitledJournal` when blank). The selected item is the effective default: the chosen journal, or the oldest journal in use when none is chosen or the choice is gone. The combo box is as wide as its longest item, at most 320 epx, and the name trims with an ellipsis and a tooltip |
| Format Markdown as You Type | A switch card: `Header` `settings.general.formatAsYouType`, `Description` `settings.general.formatAsYouType.footer`, a `ToggleSwitch` | On by default. Saved when toggled |
| Erase group (last) | The group in [settings-erase](settings-erase.md), after a 24 epx gap and with no header of its own | Always the last group on the page |

States:

- **No journals:** the default journal card is not in the tree; Format Markdown is the first card.
- **Saving the default journal failed:** the `ComboBox` returns to the previous selection and the general error dialog shows `messages.generic.defaultJournalFailed` (a `ContentDialog` with that text, Close button `common.ok`, no title: [8.1, rule 3](../platform.md#81-rules)).
- **The list changes while the page is open** (a journal is added, renamed, deleted or reordered on another device): the items refresh and the selection follows the journal, not the position. Refreshing the items never counts as a choice and never writes the setting.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Cards in the column of [settings](settings.md); the combo box and switch sit at the trailing edge of their cards | Mac General tab |
| Small | The combo box and switch move under the card text at full width | iPhone Writing pane |
| Text size 200% or more | As small; the footers wrap | Accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `choose-default-journal` | Combo box in its card | as in commands.md | At least one journal in use |
| `toggle-format-as-you-type` | Switch in its card | as in commands.md | Always |
| `erase-device` | Erase group ([settings-erase](settings-erase.md)) | — | As in that file |

Keyboard: Tab reaches each control; in the combo box ↑ and ↓ change the choice and Alt+↓ opens the list; Space toggles the switch. Both settings take effect at once; there is no Save.

## Copy differences

Sentence case applies as in [platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary): "Default journal" (the Mac already has this variant for `settings.general.defaultJournal`) and "Format Markdown as you type". Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.general.formatAsYouType.footer` | Typing “- ”, “1. ”, “# ” or “> ” at the start of a line formats it. Press Delete right after to keep what you typed. | Typing “- ”, “1. ”, “# ” or “> ” at the start of a line formats it. Press Backspace right after to keep what you typed. | vocabulary (platform.md, 12.3) |

## Accessibility

- The combo box is named by its header and described by its footer; Narrator reads "Default journal, {name}, combo box". Journal names are read as written.
- The switch reads "Format Markdown as you type, On" and its footer as its description. Changing either is confirmed by the control's own state; nothing else is announced.
- Focus stays on the control that was changed. When the selection reverts after a failure, the error dialog's Close button returns focus to the combo box.

## Different by design

- **Home of the Erase group.** As on the Mac, Erase is the last group of this page, not a section of its own ([platform.md, 10](../platform.md#10-settings)).
- **The Mac's pop-up button** is a `ComboBox`, the Windows choice control.

## Open questions

None.
