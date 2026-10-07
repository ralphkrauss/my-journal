---
id: new-entry
title: New entry (Windows)
spec: flows/new-entry.md
features: [new-entry, new-blank-entry, new-entry-from-template, template-suggestion, journal-default-template, default-journal]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar
---

# New entry (Windows)

Starts writing: one New entry command everywhere, filed in a predictable journal, optionally from a template. Steps, rules and copy keys are the spec's [new-entry](../../../flows/new-entry.md); the window is [library-window](../screens/library-window.md).

## Controls

| Spec entry point | Windows control |
| --- | --- |
| New Entry button (Mac toolbar, iPhone and iPad bars) | The accent `AppBarButton` **New entry** (`library.menu.file.newEntry`, icon Add E710) at the end of the entry list header, label kept as the bar narrows and at every width, with a tooltip |
| File ▸ New Entry | File menu, `library.menu.file.newEntry`, Ctrl+N |
| File ▸ New Blank Entry | File menu, `library.menu.file.newBlankEntry`, Ctrl+Shift+N |
| File ▸ New Entry from Template… | File menu, `library.menu.file.newEntryFromTemplate`, no shortcut; opens the [template chooser](../screens/template-chooser.md) anchored to the New entry button |
| New Entry In ▸ and New Entry from Template on a template | The template's context menu and Entry actions ([templates](../screens/templates.md)) |
| "use a template" | The link in an empty entry's placeholder ([entry-editor](../screens/entry-editor.md)) |
| Empty list action | A `Button` under the empty text ([entry-list](../screens/entry-list.md)): `common.newJournalEllipsis` when there is no journal in use, otherwise `library.menu.file.newEntry` |

## Steps on Windows

The steps are the spec's, numbered as there:

1. **Which journal:** the one whose entries are shown; anywhere else (All Entries, Templates, Recently deleted, Unavailable journals, nothing selected, the small layout's Journals page) the Default Journal.
2. **No journal in use:** the New entry button opens the New journal dialog ([journals](../screens/journals.md)) and, once it is created, starts the entry there; File ▸ New entry is disabled. The two dialogs are never open together: the entry starts after the first dialog has closed.
3. **The open entry is saved first;** if that fails nothing is created and the failure follows [flows/save-failure](../../../flows/save-failure.md).
4. **Contents:** New entry uses the journal's default template, or is empty; New blank entry is always empty; from a template uses its current text.
5. **Where it shows:** the list switches to the target journal (closing what was open there) unless All Entries is shown, where the list stays and the entry shows its journal label. The search is cleared. The entry is dated now, appears at the top of its month, opens, and **its title gets keyboard focus with its text selected**. In the small layout the stack becomes Journals, the journal's list, the entry, so Back shows where it was filed.
6. Nothing is announced and no message appears; Narrator reads the focused title.

## Layout at each window width

| Width | What differs | Apple equivalent |
| --- | --- | --- |
| Large and medium | The New entry button in the list header; the entry opens in the editor pane | Mac toolbar over the editor; iPad list column |
| Small | The button is in the list page's header, with its label. From the Journals page it is not shown: the person opens a journal first, or uses the File menu in the More menu. The entry opens as the next page | iPhone bottom bar button that opens the Default Journal's list first |
| Text size | The button keeps its tooltip and name at 200% and more | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `new-entry` | File menu; list header button | as in commands.md | Not while locked or while the library is being replaced; the menu item also needs a journal in use |
| `new-blank-entry` | File menu | as in commands.md | As the menu item of `new-entry` |
| `new-entry-from-template` | File menu | none | As `new-entry`, and at least one template exists |
| `new-entry-in` | Template context menu | none | [templates](../screens/templates.md) |
| `use-a-template` | Placeholder link | none | The template suggestion is shown |
| `empty-new-entry` | Button in the empty list | as in commands.md | As `new-entry` |

The button is also disabled while an entry is being created. Choosing another collection or entry while one is being created cancels showing it; an entry already stored stays. An entry is kept once created, even if left empty, and never disappears on its own. New entry while Templates is shown creates an entry in the Default Journal with that journal's default template, not the selected one.

## Copy differences

Sentence case: "New entry", "New blank entry", "New entry from template…" ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)). No other differences.

## Accessibility

- Focus moves to the new entry's title; Narrator reads its name `editor.title.accessibilityLabel` and the empty value. Nothing else is announced, as in the spec.
- The New entry button has the name `library.menu.file.newEntry` and the accelerator key Ctrl+N.
- Errors use the general error dialog, announced by Narrator when it opens.

## Different by design

- **The button stays in the list header** instead of a bottom bar or the editor toolbar.
- **No journal on the stacked Journals page:** the Windows Journals page has no New entry button (iPhone has one that opens the Default Journal first); the File menu command and a journal's page cover it.
- **File ▸ New entry from template…** opens a flyout, not a sheet.

## Open questions

None.
